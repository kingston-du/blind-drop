import SwiftUI
import UIKit
import UserNotifications

/// The two callbacks APNs only delivers to a `UIApplicationDelegate`: the device token, and a
/// tapped notification (`docs/05` §4, §5).
///
/// SwiftUI has no equivalent, so this is the smallest possible delegate — it holds no state of its
/// own and makes no decisions. `attach(_:)` hands it the environment once the app has one, which
/// is how it reaches the registrar and the router **without** a global: `CLAUDE.md` §4 allows one
/// singleton, `AppEnvironment`, and this is not a second one.
///
/// There are **no background modes** (`docs/13` §8). Nothing here wakes the app; both callbacks
/// are consequences of something the user or the system did in the foreground.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private var environment: AppEnvironment?

    /// Called from the app's scene once the environment exists.
    func attach(_ environment: AppEnvironment) {
        guard self.environment == nil else { return }
        self.environment = environment
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - The token

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await environment?.push.adopt(deviceToken: deviceToken)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Nothing to show and nothing to retry: without a token there is no `POST /devices` to
        // make, and the next launch tries again for free. A user-facing error here would be an
        // alert about a feature they may never have asked for.
    }

    // MARK: - The tap

    /// A notification the user tapped. Its `deep_link` becomes the router's **pending** link, and
    /// is applied only once the round has loaded (`docs/05` §5).
    ///
    /// `nonisolated`, because `UNNotificationResponse` and the center itself are not `Sendable` and
    /// the delegate protocol is not main-actor isolated. The link is lifted out as a `String`
    /// before the hop, so nothing non-`Sendable` crosses.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[PushRouter.deepLinkKey] as? String
        await MainActor.run {
            guard let environment else { return }
            PushRouter.receive(
                PushRouter.link(from: raw),
                into: environment.router,
                session: environment.session.state
            )
        }
    }

    /// A notification that arrived while the app was open.
    ///
    /// Shown as a banner rather than swallowed: the reveal push lands at exactly the moment a
    /// group is staring at their phones, and a member who happens to have the app open should see
    /// the same thing everybody else does. The screen behind it refetches on its own countdown.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
