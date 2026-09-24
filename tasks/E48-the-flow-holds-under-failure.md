# E48 — The core flow holds under failure

A pre-resubmission audit of the whole core flow — sign-in, onboarding, the four phases, the
record, settings — looking for dead ends rather than for crashes. It found no leak (`CLAUDE.md`
§2.1 is intact, client and server, and `audit:leak` reports **AC-1 SATISFIED**), no reachable
force-unwrap, and no client-side phase decision. What it did find was six places where the app
**stops having anything to offer**: a screen with no error branch, a retry that cannot succeed,
a countdown that never resolves.

These are not crashes, which is exactly why they survived this long. Each one is a person
holding a phone that has quietly stopped working, with no way to tell.

**The one with a review deadline attached** is the phase refetch (below). `docs/APP-REVIEW-NOTES.md`
tells the reviewer to seal a song, watch a twelve-second countdown, and wait for the reveal. If
the single refetch fired at zero lands before the server's tick, the screen sits at `00:00:00`
and the walkthrough stops there.

---

### E48-01 — Six dead ends, closed

**Status:** done · **Deps:** — · **Parallel:** no
**Reads:** `CLAUDE.md` §2, `docs/04` §2, `docs/08`, `docs/13` §4, this file
**Touches:** `ios/BlindDrop/Features/Round/RoundScreen.swift`,
`ios/BlindDrop/Features/Onboarding/SignInScreen.swift`,
`ios/BlindDrop/Features/Results/PastResultsScreen.swift`,
`ios/BlindDrop/Features/Record/RecordStore.swift`,
`ios/BlindDrop/Features/Submit/SubmitStore.swift`,
`ios/BlindDrop/Core/Networking/APIError.swift`, `Localizable.strings`,
`server/supabase/tests/`
**Verify:** `./ios/scripts/lint.sh`; `node server/scripts/lint.mjs`; iOS unit + snapshot;
`cd server && npm test` (including `audit:leak`)
**Proves:** nothing new about AC-1; it is re-run to show these changes cost it nothing

- [x] **The countdown resolves.** `phaseDeadlineID` / `refreshAtPhaseDeadline` were gated on
      `case .scored`, so `open → revealed` and `revealed → scored` had one refetch — the single
      `.onChange(of: timer.hasElapsed)` edge — against a `tick_rounds()` that runs on a *minute*
      cadence. Now every phase waits out its deadline and keeps asking, 2s/5s/10s then 15s × 8,
      until the server agrees the phase moved. Bounded on purpose: a client that retried forever
      against a server that is down is a request a second for the rest of the evening.
- [x] **The answers have an error state.** `ResultsHost` rendered `ResultsScreen` the instant the
      store existed and had no branch for `state.error` — the only route in the app without one,
      on the terminal screen of the night. A failed results fetch was the headline *"The
      answers."* over nothing, permanently: `GET /rounds/current` had succeeded, so the chrome's
      offline banner never fired either. Skeleton while loading, line and retry on failure.
- [x] **`TRACK_ALREADY_USED` says what it means.** The server raises it (`E18-03`) and
      `docs/11` has had the string since, but `APIError` never mapped the code, so the
      cross-circle repeat refusal rendered as *"That didn't seal. Try again."* — an instruction
      that cannot work, on the round's one required action. Mapped, with the deck's line.
- [x] **A sign-in whose `GET /me` fails says so.** `signIn` ends in `loadIdentity()`, which does
      not throw; the failure lands in `SessionStore.loadFailure` and the state stays put.
      `SignInScreen` never read it, so a flaky network made Apple's sheet complete and the screen
      do *nothing*. `OnboardingStore.finish()` and `join()` already read it back out.
- [x] **Past results can be retried.** Its error state was a line of text; `.task` runs once per
      appearance, so an offline first load was a dead end until the screen was popped and pushed.
- [x] **Cancelling Spotify's login is not a failure.** `SpotifyAuthError.cancelled` went through
      the same bare `catch` as everything else and reported *"The playlist didn't get made"* about
      a thing the user had just decided not to do.
- [x] Two clock-boundary flakes in the release gate, fixed where they bit (see the open question).
- [x] The standings perf gate measures once instead of twice.

**What was verified, and what was not.** `./ios/scripts/lint.sh` and `node server/scripts/lint.mjs`
clean. iOS: 596 unit tests, 115 snapshot tests, **no golden moved** — the new branches add states
the goldens do not cover rather than changing the ones they do. Server, after a `db:reset`: 819
pgTAP assertions across 31 files, 335 Edge Function tests, and `audit:leak` reports **AC-1
SATISFIED**, which is this slice's actual claim — the flow got more resilient and gave up nothing
about the blind window. On an iPhone 17 against the fixture server, the answers screen was driven
live in both new states: the happy path with reaction counts, and — with `LATENCY_MS=4000` — the
**skeleton** where the headline-over-nothing frame used to be.

**Not verified live:** the retry loop in the phase refetch. Reaching it needs a server that
accepts `GET /rounds/current` while refusing to advance the round for two minutes, which the
fixture server cannot express. Its parts are covered — the deadline maths is
`CountdownTimer`'s, already pinned — but the loop itself has been reasoned about rather than
watched. It is the one thing in this slice to look at on the first real evening.

> **Open question — the suite's clock-boundary flake is wider than the two sites fixed here.**
> `zoneWhereLocalHourIs` can only shift by whole hours, so a test group's local *minute* is the
> real UTC minute. Every room built at 17:00 local with `reveal_hour: 18` therefore has between
> zero and sixty minutes of headroom, and a run in the last minutes of an hour either measures a
> reveal that is seconds away or gets *tomorrow's* round from `ensure_rounds`. `demo.test.ts` and
> `reactions.test.ts` were the two that failed and are fixed by giving them hours of margin; the
> same 17/18 pattern is still in `reveal.test.ts`, `leak.test.ts`, `results.test.ts`,
> `record.test.ts`, `standings.test.ts`, `circle_switcher.test.ts` and `push.test.ts`. Fixing it
> properly means changing the helper's contract — "comfortably inside hour H" rather than
> "in hour H" — and re-running the whole suite against a simulated boundary. That is its own
> slice, and doing it by hand across thirteen call sites the night before a resubmission is how
> a green suite becomes a wrong one. **Nothing here affects users or App Review**: it is a test
> that fails for two minutes in every hour.

> **Open question — three low findings left open, deliberately.** A Keychain *read* failure is
> indistinguishable from "no token" and signs the user out silently (`SessionStore.load()`, rare:
> needs a launch before first unlock after reboot); a 4xx with no envelope from infrastructure in
> front of the functions renders as *"That doesn't exist"* (`APIClient`); and one unreadable group
> row 500s the whole circle switcher rather than being dropped from the list, which is the
> opposite of what the same function does with a null caller-state (`groups/index.ts`). Each is a
> real inconsistency and none is on a path a normal session reaches.
