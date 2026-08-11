# E04 — Submissions API

The blind window lives in this epic. `E04-03` and `E04-04` are the tests the whole product
rests on — treat them as deliverables, not as chores at the end.

---

### E04-01 — `PUT /rounds/current/submission`

**Status:** wip · **Deps:** E03-01, E07-03 · **Reads:** `docs/04` §4, `docs/02` §3, `docs/06` §3–4
**Touches:** `functions/rounds/index.ts`
**Verify:** `npm run test:functions -- submit`

Upsert on `(round_id, user_id)`. Accepts an Apple Music id, a Spotify URL, or an ISRC, and
resolves through `E07-03` to a canonical Track.

- [ ] Allowed only in `open`; otherwise `WRONG_PHASE` carrying `state` and nothing else
- [ ] Upsert preserves `created_at`, moves `updated_at`
- [ ] **No `DELETE` route** — there is no un-submitting
- [ ] Duplicate tracks across users are never rejected and the response gives no hint that a
      duplicate exists (`docs/02` §3 — the rejection itself would be the leak)
- [ ] Idempotent: the same body twice → one row, identical response
- [ ] Spotify resolution runs inline with a 700ms budget; a timeout does **not** fail the
      submission (`docs/06` §5)
- [ ] Rate limit 20/min per user
- [ ] Test: submitting the same `track_key` as another user succeeds with a byte-identical
      response shape to a unique submission

---

### E04-02 — `GET /rounds/current`: open and voided

**Status:** wip · **Deps:** E04-01 · **Reads:** `docs/04` §4, `docs/14` §3
**Touches:** `functions/rounds/index.ts`, `functions/_shared/dto.ts`
**Verify:** `npm run test:functions -- round_open`

The single most security-sensitive handler in the codebase.

The `open` payload key set is **exactly**:
`{round_id, local_date, state, opens_at, reveals_at, scores_at, my_submission}`.

- [ ] Built by naming fields in `dto.ts` — no spread, no `select *`, no passthrough
- [ ] The handler's query plan touches **no other user's submission row**. Do not add a
      `count(*)` "for logging" (`docs/14` §3, timing channel)
- [ ] `voided` returns the same key set, with the caller's own submission returned
- [ ] **No count of actual submitters in the voided payload** (`docs/08` §5)
- [ ] `my_submission.sealed_at` is the caller's own `updated_at`
- [ ] Test: payload for a submitter and a non-submitter differ only in `my_submission` and
      `server_now`
- [ ] Test: byte-length invariant across 0/1/5/11 other submitters, holding the caller's own
      track fixed

---

### E04-03 — Golden leak fixtures

**Status:** wip · **Deps:** E04-02 · **Reads:** `docs/15` AC-1, `docs/14` §3
**Touches:** `tests/golden/*.json`, `tests/functions/leak.test.ts`
**Verify:** `npm run test:functions -- leak`

Capture every response reachable during `open` as a golden file and diff on every run. Adding
a field to an `open`-phase response must therefore require a human to update a golden file —
**that friction is the control** (`docs/14` §3).

- [ ] `round_open.json`, `round_open_nosub.json`, `round_voided.json`, `groups_current.json`,
      `me.json`
- [ ] Golden files assert the **key set**, not the values, so fixture churn doesn't create
      noise
- [ ] A separate assertion on byte length where it matters
- [ ] Test enumerates every route in `functions/` and fails if a route has no golden file —
      a new endpoint cannot be added without one
- [ ] Test: `WRONG_PHASE` error bodies contain only `state`

---

### E04-04 — `audit:leak` script

**Status:** wip · **Deps:** E04-03 · **Reads:** `docs/14` §10, `docs/15` AC-1
**Touches:** `server/package.json`, `tests/functions/leak_timing.test.ts`, `tests/functions/postgrest_locked.test.ts`
**Verify:** `npm run audit:leak`

Bundle the AC-1 group into one command. It gates release and it is the single most important
command in the repo.

- [ ] Golden-file diff (E04-03)
- [ ] Authenticated PostgREST `select` on each of the nine tables returns `[]`
- [ ] Anonymous call to every Edge Function returns 401
- [ ] Latency correlation with submitter count: |r| < 0.2 over 100 samples
- [ ] Cross-group probe: a member of A gets `NOT_FOUND` for every B resource, path-fuzzed
      with real UUIDs
- [ ] Ex-member's live token → `NO_GROUP`
- [ ] Prints a one-page pass/fail summary suitable for pasting into a release checklist
