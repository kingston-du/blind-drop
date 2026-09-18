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
        let template = string(key)
        // `localizedStringWithFormat` is the formatter that resolves `%#@rule@` tokens from
        // Localizable.stringsdict. Spell out the small, bounded arities used by the copy deck
        // because Swift variadics cannot otherwise forward an already-collected argument array.
        switch arguments.count {
        case 0: return template
        case 1: return String.localizedStringWithFormat(template, arguments[0])
        case 2: return String.localizedStringWithFormat(template, arguments[0], arguments[1])
        case 3:
            return String.localizedStringWithFormat(
                template, arguments[0], arguments[1], arguments[2]
            )
        case 4:
            return String.localizedStringWithFormat(
                template, arguments[0], arguments[1], arguments[2], arguments[3]
            )
        case 5:
            return String.localizedStringWithFormat(
                template, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]
            )
        case 6:
            return String.localizedStringWithFormat(
                template, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4],
                arguments[5]
            )
        default:
            assertionFailure("Copy format \(key) exceeds the supported copy-deck arity")
            return String(format: template, locale: .current, arguments: arguments)
        }
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

    // MARK: - The switcher

    /// A switcher row's entire second column (`E19-02`, `docs/11` §The switcher) — `CircleState`'s
    /// raw value is the key suffix, the same trick `band(_:)` above plays on `ReadabilityBand`.
    static func switcherState(_ state: CircleState) -> String {
        string("switcher.state.\(state.rawValue)")
    }

    // MARK: - Results

    /// *"4 of 7 got it"*, and the two ends of that range which get their own sentence
    /// (`docs/11` — `results.card.*`).
    ///
    /// The special cases are copy rather than arithmetic on screen: *"0 of 7 got it"* and
    /// *"7 of 7 got it"* are both true and both read like a spreadsheet, and the two nights this
    /// game is remembered for are the one nobody got and the one everybody did.
    static func resultCount(correct: Int, eligible: Int) -> String {
        if correct <= 0 { return string("results.card.nobody") }
        if correct >= eligible { return string("results.card.everybody") }
        return format("results.card.correct", correct, eligible)
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
        static func card(
            number: Int,
            title: String,
            artist: String,
            guess: Guess,
            reaction: ReactionKind? = nil
        ) -> String {
            let facts = cardFacts(number: number, title: title, artist: artist, guess: guess)
            // Appended as its own sentence rather than folded into the four formats above, which
            // would have meant five more strings in the deck saying the same clause five times
            // (`E46-02`). Absent entirely when there is no mark — *"No mark"* is a thing to say
            // about a card nobody needed to say anything about.
            guard let reaction else { return facts }
            return "\(facts) \(format("a11y.reaction.card", string(reaction.copyKey)))"
        }

        private static func cardFacts(
            number: Int, title: String, artist: String, guess: Guess
        ) -> String {
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
            case let .resolved(resolution):
                result(number: number, title: title, artist: artist, resolution: resolution)
            }
        }

        /// A mark just placed or cleared, for the announcement `docs/12` §2 requires of a state
        /// change nobody moved to see (`E46-02`).
        ///
        /// Two strings rather than one with an optional clause, for the same reason
        /// `result(number:…)` below is two sentences: *"cleared"* is not a kind, and a format
        /// taking `%@` for the mark would have to be handed a word meaning no word.
        static func reactionPlaced(cardNumber: Int, kind: ReactionKind?) -> String {
            guard let kind else { return format("a11y.reaction.cleared", cardNumber) }
            return format("a11y.reaction.placed", cardNumber, string(kind.copyKey))
        }

        /// A results card: the three facts, then the answer, then — only if the caller guessed
        /// — what they said and how it went (`docs/12` §2, `a11y.card.result` + `.result.mine`).
        ///
        /// Two sentences joined rather than one format with optional pieces, because *"Your
        /// guess was Cal. Wrong."* is a sentence about the reader and the one before it is a
        /// sentence about the room. A VoiceOver user who did not guess hears only the second,
        /// which is exactly what a sighted one sees.
        private static func result(
            number: Int,
            title: String,
            artist: String,
            resolution: CardResolution
        ) -> String {
            let answer = format(
                "a11y.card.result", number, title, artist,
                resolution.owner, resolution.correctCount, resolution.eligibleCount
            )
            guard let guess = resolution.myGuess else { return answer }
            let verdict = string(guess.isCorrect ? "a11y.guess.correct" : "a11y.guess.incorrect")
            return "\(answer) \(format("a11y.card.result.mine", guess.name, verdict))"
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
            /// The answers are out: the card names its owner, its count, and the caller's mark.
            case resolved(CardResolution)
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

        static func recordTrack(title: String, artist: String, member: String) -> String {
            format("a11y.record.track", title, artist, member)
        }

        static let trackHint = string("a11y.track.hint")

        /// The readability meter, announced as a percentage **and** a band name — the number
        /// alone would be a rank with extra steps.
        static func readability(percent: Int, band: ReadabilityBand) -> String {
            format("a11y.readability", percent, Copy.band(band))
        }

        /// One switcher row (`E19-02`): the group's name, its state, and — only when the group
        /// wants the caller's attention — a third sentence naming that. Two localized reads
        /// joined rather than a third placeholder in `a11y.switcher.row`, the same shape
        /// `result(...)` above uses for a results card's own optional second sentence: a group
        /// that does not need attention should not carry a silent "false" through the format.
        static func switcherRow(name: String, state: String, needsAction: Bool) -> String {
            let base = format("a11y.switcher.row", name, state)
            guard needsAction else { return base }
            return "\(base) \(string("a11y.switcher.attention"))"
        }

        static let switcherOpenerHint = string("a11y.switcher.opener.hint")
        static let switcherRowHint = string("a11y.switcher.row.hint")

        /// The header's own label plus, when some *other* circle wants attention, a second
        /// sentence saying so — the VoiceOver channel for the small mark beside the group's
        /// name (`docs/12` §3: colour, and here presence, is never the only channel).
        static func switcherOpener(groupName: String, otherNeedsAction: Bool) -> String {
            guard otherNeedsAction else { return groupName }
            return "\(groupName) \(string("a11y.switcher.opener.otherNeedsAction"))"
        }
    }
}
