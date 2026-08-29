import SwiftUI
import UIKit

/// The card at a size you can see, and the system share sheet behind it (`docs/10` §4).
///
/// > **Share tonight** on `ResultsScreen` → this sheet, showing the square-tall card →
/// > system share sheet with the rendered PNG.
///
/// **There is no variant picker here, and putting one back is a product change, not a tweak.**
/// There was one — two thumbnails, square-tall preselected — and it did not work. `preview` ends
/// in `.allowsHitTesting(false)`, and a `.buttonStyle(.plain)` button's hit region is the union of
/// its label's *hittable* subviews, so the only part of a thumbnail that answered a finger was its
/// caption text. The story caption sat some sixty points lower than the square-tall one, because
/// its thumbnail is 199 points tall against 140, which put it at the very edge of the `.medium`
/// detent: one option looked like it worked and the other looked dead. A `contentShape` would have
/// repaired the control. What actually needed deciding was whether the question was worth asking,
/// and it was not — square-tall is where this gets pasted (`docs/10` §1), and a chooser between one
/// good default and one shape almost nobody wanted charged everybody a decision to save a few
/// people a detour.
///
/// So the space two thumbnails took goes into one preview large enough to read. The sheet stops
/// asking a question and starts showing the card, which is also the only thing anybody wanted from
/// it: *is this the one I think it is, and does it look right.*
///
/// `ShareCard.Variant.story` **stays** in the model — `docs/10` §3 specifies it, the goldens draw
/// it, and `ShareRenderer` still writes and cleans up after it. Only the UI retired it.
struct ShareSheet: View {
    let content: ShareCardContent
    let renderer: ShareRenderer

    /// `docs/10` §1: *"square-tall is the default"* — and now the only shape with a way out of the
    /// app. A `let` rather than `@State`, because nothing on this sheet can change it and the
    /// declaration is the first place anybody looking for the picker will land.
    private let variant: ShareCard.Variant = .squareTall

    /// The height the sheet opens at. Written as a selection rather than left to the system's
    /// choice of the smallest detent, so that the opening size is stated here and cannot change
    /// underneath the sheet when a second detent is added.
    @State private var detent: PresentationDetent = .height(Layout.shareSheetHeight)
    @State private var sharing: ShareFile?

    var body: some View {
        panel
            .padding(Layout.screenInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        // Not `.medium`: that is half of whatever screen it is shown on, and this sheet is the
        // same size on all of them. `Layout.shareSheetHeight` fits the content instead of fitting
        // the phone; `.large` rides along so that an accessibility type size, which is the one
        // thing here that does grow, has somewhere to go rather than being clipped.
        .presentationDetents([.height(Layout.shareSheetHeight), .large], selection: $detent)
        .presentationCornerRadius(Radius.sheet)
        // Renders the card as soon as the sheet is up, so the file is already on disk by the time
        // a thumb reaches the button (`docs/10` §4: target < 250ms). Still keyed on the variant
        // although the variant is now constant: the key is what says the render belongs to the
        // shape rather than to the sheet's lifetime, and it is what would have to be right again
        // first if a second shape ever came back.
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
            // Backing out of the sheet without sharing still leaves a card on disk.
            if sharing == nil { renderer.discard() }
        }
    }

    /// The sheet without its own inset, for the goldens — the renderer applies one of its own,
    /// and two would indent the content by forty points it does not have on an SE.
    var snapshotContent: some View {
        panel
    }

    private var panel: some View {
        // No heading above the card. The deck has one string for this moment — `results.share` —
        // and it is already on the button; a title as well would be the sheet saying the same
        // thing twice (`CLAUDE.md` §6). The caption under the preview is not that title: it names
        // what the picture *is*, which the picture at this size can nearly say for itself and a
        // 184-point one could not.
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            VStack(alignment: .leading, spacing: Space.sm) {
                preview
                Text("results.share.caption")
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton("results.share", accent: .revealed, isEnabled: !renderer.isRendering) {
                Task {
                    sharing = await renderer.png(for: content, variant: variant).map(ShareFile.init)
                }
            }
        }
    }

    /// The card at about half its size, on the `paperSunk` skeleton `docs/10` §4 asks for.
    ///
    /// A live `ShareCardView` scaled down rather than the rendered PNG — the render is asynchronous
    /// and the sheet *"shows immediately with a `paperSunk` skeleton if the render is not ready"*
    /// (`docs/10` §4), so a preview that waited on the file would be the skeleton every time. The
    /// skeleton is the *background* rather than a separate loading state: the card is a live view,
    /// so it draws as soon as it can and the sunk rectangle is what is underneath it until then.
    ///
    /// Inert on purpose, and now honestly so. `.allowsHitTesting(false)` used to sit under a button
    /// and eat the taps meant for it; with nothing to tap it does the job it was written for, which
    /// is keeping a picture of a card from swallowing the drag that resizes the sheet.
    /// `.accessibilityHidden(true)` goes with it: VoiceOver reading a scaled-down card aloud is the
    /// results screen read a second time in miniature, and every word of it is already on the
    /// screen behind this one. The caption is what the sheet says.
    private var preview: some View {
        let scale = Layout.sharePreviewWidth / variant.size.width
        return ShareCardView(content: content, variant: variant)
            .scaleEffect(scale, anchor: .topLeading)
            // The scaled card still *reports* its full size, so the frame after it is what makes
            // a 360 × 600 card occupy 184 × 307.
            .frame(
                width: Layout.sharePreviewWidth,
                height: variant.size.height * scale,
                alignment: .topLeading
            )
            .background(Palette.paperSunk)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            // A hairline, not the ultramarine ring: the ring was a *selection* indicator, and with
            // one card there is no selection to indicate. An accent on the only thing on screen
            // would be decoration, which `CLAUDE.md` §2.5 does not allow it to be.
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Palette.edge, lineWidth: Stroke.border)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
