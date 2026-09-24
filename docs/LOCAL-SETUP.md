# Local setup

The full local development reference. The short version is in the [README](../README.md).


Requires Docker. Everything else (the Supabase CLI and Deno) installs as a local
devDependency, so there is nothing to install globally.

```bash
cd server
npm install          # Supabase CLI + Deno, pinned in package.json
npm run db:start     # first run pulls images and takes a few minutes
```

`db:start` applies every migration in `supabase/migrations/` and loads `supabase/seed.sql`,
so you land on the `docs/02` §4.4 fixture: one group, nine profiles (Ana…Ivy), and three
rounds: 2026-08-08 `scored`, 2026-08-09 `revealed`, 2026-08-10 `open`.

This stack runs on the **544xx** ports, not Supabase's 543xx defaults, so it coexists with
any other local Supabase project:

| Service | URL |
|---|---|
| API / Edge Functions | `http://127.0.0.1:54421` |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54422/postgres` |
| Studio | `http://127.0.0.1:54423` |
| Mail (Mailpit) | `http://127.0.0.1:54424` |

## Scheduler settings

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

## Tests

```bash
cd server
npm run test:db              # pgTAP, against the running local database
npm run test:db -- seed      # just one file
npm run test:functions       # Deno, the Edge Functions
npm run audit:leak           # the AC-1 group, see docs/15 §1
npm test                     # all three
```

`test:db` expects the seeded fixture, and `test:functions` creates real groups. So before
running `npm test` a second time, reseed with `npm run db:reset`, or `test:db` will stop and
tell you the fixture has drifted.

`npm run audit:leak` is the most important command in this repo. It runs the golden payload,
byte-length, timing-correlation, and PostgREST-lockdown suites and gates release in E14-01.

The pgTAP suite never sleeps. Lifecycle code calls `public.now_()` rather than `now()`, and
tests move the clock with `tests.set_test_now(…)`; the runner fails the run if `pg_sleep`
appears anywhere in `tests/db/`.

## The iOS fixture server

The iOS lane does not need the backend. `ios/Fixtures/server.ts` serves canned responses for
every endpoint in `docs/04`:

```bash
cd ios/Fixtures
PHASE=open ../../server/node_modules/.bin/deno run --allow-net --allow-read --allow-env server.ts
```

`PHASE` is one of `open | sealed | revealed | scored | voided`, and `LATENCY_MS` adds delay
so the 400ms search budget can be exercised. See `ios/Fixtures/README.md`.
