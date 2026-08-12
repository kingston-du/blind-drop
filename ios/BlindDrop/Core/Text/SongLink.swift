import Foundation

/// A pasted string → the field the contract wants it in, or `nil` if it is not a song link at all
/// (`docs/04` §6, `docs/06` §4).
///
/// The server parses the same three forms in `_shared/music/identity.ts`, and it is the
/// authority: this type does not decide whether a song exists, and it never will. What it decides
/// is **which of the copy deck's two paste errors the user sees**, and that needs a client-side
/// answer:
///
/// - a string that is not a link at all is `resolve.error.badlink` — *"That's not a song link."* —
///   and it is answered without a request, because there is nothing to ask;
/// - a link the server cannot find in the Apple catalog is `resolve.error.notfound` —
///   *"That song isn't in the Apple catalog. Search for it instead."*
///
/// Both arrive from the server as one `INVALID_INPUT`, so without this the app would have to show
/// one string for two different situations and would pick the wrong one half the time.
///
/// The three shapes are the ones `docs/06` §4 lists and nothing else. A URL this type rejects
/// never becomes a request.
enum SongLink: Equatable, Sendable {

    /// Every URL form. Sent in `spotify_url`, which is the field the server runs its full link
    /// parser over — *"the field is where people paste **a link**, and half of them will paste an
    /// Apple one"* (`_shared/music/resolve.ts`). Naming the field after one service is the wire's
    /// choice, not this app's.
    case link(String)
    /// A bare ISRC, which has no scheme and no host and so is its own field.
    case isrc(String)

    /// The submission body for this link (`docs/04` §4, §6). One field, always exactly one — the
    /// server answers `INVALID_INPUT` for zero or two.
    var input: SubmissionInput {
        switch self {
        case let .link(raw): .spotifyURL(raw)
        case let .isrc(isrc): .isrc(isrc)
        }
    }

    /// Parses a pasted string, or returns `nil` for something that is not a song link.
    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A bare ISRC first: it is the one form with no scheme, so it cannot be confused with a
        // URL, and trying to parse it as one would produce a relative URL with no host.
        if let isrc = Self.isrc(from: trimmed) {
            self = .isrc(isrc)
            return
        }

        // `spotify:track:{id}` — what the desktop app's "Copy Spotify URI" produces.
        if trimmed.lowercased().hasPrefix("spotify:track:") {
            let id = trimmed.dropFirst("spotify:track:".count)
            guard !id.isEmpty, id.allSatisfy(\.isAlphanumeric) else { return nil }
            self = .link(trimmed)
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(),
              Self.hosts.contains(host)
        else { return nil }
        self = .link(trimmed)
    }

    /// The hosts a song link can be on. The same allowlist the server keeps, and for the same
    /// reason: a string that is not on it never becomes a request (`docs/14` §7).
    static let hosts: Set<String> = [
        "open.spotify.com", "play.spotify.com",
        "music.apple.com", "geo.music.apple.com",
    ]

    /// An ISRC, normalised: twelve characters, uppercased, hyphens stripped (`docs/06` §3).
    ///
    /// The shape is two letters of country, three of registrant, two digits of year, five of
    /// designation. Checked here rather than sent hopefully, because *"CAN SOMEBODY FIND MY
    /// SONG"* is twelve characters too.
    static func isrc(from raw: String) -> String? {
        let compact = raw
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard compact.count == 12 else { return nil }
        let characters = Array(compact)
        guard characters[0...1].allSatisfy(\.isLetter),
              characters[2...4].allSatisfy({ $0.isLetter || $0.isNumber }),
              characters[5...11].allSatisfy(\.isNumber)
        else { return nil }
        return compact
    }
}

private extension Character {
    /// ASCII alphanumeric — a Spotify id's alphabet. `isLetter` alone would accept a Cyrillic
    /// lookalike, which is exactly the string an id must not be built from.
    var isAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
}
