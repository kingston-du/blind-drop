# E00 — Repo, tooling, CI

Everything that must exist before any feature work. When this epic is done, all five verify
commands in `CLAUDE.md` §5 exist and pass on an empty project.

---

### E00-01 — Repo skeleton and npm scripts

**Status:** done · **Deps:** — · **Reads:** `CLAUDE.md` §3–4, `docs/01` §3
**Touches:** `server/package.json`, `server/.env.example`, `.gitignore`, `.editorconfig`
**Verify:** `cd server && npm run test` (exits 0, "no tests yet" is fine)

Create the directory structure from `docs/01` §3 with `.gitkeep` where needed. `package.json`
declares the four scripts (`test:db`, `test:functions`, `audit:leak`, `test`), each currently
a stub that exits 0 with a clear message.

`.env.example` lists every secret name from `docs/01` §5 and `docs/06` §8 with empty values
and a one-line comment each. It contains no real values, ever.

- [x] Directory tree matches `docs/01` §3
- [x] Four npm scripts exist and exit 0
- [x] `.env.example` complete; `.env` in `.gitignore`
- [x] `git init`, initial commit

---

### E00-02 — Supabase local project

**Status:** done · **Deps:** E00-01 · **Reads:** `docs/01` §1–2, §5
**Touches:** `server/supabase/config.toml`
**Verify:** `supabase start` then `supabase status` shows all services healthy

Initialise the Supabase project. In `config.toml`: enable Apple as an auth provider, disable
phone auth, expose `public` to PostgREST so the production attack surface can be tested, and
grant `anon`/`authenticated` no privileges on it. The app needs and receives no data from
PostgREST (`docs/01` §2).

- [x] `supabase init` complete, `config.toml` committed
- [x] Apple auth provider configured (placeholder credentials, documented in `.env.example`)
- [x] Phone auth off
- [x] `supabase start` / `supabase db reset` documented in `README.md`'s local-setup section
- [x] Replace the placeholder local-setup section in the root `README.md`

> **Resolved — owner, 2026-08-12:** the task said to "disable the PostgREST-exposed schemas the client could
> reach", but `E01-02` had required a test in which an authenticated PostgREST `select` on each
> table *returns `[]`*. Those pull in opposite directions: with `public` unexposed, PostgREST
> answers with a schema error and the lock is never exercised; with `public` exposed and
> everything revoked, the request fails closed with `42501` and the test is meaningful
> against the same surface production has. Taken the second reading — `schemas = ["public"]`,
> `graphql_public` removed entirely, Realtime off, `auto_expose_new_tables = false` — because
> a lock nobody tests is the weaker protection. `tests/db/rls.sql` asserts every table fails
> closed for both `anon` and `authenticated`.

> **Resolved — owner, 2026-08-12:** Postgres 17 is the project version. Local, CI, staging and
> production must use 17; no environment may silently fall back to 15.

> **Note:** ports moved from Supabase's 543xx defaults to 544xx so this stack coexists with
> another local Supabase project on the same machine. `README.md` lists them.

---

### E00-03 — Xcode project skeleton

**Status:** done · **Deps:** E00-01 · **Reads:** `docs/13` §1, §8
**Touches:** `ios/BlindDrop.xcodeproj`, `ios/BlindDrop/App/`
**Verify:** `xcodebuild build -scheme BlindDrop -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17'`

Create the project with the settings in `docs/13` §8. Empty folders per the tree in §1. Three
test targets (Unit, Snapshot, UI) wired into one scheme.

- [x] iOS 17.4, Swift 6 language mode, strict concurrency
- [x] Portrait only, iPhone only
- [x] Capabilities: Push, Sign in with Apple, MusicKit, Associated Domains
- [x] `blinddrop` URL scheme registered
- [x] **No** `UIBackgroundModes`
- [x] Three test targets build and run empty
- [x] Zero package dependencies (verify `Package.resolved` is absent)

> **Resolved — owner, 2026-08-12:** routine CI uses a centrally configured, pinned Xcode and
> current simulator destination, presently `OS=latest,name=iPhone 17`; commands do not name a
> simulator independently. E13 raised the deployment target to iOS 17.4 for Apple's HTTPS
> authentication-session callback matcher. Before release, the full suite also runs once on
> an iOS 17.4 runtime so the minimum supported version is real, not only a build setting.

> **Note:** the project uses Xcode 16+ file-system-synchronized groups, so `Features/…`,
> `DesignSystem/…` and the rest sync from disk and no future task has to edit
> `project.pbxproj` to add a file. `Info.plist`, the entitlements, and the `.gitkeep`
> placeholders are listed as membership exceptions so they are not copied as bundle
> resources.

> **Note:** signing is off (`CODE_SIGNING_ALLOWED = NO`) because this repo has no Apple
> team. The entitlements file is complete and committed; a `DEVELOPMENT_TEAM` has to be set
> before the first device build or TestFlight upload.

---

### E00-04 — CI pipeline and lint rules

**Status:** done · **Deps:** E00-02, E00-03 · **Reads:** `docs/15` §3, `docs/13` §9, `docs/11` (voice section)
**Touches:** `.github/workflows/ci.yml`, `ios/scripts/lint.sh`
**Verify:** `./ios/scripts/lint.sh` passes; CI green on a trivial PR

The lint script is a set of grep-based rules — no SwiftLint dependency. Each rule prints the
offending file:line and the doc reference.

- [x] `Date()` outside `Core/Time/ServerClock.swift` → fail (`docs/13` §5)
- [x] Hex literal, `.font(.system(size:))`, or bare numeric padding in `Features/` → fail (`docs/07`)
- [x] String literal passed to `Text(_:)` in `Features/` → fail (`docs/11`)
- [x] `!` inside any `Localizable.strings` value → fail (`docs/11` voice)
- [x] Banned words in `Localizable.strings` → fail (list in `docs/11` voice)
- [x] `@unchecked Sendable` anywhere → fail
- [x] `colorScheme` or `.dark` in `Features/` or `DesignSystem/` → fail (`docs/07`)
- [x] CI: lint → `npm run test` → iOS unit + snapshot on push; + UI tests on PR to main

---

### E00-05 — Fixture server for iOS tests

**Status:** done · **Deps:** E00-01 · **Reads:** `docs/04` (all payload shapes), `docs/15` §3
**Touches:** `ios/Fixtures/server.ts`, `ios/Fixtures/payloads/*.json`
**Verify:** `deno run ios/Fixtures/server.ts` then `curl localhost:8787/rounds/current` returns the `open` payload

A Deno script serving canned responses for every endpoint in `docs/04`, switchable between
phases by an env var (`PHASE=open|revealed|scored|voided`). The iOS scheme launches it and
points the app at it via a launch argument.

**This unblocks the entire iOS lane before the backend exists.** Build it early and keep the
payloads in sync with `docs/04` — a fixture that drifts from the contract is worse than no
fixture.

- [x] One JSON payload file per phase, matching `docs/04` exactly
- [x] `PHASE` env var switches the `/rounds/current` response
- [x] Search returns 8 fixture tracks with real artwork template URLs and preview URLs
- [x] Results payload uses the `docs/02` §4.4 numbers
- [x] Configurable latency (`LATENCY_MS`) so the 400ms search budget can be tested
- [x] Launch argument `-apiBaseURL` passed by the UI test target (`AppEnvironment` must read
      it — carried into E08-01)

> **Note:** phases are `open | open_nosub | revealed | revealed_nosub |
> revealed_joinedlate | scored | voided`. The `_nosub` and `_joinedlate` variants exist
> because AC-1 and AC-6 both turn on the *absence* of data for a particular caller, and a
> single payload per state cannot express that. `ANCHOR=now` (the default) re-times the
> round around `server_now` so countdowns are live; `ANCHOR=fixed` serves the literal
> timestamps for golden-file work.
