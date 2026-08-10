# E02 — Auth, profiles, groups

The `_shared` layer built here is used by every later handler. Getting the authorization
pipeline and the error envelope right once means the rest of the backend inherits them.

---

### E02-01 — `_shared`: http, auth, dto, db

**Status:** todo · **Deps:** E01-02 · **Reads:** `docs/04` §1, `docs/14` §4, `docs/01` §2
**Touches:** `functions/_shared/{http,auth,db,time,dto}.ts`
**Verify:** `npm run test:functions -- shared`

The spine. Five modules:

- `http.ts` — `ok(data)` / `fail(code, status)`. Both inject `server_now`. **No handler ever
  constructs a `Response` directly**; add a lint check for `new Response` outside this file.
- `auth.ts` — the six-step pipeline in `docs/14` §4, as composable guards returning typed
  context. `requireMembership` resolves the group from the caller, never from the request.
- `db.ts` — the service-role client, created once per invocation.
- `time.ts` — `serverNow()`, phase predicates.
- `dto.ts` — **every** response shape in one file, each built by naming its fields. This is
  the file a security reviewer reads.

- [ ] `ok`/`fail` envelope matches `docs/04` §1 exactly
- [ ] Every error code from `docs/04` §1 defined with its HTTP status and copy-deck message
- [ ] `WRONG_PHASE` bodies carry `state` and nothing else (`docs/14` §3)
- [ ] Guards compose; `requireMembership` takes no group parameter
- [ ] Unknown request-body keys are **rejected**, not ignored (`docs/14` §7)
- [ ] Tests: 401 for anonymous, 409 for no profile / no group, unknown-key rejection

---

### E02-02 — `/me`

**Status:** todo · **Deps:** E02-01 · **Reads:** `docs/04` §2, `docs/14` §7
**Touches:** `functions/me/index.ts`
**Verify:** `npm run test:functions -- me`

- [ ] `GET /me` returns `{user_id, display_name, has_group}`
- [ ] Returns `NO_PROFILE` when the display name has never been set
- [ ] `PUT /me` trims, validates 1–24 chars, strips control/zero-width/RTL-override
      characters (`docs/14` §7)
- [ ] Duplicate display names across a group are accepted
- [ ] Tests including the RTL-override strip

---

### E02-03 — `/groups`

**Status:** todo · **Deps:** E02-02 · **Reads:** `docs/04` §3, `docs/02` §1, `docs/14` §4
**Touches:** `functions/groups/index.ts`
**Verify:** `npm run test:functions -- groups`

Create, join, current, patch, leave.

- [ ] `POST /groups` validates the IANA timezone against `pg_timezone_names`
- [ ] `reveal_hour` constrained to 18–21; creator becomes `admin`
- [ ] `ALREADY_IN_GROUP` when an active membership exists (ADR-005)
- [ ] `POST /groups/join` is case-insensitive and whitespace-tolerant
- [ ] `GET /groups/current` returns the roster with **`user_id` and `display_name` only** —
      no `joined_at`, no counts (`docs/14` §3)
- [ ] `PATCH` is admin-only; `timezone` is immutable; response echoes `effective_from`
- [ ] `POST /groups/current/leave` sets `left_at`; historical rows untouched
- [ ] Test: a member of group A gets `NOT_FOUND` for every group-B resource
- [ ] Test: an ex-member's live token gets `NO_GROUP`

---

### E02-04 — Invite code generation

**Status:** todo · **Deps:** E02-03 · **Reads:** `docs/03` §2 (groups), `docs/14` §8
**Touches:** `functions/groups/index.ts`, `migrations/0002_core_tables.sql`
**Verify:** `npm run test:functions -- invite`

Six characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` — no I, L, O, 0, or 1, because this
code gets read aloud and typed by teenagers.

- [ ] Generated with a CSPRNG, not `Math.random`
- [ ] Retry on unique violation, up to 5 attempts, then 500
- [ ] Rate limits: 10/hour per user, 30/hour per IP on join (`docs/04` §8)
- [ ] A bad code and a valid-but-unusable code return the identical `NOT_FOUND`
- [ ] Test: 10k generated codes contain no excluded character and no duplicate

---

### E02-05 — Account deletion

**Status:** todo · **Deps:** E02-03 · **Reads:** `docs/03` §6, `docs/14` §9
**Touches:** `migrations/0008_delete_account.sql`, `functions/me/index.ts`
**Verify:** `npm run test:db -- deletion`

Deletion must not cascade away submissions and guesses — other members' scores depend on
them.

- [ ] `delete_account(user_id)` anonymises `display_name` to "Former member", unlinks auth,
      sets `left_at`
- [ ] Submissions and guesses survive; The Record keeps attribution to "Former member"
- [ ] Test: after deletion, every other member's standings are unchanged
- [ ] Test: the deleted user cannot authenticate
- [ ] Settings copy states this before confirming (coordinate with `docs/11`)
