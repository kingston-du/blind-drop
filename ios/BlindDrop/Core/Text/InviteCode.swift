import Foundation

/// The invite code, as the field has to treat it (`docs/14` §7, `docs/03` §2).
///
/// Six characters from a **restricted alphabet**: `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. It
/// excludes `I`, `L`, `O`, `0` and `1` because this code gets read aloud across a room and typed
/// by somebody who was not listening carefully.
///
/// Everything here is normalisation, never validation-by-rejection: the field is not the place
/// a wrong code is discovered. `POST /groups/join` answers `NOT_FOUND` and that is the only
/// authority on whether a code exists (`docs/04` §3).
enum InviteCode {

    static let length = 6

    /// `docs/03` §2's alphabet, verbatim.
    static let alphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// Anything a person can get into the field, reduced to what a code can be.
    ///
    /// Uppercases, drops every character outside the alphabet, and truncates to six. That
    /// covers the three things that actually happen: typing lowercase, pasting `K7MQ-2X` off a
    /// message, and pasting the whole invite link.
    ///
    /// A pasted URL is handled first, because `https://blinddrop.app/j/K7MQ2X` filtered
    /// character by character would come out as `HTTPSBLINDDR` — six characters of nonsense
    /// that look exactly like a code. The link is the commonest way an invite arrives, so it is
    /// the case worth getting right rather than the case worth mangling.
    ///
    /// A string that is a URL but **not** one of ours yields nothing at all, for the same
    /// reason: `https://example.com/j/K7MQ2X` mined character by character is `HTTPSE`, which
    /// is a complete-looking code that can never match. An empty field is the honest answer to
    /// a link we do not understand.
    static func normalise(_ raw: String) -> String {
        switch link(in: raw) {
        case .ours(let code):
            return String(code.uppercased().filter { alphabet.contains($0) }.prefix(length))
        case .foreign:
            return ""
        case .notALink:
            return String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
        }
    }

    /// Whether a normalised code is the right shape to send. Not whether it exists.
    static func isComplete(_ normalised: String) -> Bool {
        normalised.count == length
    }

    /// What a pasted string is, as far as this field is concerned.
    private enum Pasted {
        /// An invite link, and the code in it.
        case ours(code: String)
        /// A URL, but not one that names a group of ours.
        case foreign
        /// Not a URL at all — a typed or pasted code.
        case notALink
    }

    private static func link(in raw: String) -> Pasted {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://") else { return .notALink }
        // Parsed through the same type the deep links use, so there is one grammar for
        // `blinddrop://join/…` and `https://blinddrop.app/j/…` and not a second one here.
        guard let url = URL(string: trimmed), case .join(let code)? = DeepLink(url) else {
            return .foreign
        }
        return .ours(code: code)
    }

    /// The invite URL for a code — what **Share invite** actually shares (`docs/05` §5).
    ///
    /// The URL and not the bare code: a code alone in a message is six characters somebody has
    /// to know what to do with, and the whole point of the landing page is that they do not.
    static func inviteURL(for code: String) -> URL? {
        URL(string: "https://\(DeepLink.inviteHost)/j/\(normalise(code))")
    }
}
