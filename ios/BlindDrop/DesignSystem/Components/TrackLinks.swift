import SwiftUI
import UIKit

enum TrackService: String, Sendable, Equatable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
}

struct TrackLinkDestination: Sendable, Equatable {
    let service: TrackService
    let appURL: URL
    let webURL: URL

    static func spotify(track: TrackDTO) -> TrackLinkDestination? {
        guard let id = track.spotifyID, let webURL = track.spotifyURL,
              let appURL = URL(string: "spotify:track:\(id)")
        else { return nil }
        return TrackLinkDestination(service: .spotify, appURL: appURL, webURL: webURL)
    }

    static func appleMusic(track: TrackDTO) -> TrackLinkDestination? {
        var components = URLComponents(url: track.appleMusicURL, resolvingAgainstBaseURL: false)
        components?.scheme = "music"
        guard let appURL = components?.url else { return nil }
        return TrackLinkDestination(
            service: .appleMusic,
            appURL: appURL,
            webURL: track.appleMusicURL
        )
    }
}

@MainActor
protocol TrackLinkOpening {
    func canOpen(_ url: URL) -> Bool
    func open(_ url: URL)
}

@MainActor
struct SystemTrackLinkOpener: TrackLinkOpening {
    func canOpen(_ url: URL) -> Bool { UIApplication.shared.canOpenURL(url) }
    func open(_ url: URL) { UIApplication.shared.open(url) }
}

/// The app URL first, then the service's HTTPS URL. The decision is centralized so every track
/// surface follows the same fallback chain (`docs/06` §5).
@MainActor
enum TrackLinkRouter {
    static func open(_ destination: TrackLinkDestination, using opener: any TrackLinkOpening) {
        opener.open(opener.canOpen(destination.appURL) ? destination.appURL : destination.webURL)
    }
}

/// The same two links, compact and stacked, in place of a full "Open in …" row.
///
/// This replaced `TrackLinkButtons` — a text row of "Open in Spotify" / "Open in Apple Music"
/// drawn beneath the sealed and results cards. `record.open.spotify`/`record.open.apple` (the
/// same "Open in …" copy) live on for `TrackUtilityMenu`, which still wants the long form.
///
/// **One caller: the sealed card** (`SealedScreen`). Its cover is one plain panel with the stamp
/// in its lower-right (`docs/09` §2) — its upper-right is genuinely empty, not space borrowed
/// from anything else — so there it is drawn as a true corner,
/// `.overlay(alignment: .topTrailing)` from the call site, which is the case this component was
/// written for. The results answer card drew it too, as a trailing row of its own, until `E17-03`
/// weighed what that cost: two independently 44pt-tall tap targets are ~90pt of card height, and
/// a night runs to twelve cards. There it is now `TrackUtilityMenu`'s ellipsis instead — one
/// glyph in the card's top right, the same overflow The Record already uses for the same two
/// links. The sealed card keeps the corner because a sealed card is one card, and the height it
/// spends is height nothing else wanted.
///
/// The call does not draw it from inside the card: the sealed card collapses its whole subtree
/// into one VoiceOver element (`docs/12` §2), and a link nested inside that collapse would be
/// unreachable.
///
/// Apple Music first — it is the platform's own store — Spotify under it, both in `labelSmall`
/// so two lines and an arrow fit without crowding whatever they sit beside.
struct CardCornerLinks: View {
    let track: TrackDTO
    var opener: any TrackLinkOpening = SystemTrackLinkOpener()
    /// The colour the words are read in — `accent.text` on the sealed card's amber cover,
    /// `inkDim` (the default) on a white answer card, matching every other micro-label there.
    var color: Color = Palette.inkDim

    var body: some View {
        Group {
            if TrackLinkDestination.appleMusic(track: track) != nil
                || TrackLinkDestination.spotify(track: track) != nil {
                VStack(alignment: .trailing, spacing: Space.xxs) {
                    if let apple = TrackLinkDestination.appleMusic(track: track) {
                        link("link.apple") { TrackLinkRouter.open(apple, using: opener) }
                    }
                    if let spotify = TrackLinkDestination.spotify(track: track) {
                        link("link.spotify") { TrackLinkRouter.open(spotify, using: opener) }
                    }
                }
            }
        }
    }

    private func link(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xxs) {
                SectionLabel(title, color: color, style: .labelSmall)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, Space.xs)
            .contentShape(Rectangle())
            .frame(minWidth: Layout.minimumTouchTarget, minHeight: Layout.minimumTouchTarget, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// A track's overflow: only actions that can actually succeed are present.
///
/// Two callers, and what they share is more than what differs. A Record row wants the two links
/// **and** a way through to that night's results; a results answer card wants the links alone
/// (`FlightCard.linksMenu`). Everything else — the ellipsis, its `inkDim`, its 44pt region, the
/// order the services come in, the rule that a link absent from the payload is absent from the
/// menu rather than present and dead — is the same at both, and it is the sameness that is the
/// point: an ellipsis in the top right of a card should open the menu an ellipsis on a row does.
///
/// So `showResults` is **optional** rather than the menu being split into a shared inner
/// `ViewBuilder` wrapped by two shells. Extracting the items would have left the shell — the
/// `Menu`, the glyph, the touch target, the label — written twice to save writing one `Button`
/// once, and two shells drifting apart is exactly the failure this component exists to prevent.
/// What varies is one item at the end of a list, so one optional closure carries it.
///
/// The accessibility label is always applied, and only ever heard on The Record: the answer card
/// is a single VoiceOver element (`docs/12` §2) and hides this menu outright, re-exposing both
/// links as actions on the card itself.
struct TrackUtilityMenu: View {
    let track: TrackDTO
    /// The Record's *"See results"*. `nil` on a surface that is already the results — the item is
    /// absent, not disabled, for the same reason a missing link is.
    var showResults: (() -> Void)? = nil
    var opener: any TrackLinkOpening = SystemTrackLinkOpener()
    /// See `EnvironmentValues.blindDropRendersForSnapshot`.
    @Environment(\.blindDropRendersForSnapshot) private var rendersForSnapshot

    var body: some View {
        if rendersForSnapshot {
            glyph
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            if let spotify = TrackLinkDestination.spotify(track: track) {
                Button("record.open.spotify") {
                    TrackLinkRouter.open(spotify, using: opener)
                }
            }
            if let apple = TrackLinkDestination.appleMusic(track: track) {
                Button("record.open.apple") {
                    TrackLinkRouter.open(apple, using: opener)
                }
            }
            if let showResults {
                Button("record.results", action: showResults)
            }
        } label: {
            glyph
        }
        .accessibilityLabel(Text("record.actions"))
    }

    private var glyph: some View {
        Image(systemName: "ellipsis")
            .foregroundStyle(Palette.inkDim)
            .minimumTouchTarget()
    }
}
