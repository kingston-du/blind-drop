import Foundation

/// One song in the archive, with whose it was (`docs/04` §5).
struct RecordEntryDTO: Decodable, Sendable, Equatable, Identifiable {
    let userID: String
    let displayName: String
    let track: TrackDTO

    /// Unique within a night: one person drops one song a night, and the same person's name
    /// appears on a different day under a different `id` because the day is part of the key.
    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case track
    }
}

/// One night in the archive. `roundID` is here so the screen can link straight into that
/// night's results (`docs/11` `record.results`) without a second lookup.
struct RecordDayDTO: Decodable, Sendable, Equatable, Identifiable {
    let localDate: String
    let roundID: String
    /// The cue that steered this night's drops, when there was one (`docs/18-CUES.md` §8).
    /// `nil` for every night before the feature shipped and for uncued nights after it.
    let cue: CueDTO?
    let entries: [RecordEntryDTO]

    var id: String { roundID }

    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case roundID = "round_id"
        case cue
        case entries
    }
}

/// `GET /groups/current/record` — the archive, newest night first (`docs/04` §5).
///
/// Only `scored` nights are ever in it: tonight's round is not an archive entry, and a
/// `voided` night never becomes one — its songs went back to their owners unseen, and
/// publishing them the next morning would retroactively break the window they were sealed
/// inside. The client does not filter for that; the server cannot see the other states.
///
/// `nextCursor` is `nil` on the last page. An absent cursor is the end of the archive, not an
/// error, and the paging stops when it sees one.
struct RecordDTO: Decodable, Sendable, Equatable {
    let days: [RecordDayDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case days
        case nextCursor = "next_cursor"
    }
}

/// Which service an export is for. The value is the `?service=` the server takes.
enum ExportService: String, Sendable, CaseIterable {
    case spotify
    case apple
}

/// One track in an export, in the shape a playlist call needs and no other (`docs/06` §6).
///
/// Deliberately not a `TrackDTO`: artwork, previews and durations are what The Record renders,
/// and none of them takes part in creating a playlist. `isrc`, `title` and `artist` are here so
/// a failed add can be reported as a song rather than as an identifier.
struct ExportTrackDTO: Decodable, Sendable, Equatable, Identifiable {
    let spotifyURI: String?
    let appleMusicID: String?
    let isrc: String?
    let title: String
    let artist: String

    var id: String { spotifyURI ?? appleMusicID ?? "\(title)-\(artist)" }

    enum CodingKeys: String, CodingKey {
        case spotifyURI = "spotify_uri"
        case appleMusicID = "apple_music_id"
        case isrc, title, artist
    }
}

/// `GET /groups/current/record/export` — the ordered list, and nothing else (`docs/04` §5).
///
/// **The server never creates the playlist and never holds a Spotify or Apple Music
/// credential.** The client does it with the user's own token (`docs/06` §6), which is why
/// this type is the end of the server's involvement.
///
/// `unresolvedCount` is the number of archive tracks with no id for the requested service.
/// They are skipped from `tracks` and **stated** — *"3 songs aren't on Spotify. The rest are
/// in."* (`docs/11` `record.export.partial`). Never silently dropped.
struct ExportDTO: Decodable, Sendable, Equatable {
    let playlistName: String
    let tracks: [ExportTrackDTO]
    let unresolvedCount: Int

    enum CodingKeys: String, CodingKey {
        case playlistName = "playlist_name"
        case tracks
        case unresolvedCount = "unresolved_count"
    }
}
