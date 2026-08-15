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
/// drawn beneath the sealed and results cards. Both cards now draw the links themselves (the
/// sealed card's corner, the results card's trailing row), so nothing calls the row form any
/// more; `record.open.spotify`/`record.open.apple` (the same "Open in …" copy) live on for The
/// Record's own overflow menu, which still wants the long form.
///
/// The sealed card's cover is one plain panel with the stamp in its lower-right (`docs/09` §2)
/// — its upper-right is genuinely empty, not space borrowed from anything else — so there it is
/// drawn as a true corner, `.overlay(alignment: .topTrailing)` from the call site. A results
/// answer card has no equivalent dead space (its title already claims the row's width), so
/// there it is a trailing row of its own instead (`FlightCard`'s `cornerLinks`) — same words,
/// same stack order, a different place to put them. Neither call draws it from inside the card
/// itself: both cards collapse their whole subtree into one VoiceOver element (`docs/12` §2),
/// and a link nested inside that collapse would be unreachable.
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

/// A Record row's overflow: only actions that can actually succeed are present.
struct TrackUtilityMenu: View {
    let track: TrackDTO
    let showResults: () -> Void
    var opener: any TrackLinkOpening = SystemTrackLinkOpener()

    var body: some View {
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
            Button("record.results", action: showResults)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Palette.inkDim)
                .minimumTouchTarget()
        }
        .accessibilityLabel(Text("record.actions"))
    }
}
