import Foundation

/// The handful of facts that are about **this install** rather than about the game.
///
/// `docs/13` §7: there is no local database, and a cache of game state is a correctness hazard
/// rather than a feature. What lives here is the opposite of game state — a flag the server has no
/// opinion about and could not answer for: has this person already been asked about notifications.
///
/// It is a type rather than scattered `UserDefaults` calls so that the set of things kept on the
/// device is a list somebody can read, and so a test can hand it a scratch suite instead of
/// mutating the simulator's real defaults.
///
/// **No credential ever goes in here** (`docs/14` §5, and `ios/scripts/lint.sh` rule 9 checks the
/// directory that would): tokens live in the Keychain.
@MainActor
final class LocalFlags {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Notifications (`docs/05` §4)

    /// Whether the pre-prompt has been shown. `docs/05` §4: the ask lands **after the first
    /// successful seal**, once.
    var hasAskedAboutNotifications: Bool {
        get { defaults.bool(forKey: Key.askedAboutNotifications) }
        set { defaults.set(newValue, forKey: Key.askedAboutNotifications) }
    }

    /// Whether they said no.
    ///
    /// > *"Declining is remembered; never re-prompted in v1."* (`E10-07`)
    ///
    /// Remembered separately from having been asked, because the two answers are not the same
    /// fact: somebody who granted permission and later turned it off in Settings has been asked
    /// and has not declined us, and re-asking either of them is the behaviour `docs/05` §4 rules
    /// out when it says there are no notification settings to manage.
    var hasDeclinedNotifications: Bool {
        get { defaults.bool(forKey: Key.declinedNotifications) }
        set { defaults.set(newValue, forKey: Key.declinedNotifications) }
    }

    // MARK: - Reveal (`docs/09` §3)

    /// Whether this install has already begun the unseal for a round. The check and write live
    /// together so relaunching midway through the sequence cannot replay its haptic or covers.
    func beginUnseal(roundID: String) -> Bool {
        var seen = Set(defaults.stringArray(forKey: Key.seenUnsealRounds) ?? [])
        guard seen.insert(roundID).inserted else { return false }
        defaults.set(seen.sorted(), forKey: Key.seenUnsealRounds)
        return true
    }

    func hasSeenUnseal(roundID: String) -> Bool {
        defaults.stringArray(forKey: Key.seenUnsealRounds)?.contains(roundID) == true
    }

    // MARK: - Results (`docs/09` §4)

    /// Whether this install has already run the results name-resolve for a round.
    ///
    /// The same shape as `beginUnseal(roundID:)` and for the same reason: *"runs once per
    /// round"* has to survive a relaunch, and a check separate from its write would let two
    /// appearances in the same second both decide they were first.
    func beginResolve(roundID: String) -> Bool {
        var seen = Set(defaults.stringArray(forKey: Key.seenResolveRounds) ?? [])
        guard seen.insert(roundID).inserted else { return false }
        defaults.set(seen.sorted(), forKey: Key.seenResolveRounds)
        return true
    }

    func hasSeenResolve(roundID: String) -> Bool {
        defaults.stringArray(forKey: Key.seenResolveRounds)?.contains(roundID) == true
    }

    // MARK: - Circles (`docs/01` ADR-011, `E19-01`)

    /// The last circle the user explicitly chose (`E19-02`; this slice only reads it).
    ///
    /// Not a decision about which circles are theirs — `CircleStore` reconciles this against the
    /// server's own list on every read, so an id for a circle the user has since left is quietly
    /// ignored rather than remembered forever.
    var activeCircleID: String? {
        get { defaults.string(forKey: Key.activeCircleID) }
        set { defaults.set(newValue, forKey: Key.activeCircleID) }
    }

    private enum Key {
        static let askedAboutNotifications = "flags.notifications.asked"
        static let declinedNotifications = "flags.notifications.declined"
        static let seenUnsealRounds = "flags.reveal.seen-unseal-rounds"
        static let seenResolveRounds = "flags.results.seen-resolve-rounds"
        static let activeCircleID = "flags.circles.active-id"
    }
}
