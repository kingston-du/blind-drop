import Foundation

/// The client half of `docs/14` §7's display-name rule, and a **mirror** of the server's
/// `_shared/text.ts` rather than a second opinion about it.
///
/// The server is still the authority: it cleans and length-checks every `PUT /me` body whatever
/// the client sends. This exists so the person typing sees what will actually be saved. A name
/// that silently loses four characters between the field and the guess sheet is a name the user
/// did not choose, and they find out about it tomorrow night in front of their friends.
///
/// What is stripped, and why it is not paranoia (`docs/14` §7): a right-to-left override in a
/// name reorders the guess sheet around it, and a zero-width joiner makes two names
/// indistinguishable on screen. Both are one paste away, and both are cheap to remove at the
/// door.
enum DisplayName {

    /// `docs/04` §2 — 1 to 24 characters, counted after cleaning.
    static let maximumLength = 24

    /// C0 and C1 control characters, including newline and tab. The same set as the server's
    /// `CONTROL`.
    private static let control = CharacterSet(charactersIn: "\u{0000}"..."\u{001F}")
        .union(CharacterSet(charactersIn: "\u{007F}"..."\u{009F}"))

    /// Invisibles and bidirectional overrides. The same set as the server's `INVISIBLE`:
    /// zero-width space/joiner, the direction marks, the embedding and override block, the word
    /// joiner and invisible operators, the isolate block, the soft hyphen, and the BOM.
    private static let invisible = CharacterSet(charactersIn: "\u{00AD}")
        .union(CharacterSet(charactersIn: "\u{200B}"..."\u{200F}"))
        .union(CharacterSet(charactersIn: "\u{202A}"..."\u{202E}"))
        .union(CharacterSet(charactersIn: "\u{2060}"..."\u{2064}"))
        .union(CharacterSet(charactersIn: "\u{2066}"..."\u{2069}"))
        .union(CharacterSet(charactersIn: "\u{FEFF}"))

    /// A name as it will be stored: NFC-normalised, stripped of controls and invisibles,
    /// internal whitespace collapsed, ends trimmed.
    ///
    /// Returns the cleaned string, which the caller still has to length-check — an all-invisible
    /// name cleans down to `""` and is not a name.
    static func clean(_ raw: String) -> String {
        let stripped = raw.precomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !control.contains($0) && !invisible.contains($0)
        }
        return String(String.UnicodeScalarView(stripped))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Length as a person and as Postgres both count it: **characters**, not UTF-16 units.
    ///
    /// `"👨‍👩‍👧".count` is 1 and its `utf16.count` is 8. Counting the second would tell somebody
    /// their three-character name is too long, which is the kind of validation error nobody can
    /// act on because the field looks fine.
    static func length(_ cleaned: String) -> Int { cleaned.count }

    /// What is wrong with a name, or `nil` when nothing is.
    ///
    /// Evaluated on the **cleaned** string, which is what the field shows and what the server
    /// will store, so "the button is enabled" and "the server will accept it" cannot disagree.
    static func problem(with raw: String) -> Problem? {
        let cleaned = clean(raw)
        if cleaned.isEmpty { return .empty }
        if length(cleaned) > maximumLength { return .tooLong }
        return nil
    }

    /// The two ways a name is refused, each with its own line in `docs/11`. They are separate
    /// cases rather than one "invalid" because *"Enter a name to continue"* and *"Keep it to 24
    /// characters"* ask for different actions.
    enum Problem: Equatable, Sendable {
        case empty
        case tooLong

        var copyKey: String {
            switch self {
            case .empty: "onboarding.name.error.empty"
            case .tooLong: "onboarding.name.error.long"
            }
        }
    }
}
