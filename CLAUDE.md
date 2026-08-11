# Operating manual for agents working on Blind Drop

Read this file completely. Then read only the docs your task names.

---

## 1. How to pick up work

```
tasks/BOARD.md          → status of every task, dependency graph
tasks/E##-<name>.md     → the epic containing the task, with full detail
```

Loop:

1. Open `tasks/BOARD.md`. Pick the top-most task whose deps are all `done` and whose status
   is `todo`.
2. Set its status to `wip` in `BOARD.md` **and** in the epic file. Commit that change alone.
3. Read the docs listed under that task's **Reads** field. Nothing else.
4. Implement.
5. Run the task's **Verify** commands. They must pass.
6. Tick the task's checklist, set status `done` in both places, commit.

If a task's spec is ambiguous, do not guess silently. Add a `> **Open question:**` block to
the epic file, pick the interpretation most protective of the blind window, note it in the
commit message, and continue.

**Never mark a task `done` with failing verification.** Mark it `blocked` and write why.

---

## 2. Rules that override everything

These are product-defining. A change here needs the owner, not an agent.

1. **No leak during `open`.** No endpoint may return, during a round's `open` phase, any of:
   another user's submission, a count of submissions, a member's submitted/not-submitted
   status, a timestamp derived from someone else's activity, or a payload length that varies
   with participation. Filtering in the client is not compliance.
2. **Server owns time.** The client renders countdowns from `server_now` + monotonic clock
   offset, never from `Date()` alone, and never decides a phase transition.
3. **Only submitters may guess.** Enforced server-side, not just disabled in the UI.
4. **Light mode only.** No dark mode in v1. Do not add `@Environment(\.colorScheme)`
   branches. The app is `.preferredColorScheme(.light)` at the root.
5. **Two accents, semantic only.** Amber = sealed/hidden. Ultramarine = revealed/live.
   Never both on one screen except the reveal transition. Never decorative.
6. **Three pushes a day, maximum.** See `docs/05-JOBS-AND-NOTIFICATIONS.md`. Adding a fourth
   is a product change.
7. **No gamification.** No streaks, badges, XP, levels, or cosmetics. See `docs/16`.
8. **Scores are derived, not stored.** Compute from `guesses` × `submissions` on read.

---

## 3. Repo layout

```
blind-drop/
├── README.md                  entry point
├── CLAUDE.md                  this file
├── docs/                      the spec (see README index)
├── tasks/                     the board and epics
├── server/                    Supabase project
│   ├── supabase/
│   │   ├── config.toml
│   │   ├── migrations/        NNNN_name.sql, forward-only
│   │   ├── functions/         Deno Edge Functions, one dir per endpoint group
│   │   │   ├── _shared/       auth, errors, http, db helpers
│   │   │   ├── me/
│   │   │   ├── groups/
│   │   │   ├── rounds/
│   │   │   ├── tracks/
│   │   │   ├── devices/
│   │   │   └── push-worker/
│   │   └── tests/             pgTAP + Deno tests
│   └── package.json
└── ios/
    ├── BlindDrop.xcodeproj
    └── BlindDrop/             see docs/13-IOS-APP-ARCHITECTURE.md for the full tree
```

**File map for token efficiency.** Before searching, check this table. It tells you which
directory owns a concern, so you can scope `grep`/`glob` instead of scanning the repo.

| Concern | Lives in |
|---|---|
| DB schema, RLS, indexes | `server/supabase/migrations/` |
| Phase transitions, scoring SQL | `server/supabase/migrations/` (plpgsql fns) |
| HTTP endpoints, payload shaping | `server/supabase/functions/<group>/` |
| Auth guards, error envelope | `server/supabase/functions/_shared/` |
| APNs, notification outbox drain | `server/supabase/functions/push-worker/` |
| Apple Music / Spotify calls | `server/supabase/functions/_shared/music/` |
| Colors, type, spacing tokens | `ios/BlindDrop/DesignSystem/` |
| Reusable views (cards, buttons) | `ios/BlindDrop/DesignSystem/Components/` |
| Seal / unseal animation | `ios/BlindDrop/DesignSystem/Motion/` |
| Screens | `ios/BlindDrop/Features/<Feature>/` |
| API client, DTOs | `ios/BlindDrop/Core/Networking/` |
| Server-time clock | `ios/BlindDrop/Core/Time/` |
| Keychain, Spotify OAuth | `ios/BlindDrop/Core/Auth/` |
| Share image rendering | `ios/BlindDrop/Features/Results/Share/` |
| All user-facing strings | `ios/BlindDrop/Resources/Localizable.strings` |

---

## 4. Conventions

### Swift
- Swift 6 language mode, strict concurrency. iOS 17.0 deployment target.
- SwiftUI only. No UIKit view controllers except `ASWebAuthenticationSession` hosting.
- State: `@Observable` model objects owned by a feature-scoped `…Store`. No singletons
  except `AppEnvironment`, injected through `.environment(…)`.
- Networking: `async/await` + `URLSession`. No third-party HTTP library.
- Zero third-party dependencies in v1 except the Bricolage Grotesque font file. If you
  believe you need one, write an open question instead of adding it.
- Naming: `SubmitScreen`, `SubmitStore`, `SubmitViewState`. Views are `…Screen` (routed) or
  `…View` (composed).
- Never hardcode a color, font size, or spacing value in a feature file. Pull from
  `DesignSystem`. A raw hex in `Features/` is a review failure.

### TypeScript (Edge Functions)
- Deno, `std` only plus `@supabase/supabase-js`. No Express-style frameworks.
- Every handler: parse → authenticate → authorize → load → **shape** → respond. The shaping
  step is explicit and never `select *` passed through.
- Responses go through `_shared/http.ts` `ok()` / `fail()`. Never `new Response` in a handler.
- All timestamps in JSON are RFC 3339 UTC with `Z`. Never a local-time string.

### SQL
- Forward-only migrations, `NNNN_short_name.sql`, never edited after merge.
- RLS enabled and **deny-by-default** on every table. Edge Functions use the service role and
  do their own authorization; RLS is the second lock, not the only one.
- Money/percentages are never stored. Derived reads live in SQL views or functions.

### Git
- Branch per task: `t/E03-02-round-tick`. Conventional commits.
- Commit the board status change separately from the implementation.

---

## 5. Verification you must run before `done`

| Layer | Command |
|---|---|
| SQL | `npm run test:db` (pgTAP, in `server/`) |
| Edge Functions | `npm run test:functions` (Deno test) |
| Leak audit | `npm run audit:leak` — asserts `open`-phase payloads by golden file |
| iOS unit | `xcodebuild test -scheme BlindDrop -destination 'platform=iOS Simulator,name=iPhone 15'` |
| iOS snapshot | included in the above scheme |

`E00` is responsible for making all five commands exist and pass on an empty project.

---

## 6. Tone for anything user-facing

Dry, plain, active, a little arch. Sentence case. No exclamation marks. The app never cheers.
Buttons name what happens and keep the name through the flow: **Drop a song → Seal it →
Sealed**. Never "Submit". Never "Submitted".

Do not invent strings. Every string is in `docs/11-COPY-DECK.md`. If you need one that isn't
there, add it to the copy deck in the same commit.

---

## 7. What "done" looks like

A task is done when its checklist is ticked, its verify commands pass, no rule in §2 is
violated, and the acceptance criteria it maps to in `docs/15-TESTING-AND-ACCEPTANCE.md` have
a passing test — not a manual check.
