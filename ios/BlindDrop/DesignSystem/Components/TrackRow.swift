import SwiftUI

/// A song in a list — search results and The Record (`docs/07` §5).
///
/// 56pt artwork · `bodyLStrong` title, one line, truncating · `bodyM` `inkDim` artist, one line
/// · an optional preview control on the trailing edge. **The whole row is the tap target**, and
/// the preview control is a nested button with its own.
///
/// The title truncates here and nowhere else in the app. A search result is a list of
/// candidates being scanned, and a wrapping title turns a scannable list into a paragraph; the
/// full title is one tap away on the confirm screen, which does not truncate. `docs/12` §1's
/// "nothing truncates" is about layouts breaking at large text — a deliberate one-line row that
/// grows with the text and truncates at its end is intact at every size.
struct TrackRow: View {
    let track: TrackDTO
    /// The preview's state, or `nil` if this row does not offer one — which is also what a
    /// track with no `preview_url` gets (`docs/06` §7: no control, never a disabled one).
    var preview: Preview?
    let action: () -> Void

    /// A row's preview control, if it has one.
    struct Preview {
        let isPlaying: Bool
        let toggle: () -> Void

        init(isPlaying: Bool, toggle: @escaping () -> Void) {
            self.isPlaying = isPlaying
            self.toggle = toggle
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                ArtworkView(track, size: artworkSize)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: track.title)
                        .typeStyle(.bodyLStrong)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(lineLimit)
                        .truncationMode(.tail)
                    Text(verbatim: track.artist)
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(lineLimit)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let preview {
                    PreviewControl(isPlaying: preview.isPlaying, accent: .revealed, action: preview.toggle)
                }
            }
            .padding(.vertical, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.A11y.track(title: track.title, artist: track.artist))
        .accessibilityHint(Copy.A11y.trackHint)
        .accessibilityAddTraits(.isButton)
    }

    /// The artwork grows with the text, capped so that at `.accessibility5` the thumbnail does
    /// not push the title off an SE. It is a thumbnail at every size; what has to stay readable
    /// is the words beside it.
    private var artworkSize: CGFloat {
        dynamicTypeSize >= .accessibility1 ? Layout.Artwork.searchRow * 1.25 : Layout.Artwork.searchRow
    }

    /// One line at the reading sizes, unbounded at the accessibility sizes.
    ///
    /// `docs/07` §5 specifies a one-line truncating row; `docs/12` §1 says nothing truncates at
    /// `.accessibility5`. Both are right about their own case and they cannot both be obeyed at
    /// once, so the row obeys each where it applies — see the open question in
    /// `tasks/E08-ios-foundation.md`. A scannable list stays scannable at the size people scan
    /// at, and somebody running `.accessibility5` gets the whole title, which is the only thing
    /// they came for.
    private var lineLimit: Int? {
        dynamicTypeSize >= .accessibility1 ? nil : 1
    }
}
