import SwiftUI

/// A screen with nothing on it yet (`docs/07` §5).
///
/// `displayM` line, `bodyM` `inkDim` line, one `PrimaryButton`.
///
/// > **Empty states are invitations, not apologies** (`docs/11`).
///
/// So there is no illustration, no shrug, and no "nothing here yet". There is a sentence saying
/// what this is and a button naming what happens next — and the button is optional, because the
/// Record's empty state before the first round has nothing to offer but the fact.
struct EmptyState: View {
    private let headline: LocalizedStringKey
    private let message: LocalizedStringKey
    private let action: Action?

    /// The one primary action an empty state may carry. One, because the layout law is one
    /// primary action per screen (`docs/07` §4) and an empty state *is* the screen.
    struct Action {
        let title: LocalizedStringKey
        let accent: PhaseAccent
        let perform: () -> Void

        init(title: LocalizedStringKey, accent: PhaseAccent, perform: @escaping () -> Void) {
            self.title = title
            self.accent = accent
            self.perform = perform
        }
    }

    init(headline: LocalizedStringKey, message: LocalizedStringKey, action: Action? = nil) {
        self.headline = headline
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text(headline)
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                PrimaryButton(action.title, accent: action.accent, action: action.perform)
                    .padding(.top, Layout.blockGap - Layout.itemGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
