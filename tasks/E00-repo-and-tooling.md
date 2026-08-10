# E00 — Repo, tooling, CI

Everything that must exist before any feature work. When this epic is done, all five verify
commands in `CLAUDE.md` §5 exist and pass on an empty project.

---

### E00-01 — Repo skeleton and npm scripts

**Status:** wip · **Deps:** — · **Reads:** `CLAUDE.md` §3–4, `docs/01` §3
**Touches:** `server/package.json`, `server/.env.example`, `.gitignore`, `.editorconfig`
**Verify:** `cd server && npm run test` (exits 0, "no tests yet" is fine)

Create the directory structure from `docs/01` §3 with `.gitkeep` where needed. `package.json`
declares the four scripts (`test:db`, `test:functions`, `audit:leak`, `test`), each currently
a stub that exits 0 with a clear message.

`.env.example` lists every secret name from `docs/01` §5 and `docs/06` §8 with empty values
and a one-line comment each. It contains no real values, ever.

- [ ] Directory tree matches `docs/01` §3
- [ ] Four npm scripts exist and exit 0
- [ ] `.env.example` complete; `.env` in `.gitignore`
- [ ] `git init`, initial commit

---

### E00-02 — Supabase local project

**Status:** wip · **Deps:** E00-01 · **Reads:** `docs/01` §1–2, §5
**Touches:** `server/supabase/config.toml`
**Verify:** `supabase start` then `supabase status` shows all services healthy

Initialise the Supabase project. In `config.toml`: enable Apple as an auth provider, disable
phone auth, and **disable the PostgREST-exposed schemas the client could reach** —
`db.schemas` should not expose anything the app needs, because the app needs nothing from
PostgREST (`docs/01` §2).

- [ ] `supabase init` complete, `config.toml` committed
- [ ] Apple auth provider configured (placeholder credentials, documented in `.env.example`)
- [ ] Phone auth off
- [ ] `supabase start` / `supabase db reset` documented in `README.md`'s local-setup section
- [ ] Replace the placeholder local-setup section in the root `README.md`

---

### E00-03 — Xcode project skeleton

**Status:** wip · **Deps:** E00-01 · **Reads:** `docs/13` §1, §8
**Touches:** `ios/BlindDrop.xcodeproj`, `ios/BlindDrop/App/`
**Verify:** `xcodebuild build -scheme BlindDrop -destination 'platform=iOS Simulator,name=iPhone 15'`

Create the project with the settings in `docs/13` §8. Empty folders per the tree in §1. Three
test targets (Unit, Snapshot, UI) wired into one scheme.

- [ ] iOS 17.0, Swift 6 language mode, strict concurrency
- [ ] Portrait only, iPhone only
- [ ] Capabilities: Push, Sign in with Apple, MusicKit, Associated Domains
- [ ] `blinddrop` URL scheme registered
- [ ] **No** `UIBackgroundModes`
- [ ] Three test targets build and run empty
- [ ] Zero package dependencies (verify `Package.resolved` is absent)

---

### E00-04 — CI pipeline and lint rules

**Status:** wip · **Deps:** E00-02, E00-03 · **Reads:** `docs/15` §3, `docs/13` §9, `docs/11` (voice section)
**Touches:** `.github/workflows/ci.yml`, `ios/scripts/lint.sh`
**Verify:** `./ios/scripts/lint.sh` passes; CI green on a trivial PR

The lint script is a set of grep-based rules — no SwiftLint dependency. Each rule prints the
offending file:line and the doc reference.

- [ ] `Date()` outside `Core/Time/ServerClock.swift` → fail (`docs/13` §5)
- [ ] Hex literal, `.font(.system(size:))`, or bare numeric padding in `Features/` → fail (`docs/07`)
- [ ] String literal passed to `Text(_:)` in `Features/` → fail (`docs/11`)
- [ ] `!` inside any `Localizable.strings` value → fail (`docs/11` voice)
- [ ] Banned words in `Localizable.strings` → fail (list in `docs/11` voice)
- [ ] `@unchecked Sendable` anywhere → fail
- [ ] `colorScheme` or `.dark` in `Features/` or `DesignSystem/` → fail (`docs/07`)
- [ ] CI: lint → `npm run test` → iOS unit + snapshot on push; + UI tests on PR to main

---

### E00-05 — Fixture server for iOS tests

**Status:** wip · **Deps:** E00-01 · **Reads:** `docs/04` (all payload shapes), `docs/15` §3
**Touches:** `ios/Fixtures/server.ts`, `ios/Fixtures/payloads/*.json`
**Verify:** `deno run ios/Fixtures/server.ts` then `curl localhost:8787/rounds/current` returns the `open` payload

A Deno script serving canned responses for every endpoint in `docs/04`, switchable between
phases by an env var (`PHASE=open|revealed|scored|voided`). The iOS scheme launches it and
points the app at it via a launch argument.

**This unblocks the entire iOS lane before the backend exists.** Build it early and keep the
payloads in sync with `docs/04` — a fixture that drifts from the contract is worse than no
fixture.

- [ ] One JSON payload file per phase, matching `docs/04` exactly
- [ ] `PHASE` env var switches the `/rounds/current` response
- [ ] Search returns 8 fixture tracks with real artwork template URLs and preview URLs
- [ ] Results payload uses the `docs/02` §4.4 numbers
- [ ] Configurable latency (`LATENCY_MS`) so the 400ms search budget can be tested
- [ ] Launch argument `-apiBaseURL` honoured by `AppEnvironment` (coordinate with E08-01)
