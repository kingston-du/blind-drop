import SwiftUI
import UIKit

/// Filling a circle: the link, the code, and the people you already play with (`E38-03`).
///
/// This used to live inside `StartGroupSheet` and **only** inside it, which meant the invite
/// affordance existed for about thirty seconds after a circle was created and never again.
/// `GroupScreen` — the screen actually called *the group* — had no way to add anybody, so an
/// existing circle could not grow: the only remaining route in was a direct invitation from
/// somebody who already shared a circle with you, and two people who have never played together
/// had none at all.
///
/// One panel, two call sites, so the two cannot drift.
@Observable @MainActor
final class InviteStore {
    private let api: APIClient

    private(set) var people: [KnownPersonDTO] = []
    private(set) var isLoadingPeople = false
    private(set) var invitingIDs = Set<String>()
    /// Invitee `user_id` → the pending invitation's id, which is all the row needs: it is what
    /// `InvitationLink.url(for:)` builds the share link from.
    ///
    /// Filled from **two** sources, and it has to be both. `invite(_:to:)` puts one here the
    /// moment the caller sends it, and `load(excluding:)` now asks the server for the ones this
    /// circle already sent — without that second source this map started empty on every launch
    /// and on every other device, so a row for somebody already invited still offered **Invite**,
    /// the server refused it with `ALREADY_INVITED`, and the row had no way to become **Share
    /// invite**: the link needs the invitation's id, and the error does not carry one.
    private(set) var invitations: [String: String] = [:]
    private(set) var failure: String?

    init(api: APIClient) {
        self.api = api
    }

    /// The shortlist, minus anybody already in this circle.
    ///
    /// `GET /groups/people-you-played-with` answers for **every** circle the caller shares with
    /// somebody, which is right for a circle that was created ten seconds ago and wrong for one
    /// that already has eleven people in it: offering to invite somebody who is standing in the
    /// room is an error the server would have to refuse (`ALREADY_IN_GROUP`), presented as a
    /// button. The filter is the client's because the endpoint is deliberately circle-agnostic —
    /// it is a shortcut derived from shared memberships, not a social graph, and giving it a
    /// group parameter would make it one.
    func load(excluding memberIDs: Set<String>, in groupID: String) async {
        isLoadingPeople = true
        defer { isLoadingPeople = false }
        do {
            // Concurrently: two independent GETs, and the shortlist is not worth a second round
            // trip's wait. Both are `retry: .twice` idempotent reads.
            async let peopleResult = api.send(Endpoint<KnownPeopleDTO>.peopleYouPlayedWith)
            async let sentResult = api.send(Endpoint<SentInvitationsDTO>.sentInvitations(for: groupID))

            let all = try await peopleResult.people
            let sent = try await sentResult.invitations

            people = all.filter { !memberIDs.contains($0.id) }
            // **Merged over, not replaced.** An invitation sent seconds ago in this session is
            // already here; a refresh whose response was assembled before it must not take the
            // row back to **Invite**, which is the flicker `GroupScreen` holds `inviteStore`
            // across refreshes precisely to avoid.
            for invitation in sent {
                invitations[invitation.invitedUser] = invitation.id
            }
            failure = nil
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    func invite(_ person: KnownPersonDTO, to groupID: String) async {
        guard !invitingIDs.contains(person.id), invitations[person.id] == nil else { return }
        invitingIDs.insert(person.id)
        failure = nil
        defer { invitingIDs.remove(person.id) }
        do {
            invitations[person.id] = try await api.send(.invitePerson(person.id, to: groupID)).id
        } catch let error as APIError {
            // A second tap after an interrupted request is still honestly represented as already
            // invited; the button remains available so the next run can show that answer.
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }
}

struct InvitePanel: View {
    /// How loud the share action is. The creation flow has no other primary and this is the
    /// point of the screen; `GroupScreen` is a leaderboard with settings under it, where a
    /// full-weight black button for a secondary errand would outrank the screen's own subject.
    enum Emphasis { case primary, quiet }

    let groupID: String
    let inviteCode: String
    let store: InviteStore
    var emphasis: Emphasis = .primary

    @State private var didCopy = false
    /// The one pending *"back to Copy"*. Held so a second copy can cancel the first — see
    /// `codeRow`.
    @State private var copyReceipt: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            linkSection
            peopleSection
            if let failure = store.failure {
                Text(LocalizedStringKey(failure))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.invite.link")
            if let url = InviteCode.inviteURL(for: inviteCode) {
                ShareLink(item: url) {
                    switch emphasis {
                    case .primary:
                        PrimaryButtonLabel("group.invite.share")
                            .primaryButtonChrome(fill: .neutral)
                    case .quiet:
                        PrimaryButtonLabel("group.invite.share")
                            .outlineButtonChrome()
                    }
                }
                .buttonStyle(.plain)
            }
            codeRow
        }
    }

    /// The code itself, under the link.
    ///
    /// Both, not one: the link is what somebody taps, and the code is what somebody **reads out**
    /// — across a table, over a call, into a message app that has eaten the link. `docs/03` §2's
    /// alphabet exists for exactly that, and a screen that only offers a URL throws the reason
    /// for the alphabet away.
    private var codeRow: some View {
        HStack(spacing: Space.sm) {
            Text(verbatim: inviteCode)
                .typeStyle(.monoM)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: Space.sm)
            Button {
                UIPasteboard.general.string = inviteCode
                didCopy = true
                // Back to **Copy** shortly. A label that says *Copied* forever starts lying the
                // moment the caller copies anything else.
                //
                // Cancelling the previous one is what keeps the receipt attached to the *last*
                // copy rather than the first. Each tap used to leave its own two-second timer
                // running, so copying twice in quick succession let the earlier timer fire a
                // fraction of a second after the second tap and take the word away while that
                // copy was still the freshest thing that had happened.
                copyReceipt?.cancel()
                copyReceipt = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    didCopy = false
                }
            } label: {
                Text(didCopy ? "group.invite.code.copied" : "group.invite.code.copy")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .minimumTouchTarget()
                    // **Snappier than SwiftUI's default.** Left alone, a `Text` whose string
                    // changes crossfades at the ambient duration, and *Copy* → *Copied* read as
                    // a slow dissolve arriving well after the tap that caused it. The word is
                    // the receipt for a copy that already happened, so it should land with the
                    // tap; a tenth of a second is fast enough to feel simultaneous and still
                    // short of a hard cut, which at this weight of text flickers.
                    .animation(.easeOut(duration: 0.1), value: didCopy)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
        .rowSurface()
        .accessibilityElement(children: .contain)
        // The alphabet has no lowercase and no `I`, `L`, `O`, `0` or `1`, so a spelled-out value
        // is the only one somebody can check against what they are about to read aloud.
        .accessibilityValue(Text(verbatim: JoinOrCreateScreen.spelled(inviteCode)))
    }

    @ViewBuilder private var peopleSection: some View {
        // **Only the first load draws a spinner** — the same rule `E28-06` applied to the group
        // itself and `GroupScreen` applies to its standings. This panel's `.task` re-runs every
        // time it reappears, so tapping a member row on The Group and coming back collapsed a
        // populated shortlist into a single `ProgressView`, jumped the name field, reveal hour
        // and Leave button up the page, and jumped them back a moment later. A list already in
        // hand stays on screen through its own refresh.
        if store.isLoadingPeople, store.people.isEmpty {
            ProgressView().tint(Palette.ink)
        } else if !store.people.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("group.invite.people")
                ListCard(data: store.people) { person in
                    personRow(person)
                }
            }
        }
        // No empty state. `group.invite.empty` said *"Nobody from another group is here yet"*,
        // which is a sentence about an absence on a panel whose link already works for anybody —
        // and on `GroupScreen` it would be a permanent apology under the leaderboard.
    }

    private func personRow(_ person: KnownPersonDTO) -> some View {
        HStack(spacing: Space.sm) {
            Text(verbatim: person.displayName)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            action(for: person)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget, alignment: .leading)
    }

    @ViewBuilder private func action(for person: KnownPersonDTO) -> some View {
        if let invitationID = store.invitations[person.id],
           let url = InvitationLink.url(for: invitationID) {
            // Invited already. The row becomes the thing worth doing next — sending them the
            // link, since a pending invitation they never open is not an invitation.
            ShareLink(item: url) {
                Text("group.invite.share")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .minimumTouchTarget()
            }
            .buttonStyle(.plain)
        } else if store.invitingIDs.contains(person.id) {
            ProgressView().tint(Palette.ink).minimumTouchTarget()
        } else {
            // Outlined, not filled. There can be a dozen of these; see `PillButton.Style`.
            PillButton("group.invite.action", style: .outlined) {
                Task { await store.invite(person, to: groupID) }
            }
        }
    }
}
