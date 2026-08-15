import SwiftUI

/// The `[?]` that opens **How to play** (`docs/08` §2, §8).
///
/// Drawn like `CloseButton` — a bare glyph, `inkDim`, tapped at 44pt — because it is chrome, not
/// a choice being offered, and `docs/07` §5 has exactly one visual language for that kind of
/// control. It carries no accent: `CLAUDE.md` §2.5 reserves amber and ultramarine for what the
/// round is doing, and an explainer is apparatus, true on every phase at once.
///
/// `questionmark.circle` rather than a bare `questionmark` — the header already sets a bare
/// glyph beside it (`RoundHeader`'s `[≡]`), and a second bare mark that close to the first reads
/// as punctuation rather than as a second control. The circle is the one place this app draws a
/// container around a glyph, and it buys legibility exactly where two glyphs would otherwise run
/// together.
struct HelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(Font(Typography.uiFont(.bodyL)))
                .foregroundStyle(Palette.inkDim)
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("howto.title"))
        .accessibilityAddTraits(.isButton)
    }
}
