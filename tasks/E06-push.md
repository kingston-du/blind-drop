# E06 — Push notifications

Three pushes a day, maximum. The outbox is written only by the tick job, never by a request
handler — that is what makes notification abuse structurally impossible.

---

### E06-01 — Outbox and the APNs JWT

**Status:** todo · **Deps:** E03-03 · **Reads:** `docs/05` §2, §4, `docs/06` §8
**Touches:** `functions/_shared/apns.ts`, `migrations/0006_notifications.sql`
**Verify:** `npm run test:functions -- apns`

ES256 JWT signing with Web Crypto in Deno. No JWT library.

- [ ] `.p8` parsed from a Supabase secret; **never** in the repo or the app bundle
- [ ] JWT cached in module scope, regenerated at 50 minutes (Apple rejects regeneration more
      often than every 20 and expires at 60)
- [ ] Outbox `unique (round_id, kind)` in place — this **is** the idempotency guarantee
- [ ] Bodies from the `docs/11` notifications table, verbatim
- [ ] Test: two JWT requests within 50 minutes return the same token
- [ ] Test: signature verifies against the public key

---

### E06-02 — `push-worker`

**Status:** todo · **Deps:** E06-01 · **Reads:** `docs/05` §2, §4
**Touches:** `functions/push-worker/index.ts`
**Verify:** `npm run test:functions -- push`

Drains the outbox. Claim → send → mark, with `for update skip locked`.

- [ ] Claim increments `attempts` and locks; two concurrent invocations claim disjoint rows
- [ ] `apns-collapse-id = <round_id>:<kind>` — makes a duplicated batch invisible to the user
- [ ] `apns-expiration`: reveal push expires at `scores_at`; results push at +12h. A reveal
      push must never arrive at midnight.
- [ ] `apns-priority: 10`, `apns-push-type: alert`, `interruption-level: active`
- [ ] Payload carries `kind`, `round_id`, `deep_link` (`docs/05` §5)
- [ ] Bounded concurrency of 16; whole group delivered within 20s
- [ ] `sent_at` set **after** the send completes, never before
- [ ] Test: a crash between send and mark re-sends with the same collapse id

---

### E06-03 — `POST /devices`

**Status:** todo · **Deps:** E02-02 · **Reads:** `docs/04` §2, `docs/05` §4
**Touches:** `functions/devices/index.ts`
**Verify:** `npm run test:functions -- devices`

- [ ] Upsert on `apns_token`; re-points to the current user, clears `disabled_at`, bumps
      `last_seen_at`
- [ ] Returns 204
- [ ] Test: the same token registered by a second user moves ownership (a shared device)
- [ ] **No notification-preference fields.** There are no settings (`docs/05` §4)

---

### E06-04 — Idempotency, expiry, and 410 handling

**Status:** todo · **Deps:** E06-02 · **Reads:** `docs/05` §2, §6, `docs/15` AC-3
**Touches:** `tests/functions/push.test.ts`
**Verify:** `npm run test:functions -- push`

- [ ] 410 Unregistered → `devices.disabled_at = now()`, never retried
- [ ] 429/5xx → leave `sent_at` null, retry next minute
- [ ] `attempts >= 5` → record `last_error` and stop. Do not retry forever.
- [ ] Test: the nudge audience is frozen at enqueue — a user who submits afterwards still
      receives it, and a user who had already submitted never does
- [ ] Test: over a simulated 14-day season, no user receives more than 3 pushes in any 24h
- [ ] Test: `reveal` and `void` are mutually exclusive for a given round
