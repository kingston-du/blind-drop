import Foundation
import Security

/// Where a secret is kept between launches.
///
/// One implementation ships — `Keychain` — and the protocol exists so a test can run without
/// depending on the simulator's keychain daemon, **not** so a second real backing store can be
/// added later. `docs/14` §5 is unambiguous: refresh tokens live in the Keychain, *"never
/// `UserDefaults`, never a file."* `ios/scripts/lint.sh` rule 9 fails the build if either word
/// appears anywhere under `Core/Auth/`, so the rule is enforced rather than remembered.
///
/// `@MainActor` for the same reason `AuthService` is: the only caller is `SessionStore`, which
/// is a main-actor store, and the calls are a handful of microseconds each at launch and at
/// sign-in. Isolating the protocol is what keeps the in-memory test double a plain class
/// instead of a lock-wrapped `@unchecked Sendable` one — which `ios/scripts/lint.sh` rule 5
/// bans in the app and `docs/13` §6 bans in principle.
@MainActor
protocol SecretStore {
    func read(_ account: String) throws -> String?
    func write(_ value: String, to account: String) throws
    func delete(_ account: String) throws
}

/// A minimal `kSecClassGenericPassword` wrapper. Four `SecItem` calls, no dependency
/// (`docs/13` §1).
///
/// Every item is written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which is two
/// separate decisions:
///
/// - **`AfterFirstUnlock`**, not `WhenUnlocked`: a push arriving at 8:00 PM can wake the app
///   into a state where it has to refresh a token with the phone in a pocket. `WhenUnlocked`
///   would make that fail.
/// - **`ThisDeviceOnly`**: the refresh token is not in the iCloud Keychain backup, so restoring
///   a backup onto a second device does not hand it a live session (`docs/14` §2 — the attacker
///   with physical access is the primary one).
@MainActor
struct Keychain: SecretStore {

    /// The accounts the app stores, named once. Two call sites that spelled the same account
    /// differently would silently keep two secrets.
    enum Account {
        /// The Supabase refresh token (`docs/14` §5).
        static let refreshToken = "supabase.refresh_token"
        static let spotifyAccessToken = "spotify.access_token"
        static let spotifyRefreshToken = "spotify.refresh_token"
    }

    /// The `kSecAttrService` every item is filed under. A parameter so a test can use its own
    /// namespace and leave the app's alone.
    let service: String

    init(service: String = "app.blinddrop.auth") {
        self.service = service
    }

    func read(_ account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Update first, add if there is nothing to update. The order matters: `SecItemAdd` on an
    /// existing account fails with `errSecDuplicateItem`, and the alternative — delete then add
    /// — has a window where the token is gone and the process could be killed.
    func write(_ value: String, to account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError.status(updated) }

        var item = baseQuery(account)
        item.merge(attributes) { existing, _ in existing }
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.status(added) }
    }

    /// Deleting what is not there is a success. Sign-out must not fail because the token had
    /// already been cleared.
    func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    /// The stored item's protection class, as the raw `kSecAttrAccessible` string.
    ///
    /// This exists for one test. "The refresh token is written with
    /// `AfterFirstUnlockThisDeviceOnly`" is a `docs/14` §5 requirement, and the only way to
    /// assert it is to read the attribute back off the item that was actually written.
    func accessibility(of account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = item as? [String: Any] else {
            throw KeychainError.status(status)
        }
        return attributes[kSecAttrAccessible as String] as? String
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A `SecItem` call that did not succeed, carrying the status so a failure is diagnosable
/// rather than just "keychain error".
enum KeychainError: Error, Equatable {
    case status(OSStatus)
}
