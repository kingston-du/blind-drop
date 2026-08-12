# 01 — Architecture

---

## 1. Stack

| Layer | Choice | Version |
|---|---|---|
| Client | Native SwiftUI | iOS 17.0 minimum, Swift 6 strict concurrency |
| Auth | Supabase Auth — Sign in with Apple (primary), phone OTP (flagged) | — |
| API | Supabase Edge Functions (Deno / TypeScript) | hand-written handlers only |
| Database | Postgres 17 (Supabase) | RLS deny-by-default |
| Scheduler | `pg_cron` + `pg_net` | 1-minute tick |
| Push | APNs, HTTP/2, token-based (ES256 JWT) | from `push-worker` function |
| Catalog | Apple Music API (REST, server-proxied) | developer-token JWT, ES256 |
| Bridge | Spotify Web API (client-credentials for lookup, PKCE for export) | — |
| Analytics | None in v1 | — |

**Zero third-party iOS dependencies** except the bundled Bricolage Grotesque variable font.
**Zero server dependencies** beyond Deno `std` and `@supabase/supabase-js`.

---

## 2. Request path

```
iOS app
  │  Authorization: Bearer <supabase access token>
  ▼
Edge Function  (functions/v1/rounds/current)
  │  1. parse
  │  2. authenticate  → user_id from JWT
  │  3. authorize     → membership in group, phase gate
  │  4. load          → service-role queries
  │  5. SHAPE         → construct the DTO field by field
  ▼
Postgres  (RLS on, service role bypasses it — authorization is done in step 3)
```

The **shape** step is the security boundary. There is no `select *` that reaches a client.
Every response DTO is built by naming its fields. See `14-SECURITY-AND-THREAT-MODEL.md`.

### PostgREST is off-limits

Supabase's auto-generated REST/Realtime API is **disabled for client use**. The iOS app never
calls `/rest/v1/…`. Reasons: the generated API leaks row counts through `Content-Range`,
leaks table shape through error messages, and makes "which columns can this user see right
now" a phase-dependent RLS puzzle that is easy to get subtly wrong. Enforcement:

- Every table has `REVOKE ALL … FROM anon, authenticated`.
- RLS policies exist anyway, deny-by-default, as a second lock.
- `E14` includes a test that asserts authenticated and anonymous PostgREST calls to every
  table fail with PostgreSQL `42501 permission denied`. Failing at the privilege layer is
  stronger than returning an empty result through RLS alone.

---

## 3. Repo layout

```
blind-drop/
├── docs/                                 spec
├── tasks/                                board + epics
├── server/
│   ├── package.json                      npm scripts: test:db, test:functions, audit:leak
│   ├── .env.example
│   └── supabase/
│       ├── config.toml
│       ├── migrations/
│       │   ├── 0001_extensions.sql
│       │   ├── 0002_core_tables.sql
│       │   ├── 0003_rls.sql
│       │   ├── 0004_round_lifecycle.sql   plpgsql: ensure_rounds, tick_rounds
│       │   ├── 0005_scoring.sql           plpgsql/views: round_scores, standings
│       │   ├── 0006_notifications.sql     outbox + unique idempotency key
│       │   ├── 0007_track_links.sql       ISRC ↔ apple ↔ spotify cache
│       │   ├── 0010_service_role_grants.sql  least-privilege grants for the API role
│       │   ├── 0011_rate_limits.sql       sliding-window limiter (docs/04 §8)
│       │   ├── 0012_group_api.sql         timezone validation, atomic group creation
│       │   ├── 0013_tick_rounds_reveal.sql reveal/void transition
│       │   ├── 0014_delete_account.sql    anonymise, don't cascade
│       │   ├── 0015_tick_rounds_score_nudge.sql score/nudge transition
│       │   ├── 0016_cron.sql              pg_cron job registration
│       │   ├── 0017_track_meta_spotify_patch.sql track bridge metadata
│       │   ├── 0018_submission_upsert.sql atomic submission upsert
│       │   ├── 0019_links_worker_job.sql  track-link backfill job
│       │   ├── 20260811194721_claim_notifications.sql durable push claims
│       │   └── 20260811201246_notification_retry.sql push retry state
│       ├── functions/
│       │   ├── _shared/
│       │   │   ├── http.ts                ok(), fail(), error envelope
│       │   │   ├── auth.ts                requireUser(), requireMembership()
│       │   │   ├── db.ts                  service-role client
│       │   │   ├── time.ts                serverNow(), phase gates
│       │   │   ├── dto.ts                 every response shape, in one place
│       │   │   └── music/
│       │   │       ├── appleMusic.ts      dev-token JWT, search, lookup
│       │   │       ├── spotify.ts         client-credentials, isrc lookup
│       │   │       └── resolve.ts         url/isrc → canonical Track
│       │   ├── me/index.ts
│       │   ├── groups/index.ts
│       │   ├── rounds/index.ts            current, submission, reveal, guesses, results
│       │   ├── tracks/index.ts            search, resolve
│       │   ├── devices/index.ts
│       │   └── push-worker/index.ts       drains notification_outbox → APNs
│       └── tests/
│           ├── db/*.sql                   pgTAP
│           ├── functions/*.test.ts        Deno
│           └── golden/                    leak-audit golden payloads
└── ios/
    ├── BlindDrop.xcodeproj
    ├── BlindDrop/                        see 13-IOS-APP-ARCHITECTURE.md
    └── BlindDropTests/
```

---

## 4. Architecture decision records

### ADR-001 — Supabase Edge Functions over a bespoke Node service

**Decision.** Host on Supabase; write every endpoint as a hand-rolled Edge Function.

**Why.** The build needs Postgres, a scheduler, auth with Sign in with Apple, and a push
worker. Supabase supplies four of those on day one, which is most of `E01`–`E02` deleted. The
one thing we refuse is its generated API — and refusing it costs nothing, because we were
going to hand-write payload shaping anyway (acceptance criterion #1 demands byte-level
control of responses).

**Rejected.** Fastify + Postgres on Fly.io. More control, but we'd rebuild Apple Sign-in
token verification, a job runner, and connection pooling for no gain the spec asks for.

**Would revisit if.** Edge Function cold starts push `GET /rounds/current` past ~600ms p95,
or the group count grows past a few thousand and the 1-minute tick becomes a hot loop.

### ADR-002 — Apple Music via a **server-side** proxy, not client MusicKit

**Decision.** Song search, metadata, and preview URLs come from the Apple Music REST API
called by our server with a developer-token JWT. The client plays previews with `AVPlayer`
from the returned URL. The MusicKit framework is used **only** for Apple Music playlist
export.

**Why.** Three wins.
1. **No permission prompt in the critical path.** Client-side MusicKit catalog search
   requires `MusicAuthorization.request()`. A denied prompt at second 10 of a 90-second loop
   kills the product. The REST proxy needs nothing from the user.
2. **The server always sees the ISRC.** That is the key the entire Spotify bridge hangs on
   (`06-MUSIC-INTEGRATION.md`). If search happened on-device we'd need a second round trip to
   get it server-side anyway.
3. **No Apple Music subscription required** for search or 30-second previews.

**Cost.** We hold and rotate an Apple Music private key server-side, and search adds one
network hop. Mitigated by a 10-minute edge cache on search queries.

**Rejected.** Client MusicKit for search — permission prompt, no server-side ISRC.

### ADR-003 — Cards are addressed by `card_no`, never by `submission_id`

**Decision.** The reveal payload identifies cards as `1…N` within the round. Guesses are
written against `card_no`. `submission_id` never crosses the wire before the round is
`scored`.

**Why.** A submission's UUID is a stable, guessable-order-adjacent identifier that exists
before the reveal. Exposing it invites correlation attacks (compare IDs across rounds, infer
creation order from any leak in UUID generation). `card_no` exists only after the reveal, is
meaningful only within one round, and carries exactly the information the game intends.

### ADR-004 — Scores derived on read, never stored

**Decision.** `readability` and `ear` are computed from `guesses` × `submissions` by SQL
views. No score columns.

**Why.** Scoring rules have three edge cases (duplicates, non-guessers, mid-round joiners) and
will be tweaked during the pilot. Stored scores mean a backfill every tweak, and a
denormalization bug is invisible until someone notices their number is wrong. Group sizes are
6–12 and rounds are one per day — this will never be slow.

**Escape hatch.** If standings ever exceed ~150ms, add a materialized view refreshed at
score time. Do not denormalize into `submissions`.

### ADR-005 — One group per user, enforced in the schema

**Decision.** A user has at most one active membership. The endpoint is `/groups/current`,
singular, with no group ID in any client-facing path.

**Why.** Multi-group is explicitly out of scope, and every "which group?" parameter is a
place where a future agent adds scaffolding the spec forbids. Encoding singularity in the
route shape makes the constraint structural rather than a comment.

**Cost.** If multi-group ever ships, every route changes. Accepted — that is a v2 rewrite of
the navigation model anyway.

---

## 5. Environments

| Env | Supabase project | APNs | Apple Music | Spotify |
|---|---|---|---|---|
| `local` | `supabase start` | sandbox, or logged-to-console | real dev token | dev-mode app |
| `staging` | separate project | sandbox | real dev token | dev-mode app |
| `prod` | separate project | production | real dev token | same app, extended-quota request pending |

Secrets live in Supabase function secrets, never in the repo. `server/.env.example` lists the
names: `APPLE_MUSIC_KEY_ID`, `APPLE_MUSIC_TEAM_ID`, `APPLE_MUSIC_PRIVATE_KEY`,
`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`, `SPOTIFY_CLIENT_ID`,
`SPOTIFY_CLIENT_SECRET`.

> **Note for the pilot.** Spotify apps created today start in *development mode*, capped at
> 25 manually-added users. A 6–12 person pilot fits inside that cap. Extended-quota approval
> is only needed before public release, and Spotify preview URLs are **not** used at all
> (previews come from Apple), so the 2024 preview-endpoint restriction does not affect us.
> See `06-MUSIC-INTEGRATION.md` §6.

---

## 6. Non-functional targets

| Metric | Target |
|---|---|
| `GET /rounds/current` p95 | < 300ms |
| Track search p95 | < 400ms |
| Reveal push → all devices | < 20s spread |
| Phase transition accuracy | fires within 60s of the target minute |
| Seal / unseal animation | 60fps on iPhone 12 |
| Cold app launch → today's round rendered | < 1.2s |
