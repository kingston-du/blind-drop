import SwiftUI

/// Placeholder. E10-01 onward build the phase screens; this one switches on the round's phase
/// and nothing else (`docs/13` §4).
///
/// When `RoundStore` lands (E10) it calls `router.consume(session:roundIsLoaded:)` from here
/// once the round has actually loaded — that is the "consumed only after the round loads" half
/// of `docs/05` §5.
struct RoundScreen: View {
    var body: some View {
        Color.clear
    }
}
