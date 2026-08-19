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
                // `linksMenu` is `accessibilityHidden` — these are how the two links inside it
                // stay reachable on an answer card. Both services, each present only when the
                // payload actually carries it: an action that opens nothing is the same lie as
                // a menu item that does. Apple Music first here, as on the sealed card's corner,
                // where the order is the platform's store before the other one.
                if isAnswer {
                    if let apple = TrackLinkDestination.appleMusic(track: track) {
                        Button(action: { TrackLinkRouter.open(apple, using: SystemTrackLinkOpener()) }) {
                            Text("link.apple")
                        }
                    }
                    if let spotify = TrackLinkDestination.spotify(track: track) {
                        Button(action: { TrackLinkRouter.open(spotify, using: SystemTrackLinkOpener()) }) {
                            Text("link.spotify")
                        }
                    }
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

    /// Two densities, and the card picks its own.
    ///
    /// A reveal card is a **row** in a list of eight that has to be scannable in one screen: a
    /// 26pt number, a thumbnail, two lines, and the guess chip on the same line. An answer card
    /// is the **subject** of the moment: a 44pt number, a large thumbnail, and two blocks of
    /// resolution under a rule. It is keyed off the assignment rather than passed in, because
    /// `.resolved` is the *definition* of an answer card — a call site that could disagree is a
    /// call site that eventually would.
    private var isAnswer: Bool {
        if case .resolved = assignment { return true }
        return false
    }

    private var card: some View {
        Group {
            if isAnswer {
                answerCard
            } else {
                flightRow
            }
        }
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

    /// One line of tonight's flight.
    private var flightRow: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if isStacked {
                // `docs/12` §1: the text comes off the line and the chip with it. The number and
                // the artwork **stay** on a line together — neither grows with the type size, so
                // stacking them would add height and buy nothing. What has to move is the title,
                // because at `.accessibility5` a title and a name cannot share a 375pt row.
                HStack(alignment: .center, spacing: Space.md) {
                    cardNumber
                    artwork
                }
                metadata
                assignmentChip
            } else {
                HStack(alignment: .center, spacing: Space.md) {
                    cardNumber
                    artwork
                    metadata
                    // The chip takes its natural width and the title gives way, which is the
                    // right way round: a truncated title is still a title, and a truncated name
                    // is a different person.
                    assignmentChip
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
        }
        .padding(Layout.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tonight's answer for one song.
    ///
    /// **The links are one glyph, not two rows.** They were a trailing row of `CardCornerLinks`
    /// until `E17-03`: two independently 44pt-tall tap targets (`docs/12` §5) plus the gap above
    /// them is ~90pt of card, and a night runs to twelve cards, so the two words cost most of a
    /// screen of scrolling on a list whose whole job is to be read top to bottom. The Record had
    /// already answered this for a list of the same links — an ellipsis, top right — and the same
    /// menu is what the card takes now (`TrackUtilityMenu`, minus the *See results* item, which
    /// on the results screen would lead here).
    ///
    /// **Placed by the layout, not by an overlay.** The menu shares the card's first row, in an
    /// `HStack(alignment: .top)`; the row itself keeps its own `.center` alignment, because the
    /// number/artwork/title relationship is what makes the card read as a tasting sheet and
    /// nothing here touches it. An `.overlay(alignment: .topTrailing)` would have been fewer
    /// lines and would have put the ellipsis on top of the title at `.accessibility5`, where the
    /// title wraps to three lines and takes every point of width it is given. In a stack it
    /// cannot: the menu's 44pt is width the row never had to give.
    ///
    /// It sits beside **whatever the first row is**, which differs by size and is the point. Below
    /// `.accessibility1` that row is the number, the artwork and the metadata, so the menu costs
    /// the title 52pt of a line it was truncating anyway. Above it the row is the number and the
    /// artwork alone (`docs/12` §1's reflow) and the metadata has dropped below — where it keeps
    /// the card's **full** width, rather than the width left over beside an ellipsis it is no
    /// longer level with. Hanging the menu off the whole head block instead would have been one
    /// stack fewer and would have narrowed the title by those 52pt at exactly the sizes the
    /// reflow exists to give it room at.
    private var answerCard: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            if isStacked {
                HStack(alignment: .top, spacing: Space.sm) {
                    HStack(alignment: .center, spacing: Space.lg) {
                        cardNumber
                        artwork
                    }
                    // Neither the number nor the artwork grows with the type size, so this row
                    // does not fill the card on its own and the menu needs pushing to the edge.
                    // The row below has `metadata`'s `maxWidth: .infinity` doing the same job.
                    Spacer(minLength: Space.sm)
                    linksMenu
                }
                metadata
            } else {
                HStack(alignment: .top, spacing: Space.sm) {
                    HStack(alignment: .center, spacing: Space.lg) {
                        cardNumber
                        artwork
                        metadata
                    }
                    linksMenu
                }
            }
            assignmentChip
        }
        .padding(Layout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The card's overflow, hidden from VoiceOver here and re-exposed through `body`'s
    /// `.accessibilityActions` — the whole card is one VoiceOver element (`docs/12` §2), and a
    /// menu reachable only by direct touch inside that collapse would not be reachable by anyone
    /// swiping through it.
    ///
    /// Absent, not empty, when the payload carries neither service: an ellipsis that opens onto
    /// nothing is worse than no ellipsis. The same test `CardCornerLinks` makes before it draws.
    @ViewBuilder private var linksMenu: some View {
        if TrackLinkDestination.appleMusic(track: track) != nil
            || TrackLinkDestination.spotify(track: track) != nil {
            TrackUtilityMenu(track: track)
                .accessibilityHidden(true)
        }
    }

    /// The number, in the accent, capped at 1.6× by `Typography` so it stays the largest thing
    /// on the card without eating it (`docs/12` §1).
    private var cardNumber: some View {
        // Zero-padded to two digits, so *01* and *11* are the same width and the column of
        // numbers down the flight is a column. It is a number format rather than copy, which
        // is why it is written here and not in the deck.
        Text(verbatim: String(format: "%02lld", number))
            .typeStyle(isAnswer ? .numberL : .numberM)
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
        let style: TypeStyle = isAnswer ? .numberL : .numberM
        let font = Typography.uiFont(style, for: UIContentSizeCategory(dynamicTypeSize))
        return ("88" as NSString).size(withAttributes: [.font: font]).width
    }

    @ViewBuilder private var artwork: some View {
        if let unseal {
            UnsealingArtwork(track: track, presentation: unseal)
        } else {
            ArtworkView(track, size: isAnswer ? Layout.Artwork.resultCard : Layout.Artwork.flightCard)
        }
    }

    private var cardFill: Color {
        unseal?.phase == .sealed ? Palette.amberWash : Palette.surface
    }

    private var cardBorder: Color {
        unseal?.phase == .sealed ? Palette.amberEdge : Palette.edge
    }

    private var numberColor: Color {
        unseal?.phase == .sealed ? Palette.amber : accent.mark
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
                .lineLimit(isStacked ? nil : 1)
                .truncationMode(.tail)
                // **The answer card only.** Below `.accessibility1` its title shares a row with
                // the number, the artwork and the corner menu (`docs/12` §1's reflow has not
                // happened yet), which leaves an ordinary two-word title — *"Motion Sickness"*,
                // this file's own worked example — no room to set at full size without
                // truncating: a narrowed column, not a genuinely long title. It gets the same
                // "shrink rather than clip" the share card's headline already uses
                // (`10-SHARE-CARD-SPEC.md` §3) instead of a wider truncation floor: a title that
                // still does not fit at 80% is the case truncation is actually for. The reveal
                // row keeps its plain truncation — its title never carried this report, and its
                // chip already competes for the same line, which is a different-shaped problem.
                .minimumScaleFactor(isStacked || !isAnswer ? 1 : 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(verbatim: track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(isStacked ? nil : 1)
                    .truncationMode(.tail)
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
            // The chip shares the row with a title and an artist, so the prompt on it is two
            // words rather than four. The long form is still what VoiceOver hears, through the
            // card's own label.
            chip(Text(isStacked ? "reveal.card.prompt" : "reveal.card.prompt.short"), isFilled: false)
        case let .guessed(name):
            chip(Text(verbatim: name), isFilled: true, onClear: clearGuess)
        case .mine:
            // **The one place amber appears on the reveal screen** (`docs/08` §6): a plain
            // label, not a chip, *"because your card is still your secret"*. It is not a guess
            // and giving it a guess's shape would invite a tap that does nothing.
            Text("reveal.card.mine")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.amberText)
                .fixedSize()
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
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                Rule()
                resolution_
                Rule()
                room
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// Whose song it was, on the left, and what the caller said about it, on the right.
        ///
        /// Two columns rather than two lines, because they are two answers to the same question
        /// and reading them side by side is the whole moment the screen exists for.
        private var resolution_: some View {
            HStack(alignment: .top, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SectionLabel("results.card.by")
                    Text(verbatim: Copy.format("results.card.owner", resolution.owner))
                        .typeStyle(.displayS)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
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
                .frame(maxWidth: .infinity, alignment: .leading)

                if let guess = resolution.myGuess {
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        SectionLabel("results.card.yousaid")
                        mark(guess)
                    }
                    // Its own half of the row, right-aligned. Sized by the layout rather than by
                    // its content: a name that took its ideal width would push its own column
                    // off the card the moment somebody in the group is called Konstantinos.
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(presentation.hasMark ? 1 : 0)
                    .animation(presentation.reducedMotion
                               ? Motion.Resolve.reduced
                               : Motion.Resolve.mark,
                               value: presentation.hasMark)
                }
            }
        }

        /// How the room did on this one: a bar and the count that made it.
        private var room: some View {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("results.card.room")
                ProportionBar(
                    part: resolution.correctCount,
                    whole: resolution.eligibleCount,
                    accent: .revealed,
                    announcement: Copy.resultCount(
                        correct: resolution.correctCount,
                        eligible: resolution.eligibleCount
                    ),
                    fillProgress: presentation.hasBar ? 1 : 0
                )
            }
            .opacity(presentation.hasName ? 1 : 0)
            .animation(presentation.reducedMotion ? Motion.Resolve.reduced : Motion.Resolve.name,
                       value: presentation.hasName)
            .animation(presentation.reducedMotion ? Motion.Resolve.reduced : Motion.Resolve.mark,
                       value: presentation.hasBar)
        }

        /// The caller's own guess. **`ultramarine` check or `inkFaint` strike — never red and
        /// never a cross** (`docs/07` §2), and the two differ by *shape* as well as by colour
        /// (`docs/12` §3): one carries a glyph the other does not, and one is struck through.
        ///
        /// The struck name itself is `inkDim` rather than `inkFaint`: `docs/12` §3 rules
        /// `inkFaint` out for body text at 3.49:1, and it is the **strike** that the design
        /// system assigns that token to.
        @ViewBuilder private func mark(_ guess: CardResolution.MyGuess) -> some View {
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(verbatim: guess.name)
                    .typeStyle(.bodyL)
                    .foregroundStyle(guess.isCorrect ? Palette.ultramarine : Palette.inkDim)
                    .strikethrough(!guess.isCorrect, color: Palette.inkQuiet)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // **The word as well as the colour** (`docs/12` §3). *Hit* and *Miss* are set in
                // the micro-label, which is the same apparatus voice the rest of the card uses,
                // and there is no red anywhere near either of them.
                SectionLabel(
                    guess.isCorrect ? "results.card.hit" : "results.card.miss",
                    color: guess.isCorrect ? Palette.ultramarine : Palette.amberText
                )
            }
        }

    }

    private func chip(_ label: Text, isFilled: Bool, onClear: (() -> Void)? = nil) -> some View {
        HStack(spacing: Space.xs) {
            label
                .typeStyle(.bodyM)
                .foregroundStyle(isFilled ? accent.onFill : Palette.inkDim)
                // One line while the chip shares a row with a title; wrapping once the layout has
                // stacked and the chip has the width to itself.
                .lineLimit(isStacked ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent.onFill)
                        // Padded out to a 44pt region and then negatively padded back
                        // (`docs/12` §5). A `minimumTouchTarget()` frame here would make the
                        // glyph 44pt *wide* in the layout too, which on an SE costs the title
                        // beside it about a third of its column for a mark that is 11pt.
                        .padding(Space.md)
                        .contentShape(Rectangle())
                        .padding(-Space.md)
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
                .fill(isFilled ? accent.fill : Color.clear)
        )
        .overlay(
            // An empty chip is an outline, and a dashed one: it is the only control on the card
            // that is asking for something rather than reporting it, and a dashed edge is how a
            // form says *this is a blank* without printing the word.
            RoundedRectangle(cornerRadius: isStacked ? Radius.control : Radius.pill, style: .continuous)
                .strokeBorder(
                    isFilled ? Color.clear : Palette.edgeStrong,
                    style: StrokeStyle(lineWidth: Stroke.border, dash: [4, 3])
                )
        )
        .accessibilityHidden(true)  // the card's own label already carries the guess
    }
}
