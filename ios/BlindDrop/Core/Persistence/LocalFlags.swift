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

    private enum Key {
        static let askedAboutNotifications = "flags.notifications.asked"
        static let declinedNotifications = "flags.notifications.declined"
    }
}
