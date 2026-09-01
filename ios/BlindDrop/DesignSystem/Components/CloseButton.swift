import SwiftUI

/// The `✕` at the top of a sheet (`docs/08` §3.1, §3.2).
///
/// It exists because *"no gesture is the only way to do anything"* (`docs/12` §5). A sheet that
/// could only be dismissed by dragging it down is unreachable to Full Keyboard Access, to Switch
/// Control, and to anybody using VoiceOver — for whom the drag is not an available gesture at all.
///
/// Drawn as a glyph and tapped at 44pt, like every other undersized control in the app.
///
/// **The glyph scales with Dynamic Type** (`E38-01`). It used to ask `Typography.uiFont` for
/// `.unspecified`, which resolves against whatever trait collection happens to be current — so
/// under `ImageRenderer`, which has none, the mark stayed at its `.large` size while every word
/// around it grew, and an `.accessibility5` golden showed a control the device would not draw.
/// This is `TypeStyleModifier`'s own two lines, applied to a glyph that is set in a font rather
/// than through `typeStyle`.
struct CloseButton: View {
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let font = Typography.uiFont(.bodyLStrong, for: UIContentSizeCategory(dynamicTypeSize))
        return Button(action: action) {
            Image(systemName: "xmark")
                .font(Font(font))
                .foregroundStyle(Palette.inkDim)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("search.close"))
        .accessibilityAddTraits(.isButton)
    }
}
