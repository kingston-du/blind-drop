import SwiftUI

/// The switcher (`E19-02`, `docs/08` §2, §6). Reached by tapping the group's name in
/// `RoundHeader`; picking a row switches the whole app to that circle.
///
/// **A row is a name and a state, and nothing else** — no artwork, no member count, no
/// progress bar, no activity, no submission count. Partly because they are clutter, and partly
/// because half of them would be `CLAUDE.md` §2.1 leaks wearing a friendly face: this sheet
/// shows every circle the caller belongs to, including ones they have not opened tonight, and a
/// submission count on any of them is exactly the fact the blind window exists to withhold.
///
/// Circles needing the caller's attention sort first, with **no visible heading** — `rows` is
/// already in that order (`CircleSwitcher`), so this view never re-sorts anything itself. The
/// order *is* the signal; a section header would turn a quiet nudge into a chore list.
struct CircleSwitcherSheet: View {
    /// Already ordered — needs-action circles first — by `CircleSwitcher`. This view does not
    /// re-derive that order, so there is exactly one place the rule lives.
    let rows: [CircleSummaryDTO]
    let activeID: String?
    let select: (String) -> Void
    let startGroup: () -> Void
    let close: () -> Void
    /// A successful in-place accept joins this circle and then uses the same switch path as a
    /// picked circle row. The sheet owns the invitation request; the routed screen owns the
    /// round invalidation that follows a circle change.
    let acceptInvitation: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    /// Loaded independently of the circles: pending invitations are not memberships and must
    /// never be folded into `CircleStore`'s list. Supplying an initial value lets snapshot tests
    /// render the real section without a network task.
    @State private var invitations: [InvitationDTO]
    @State private var invitationsFailure: String?

    /// Explicit because `typeSizeOverride` below is `fileprivate` — left off the synthesized
    /// memberwise init, that property would otherwise pull the *whole* init down to `fileprivate`
    /// with it, and `RoundScreen.swift` (a different file) is the real, production call site.
    init(
        rows: [CircleSummaryDTO],
        activeID: String?,
        select: @escaping (String) -> Void,
        startGroup: @escaping () -> Void = {},
        invitations: [InvitationDTO] = [],
        acceptInvitation: @escaping (String) -> Void = { _ in },
        close: @escaping () -> Void
    ) {
        self.rows = rows
        self.activeID = activeID
        self.select = select
        self.startGroup = startGroup
        _invitations = State(initialValue: invitations)
        self.acceptInvitation = acceptInvitation
        self.close = close
    }

    /// Stacks the row at `.accessibility1` and above (`TrackRow`'s own threshold). Below it, a
    /// name and a state word share one line the way every other row in the app does; above it,
    /// a wide `bodyLStrong` name and a `bodyM` state word fighting for the same line is what
    /// produced `Late…` and `Answe` / `rs` on two lines — a switcher whose entire job is
    /// telling two circles apart is not allowed to make the name the thing that gives.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Set only by `snapshotContent(typeSize:)`. See `effectiveTypeSize`.
    fileprivate var typeSizeOverride: DynamicTypeSize?

    /// The size to lay `row(_:)` out against.
    ///
    /// `@Environment` only resolves on a view SwiftUI itself installed — the same trap
    /// `GuessSheet.effectiveTypeSize` documents. The snapshot suite calls `snapshotContent`
    /// directly on a bare `CircleSwitcherSheet` *value*, which SwiftUI never installs, so
    /// `dynamicTypeSize` there would silently read whatever the property wrapper's default
    /// happens to be regardless of the size the suite asked to render — which is exactly how the
    /// first `-accessibility5` goldens shipped showing the `.large` single-line layout truncating
    /// names to four characters instead of the stacked one this threshold exists to draw.
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }

    /// The sheet's own height, corrected once the column has actually laid out
    /// (`.fixedSize(vertical:)` below reports the column's *ideal* height regardless of what
    /// the current detent proposes, which is what makes this settle instead of oscillating).
    /// Seeded at roughly two rows so the very first frame is not a flash of nothing — most
    /// callers have two or three circles (`CLAUDE.md` §2's cap is three).
    @State private var measuredHeight: CGFloat = Layout.buttonHeight * 2 + Layout.blockGap * 2

    var body: some View {
        column
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Width fills the sheet; height is the column's own — the trick that lets a sheet
            // suit one circle as well as three instead of guessing a fraction of the screen.
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in measuredHeight = height }
                }
            }
            .background(Palette.paper)
            .presentationDetents([.height(measuredHeight)])
            .presentationCornerRadius(Radius.sheet)
            .presentationDragIndicator(.visible)
            .task { await loadInvitations() }
    }

    /// Exposed bare for the snapshot suite, the same shape `HowToSheet.snapshotContent` takes —
    /// a golden points at the undressed column, never at a live `.sheet` presentation. Takes the
    /// size explicitly rather than trusting `@Environment` — see `effectiveTypeSize`.
    func snapshotContent(typeSize: DynamicTypeSize) -> some View {
        var copy = self
        copy.typeSizeOverride = typeSize
        return copy.column
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            closeRow
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("switcher.title")
                VStack(spacing: Space.sm) {
                    ForEach(rows) { circle in
                        row(circle)
                    }
                }
            }
            invitationSection
            OutlineButton("switcher.startGroup", action: startGroup)
        }
    }

    @ViewBuilder private var invitationSection: some View {
        // Unlike the needs-action ordering above, an invitation is not a circle yet. It earns a
        // heading precisely because sorting it into the membership list would make that fact
        // unclear. An empty successful response draws nothing — an "empty invites" card would
        // be a useless second empty state in an otherwise ordinary switcher.
        if !invitations.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("switcher.invites")
                VStack(spacing: Space.sm) {
                    ForEach(invitations) { invitation in
                        invitationRow(invitation)
                    }
                }
            }
        } else if let invitationsFailure {
            Text(LocalizedStringKey(invitationsFailure))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.alert)
        }
    }

    private var closeRow: some View {
        HStack {
            Spacer(minLength: Space.none)
            CloseButton(action: close)
        }
    }

    /// One circle: its name, its state, and — only when it wants the caller's attention — the
    /// mark. The active circle carries no visible mark of its own; `docs/08`'s checklist is
    /// explicit that a row is a name and a state and nothing else, so "this is where you are"
    /// is stated to VoiceOver (`.isSelected`) rather than drawn.
    private func row(_ circle: CircleSummaryDTO) -> some View {
        let isActive = circle.id == activeID
        let state = Copy.switcherState(circle.myState)
        let mark = Circle()
            .fill(Palette.inkDim)
            .frame(width: Space.xs, height: Space.xs)
            .opacity(circle.needsAction ? 1 : 0)

        return Button {
            select(circle.id)
        } label: {
            Group {
                if effectiveTypeSize >= .accessibility1 {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        // `.top`, not the default `.center` — a name long enough to wrap at this
                        // size must not pull the mark down into the gap between its own lines.
                        HStack(alignment: .top, spacing: Space.sm) {
                            mark
                                .padding(.top, Space.xxs)
                            Text(verbatim: circle.name)
                                .typeStyle(.bodyLStrong)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(verbatim: state)
                            .typeStyle(.bodyM)
                            .foregroundStyle(Palette.inkDim)
                    }
                } else {
                    HStack(spacing: Space.sm) {
                        // Reserved whether or not it is filled, so names line up down the column
                        // instead of the ones with a mark starting a few points further right.
                        mark
                        Text(verbatim: circle.name)
                            .typeStyle(.bodyLStrong)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Space.sm)
                        Text(verbatim: state)
                            .typeStyle(.bodyM)
                            .foregroundStyle(Palette.inkDim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.A11y.switcherRow(name: circle.name, state: state, needsAction: circle.needsAction)
        )
        .accessibilityHint(Copy.A11y.switcherRowHint)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func invitationRow(_ invitation: InvitationDTO) -> some View {
        SwitcherInvitationRow(
            invitation: invitation,
            accept: { id in acceptInvitation(id) },
            decline: { id in invitations.removeAll { $0.id == id } }
        )
    }

    private func loadInvitations() async {
        do {
            invitations = try await env.api.send(Endpoint<InvitationsDTO>.invitations).invitations
            invitationsFailure = nil
        } catch let error as APIError {
            invitationsFailure = error.copyKey
        } catch {
            invitationsFailure = APIError.unreadable.copyKey
        }
    }
}

/// One invitation in the switcher. It deliberately owns its own request state: a slow accept
/// must not disable the unrelated circles or a second invitation, and a declined row vanishes
/// without closing the sheet it came from.
private struct SwitcherInvitationRow: View {
    let invitation: InvitationDTO
    let accept: (String) -> Void
    let decline: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var failure: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(verbatim: invitation.group.name)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
            Text(verbatim: Copy.format("group.join.by", invitation.invitedBy.displayName))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
            if let failure {
                Text(LocalizedStringKey(failure))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
            }
            VStack(spacing: Space.xs) {
                PrimaryButton("group.join.action", fill: .neutral, isEnabled: !isWorking) {
                    Task { await acceptInvitation() }
                }
                OutlineButton("group.join.decline") { Task { await declineInvitation() } }
                    .disabled(isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowSurface()
    }

    private func acceptInvitation() async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            let group = try await env.api.send(.acceptInvitation(invitation.id))
            await env.circles.load()
            accept(group.id)
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    private func declineInvitation() async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            _ = try await env.api.send(.declineInvitation(invitation.id))
            decline(invitation.id)
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }
}
