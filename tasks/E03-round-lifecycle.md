# E03 — Round lifecycle and scheduler

The server-authoritative heart of the product. If this epic is wrong, the game is wrong in a
way no client fix can reach.

Everything here calls `public.now_()`, never `now()` — that is what makes the tests instant.

---

### E03-01 — `ensure_rounds()`

**Status:** todo · **Deps:** E01-05, E02-03 · **Reads:** `docs/02` §1, `docs/03` §4
**Touches:** `migrations/0004_round_lifecycle.sql`
**Verify:** `npm run test:db -- ensure_rounds`

Materialise today's and tomorrow's round for every group, idempotently. Two days ahead only,
so the timezone offset used is never stale across a DST boundary.

- [ ] Local date computed with `timezone(g.timezone, ...)`, never a fixed offset
- [ ] `reveals_at` is the UTC instant of `reveal_hour:00` group-local **on that local date**
- [ ] `opens_at = reveals_at - 10h`, `scores_at = reveals_at + 2h`
- [ ] `on conflict (group_id, local_date) do nothing` — an existing round is never re-timed
- [ ] A `reveal_hour` change therefore lands on the first uncreated round; test this
- [ ] Test: `America/New_York` spring-forward and fall-back dates both produce 20:00 local
- [ ] Test: `Australia/Lord_Howe` (30-minute offset) works
- [ ] Test: an invalid timezone raises for that group only and the loop continues

---

### E03-02 — `tick_rounds()`: reveal and void

**Status:** todo · **Deps:** E03-01 · **Reads:** `docs/02` §2–3, `docs/03` §4
**Touches:** `migrations/0004_round_lifecycle.sql`
**Verify:** `npm run test:db -- lifecycle`

The `open → revealed | voided` branch. One transaction per round, `for update skip locked`,
guarded update, outbox insert in the same transaction.

- [ ] `count(submissions) < 3` → `voided` + one `void` outbox row
- [ ] `>= 3` → `revealed` + `card_order` + one `reveal` outbox row
- [ ] Every update guarded with `where state = 'open'`; branch on the affected row count
- [ ] Outbox insert is `on conflict do nothing`
- [ ] Transition and enqueue are in **one** transaction — never enqueue first
- [ ] Test: running the tick 10× at the same instant produces one transition, one outbox row
- [ ] Test: exactly 2 submitters voids; exactly 3 reveals
- [ ] Test: a voided round has `card_order is null` and no `reveal` row

---

### E03-03 — `tick_rounds()`: score and nudge

**Status:** todo · **Deps:** E03-02 · **Reads:** `docs/02` §2, `docs/05` §3
**Touches:** `migrations/0004_round_lifecycle.sql`
**Verify:** `npm run test:db -- lifecycle`

- [ ] `revealed → scored` at `scores_at`, guarded, one `results` outbox row
- [ ] `results` audience is members who **submitted or guessed**
- [ ] Nudge enqueued once when `now_() >= reveals_at - 2h` and state is still `open`
- [ ] Nudge audience is active members with **no submission**, frozen at enqueue time
      (`docs/05` §3)
- [ ] Test: a user who submits after the nudge is enqueued still receives it, and no second
      nudge is created
- [ ] Test: a user who submitted before the nudge is **not** in the audience
- [ ] Test: no user receives more than 3 notifications in any 24h over a simulated 14-day
      season (`docs/15` §2)

---

### E03-04 — `card_order` shuffle

**Status:** todo · **Deps:** E03-02 · **Reads:** `docs/02` §2 (card_order), `docs/01` ADR-003
**Touches:** `migrations/0004_round_lifecycle.sql`
**Verify:** `npm run test:db -- shuffle`

Fisher–Yates seeded with `hashtext(round_id::text)`. The **stored array** is authoritative;
the seed exists only so tests are reproducible.

- [ ] Stored as a JSON array of submission ids; position `i` is `card_no = i + 1`
- [ ] Length equals the round's submission count; it is a permutation of them
- [ ] Generated exactly once, at the reveal transition; never regenerated, never per-user
- [ ] Test: over 1000 synthetic rounds, Spearman correlation between submission `created_at`
      rank and `card_no` is within ±0.1 of zero
- [ ] Test: no correlation with `user_id` ordering either
- [ ] Test: the same round shuffled twice (forced) would produce the same array — proving the
      seed is deterministic — but the code path can only run once

---

### E03-05 — `pg_cron` registration

**Status:** todo · **Deps:** E03-03 · **Reads:** `docs/05` §1
**Touches:** `migrations/0009_cron.sql`
**Verify:** `npm run test:db -- cron` (asserts the jobs are registered)

- [ ] `tick` job every minute calling `tick_rounds()`
- [ ] `push` job every minute calling the `push-worker` function via `pg_net`
- [ ] Function URL and service key from `current_setting`, set per environment — **not**
      hardcoded in the migration
- [ ] `ensure_rounds()` is called at the top of `tick_rounds()`, not as a third job
- [ ] Documented in `README.md` how to set the two settings per environment

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
