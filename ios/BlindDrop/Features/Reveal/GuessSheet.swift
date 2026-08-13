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
/// `E11-03` takes over the pool's layout: the trailing fade that makes overflow visible, and the
/// two-row wrapping grid it becomes above `.accessibility3`. What lands here is the part `E11-02`
/// and `E11-05` need — chips that select, move and announce, and the blocked treatment that keeps
/// all of it visible when the caller cannot play.
struct GuessSheet: View {
    let store: RevealStore
    /// The height of the screen hosting this sheet. `RevealScreen` measures it once and passes
    /// it down, so the accessibility grid can honour its 40%-of-screen cap without guessing
    /// from the device model.
    var availableHeight: CGFloat? = nil
    /// **Lock in guesses** — a confirmation and a dismissal, not the only save (`docs/08` §6).
    /// `E11-06` adds the debounced save that makes that true; until then the button reports the
    /// intent and nothing is lost by it.
    var lockIn: (() -> Void)?

    private let accent = PhaseAccent.revealed

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: NamePoolLayout { NamePoolLayout(dynamicTypeSize: dynamicTypeSize) }

    var body: some View {
        sheet { pool }
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
    func content(layout: NamePoolLayout) -> some View {
        sheet {
            snapshotPool(layout: layout)
        }
    }

    /// The sheet, over whichever presentation of the pool it is handed.
    private func sheet(@ViewBuilder pool: () -> some View) -> some View {
        VStack(spacing: Layout.itemGap) {
            pool()
            if let blocked = store.blockedReason {
                blockedLine(blocked)
            } else {
                PrimaryButton("reveal.action", accent: accent, isEnabled: store.assignedCount > 0) {
                    lockIn?()
                }
                .padding(.horizontal, Layout.screenInset)
                Text(verbatim: store.progress)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .padding(.vertical, Layout.itemGap)
        .background(Palette.paper)
        .overlay(alignment: .top) {
            // The sheet is pinned over a scrolling flight, so it needs an edge. A hairline rather
            // than a shadow — there is no shadow anywhere in this app (`docs/07` §2).
            Rectangle()
                .fill(Palette.edge)
                .frame(height: Stroke.border)
        }
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
                    LinearGradient(
                        colors: [Palette.paper.opacity(0), Palette.paper],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: Layout.namePoolOverflowFadeWidth)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder private func snapshotPool(layout: NamePoolLayout) -> some View {
        if layout == .verticalGrid {
            gridChips.padding(.horizontal, Layout.screenInset)
        } else {
            chips.padding(.horizontal, Layout.screenInset)
        }
    }

    /// The names themselves.
    ///
    /// A non-submitter sees them **dimmed and inert, not gone** (`docs/08` §6): they must see
    /// exactly what they missed. `.disabled` is what stops the taps; the 0.5 is what says so; and
    /// each chip carries the reason in its own accessibility label, because a VoiceOver user
    /// arrives at a chip rather than at the container (`docs/12` §2).
    private var chips: some View {
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
        // The row takes its natural width rather than the one it is offered, so twelve chips
        // scroll instead of being squeezed onto a 375pt screen.
        .fixedSize()
        .disabled(!store.canGuess)
        .opacity(store.canGuess ? 1 : 0.5)
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
        .disabled(!store.canGuess)
        .opacity(store.canGuess ? 1 : 0.5)
    }
}
