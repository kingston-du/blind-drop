import SwiftUI

/// The `✕` at the top of a sheet (`docs/08` §3.1, §3.2).
///
/// It exists because *"no gesture is the only way to do anything"* (`docs/12` §5). A sheet that
/// could only be dismissed by dragging it down is unreachable to Full Keyboard Access, to Switch
/// Control, and to anybody using VoiceOver — for whom the drag is not an available gesture at all.
///
/// Drawn as a glyph and tapped at 44pt, like every other undersized control in the app.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Font(Typography.uiFont(.bodyLStrong)))
                .foregroundStyle(Palette.inkDim)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("search.close"))
        .accessibilityAddTraits(.isButton)
    }
}
