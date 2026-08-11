# Blind Drop

A daily blind music-guessing game for one private friend group (6–12 people).

Every day each member submits **one song, blind**. At 8:00 PM the songs are revealed as an
anonymous numbered list. Everyone has two hours to guess who dropped what. At 10:00 PM the
answers and scores land.

**This is not a music player, a playlist app, or a social network.** It is a daily guessing
game with a music substrate. Check every implementation decision against that sentence.

---

## Status

The backend game loop through reveal and scoring is in, along with the Apple Music catalog
proxy and Spotify bridge. Push delivery (`E06`) and Record/export endpoints (`E07-06`) are
the remaining backend epics; iOS foundation work is underway in `E08`.

| Area | State |
|---|---|
| Spec | Complete — `docs/` |
| Task board | `tasks/BOARD.md` |
| Backend | Auth, groups, lifecycle, submissions, reveal, guessing, scoring, and music bridging are covered by pgTAP and function tests. |
| iOS client | Project foundation is underway in `E08`; palette tokens and contrast tests are in. |

---

## If you are a coding agent picking this up

1. Read [`CLAUDE.md`](CLAUDE.md) first. It is the operating manual: conventions, file map,
   and the rules you must not break.
2. Open [`tasks/BOARD.md`](tasks/BOARD.md), find the first task whose dependencies are all
   `done`, and read its epic file in `tasks/`.
3. Each task names the exact docs you need. **Read only those.** The spec is split so you
   never have to load all of it.

Do not start by reading every file in `docs/`. That is ~40k tokens and almost none of it is
relevant to any single task.

---

## The one-paragraph architecture

Native SwiftUI iOS app (iOS 17+) talking to a Supabase-hosted Postgres over hand-written
Edge Functions — **never** over auto-generated table endpoints. All phase state is
server-authoritative; the client never decides what time it is. Song search runs through a
server-side Apple Music API proxy (so no MusicKit permission prompt and the server always
captures the ISRC), and every track is bridged to Spotify by ISRC so the group's archive
exports to either service.

Full detail: [`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md).

---

## The three things that must not break

1. **The blind window.** During the `open` phase the API must not return another user's
   submission, a submission count, a member's submission status, or anything you can derive
   one from. Not filtered in the client — *absent from the payload*. See
   [`docs/14-SECURITY-AND-THREAT-MODEL.md`](docs/14-SECURITY-AND-THREAT-MODEL.md).
2. **Server-authoritative time.** Changing the device clock or timezone must have zero
   effect on what phase the app believes it is in.
3. **The seal.** The ~600ms seal animation is the moment the app is remembered by. It gets
   disproportionate effort. See [`docs/09-MOTION-SPEC.md`](docs/09-MOTION-SPEC.md).

---

## Doc index

| File | What it covers | Read it when |
|---|---|---|
| `docs/00-PROJECT-BRIEF.md` | Product intent, goals, non-goals, pilot success criteria | Onboarding to the project |
| `docs/01-ARCHITECTURE.md` | Stack, repo layout, ADRs | Any structural decision |
| `docs/02-DOMAIN-RULES.md` | Phase machine, edge cases, scoring math | Any logic task, client or server |
| `docs/03-DATA-MODEL.md` | Postgres schema, RLS, indexes | Any DB task |
| `docs/04-API-CONTRACT.md` | Every endpoint, exact payloads, error codes | Any client↔server task |
| `docs/05-JOBS-AND-NOTIFICATIONS.md` | Scheduler, idempotency, APNs | Round lifecycle, push |
| `docs/06-MUSIC-INTEGRATION.md` | Apple Music proxy, ISRC, Spotify bridge + export | Search, previews, links, export |
| `docs/07-DESIGN-SYSTEM.md` | Light-mode palette, type scale, spacing, components | Any UI task |
| `docs/08-SCREEN-SPECS.md` | Screen-by-screen, every state | Building a screen |
| `docs/09-MOTION-SPEC.md` | Seal, unseal, reduced motion | Animation tasks |
| `docs/10-SHARE-CARD-SPEC.md` | Share image render spec | Results/share task |
| `docs/11-COPY-DECK.md` | Every user-facing string | Any UI task |
| `docs/12-ACCESSIBILITY.md` | Dynamic Type, VoiceOver, contrast | Any UI task |
| `docs/13-IOS-APP-ARCHITECTURE.md` | SwiftUI module layout, state, file tree | Any iOS task |
| `docs/14-SECURITY-AND-THREAT-MODEL.md` | Leak rules, auth, token handling | Backend + auth tasks |
| `docs/15-TESTING-AND-ACCEPTANCE.md` | Acceptance criteria mapped to tests | Before calling anything done |
| `docs/16-OUT-OF-SCOPE.md` | What not to build | When you feel like adding something |

---

## Local setup

Requires Docker. Everything else — the Supabase CLI and Deno — installs as a local
devDependency, so there is nothing to install globally.

```bash
cd server
npm install          # Supabase CLI + Deno, pinned in package.json
npm run db:start     # first run pulls images and takes a few minutes
```

`db:start` applies every migration in `supabase/migrations/` and loads `supabase/seed.sql`,
so you land on the `docs/02` §4.4 fixture: one group, nine profiles (Ana…Ivy), and three
rounds — 2026-08-08 `scored`, 2026-08-09 `revealed`, 2026-08-10 `open`.

This stack runs on the **544xx** ports, not Supabase's 543xx defaults, so it coexists with
any other local Supabase project:

| Service | URL |
|---|---|
| API / Edge Functions | `http://127.0.0.1:54421` |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54422/postgres` |
| Studio | `http://127.0.0.1:54423` |
| Mail (Mailpit) | `http://127.0.0.1:54424` |

### Scheduler settings

The `tick` and `push` cron jobs are installed by migration. The push job reads its function
host and service credential from target-database settings so neither value is committed or
stored in `cron.job`. Set them once in each environment, using the SQL editor or `psql`
connected to that database:

```sql
alter database postgres set app.functions_url = 'https://<project-ref>.supabase.co/functions/v1';
alter database postgres set app.service_key = '<that environment service-role key>';
```

For the local Docker stack, use `http://kong:8000/functions/v1` for `app.functions_url` and
the `SERVICE_ROLE_KEY` reported by `supabase status -o env`. `kong` is the internal hostname
reachable from the database container; `127.0.0.1:54421` is only the host-machine address.
`ALTER DATABASE` applies to new sessions, including the next cron invocation. The local seed
pauses both jobs so its dated fixture cannot advance under the real clock; after setting the
values, opt into the live local scheduler explicitly:

```sql
select public.set_blind_drop_jobs_active(true);
```

```bash
npm run db:reset     # re-run all migrations + seed from scratch
npm run db:stop      # stop the stack
```

Secrets: copy `server/.env.example` to `server/.env` and fill it in. `.env` is git-ignored
and must never be committed. Deployed environments read the same names from Supabase
function secrets (`docs/01` §5).

### Tests

```bash
cd server
npm run test:db              # pgTAP, against the running local database
npm run test:db -- seed      # just one file
npm run test:functions       # Deno, the Edge Functions
npm run audit:leak           # the AC-1 group — see docs/15 §1
npm test                     # all three
```

`npm run audit:leak` is the most important command in this repo. It runs the golden payload,
byte-length, timing-correlation, and PostgREST-lockdown suites and gates release in E14-01.

The pgTAP suite never sleeps. Lifecycle code calls `public.now_()` rather than `now()`, and
tests move the clock with `tests.set_test_now(…)`; the runner fails the run if `pg_sleep`
appears anywhere in `tests/db/`.

### The iOS fixture server

The iOS lane does not need the backend. `ios/Fixtures/server.ts` serves canned responses for
every endpoint in `docs/04`:

```bash
cd ios/Fixtures
PHASE=open ../../server/node_modules/.bin/deno run --allow-net --allow-read --allow-env server.ts
```

`PHASE` is one of `open | sealed | revealed | scored | voided`, and `LATENCY_MS` adds delay
so the 400ms search budget can be exercised. See `ios/Fixtures/README.md`.
