# E20 — Circle creation and invitations

Today a circle is joined by typing a six-character code, and that is the only way in. It works,
it is rate-limited, and it is fine for one circle. It is not enough for someone starting their
second, who wants to pull in four people they already play with.

Two things are deliberately **not** being built. There is no Friends system — "people you've
played with" is derived from shared memberships and is a shortcut, not a graph, with no
following, no requests, and no list that exists on its own. And an invited person is **not** a
member: the pending state is real, and everything downstream must ignore it.

---

### E20-01 — Pending invitations

**Status:** done · **Deps:** E18-01 · **Parallel:** yes — against E21, E24
**Reads:** `docs/02` §2, §4, `docs/03` §2, `docs/14` §2
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/groups/`,
`server/supabase/tests/`, `ios/Fixtures/`
**Verify:** `npm run test:db`, `npm run test:functions`, `npm run audit:leak`
**Proves:** AC-3, AC-5

There is no invitation row anywhere in the schema — joining inserts a membership directly. A
pending invitation is new state, and its whole risk is the code that already exists and does not
know about it.

**A pending user is invisible to the game.** Not in the name pool, not in the minimum-submitters
count, not in `card_order`, not in standings, not in scoring, not in any push audience. Every one
of those reads memberships today and every one of them will be wrong by default. That is the
slice: not the table, the audit of everything the table touches.

Invite codes keep working. They are how a link invites someone who has no account yet, and
`E09-04` already ships the landing page for them.

- [x] Invitations as their own state, distinct from membership, with an inviter and an outcome
- [x] Accepting creates the membership atomically and respects ADR-011's cap
- [x] pgTAP proves a pending user affects nothing: name pool, minimum of three, `card_order`,
      standings, scoring, notification audience
- [x] Declining and expiry are terminal and re-invitable
- [x] Invite codes unchanged; rate limits still cover both paths
- [x] The fixture server grows the routes

---

### E20-02 — Starting a group, and filling it

**Status:** blocked · **Deps:** E20-01, E19-02 · **Parallel:** no
**Reads:** `docs/08` §1, `docs/11`, `docs/12` §2
**Touches:** `BlindDrop/Features/Onboarding/`, the switcher, `Localizable.strings`,
`docs/11-COPY-DECK.md`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot; `verify-fixture.sh` onboarding.

> **Blocked:** `npm run test:functions -- groups` cannot run because the local
> `supabase_db_blind-drop` container is unhealthy (`LegacyStatusDbNotReadyError`). Server lint
> and `deno check` pass; restore the local stack and run the function suite before closing.

**`+ Start a group`** at the foot of the switcher. Creation asks for a name and the schedule,
and then gets out of the way — the second group should cost a few taps, not a form. Timezone
defaults from the device and is fixed at creation, so it is stated rather than asked.

Then invitations, immediately, because a group with one person in it is not a group yet.
**People you've played with** lists people sharing a group with the user already: a shortcut,
ordered by nothing cleverer than recency, with no counts and no profiles attached. Alongside it,
the invite link, which is the path for anyone not on it.

An existing user opening an invite link lands on a short Join screen — the group's name, who
invited them, accept or not — never the sign-up flow they have already completed.

- [ ] `+ Start a group` in the switcher; creation is name plus schedule, then invitations
- [ ] Timezone stated, not asked; reveal hour defaulted sensibly and adjustable
- [ ] People you've played with, derived from shared groups, no standalone list
- [ ] Invite link works for new users (landing page) and existing users (Join screen)
- [ ] ADR-011's cap refused clearly at both create and accept
- [ ] Creation reachable when the user has no group at all — the onboarding path still works

---

### E20-03 — Invitations in the switcher, and the push that gets you there

**Status:** todo · **Deps:** E20-02, E23-01 · **Parallel:** no
**Reads:** `docs/05` §2, §3, `CLAUDE.md` §2.6, `docs/11`
**Touches:** `server/supabase/functions/`, `BlindDrop/Features/`, `Localizable.strings`,
`docs/05-JOBS-AND-NOTIFICATIONS.md`, `docs/11-COPY-DECK.md`
**Verify:** `npm run test:functions`; `./ios/scripts/lint.sh`; unit + snapshot. Simulator: an
invite push tapped from cold lands on the invitation.
**Proves:** AC-3

Pending invitations sit **below** the circles in the switcher, in a small Invites section — this
one gets a heading, because unlike needs-action circles it is a different kind of thing and
sorting it in would be confusing.

`invite` is a fifth notification kind and the first one not fired by `tick_rounds()`, which is
the structural reason the three-a-day rule has held: nothing else could enqueue a push. That
guarantee has to be rebuilt rather than dropped. An invite is a person acting, not a schedule
firing, so it delivers promptly — but it still counts against the user's daily budget, and a
person invited to three circles at once gets one notification.

`CLAUDE.md` §2.6 already carries the amendment. Update `docs/05` §3 to match.

- [ ] Invites section below the circles, with a heading, accept and decline in place
- [ ] `invite` added to the closed set of kinds, with the budget rule enforced in code
- [ ] Several invitations at once coalesce into one delivery
- [ ] The push deep-links to the invitation itself, cold and warm
- [ ] `docs/05` §3 updated; the count assertions there still hold
