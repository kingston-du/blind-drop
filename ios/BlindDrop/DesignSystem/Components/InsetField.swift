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
        alignment: TextAlignment = .leading,
        isFocused: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self.style = style
        self.alignment = alignment
        self.isFocused = isFocused
    }

    /// Whether the field is the one being typed into.
    ///
    /// Passed in rather than read from a `FocusState` here, because focus belongs to the screen
    /// that owns the keyboard order. What the field does with it is draw its border in `ink`
    /// instead of `edge` — a border, not a glow and not a fill change, so the control does not
    /// move or change weight when it takes focus.
    private let isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .typeStyle(style)
            .multilineTextAlignment(alignment)
            .foregroundStyle(Palette.ink)
            .textFieldStyle(.plain)
            .padding(.horizontal, Space.lg)
            // The height is a minimum for the same reason `PrimaryButton`'s is: at
            // `.accessibility5` the field has to grow rather than clip what is typed in it.
            .frame(minHeight: Layout.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(isFocused ? Palette.ink : Palette.edge, lineWidth: Stroke.border)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            )
            // Placeholder text is visually sufficient but is not consistently promoted to the
            // field's VoiceOver label across OS versions (caught by E14's live tree walk).
            .accessibilityLabel(Text(placeholder))
    }
}
