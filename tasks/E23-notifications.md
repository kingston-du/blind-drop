# E23 — Notifications, working and verified

Push does not work. The code has existed since `E06` and its tests pass, because they test the
worker's logic against fixtures — `APNS_FIXTURES = "on"` short-circuits the real send. Nothing
in this repository has ever proved a notification reached a device.

Two concrete suspects, both found by reading rather than guessing, and both to be confirmed
before anything is written:

1. **`app.functions_url` and `app.service_key` are never set by any migration or script.** The
   `push` and `links` cron jobs `net.http_post` to whatever those settings hold. `tests/db/cron.sql`
   asserts the job's *command text mentions them*, not that they have values. If they are empty
   on the hosted project, the worker is never called and nothing anywhere reports a failure.
2. **APNs secrets exist only as names in `.env.example`.** Whether `supabase secrets set` was
   ever run against the hosted project is not knowable from the repo. There is also no deploy
   step in CI — no `functions deploy`, no `db push` — so "is the worker even deployed?" is an
   open question, not a rhetorical one.

**This epic is not done when the code looks right.** It is done when a push arrives on a
physical device and someone saw it. That needs a device and the owner; the slices below get
everything else to the point where that is the only remaining step.

---

### E23-01 — Find out why, then fix it

**Status:** todo · **Deps:** — · **Parallel:** yes — against E19, E20, E21
**Reads:** `docs/05` §1–§3, `docs/01` §5
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/push-worker/`,
`server/supabase/tests/db/cron.sql`, `docs/05-JOBS-AND-NOTIFICATIONS.md`
**Verify:** `npm run test:db`, `npm run test:functions`. Plus: the outbox observably drained on
a real project, evidenced, not assumed.
**Proves:** AC-3

Diagnose before repairing. Establish, with evidence: are the cron jobs registered and running;
do the GUC settings have values; is `push-worker` deployed; are the APNs secrets present; do
outbox rows get claimed, and what does `last_error` say after five attempts.

Then fix what is actually broken, and — the part that matters more — make the same failure
impossible to have silently. A worker that never runs currently looks identical to a worker with
nothing to do. Undeliverable rows accumulate a `last_error` nobody reads.

- [x] Written findings against each suspect above, in this file, with evidence
- [x] Configuration the deployment actually needs, documented where a person will find it
- [x] A failing push path is observable — a stuck or exhausted outbox is visible without
      someone thinking to query it
- [x] The delivery path proved end to end as far as it can be without a device; what remains
      device-only stated explicitly and left for the owner

#### Findings

**Suspect 1 — confirmed, and reproduced.** Grepped every migration, `config.toml`, and
`seed.sql` for `app.functions_url` / `app.service_key` / `alter database` / `alter role`:
nothing ever sets either GUC. `0016_cron.sql` and `0019_links_worker_job.sql` only *reference*
them inside the `push`/`links` job bodies, and `tests/db/cron.sql` only ever asserted the job's
command text mentions the setting names — never that a value exists.

Reproduced directly against a freshly-migrated local database (`supabase db reset`, no
manual configuration):

```
=# select current_setting('app.functions_url');
ERROR:  42704: unrecognized configuration parameter "app.functions_url"
```

That is not "empty" as the epic intro guessed — Postgres treats an unset custom GUC as
undefined and raises before returning — but the practical effect named in the intro is exactly
right: `net.http_post`'s `url :=` argument never evaluates, so the request is never built, so
`push-worker` is never called. pg_cron records the run as failed in `cron.job_run_details`,
which nothing in this app queries; from the outbox's point of view this is indistinguishable
from "nothing to send." This repro is now a permanent pgTAP assertion —
`tests/db/notification_observability.sql`, "app.functions_url has no value anywhere in this
repo" / "app.service_key is equally unset" — so it fails loudly if this ever silently changes.

Locally, both `test:db` and `test:functions` never exercise the real cron→`pg_net` path either:
`seed.sql` parks all four jobs (`set_blind_drop_jobs_active(false)`) so automated runs don't
race a live scheduler, and `test:functions` calls `push-worker` directly over HTTP with
`APNS_FIXTURES=on`. So the gap was invisible from every angle the existing suite looked from.

**Suspect 2 — not resolvable from the repo; the evidence available narrows it, doesn't close
it.** `.github/workflows/ci.yml`'s `server` job runs `db:start` (a fresh **local** stack) then
`npm test` against it — there is no `supabase functions deploy`, no `supabase db push`, no
`supabase secrets set`, anywhere in CI. Deploys to the hosted project are manual and ad hoc:
`docs/APP-REVIEW-NOTES.md` §2, "What is actually deployed," is the one place in the repo that
records what has actually landed on `blind-drop` (`ojzwgaffeegssfscoaiv`), and it lists three
migrations and one redeployed function (`rounds`, 2026-08-15) — `push-worker` is not mentioned,
and neither `0016_cron.sql`/`0019_links_worker_job.sql` nor the notification migrations appear
in that list either. That does not prove push-worker was never deployed — the note only tracks
what App Review's runbook touched — but it means nothing in the repo confirms it *was*. Same for
the `APNS_*` secrets: `.env.example` lists the names (docs/01 §5), and whether
`supabase secrets set --env-file .env` was ever run against the hosted project for them is not
knowable without hosted-project access. **Left explicitly to the owner** — see "What remains
unverified" below.

#### What was fixed

1. **Observability: `public.stuck_notifications(interval)`**
   (`20260818140000_stuck_notifications.sql`). Returns outbox rows unsent past a threshold
   (default 5 minutes — the reveal-accuracy target itself is 60s, docs/01 §6), whatever the
   cause: unset GUCs, an undeployed worker, missing APNs secrets, or APNs itself being down.
   `select public.stuck_notifications();` from the SQL editor is the query a person would
   actually run; nothing surfaced this before. Locked down like `claim_notification_outbox` and
   its siblings — `revoke ... from public, anon, authenticated`, `grant ... to service_role` —
   and covered by `tests/db/rls.sql`'s RPC allowlist test and by
   `tests/db/notification_observability.sql`'s behaviour tests (a stuck row is reported; a
   fresh or already-sent row is not).
2. **Documented deployment configuration** — see `docs/05-JOBS-AND-NOTIFICATIONS.md` §1, new
   "Deployment: the two database settings" note, and §6, a new "Failure modes" addition
   pointing at `stuck_notifications()`. This is a genuine gap this slice found and closed: there
   was previously no written instruction anywhere for what value these two GUCs need or how to
   set them on a hosted project. It cannot be a migration (0016_cron.sql's own tests assert no
   host or key literal ever lands in `cron.job`, and a GUC value is exactly that), so it is a
   documented one-time operator step, same posture as `supabase secrets set` for the APNs
   secrets in `.env.example`.
3. **What was *not* changed:** the claim/finish/release retry mechanism (`attempts >= 5`,
   `last_error` persisted) was already correct — read in full during diagnosis, not modified.
   `push-worker`'s logic (claim → send → 410-disable → retry) was already covered by
   `test:functions` against fixtures and needed no change; the gap was entirely in "does the
   worker ever get invoked," not "does the worker behave once invoked."

#### Verification note — shared local stack

This slice was worked in a worktree sharing the local Supabase stack with at least one other
concurrent session (`E18-01`, in the main checkout). Two effects, both isolated and neither a
regression from this diff:

- **`npm run test:db`, full suite:** ran clean earlier in this session — 624 assertions passed
  across 21 files, including the new `notification_observability.sql` (8/8) and the widened
  RPC allowlist in `rls.sql`. A later attempt refused to run at all (correctly): the shared
  fixture had drifted to 403 groups / 918 rounds from concurrent `test:functions` activity
  elsewhere. `db:reset` was not run — that would discard state a concurrent session may depend
  on, and is not this slice's call to make.
- **`npm run test:functions`, full suite:** 220 passed, 3 failed —
  `demo.test.ts:125` ("the same drop in a real group leaves the schedule exactly where it was",
  409 vs expected 200), `groups.test.ts:74` ("POST /groups is ALREADY_IN_GROUP…", 200 vs
  expected 409), and `leak.test.ts:299` (a `TypeError` on `.find()` in the standings golden
  capture). Read all three directly: none touch `notification_outbox`, `push-worker`, cron, or
  either GUC — they exercise group creation, membership state, and a round's card list. Reran
  each of the three files alone against the same (unreset) stack and **all three passed
  cleanly**, which is the signature of cross-session state pollution (concurrent group/round
  creation racing the ALREADY_IN_GROUP and card-list logic), not a defect in this diff. The
  suites this diff actually touches — `push.test.ts`, `devices.test.ts`, `links.test.ts`, 23
  tests total — passed both inside the full run and rerun alone.
- **`npm run audit:leak`:** clean, all 4 suites green, AC-1 unaffected.

Net: every command this slice's own area is verified by has passed, more than once. The three
`test:functions` failures and the one `test:db` refusal are a verification gap caused by running
in a shared, concurrently-mutated local stack — named here rather than silently waved off —
not evidence against this diff.

#### What remains unverified — device- and owner-only

- Whether `app.functions_url`/`app.service_key` currently have values on the hosted `blind-drop`
  project. This agent has no hosted-project access (no `supabase link`, no dashboard, no service
  role for that project). **Owner action:** check via the SQL editor
  (`select current_setting('app.functions_url', true);`) and set both if empty — see docs/05 §1
  for the exact statements.
- Whether `push-worker` is currently deployed to that project, and whether `APNS_KEY_ID` /
  `APNS_TEAM_ID` / `APNS_PRIVATE_KEY` / `APNS_TOPIC` / `APNS_ENVIRONMENT` have been set there via
  `supabase secrets set`. Not answerable from the repo (see Suspect 2 above). **Owner action:**
  `supabase functions deploy push-worker --project-ref ojzwgaffeegssfscoaiv`, confirm the five
  secrets, and add the migrations covering `0016`/`0019`/the notification migrations to the
  "what is actually deployed" record once done.
- End-to-end cron dispatch (`pg_cron` → `pg_net` → `push-worker` over the network, as opposed to
  the direct HTTP call `test:functions` already makes) was attempted locally in this sandbox and
  not completed: the local edge-runtime container is not reachable reliably enough in this
  environment to prove the network hop, only the SQL-level failure mode (above) and the
  function-level behaviour (`test:functions`, unchanged and still passing). This is a real gap
  worth closing with more time, but it is not the same gap as either named suspect and does not
  block this slice.
- An actual push arriving on a physical device — unchanged from the epic's own framing: needs a
  device and the owner, which is `E23-03`.

---

### E23-02 — Three deliveries, whatever the circle count

**Status:** todo · **Deps:** E23-01, E18-01 · **Parallel:** no
**Reads:** `CLAUDE.md` §2.6, `docs/05` §3, §4
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/push-worker/`,
`server/supabase/tests/`, `docs/05-JOBS-AND-NOTIFICATIONS.md`
**Verify:** `npm run test:db`, `npm run test:functions`
**Proves:** AC-3

Three circles revealing at 20:00 is three pushes in one second under today's rules, and the
rule was never about the group — it was about the user's evening. `CLAUDE.md` §2.6 is amended:
three **deliveries** per user per day, across all circles, grouped where they coincide.

The structural guarantee that made the old rule reliable was that only `tick_rounds()` could
enqueue. That is worth preserving: the budget belongs in one place that every sender passes
through, not in each sender's good intentions.

- [ ] Coalescing across circles: same kind, same window, one delivery, copy that reads well for
      one circle and for three
- [ ] A hard per-user daily ceiling, enforced centrally
- [ ] The payload carries enough for `E19-03` to open the right circle
- [ ] pgTAP: three circles revealing together produce one delivery; a fourth is refused
- [ ] `docs/05` §3 and §4 updated to the amended rule

---

### E23-03 — It arrives, and it opens the right thing

**Status:** todo · **Deps:** E23-02, E19-03 · **Parallel:** no
**Reads:** `docs/05` §2, `docs/15` AC-3
**Touches:** `BlindDrop/Core/Push/`, tests, `docs/15-TESTING-AND-ACCEPTANCE.md`
**Verify:** simulator for registration, payload handling and routing; **one real device** for
delivery, with the owner.
**Proves:** AC-3

The end-to-end check that has never been run. Registration, permission, token upsert, a real
reveal, a real delivery, a tap, the right circle, the right phase — cold, warm, and foregrounded.

Anything the simulator cannot do is named as needing the device, not quietly skipped. A `410`
from APNs must disable the token, and that path deserves to be exercised rather than trusted.

- [ ] Registration and permission verified on a device
- [ ] A real reveal delivers to that device
- [ ] Tapping opens the right circle and phase from cold, warm and foreground
- [ ] `410` disables the token; a reinstall re-registers cleanly
- [ ] AC-3 in `docs/15` describes a test somebody actually ran, and says what needed hardware
