import Foundation

/// The only source of time in the app (`docs/13` §5, AC-2). The device wall clock is not a
/// source of truth: the *value* comes from the server's `server_now` and the *elapsed time
/// since that value* comes from a monotonic uptime reading, so setting the phone to 2029
/// changes no countdown.
///
/// E08-06 implements the anchor, `sync(serverNow:)`, the optional `now`, and
/// `timeRemaining(until:)`, and widens the `Date()` lint that guards them. The shape exists
/// here in E08-01 so `AppEnvironment` and `RootView` are not rewritten for it — `RootView`
/// already invalidates on foreground, which is `docs/13` §5 rule 5 and is routing, not
/// timekeeping.
@Observable @MainActor
final class ServerClock {
    /// `docs/13` §5 rule 5: an uptime reading does not advance while the device is asleep, so
    /// the anchor is assumed stale after any background period and a refetch must precede any
    /// countdown render. A no-op until E08-06 has an anchor to drop.
    func invalidate() {}
}
