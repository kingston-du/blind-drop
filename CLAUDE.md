# Operating manual for agents working on Blind Drop

Read this file completely. Then read only the docs your task names.

---

## 1. How to pick up work

```
tasks/BOARD.md          → status of every task, dependency graph
tasks/E##-<name>.md     → the epic containing the task, with full detail
```

The loop below is the minimum, and it is what `E00`–`E16` were built under. **§8 is the current
process** — it wraps this loop with planning, review and running the app, and it is what "do
the next slice" means. Read §8 before starting `E17-10` or anything in `E18` or later.

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
   Never both on one screen except the reveal transition and **How to play**. Never decorative.

   How to play is the second exception because it is the **legend**: its four steps are the four
   phases of a round, so colouring them is not decoration, it is the key the rest of the app is
   read against. The carve-out is that page and nothing else — a screen that merely mentions a
   phase does not inherit it, and the rest of How to play (the scoring card, the notes) stays
   neutral. See `Features/HowTo/HowToSheet.swift`, which argues it at length; do not revert it
   as a rule violation.

   **The circle switcher is the third exception, amended by the owner (`E42-01`).** It lists
   circles that are genuinely in different phases at the same moment, so one accent per screen
   cannot express what the screen is for. It is bounded, and the bounds are the rule:
   - **The mark tier only.** `PhaseAccent.mark` on an 8pt pip. Never `text`, never `fill` — four
     accent-coloured *words* is a category colour, a mark is a signal.
   - **One accent-bearing element.** Selection (`ink` rail), attention (`ink` vs `inkDim` on the
     state word) and both footer buttons stay neutral. `PrimaryButton.Fill.neutral` is `ink` and
     is explicitly not a third accent.
   - **That sheet and nothing else.** A future screen listing cross-circle state does **not**
     inherit this by precedent. It needs the owner, the same as this did.

   See `Features/Circles/CircleSwitcherSheet.swift` and `PhaseAccent.init(_:CircleState)`.
6. **No fixed daily push cap — but the kinds are still a closed set, and coincident circles
   still group.** See `docs/05-JOBS-AND-NOTIFICATIONS.md`. Originally three deliveries per user
   per day; **amended by the owner** when multi-circle landed (ADR-011), which kept the cap at
   three but stopped it growing with circle count. **Amended again by the owner**, on the same
   footing as ADR-011, in `docs/17-NEXT-FEATURES.md` §5 (E31): the unconditional `nudge` is
   retired for two conditional reminders, `seal_reminder` (up to twice a round) and
   `guess_reminder` (once), and the 3/day cap is lifted to admit them — a fully disengaged
   member in one circle can now see up to five pushes in an evening (both `seal_reminder`s,
   `reveal`, `guess_reminder`, `results`). What the cap protected is otherwise unchanged: a
   reveal that fires for three circles at the same hour is still **one** grouped notification,
   not three, and the kinds themselves stay closed — `seal_reminder`, `guess_reminder`,
   `reveal`, `results`, `void`, plus `invite` (E20). A seventh kind, or a push that mentions
   another member's status or a count, is a product change and needs the owner. `nudge` is
   retired; the label is not removed from the database (Postgres cannot drop an enum value),
   but no code path produces it anymore.
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
- Swift 6 language mode, strict concurrency. iOS 17.4 deployment target (Spotify's required
  HTTPS OAuth callback uses `ASWebAuthenticationSession.Callback.https`, introduced in 17.4).
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

Run what the slice touches, not everything. iOS-only work does not need the Supabase stack up.

| Layer | Command | Notes |
|---|---|---|
| iOS lint | `./ios/scripts/lint.sh` | Seconds, no simulator. Grep rules; `--self-test` proves they still fire. |
| iOS unit + snapshot | `cd ios && xcodebuild test -scheme BlindDrop -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' -derivedDataPath .build -only-testing:BlindDropUnitTests -only-testing:BlindDropSnapshotTests` | ~4 min. Narrow with more `-only-testing:` while iterating. |
| iOS fixture-backed | `./ios/scripts/verify-fixture.sh BlindDropUnitTests/FixtureRoundTests "Round"` | Starts and stops its own Deno fixture server. |
| iOS UI loop | `-only-testing:BlindDropUITests` with the fixture server on `127.0.0.1:8787` and `TEST_RUNNER_CI=1` | Without that variable a missing fixture **skips** and reports green. |
| Server lint | `node server/scripts/lint.mjs` | Dependency-free on purpose. |
| SQL | `cd server && npm run test:db` | pgTAP. Needs `npm run db:start`. |
| Edge Functions | `cd server && npm run test:functions` | Deno, black-box HTTP. Needs the local stack **and** the edge runtime. |
| Leak audit | `cd server && npm run audit:leak` | AC-1's gate. Never let this regress quietly. |
| Everything server | `cd server && npm test` | Chains the three above. |

**Snapshot goldens.** A mismatch is not automatically a failure — it is a question. Look at
`ios/BlindDropTests/__Snapshots__/__Failures__/<Suite>/*.{actual,expected,diff}.png` and decide
whether the change was intended. Only then re-record:

```
cd ios && TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme BlindDrop \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' \
  -derivedDataPath .build -only-testing:BlindDropSnapshotTests
```

The `TEST_RUNNER_` prefix is required; a bare env var never reaches the runner process. **It
goes in front of `xcodebuild`, not after it.** Trailing, it is parsed as a build setting and
silently does nothing — the run reports every mismatch exactly as it would have anyway, so the
only symptom is that nothing was rewritten. `SnapshotRenderer.isRecording` documents both
spellings; this recipe had the wrong one until `E17-10` spent a re-record finding out.
Re-recording a golden you have not looked at is how a visual regression gets committed as a
fact.

**Running the app.** The simulator is drivable directly — build and launch onto a booted
iPhone 17, then tap, type, and screenshot to check the flow. For any user-facing slice this is
part of verification, not a bonus. See §8 step F.

`E00` is responsible for making these commands exist and pass on an empty project.

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

---

## 8. "Do the next slice"

From `E18` onward a task **is a slice**: the largest coherent unit that can be understood,
implemented, built, tested, exercised, reviewed and closed as one behaviour. `E00`–`E16` were
written at a finer grain and are left exactly as they are. `E17-10` is the hinge — written as a
slice, carrying a slice's fields, and worked under this section.

When the owner says *"do the next slice"* — or runs `/next-slice` — do all of this without
asking permission between steps.

**A · Resolve — and look for a batch.** Open `tasks/BOARD.md`. If it carries a **Start here**
line, that slice is the answer and outranks the scan below — it is set deliberately, because the
owner knows things the status column does not. Otherwise scan top to bottom for every slice
whose deps are all `done` (or none) and whose status is `todo`. A slice whose deps are `wip` is
never eligible — somebody is mid-flight in it, and starting on top of that is how two agents
overwrite each other.

If more than one slice is eligible at once, check whether they form a **safe batch** before
picking just the top one: two eligible slices batch together when neither's `Parallel` field
excludes the other — `yes` (unqualified) is compatible with any other `yes`; `vs E20, E24` is
compatible only with eligible slices actually in those epics; `no` never batches, with anything.
Build the largest mutually-safe group from what's eligible right now. If nothing forms a group
of two or more, work the single top-most slice as before — that is the common case, and nothing
below changes for it.

A **Start here** line is always a single slice and skips this scan entirely; batching only
applies when the board is left to resolve itself.

**B · Inspect before trusting the plan.** Read the slice's **Reads** and its epic entry, then
read the code it names. The plan was written before the code existed in its current form; where
they disagree, the code is the fact. Run `git status` and `git log --oneline -5` — there may be
uncommitted work you did not write. Never discard, revert, or stash a change you did not make.

**C · Plan, then continue.** Show a short plan first — a dozen lines, not a design document:

- the behaviour being completed, in one sentence
- for UI work: the interaction, what changes on screen, how it is presented and navigated to,
  the edge cases that matter (empty, error, keyboard), and **what you will look at in the
  simulator**
- the systems affected
- the verification you will run
- any parallel investigation you are launching

For a batch, give each slice its own block rather than folding them into one description — the
point of listing them separately is that the owner can veto one and leave the rest running.

Then keep going. Do not wait for approval. Stop and ask only when a genuinely consequential
product or architecture question cannot be answered from the docs or the code — and when you
do, record it as an `> **Open question:**` block in the epic rather than only in chat.

**D · Investigate in parallel, read-only.** Use the built-in `Explore` agent for anything that
would otherwise pour files into this context: tracing behaviour, finding call sites, mapping
data flow, checking what a test actually covers. Independent questions go out as concurrent
agents in one message. Ask for conclusions and `file:line`, never file contents. Keep the
architecture and integration decisions here — a subagent reports, it does not decide.

**E · Implement.**

*Single slice* — implement it directly. No worktree needed; there is nothing to isolate from.

*Batch* — one `Agent` per slice, each with `isolation: "worktree"`, each running the **entire**
loop (this step through **I**) for its one slice, independently: implement, verify via
`verifier`, review via `reviewer`, fix, tick its checklist, commit in its own worktree. Branch
name follows the existing convention (`t/E##-##-slug`); the worktree lives under
`.claude/worktrees/`, alongside the ones already there. Dispatch every slice in the batch in one
message so they actually run concurrently — that is the entire point of building the batch in
step A.

A slice that builds but does not do the thing is not started, it is abandoned in an expensive
place — that standard is unchanged by running several at once.

**F · Verify for real.** §5 has the commands. Delegate long runs to the `verifier` agent so the
log stays out of this context. Then, for any slice a user can see:

1. Build and install onto a booted simulator, launch, and navigate to the affected flow.
2. Exercise it — tap, type, dismiss the keyboard, background and foreground the app.
3. Screenshot the changed states and **look at them**.
4. Fix what you find, then re-run whatever the fix touched.

**Device matrix, for now.** One device — iPhone 17 — for the simulator pass, and the standard
snapshot matrix (already SE + 15 Pro Max × large/accessibility sizes) for the automated goldens,
since those are cheap, already written, and catch real regressions for free. What is *not*
required per slice right now: a manual SE and `accessibility5` simulator pass. That is an
owner call, for external-testing speed — an individual epic's **Verify** line may still name SE
or `accessibility5` from when it was written; this overrides it. Bring the full device sweep
back before release (`E14-05`), and sooner for any slice where the owner flags real layout risk
at small width or large type.

Say precisely what you verified. "Visually verified" means you looked at a screenshot of it.
If you could not run something, name it as unverified — a silent gap is worse than a known one.

In a batch, each worktree agent does this itself, on its own worktree's build. `xcodebuild test`
and lint don't collide across worktrees. The simulator does — it's one device, not one per
worktree — so step 1's install-and-launch is first-come inside a batch; a worktree agent whose
turn hasn't come yet finishes its build and automated tests, then waits for the device before
its own screenshot pass rather than fighting another agent for it.

**G · Review.** Run the `reviewer` agent against the finished diff, giving it the slice ID, its
acceptance checklist, and what you already ran. In a batch this happens inside each worktree
agent, against that worktree's own diff.

**H · Fix, judging each finding.** Evaluate them; the reviewer is a colleague, not an oracle.
Fix the valid ones. Say plainly which you rejected and why. Re-run the verification the fixes
touched, and re-review only if the fixes were substantial.

**I · Close, and — for a batch — merge one at a time.**

*Single slice* — tick the checklist, set `done` in **both** `BOARD.md` and the epic, update the
progress table, and commit. Never `done` with verification outstanding — `blocked`, with the
reason written under the task.

*Batch* — wait for every worktree agent to report done or blocked, then integrate **sequentially,
never all at once**, in board order:

1. Merge that branch into the working branch.
2. Re-run that slice's own **Verify** command against the merged tree — two slices with disjoint
   files can still interact through the app they share, and this is the check that would catch it.
3. Only then move to the next branch.

A merge conflict or a post-merge verify failure stops the batch **there**: finish integrating
whatever has already landed cleanly, leave the rest on their branches, mark them `blocked` on
the board with the reason, and report it plainly rather than forcing a merge through. Tick and
close each slice as its own merge lands — one commit per slice, in merge order, same as always.

**J · Run the simulator once more.** For a batch touching UI, do one more pass on the merged tree
after every branch is in — the combination is what a user will actually see, and no single
worktree's screenshot proves that.

**K · Report.** Short: what changed, what you actually verified, what the review found, what
remains unverified, and what the next slice is. For a batch, one line per slice plus how the
merges went.

### Which model does what

| | |
|---|---|
| **Opus** | Resolving and planning slices, architecture, cross-cutting reasoning, UI and interaction design, bugs Sonnet is stuck on, release-quality review |
| **Sonnet** | Implementation, Swift/SwiftUI, refactors, tests, build fixes, simulator iteration, the `reviewer` and `verifier` agents |
| **Haiku** | Bounded read-only lookups — finding call sites, mechanical greps, summarising logs. Never architecture, never UI design |

Two project agents exist and that is deliberate: `reviewer` (read-only, judges a diff) and
`verifier` (runs commands, returns a distilled result). Investigation uses the built-in
`Explore`. Do not add more without a reason that survives being written down.
