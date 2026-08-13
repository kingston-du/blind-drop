import SwiftUI
import UIKit

/// The variant picker, and the system share sheet behind it (`docs/10` §4).
///
/// > **Share tonight** on `ResultsScreen` → variant picker (two thumbnails, **square-tall
/// > preselected**) → system share sheet with the rendered PNG.
///
/// Square-tall is preselected because *"iMessage is where this actually gets pasted"*, not
/// because it is first alphabetically — which is why the default is written down here rather
/// than left to the order of `ShareCard.Variant.allCases`.
struct ShareSheet: View {
    let content: ShareCardContent
    let renderer: ShareRenderer

    /// `docs/10` §1: *"the share sheet offers both; square-tall is the default"*.
    @State private var variant: ShareCard.Variant = .squareTall
    @State private var sharing: ShareFile?

    var body: some View {
        picker
            .padding(Layout.screenInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .presentationDetents([.medium])
        .presentationCornerRadius(Radius.sheet)
        // Renders the preselected variant as soon as the sheet is up, so the common path is
        // already on disk by the time a thumb reaches the button (`docs/10` §4: target < 250ms).
        .task(id: variant) { _ = await renderer.png(for: content, variant: variant) }
        .sheet(item: $sharing) { file in
            SystemShareSheet(url: file.url) {
                // **The completion handler is where the file goes** (`docs/10` §5). Not a
                // deinit, not a timer, and not conditional on the share having happened —
                // cancelling the sheet is also the sheet dismissing.
                renderer.discard()
                sharing = nil
            }
        }
        .onDisappear {
            // Backing out of the picker without sharing still leaves a card on disk.
            if sharing == nil { renderer.discard() }
        }
    }

    /// The sheet without its own inset, for the goldens — the renderer applies one of its own,
    /// and two would indent the picker by forty points it does not have on an SE.
    var snapshotContent: some View {
        picker
    }

    private var picker: some View {
        // No heading. The deck has one string for this moment — `results.share` — and it is
        // already on the button; repeating it above two self-explanatory thumbnails would be
        // the sheet saying the same thing twice (`CLAUDE.md` §6).
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            HStack(alignment: .top, spacing: Layout.itemGap) {
                ForEach(ShareCard.Variant.allCases) { option in
                    thumbnail(option)
                }
            }

            PrimaryButton("results.share", accent: .revealed, isEnabled: !renderer.isRendering) {
                Task {
                    sharing = await renderer.png(for: content, variant: variant).map(ShareFile.init)
                }
            }
        }
    }

    /// One option: the card itself, drawn small, and the line that says where it is for.
    ///
    /// A live `ShareCardView` scaled down rather than the rendered PNG — the render is
    /// asynchronous and the picker *"shows immediately with a `paperSunk` skeleton if the render
    /// is not ready"* (`docs/10` §4), so a thumbnail that waited on the file would be the
    /// skeleton every time.
    private func thumbnail(_ option: ShareCard.Variant) -> some View {
        Button {
            variant = option
        } label: {
            VStack(alignment: .leading, spacing: Space.sm) {
                preview(option)
                Text(option.pickerLabel)
                    .typeStyle(.caption)
                    .foregroundStyle(option == variant ? Palette.ink : Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == variant ? [.isButton, .isSelected] : .isButton)
    }

    /// The card at a twelfth of its size, on the `paperSunk` skeleton `docs/10` §4 asks for.
    ///
    /// The skeleton is the *background* rather than a separate loading state: the card is a
    /// live view, so it draws as soon as it can and the sunk rectangle is what is underneath it
    /// until then. The selected one is ringed in ultramarine at `Stroke.mark`, which is the same
    /// 2pt focus indicator the reveal uses and clears the 3:1 `docs/12` §3 asks of one.
    private func preview(_ option: ShareCard.Variant) -> some View {
        let scale = Layout.shareThumbnailWidth / option.size.width
        let isSelected = option == variant
        return ShareCardView(content: content, variant: option)
            .scaleEffect(scale, anchor: .topLeading)
            // The scaled card still *reports* its full size, so the frame after it is what makes
            // a 450-point card occupy 140 points in the row.
            .frame(
                width: Layout.shareThumbnailWidth,
                height: option.size.height * scale,
                alignment: .topLeading
            )
            .background(Palette.paperSunk)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(
                        isSelected ? PhaseAccent.revealed.fill : Palette.edge,
                        lineWidth: isSelected ? Stroke.mark : Stroke.border
                    )
            )
            .allowsHitTesting(false)
    }
}

/// `UIActivityViewController`, and the one thing this app asks of it: tell us when it is gone.
///
/// The completion handler is not a nicety — it is where `docs/10` §5's *"the temporary file is
/// deleted after the share sheet dismisses"* actually happens, and `ShareRendererTests` asserts
/// the file is absent once it has run.
private struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completed: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completed() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A rendered card on its way to the share sheet.
///
/// A wrapper rather than a retroactive `Identifiable` on `URL`: conforming a standard-library
/// type to a standard-library protocol from an app target is a claim about everybody's `URL`,
/// and this only needs to be about the one being shared. Identity is the path, which carries a
/// UUID and is therefore unique per render.
private struct ShareFile: Identifiable {
    let url: URL

    init(_ url: URL) {
        self.url = url
    }

    var id: String { url.absoluteString }
}
