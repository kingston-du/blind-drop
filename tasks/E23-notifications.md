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

- [ ] Written findings against each suspect above, in this file, with evidence
- [ ] Configuration the deployment actually needs, documented where a person will find it
- [ ] A failing push path is observable — a stuck or exhausted outbox is visible without
      someone thinking to query it
- [ ] The delivery path proved end to end as far as it can be without a device; what remains
      device-only stated explicitly and left for the owner

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
