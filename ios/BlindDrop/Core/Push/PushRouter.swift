import Foundation

/// An APNs payload → a `DeepLink` (`docs/05` §4, §5).
///
/// The payload carries `deep_link` beside `aps`, and it is the **same grammar** the URL scheme
/// uses — so it is parsed by the same `DeepLink` initialiser rather than by a second parser that
/// could disagree with the first about what `blinddrop://round/current/results` means.
///
/// What this type does not do is navigate. `Router.receive(_:)` holds the link, and
/// `Router.consume(session:roundIsLoaded:)` applies it **after** the round has loaded:
///
/// > *"A deep link **never** shortcuts a phase gate … A deep link is a navigation hint, not an
/// > authorization."* (`docs/05` §5)
///
/// So a `results` push tapped at 21:30 — before the answers exist — lands on the guess screen with
/// no error, because the client asks the server what phase it is and renders that.
enum PushRouter {

    /// The payload key `docs/05` §4 puts the link in.
    static let deepLinkKey = "deep_link"

    /// The link a notification points at, or `nil`.
    ///
    /// Total, like `DeepLink` itself: a payload with no link, an unrecognised one, or a value that
    /// is not a string produces nothing at all rather than a fallback to the round. A push we do
    /// not understand should open the app and leave it where it was.
    static func link(from payload: [AnyHashable: Any]) -> DeepLink? {
        link(from: payload[deepLinkKey] as? String)
    }

    /// The same, from the raw string.
    ///
    /// The delegate reaches for this one: `userInfo` is not `Sendable`, so the string is lifted out
    /// of it **before** the hop to the main actor rather than carried across as a dictionary
    /// (`docs/13` §6 — no `@unchecked` escapes, including the tempting one here).
    static func link(from raw: String?) -> DeepLink? {
        guard let raw, let url = URL(string: raw) else { return nil }
        return DeepLink(url)
    }

    /// Hands a tapped notification to the router, which holds it until the round is loaded.
    @MainActor
    static func receive(_ link: DeepLink?, into router: Router, session: SessionState) {
        router.receive(link)
        // Applied only if the round is already loaded; otherwise it stays pending and
        // `RoundStore.load()` consumes it (`docs/05` §5).
        router.consume(session: session, roundIsLoaded: false)
    }
}
