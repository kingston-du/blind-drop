import Foundation

/// The strings a **component** renders, keyed to `docs/11`.
///
/// Screens do not go through this type — they hand their copy to a component as a parameter,
/// or write `Text("some.key")` and let SwiftUI resolve the `LocalizedStringKey`. What lives
/// here is the copy a view in `DesignSystem/` builds for itself, and there are only three
/// kinds of it:
///
/// 1. **VoiceOver labels.** `docs/12` §2 requires cards to be a single accessibility element
///    announcing four facts. That label is assembled from the view's own parts, so the view
///    has to build it, and building it means resolving a format.
/// 2. **The countdown's words.** `CountdownDisplay` is deliberately a value, not a string
///    (`docs/13` §5) — this is where the words get applied to it.
/// 3. **The readability bands.** `StatMeter` prints its own band label.
///
/// Nothing here holds a literal. Every string is a key into `Resources/Localizable.strings`,
/// which is transcribed from `docs/11`; `CopyTests` asserts each key actually resolves, so a
/// typo surfaces as a failing test rather than as the key itself printed on a card.
enum Copy {

    /// The bundle the strings live in — found through a marker class rather than assumed to be
    /// `Bundle.main`, so the lookup is the same whether the caller is the app or a test bundle
    /// hosted inside it.
    static let bundle = Bundle(for: BundleMarker.self)

    private final class BundleMarker {}

    /// A string with no placeholders.
    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// A string with placeholders, filled positionally.
    ///
    /// `String(format:)` rather than string interpolation because the deck's formats are
    /// positional (`%lld`, `%@`) and a translator has to be able to reorder them — which is
    /// what `%1$@` exists for and what interpolation cannot express.
    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }

    // MARK: - The countdown

    /// `CountdownDisplay` in words (`docs/11` §The countdown).
    ///
    /// The precise form is assembled here rather than in the deck because `HH:MM:SS` is a
    /// number format, not a phrase — there is nothing in it for a translator to translate, and
    /// a `%02lld:%02lld:%02lld` row in the copy deck would be a trap rather than a string.
    static func countdown(_ display: CountdownDisplay) -> String {
        switch display {
        case .unknown:
            string("countdown.unknown")
        case let .precise(hours, minutes, seconds):
            String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
        case let .coarse(.hours(hours)):
            format("countdown.coarse.hours", hours)
        case let .coarse(.minutes(minutes)):
            format("countdown.coarse.minutes", minutes)
        case .coarse(.underAMinute):
            string("countdown.coarse.soon")
        }
    }

    // MARK: - Readability bands

    /// A band in words. No band is framed as good or bad (`docs/11`).
    static func band(_ band: ReadabilityBand) -> String {
        string("band.\(band.rawValue)")
    }

    // MARK: - VoiceOver

    /// The label formats of `docs/12` §2, assembled.
    ///
    /// **The blind window applies to VoiceOver too** (`docs/12` §2). Nothing in here counts
    /// submissions, names a member who has not been revealed, or exposes a fact the visual UI
    /// is withholding — a hidden label that says "4 of 8 submitted" leaks exactly as hard as a
    /// visible one, and `E14`'s audit reads this file.
    enum A11y {

        /// A reveal card: its number, its title, its artist, and its current guess — the four
        /// facts `docs/12` §2 requires, literally.
        static func card(number: Int, title: String, artist: String, guess: Guess) -> String {
            switch guess {
            case .none:
                format("a11y.card.unguessed", number, title, artist)
            case let .assigned(name):
                format("a11y.card.guessed", number, title, artist, name)
            case .mine:
                format("a11y.card.mine", number, title, artist)
            case .unavailable:
                // A round the caller cannot guess in (`docs/04` §4). The card still announces
                // its three facts; there is no fourth because there is no sheet to fill in.
                format("a11y.card", number, title, artist)
            }
        }

        /// What a card's fourth fact is.
        enum Guess: Sendable, Equatable {
            /// Guessable, not yet guessed.
            case none
            /// Guessed, as this person.
            case assigned(name: String)
            /// The caller's own song — it has no guess and never will.
            case mine
            /// The caller cannot guess at all: they did not submit, or they joined late.
            case unavailable
        }

        static let cardHint = string("a11y.card.hint")

        static func sealed(title: String, artist: String, remaining: String) -> String {
            format("a11y.sealed", title, artist, remaining)
        }

        /// The countdown, which announces what it is counting to. `.updatesFrequently` and
        /// recomputed on focus, not on every tick (`docs/12` §2).
        static func countdown(_ display: CountdownDisplay, until deadline: Deadline) -> String {
            format(deadline.key, Copy.countdown(display))
        }

        /// What a countdown is counting down to.
        enum Deadline: Sendable, Equatable {
            case reveal
            case answers

            var key: String {
                switch self {
                case .reveal: "a11y.countdown"
                case .answers: "a11y.countdown.answers"
                }
            }
        }

        /// A name chip: the name, then its state. **The state is a real announcement, not the
        /// 0.6 opacity** — `docs/12` §3: opacity alone is not a status indicator.
        static func nameChip(_ name: String, assignedTo cardNumber: Int?) -> String {
            format("a11y.namechip", name, nameChipValue(assignedTo: cardNumber))
        }

        /// The state is also supplied separately as the control's accessibility value. Keeping
        /// it here makes the full copy string and the VoiceOver value impossible to drift.
        static func nameChipValue(assignedTo cardNumber: Int?) -> String {
            cardNumber.map { format("a11y.namechip.assigned", $0) }
                ?? string("a11y.namechip.unassigned")
        }

        /// A chip the caller cannot use, with **why** in place of the state (`docs/12` §2:
        /// *"their label includes the reason. A disabled control that does not explain itself is
        /// worse than a hidden one."*). Same format as the assignable case, because to a
        /// VoiceOver user the shape of the sentence should not change with the caller's luck.
        static func nameChip(_ name: String, unavailable reason: String) -> String {
            format("a11y.namechip", name, reason)
        }

        /// Posted as an `.announcement` when a guess is assigned (`docs/12` §2).
        static func guessAssigned(cardNumber: Int, name: String) -> String {
            format("a11y.guess.assigned", cardNumber, name)
        }

        /// The `✕` on an inline chip (`docs/08` §6), which is a 24pt glyph visually and a named
        /// action to VoiceOver. `docs/12` §5: no gesture is the only way to do anything, and
        /// that holds for the pointer-free path too.
        static let clearGuess = string("a11y.guess.clear")

        static func preview(isPlaying: Bool) -> String {
            string(isPlaying ? "a11y.preview.stop" : "a11y.preview.play")
        }

        static func track(title: String, artist: String) -> String {
            format("a11y.track", title, artist)
        }

        static let trackHint = string("a11y.track.hint")

        /// The readability meter, announced as a percentage **and** a band name — the number
        /// alone would be a rank with extra steps.
        static func readability(percent: Int, band: ReadabilityBand) -> String {
            format("a11y.readability", percent, Copy.band(band))
        }
    }
}
