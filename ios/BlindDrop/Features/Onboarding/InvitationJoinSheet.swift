import SwiftUI

/// A direct invitation opened by an existing account (`E20-02`). The invitation id is not
/// trusted by the client: loading the caller's own pending invitations is what proves it belongs
/// to this person before either its group or inviter is rendered.
struct InvitationJoinSheet: View {
    let invitationID: String
    let close: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var invitation: InvitationDTO?
    @State private var failure: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            HStack {
                Text("group.join.title").typeStyle(.displayM).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                CloseButton(action: finish)
            }

            if let invitation {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(verbatim: invitation.group.name).typeStyle(.displayL).foregroundStyle(Palette.ink)
                    Text(verbatim: Copy.format("group.join.by", invitation.invitedBy.displayName))
                        .typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                }
                Spacer(minLength: Space.none)
                if let failure {
                    Text(LocalizedStringKey(failure)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                }
                VStack(spacing: Space.sm) {
                    PrimaryButton("group.join.action", fill: .neutral, isEnabled: !isWorking) {
                        Task { await accept(invitation) }
                    }
                    OutlineButton("group.join.decline") { Task { await decline(invitation) } }
                        .disabled(isWorking)
                }
            } else if let failure {
                Text(LocalizedStringKey(failure)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                Spacer(minLength: Space.none)
                SecondaryButton("group.join.decline", action: finish)
            } else {
                ProgressView().tint(Palette.ink)
                Spacer(minLength: Space.none)
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Layout.blockGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.paper)
        .task { await load() }
    }

    private func load() async {
        do {
            invitation = try await env.api.send(Endpoint<InvitationsDTO>.invitations)
                .invitations.first(where: { $0.id == invitationID })
            if invitation == nil { failure = APIError.notFound.copyKey }
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    /// Guarded on re-entry, like every other async action in the app (`SettingsStore`'s own note
    /// on `turnOnNotifications` makes the argument): `isWorking` drives the buttons' disabled
    /// state, but a disabled state is applied on the next render and two taps landing in the same
    /// frame both get through it. Accepting an invitation twice is two `POST`s for a membership
    /// that only exists once.
    private func accept(_ invitation: InvitationDTO) async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            let group = try await env.api.send(.acceptInvitation(invitation.id))
            await env.circles.load()
            env.circles.select(group.id)
            finish()
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    private func decline(_ invitation: InvitationDTO) async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            _ = try await env.api.send(.declineInvitation(invitation.id))
            finish()
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    private func finish() {
        close()
        dismiss()
    }
}
