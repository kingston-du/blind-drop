import Foundation
import UIKit
import UserNotifications

/// Notification permission and `POST /devices` (`docs/05` §4).
///
/// The timing is the product decision, and it is the only one this type makes:
///
/// > *"Permission is requested **after** the first successful seal, never at launch — the ask
/// > lands when the user has just learned that something happens at 8:00 PM and has a reason to
/// > want to be told."*
///
/// So there is no `requestAuthorization` call reachable from launch. What launch does is the
/// cheap half: if permission already exists, register with APNs and upsert the token, which
/// refreshes `last_seen_at` and costs the user nothing.
///
/// **Declining is remembered** (`LocalFlags.hasDeclinedNotifications`) and there is no second ask
/// in v1. `docs/05` §4: there are no notification settings either — three pushes a day is already
/// quiet, and a settings screen implies there is something to manage.
@Observable @MainActor
final class PushRegistrar {

    /// Whether the pre-prompt sheet is up. The **pre**-prompt: `docs/11`'s `push.permission.*`
    /// copy states exactly what will arrive before the system's one-shot dialog is spent.
    var isPrompting = false

    private let api: APIClient
    private let flags: LocalFlags
    private let center: any NotificationAuthority
    /// The APNs token, once the system has one. Held so a registration that lands before the
    /// session is ready can still be sent.
    private var deviceToken: String?

    init(api: APIClient, flags: LocalFlags, center: any NotificationAuthority = SystemNotificationAuthority()) {
        self.api = api
        self.flags = flags
        self.center = center
    }

    // MARK: - Launch

    /// Registers on every launch **if permission already exists** (`docs/05` §4: *"and again on
    /// every launch (cheap upsert, refreshes `last_seen_at`)"*).
    ///
    /// It never prompts. `authorizationStatus` is readable without asking anybody anything, which
    /// is the whole reason the check is safe to do at launch.
    func registerIfAuthorized() async {
        guard await center.isAuthorized else { return }
        center.registerForRemoteNotifications()
    }

    // MARK: - After the first seal

    /// The ask, ~1.2s after the first successful seal (`E10-07`).
    ///
    /// The delay is deliberate and it is not a hack around a presentation race: the seal has just
    /// finished, the countdown has just appeared, and a dialog on the same frame would land on top
    /// of the one moment the app is asking to be remembered for. A beat later it reads as a
    /// consequence of what just happened.
    ///
    /// Asked once, ever. A person who has already been asked — or who declined — is never asked
    /// again, whatever they have done in Settings since.
    func promptAfterFirstSeal() async {
        guard !flags.hasAskedAboutNotifications, !flags.hasDeclinedNotifications else { return }
        guard await center.isNotDetermined else {
            // Already decided at the system level (granted elsewhere, or denied). There is nothing
            // to pre-prompt for, and recording the ask keeps us from checking again next time.
            flags.hasAskedAboutNotifications = true
            return
        }
        try? await Task.sleep(for: .milliseconds(1_200))
        guard !Task.isCancelled else { return }
        isPrompting = true
    }

    /// **Turn on notifications** — the pre-prompt's primary action, which spends the system's one
    /// dialog.
    func allow() async {
        isPrompting = false
        flags.hasAskedAboutNotifications = true
        guard await center.requestAuthorization() else {
            // The system dialog was shown and refused. That is a decline, and it is remembered.
            flags.hasDeclinedNotifications = true
            return
        }
        center.registerForRemoteNotifications()
    }

    /// **Not now.** Remembered, and never asked again in v1.
    func skip() {
        isPrompting = false
        flags.hasAskedAboutNotifications = true
        flags.hasDeclinedNotifications = true
    }

    // MARK: - The token

    /// APNs handed us a token. `POST /devices` — a 204 whatever happened, with no read side, so
    /// registering tells the caller nothing (`docs/04` §2).
    func adopt(deviceToken data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        await send(token)
    }

    /// Detaches this physical device from the current account before its bearer is revoked.
    /// Best effort: signing out must still finish when the device is offline.
    func unregisterCurrentDevice() async {
        if let deviceToken {
            _ = try? await api.send(.unregisterDevice(token: deviceToken))
        }
        clearDeliveredNotifications()
    }

    func clearDeliveredNotifications() {
        center.clearDeliveredNotifications()
    }

    /// The APNs environment this build talks to (`docs/05` §4 — sandbox and production are
    /// different hosts and a token is only valid against one of them).
    ///
    /// Derived from the build configuration rather than from a runtime probe: a development build
    /// is signed with the sandbox entitlement, and every other build — TestFlight included — is
    /// production. Getting this wrong does not fail loudly; it fails as pushes that never arrive,
    /// which is why it is written down here rather than inferred at three call sites.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func send(_ token: String) async {
        _ = try? await api.send(.registerDevice(token: token, environment: Self.environment))
    }
}

/// The two questions and one command this app has for `UNUserNotificationCenter`.
///
/// A protocol because the real thing is a process-wide singleton that shows system UI: a unit test
/// that called it would either hang on a dialog or silently depend on the simulator's notification
/// state.
@MainActor
protocol NotificationAuthority: AnyObject {
    /// Whether permission already exists — readable without asking anybody anything.
    var isAuthorized: Bool { get async }
    /// Whether the user has never been asked. `false` once they have granted or denied.
    var isNotDetermined: Bool { get async }
    /// Shows the system dialog. This is the one-shot: iOS shows it once per install.
    func requestAuthorization() async -> Bool
    /// Asks APNs for a token, which arrives at the app delegate.
    func registerForRemoteNotifications()
    func clearDeliveredNotifications()
}

/// The real one.
@MainActor
final class SystemNotificationAuthority: NotificationAuthority {
    private let center = UNUserNotificationCenter.current()

    init() {}

    var isAuthorized: Bool {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional || status == .ephemeral
        }
    }

    var isNotDetermined: Bool {
        get async { await center.notificationSettings().authorizationStatus == .notDetermined }
    }

    func requestAuthorization() async -> Bool {
        // Alert, sound, badge — and no provisional option. `docs/05` §4's notifications are
        // `interruption-level: active` alerts about a thing happening now; delivering them quietly
        // would be delivering them after the moment they are about.
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func clearDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }
}
