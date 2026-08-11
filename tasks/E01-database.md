# E01 — Database foundation

Schema, locks, and the test harness. Everything downstream depends on this being right, so
the constraints matter more than the speed.

---

### E01-01 — Extensions and core tables

**Status:** done · **Deps:** E00-02 · **Reads:** `docs/03` §1–2
**Touches:** `migrations/0001_extensions.sql`, `migrations/0002_core_tables.sql`
**Verify:** `npm run test:db -- schema`

Transcribe the schema in `docs/03` §2 exactly. Nine tables, the `round_state` and
`notif_kind` enums, every index and check constraint listed.

- [x] `0001` creates `pgcrypto`, `pg_cron`, `pg_net`
- [x] `0002` creates profiles, groups, memberships, rounds, submissions, guesses, devices
- [x] `0006` creates the notification outbox; `0007` creates `track_links`
- [x] Every index in `docs/03` §2 present, including the partial indexes
- [x] `rounds_window` and `rounds_card_order_iff_revealed` check constraints present
- [x] `memberships_one_active_per_user` unique index present (this is ADR-005 in the schema)
- [x] pgTAP test asserts every table, column type, and index exists

---

### E01-02 — RLS lockdown

**Status:** done · **Deps:** E01-01 · **Reads:** `docs/03` §3, `docs/01` §2, `docs/14` §4
**Touches:** `migrations/0003_rls.sql`
**Verify:** `npm run test:db -- rls`

Enable RLS on all nine tables, create **no policies**, and revoke everything from `anon` and
`authenticated` including default privileges.

> Resist adding a "read your own profile" policy. The app reads its profile through an Edge
> Function. Every policy you add is a surface that has to be re-reasoned about in every phase.

- [x] RLS enabled on all nine tables
- [x] Zero policies created
- [x] `revoke all` on tables, sequences, functions, and default privileges
- [x] Test: an authenticated PostgREST `select` on each table returns no row — see the open
      question below
- [x] Test: `anon` likewise

> **Open question:** the checklist asks for `[]` "not an error". With `REVOKE ALL` in place
> the database answers `42501 permission denied`, which is a *stronger* outcome than an empty
> array: it fails closed at the privilege layer rather than relying on RLS returning no rows.
> Asserted "no row is ever returned, for either role, on any of the nine tables, for reads
> and writes alike" instead of asserting the specific empty-array shape. The HTTP-level
> version of this test lands in `E14-01`.

> **Note:** RLS is also `FORCE`d on all nine tables, so a future `security definer` function
> owned by `postgres` cannot become an accidental bypass. Supabase's platform role
> `supabase_admin` holds default privileges granting `anon`/`authenticated` on future objects
> in `public`, and `postgres` is refused when it tries to revoke them; nothing here creates
> an object as that role, `config.toml` sets `auto_expose_new_tables = false`, and the test
> is scoped to the grantor this repo controls. Documented inline in `tests/db/rls.sql`.

---

### E01-03 — Constraints and triggers

**Status:** done · **Deps:** E01-01 · **Reads:** `docs/02` §5, `docs/03` §2
**Touches:** `migrations/0002_core_tables.sql` (trigger section)
**Verify:** `npm run test:db -- constraints`

Implement `guesses_validate()` and prove every invariant in `docs/02` §5 is unviolatable by a
direct SQL insert. These are the last line of defence if an Edge Function's authorization has
a hole.

- [x] `guesses_validate` trigger rejects: round mismatch, guessing your own card, guessing
      when you did not submit
- [x] `guesses_not_self` check rejects `guesser_id = guessed_user_id`
- [x] Unique indexes reject a second submission per user per round and a second guess per card
- [x] `rounds_card_order_iff_revealed` rejects `card_order` in `open`/`voided` and null in
      `revealed`/`scored`
- [x] `rounds_window` rejects a mis-timed round
- [x] One pgTAP `throws_ok` per invariant in `docs/02` §5 (11 of them)

> **Note:** `docs/03` §2 says invariants 4, 5 and 7 need a trigger. Two more do, and this
> task asks that every invariant be unviolatable by direct SQL, so `0002` also adds:
> `rounds_state_forward_only` (invariant 1 — a round never moves backwards) and
> `rounds_card_order_is_permutation` (invariant 3 — deferred to commit, since a round and its
> submissions are written in one transaction). Invariant 10's aggregate half is not
> assertable until the scoring views exist; `tests/db/constraints.sql` proves the structural
> half and points at `E05-03` for the rest.

---

### E01-04 — Seed data

**Status:** done · **Deps:** E01-03 · **Reads:** `docs/02` §4.4, `docs/03` §7
**Touches:** `server/supabase/seed.sql`
**Verify:** `supabase db reset` then `npm run test:db -- seed`

The `docs/02` §4.4 fixture, exactly: one group (`America/New_York`, `reveal_hour = 20`), nine
profiles (Ana…Ivy), and three rounds — one `scored` with the full guess matrix, one
`revealed`, one `open`.

The guess matrix must produce the exact per-user correct counts in §4.4. Work backwards from
the table; do not generate guesses randomly and hope.

- [x] Nine profiles with the §4.4 names
- [x] Ana and Ben share a `track_key` (the duplicate case)
- [x] Ivy has no submission in the scored round
- [x] Eli has a submission and **zero** guesses
- [x] Ben has 4 guesses, 3 correct, 3 cards blank
- [x] Every per-user correct count matches §4.4 exactly
- [x] Test asserts the seeded counts before any view exists, so a seed drift is caught here
      and not blamed on E05

> **Open question — needs the owner.** `docs/02` §4.4 as printed is unsatisfiable, so the
> seed cannot match it exactly.
>
> "Cal guesses all 7; 7 correct" means Cal places a correct guess on every card except his
> own. Every card therefore holds at least one correct guess, so no card can have a
> readability of 0 — which contradicts the table's `Gus | 0 | 0%`. Checked exhaustively:
> there is no assignment of 46 guesses satisfying both tables, and the minimum repair is two
> units in either direction.
>
> Applied the repair that keeps every stated *guess activity* number and touches only the
> readability table, which the doc introduces hypothetically ("say the correct-guess counts
> on each person's card were"):
>
> | | §4.4 as printed | seeded |
> |---|---|---|
> | Gus readability | 0 / 7 | **1 / 7** |
> | Hal readability | 5 / 7 | **4 / 7** |
>
> Ear is untouched, so Cal keeps 7/7 and Eli keeps the `0/0 → null` case. Both tables still
> total 26. The alternative — keeping `Gus 0` and dropping Cal to 6/7 — costs the 100% ear
> case instead and needs a second adjustment to rebalance.
>
> Cost of getting this wrong is low and contained: `seed.sql`, `tests/db/seed.sql`, and
> `ios/Fixtures/payloads/results.json` carry the same two numbers and are the only places to
> change. **Confirm before E05-06 hardens the scoring views against this fixture.**

---

### E01-05 — pgTAP harness and `now_()`

**Status:** done · **Deps:** E01-01 · **Reads:** `docs/15` §3
**Touches:** `migrations/0002_core_tables.sql`, `server/supabase/tests/db/_helpers.sql`, `package.json`
**Verify:** `npm run test:db` runs and reports

Set up pgTAP and the time-travel indirection. Every lifecycle function calls `public.now_()`,
never `now()` directly, so tests can move the clock without sleeping.

```sql
create or replace function public.now_() returns timestamptz
language sql stable as $$
  select coalesce(
    nullif(current_setting('app.test_now', true), '')::timestamptz,
    now())
$$;
```

- [x] `pgtap` extension installed in the test database only
- [x] `now_()` created; a test proves it honours `app.test_now` and falls back to `now()`
- [x] `npm run test:db` runs every `tests/db/*.sql` and reports TAP output
- [x] `npm run test:db -- <name>` filters to one file
- [x] Helper `set_test_now(timestamptz)` for readability in tests
- [x] **No `pg_sleep` anywhere in the test suite** — add a grep check to the script
