# E02 — Auth, profiles, groups

The `_shared` layer built here is used by every later handler. Getting the authorization
pipeline and the error envelope right once means the rest of the backend inherits them.

---

### E02-01 — `_shared`: http, auth, dto, db

**Status:** done · **Deps:** E01-02 · **Reads:** `docs/04` §1, `docs/14` §4, `docs/01` §2
**Touches:** `functions/_shared/{http,auth,db,time,dto}.ts`, `scripts/lint.mjs`,
`migrations/0010_service_role_grants.sql`, `migrations/0011_rate_limits.sql`
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

- [x] `ok`/`fail` envelope matches `docs/04` §1 exactly
- [x] Every error code from `docs/04` §1 defined with its HTTP status and copy-deck message
- [x] `WRONG_PHASE` bodies carry `state` and nothing else (`docs/14` §3)
- [x] Guards compose; `requireMembership` takes no group parameter
- [x] Unknown request-body keys are **rejected**, not ignored (`docs/14` §7)
- [x] Tests: 401 for anonymous, 409 for no profile / no group, unknown-key rejection

> **Open question:** `service_role` held **no** privilege on any table — `config.toml` sets
> `auto_expose_new_tables = false`, so 0002/0006/0007 granted nothing to anyone, and every
> handler would have failed with `42501`. `docs/01` §2 assumes "service-role queries" work, so
> the lockdown needed a companion: `0010_service_role_grants.sql` grants `service_role` the
> verbs each table's handlers use and nothing more. `anon` and `authenticated` are untouched.
> Owner to confirm the per-table verb list.

> **Open question:** rate limiting (`docs/04` §8) needs shared state, which an Edge Function
> has none of, so it lives in a tenth table (`0011_rate_limits.sql`). That table is documented
> in `docs/03` §2 and `tests/db/rls.sql` now asserts ten tables rather than nine — the count
> is deliberate friction, so this is exactly the doc change it is asking for.

> **Open question:** the invite alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789` has **31**
> characters, not 32 — `docs/03` §2 and `docs/14` §8 both say `32^6 ≈ 1.07e9`. The real space
> is `31^6 ≈ 8.9e8`, which changes nothing about brute-force feasibility given the 10/hour and
> 30/hour limits. The alphabet in the merged check constraint is authoritative; the arithmetic
> in the docs is what is wrong.

Also fixed here, because it blocked every function test: `seed.sql` left four `auth.users`
token columns NULL, which GoTrue scans as `string` rather than `*string`. Any fixture user
authenticating produced a 500 from `GET /auth/v1/user`.

---

### E02-02 — `/me`

**Status:** done · **Deps:** E02-01 · **Reads:** `docs/04` §2, `docs/14` §7
**Touches:** `functions/me/index.ts`, `functions/_shared/text.ts`, `config.toml`
**Verify:** `npm run test:functions -- me`

- [x] `GET /me` returns `{user_id, display_name, has_group}`
- [x] Returns `NO_PROFILE` when the display name has never been set
- [x] `PUT /me` trims, validates 1–24 chars, strips control/zero-width/RTL-override
      characters (`docs/14` §7)
- [x] Duplicate display names across a group are accepted
- [x] Tests including the RTL-override strip

> **Open question:** `docs/14` §7 says newlines are *stripped*, so `"Ana\nBen"` is stored as
> `"AnaBen"` rather than `"Ana Ben"`. Taken literally, which is what the tests assert. Runs of
> real whitespace still collapse to one space, so `"  Ana   Lucia "` is `"Ana Lucia"`.

> **Open question:** `verify_jwt = false` is set for each function in `config.toml`. With the
> platform gate on, an anonymous request is refused *before* the handler runs, with a body
> that is not the `docs/04` §1 envelope — so a client switching on `error.code` gets nothing
> to switch on. Every handler's first act is `requireUser()`, which returns
> `401 UNAUTHENTICATED` in the documented shape. The gate moves; it does not open.

---

### E02-03 — `/groups`

**Status:** done · **Deps:** E02-02 · **Reads:** `docs/04` §3, `docs/02` §1, `docs/14` §4
**Touches:** `functions/groups/index.ts`, `functions/_shared/invite.ts`,
`migrations/0012_group_api.sql`, `config.toml`
**Verify:** `npm run test:functions -- groups`

Create, join, current, patch, leave.

- [x] `POST /groups` validates the IANA timezone against `pg_timezone_names`
- [x] `reveal_hour` constrained to 18–21; creator becomes `admin`
- [x] `ALREADY_IN_GROUP` when an active membership exists (ADR-005)
- [x] `POST /groups/join` is case-insensitive and whitespace-tolerant
- [x] `GET /groups/current` returns the roster with **`user_id` and `display_name` only** —
      no `joined_at`, no counts (`docs/14` §3)
- [x] `PATCH` is admin-only; `timezone` is immutable; response echoes `effective_from`
- [x] `POST /groups/current/leave` sets `left_at`; historical rows untouched
- [x] Test: a member of group A gets `NOT_FOUND` for every group-B resource
- [x] Test: an ex-member's live token gets `NO_GROUP`

> **Open question:** "a member of group A gets `NOT_FOUND` for every group-B resource" has no
> request to make: no route in this function takes a group id, so there is nothing to point at
> group B. The test asserts the stronger property instead — a smuggled `group_id` in the body
> is rejected as an unknown key, and group A's member sees only group A. Revisit when a
> `round_id`-in-path route lands (E05-04), which is the first real IDOR surface.

> **Note:** `_shared/invite.ts` (CSPRNG generation, normalisation) landed here because
> `POST /groups` cannot work without it. E02-04 keeps the rate limits, the identical-
> `NOT_FOUND` guarantee, and the 10k-code distribution test.

---

### E02-04 — Invite code generation

**Status:** done · **Deps:** E02-03 · **Reads:** `docs/03` §2 (groups), `docs/14` §8
**Touches:** `functions/groups/index.ts`, `tests/functions/invite.test.ts`,
`tests/functions/_harness.ts`
**Verify:** `npm run test:functions -- invite`

Six characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` — no I, L, O, 0, or 1, because this
code gets read aloud and typed by teenagers.

- [x] Generated with a CSPRNG, not `Math.random`
- [x] Retry on unique violation, up to 5 attempts, then 500
- [x] Rate limits: 10/hour per user, 30/hour per IP on join (`docs/04` §8)
- [x] A bad code and a valid-but-unusable code return the identical `NOT_FOUND`
- [x] Test: 10k generated codes contain no excluded character and no duplicate

> **Note:** `migrations/0002_core_tables.sql` is listed under **Touches** in the original
> plan, but 0002 is merged and `CLAUDE.md` §4 forbids editing a merged migration. The invite
> alphabet's check constraint is already in it and is correct, so no migration changed here.
> Generation and normalisation had already landed in E02-01/E02-03; what this task added is
> the two limits, which are the control that actually stops a brute force.

> **Open question:** the unique-violation retry cannot be *forced* through the black-box HTTP
> suite — nothing outside the handler can make `generateInviteCode()` collide on demand, so
> `docs/15`'s "a passing test, not a manual check" is met only in part. The branch is covered
> by inspection plus a test that twelve created groups get twelve distinct well-formed codes.
> Forcing it needs either an injectable generator (a seam in `_shared/invite.ts` that exists
> only for tests) or a pgTAP test against `create_group` with a pre-seeded colliding code. The
> latter is preferred — it tests the constraint that actually raises — and belongs with the
> other `create_group` SQL tests. Ticked on that basis; owner to confirm.

> **Open question:** the per-IP limit is real state in `rate_limit_events` that outlives a test
> run, and roughly fifteen joins happen per suite run. A suite that shared one apparent IP
> would therefore start 429-ing on its second run inside an hour for reasons unrelated to the
> code under test. `tests/functions/_harness.ts` now sends a random RFC 2544 address as
> `x-forwarded-for` on every call so each one gets its own bucket; the two tests that are
> *about* the limits pin the header themselves. This assumes the edge runtime passes
> `x-forwarded-for` through untouched, which the "fresh address still gets through" assertion
> in `invite.test.ts` verifies rather than presumes. In production the header is set by the
> platform's proxy, so the same code path is exercised — but if a future deployment sits
> behind a second proxy, `clientIp()` takes the first entry and would need revisiting.

---

### E02-05 — Account deletion

**Status:** done · **Deps:** E02-03 · **Reads:** `docs/03` §6, `docs/14` §9
**Touches:** `migrations/0014_delete_account.sql`, `functions/me/index.ts`,
`tests/db/deletion.sql`, `tests/functions/me.test.ts`
**Verify:** `npm run test:db -- deletion`

Deletion must not cascade away submissions and guesses — other members' scores depend on
them.

> **Open question:** the planned filename was `0008_delete_account.sql`, but migrations
> through `0013` have already been applied by the parallel lifecycle lane. Adding `0008` now
> would be an out-of-order rewrite on existing databases, so the forward-only implementation
> is `0014_delete_account.sql`.

> **Open question:** `profiles.id` was defined as `references auth.users(id) on delete
> cascade`, while this task requires the profile to survive as the `Former member` principal.
> A primary key cannot also be a nullable auth link. The migration drops that foreign key;
> live profiles still use the auth UUID, and deleting the matching `auth.users` row is the
> unlink. This preserves every historical foreign key without adding a second identity that
> could drift.

- [x] `delete_account(user_id)` anonymises `display_name` to "Former member", unlinks auth,
      sets `left_at`
- [x] Submissions and guesses survive; The Record keeps attribution to "Former member"
- [x] Test: after deletion, every other member's standings are unchanged
- [x] Test: the deleted user cannot authenticate
- [x] Settings copy states this before confirming (coordinate with `docs/11`)
