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
/// restraint.
///
/// **What `E42-01` changed, and why.**
///
/// Everything on the sheet was drawn at the app's two quietest weights, so nothing on it
/// outranked anything else. Five moves, in the order they matter:
///
/// 1. **The title is a title.** `SectionLabel` is *apparatus* — an 11pt mono micro-label that
///    runs above a block. As a whole sheet's only headline it made the modal read as a fragment
///    torn off some other screen. It is `displayS` now, still sharing `CloseButton`'s line.
/// 2. **Selection is a rail, not a wash.** `paperSunk` is this app's *disabled-control* fill
///    (`docs/07` §2), so the previous design greyed out the row you were standing in — "spent",
///    where it meant "here". A 3pt `ink` rail on the leading edge says it without dulling
///    anything, and lives inside `ListCard`'s clip so the end rows keep the card's corners.
/// 3. **Name and state stop competing.** 17pt semibold against 15pt regular is barely a step,
///    which is why a state word read like a button somebody had failed to tap. The name takes
///    `displayS` and the state drops to `label` — the same mono voice as `SEALS IN 19:26:26` in
///    the header this sheet is opened from.
/// 4. **The needs-action mark moved onto the thing it is about.** A 4pt dot to the left of every
///    name, drawn at zero opacity when unset, is read as a bullet. It is now a pip beside the
///    *state*, where the fact actually lives, and the name column starts flush.
/// 5. **The footer is buttons.** Two full-width `OutlineButton`s are the *secondary* weight
///    spent twice on the two least important actions, and nothing on the sheet was at the
///    primary weight at all. They are `PillButton`s now — filled for **Join a group**, outlined
///    for **Start a group** — which is the row-scale control this file's own invitation row
///    already uses.
///
/// **The pip carries the phase, and that is a §2.5 exception.**
///
/// `CLAUDE.md` §2.5 allows one accent per screen; this sheet lists circles that are genuinely
/// in different phases at the same moment, so a phase-coloured pip puts amber and ultramarine
/// on one screen. That is an **owner call, taken deliberately** (`E42-01`), and it is bounded
/// three ways: it is `PhaseAccent.mark` and never `text` or `fill` — a mark is a signal, four
/// accent-coloured *words* would be a category colour; it is the only accent on the sheet, with
/// selection, attention and both buttons all staying neutral ink; and it is the switcher alone.
/// A future screen listing cross-circle state does not inherit it by precedent.
///
/// The pip carries **two** facts on two channels and neither is a leak: its *colour* is the
/// phase (`PhaseAccent(circle.myState)`), its *fill* is whether this circle wants you
/// (`needsAction`) — filled when it does, a ring when it does not. Both are facts about the
/// caller's own next action and nobody else's, which is what keeps `CLAUDE.md` §2.1 intact: a
/// row still cannot tell you that somebody *else* has submitted, or how many have.
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
    /// a wide `displayS` name and a `label` state word fighting for the same line is what
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

    /// The phase pip's drawn diameter, scaled alongside the `label` it sits inside rather than
    /// against the layout — see `Typography.scaled`. A pip that stayed 8pt while the words beside
    /// it tripled would be the speck the old needs-action dot was.
    private var pipSize: CGFloat {
        Typography.scaled(
            Layout.switcherPip, alongside: .label, for: UIContentSizeCategory(effectiveTypeSize)
        )
    }

    /// The gap between the pip and the word it marks, scaled the same way the pip is. A fixed
    /// 6pt looked right at `.large` and crowded at `.accessibility5`, where the word beside it
    /// is three times the size and the gap was the only thing in the row that had not moved.
    private var pipGap: CGFloat {
        Typography.scaled(
            Space.sm, alongside: .label, for: UIContentSizeCategory(effectiveTypeSize)
        )
    }

    /// One line of the state label, which is what the pip is centred in — see `stateLabel`.
    private var stateLineHeight: CGFloat {
        Typography.lineHeight(.label, for: UIContentSizeCategory(effectiveTypeSize))
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
            VStack(alignment: .leading, spacing: Space.lg) {
                titleRow
                ListCard(data: rows) { circle in
                    row(circle)
                }
            }
            invitationSection
            footer
        }
    }

    /// The title and the close control on one line. The button is a 44pt target and the title
    /// rides inside it, which is the whole saving over giving the `✕` a line of its own.
    ///
    /// `displayS` rather than `SectionLabel` — see the type's note. `docs/07` §3 rations the
    /// display face to "roughly six places in the entire app", and this is a considered spend of
    /// one of them: `displayS`'s own job description is *"a card title, a name printed as a
    /// result"*, and a sheet reached by tapping the app's own title is a card title.
    private var titleRow: some View {
        HStack(spacing: Space.sm) {
            Text("switcher.title")
                .typeStyle(.displayS)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
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

    /// The two ways to end up in a circle you are not in yet, side by side.
    ///
    /// **Ranked, where they used to be equal.** The previous note here argued that neither
    /// outranks the other, and as a statement about *importance* that is still true. It is not
    /// true about frequency: almost everybody who opens this sheet meaning to add a circle was
    /// sent a six-character code by a friend, and almost nobody starts a second group twice.
    /// So Join is `.filled(.neutral)` and Start is `.outlined` — `PillButton.Style`'s own
    /// distinction, used the way that type describes it, with the emphasis on the one there is
    /// a reason to expect.
    ///
    /// Filled is also the point. `OutlineButton` is the *secondary* weight, and with two of them
    /// there was nothing on this sheet at the primary weight at all — which is most of why a
    /// footer taking a third of the sheet still read as unpressable furniture.
    ///
    /// `.neutral` is `Palette.ink`, which `PrimaryButton.Fill` is careful to note "is not a new
    /// colour pair and not a third accent". The pip is the only accent here; a phase-filled
    /// button would put a second one on the sheet and undo the §2.5 bound the type's note sets.
    @ViewBuilder private var footer: some View {
        if isStacked {
            VStack(spacing: Space.sm) {
                joinButton
                startButton
            }
        } else {
            HStack(spacing: Space.sm) {
                joinButton
                startButton
            }
        }
    }

    /// `fillsWidth` so the pair reads as two halves of one row rather than as two lozenges of
    /// whatever width their words happened to want. Harmless stacked, where each is the only
    /// thing on its line anyway.
    ///
    /// **Filled only when nothing else on the sheet is.** With a pending invitation there are
    /// otherwise two black pills a few points apart reading *Join group* and *Join with a code* —
    /// near-identical words, identical weight, and a genuine chance of tapping the wrong one.
    /// `PillButton.Style`'s own rule settles it: *"the emphasis stays with whatever there is only
    /// one of"*. An invitation is time-sensitive and somebody is waiting on the answer; the
    /// footer is standing furniture that will still be there tomorrow. So the invitation keeps
    /// the fill and this yields it, rather than the sheet shouting twice.
    private var joinButton: some View {
        PillButton(
            "switcher.joinWithCode",
            style: invitations.isEmpty ? .filled(.neutral) : .outlined,
            fillsWidth: true,
            action: joinWithCode
        )
    }

    private var startButton: some View {
        PillButton("switcher.startGroup", style: .outlined, fillsWidth: true, action: startGroup)
    }

    /// One circle: its name, its state, and the pip on that state.
    ///
    /// The active row is marked by the **leading rail** — `Stroke.rail` of `Palette.ink`, drawn
    /// as an overlay so the row keeps `surface` underneath it. The pip is the only thing on this
    /// row that is ever an accent; the rail is neutral, and deliberately so. See the type's own
    /// note for why the rail replaced a `paperSunk` fill, and for the three bounds on the §2.5
    /// carve-out the pip spends.
    private func row(_ circle: CircleSummaryDTO) -> some View {
        let isActive = circle.id == activeID
        let state = Copy.switcherState(circle.myState)

        return Button {
            select(circle.id)
        } label: {
            Group {
                if isStacked {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(verbatim: circle.name)
                            .typeStyle(.displayS)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        stateLabel(circle, state)
                    }
                } else {
                    HStack(spacing: Space.md) {
                        Text(verbatim: circle.name)
                            .typeStyle(.displayS)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Space.sm)
                        // The name truncates and the state never does. A switcher's job is
                        // telling two circles apart, so the *name* would seem the thing to
                        // protect — but the state column is barely ninety points and has
                        // nowhere to wrap to, and a name is recoverable from a prefix in a way
                        // that `Answ` / `ers` is not.
                        stateLabel(circle, state)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .frame(
                maxWidth: .infinity, minHeight: Layout.switcherRowHeight, alignment: .leading
            )
            .background(Palette.surface)
            // The selection. Inside `ListCard`'s clip, so the first and last rows keep the
            // card's corners rather than squaring them off, and drawn as an overlay rather than
            // a fill so the active row stays as bright as the ones around it — it is the row
            // you are standing in, not a spent one.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.ink)
                    .frame(width: Stroke.rail)
                    .opacity(isActive ? 1 : 0)
            }
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

    /// The state word, and the pip that carries the phase.
    ///
    /// `label` rather than `bodyM`: at 15pt regular beside a name the state read as a second
    /// title competing with the first, and as something you might have failed to tap. In the
    /// mono micro-label it reads as a status column, in the same voice the header's
    /// `SEALS IN 19:26:26` is set in.
    ///
    /// The word carries attention in **weight** (`ink` when this circle wants you, `inkDim`
    /// otherwise) and the pip carries the phase in **colour**. Keeping those on two channels is
    /// what lets the sheet say both things at once; colouring the word instead would spend the
    /// channel attention was using and leave the pip to carry two facts alone.
    private func stateLabel(_ circle: CircleSummaryDTO, _ state: String) -> some View {
        // `.top` with the pip given exactly one line box of its own, rather than the default
        // `.center` — at `.accessibility5` the state wraps (`DROP` / `A SONG`) and a centred pip
        // floats into the gap between its two lines, reading as a bullet for a list rather than
        // as a mark on a status. Boxed this way it sits *on* the first line at every size, which
        // a bare `.top` does not do either: that pins it to the line's ascender, above the cap
        // height, where it looks like a stray speck. Same trick the old needs-action mark used
        // against the name; it belongs to the state now.
        HStack(alignment: .top, spacing: pipGap) {
            pip(for: circle)
                .frame(height: stateLineHeight)
            Text(verbatim: state)
                .typeStyle(.label)
                .foregroundStyle(circle.needsAction ? Palette.ink : Palette.inkDim)
        }
    }

    /// Filled when this circle wants the caller, a ring when it does not, and `PhaseAccent.mark`
    /// either way.
    ///
    /// `mark` is the deliberate tier — *"marks, borders, icons"*, and the one that clears 3.0:1
    /// on `surface`, which is the bar a non-text graphic has to meet. Not `text`, which would
    /// put four accent-coloured words on a sheet with no phase of its own; not `fill`, whose own
    /// note says it goes behind something and is "never a word and never a lone mark".
    ///
    /// `strokeBorder` rather than `stroke`: `stroke` straddles the path, so a 2pt ring on an 8pt
    /// circle would draw a point outside the frame it was given and sit a point closer to the
    /// word than the filled version does.
    private func pip(for circle: CircleSummaryDTO) -> some View {
        let accent = PhaseAccent(circle.myState).mark
        return Group {
            if circle.needsAction {
                Circle().fill(accent)
            } else {
                Circle().strokeBorder(accent, lineWidth: Stroke.mark)
            }
        }
        .frame(width: pipSize, height: pipSize)
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
            // `displayS`, matching a membership row above it (`E42-01`) — the two cards sit one
            // gap apart and a circle's name should not change size according to whether you are
            // already in it. It carries no pip: an invitation has no phase, because you are not
            // in the round yet.
            Text(verbatim: invitation.group.name)
                .typeStyle(.displayS)
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
