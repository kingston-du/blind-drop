# E03 — Round lifecycle and scheduler

The server-authoritative heart of the product. If this epic is wrong, the game is wrong in a
way no client fix can reach.

Everything here calls `public.now_()`, never `now()` — that is what makes the tests instant.

---

### E03-01 — `ensure_rounds()`

**Status:** done · **Deps:** E01-05, E02-03 · **Reads:** `docs/02` §1, `docs/03` §4
**Touches:** `migrations/0013_tick_rounds_reveal.sql`, `tests/db/lifecycle.sql`
**Verify:** `npm run test:db -- ensure_rounds`

Materialise today's and tomorrow's round for every group, idempotently. Two days ahead only,
so the timezone offset used is never stale across a DST boundary.

- [x] Local date computed with `timezone(g.timezone, ...)`, never a fixed offset
- [x] `reveals_at` is the UTC instant of `reveal_hour:00` group-local **on that local date**
- [x] `opens_at = reveals_at - 10h`, `scores_at = reveals_at + 2h`
- [x] `on conflict (group_id, local_date) do nothing` — an existing round is never re-timed
- [x] A `reveal_hour` change therefore lands on the first uncreated round; test this
- [x] Test: `America/New_York` spring-forward and fall-back dates both produce 20:00 local
- [x] Test: `Australia/Lord_Howe` (30-minute offset) works
- [x] Test: an invalid timezone raises for that group only and the loop continues

> **Open question:** should `ensure_rounds()` create today's round when `reveals_at` has
> already passed? `docs/03` §4 says "today and today+1" with no condition. A group created at
> 21:00 local would then be handed a round that reveals in the past, which the very next tick
> voids — a `void` push to people who never had a chance to drop, against the three-a-day
> budget (`CLAUDE.md` §2.6), and an `open` round that any read endpoint would render with a
> countdown that has already expired.
> **Reading taken (most protective):** the insert carries `where reveals_at > public.now_()`.
> It suppresses *creation* only; it can neither re-time nor remove a round that already
> exists, so the cron-outage path in `docs/05` §6 is untouched, and it matches the copy deck's
> `reveal.blocked.joinedlate` — "You're in from tomorrow." Pinned by an assertion in
> `tests/db/ensure_rounds_timezones.sql`. Owner's call to confirm.

> **Open question:** `docs/15` §? names the DST test `tests/db/timezones.sql`, but this task's
> **Verify** command filters test filenames on the substring `ensure_rounds`, so a file called
> `timezones.sql` would never run under the command that is supposed to prove this task.
> **Reading taken:** one file named `tests/db/ensure_rounds_timezones.sql`, which matches both.

> **Open question:** `docs/03` §4 says both lifecycle functions are `security definer` owned by
> `postgres`, while `0003_rls.sql` turns on `force row level security` with zero policies
> explicitly so "a future `security definer` function owned by postgres cannot become an
> accidental bypass". The two only coexist because `postgres` carries `BYPASSRLS`; without it
> `ensure_rounds()` would see zero groups and create nothing — a silent no-op rather than an
> error, which is the worst possible failure mode for a scheduler.
> **Reading taken:** keep `security definer` per `docs/03` §4, and assert the owner's
> `BYPASSRLS` bit in the test so the assumption is checked rather than believed.

---

### E03-02 — `tick_rounds()`: reveal and void

**Status:** done · **Deps:** E03-01 · **Reads:** `docs/02` §2–3, `docs/03` §4
**Touches:** `migrations/0004_round_lifecycle.sql`
**Verify:** `npm run test:db -- lifecycle`

The `open → revealed | voided` branch. One transaction per round, `for update skip locked`,
guarded update, outbox insert in the same transaction.

> **Open question:** the task originally named `0004_round_lifecycle.sql`, but E03-01 already
> committed and applied that migration. Editing it now would violate the repository's
> forward-only migration rule and would leave existing databases without `tick_rounds()`.
> The implementation therefore lands as `0013_tick_rounds_reveal.sql`. Each round's block is
> a PL/pgSQL subtransaction, so a failed transition rolls back its matching outbox insert and
> does not stop other due rounds; the function invocation itself remains one outer Postgres
> transaction, as required by a function called through `select public.tick_rounds()`.

- [x] `count(submissions) < 3` → `voided` + one `void` outbox row
- [x] `>= 3` → `revealed` + `card_order` + one `reveal` outbox row
- [x] Every update guarded with `where state = 'open'`; branch on the affected row count
- [x] Outbox insert is `on conflict do nothing`
- [x] Transition and enqueue are in **one** transaction — never enqueue first
- [x] Test: running the tick 10× at the same instant produces one transition, one outbox row
- [x] Test: exactly 2 submitters voids; exactly 3 reveals
- [x] Test: a voided round has `card_order is null` and no `reveal` row

---

### E03-03 — `tick_rounds()`: score and nudge

**Status:** done · **Deps:** E03-02 · **Reads:** `docs/02` §2, `docs/05` §3
**Touches:** `migrations/0015_tick_rounds_score_nudge.sql`,
`tests/db/lifecycle_score_nudge.sql`, `tests/db/notification_budget.sql`
**Verify:** `npm run test:db -- lifecycle`

> **Open question:** the task originally named `0004_round_lifecycle.sql`, but that migration
> is already applied. The forward-only implementation replaces `tick_rounds()` in `0015`;
> the preceding `0013` remains an accurate record of the reveal/void slice it introduced.

- [x] `revealed → scored` at `scores_at`, guarded, one `results` outbox row
- [x] `results` audience is members who **submitted or guessed**
- [x] Nudge enqueued once when `now_() >= reveals_at - 2h` and state is still `open`
- [x] Nudge audience is active members with **no submission**, frozen at enqueue time
      (`docs/05` §3)
- [x] Test: a user who submits after the nudge is enqueued still receives it, and no second
      nudge is created
- [x] Test: a user who submitted before the nudge is **not** in the audience
- [x] Test: no user receives more than 3 notifications in any 24h over a simulated 14-day
      season (`docs/15` §2)

---

### E03-04 — `card_order` shuffle

**Status:** done · **Deps:** E03-02 · **Reads:** `docs/02` §2 (card_order), `docs/01` ADR-003
**Touches:** `migrations/0013_tick_rounds_reveal.sql`,
`migrations/0015_tick_rounds_score_nudge.sql`, `tests/db/shuffle.sql`
**Verify:** `npm run test:db -- shuffle`

Fisher–Yates seeded with `hashtext(round_id::text)`. The **stored array** is authoritative;
the seed exists only so tests are reproducible.

- [x] Stored as a JSON array of submission ids; position `i` is `card_no = i + 1`
- [x] Length equals the round's submission count; it is a permutation of them
- [x] Generated exactly once, at the reveal transition; never regenerated, never per-user
- [x] Test: over 1000 synthetic rounds, Spearman correlation between submission `created_at`
      rank and `card_no` is within ±0.1 of zero
- [x] Test: no correlation with `user_id` ordering either
- [x] Test: the same round shuffled twice (forced) would produce the same array — proving the
      seed is deterministic — but the code path can only run once

---

### E03-05 — `pg_cron` registration

**Status:** done · **Deps:** E03-03 · **Reads:** `docs/05` §1
**Touches:** `migrations/0016_cron.sql`, `tests/db/cron.sql`, `README.md`
**Verify:** `npm run test:db -- cron` (asserts the jobs are registered)

> **Open question:** the planned `0009_cron.sql` slot predates already-applied migrations
> through `0015`. The job registration therefore lands forward-only as `0016_cron.sql`.

- [x] `tick` job every minute calling `tick_rounds()`
- [x] `push` job every minute calling the `push-worker` function via `pg_net`
- [x] Function URL and service key from `current_setting`, set per environment — **not**
      hardcoded in the migration
- [x] `ensure_rounds()` is called at the top of `tick_rounds()`, not as a third job
- [x] Documented in `README.md` how to set the two settings per environment

---

### E03-06 — Outage and idempotency tests

**Status:** todo · **Deps:** E03-05 · **Reads:** `docs/05` §2, §6, `docs/15` AC-3, AC-4
**Touches:** `tests/db/lifecycle.sql`, `tests/db/idempotency.sql`
**Verify:** `npm run test:db`

The row of `docs/05` §6 that actually happens: cron down for three hours.

- [ ] Test: no tick from 19:00 to 23:00, then one tick → `open → revealed → scored`, with
      **both** outbox rows present exactly once and no state skipped
- [ ] Test: a round with 2 submitters after the same outage voids and produces only a `void`
      row
- [ ] Test: two concurrent `tick_rounds()` calls (simulated via two sessions) do not
      double-transition — `for update skip locked` holds
- [ ] Test: a transaction that fails after the state update rolls back the outbox row too
- [ ] Test: the tick is a single index scan on `rounds_pending_tick` (assert via `explain`
      that no sequential scan on `rounds` occurs)
