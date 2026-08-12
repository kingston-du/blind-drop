import SwiftUI

/// The sunk text field of `docs/08` §1.2: `paperSunk`, `Radius.control`, 52pt.
///
/// A component rather than a modifier repeated on four `TextField`s, because the four fields in
/// onboarding and search are the same control with different keyboards, and a screen that
/// rebuilt it would be a screen that could get the height or the radius subtly wrong.
///
/// Carries **no accent**. It is an input, not a phase.
struct InsetField: View {
    private let placeholder: LocalizedStringKey
    @Binding private var text: String
    private let style: TypeStyle
    private let alignment: TextAlignment

    /// - Parameters:
    ///   - style: `bodyL` for prose, `monoM` for the invite code (`docs/08` §1.3).
    ///   - alignment: the code field is centred; a name field is not.
    init(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        style: TypeStyle = .bodyL,
        alignment: TextAlignment = .leading
    ) {
        self.placeholder = placeholder
        self._text = text
        self.style = style
        self.alignment = alignment
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .typeStyle(style)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Palette.ink)
            .textFieldStyle(.plain)
            .padding(.horizontal, Space.lg)
            // The height is a minimum for the same reason `PrimaryButton`'s is: at
            // `.accessibility5` the field has to grow rather than clip what is typed in it.
            .frame(minHeight: Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paperSunk)
            )
    }
}
