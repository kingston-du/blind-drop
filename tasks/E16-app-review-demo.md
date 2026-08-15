# E16 — The App Review demo environment

App Review happens whenever it happens. On the real schedule the loop — drop, seal, reveal,
guess, results — is reachable for two hours a day, and a round with fewer than three submitters
voids (`docs/02` §2). A reviewer opening the app at 23:00 finds a scored round or the dark
hours; an account playing alone finds every night voided. Neither shows the app working, and
Guideline 2.1 (App Completeness) is the ground a build gets rejected on for exactly that.

The fix is a group whose rounds advance on the **reviewer's own actions** rather than on the
clock. It is a server change end to end: the client keeps rendering a countdown from
`server_now` and refetching when it reaches zero, which is already the whole mechanism —
`CLAUDE.md` §2.2 stays intact and no iOS file changes.

---

### E16-01 — Demo groups, the demo lifecycle, and provisioning

**Status:** done · **Deps:** E03-03, E04-01, E05-02
**Reads:** `docs/02` §1–2 §6, `docs/03` §4 §4.1, `docs/04` §4, `docs/14` §3
**Touches:** `migrations/20260815090000_demo_groups.sql`,
`migrations/20260815090500_demo_lifecycle.sql`, `functions/rounds/index.ts`,
`scripts/seed-app-review-demo.sql`, `supabase/seed.sql`,
`tests/db/demo_mode.sql`, `tests/db/rls.sql`, `tests/functions/demo.test.ts`
**Verify:** `npm run test:db`, `npm run test:functions`, `npm run audit:leak`, `npm run lint`

- [x] `groups.is_demo` and `pilot_cohorts.is_demo`; `assign_pilot_cohort()` carries the flag
      onto the group it creates, so App Review enrollment stays code-free
- [x] `rounds.is_demo` mirrored by trigger on insert **and** on the group being marked, so
      `rounds_window` can exempt a demo round without the column ever disagreeing
- [x] `ensure_rounds()` and all three `tick_rounds()` loops skip demo groups
- [x] `shuffle_submissions()` extracted from `tick_rounds()`, so the reveal has one
      implementation and `tests/db/shuffle.sql` proves both callers
- [x] `demo_arm()` — reveal at 12s on the drop, score at 20s on a completed sheet, 180s
      backstop on a partial one. Never moves `reveals_at` after the reveal
- [x] `demo_tick()` — score, reveal-when-the-room-is-full, carry across local midnight, roll a
      fresh round two minutes after the last one scored. Never voids, never notifies
- [x] `demo_provision()` — *App Reviewer*, three companions, three finished nights, tonight's
      round. Owner-run; deliberately not granted to `service_role`
- [x] `rounds/index.ts`: `demo_tick` before the round read, `demo_arm` after submit and after
      the guess sheet. No response shape changes, so no golden file moves
- [x] `tests/db/demo_mode.sql` walks the whole loop at 03:17 with no `pg_sleep`, and asserts
      the scheduler cannot see a demo round while the seed group's lifecycle still runs
- [x] `tests/functions/demo.test.ts` compares a demo group's payloads against a real group's
      byte for byte
- [x] `seed-app-review-demo.sql` reduced to a call on `demo_provision()`. Nothing decays, so
      there is no longer a window in which it must be re-run

> **Open question — resolved by the owner, recorded here.** The seal countdown reads twelve
> seconds under `sealed.status`, which names the group's 8:00 PM reveal hour. An in-app
> "review mode" line would reconcile the two, at the cost of a `GroupDTO` field, a
> `groups_current.json` golden, a copy-deck entry, and new goldens across the snapshot matrix.
> Taken to the App Store Connect review notes instead, keeping this change server-only.

---

### E16-02 — Hosted activation

**Status:** todo · **Deps:** E16-01 · **Reads:** `docs/RELEASE-2026-08-12.md`
**Touches:** nothing in the repo
**Verify:** a walked loop on the hosted project at a deliberately awkward hour

Needs the owner's Supabase credentials and a device; it cannot be closed from here.

- [ ] Deploy both migrations and the `rounds` function to `ojzwgaffeegssfscoaiv`
- [ ] Sign in once as the review account, then run `scripts/seed-app-review-demo.sql`
- [ ] Walk the loop at 23:00 or later: The Record populated → search → pick → confirm → seal →
      ~12s → reveal → guess → ~20s → results → share card → back → a fresh round is open
- [ ] Confirm a real pilot account in the TestFlight cohort is on the normal schedule and
      untouched
- [ ] Put the accelerated-clock note in the App Store Connect review notes
