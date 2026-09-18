import SwiftUI

/// The three marks a card can carry, and the one control that places them (`E46-02`,
/// `docs/19-REACTIONS.md` §5, §8.1).
///
/// **One shape, not three.** This is a single sunk strip divided into three, and the reason is
/// an argument the codebase had already made about a different control: `QuickPassScreen`'s
/// `navigation` doc comment rejects a bordered pill for Skip because *"a bordered pill beside a
/// grid of bordered pills reads as one more name, however its border is dashed"*. Three pills
/// under four `NameChip`s would read as three more names — a set of seven candidates, of which
/// three are not people. A strip cannot be mistaken for a chip: it is one object, it is sunk
/// rather than outlined, and it shares its register with `CueBanner` rather than with the pool.
///
/// **State is carried by shape as well as by colour** (`docs/12` §3, the rule `NameChip`'s
/// strikethrough answers): the chosen mark switches from its outline symbol to its filled one and
/// picks up the screen's accent, so the selection survives being read by someone who does not
/// see the accent at all. The word beneath moves from `inkDim` to `ink` with it.
///
/// **No count, ever, on this control.** `docs/19` §3: a reaction behaves exactly like a guess,
/// so the room's totals do not exist until the round is `scored`. The results screen draws the
/// counts with `ReactionMark` directly; this type has nowhere to put one.
struct ReactionBar: View {

    /// The caller's own mark on this card, or `nil`.
    let selected: ReactionKind?
    /// The screen's accent, passed in and never read from `Palette` — `CLAUDE.md` §2.5 is a
    /// decision the screen makes once (`PhaseAccent`).
    let accent: PhaseAccent
    /// Tapping the selected mark again passes `nil`: a second tap clears (`docs/19` §5).
    let action: (ReactionKind?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var typeSizeOverride: DynamicTypeSize?
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }

    /// Above `.accessibility1` the three segments become three rows — the same boundary
    /// `FlightCard` and the quick pass's own cue strip reflow at (`docs/12` §1). Three words
    /// cannot share a 375pt row at `.accessibility5`, and *"Not for me"* wrapping inside a
    /// third of one is the worst of both arrangements.
    private var isStacked: Bool { effectiveTypeSize >= .accessibility1 }

    init(
        selected: ReactionKind?,
        accent: PhaseAccent,
        action: @escaping (ReactionKind?) -> Void
    ) {
        self.selected = selected
        self.accent = accent
        self.action = action
    }

    /// Snapshot-only: fixes the size the bar lays out at, the same escape hatch the quick pass
    /// takes for its own goldens.
    func typeSize(_ typeSize: DynamicTypeSize) -> Self {
        var copy = self
        copy.typeSizeOverride = typeSize
        return copy
    }

    var body: some View {
        segments
            .padding(Space.sm)
            .frame(maxWidth: .infinity)
            .background(Palette.paperSunk, in: RoundedRectangle(cornerRadius: Radius.control))
    }

    /// How tall the bar draws at a given size — **the same arithmetic `body` lays out with**, so
    /// a caller reserving space for it cannot disagree with what it does (`E46-02`).
    ///
    /// The quick pass sizes its artwork from what the column has left, and it computes that
    /// rather than measuring it, for the reason `Layout.quickPassFixedChrome` records: a
    /// preference arrives after the first layout, so the square would draw large and jump
    /// smaller a frame later, on every card of every run. A flat `minimumTouchTarget` was the
    /// first answer here and was wrong in the middle of the ramp — `.frame(minHeight:)` is a
    /// floor, not a cap, and around `.xxxLarge` a scaled mark over a scaled `bodyS` word is
    /// taller than 44pt while the bar is still in its three-column arrangement.
    static func height(for typeSize: DynamicTypeSize) -> CGFloat {
        let category = UIContentSizeCategory(typeSize)
        let word = Typography.lineHeight(.bodyS, for: category)
        let mark = ReactionMark.Scale.control.base * UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: 1, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            // The widest of the three corrections, so the reserve is never under the tallest mark.
            * ReactionKind.allCases.map(\.opticalCorrection).max()!
        let stacked = typeSize >= .accessibility1
        // Stacked: mark beside word, three rows, `Space.xs` between them.
        // Otherwise: mark over word in one row.
        let segment = stacked
            ? max(word, mark)
            : mark + Space.xxs + word
        let rows = stacked ? 3 : 1
        let gaps = stacked ? Space.xs * 2 : 0
        return CGFloat(rows) * max(segment, Layout.minimumTouchTarget) + gaps + Space.sm * 2
    }

    @ViewBuilder private var segments: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(ReactionKind.allCases) { segment($0) }
            }
        } else {
            HStack(spacing: Space.xs) {
                ForEach(ReactionKind.allCases) { segment($0) }
            }
        }
    }

    private func segment(_ kind: ReactionKind) -> some View {
        let isChosen = selected == kind
        return Button {
            action(isChosen ? nil : kind)
        } label: {
            content(kind, isChosen: isChosen)
                .frame(maxWidth: .infinity, alignment: isStacked ? .leading : .center)
                .frame(minHeight: Layout.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Copy.format(
                isChosen ? "a11y.reaction.set" : "a11y.reaction.unset",
                Copy.string(kind.copyKey)
            )
        )
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// Mark over word below `.accessibility1`, mark beside word above it.
    ///
    /// The stacked arrangement is not the vertical one grown: at accessibility sizes a centred
    /// two-line segment is a column of ragged text, while a leading mark with the word after it
    /// is the same row shape the rest of the app reflows into.
    @ViewBuilder private func content(_ kind: ReactionKind, isChosen: Bool) -> some View {
        let mark = ReactionMark(kind, isFilled: isChosen, scale: .control)
            .foregroundStyle(isChosen ? accent.mark : Palette.inkDim)
        // `Copy.string`, not `Text(kind.copyKey)`. A `Text` given a non-literal `String` takes
        // the verbatim initialiser, so the key printed itself on the card — caught by looking at
        // a screenshot, which is the only place it was visible: `CopyTests` proves the key
        // resolves and every unit test here asked `Copy` directly, so both were green.
        let word = Text(verbatim: Copy.string(kind.copyKey))
            .typeStyle(.bodyS)
            .foregroundStyle(isChosen ? Palette.ink : Palette.inkDim)
            .lineLimit(isStacked ? nil : 1)
            .multilineTextAlignment(isStacked ? .leading : .center)
        if isStacked {
            HStack(spacing: Space.sm) {
                mark
                word
                Spacer(minLength: Space.none)
            }
        } else {
            VStack(spacing: Space.xxs) {
                mark
                word
            }
        }
    }
}

/// One mark, at one of two scales, filled or not (`docs/19` §5).
///
/// Shared by all three surfaces that draw a reaction — the bar above, the flight row's read-only
/// mark, and the counts on the results card — so the glyph a kind means is decided once.
///
/// **A per-kind optical size, not one shared point size.** A `heart.fill` and a three-dot mark
/// set at the same size do not carry the same visual mass, and three marks of visibly different
/// weight is the thing that would make this look cheap. The corrections are small, deliberate,
/// and pinned by a snapshot golden — a heart reads heavy and comes down, the enclosed ellipsis
/// reads light inside its circle and goes up.
struct ReactionMark: View {

    /// How big, and it is expressed as a relationship to type rather than as points: the marks
    /// sit beside `bodyS` in the bar and beside `monoS` on the results card, and both have to
    /// grow with Dynamic Type.
    enum Scale {
        /// Inside `ReactionBar` — the thing a finger aims at.
        case control
        /// Beside a number or on a flight row — a signal, not a target.
        case mark

        var base: CGFloat {
            switch self {
            case .control: 18
            case .mark: 13
            }
        }
    }

    let kind: ReactionKind
    let isFilled: Bool
    let scale: Scale

    /// A **unit** metric rather than one per scale: `ScaledMetric`'s wrapped value has to be
    /// known at declaration, and the two bases live on `Scale`. Scaling 1pt and multiplying is
    /// the same ramp with the size left where it is readable.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    init(_ kind: ReactionKind, isFilled: Bool, scale: Scale) {
        self.kind = kind
        self.isFilled = isFilled
        self.scale = scale
    }

    var body: some View {
        Image(systemName: isFilled ? kind.filledSymbol : kind.outlineSymbol)
            .font(.system(size: scale.base * unit * kind.opticalCorrection, weight: .regular))
            // Monochrome, always. A multicolour heart is an emoji by another route, and
            // `docs/11` bans emoji in app copy for reasons that do not stop at the text.
            .symbolRenderingMode(.monochrome)
            .accessibilityHidden(true)
    }
}

extension ReactionKind {

    /// The copy-deck key for this kind's word (`docs/11`, the Reactions block).
    var copyKey: String {
        switch self {
        case .loved: "reaction.loved"
        case .interesting: "reaction.interesting"
        case .notForMe: "reaction.not_for_me"
        }
    }

    /// Unselected. An outline symbol, so the filled one below is a **shape** change and not
    /// only a colour change (`docs/12` §3).
    var outlineSymbol: String {
        switch self {
        case .loved: "heart"
        case .interesting: "ellipsis.circle"
        case .notForMe: "hand.thumbsdown"
        }
    }

    var filledSymbol: String {
        switch self {
        case .loved: "heart.fill"
        case .interesting: "ellipsis.circle.fill"
        case .notForMe: "hand.thumbsdown.fill"
        }
    }

    /// The optical correction this mark takes against the scale's base size.
    ///
    /// **`interesting` is the one that needed thinking about**, and `docs/19` §5 records the
    /// argument: the thinking beat wants an ellipsis, and both off-the-shelf ellipses are
    /// spoken for — a bare `ellipsis` **is** this app's overflow menu (`TrackLinks`), and every
    /// bubble variant draws a speech bubble on a song, which `docs/16` §1 still bans outright.
    /// The enclosure is what separates it from the ⋯ menu, and an enclosed glyph reads smaller
    /// than a bare one at the same point size, so it is the mark that scales **up**.
    var opticalCorrection: CGFloat {
        switch self {
        case .loved: 0.94
        case .interesting: 1.08
        case .notForMe: 1.0
        }
    }
}
