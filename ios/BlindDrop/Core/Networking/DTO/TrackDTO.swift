import Foundation

/// The single track shape used everywhere in `docs/04`, and verbatim the shape of
/// `submissions.track_meta` (`docs/06` §2).
///
/// Four fields are optional and each one is a real case rather than defensiveness: a track
/// with no ISRC keys as `am:` and can never have a Spotify link; a track with no preview
/// renders with **no play control** — not a disabled one (`docs/06` §7); and `spotify*` may
/// simply not have resolved yet, in which case the *Open in Spotify* button is absent.
struct TrackDTO: Decodable, Sendable, Equatable, Identifiable {
    /// `isrc:…` or `am:…` — the dedupe identity (`docs/06` §3). Also the stable id for a card
    /// in a list, which is why this type is `Identifiable` on it rather than on a UUID.
    let trackKey: String
    let isrc: String?
    let title: String
    let artist: String
    let album: String
    /// Apple's literal `{w}x{h}` **template**, never a resolved size. `ArtworkView` (E08-04)
    /// substitutes the size it needs at the display scale (`docs/06` §2.1); freezing one size
    /// here would cost the app the other three.
    let artworkURL: String?
    /// Apple's extracted dominant colour, used for exactly one thing: the placeholder fill
    /// behind artwork while it loads, at 12%. Never an accent, never a gradient (`docs/06` §2.1).
    let artworkBackgroundColor: String?
    let durationMilliseconds: Int
    let previewURL: URL?
    let appleMusicID: String
    let appleMusicURL: URL
    let spotifyID: String?
    let spotifyURL: URL?

    var id: String { trackKey }

    enum CodingKeys: String, CodingKey {
        case trackKey = "track_key"
        case isrc, title, artist, album
        case artworkURL = "artwork_url"
        case artworkBackgroundColor = "artwork_bg_color"
        case durationMilliseconds = "duration_ms"
        case previewURL = "preview_url"
        case appleMusicID = "apple_music_id"
        case appleMusicURL = "apple_music_url"
        case spotifyID = "spotify_id"
        case spotifyURL = "spotify_url"
    }
}

/// `GET /tracks/search` — `{ "results": [Track] }` (`docs/04` §6).
struct SearchResultsDTO: Decodable, Sendable, Equatable {
    let results: [TrackDTO]
}
