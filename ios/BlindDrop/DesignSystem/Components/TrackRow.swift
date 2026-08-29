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
    var attribution: String?
    /// Makes `attribution` its own tap target, opening that member's profile. `nil` (the
    /// default) leaves the name as plain text — search results and the profile screen's own
    /// track list never pass this.
    var onAttributionTap: (() -> Void)?
    /// How the row is drawn. See `Style`.
    var style: Style = .plain
    /// Whether this is the row the caller has picked. Only meaningful on `.surface`.
    var isChosen = false
    let action: (() -> Void)?

    /// The two shapes a row takes, and they are about the list rather than the row.
    ///
    /// A search result is something you **pick**, so it is drawn as its own white surface with
    /// an edge — a target. An archive entry is something you **read past**, so it is a line of
    /// text with a hairline under it. Drawing the archive as three hundred little cards would
    /// make a list nobody can scan, and drawing search results as bare lines would make a list
    /// with no targets in it.
    enum Style: Equatable, Sendable {
        case plain
        case surface
    }

    init(
        track: TrackDTO,
        preview: Preview? = nil,
        attribution: String? = nil,
        onAttributionTap: (() -> Void)? = nil,
        style: Style = .plain,
        isChosen: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.track = track
        self.preview = preview
        self.attribution = attribution
        self.onAttributionTap = onAttributionTap
        self.style = style
        self.isChosen = isChosen
        self.action = action
    }

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

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.A11y.track(title: track.title, artist: track.artist))
                .accessibilityHint(Copy.A11y.trackHint)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    attribution.map {
                        Copy.A11y.recordTrack(
                            title: track.title,
                            artist: track.artist,
                            member: $0
                        )
                    } ?? Copy.A11y.track(title: track.title, artist: track.artist)
                )
                .accessibilityAddTraits(.isStaticText)
                .accessibilityActions {
                    if let preview {
                        Button(action: preview.toggle) {
                            Text(verbatim: Copy.A11y.preview(isPlaying: preview.isPlaying))
                        }
                    }
                }
                .accessibilityChildren {
                    if let preview {
                        PreviewControl(
                            isPlaying: preview.isPlaying,
                            accent: .revealed,
                            action: preview.toggle
                        )
                    }
                    if let attribution, let onAttributionTap {
                        Button(action: onAttributionTap) {
                            Text(verbatim: attribution)
                        }
                        .accessibilityHint(Copy.string("insights.profile.hint"))
                    }
                }
        }
    }

    private var content: some View {
        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .top, spacing: Space.md) {
                        ArtworkView(track, size: artworkSize)
                        Spacer(minLength: Space.none)
                        if let preview {
                            PreviewControl(
                                isPlaying: preview.isPlaying,
                                accent: .revealed,
                                action: preview.toggle
                            )
                        }
                    }
                    metadata
                }
            } else {
                HStack(spacing: Space.md) {
                    ArtworkView(track, size: artworkSize)
                    metadata
                    // Whose song it was sits at the end of the row rather than under the artist.
                    // The archive reads as two columns — what the song was, and who is
                    // answerable for it — and a name tucked under the artist joins the wrong one.
                    if let attribution {
                        attributionText(attribution)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let preview {
                        PreviewControl(
                            isPlaying: preview.isPlaying,
                            accent: .revealed,
                            action: preview.toggle
                        )
                    }
                }
            }
        }
        .modifier(RowChrome(style: style, isChosen: isChosen))
    }

    /// The row's surface, or its absence.
    private struct RowChrome: ViewModifier {
        let style: Style
        let isChosen: Bool

        func body(content: Content) -> some View {
            switch style {
            case .plain:
                content
                    .padding(.vertical, Space.md)
                    .contentShape(Rectangle())
            case .surface:
                content
                    .rowSurface(border: isChosen ? Palette.ink : Palette.edge)
                    .contentShape(
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    )
            }
        }
    }

    private var metadata: some View {
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
            // At the accessibility sizes the row has already stacked, so the name comes back
            // under the artist where there is room for it to wrap.
            if let attribution, dynamicTypeSize >= .accessibility1 {
                attributionText(attribution)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `attribution`, plain text unless `onAttributionTap` makes it a tap target to that
    /// member's profile. The accessibility exposure for the tappable case lives in `body`'s
    /// `accessibilityChildren`, alongside the preview control — this view is what sighted users
    /// see; VoiceOver reaches the same button through the row's explicit children instead,
    /// since the row itself collapses to one element (`accessibilityElement(children: .ignore)`).
    @ViewBuilder
    private func attributionText(_ attribution: String) -> some View {
        let text = Text(verbatim: attribution)
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.ink)
        if let onAttributionTap {
            Button(action: onAttributionTap) { text }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
        } else {
            text
        }
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
