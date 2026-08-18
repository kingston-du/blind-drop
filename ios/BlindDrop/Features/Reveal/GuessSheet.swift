import SwiftUI

/// The two presentations of the name pool. Kept as a value so the size boundary is directly
/// testable; a layout that changes only by an `if` buried in a view is exactly the kind that
/// drifts until somebody with large text has to find it.
enum NamePoolLayout: Equatable, Sendable {
    case horizontalScroll
    case verticalGrid

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize >= .accessibility3 ? .verticalGrid : .horizontalScroll
    }
}

enum CallSheetDetent: Equatable, Sendable {
    case peek
    case open
}

/// The guess apparatus pinned under the flight (`docs/08` §6): the name pool, the progress line,
/// and **Lock in guesses**.
///
/// ```
/// ├─────────────────────────────┤
/// │  Ana  Ben  Cal  Dee  Eli    │   pool, horizontally scrollable
/// │  ┌───────────────────────┐  │
/// │  │  Lock in guesses      │  │
/// │  └───────────────────────┘  │
/// │      6 of 7 assigned        │
/// └─────────────────────────────┘
/// ```
///
/// The pool becomes a vertically scrolling, two-column wrapping grid above `.accessibility3`;
/// the ordinary-size row keeps a trailing fade so its horizontal overflow is visible. Chips
/// select, move and announce, while the blocked treatment keeps the full apparatus visible when
/// the caller cannot play.
struct GuessSheet: View {
    let store: RevealStore
    /// The height of the screen hosting this sheet. `RevealScreen` measures it once and passes
    /// it down, so the accessibility grid can honour its 40%-of-screen cap without guessing
    /// from the device model.
    var availableHeight: CGFloat? = nil
    /// Optional host callback after **Lock in guesses** changes the store to its confirmed state.
    /// Saving is owned by the store and happens on every edit; this is never the only save.
    var lockIn: (() -> Void)?
    /// The sheet's two heights, reported to the host as it measures them.
    ///
    /// One value rather than two callbacks because the flight uses them together — what it must
    /// reserve, and how much of it an open sheet stands in front of — and two arrivals a frame
    /// apart would put the flight through a layout that is briefly nonsense.
    var onMetrics: ((CallSheetMetrics) -> Void)?
    /// Set only by `content(layout:typeSize:)`. See `effectiveTypeSize`.
    fileprivate var typeSizeOverride: DynamicTypeSize?
    /// The screen's bottom safe-area inset, because this sheet draws through it.
    ///
    /// The panel's surface is *supposed* to run under the home indicator — that is what removes
    /// the `paper` seam at the screen's edge (`RevealScreen`) — but its content is not, and until
    /// this existed **Lock in guesses** sat seventeen points off the bottom of the glass with the
    /// indicator drawn across it. The surface still extends; the padding this adds is what the
    /// content stops short at.
    var bottomInset: CGFloat = Space.none
    @Binding private var detent: CallSheetDetent

    private let accent = PhaseAccent.revealed

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dragOffset: CGFloat = 0
    @State private var expandedHeight: CGFloat = Layout.callSheetPeekHeight
    /// The measured height of the peek header — the exact amount of this sheet that a collapsed
    /// detent leaves on screen. See `peekHeader`.
    @State private var peekHeight: CGFloat = Layout.callSheetPeekHeight

    init(
        store: RevealStore,
        availableHeight: CGFloat? = nil,
        bottomInset: CGFloat = Space.none,
        detent: Binding<CallSheetDetent> = .constant(.open),
        onMetrics: ((CallSheetMetrics) -> Void)? = nil,
        lockIn: (() -> Void)? = nil
    ) {
        self.store = store
        self.availableHeight = availableHeight
        self.bottomInset = bottomInset
        self.onMetrics = onMetrics
        self.lockIn = lockIn
        self._detent = detent
    }

    private var metrics: CallSheetMetrics {
        CallSheetMetrics(full: expandedHeight, peek: peekHeight)
    }

    private var layout: NamePoolLayout { NamePoolLayout(dynamicTypeSize: effectiveTypeSize) }
    private var isStacked: Bool { effectiveTypeSize >= .accessibility1 }

    /// The type size to lay out against.
    ///
    /// `@Environment` is only populated on a view SwiftUI itself instantiated, and the snapshot
    /// path does not do that — it calls `content(layout:typeSize:)` on a `GuessSheet` *value*,
    /// so `dynamicTypeSize` there is whatever the property's default happens to be. It is the
    /// same trap `RevealScreen` documents for `@Namespace`, and it is why `content` has always
    /// taken the pool's layout as an argument rather than reading it. Everything else that turns
    /// on the type size has to be told the same way, or a golden labelled `accessibility5`
    /// quietly renders the `large` layout — which is exactly what the twelve-member grid did.
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }
    private var collapseDistance: CGFloat {
        max(Space.none, expandedHeight - peekHeight)
    }
    private var restingOffset: CGFloat { detent == .peek ? collapseDistance : Space.none }

    /// How much of the sheet below the header is showing, 0 at peek and 1 at open.
    ///
    /// **The pool is hidden by fading, not by arithmetic.** Sliding a fixed-height panel down by
    /// a measured amount leaves whatever the measurement was wrong by on screen, and it is always
    /// wrong by something: the header is one text size away from being a different height, the
    /// home-indicator band has to be inside the collapsed strip so the label clears it, and a
    /// spring overshoots past its resting offset by design. Every one of those showed the top of
    /// the name row through a sheet that is meant to be shut — which is the thing `E17-06`
    /// collapsed the sheet to stop, since a pool you can see while collapsed gives nobody a
    /// reason to raise it.
    ///
    /// Derived from the live offset rather than from the detent, so a drag cross-fades with the
    /// finger instead of snapping when the gesture ends.
    private var bodyOpacity: CGFloat {
        guard collapseDistance > Space.none else { return 1 }
        return max(0, min(1, 1 - (restingOffset + dragOffset) / collapseDistance))
    }

    var body: some View {
        sheet { pool }
        .frame(maxWidth: .infinity)
        // Keep one sheet alive and slide it between detents. Swapping a peek view for a full
        // view gives SwiftUI no common geometry to animate and is what caused the hard jump.
        .offset(y: restingOffset + dragOffset)
        .animation(Motion.CallSheet.spring, value: detent)
        .onChange(of: store.blockedReason) { _, reason in
            if reason != nil { setDetent(.open) }
        }
        .onChange(of: store.saveErrorKey) { _, error in
            if error != nil { setDetent(.open) }
        }
        .onAppear {
            if !canCollapse { setDetent(.open) }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { expandedHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in expandedHeight = height }
            }
        }
        // **A closure, not a `PreferenceKey`.** The measured heights used to travel up as
        // preferences and they never arrived: a `GeometryReader` in a `.background` is a
        // secondary layout branch and its preferences are not collected by the primary one, so
        // the host read the key's *default* — `Layout.callSheetPeekHeight`, for both numbers,
        // forever. Nothing looked broken, which is why it survived: the fallback happens to be a
        // plausible peek height, and `full - peek` came out as zero, which is exactly the value
        // that makes both of the things those numbers are for quietly do nothing.
        .onChange(of: metrics) { _, latest in onMetrics?(latest) }
        .onAppear { onMetrics?(metrics) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: Space.xs)
            .onChanged { value in
                guard canCollapse else { return }
                let translation = value.translation.height
                dragOffset = detent == .open
                    ? min(collapseDistance, max(0, translation))
                    : max(-collapseDistance, min(0, translation))
            }
            .onEnded { value in
                guard canCollapse else {
                    withAnimation(Motion.CallSheet.spring) { dragOffset = 0 }
                    return
                }
                let projected = value.predictedEndTranslation.height
                let threshold = max(Space.xxl, collapseDistance * 0.25)
                if detent == .open, projected > threshold {
                    setDetent(.peek)
                } else if detent == .peek, projected < -threshold {
                    setDetent(.open)
                }
                // `.animation(_:value:)` on the body is keyed to `detent`, so a drag that *does*
                // cross the threshold gets its spring for free when `setDetent` changes it above.
                // One that does not — released short of the threshold — leaves `detent` alone,
                // and an unanimated `dragOffset = 0` snapped the panel back in a single frame
                // instead of springing it, the one drag outcome the value-keyed animation cannot
                // see. Wrapping it here is what makes every release animated, committed or not.
                withAnimation(Motion.CallSheet.spring) { dragOffset = 0 }
            }
    }

    private var canCollapse: Bool {
        store.blockedReason == nil && store.saveErrorKey == nil
    }

    private func setDetent(_ value: CallSheetDetent) {
        guard value == .open || canCollapse else { return }
        if value == .peek { store.dismissSheet() }
        detent = value
    }

    private func toggleDetent() {
        setDetent(detent == .open ? .peek : .open)
    }

    /// The sheet with the pool laid out flat instead of in a scroll view.
    ///
    /// **`ImageRenderer` does not draw a `ScrollView`'s content** — not clipped, not squeezed,
    /// absent. It is the same property that made the flight's first goldens a picture of a
    /// clipped rectangle, and here it produced a blank strip where eleven chips should have been.
    /// So the snapshots render this, and the scroll container — which has no appearance of its
    /// own to verify — is the one thing the goldens do not cover. `E11-03`'s reachability test is
    /// what proves the pool actually scrolls, which is the right tool for it anyway: whether
    /// every chip can be *reached* is not a question a picture can answer.
    func content(layout: NamePoolLayout, typeSize: DynamicTypeSize = .large) -> some View {
        var copy = self
        copy.typeSizeOverride = typeSize
        return copy.sheet {
            copy.snapshotPool(layout: layout)
        }
    }

    /// The sheet, over whichever presentation of the pool it is handed.
    ///
    /// It is a panel pinned under a scrolling flight, not a presented sheet, so it has to say so
    /// itself: a white surface where the flight is `paper`, rounded at the top two corners only,
    /// a grab bar, and a hairline at the join. `docs/07` §2 rules out a shadow, and the hairline
    /// is what stops `paper` showing through a seam that is meant to be an edge.
    private func sheet(@ViewBuilder pool: () -> some View) -> some View {
        VStack(spacing: Layout.itemGap) {
            peekHeader
            VStack(spacing: Layout.itemGap) {
                pool()
                if let blocked = store.blockedReason {
                    blockedLine(blocked)
                } else {
                    action
                }
            }
            .opacity(bodyOpacity)
            // A pool at zero opacity still takes taps and still holds VoiceOver focus, and both
            // would be a control nobody can see. The half-way point is the switch because a drag
            // passes through it once, in the direction the finger is already going.
            .allowsHitTesting(bodyOpacity > 0.5)
            .accessibilityHidden(bodyOpacity <= 0.5)
        }
        // No top padding: the header carries its own, so that what a collapsed detent leaves on
        // screen is exactly one measured block and not a block plus a gap.
        .padding(.bottom, Layout.itemGap + bottomInset)
        .background(Palette.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.sheet,
                topTrailingRadius: Radius.sheet,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.edge)
                .frame(height: Stroke.border)
        }
    }

    /// The grab bar, the label and the status, as one block — and as one tap target.
    ///
    /// **This is the whole of the collapsed sheet.** It is measured rather than assumed: whatever
    /// this block is tall, that is what a peek leaves on screen, at every Dynamic Type size. The
    /// constant it replaced was 108 points against a header nearer 84, and the difference was the
    /// top of the name row showing through a sheet that is meant to be closed.
    ///
    /// It is also one control instead of two. The grabber and the heading were separate buttons
    /// doing the identical thing, which is two VoiceOver stops for one action — and the heading's
    /// `Spacer` was not part of either, so the wide empty middle of the row, which is most of it
    /// and the easiest place to hit, did nothing at all. That is the same dead-`Spacer` hit region
    /// `E17-02` found on the share sheet's thumbnails, in a second place. The toggle now sits
    /// behind the whole block with its own `contentShape`, so any point on the row works, while
    /// **Change a guess** stays a real button in front of it.
    private var peekHeader: some View {
        VStack(spacing: Space.sm) {
            Capsule()
                .fill(Palette.edgeStrong)
                .frame(width: Layout.grabber.width, height: Layout.grabber.height)
            // Two uncapped labels sharing a row is the same trap the reveal's own header falls
            // into: above `.accessibility1` *"Your call sheet"* and *"Change a guess"* each want
            // more than half the width and both letter-wrap into columns. They stack instead.
            if isStacked {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SectionLabel("reveal.callsheet")
                    trailingStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Layout.screenInset)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    SectionLabel("reveal.callsheet")
                    Spacer(minLength: Space.sm)
                    trailingStatus
                }
                .padding(.horizontal, Layout.screenInset)
            }
        }
        .padding(.top, Layout.itemGap)
        .padding(.bottom, Layout.itemGap)
        .frame(maxWidth: .infinity)
        .background {
            Button(action: toggleDetent) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCollapse)
            .accessibilityLabel(Text(
                detent == .open ? "reveal.callsheet.collapse" : "reveal.callsheet.expand"
            ))
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { peekHeight = proxy.size.height + bottomInset }
                    .onChange(of: proxy.size.height) { _, height in
                        peekHeight = height + bottomInset
                    }
                    .onChange(of: bottomInset) { _, inset in
                        peekHeight = proxy.size.height + inset
                    }
            }
        }
    }

    /// The right-hand end of the header row, which answers whichever question is live.
    ///
    /// Three things can be true there and only one at a time. **Naming No. 4** while a card is
    /// focused, because the sheet is otherwise silent about what the next tap will do — a person
    /// who taps a card, scrolls, and comes back has nothing on screen telling them which card
    /// they are still filling in. The **count** when nothing is focused, because *how much is
    /// left* is the question asked on the way to the button. And **Change a guess** once locked,
    /// where the count is spent — the flight already shows every name — and editing is the only
    /// move left (`E17-06`).
    @ViewBuilder private var trailingStatus: some View {
        if store.blockedReason != nil {
            EmptyView()
        } else if store.isLocked {
            Button {
                store.changeAGuess()
                setDetent(.open)
            } label: {
                SectionLabel("reveal.edit", color: accent.fill)
                    .frame(minHeight: Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let focused = store.focusedCard {
            SectionLabel(verbatim: Copy.format("reveal.callsheet.naming", focused), color: accent.fill)
        } else {
            SectionLabel(verbatim: store.progress, color: Palette.inkDim)
        }
    }

    @ViewBuilder private var action: some View {
        VStack(spacing: Space.sm) {
            if store.isLocked {
                PrimaryButton("reveal.action.locked", accent: accent, isEnabled: false) {}
                // **Change a guess** is in the header row now, where it is reachable without
                // opening the sheet first (`E17-06`). Repeating it here would be two controls for
                // one action on a screen whose only remaining job is to be re-read.
            } else {
                PrimaryButton("reveal.action", accent: accent, isEnabled: store.assignedCount > 0) {
                    store.lockIn()
                    lockIn?()
                }
            }
            if let errorKey = store.saveErrorKey {
                Text(LocalizedStringKey(errorKey))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.alert)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.horizontal, Layout.screenInset)
    }

    /// **The button's replacement, not an error.** `docs/08` §6: the guess apparatus stays
    /// visible and inert, and this line says why. Two sentences — what happened, and that looking
    /// is still allowed — because the second is the difference between a locked door and a
    /// window.
    private func blockedLine(_ reason: String) -> some View {
        VStack(spacing: Space.xs) {
            Text(verbatim: reason)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.ink)
            Text("reveal.blocked.canview")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Layout.screenInset)
        .accessibilityElement(children: .combine)
    }

    /// The pool. Horizontally scrollable, because twelve names do not fit on a 375pt screen and
    /// `docs/08` §6 says they scroll rather than wrap at the default sizes.
    private var pool: some View {
        Group {
            if layout == .verticalGrid {
                ScrollView(.vertical) {
                    gridChips
                        .padding(.horizontal, Layout.screenInset)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: availableHeight.map { $0 * Layout.namePoolMaximumHeightFraction }
                    ?? Layout.namePoolSnapshotMaximumHeight)
            } else {
                ScrollView(.horizontal) {
                    chips.padding(.horizontal, Layout.screenInset)
                }
                // The chips carry their own 44pt hit regions and the indicator would sit on
                // top of them. The trailing fade supplies the overflow affordance instead.
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    // `surface`, because that is what this panel is made of. It faded to `paper`
                    // — the flight's colour, not the sheet's — which drew a grey wash down the
                    // right-hand edge of a white sheet: a fade that announced itself as a fade
                    // rather than as more names.
                    LinearGradient(
                        colors: [Palette.surface.opacity(0), Palette.surface],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: Layout.namePoolOverflowFadeWidth)
                    .allowsHitTesting(false)
                }
            }
        }
        // The name pool owns its own scrolling gestures. The header is the sheet's stable,
        // full-width handle, so its drag takes precedence over the transparent toggle behind
        // it. Without that precedence the button recognizer wins and a downward swipe is
        // treated like an inert press instead of collapsing the sheet.
        .highPriorityGesture(dragGesture)
    }

    @ViewBuilder private func snapshotPool(layout: NamePoolLayout) -> some View {
        if layout == .verticalGrid {
            gridChips.padding(.horizontal, Layout.screenInset)
        } else if let sizer = store.pool.first {
            // The flat row stands in for the scroll container; it must not also stand in for its
            // width. `chips` is `.fixedSize()`, and placed straight into the sheet's stack the
            // row's width becomes the *sheet's* width — with a minimum pill width that is five
            // 72-point chips, wider than an SE, and the golden becomes a picture of a panel
            // hanging off the side of the phone with **Lock in guesses** running past the edge.
            //
            // An **overlay**, because nothing smaller works. `.clipped()` changes what is drawn,
            // not what is measured. `.frame(maxWidth: .infinity)` cannot help either: a frame
            // clamps a child that is *smaller* than the proposal, and this one is larger — an
            // `HStack` of chips that will not go under their minimum width reports the width it
            // needs and the frame reports it onward. Overlay content is the one thing that never
            // contributes to its parent's size. So the row is drawn over a single invisible chip,
            // which supplies exactly the row's height and none of its width, and the clip cuts
            // the overflow at the sheet's edge — which is what the device shows behind the fade.
            NameChip(
                member: sizer,
                displayName: store.displayNames[sizer.userID],
                state: .unused,
                action: {}
            )
            .opacity(0)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                chipRow.padding(.horizontal, Layout.screenInset)
            }
            .clipped()
        }
    }

    /// The names themselves.
    ///
    /// A non-submitter sees them **dimmed and inert, not gone** (`docs/08` §6): they must see
    /// exactly what they missed. `.disabled` is what stops the taps; the 0.5 is what says so; and
    /// each chip carries the reason in its own accessibility label, because a VoiceOver user
    /// arrives at a chip rather than at the container (`docs/12` §2).
    private var chips: some View {
        // The row takes its natural width rather than the one it is offered, so twelve chips
        // scroll instead of being squeezed onto a 375pt screen. Only inside the scroll view,
        // which is the one place that ideal width is absorbed rather than passed upward.
        chipRow.fixedSize()
    }

    private var chipRow: some View {
        HStack(spacing: Space.sm) {
            ForEach(store.pool) { member in
                NameChip(
                    member: member,
                    displayName: store.displayNames[member.userID],
                    state: store.chipState(for: member),
                    action: { store.tapName(member.userID) },
                    unavailableReason: store.blockedReason
                )
            }
        }
        .disabled(!store.canGuess || store.isLocked)
        .opacity(store.canGuess && !store.isLocked ? 1 : 0.5)
    }

    /// The large-text alternative. The task says "2-row" *and* requires a vertical scroll;
    /// those constraints only fit a two-column wrapping grid, so every name gets enough width
    /// to wrap and the pool gets the named, visible vertical scroller.
    private var gridChips: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: Layout.minimumTouchTarget), spacing: Space.sm),
                GridItem(.flexible(minimum: Layout.minimumTouchTarget), spacing: Space.sm),
            ],
            alignment: .center,
            spacing: Space.sm
        ) {
            ForEach(store.pool) { member in
                NameChip(
                    member: member,
                    displayName: store.displayNames[member.userID],
                    state: store.chipState(for: member),
                    action: { store.tapName(member.userID) },
                    unavailableReason: store.blockedReason,
                    allowsWrapping: true
                )
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(!store.canGuess || store.isLocked)
        .opacity(store.canGuess && !store.isLocked ? 1 : 0.5)
    }
}

/// What the call sheet is, in the two numbers the flight above it has to know.
///
/// `peek` is what a collapsed detent leaves on screen and what the flight permanently reserves;
/// `full - peek` is what an open one stands in front of, and therefore how much extra the flight
/// has to be able to scroll before its last card can be brought clear (`RevealScreen`). Both are
/// measured, so neither can drift away from the layout the way a shared constant does.
struct CallSheetMetrics: Equatable, Sendable {
    var full: CGFloat = Layout.callSheetPeekHeight
    var peek: CGFloat = Layout.callSheetPeekHeight

    /// How much of the flight an open sheet covers.
    var occluded: CGFloat { max(Space.none, full - peek) }
}
