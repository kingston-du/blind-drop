import SwiftUI

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
/// needs — chips that select, move and announce.
struct GuessSheet: View {
    let store: RevealStore
    /// **Lock in guesses** — a confirmation and a dismissal, not the only save (`docs/08` §6).
    /// `E11-06` adds the debounced save that makes that true; until then the button reports the
    /// intent and nothing is lost by it.
    var lockIn: (() -> Void)?

    private let accent = PhaseAccent.revealed

    var body: some View {
        VStack(spacing: Layout.itemGap) {
            pool
            PrimaryButton("reveal.action", accent: accent, isEnabled: store.assignedCount > 0) {
                lockIn?()
            }
            .padding(.horizontal, Layout.screenInset)
            Text(verbatim: store.progress)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
        }
        .padding(.vertical, Layout.itemGap)
        .background(Palette.paper)
        .overlay(alignment: .top) {
            // The pool is pinned over a scrolling flight, so it needs an edge. A hairline rather
            // than a shadow — there is no shadow anywhere in this app (`docs/07` §2).
            Rectangle()
                .fill(Palette.edge)
                .frame(height: Stroke.border)
        }
    }

    /// The pool. Horizontally scrollable, because twelve names do not fit on a 375pt screen and
    /// `docs/08` §6 says they scroll rather than wrap at the default sizes.
    private var pool: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.sm) {
                ForEach(store.pool) { member in
                    NameChip(member: member, state: store.chipState(for: member)) {
                        store.tapName(member.userID)
                    }
                }
            }
            .padding(.horizontal, Layout.screenInset)
        }
        // The chips carry their own 44pt hit regions and the indicator would sit on top of them.
        .scrollIndicators(.hidden)
        // A non-submitter sees the apparatus **disabled, not hidden** (`docs/08` §6): they must
        // see exactly what they missed. `E11-05` adds the explanatory line that replaces the
        // button and puts the reason into the labels.
        .disabled(!store.canGuess)
        .opacity(store.canGuess ? 1 : 0.5)
    }
}
