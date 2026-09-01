import SwiftUI

/// The switcher (`E19-02`, remade in `E38-01`; `docs/08` §2, §6). Reached by tapping the group's
/// name in `RoundHeader`; picking a row switches the whole app to that circle.
///
/// **A row is a name and a state** — no artwork, no member count, no progress bar, no activity,
/// no submission count. Partly because they are clutter, and partly because half of them would
/// be `CLAUDE.md` §2.1 leaks wearing a friendly face: this sheet shows every circle the caller
/// belongs to, including ones they have not opened tonight, and a submission count on any of
/// them is exactly the fact the blind window exists to withhold.
///
/// Circles needing the caller's attention sort first, with **no visible heading** — `rows` is
/// already in that order (`CircleSwitcher`), so this view never re-sorts anything itself. The
/// order *is* the signal; a section header would turn a quiet nudge into a chore list.
///
/// **What `E38-01` changed, and why.**
///
/// The sheet used to open with ninety points of nothing: a 44pt `✕` on a row of its own, then
/// `Layout.blockGap`, and only then the first word — on a sheet whose whole content is three
/// rows. The close control could not simply go (`CloseButton` argues its own case: a sheet
/// dismissable only by a drag is unreachable to VoiceOver, Switch Control and Full Keyboard
/// Access), so it moved into the title's row, where it costs nothing.
///
/// The rows became one `ListCard` instead of three `rowSurface()` cards on paper, and the
/// active circle became **visible** rather than being announced only to VoiceOver as
/// `.isSelected`. `docs/08`'s checklist previously read *"a name and a state and nothing
/// else"*, with the active row deliberately unmarked; that is amended here, because a fact
/// stated to one class of user and withheld from another is an accessibility defect and not
/// restraint. It is drawn as a **sunken** row — `paperSunk` inside the white card — and never
/// with an accent (`CLAUDE.md` §2.5 is untouched: there is no amber and no ultramarine on this
/// sheet). Sunken is also the honest reading: the active row is the one row in the list that
/// does nothing but close the sheet.
struct CircleSwitcherSheet: View {
    /// Already ordered — needs-action circles first — by `CircleSwitcher`. This view does not
    /// re-derive that order, so there is exactly one place the rule lives.
    let rows: [CircleSummaryDTO]
    let activeID: String?
    let select: (String) -> Void
    let startGroup: () -> Void
    /// `E38-02`. The other way into a circle, and the common one: a six-character code that
    /// arrived in a message rather than as a tapped link.
    let joinWithCode: () -> Void
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
        joinWithCode: @escaping () -> Void = {},
        invitations: [InvitationDTO] = [],
        acceptInvitation: @escaping (String) -> Void = { _ in },
        close: @escaping () -> Void
    ) {
        self.rows = rows
        self.activeID = activeID
        self.select = select
        self.startGroup = startGroup
        self.joinWithCode = joinWithCode
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

    /// Above this, a row stacks and the two footer actions stack with it. One threshold for the
    /// whole sheet rather than one per block, so nothing ends up half-reflowed.
    private var isStacked: Bool { effectiveTypeSize >= .accessibility1 }

    /// One line of a row's name, at the size this sheet is being laid out against. What the
    /// needs-action mark is centred in when the row stacks.
    private var firstLineHeight: CGFloat {
        Typography.lineHeight(.bodyLStrong, for: UIContentSizeCategory(effectiveTypeSize))
    }

    /// The sheet's own height, corrected once the column has actually laid out
    /// (`.fixedSize(vertical:)` below reports the column's *ideal* height regardless of what
    /// the current detent proposes, which is what makes this settle instead of oscillating).
    /// Seeded at roughly two rows plus the footer so the very first frame is not a flash of
    /// nothing — most callers have two or three circles (`CLAUDE.md` §2's cap is three).
    @State private var measuredHeight: CGFloat = Layout.buttonHeight * 3 + Layout.blockGap

    var body: some View {
        // Scrollable only when it has to be (`.basedOnSize`). Three circles at `.large` are a
        // short, still sheet that must not rubber-band; three circles and an invitation at
        // `.accessibility5` are taller than an SE's screen, and before this they were simply
        // cut off — the detent is clamped to the screen and there was nothing underneath it to
        // scroll. `snapshotContent` stays a bare column: `ImageRenderer` draws a `ScrollView`'s
        // frame and none of its content (`SnapshotRenderer`), so a golden of this `body` would
        // be an empty rectangle.
        ScrollView {
            column
                .padding(.horizontal, Layout.screenInset)
                // Asymmetric on purpose. The drag indicator already occupies the top of the
                // sheet, so a full `blockGap` above the title row is a second gap for the same
                // job; the bottom keeps one, because below it there is only the home indicator.
                .padding(.top, Layout.itemGap)
                .padding(.bottom, Layout.blockGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Width fills the sheet; height is the column's own — the trick that lets a
                // sheet suit one circle as well as three instead of guessing a fraction of the
                // screen. Measured here, inside the scroll view, so it is the *content's*
                // height and not the height the detent has already granted.
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { measuredHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in measuredHeight = height }
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
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
            VStack(alignment: .leading, spacing: Space.sm) {
                titleRow
                ListCard(data: rows) { circle in
                    row(circle)
                }
            }
            invitationSection
            footer
        }
    }

    /// The label and the close control on one line. The label is `label`-sized apparatus and the
    /// button is a 44pt target, so the row is the button's height and the words ride in it —
    /// which is the whole saving over giving the `✕` a line of its own.
    private var titleRow: some View {
        HStack(spacing: Space.sm) {
            SectionLabel("switcher.title")
            Spacer(minLength: Space.sm)
            CloseButton(action: close)
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
                ListCard(data: invitations) { invitation in
                    invitationRow(invitation)
                }
            }
        } else if let invitationsFailure {
            Text(LocalizedStringKey(invitationsFailure))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.alert)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two ways to end up in a circle you are not in yet, side by side because neither is
    /// the point of this sheet and neither outranks the other. Somebody was sent a code; somebody
    /// else is starting their own. A single full-width `OutlineButton` for one of them and
    /// nothing at all for the other — which is what this was — made the wrong one of those two
    /// look like the answer.
    @ViewBuilder private var footer: some View {
        if isStacked {
            VStack(spacing: Space.sm) {
                OutlineButton("switcher.joinWithCode", action: joinWithCode)
                OutlineButton("switcher.startGroup", action: startGroup)
            }
        } else {
            HStack(spacing: Space.sm) {
                OutlineButton("switcher.joinWithCode", action: joinWithCode)
                OutlineButton("switcher.startGroup", action: startGroup)
            }
        }
    }

    /// One circle: its name, its state, and — only when it wants the caller's attention — the
    /// mark. The active row is drawn sunken; see the type's own note for why that is a change
    /// and why it is not an accent.
    private func row(_ circle: CircleSummaryDTO) -> some View {
        let isActive = circle.id == activeID
        let state = Copy.switcherState(circle.myState)
        // Twice the size once rows stack. A 4pt dot beside 40pt type at `.accessibility5` is a
        // speck, and the mark is the sighted reader's half of a fact VoiceOver gets as a
        // sentence (`a11y.switcher.attention`, `docs/12` §3) — it may be quiet, but it has to be
        // *there*. Two tokens rather than a ratio: the ramp is `Space`'s to own.
        let markSize = isStacked ? Space.sm : Space.xs
        let mark = Circle()
            .fill(Palette.inkDim)
            .frame(width: markSize, height: markSize)
            .opacity(circle.needsAction ? 1 : 0)

        return Button {
            select(circle.id)
        } label: {
            Group {
                if isStacked {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        // `.top`, not the default `.center` — a name long enough to wrap at this
                        // size must not pull the mark down into the gap between its own lines.
                        // The mark is then given exactly one line box of its own height, so it
                        // sits *on* the first line rather than above its cap height, where a
                        // bare `.top` leaves it looking like a stray speck.
                        HStack(alignment: .top, spacing: Space.sm) {
                            mark
                                .frame(height: firstLineHeight)
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
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget, alignment: .leading)
            // The fill is the selection. It is inside the `ListCard`'s clip, so the first and
            // last rows keep the card's corners rather than squaring them off.
            .background(isActive ? Palette.paperSunk : Palette.surface)
            .contentShape(Rectangle())
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
            isStacked: isStacked,
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
///
/// `E38-01` took the full-width black `PrimaryButton` out of it. An invitation is worth a row of
/// its own and a heading; it is not worth being the loudest thing on a sheet whose job is
/// switching between circles you are already in. `PillButton` is that action at row scale, with
/// **Decline** beside it as the text link it always should have been.
private struct SwitcherInvitationRow: View {
    let invitation: InvitationDTO
    let isStacked: Bool
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
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: Copy.format("group.join.by", invitation.invitedBy.displayName))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(LocalizedStringKey(failure))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var actions: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: Space.xs) {
                PillButton("group.join.action", isEnabled: !isWorking) {
                    Task { await acceptInvitation() }
                }
                SecondaryButton("group.join.decline", isEnabled: !isWorking) {
                    Task { await declineInvitation() }
                }
            }
        } else {
            HStack(spacing: Space.xs) {
                PillButton("group.join.action", isEnabled: !isWorking) {
                    Task { await acceptInvitation() }
                }
                SecondaryButton("group.join.decline", isEnabled: !isWorking) {
                    Task { await declineInvitation() }
                }
                Spacer(minLength: Space.none)
            }
        }
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
