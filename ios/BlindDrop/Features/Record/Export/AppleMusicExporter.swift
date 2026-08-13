import Foundation
import MusicKit

enum AppleMusicAuthorization: Sendable, Equatable {
    case authorized
    case denied
}

@MainActor
protocol AppleMusicProviding: AnyObject {
    func requestAuthorization() async -> AppleMusicAuthorization
    func hasSubscription() async throws -> Bool
    func createPlaylist(name: String, appleMusicIDs: [String]) async throws -> URL?
}

/// The app's only MusicKit implementation. Catalog songs are restored to the exact order the
/// Record endpoint supplied before the new library playlist is created.
@MainActor
final class SystemAppleMusicProvider: AppleMusicProviding {
    func requestAuthorization() async -> AppleMusicAuthorization {
        await MusicAuthorization.request() == .authorized ? .authorized : .denied
    }

    func hasSubscription() async throws -> Bool {
        try await MusicSubscription.current.canPlayCatalogContent
    }

    func createPlaylist(name: String, appleMusicIDs: [String]) async throws -> URL? {
        var songsByID: [String: Song] = [:]
        for batch in Self.batches(appleMusicIDs, size: 25) {
            let ids = batch.map { MusicItemID($0) }
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
            request.limit = ids.count
            let response = try await request.response()
            for song in response.items { songsByID[song.id.rawValue] = song }
        }
        let ordered = appleMusicIDs.compactMap { songsByID[$0] }
        let playlist = try await MusicLibrary.shared.createPlaylist(name: name, items: ordered)
        return playlist.url
    }

    private static func batches(_ values: [String], size: Int) -> [[String]] {
        stride(from: 0, to: values.count, by: size).map { start in
            Array(values[start..<min(start + size, values.count)])
        }
    }
}

@MainActor
final class AppleMusicExporter {
    private let music: any AppleMusicProviding

    init(music: any AppleMusicProviding = SystemAppleMusicProvider()) {
        self.music = music
    }

    func export(_ payload: ExportDTO) async throws -> PlaylistExportResult {
        guard await music.requestAuthorization() == .authorized else {
            throw PlaylistExportError.denied
        }
        let hasSubscription: Bool
        do {
            hasSubscription = try await music.hasSubscription()
        } catch {
            // A MusicKit/network failure says nothing about the person's subscription. Do not
            // turn a transient provider error into the actionable-but-false "no subscription"
            // message.
            throw PlaylistExportError.failed
        }
        guard hasSubscription else {
            throw PlaylistExportError.noSubscription
        }
        do {
            let ids = payload.tracks.compactMap(\.appleMusicID)
            let url = try await music.createPlaylist(name: payload.playlistName, appleMusicIDs: ids)
            return PlaylistExportResult(
                service: .appleMusic,
                url: url,
                unresolvedCount: payload.unresolvedCount
            )
        } catch {
            throw PlaylistExportError.failed
        }
    }
}
