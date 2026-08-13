import Foundation

struct PlaylistExportResult: Sendable, Equatable {
    let service: TrackService
    let url: URL?
    let unresolvedCount: Int
}

enum PlaylistExportError: Error, Equatable {
    case denied
    case noSubscription
    case failed
}

private struct SpotifyCreatePlaylistBody: Encodable {
    let name: String
    let `public`: Bool
}

private struct SpotifyAddItemsBody: Encodable {
    let uris: [String]
}

private struct SpotifyPlaylistResponse: Decodable {
    let id: String
    let externalURLs: [String: URL]

    enum CodingKeys: String, CodingKey {
        case id
        case externalURLs = "external_urls"
    }
}

/// Creates a fresh private playlist and appends the Record in 100-item batches, preserving the
/// server's newest-first order (`docs/06` §6). Uses Spotify's current February 2026 endpoints.
@MainActor
final class SpotifyExporter {
    static let batchSize = 100

    private let auth: any SpotifyAuthorizing
    private let apiBaseURL: URL

    init(
        auth: any SpotifyAuthorizing,
        apiBaseURL: URL = URL(string: "https://api.spotify.com/v1")!
    ) {
        self.auth = auth
        self.apiBaseURL = apiBaseURL
    }

    func export(_ payload: ExportDTO) async throws -> PlaylistExportResult {
        let playlist = try await createPlaylist(named: payload.playlistName)
        let uris = payload.tracks.compactMap(\.spotifyURI)
        for batch in Self.batches(uris) {
            try await add(batch, to: playlist.id)
        }
        return PlaylistExportResult(
            service: .spotify,
            url: playlist.externalURLs["spotify"],
            unresolvedCount: payload.unresolvedCount
        )
    }

    static func batches(_ uris: [String]) -> [[String]] {
        stride(from: 0, to: uris.count, by: batchSize).map { start in
            Array(uris[start..<min(start + batchSize, uris.count)])
        }
    }

    private func createPlaylist(named name: String) async throws -> SpotifyPlaylistResponse {
        var request = URLRequest(url: apiBaseURL.appending(path: "me/playlists"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpotifyCreatePlaylistBody(name: name, public: false))
        let (data, response) = try await auth.data(for: request)
        guard (200..<300).contains(response.statusCode),
              let playlist = try? JSONDecoder().decode(SpotifyPlaylistResponse.self, from: data)
        else { throw PlaylistExportError.failed }
        return playlist
    }

    private func add(_ uris: [String], to playlistID: String) async throws {
        let encodedID = playlistID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? playlistID
        var request = URLRequest(
            url: apiBaseURL.appending(path: "playlists/\(encodedID)/items")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpotifyAddItemsBody(uris: uris))
        let (_, response) = try await auth.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw PlaylistExportError.failed }
    }
}
