import Foundation

@Observable @MainActor
final class SettingsStore {
    var name: String
    private(set) var isSaving = false
    private(set) var isSigningOut = false
    private(set) var isDeleting = false
    private(set) var messageKey: String?
    private(set) var errorKey: String?

    private let api: APIClient
    private let session: SessionStore
    private let router: Router
    private let push: PushRegistrar
    private var savedName: String

    init(api: APIClient, session: SessionStore, router: Router, push: PushRegistrar) {
        let current = session.user?.displayName ?? ""
        self.name = current
        self.savedName = current
        self.api = api
        self.session = session
        self.router = router
        self.push = push
    }

    var cleanedName: String { DisplayName.clean(name) }
    var canSave: Bool {
        !isSaving && cleanedName != savedName && DisplayName.problem(with: name) == nil
    }

    func saveName() async {
        guard canSave else { return }
        isSaving = true
        messageKey = nil
        errorKey = nil
        defer { isSaving = false }
        do {
            _ = try await api.send(.setDisplayName(cleanedName))
            await session.loadIdentity()
            savedName = cleanedName
            messageKey = "settings.saved"
        } catch {
            errorKey = error.copyKey
        }
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        await push.unregisterCurrentDevice()
        await session.signOut()
        router.path = []
    }

    func deleteAccount(using apple: some AppleIdentityProviding) async {
        guard !isDeleting else { return }
        isDeleting = true
        errorKey = nil
        defer { isDeleting = false }

        do {
            _ = try await api.send(.deleteAccount())
            finishAccountDeletion()
        } catch APIError.reauthenticationRequired {
            do {
                let identity = try await apple.requestIdentity()
                _ = try await api.send(.deleteAccount(authorizationCode: identity.authorizationCode))
                finishAccountDeletion()
            } catch AuthError.cancelled {
                return
            } catch APIError.reauthenticationFailed {
                errorKey = "settings.delete.reauth"
            } catch let error as APIError {
                errorKey = error.copyKey
            } catch let error as AuthError {
                errorKey = error.copyKey
            } catch {
                errorKey = "error.generic"
            }
        } catch let error {
            errorKey = error.copyKey
        }
    }

    private func finishAccountDeletion() {
        push.clearDeliveredNotifications()
        session.endSession()
        router.path = []
    }
}
