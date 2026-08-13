import SwiftUI

/// A card once the answers are out (`docs/08` §7.1).
///
/// The card's own numbers, resolved: whose song it was, how many of the room had it, and — only
/// if the caller guessed — what they said. `myGuess` is `nil` for the caller's own card, for a
/// card they left blank, and for a round they could not guess in at all; the three are the same
/// fact from the card's point of view, which is that there is no mark to draw.
///
/// `eligibleCount` is the server's `eligible_guesser_count` and is `S − 1` on every card
/// (`docs/02` §4.1). It is carried rather than derived because a denominator the client worked
/// out from what it could see would quietly become a count of the people who bothered.
struct CardResolution: Equatable, Sendable {
    let owner: String
    let correctCount: Int
    let eligibleCount: Int
    let myGuess: MyGuess?

    /// What the caller said, and whether it was right. The name, not the id — by this point the
    /// screen is printing a person rather than identifying one.
    struct MyGuess: Equatable, Sendable {
        let name: String
        let isCorrect: Bool
    }
}

/// The reveal card. Reads like a tasting-flight sheet (`docs/07` §5).
///
/// ```
/// ┌────────────────────────────────────────────────┐
/// │   4      ▓▓▓▓▓▓▓   Motion Sickness             │
/// │          ▓▓▓▓▓▓▓   Phoebe Bridgers        ▶︎    │
/// │          ▓▓▓▓▓▓▓   ┌──────────────────────┐    │
/// │                    │  Who dropped this?   │    │
/// │                    └──────────────────────┘    │
/// └────────────────────────────────────────────────┘
///  ↑ displayXL          ↑ 88pt artwork      ↑ assignment chip
/// ```
///
/// Vertical stack, **never a grid**. The number sits large and left in the display face; artwork
/// and metadata to its right. Above `.accessibility1` the number moves *above* the artwork row
/// rather than beside it (`docs/12` §1) — a reflow, decided from `dynamicTypeSize` and never
/// from a width measurement.
///
/// **It is a single accessibility element** (`docs/12` §2). Letting VoiceOver walk into the
/// artwork, the title and the artist separately is three swipes a card and thirty-six swipes to
/// read a twelve-card reveal. The preview control is the one nested thing, and it is reachable
/// both ways: as a custom action and as a child.
struct FlightCard: View {
    /// The card's number — the game's identity for the song, not an index.
    let number: Int
    let track: TrackDTO
    /// Amber while the round is sealed, ultramarine once it is live (`docs/07` §5).
    let accent: PhaseAccent
    /// What the card says about the caller's guess, and what it announces.
    let assignment: Assignment
    var preview: TrackRow.Preview?
    /// Tapping the card opens the guess sheet. `nil` on a card that cannot be guessed —
    /// a non-submitter's view, or the caller's own song.
    var chooseGuess: (() -> Void)?
    /// Clears an assigned guess — the `✕` on the inline chip (`docs/08` §6). `nil` leaves the
    /// chip without one, which is what a locked-in sheet renders.
    var clearGuess: (() -> Void)?
    /// Present only while the reveal's once-per-round unseal is being coordinated.
    var unseal: UnsealPresentation? = nil
    /// Present only while the results' once-per-round name-resolve is being coordinated
    /// (`docs/09` §4). Absent means settled — which is what a re-opened round renders.
    var resolve: ResolvePresentation? = nil

    /// The state of the caller's guess for this card.
    enum Assignment: Equatable {
        /// Guessable, nothing chosen yet. Renders `reveal.card.prompt` — *"Who dropped this?"*
        case unguessed
        /// Guessed, as this member.
        case guessed(name: String)
        /// The caller's own song. Renders `reveal.card.mine` — *"Yours"*.
        case mine
        /// The caller cannot guess in this round at all (`docs/04` §4). The chip is absent
        /// rather than disabled-looking: there is nothing to enable.
        case unavailable
        /// The answers are out (`docs/08` §7.1). The chip's place is taken by whose song it
        /// was, how the room did on it, and the mark on the caller's own guess.
        case resolved(CardResolution)

        var accessibilityGuess: Copy.A11y.Guess {
            switch self {
            case .unguessed: .none
            case let .guessed(name): .assigned(name: name)
            case .mine: .mine
            case .unavailable: .unavailable
            case let .resolved(resolution): .resolved(resolution)
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `docs/12` §1: side-by-side becomes stacked above `.accessibility1`, decided from the
    /// type size and not from a width check.
    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        card
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Copy.A11y.card(
                    number: number,
                    title: track.title,
                    artist: track.artist,
                    guess: assignment.accessibilityGuess
                )
            )
            // `docs/12` §2's table: a reveal card is a `.button`, a results card is
            // `.staticText`. A card with nothing to choose is the second — the caller's own
            // song, a round they cannot guess in, and every card once the answers are out.
            .accessibilityAddTraits(chooseGuess == nil ? .isStaticText : .isButton)
            .accessibilityHint(chooseGuess == nil ? "" : Copy.A11y.cardHint)
            .accessibilityAction {
                chooseGuess?()
            }
            // Reachable both ways (`docs/12` §2): as a custom action…
            .accessibilityActions {
                if let preview {
                    Button(action: preview.toggle) {
                        Text(verbatim: Copy.A11y.preview(isPlaying: preview.isPlaying))
                    }
                }
                if let clearGuess {
                    Button(action: clearGuess) { Text(verbatim: Copy.A11y.clearGuess) }
                }
            }
            // …and as a child, so direct-touch exploration finds it where it is drawn.
            .accessibilityChildren {
                if let preview {
                    PreviewControl(isPlaying: preview.isPlaying, accent: accent, action: preview.toggle)
                }
            }
            // A custom rotor "Songs", so a VoiceOver user jumps between numbers directly
            // (`docs/12` §2). The rotor is declared by the screen that owns the list; the card
            // contributes the label it will be found by.
            .accessibilityIdentifier("flightCard.\(number)")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if isStacked {
                // `docs/12` §1: the number moves above the artwork row. The artwork comes with
                // it, because leaving an 88pt thumbnail beside the text at `.accessibility5`
                // leaves the title a column narrower than the word "Sickness" — and a column
                // narrower than a word does not wrap, it breaks mid-word.
                cardNumber
                artwork
                metadata
                assignmentChip
            } else {
                HStack(alignment: .top, spacing: Space.lg) {
                    cardNumber
                    artwork
                    metadata
                }
                // Indented to the artwork's left edge and running to the card's right, which is
                // where `docs/08` §6 draws it. Inside the metadata column it would have about
                // 137pt on an SE — narrower than *"Who dropped this?"*, and a prompt that
                // truncates is a prompt that has stopped asking anything.
                assignmentChip
                    .padding(.leading, numberColumnWidth + Space.lg)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(cardFill)
                .animation(unseal?.reducedMotion == true
                    ? .easeInOut(duration: 0.240)
                    : Motion.Unseal.colors.animation, value: unseal?.phase)
        )
        .overlay(
            // A card is `surface` on `paper` with a 1pt border. There is no shadow in this app
            // (`docs/07` §2, Elevation).
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(cardBorder, lineWidth: Stroke.border)
                .animation(unseal?.reducedMotion == true
                    ? .easeInOut(duration: 0.240)
                    : Motion.Unseal.colors.animation, value: unseal?.phase)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture { chooseGuess?() }
    }

    /// The number: `displayXL`, in the accent, capped at 1.6× by `Typography` so it stays the
    /// largest thing on the card without eating it (`docs/12` §1).
    private var cardNumber: some View {
        Text(verbatim: number.formatted(.number.grouping(.never)))
            .typeStyle(.displayXL)
            // No `.monospacedDigit()` here: `Typography` already sets tabular figures on every
            // display style through the font descriptor, and the modifier would replace the
            // resolved Bricolage face — its axes and its 1.6× ceiling with it — with a system one.
            .foregroundStyle(numberColor)
            .opacity(unseal?.phase == .sealed ? 0.4 : 1)
            .animation(unseal?.reducedMotion == true
                ? .easeInOut(duration: 0.240)
                : Motion.Unseal.number.animation, value: unseal?.phase)
            .fixedSize()
            // A fixed column, so the artwork starts at the same x on every card in the list.
            // A group runs to twelve members, so two digits is the widest the number ever gets,
            // and a ragged left edge down a twelve-card reveal is the single most visible way
            // this screen could stop looking like a tasting sheet.
            .frame(minWidth: isStacked ? 0 : numberColumnWidth, alignment: .leading)
    }

    /// The width of the widest number a card can carry, measured rather than guessed.
    ///
    /// A group runs to twelve members (`docs/02`), so two digits is the ceiling; `88` is the
    /// widest pair in a tabular face, where every digit has the same advance. Measuring it off
    /// the resolved font means the column survives a change to the type scale, to the Dynamic
    /// Type ramp, or to the face itself — a hardcoded 62 would go subtly wrong at the next one
    /// and show up as a list whose artwork no longer lines up.
    private var numberColumnWidth: CGFloat {
        let font = Typography.uiFont(.displayXL, for: UIContentSizeCategory(dynamicTypeSize))
        return ("88" as NSString).size(withAttributes: [.font: font]).width
    }

    @ViewBuilder private var artwork: some View {
        if let unseal {
            UnsealingArtwork(track: track, presentation: unseal)
        } else {
            ArtworkView(track, size: Layout.Artwork.flightCard)
        }
    }

    private var cardFill: Color {
        unseal?.phase == .sealed ? Palette.amberWash : Palette.surface
    }

    private var cardBorder: Color {
        unseal?.phase == .sealed ? Palette.amberDeep : Palette.edge
    }

    private var numberColor: Color {
        unseal?.phase == .sealed ? Palette.amberDeep : accent.mark
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            // The title gets the column's full width; the preview control sits on the artist
            // line, where both of `docs/07` §5's and `docs/08` §6's drawings put it. Sharing the
            // title's line with a 28pt control costs it the width of a word, and on a 375pt
            // phone with a two-digit number and 88pt artwork beside it that is the difference
            // between "Motion / Sickness" and a title broken in the middle of *Sickness*.
            Text(verbatim: track.title)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(verbatim: track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let preview {
                    PreviewControl(isPlaying: preview.isPlaying, accent: accent, action: preview.toggle)
                        // The card owns the announcement; the control is reached through the
                        // card's custom action and its synthetic child, not by a fourth swipe.
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// What the card says about the caller's guess. Its words are `docs/11`'s
    /// (`reveal.card.prompt`, `reveal.card.mine`); a chosen name is data, not copy.
    @ViewBuilder private var assignmentChip: some View {
        switch assignment {
        case .unguessed:
            chip(Text("reveal.card.prompt"), isFilled: false)
        case let .guessed(name):
            chip(Text(verbatim: name), isFilled: true, onClear: clearGuess)
        case .mine:
            // **The one place amber appears on the reveal screen** (`docs/08` §6): a plain
            // label, not a chip, *"because your card is still your secret"*. It is not a guess
            // and giving it a guess's shape would invite a tap that does nothing.
            Text("reveal.card.mine")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.amberText)
        case .unavailable:
            EmptyView()
        case let .resolved(resolution):
            ResolvedAnswer(resolution: resolution, presentation: resolve ?? .settled)
        }
    }

    /// Whose song it was, how the room did, and how the caller did (`docs/08` §7.1).
    ///
    /// A view of its own rather than three lines inline, because it is the only part of the card
    /// that animates on the results screen and the animation has to leave the geometry alone:
    /// everything here is drawn whatever the presentation says and moved by `opacity` and
    /// `offset`, so a card is exactly as tall while its name is arriving as after it has.
    private struct ResolvedAnswer: View {
        let resolution: CardResolution
        let presentation: ResolvePresentation

        var body: some View {
            VStack(alignment: .leading, spacing: Space.xxs) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: Copy.format("results.card.owner", resolution.owner))
                        .typeStyle(.bodyLStrong)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: Copy.resultCount(
                        correct: resolution.correctCount,
                        eligible: resolution.eligibleCount
                    ))
                        .typeStyle(.monoS)
                        .foregroundStyle(Palette.inkDim)
                }
                .opacity(presentation.hasName ? 1 : 0)
                // *"a 220ms crossfade plus `y: 4 → 0`"* (`docs/09` §4). The rise is dropped
                // under reduced motion, because the rise **is** the movement — the crossfade
                // stays, because the arrival is information.
                .offset(y: presentation.hasName || presentation.reducedMotion
                        ? 0
                        : Motion.Resolve.rise)
                .animation(presentation.reducedMotion ? Motion.Resolve.reduced : Motion.Resolve.name,
                           value: presentation.hasName)

                if let guess = resolution.myGuess {
                    mark(guess)
                        .opacity(presentation.hasMark ? 1 : 0)
                        .animation(presentation.reducedMotion
                                   ? Motion.Resolve.reduced
                                   : Motion.Resolve.mark,
                                   value: presentation.hasMark)
                        .padding(.top, Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The caller's own guess. **`ultramarine` check or `inkFaint` strike — never red and
        /// never a cross** (`docs/07` §2), and the two differ by *shape* as well as by colour
        /// (`docs/12` §3): one carries a glyph the other does not, and one is struck through.
        ///
        /// The struck name itself is `inkDim` rather than `inkFaint`: `docs/12` §3 rules
        /// `inkFaint` out for body text at 3.49:1, and it is the **strike** that the design
        /// system assigns that token to.
        @ViewBuilder private func mark(_ guess: CardResolution.MyGuess) -> some View {
            HStack(spacing: Space.sm) {
                if guess.isCorrect {
                    // `.typeStyle` rather than a resolved `UIFont`: the glyph has to ride the
                    // same Dynamic Type ramp the name beside it does, and a font resolved at the
                    // device's default category leaves a 15pt check next to 40pt text at
                    // `.accessibility5` (`docs/12` §1).
                    Image(systemName: "checkmark")
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.ultramarine)
                }
                Text(verbatim: guess.name)
                    .typeStyle(.bodyM)
                    .foregroundStyle(guess.isCorrect ? Palette.ultramarine : Palette.inkDim)
                    .strikethrough(!guess.isCorrect, color: Palette.inkFaint)
            }
        }
    }

    private func chip(_ label: Text, isFilled: Bool, onClear: (() -> Void)? = nil) -> some View {
        HStack(spacing: Space.sm) {
            label
                .typeStyle(.bodyM)
                .foregroundStyle(isFilled ? accent.onFill : Palette.inkDim)
                // Wraps rather than truncating: an `HStack` proposes a single line to a `Text`
                // that has a sibling, and the prompt is the one string on this card that has to
                // arrive whole.
                .fixedSize(horizontal: false, vertical: true)
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent.onFill)
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)  // reachable as the card's "Clear guess" action
            }
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: Layout.chipHeight)
        .background(
            // A pill is a pill only while the label is one line. At the accessibility sizes a
            // three-line label inside `Radius.pill` is a blob with text spilling out of its
            // curve, so the shape steps down to a control radius where the layout stacks.
            RoundedRectangle(cornerRadius: isStacked ? Radius.control : Radius.pill, style: .continuous)
                .fill(isFilled ? accent.fill : Palette.paperSunk)
        )
        .accessibilityHidden(true)  // the card's own label already carries the guess
    }
}
