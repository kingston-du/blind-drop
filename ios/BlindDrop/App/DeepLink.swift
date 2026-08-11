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
/// Out of scope here: the invite universal link `https://blinddrop.app/j/<CODE>` (`docs/05`
/// §5) arrives through `.onContinueUserActivity`, not `.onOpenURL`, and lands with E09-04.
enum DeepLink: Equatable, Sendable {
    /// `blinddrop://round/current` — today's round, phase-appropriate screen.
    case round
    /// `blinddrop://round/current/results` — results for today's round.
    case results
    /// `blinddrop://record` — The Record.
    case record
    /// `blinddrop://join/<CODE>` — join flow, code prefilled.
    case join(code: String)

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        // `blinddrop://record` puts "record" in `host` and leaves `path` empty, while
        // `blinddrop://round/current` puts "round" in `host` and "current" in the path. Both
        // shapes are normalised into one list so the four routes match as written in
        // docs/05 §5 rather than as two special cases.
        var parts: [String] = []
        if let host = url.host(percentEncoded: false), !host.isEmpty { parts.append(host) }
        parts += url.pathComponents.filter { $0 != "/" }

        switch parts {
        case ["round", "current"]:
            self = .round
        case ["round", "current", "results"]:
            self = .results
        case ["record"]:
            self = .record
        default:
            // Swift has no array-with-binding pattern, so the one route that carries a value
            // is matched here rather than as a fifth `case`.
            guard parts.count == 2, parts[0] == "join" else { return nil }
            // docs/04 §3: invite codes are case-insensitive and whitespace-stripped, so the
            // link normalises here and the join screen never sees a stray form.
            let normalised = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalised.isEmpty else { return nil }
            self = .join(code: normalised)
        }
    }

    /// Registered in `Info.plist` under `CFBundleURLSchemes`.
    static let scheme = "blinddrop"
}
