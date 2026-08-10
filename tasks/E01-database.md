# E01 — Database foundation

Schema, locks, and the test harness. Everything downstream depends on this being right, so
the constraints matter more than the speed.

---

### E01-01 — Extensions and core tables

**Status:** wip · **Deps:** E00-02 · **Reads:** `docs/03` §1–2
**Touches:** `migrations/0001_extensions.sql`, `migrations/0002_core_tables.sql`
**Verify:** `npm run test:db -- schema`

Transcribe the schema in `docs/03` §2 exactly. Nine tables, the `round_state` and
`notif_kind` enums, every index and check constraint listed.

- [ ] `0001` creates `pgcrypto`, `pg_cron`, `pg_net`
- [ ] `0002` creates profiles, groups, memberships, rounds, submissions, guesses, devices
- [ ] `0006` creates the notification outbox; `0007` creates `track_links`
- [ ] Every index in `docs/03` §2 present, including the partial indexes
- [ ] `rounds_window` and `rounds_card_order_iff_revealed` check constraints present
- [ ] `memberships_one_active_per_user` unique index present (this is ADR-005 in the schema)
- [ ] pgTAP test asserts every table, column type, and index exists

---

### E01-02 — RLS lockdown

**Status:** wip · **Deps:** E01-01 · **Reads:** `docs/03` §3, `docs/01` §2, `docs/14` §4
**Touches:** `migrations/0003_rls.sql`
**Verify:** `npm run test:db -- rls`

Enable RLS on all nine tables, create **no policies**, and revoke everything from `anon` and
`authenticated` including default privileges.

> Resist adding a "read your own profile" policy. The app reads its profile through an Edge
> Function. Every policy you add is a surface that has to be re-reasoned about in every phase.

- [ ] RLS enabled on all nine tables
- [ ] Zero policies created
- [ ] `revoke all` on tables, sequences, functions, and default privileges
- [ ] Test: an authenticated PostgREST `select` on each table returns `[]` (not an error —
      it must fail closed and silent)
- [ ] Test: `anon` likewise

---

### E01-03 — Constraints and triggers

**Status:** wip · **Deps:** E01-01 · **Reads:** `docs/02` §5, `docs/03` §2
**Touches:** `migrations/0002_core_tables.sql` (trigger section)
**Verify:** `npm run test:db -- constraints`

Implement `guesses_validate()` and prove every invariant in `docs/02` §5 is unviolatable by a
direct SQL insert. These are the last line of defence if an Edge Function's authorization has
a hole.

- [ ] `guesses_validate` trigger rejects: round mismatch, guessing your own card, guessing
      when you did not submit
- [ ] `guesses_not_self` check rejects `guesser_id = guessed_user_id`
- [ ] Unique indexes reject a second submission per user per round and a second guess per card
- [ ] `rounds_card_order_iff_revealed` rejects `card_order` in `open`/`voided` and null in
      `revealed`/`scored`
- [ ] `rounds_window` rejects a mis-timed round
- [ ] One pgTAP `throws_ok` per invariant in `docs/02` §5 (11 of them)

---

### E01-04 — Seed data

**Status:** wip · **Deps:** E01-03 · **Reads:** `docs/02` §4.4, `docs/03` §7
**Touches:** `server/supabase/seed.sql`
**Verify:** `supabase db reset` then `npm run test:db -- seed`

The `docs/02` §4.4 fixture, exactly: one group (`America/New_York`, `reveal_hour = 20`), nine
profiles (Ana…Ivy), and three rounds — one `scored` with the full guess matrix, one
`revealed`, one `open`.

The guess matrix must produce the exact per-user correct counts in §4.4. Work backwards from
the table; do not generate guesses randomly and hope.

- [ ] Nine profiles with the §4.4 names
- [ ] Ana and Ben share a `track_key` (the duplicate case)
- [ ] Ivy has no submission in the scored round
- [ ] Eli has a submission and **zero** guesses
- [ ] Ben has 4 guesses, 3 correct, 3 cards blank
- [ ] Every per-user correct count matches §4.4 exactly
- [ ] Test asserts the seeded counts before any view exists, so a seed drift is caught here
      and not blamed on E05

---

### E01-05 — pgTAP harness and `now_()`

**Status:** wip · **Deps:** E01-01 · **Reads:** `docs/15` §3
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

- [ ] `pgtap` extension installed in the test database only
- [ ] `now_()` created; a test proves it honours `app.test_now` and falls back to `now()`
- [ ] `npm run test:db` runs every `tests/db/*.sql` and reports TAP output
- [ ] `npm run test:db -- <name>` filters to one file
- [ ] Helper `set_test_now(timestamptz)` for readability in tests
- [ ] **No `pg_sleep` anywhere in the test suite** — add a grep check to the script
