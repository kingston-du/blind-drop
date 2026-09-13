import Foundation

/// `blinddrop://` parsing — `docs/05` §5. Four routes, and only four.
///
/// Parsing is total: an unknown URL is `nil`, never a crash and never a silent fallback to
/// the round. A link we do not recognise must do nothing visible rather than guess.
///
/// The APNs payload carries the same strings (`docs/05` §4 puts `"deep_link"` alongside
/// `aps`), so `PushRouter` (E12) parses through this same type rather than inventing a second
/// grammar.
///
/// The invite universal link `https://blinddrop.app/j/<CODE>` (`docs/05` §5) arrives through
/// `.onContinueUserActivity` rather than `.onOpenURL`, and is parsed here too (E09-04) — it is
/// the same destination reached by a different door, and two parsers would be two chances to
/// disagree about what a code is.
///
/// **A circle prefix, since `E19-01`.** `blinddrop://circle/<GROUP_ID>/round/current` names
/// which circle the round belongs to; the bare `blinddrop://round/current` still means "the
/// active one", so every link `docs/05` shipped before this slice still resolves exactly as it
/// did. `docs/01` ADR-011 is why a route needs this at all — a round, its results, and The
/// Record are each scoped to one circle now, and a link written before the caller held more
/// than one cannot assume which. `.join` never takes a circle: joining is how you get one, not
/// a thing that already has one.
enum DeepLink: Equatable, Sendable {
    /// `blinddrop://round/current`, or `blinddrop://circle/<id>/round/current` — today's round,
    /// phase-appropriate screen. `groupID` is `nil` for "the active circle".
    case round(groupID: String?)
    /// `blinddrop://round/current/results`, or with a circle prefix — results for today's round.
    case results(groupID: String?)
    /// `blinddrop://record`, or with a circle prefix — The Record.
    case record(groupID: String?)
    /// `blinddrop://join/<CODE>` — join flow, code prefilled. Never circle-prefixed.
    case join(code: String)
    /// `blinddrop://invite/<UUID>` — a direct, pending invitation for an existing account.
    case invitation(id: String)

    /// The circle a link names, or `nil` for "the active one" — `.join` never has one
    /// (`E19-03`). What `Router.resolvePendingCircle(against:)` reads to decide whether a
    /// pending link needs a switch before it can be applied.
    var groupID: String? {
        switch self {
        case let .round(groupID), let .results(groupID), let .record(groupID): groupID
        case .join, .invitation: nil
        }
    }

    init?(_ url: URL) {
        var parts: [String]

        switch url.scheme {
        case Self.scheme:
            // `blinddrop://record` puts "record" in `host` and leaves `path` empty, while
            // `blinddrop://round/current` puts "round" in `host` and "current" in the path.
            // Both shapes are normalised into one list so the routes match as written in
            // docs/05 §5 rather than as two special cases.
            parts = []
            if let host = url.host(percentEncoded: false), !host.isEmpty { parts.append(host) }
            parts += url.pathComponents.filter { $0 != "/" }

        case "https":
            // The one web surface (`docs/16` §3): `https://blinddrop.app/j/<CODE>`. **Only**
            // that host and only that path — an `applinks` entitlement hands the app every URL
            // on the domain, and a link this type does not recognise must open in Safari rather
            // than be guessed at. It is rewritten into the `join` shape so there is exactly one
            // place a code is parsed.
            guard url.host(percentEncoded: false) == Self.inviteHost else { return nil }
            let path = url.pathComponents.filter { $0 != "/" }
            guard path.count == 2 else { return nil }
            switch path[0] {
            case Self.invitePath: parts = ["join", path[1]]
            case Self.directInvitePath: parts = ["invite", path[1]]
            default: return nil
            }

        default:
            return nil
        }

        // A circle prefix names which circle the rest of the link belongs to. Stripped here so
        // every route below is matched exactly as `docs/05` §5 writes it, with the id carried
        // separately rather than folded into a wider set of path shapes.
        var groupID: String?
        if parts.count >= 2, parts[0] == "circle" {
            let candidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return nil }
            groupID = candidate
            parts = Array(parts.dropFirst(2))
        }

        switch parts {
        case ["round", "current"]:
            self = .round(groupID: groupID)
        case ["round", "current", "results"]:
            self = .results(groupID: groupID)
        case ["record"]:
            self = .record(groupID: groupID)
        default:
            // Swift has no array-with-binding pattern, so the one route that carries a value
            // is matched here rather than as a fifth `case`. `.join` is never circle-prefixed —
            // a circle segment ahead of it is malformed rather than ignored.
            guard groupID == nil, parts.count == 2 else { return nil }
            if parts[0] == "invite" {
                let id = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard UUID(uuidString: id) != nil else { return nil }
                self = .invitation(id: id)
                return
            }
            guard parts[0] == "join" else { return nil }
            // docs/04 §3: invite codes are case-insensitive and whitespace-stripped, so the
            // link normalises here and the join screen never sees a stray form.
            let normalised = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalised.isEmpty else { return nil }
            self = .join(code: normalised)
        }
    }

    /// Registered in `Info.plist` under `CFBundleURLSchemes`.
    static let scheme = "blinddrop"

    /// The invite domain (`docs/05` §5, `docs/16` §3). Claimed by
    /// `com.apple.developer.associated-domains` in `BlindDrop.entitlements` and served by the
    /// `apple-app-site-association` file in `kingston-du/blinddrop-site` (mirrored at
    /// `web/.well-known/` here).
    ///
    /// The web host the invite links live on. Changing it means changing the two matching
    /// strings in `BlindDrop.entitlements` and `SpotifyAuth.redirectURI`/`callbackHost` in the
    /// same commit, and re-signing — the associated-domains claim is baked into the binary.
    static let inviteHost = "blinddrop.app"

    /// The single path segment the invite link uses: `/j/<CODE>`.
    static let invitePath = "j"
    /// Recipient-specific direct invitations (`E20-02`).
    static let directInvitePath = "i"
}
