import SwiftUI
import Testing
@testable import BlindDrop

/// A recent Ear count, a separate all-time Accuracy bar, and a Readability spectrum.
/// Thin history keeps its sample count; unavailable rates never draw a zero or a meter.
@MainActor
@Suite struct MemberProfileSnapshotTests {

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func anotherMemberWithHistory(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let fixture = try profile("member")
        verify(named: "Profile-member", device, size) {
            MemberProfileContent(profile: fixture, isOwnProfile: false)
        }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func yourThinHistory(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let fixture = try profile("thin")
        verify(named: "Profile-own-thin", device, size) {
            MemberProfileContent(profile: fixture, isOwnProfile: true)
        }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func noHistory(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let fixture = try profile("empty")
        verify(named: "Profile-empty", device, size) {
            MemberProfileContent(profile: fixture, isOwnProfile: true)
        }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        SnapshotRenderer.verify(
            SnapshotRenderer.image(of: content(), device: device, typeSize: size),
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Profile",
            sourceLocation: sourceLocation
        )
    }

    private func profile(_ kind: String) throws -> MemberProfileDTO {
        // Accuracy has its own all-time scope. Ear always names the circle's real window.
        let rates = kind == "empty"
            ? "\"ear_reads\":0,\"ear_window_rounds\":14,"
              + "\"ear\":{\"value\":null,\"samples\":0},\"readability\":{\"value\":null,\"samples\":0}"
            : kind == "thin"
            ? "\"ear_reads\":4,\"ear_window_rounds\":2,"
              + "\"ear\":{\"value\":1,\"samples\":2},\"readability\":{\"value\":0,\"samples\":2}"
            : "\"ear_reads\":42,\"ear_window_rounds\":14,"
              + "\"ear\":{\"value\":0.71,\"samples\":14},\"readability\":{\"value\":0.43,\"samples\":14}"
        let comparisons = kind == "thin"
            ? "\"you_read_them\":null,\"they_read_you\":null"
            : "\"you_read_them\":{\"correct\":8,\"possible\":14},\"they_read_you\":{\"correct\":5,\"possible\":14}"
        let tracks = kind == "thin" ? "" : """
          ,{"local_date":"2026-08-10","track":\(track("am:1440818664", "Redbone", "Childish Gambino"))}
          ,{"local_date":"2026-08-09","track":\(track("am:1440765580", "Motion Sickness", "Phoebe Bridgers"))}
        """
        let recentTracks = kind == "empty" ? "" : """
          {"local_date":"2026-08-11","track":\(track("am:1452874255", "SZA", "Kendrick Lamar"))}\(tracks)
        """
        let json = """
        {
          "member":{"user_id":"u_ben","display_name":"Ben","role":"member"},
          \(rates),
          "drop_count":\(kind == "empty" ? 0 : kind == "thin" ? 2 : 14),
          "recent_tracks":[\(recentTracks)],
          \(comparisons)
        }
        """
        return try JSONDecoder().decode(MemberProfileDTO.self, from: Data(json.utf8))
    }

    private func track(_ key: String, _ title: String, _ artist: String) -> String {
        """
        {"track_key":"\(key)","isrc":null,"title":"\(title)","artist":"\(artist)","album":"Album","artwork_url":null,"artwork_bg_color":"#c9c4bc","duration_ms":240000,"preview_url":null,"apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":null,"spotify_url":null}
        """
    }
}
