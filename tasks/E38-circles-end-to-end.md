# E38 — Circles, end to end

From an owner request of 2026-08-31, ahead of production. The whole of *join / create / invite /
more than one group* is the least-exercised surface in the app, and reading it end to end turns up
one design problem, one hole, and two pieces of jank.

**The hole is the important one.** Since ADR-011 a person may hold three circles, but every way
*into* a second one assumes they hold none. `Router` discards a `/j/<CODE>` link outright for
anybody already `.ready` — `docs/04` §3's `ALREADY_IN_GROUP` was true when a person could only be
in one circle and has not been true since — and the only field that takes a code lives inside
onboarding, behind `session == .noGroup`. The mirror of that is just as bad: `group.invite_code`
renders on `CreateGroupScreen` and `StartGroupSheet` and nowhere else, both of them creation-time,
so an existing circle has no way to grow and a person already in one can only be reached by a
direct invitation from somebody they have already played with. Two people who have never shared a
circle, both already in one, have no route to each other at all.

Nothing on the server needs to change. `POST /groups/join` has always taken a code from anybody
under the cap, and raises `ALREADY_IN_GROUP` only for the circle you are actually in
(`memberships_unique_active_pair`). This epic is four client slices.

---

### E38-01 — The switcher, remade

**Status:** wip · **Deps:** — · **Parallel:** no
**Reads:** `docs/07` §2, §4, §5, `docs/08` §2, `docs/11` (the switcher), `docs/12` §5, §6
**Touches:** `Features/Circles/CircleSwitcherSheet.swift`,
`DesignSystem/Components/{Surfaces,PillButton}.swift`, `Localizable.strings`,
`docs/11`, snapshot tests and goldens
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropSnapshotTests/CircleSwitcherSnapshots`;
simulator: the sheet with one circle, three circles, and a pending invitation.
**Proves:** —

The sheet opens with ninety points of nothing. A 44pt `✕` on a row of its own, then
`Layout.blockGap`, and only then the first word — on a sheet whose entire content is three rows.
The close button cannot simply go (`CloseButton` argues its own case: a sheet dismissable only by
a drag is unreachable to VoiceOver, Switch Control and Full Keyboard Access), so it moves into the
`YOUR GROUPS` label's row, where it costs nothing.

Below that the three row-cards become **one** list card with hairlines between rows. Three
surfaces separated by paper read as three unrelated controls; one card with rules inside it reads
as the list it is, and `Rule` already exists for exactly this — *"a hairline across a card,
between two things that belong to the same card"*.

**The active circle becomes visible.** `docs/11`'s switcher note said the row is still just a
name and a state, and the active row carried its selection only as VoiceOver's `.isSelected`; this
slice amends that, because state conveyed to one class of user and not another is an
accessibility defect rather than restraint. It is drawn as a **sunken row** — `paperSunk` inside
the white card — and not with an accent: `CLAUDE.md` §2.5 is untouched here, and the sunken
reading is also the honest one, since the active row is the single row in the list that does
nothing when tapped.

The footer's full-width `OutlineButton` becomes two equal quiet actions on one row — **Join with a
code** and **Start a group** — stacking at `.accessibility1`, on the same threshold the rows
already use so the sheet is never half-reflowed. They are alternatives of equal weight and
neither is the point of the sheet.

An invitation stops carrying a full-bleed black `PrimaryButton`. It gets `PillButton` — a new
row-level filled action, `bodyLStrong` in a pill sized to its own words — beside **Decline** as
text. The invite is worth
a card; it is not worth being the loudest thing on a screen whose job is switching.

- [ ] The close control shares the title row; no row belongs to it alone
- [ ] Circles are one list card with hairlines, not three cards
- [ ] The active row is visibly the active row, in neutrals only
- [ ] Two footer actions on one row, stacking at accessibility sizes
- [ ] An invitation's actions are row-scale
- [ ] Goldens re-recorded and looked at, one/three/invite × SE/15 Pro Max × large/a11y1/a11y5

---

### E38-02 — Join with a code, when you already have one

**Status:** todo · **Deps:** E38-01 · **Parallel:** no
**Reads:** `docs/03` §2, `docs/04` §3, `docs/05` §5, `docs/08` §1.3, `docs/11`
**Touches:** `Features/Circles/JoinCircleSheet.swift` (new), `App/Router.swift`,
`Features/Round/RoundScreen.swift`, `Localizable.strings`, `docs/05` §5, `docs/11`,
unit + snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot; simulator: join by code from the switcher,
and a `/j/<CODE>` link opened while already in a circle.
**Proves:** —

`Router.consume` drops a `.join` link on the floor for a `.ready` session. That was correct under
one circle and is a dead end under three: the code names a circle the caller is very likely
**not** in. It now routes to a sheet with the code prefilled, which is the same thing
`JoinOrCreateScreen` does for a person with no circle — *a link is a navigation hint, not an
authorization* (`docs/05` §5), so it prefills and never joins.

The sheet is also reachable by hand, from the switcher's new footer, because the common case is a
code arriving in a message rather than as a tapped link.

Errors are answered in words rather than as a generic failure: already in that circle, no such
code, and the cap. The cap's existing string says *three groups* and the cap is three — checked,
not assumed.

- [ ] A sheet that takes a code, from the switcher and from a link
- [ ] `.ready` + `.join` prefills instead of discarding
- [ ] `ALREADY_IN_GROUP`, `NOT_FOUND` and `CIRCLE_LIMIT_REACHED` each read as themselves
- [ ] Joining switches to the new circle, the same path a picked row takes

---

### E38-03 — Inviting out of a circle you already have

**Status:** todo · **Deps:** E38-01 · **Parallel:** no
**Reads:** `docs/02` §2, `docs/08` §9, `docs/11`
**Touches:** `Features/Circles/InvitePanel.swift` (new),
`Features/Onboarding/StartGroupSheet.swift`, `Features/Settings/GroupScreen.swift`,
`Localizable.strings`, `docs/08`, `docs/11`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropSnapshotTests/GroupSnapshots`;
simulator: invite from an existing circle, and the same panel after creating one.
**Proves:** —

The invite affordance exists once, inside the sheet that creates a group, and disappears the
moment that sheet closes. `GroupScreen` — the screen actually named *the group* — has no way to
add anybody. The panel is extracted from `StartGroupSheet` so both call sites are one piece of
code: the link, the code as readable text, and the people-you-played-with shortlist.

- [ ] One `InvitePanel`, two call sites
- [ ] `GroupScreen` can invite by link, by code, and from the shortlist
- [ ] The code is legible and selectable, spelled for VoiceOver

---

### E38-04 — The switch is quiet

**Status:** todo · **Deps:** — · **Parallel:** vs E38-03
**Reads:** `docs/13` §5, §7
**Touches:** `Features/Round/{RoundStore,RoundScreen}.swift`, unit tests
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropUnitTests`; simulator: switch
circles repeatedly and watch for a flash.
**Proves:** —

Switching circles shows **You're offline.** for about a second before the new round lands. It is
not a network failure: `APIClient` maps every transport error including `URLError.cancelled` to
`APIError.offline` on the argument that *"a cancelled request is a screen that went away, and
nothing renders its error"* — and on a switch the screen does not go away. The cancelled load's
failure is applied to a `.loading` state, which has no value to fall back on, so `LoadState.apply`
resolves it to `.failed` and the screen draws the error until the next load answers.

Second, smaller: **Start a group** sets `isShowingSwitcher = false` and `isStartingGroup = true`
in the same update — a dismissal racing a presentation.

- [ ] A cancelled load never becomes a rendered error
- [ ] Switching circles shows the skeleton and then the round, and nothing else
- [ ] Sheet-to-sheet handoff waits for the dismissal
