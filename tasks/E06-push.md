# E06 — Push notifications

Three pushes a day, maximum. The outbox is written only by the tick job, never by a request
handler — that is what makes notification abuse structurally impossible.

---

### E06-01 — Outbox and the APNs JWT

**Status:** done · **Deps:** E03-03 · **Reads:** `docs/05` §2, §4, `docs/06` §8
**Touches:** `functions/_shared/apns.ts`, `migrations/0006_notifications.sql`
**Verify:** `npm run test:functions -- apns`

ES256 JWT signing with Web Crypto in Deno. No JWT library.

- [x] `.p8` parsed from a Supabase secret; **never** in the repo or the app bundle
- [x] JWT cached in module scope, regenerated at 50 minutes (Apple rejects regeneration more
      often than every 20 and expires at 60)
- [x] Outbox `unique (round_id, kind)` in place — this **is** the idempotency guarantee
- [x] Bodies from the `docs/11` notifications table, verbatim
- [x] Test: two JWT requests within 50 minutes return the same token
- [x] Test: signature verifies against the public key

---

### E06-02 — `push-worker`

**Status:** done · **Deps:** E06-01 · **Reads:** `docs/05` §2, §4
**Touches:** `migrations/*_claim_notifications.sql`, `functions/push-worker/`,
`tests/functions/{push,leak}.test.ts`, `config.toml`
**Verify:** `npm run test:functions -- push`

Drains the outbox. Claim → send → mark, with `for update skip locked`.

> **Open question:** The original touch set named only the Edge Function, but PostgREST cannot
> keep a row lock open across an APNs request. This implementation uses an atomic SQL claim and
> a 55-second persisted lease, so overlapping workers are disjoint and a crashed claim becomes
> eligible on the next minute. This is the interpretation most protective against duplicate
> delivery while retaining the specified crash retry.

- [x] Claim increments `attempts` and locks; two concurrent invocations claim disjoint rows
- [x] `apns-collapse-id = <round_id>:<kind>` — makes a duplicated batch invisible to the user
- [x] `apns-expiration`: reveal push expires at `scores_at`; results push at +12h. A reveal
      push must never arrive at midnight.
- [x] `apns-priority: 10`, `apns-push-type: alert`, `interruption-level: active`
- [x] Payload carries `kind`, `round_id`, `deep_link` (`docs/05` §5)
- [x] Bounded concurrency of 16; whole group delivered within 20s
- [x] `sent_at` set **after** the send completes, never before
- [x] Test: a crash between send and mark re-sends with the same collapse id

---

### E06-03 — `POST /devices`

**Status:** done · **Deps:** E02-02 · **Reads:** `docs/04` §2, `docs/05` §4
**Touches:** `functions/devices/index.ts`, `config.toml`, `tests/functions/{devices,leak}.test.ts`
**Verify:** `npm run test:functions -- devices`

- [x] Upsert on `apns_token`; re-points to the current user, clears `disabled_at`, bumps
      `last_seen_at`
- [x] Returns 204
- [x] Test: the same token registered by a second user moves ownership (a shared device)
- [x] **No notification-preference fields.** There are no settings (`docs/05` §4)
- [x] Token stored lowercased — hex is case-insensitive, and two spellings of one token would
      be two rows and two copies of every push to one phone
- [x] `requireProfile`, not `requireUser`: `devices.user_id` references `profiles(id)`, so an
      unnamed caller gets `NO_PROFILE` rather than a foreign-key violation as `INTERNAL`

---

### E06-04 — Idempotency, expiry, and 410 handling

**Status:** done · **Deps:** E06-02 · **Reads:** `docs/05` §2, §6, `docs/15` AC-3
**Touches:** `migrations/*_notification_retry.sql`, `functions/push-worker/worker.ts`,
`tests/functions/{push,leak}.test.ts`
**Verify:** `npm run test:functions -- push`

> **Open question:** the checklist asks for the fourteen-day budget here, but that season
> already exists as a real fourteen-day simulation in `tests/db/notification_budget.sql`
> (E03-03), where `set_test_now()` can move the clock by days and the function suite cannot.
> Duplicating it over HTTP would have meant a weaker version of a test that already passes, so
> the delivery half is asserted instead: a claimed row is sent exactly once per registered
> device and never claimed again. Enqueue budget × exactly-once delivery = the AC-3 cap, and
> the two halves are named in each other's comments.

- [x] 410 Unregistered → `devices.disabled_at = now()`, never retried, and **not** a failure of
      the row: a notification with no live device left to reach is finished, not abandoned
- [x] 429/5xx → leave `sent_at` null, retry next minute
- [x] `attempts >= 5` → record `last_error` and stop. Do not retry forever. The ceiling is the
      `attempts < 5` guard inside `claim_notification_outbox`, not a check in the worker — a
      limit that lives only in the worker is a limit the second worker does not have.
- [x] `last_error` survives a re-claim. It used to be nulled on claim, which emptied the field
      exactly when a stopped row was being investigated; only a successful send clears it now.
- [x] Test: the nudge audience is frozen at enqueue — a user who submits afterwards still
      receives it, and a user who had already submitted never does
- [x] Test: over a simulated 14-day season, no user receives more than 3 pushes in any 24h
      (`tests/db/notification_budget.sql`, plus the exactly-once delivery test above)
- [x] Test: `reveal` and `void` are mutually exclusive for a given round
