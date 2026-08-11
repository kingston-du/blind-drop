import SwiftUI

/// Placeholder. E09-03 builds join-or-create (`docs/08` §1.3).
///
/// `prefilledCode` is already wired: a `blinddrop://join/<CODE>` link parks its code on the
/// router and this screen is where it lands (`docs/05` §5). The link prefills the field — it
/// does not join, because a link is a navigation hint, not an authorization.
struct JoinOrCreateScreen: View {
    let prefilledCode: String?

    var body: some View {
        Color.clear
    }
}
