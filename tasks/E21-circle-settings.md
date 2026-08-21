# E21 — Circle settings and roles

`PATCH /groups/current` and `POST /groups/current/leave` have existed since `E02-03` and no
screen has ever called either. This epic gives them one, and settles what a non-admin sees.

The temptation is to invent settings. Resist it: build what the architecture already supports
and the beta actually needs. `groups.timezone` is immutable after creation by design and
`reveal_hour` is 18–21 by domain rule — neither is negotiable here.

---

### E21-01 — The circle's own screen

**Status:** done · **Deps:** E19-02 · **Parallel:** yes — against E20, E24
**Reads:** `docs/02` §1, `docs/04` §3, `docs/08` §9, §10, `docs/11`, `docs/12` §2
**Touches:** `BlindDrop/Features/Settings/`, `BlindDrop/Resources/Localizable.strings`,
`docs/11-COPY-DECK.md`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot. Simulator: as admin and as member, both
roles seen on screen, `accessibility5` and SE.

`GroupScreen` is a read-only member list today. It becomes the circle's screen: its name, when
it reveals, who is in it, and how to leave.

**Admin sees more, not different.** A member should not meet a wall of disabled controls — that
is an interface telling them what they cannot have. Admin-only actions are absent for a member,
not greyed out. Leaving is available to everyone and is the one destructive action here, so it
confirms; the copy says what happens to their history, because that is the actual question a
person has at that moment.

Renaming and changing the reveal hour are admin-only, server-enforced, and the reveal hour takes
effect on the next round that has not been created yet — say so on screen rather than letting
someone discover it tonight.

- [x] Rename, admin only, server-enforced and not merely hidden
- [x] Reveal hour 18–21, admin only, with when it takes effect stated
- [x] Members listed with their role; the list is `E24-01`'s leaderboard once that lands
- [x] Leave, for everyone, confirmed, honest about consequences
- [x] A member sees no disabled admin controls
- [x] Timezone shown, not editable, with the reason
- [x] The last admin cannot leave a circle with members still in it without the role passing on

> **Open question:** the checklist requires that the last admin cannot leave a circle with
> members still in it without the role passing on, but no promote or remove mechanism exists
> yet — that is `E21-02`. Today an admin has no way to demote themselves and no way to appoint
> a second admin, so "the last admin tries to leave a circle that still has other members" is
> unreachable through this app's own UI. Resolved the protective way (`CLAUDE.md` §1): the
> server enforces the rule anyway, in `leaveGroup()` (`server/supabase/functions/groups/index.ts`),
> failing with a new `LAST_ADMIN_MUST_TRANSFER` (409) instead of a bare `left_at` update when the
> caller is the circle's sole active admin and other active members remain. This is defensive
> and forward-looking rather than dead code: it is exactly the guard `E21-02`'s promote/remove
> work will make reachable, and building it now means that slice inherits an already-tested rule
> instead of writing one under time pressure. Covered by a Deno test in
> `server/supabase/tests/functions/groups.test.ts` and documented in `docs/04-API-CONTRACT.md`
> §3 and its error-code table. The client-side copy (`error.lastadmin`) is plain and honest if
> ever hit, with no bespoke UI flow — matching the instruction that this needed no more than that
> until `E21-02` makes it reachable.

---

### E21-02 — Who is in charge

**Status:** done · **Deps:** E21-01 · **Parallel:** no
**Reads:** `docs/03` §2, `docs/04` §3, `docs/11`, `docs/14` §2
**Touches:** `server/supabase/functions/groups/`, `server/supabase/tests/`,
`BlindDrop/Features/Settings/`, `BlindDrop/Core/Networking/`,
`BlindDrop/Resources/Localizable.strings`, `docs/04-API-CONTRACT.md`, `docs/11-COPY-DECK.md`
**Verify:** `npm run test:functions`; `./ios/scripts/lint.sh`; unit tests. Simulator: promote
and remove, from both roles.

`memberships.role` is `member` / `admin` and nothing has ever changed it after creation. The
creator is admin; there is no way to appoint a second, and no way to remove anyone.

Small and boring by design. Enough that a circle does not die when its creator loses interest,
and not one control more.

- [x] An admin may promote a member
- [x] An admin may remove a member — their past rounds stay scored, the same as leaving
- [x] An admin may not remove or demote themselves while they are the only one
- [x] Every rule enforced server-side; the UI is a convenience over it
- [x] Removal takes effect for rounds not yet created; tonight's round is not rewritten

Verified locally: a freshly created `kingston` account created a circle, promoted a second
account through the deployed local Edge Function, then removed it (204). The server suite covers
both roles, inactive/out-of-circle targets, the last-admin guard, and that removal leaves the
historical roster untouched. `npm run test:functions` passed 258/258; iPhone 17 launched against
the fixture server and the focused networking suite passed 18/18. No SE simulator was used.
