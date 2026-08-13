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

/// Neutral, text-only utilities shown beneath sealed and results cards. Both appear when both
/// links exist; neither inherits the screen's phase accent.
struct TrackLinkButtons: View {
    let track: TrackDTO
    var opener: any TrackLinkOpening = SystemTrackLinkOpener()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: Space.xs) { buttons }
            } else {
                HStack(spacing: Space.sm) { buttons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
            if let spotify = TrackLinkDestination.spotify(track: track) {
                link("record.open.spotify") {
                    TrackLinkRouter.open(spotify, using: opener)
                }
            }
            if let apple = TrackLinkDestination.appleMusic(track: track) {
                link("record.open.apple") {
                    TrackLinkRouter.open(apple, using: opener)
                }
            }
    }

    /// A text link, set in the micro-label.
    ///
    /// These sit under a card as a footnote to it, so they are drawn as apparatus rather than as
    /// controls: two `bodyL` links under every answer would read as the screen's actions, and
    /// the screen's action is the share button at the bottom.
    private func link(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SectionLabel(title)
                .padding(.vertical, Space.sm)
                .padding(.trailing, Space.md)
                .contentShape(Rectangle())
                .frame(minHeight: Layout.minimumTouchTarget)
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
