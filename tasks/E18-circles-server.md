# E18 — Multi-circle: the server foundation

Lifts ADR-005. A user may hold several active circles — the cap is ADR-011's, not this file's —
and group-scoped routes stop resolving "the caller's only one" and start naming a group
explicitly.

Read **ADR-011** in `docs/01` before starting. It records the owner's decision *and* the four
things ADR-005 was protecting that the replacement inherits. The most important: ADR-005 got
authorization for free by resolving the group from the caller. Every route that now names a
group has to prove membership of **that** group, and a non-member must get the same answer for
a real id as for an invented one. That is not a nice-to-have, it is the whole cost of the ADR.

Server only. No iOS change lands in this epic — `E19` moves the app, deliberately after, so the
two never change under each other. Keep `/groups/current` answering until `E19` has landed.

---

### E18-01 — A user may hold several circles

**Status:** todo · **Deps:** E17-10 · **Parallel:** no
**Reads:** `docs/01` ADR-011, `docs/03` §1–§2, `docs/14` §2
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/_shared/auth.ts`,
`server/supabase/functions/groups/`, `server/supabase/tests/db/`
**Verify:** `npm run test:db`, `npm run test:functions`, `npm run audit:leak`
**Proves:** AC-1

The constraint is one partial unique index — `memberships_one_active_per_user` — plus the
`maybeSingle()` in `requireMembership()` that would throw the moment a second row existed. Both
go, and ADR-011's cap replaces them.

The cap is a product number, not a schema truth: it belongs where it can be raised for the beta
without a migration, and it must fail with a named error the app can render, not a constraint
violation.

- [ ] The active-membership index replaced by ADR-011's cap, enforced where join and create
      both pass through, as one named constant
- [ ] `requireMembership` resolves a **named** group and proves the caller belongs to it;
      membership of one circle grants nothing in another
- [ ] Every group-scoped route takes the group explicitly, `/groups/current` still answering for
      the shipped app until `E19` lands
- [ ] pgTAP: a user at the cap is refused one more, with the named error
- [ ] Deno: a member of A asking for B's group, standings, record, round and results gets the
      same response as a stranger — no existence oracle in the status code or the body
- [ ] Rounds, submissions, guesses and scoring views unchanged in meaning, still keyed by circle

---

### E18-02 — What every circle needs from me right now

**Status:** todo · **Deps:** E18-01 · **Parallel:** no
**Reads:** `docs/04` §2, `docs/02` §2, `CLAUDE.md` §2.1
**Touches:** `server/supabase/functions/groups/`, `server/supabase/tests/functions/`,
`ios/Fixtures/`
**Verify:** `npm run test:functions`, `npm run audit:leak`
**Proves:** AC-1

One request that answers, for each of the caller's circles: its name, and **the caller's own
next action** — drop a song, sealed, guess, or answers. That is the entire payload the switcher
needs, and deliberately the entire payload it gets.

This is the leak-sensitive slice of the epic. The caller's own state in their own circle is
theirs to know. Anyone else's is not, and neither is anything derived from it — no submission
counts, no member counts, no "3 of 6 have dropped", no activity, no timestamps that move when
somebody else acts. `CLAUDE.md` §2.1 applies per circle, and a payload whose *length* varies
with participation fails it just as surely as one that names names.

- [ ] One endpoint returning, per circle: id, name, the caller's own state, and whether that
      state needs action
- [ ] Nothing in the payload varies with anyone else's participation during `open` — asserted,
      by a golden fixture, the way `E04-03` did it
- [ ] Ordering left to the client; the server states facts, not priorities
- [ ] The fixture server grows the same route so `E19` has something to build against

---

### E18-03 — The same song, twice, in one evening

**Status:** todo · **Deps:** E18-01 · **Parallel:** yes — against E18-02
**Reads:** `docs/02` §3, `docs/14` §2
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/rounds/`,
`server/supabase/tests/`
**Verify:** `npm run test:db`, `npm run audit:leak`

With one circle, dropping the same song twice in a day was impossible. With three, it is a
deanonymisation channel: if Ana and Ben are both in circles X and Y, and the same track appears
in both on the same night, each of them can narrow who dropped it in the other.

So the rule is narrow and it is about *inference*, not tidiness: a repeat is refused only when
the overlap in membership would let another person draw the line. No overlap, no restriction —
two strangers may pick the same song on the same night and always could.

The refusal must not itself leak. "You already used this today" tells the user something about
their own history, which is fine. It must not hint at which circle, who else is in it, or that
anybody else is involved at all.

- [ ] The overlap condition derived, not hardcoded to "any two circles"
- [ ] Refusal is a named error with copy in `docs/11`; it names no circle and no person
- [ ] pgTAP covers: no overlap (allowed), overlap (refused), same circle same day (already
      handled by replace), and the same song on consecutive days (allowed)
- [ ] The refusal path costs the same time as the success path — `leak_timing` still passes
