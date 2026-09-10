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

**Status:** blocked · **Deps:** E16-01 · **Reads:** `docs/APP-REVIEW-NOTES.md`
**Touches:** `migrations/20260815120000_backfill_demo_groups.sql`,
`scripts/seed-app-review-demo.sql`, `scripts/status-app-review-demo.sql`,
`docs/APP-REVIEW-NOTES.md`, `tests/db/demo_mode.sql`
**Verify:** `scripts/status-app-review-demo.sql` against the linked project

- [x] Both migrations pushed to `ojzwgaffeegssfscoaiv`, plus a third
- [x] `rounds` Edge Function redeployed; anonymous smoke test returns `UNAUTHENTICATED` in our
      envelope
- [x] Provisioning run: **App Reviewer**, three companions, three nights in The Record, one
      open round holding the companions' drops and not the reviewer's
- [x] A real pilot group ("Family") is confirmed not a demo group and has no demo rounds
- [x] The whole loop walked against the **hosted** database inside a transaction that then
      threw, so nothing persisted: `open → +11s open → +13s revealed (4 cards) → +35s scored
      (4 people) → +4m a fresh open round, archive of 4`
- [x] Review note written to `docs/APP-REVIEW-NOTES.md`, ready to paste
- [ ] **Blocked, needs the owner:** walk the loop in the app on a device, signed in as
      `demo@blinddrop.dev`. Requires the account password, which is not in this repo and
      should not be. Everything below the app is verified.
- [ ] **Needs the owner:** paste §1 of `docs/APP-REVIEW-NOTES.md` into App Store Connect

> **Deployment found a gap the migrations alone did not cover.** `assign_pilot_cohort()`
> carries `pilot_cohorts.is_demo` onto the group it *creates*, but the App Review group had
> existed since 2026-08-13 — so the flag would have reached no group at all. `20260815120000`
> backfills it, the propagation trigger carries it down to the rounds already in the group,
> and `tests/db/demo_mode.sql` now covers that path directly because it is the one production
> was actually in.
>
> Provisioning also now clears the group's rounds first. It was carrying two rounds on
> sentinel dates in January 2020 left by the previous script, a `voided` night from before the
> companions existed, and a round materialised by a scheduler that no longer runs for it — so
> The Record would have opened on "Wednesday 1 January 2020".

> **Amended by the owner, 2026-09-10 (`20260910120000_demo_room_of_six`).** The room is six
> now, not four: five fixture companions — Kai, Mo, Nell, **Rae, Sol** — so the reveal is five
> cards and the guess sheet five names rather than the two a four-person room allows. The
> fixture catalogue is twelve songs instead of nine, and every row was re-resolved against the
> iTunes catalogue: the `apple_music_id` on each row had been the *album's* id, so every
> `music.apple.com/us/song/<id>` link opened the wrong page, and `preview_url` was null
> throughout — which under `docs/06` §7 means no preview control at all on any card a reviewer
> saw. Both are now real and were fetched and checked.
>
> `demo_provision()` is generalised over the roster rather than counting to four, and it now
> backfills a live `open` round with any companion missing from it. That last part is not
> tidiness: a group provisioned under the three-companion roster holds a round the two new
> members are not in, and `demo_tick()` never reveals a room that is short — it would slide
> the reveal forward for ever. **The hosted project needs `seed-app-review-demo.sql` re-run.**
