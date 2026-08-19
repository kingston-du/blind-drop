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

**Status:** done · **Deps:** E17-10 · **Parallel:** no
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

- [x] The active-membership index replaced by ADR-011's cap, enforced where join and create
      both pass through, as one named constant
- [x] `requireMembership` resolves a **named** group and proves the caller belongs to it;
      membership of one circle grants nothing in another
- [x] Every group-scoped route takes the group explicitly, `/groups/current` still answering for
      the shipped app until `E19` lands
- [x] pgTAP: a user at the cap is refused one more, with the named error
- [x] Deno: a member of A asking for B's group, standings, record, round and results gets the
      same response as a stranger — no existence oracle in the status code or the body
- [x] Rounds, submissions, guesses and scoring views unchanged in meaning, still keyed by circle

`memberships_one_active_per_user` is gone, replaced by `active_circle_cap()` (currently 3) and
the `memberships_circle_cap` trigger — one advisory-locked check both `POST /groups` and
`POST /groups/join` pass through via the same `memberships` insert. `requireMembership` now
takes an explicit `groupId` and returns `NOT_FOUND` for a non-member exactly as it does for a
fabricated id; `requireDefaultMembership` (oldest active circle, stable tiebreak) backs the
`current`-shaped routes the shipped app still calls. Every group-scoped route in `groups/` and
`rounds/` now has a `:group_id` sibling sharing one handler with its `current` counterpart.
`GET /rounds/{round_id}/results`'s membership check was folded into the round query itself
(caller's own circles fetched first, keyed by caller — cost is round-independent) after review
found the naive two-step version cost more when the round existed than when it didn't, an
oracle by timing even though the body and status already matched. Verified: `npm run test:db`
(624/624), `npm run test:functions` (232/232, including new `circles.test.ts`), `npm run
audit:leak` (AC-1 satisfied, timing r ≈ −0.07), `node scripts/lint.mjs` clean. Server-only, no
simulator pass applicable.

---

### E18-02 — What every circle needs from me right now

**Status:** done · **Deps:** E18-01 · **Parallel:** no
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

- [x] One endpoint returning, per circle: id, name, the caller's own state, and whether that
      state needs action
- [x] Nothing in the payload varies with anyone else's participation during `open` — asserted,
      by a golden fixture, the way `E04-03` did it
- [x] Ordering left to the client; the server states facts, not priorities
- [x] The fixture server grows the same route so `E19` has something to build against

`GET /groups` — one row per active circle, `{id, name, my_state, needs_action}`, `my_state` one
of `drop | sealed | guess | answers | voided`. `circleCallerState` (`groups/index.ts`) mirrors
`rounds/index.ts`'s `mySubmission`/`cannotGuessReason` semantics rather than reusing
`currentRoundResponse`, which loads a card list and guess sheet far past what a switcher row
needs. `activeMemberships` (new, `_shared/auth.ts`) is `requireDefaultMembership` without the
`.limit(1)` — same `joined_at`/`id` tie-break, so "oldest" means the same thing everywhere.

Review caught three real issues in the first pass, all fixed: a circle with no round yet for
today (created after its own `reveal_hour` had already passed — `ensure_rounds()` never creates
a round whose reveal is already behind it) threw a bare `Error` and 500'd the *entire* request
instead of just that row; a demo circle's state went stale because only `ensure_rounds()` was
reused from `rounds/index.ts`, never `demo_tick()`; and calling `ensure_rounds()` per circle
inside the `Promise.all` fired its whole-database sweep up to three times concurrently for one
request. Fixed: a circle with nothing to report yet is left out of the list rather than failing
the request (documented in `docs/04` §3, with a test); demo circles now tick before their row is
read; `ensure_rounds()` runs at most once per request via a shared trigger. Two tests added
alongside the fixes (joined-late, and the reveal-hour-passed omission), plus the golden-shape
assertion now goes through `circleSummaryFields()` instead of a hand-typed key list.

Verified: `npm run test:db` (632/632), `npm run test:functions` (245/245, including the new
`circle_switcher.test.ts`), `npm run audit:leak` (AC-1 satisfied, timing r ≈ −0.10),
`node scripts/lint.mjs` clean. Server-only; no simulator pass applicable.

---

### E18-03 — The same song, twice, in one evening

**Status:** done · **Deps:** E18-01 · **Parallel:** yes — against E18-02
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

- [x] The overlap condition derived, not hardcoded to "any two circles"
- [x] Refusal is a named error with copy in `docs/11`; it names no circle and no person
- [x] pgTAP covers: no overlap (allowed), overlap (refused), same circle same day (already
      handled by replace), and the same song on consecutive days (allowed)
- [x] The refusal path costs the same time as the success path — `leak_timing` still passes

The check lives inside `upsert_submission` itself (`20260819090000_track_reuse_overlap.sql`),
the one place every submission — first drop or replace — already passes through. Before every
insert it looks up the round's `group_id`/`local_date`, takes the same advisory-lock discipline
`enforce_circle_cap` established (a distinct key, so the two invariants never contend), and
runs one `exists` query, unconditionally, on both the accepted and the refused path: does this
user already have a submission with this `track_key` tonight (`r.local_date` equal, `r.group_id`
different), in a circle that shares an *active* member — other than the submitter — with this
one? Same circle same night never reaches the check at all (`r.group_id <> v_group_id` excludes
it by construction), which is what makes it a plain replace rather than a case the rule has an
opinion about. Different night always clears it, overlap or not — the channel this closes is
"tonight," not "ever."

New error code `TRACK_ALREADY_USED` (`BD003`, `_shared/db.ts` + `_shared/http.ts`), copy
"You already used this today." (`docs/11`, `docs/04` §1). `rounds/index.ts`'s `submitTrack`
maps BD003 to it; every other database error still falls through to `dbFailure`/`INTERNAL`
unchanged. `docs/02` §3's "a duplicate track is never rejected" is unchanged for what it always
meant — two *different* people in one round — and the header comment there now says so
explicitly, so the two rules don't read as contradicting each other.

New pgTAP suite `tests/db/track_reuse.sql` (9 assertions): a no-overlap pair (West/East, sharing
only the submitter) allows the repeat; an overlapping pair (West/North, sharing Ben) refuses it
with BD003 and writes no row; a same-circle same-day resubmission still just replaces; the same
track the following night in the same overlapping pair is allowed; the refusal is stable across
repeated attempts. Verified: `npm run test:db` (641/641), `npm run audit:leak` (AC-1 satisfied,
timing r ≈ 0.09 — the new check runs on every call, accepted or refused, so it carries no timing
signal of its own), `node scripts/lint.mjs` clean. Also ran (not required by this slice's Verify
line, but touched by the shared files): `npm run test:functions` (245/245, including the two
codes/copy exhaustiveness tests, which now cover `TRACK_ALREADY_USED` too). Server-only; no
simulator pass applicable.
