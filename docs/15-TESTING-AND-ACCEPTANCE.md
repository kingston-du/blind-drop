# 15 — Testing and acceptance

The build is done when every acceptance criterion below has a **passing automated test**, not
a manual check. Each AC names the test that proves it.

---

## 1. The acceptance criteria

Eleven at v1; AC-12 was added with reactions (`docs/19-REACTIONS.md`, 2026-09-17).

### AC-1 — No leak during `open`

> A user cannot obtain another user's submission, or any count/status of submissions, from the
> API during the `open` phase — verified by inspecting raw API responses, not the UI.

| Test | Location |
|---|---|
| Golden-file: `GET /rounds/current` during `open` has key set exactly `{round_id, local_date, state, opens_at, reveals_at, scores_at, my_submission}` | `tests/golden/round_open.json` |
| Same, for a caller who has **not** submitted (`my_submission: null`) | `tests/golden/round_open_nosub.json` |
| Same, for `voided` | `tests/golden/round_voided.json` |
| Every other endpoint reachable during `open` is captured as a golden file and diffed | `tests/functions/leak.test.ts` |
| Golden-file: `GET /groups` (`E18-02`, the switcher) has key set exactly `{id, name, my_state, needs_action}` per circle, whatever the mix of circles or their other members' participation | `tests/golden/groups_circles.json`, `tests/functions/circle_switcher.test.ts` |
| Authenticated and anonymous PostgREST calls to every table fail with `42501 permission denied` | `tests/functions/postgrest_locked.test.ts` |
| Response byte-length for `GET /rounds/current` is invariant across 0/1/5/11 other submitters (holding `my_submission` fixed) | `tests/functions/leak.test.ts` |
| Response latency shows no correlation (|r| < 0.2) with submitter count over 100 samples | `tests/functions/leak_timing.test.ts` |
| Accessibility labels on `SubmitScreen`/`SealedScreen` contain no digit other than the countdown | `A11yLabelTests.swift` |
| `cue` (when present) is byte-identical across every member's `GET /rounds/current` during `open`, and its presence/absence does not vary by whether the caller has submitted; a round whose circle has `cue_cadence = 0` carries no `cue` key at all (absent, not null) | `tests/functions/leak.test.ts`, `tests/db/cues.sql` |

`npm run audit:leak` runs the whole group. **It is the single most important command in this
repo.**

### AC-2 — Device time is irrelevant

> Changing device time and timezone has no effect on what phase the app believes it is in.

| Test | Location |
|---|---|
| `ServerClock` anchored to `systemUptime`; simulated device-clock shifts of ±5 years change no computed remaining time | `ServerClockTests.swift` |
| Lint: `Date()` appears nowhere outside `ServerClock.swift` | CI lint step |
| UI test: set simulator to a fake future date, launch, assert the rendered phase matches the server fixture | `FullLoopUITests.testFakeClock` |
| UI test: change `TimeZone` to `Pacific/Kiritimati`, assert countdown and group-local labels unchanged | same |
| Stale anchor after 30 min background returns `nil` until resync | `ServerClockTests.swift` |

### AC-3 — Reveal and score fire once, on time

> With 3+ submitters, the round reveals at exactly 8:00 PM group time and scores at exactly
> 10:00 PM group time, and both pushes fire once.

| Test | Location |
|---|---|
| Time-travel harness: advance the DB clock, run `tick_rounds()`, assert `state` transitions at the right minute | `tests/db/lifecycle.sql` (pgTAP) |
| Running `tick_rounds()` 10× at the same instant yields one transition and one outbox row per kind | `tests/db/idempotency.sql` |
| Outbox unique constraint rejects a duplicate `(round_id, kind)` | `tests/db/idempotency.sql` |
| Cron-outage simulation: no tick for 3h, then one tick → `open → revealed → scored`, both outbox rows present, exactly once | `tests/db/lifecycle.sql` |
| DST boundary: a group in `America/New_York` on the spring-forward date reveals at 20:00 local | `tests/db/timezones.sql` |
| Push worker sends each outbox row once; a crash before `sent_at` re-sends with the same `apns-collapse-id` | `tests/functions/push.test.ts` |
| A results-shaped push for a non-active circle is parsed through `PushRouter`, loads that circle, and renders the phase the server returned rather than forcing results | `FixtureRoundTests.atappedPushOpensItsCircleAtTheServersPhase` |
| A `410 Unregistered` disables only that token; registering the token again clears `disabled_at` | `tests/functions/push.test.ts` |

The two automated rows above cover payload handling, routing, retirement, and re-registration.
Actual APNs delivery, permission, and notification taps still require the `E23-03` physical-device
check: cold launch, background/warm launch, and foreground banner, all targeting a non-active
circle. Record the device/build and observed delivery in `tasks/E23-notifications.md`; do not call
that hardware gate green based on a simulator injection.

### AC-4 — Voiding

> With 2 or fewer submitters, the round voids, no submission is ever shown, and the correct
> notification fires.

| Test | Location |
|---|---|
| `S ∈ {0,1,2}` → `state = 'voided'`, `card_order is null` | `tests/db/lifecycle.sql` |
| `GET /rounds/current` on a voided round returns only the caller's own submission | `tests/golden/round_voided.json` |
| Voided round contributes nothing to `round_scores` or `standings` | `tests/db/scoring.sql` |
| Exactly one `void` outbox row, no `reveal` row | `tests/db/idempotency.sql` |
| The voided payload contains no count of actual submitters | golden file key-set assertion |

### AC-5 — Identical card order

> Card order at reveal is identical for every member of the group.

| Test | Location |
|---|---|
| Fetch the reveal as all 8 members; assert `[card_no → track_key]` sequences are identical | `tests/functions/reveal.test.ts` |
| `card_order` is a permutation of the round's submission ids, length equal to the count | `tests/db/lifecycle.sql` |
| Over 1000 synthetic rounds, Spearman correlation between submission `created_at` rank and `card_no` is within ±0.1 of zero | `tests/db/shuffle.sql` |
| `card_order` is `null` in `open` and `voided`, non-null in `revealed` and `scored` (DB constraint) | `tests/db/constraints.sql` |

### AC-6 — Non-submitters can view but not guess

| Test | Location |
|---|---|
| `PUT /rounds/current/guesses` as a non-submitter → 403 `NOT_A_SUBMITTER` | `tests/functions/guess.test.ts` |
| Same for a user who joined after `reveals_at` → 403 `JOINED_LATE` | same |
| `GET /rounds/current` as a non-submitter returns `cards` with `can_guess: false` and a reason | golden file |
| DB trigger rejects a directly-inserted guess from a non-submitter | `tests/db/constraints.sql` |
| UI: guess sheet renders disabled with the explanatory line, not hidden | snapshot test |

### AC-7 — Duplicate tracks

> Two identical track submissions both resolve correctly under the duplicate rule.

| Test | Location |
|---|---|
| A and B both submit `track_key = X`; a guess of "A" on B's card is correct and vice versa | `tests/db/scoring.sql` |
| The duplicate counts toward the guesser's ear **and** the card owner's readability | same |
| Two Apple catalog IDs sharing one ISRC produce the same `track_key` | `tests/functions/resolve.test.ts` |
| A submission that duplicates another is never rejected and returns no signal that it is a duplicate | `tests/functions/submit.test.ts` |

### AC-8 — Scoring, hand-checked

> Readability and ear compute correctly for a hand-checked round of 8 with partial guessing.

The fixture is `02-DOMAIN-RULES.md` §4.4, loaded by `server/supabase/seed.sql`.

| Test | Location |
|---|---|
| Every per-round `readability` and `ear` matches the §4.4 table | `tests/db/scoring.sql` |
| Eli (zero guesses) has `ear = null`, not `0` | same |
| Eli still has a readability | same |
| Ivy (non-submitter) appears in neither | same |
| Ben's 3 blanks count as wrong; denominator is still 7 | same |
| All-time ear pools; all-time readability is a mean of rates (verified over 3 rounds of differing size) | `tests/db/standings.sql` |
| Best Ear ranks on `ear_reads`: correct guesses over the group's last 14 scored rounds | `tests/db/standings_window.sql` |
| A round that falls out of the window leaves `ear_reads` but stays in `ear_correct_total` | same |
| A perfect rate earned entirely outside the window ranks on 0 | same |
| The window is the **group's** rounds, so a skipped night scores 0 rather than vanishing | same |
| One new scored round pushes one off the back — a full window does not grow | same |
| A `revealed` round is not in the window; the board never moves before a round scores | same |
| A member who has never guessed is omitted from `best_ear`, so `ear_all_time` is never `null` on the wire | `tests/functions/standings.test.ts` |
| `window_rounds` is `min(14, rounds_played)`, so a young circle reports the smaller number | same |
| The standings row and its VoiceOver announcement print the same `earReads` | `StandingsTests.swift` |
| Current standings contain active members only; leaving does not alter anyone's historical scores | `tests/db/standings.sql` |
| `null` ear renders as "—", never "0%" | `ScoringFormatTests.swift` |

### AC-9 — Share image dimensions

| Test | Location |
|---|---|
| Renders at exactly 1080×1350 and 1080×1920 at scale 3 | `ShareCardSnapshotTests.swift` |
| Golden-image diff for both variants | same |
| Numerals render in Bricolage, not the system face | same |
| All artwork loaded before render; placeholder path only on timeout | `ShareRendererTests.swift` |
| Headline precedence — four personal rules and five group rules, precedence order, non-submitter fallback (`E36-01`) | `ShareHeadlineTests.swift` |
| Longest display name (24 chars) in the headline and tonight's Ear podium at once does not overflow | snapshot |
| The no-personal-night fallback renders the `E30-01` shape, no empty personal bands | snapshot |
| The room tally and the podium each fit at their own worst case (six distinct names, a six-way tie, two 24-char names) | snapshot |
| The card's content never exceeds the frame it renders into, at every fixture above and both variants — `ImageRenderer` does not clip an overflow, so this is measured rather than assumed | `ShareCardSnapshotTests.theCardFits` |
| Temp file deleted after the share sheet completes | `ShareRendererTests.swift` |

### AC-10 — Full loop under 90 seconds

| Test | Location |
|---|---|
| UI test drives submit → seal → reveal → guess (7 cards) → results against a scripted server, measuring only user-interaction time; asserts < 90s | `FullLoopUITests.testFullLoopUnder90Seconds` |
| Search returns first results within 400ms against the fixture server | same |
| Tap count for the whole loop ≤ 18 | same |

The test asserts an interaction-time budget, not wall-clock: server waits are stubbed. It is a
regression guard on tap count and animation length, which are the things that actually drift.

### AC-11 — Animation performance and reduced motion

| Test | Location |
|---|---|
| 10 consecutive seals on iPhone 12 with zero animation hitches (Instruments, CI-run) — E14-03 ran this on an iPhone 13, no iPhone 12 available, see `docs/09-MOTION-SPEC.md` open question | `perf/seal.instruments` |
| No SwiftUI layout pass during the seal | same |
| Reduced-motion final state is pixel-identical to the normal path's final state | `ReducedMotionUITests.swift` |
| Reduced motion crossfades — no state is skipped, the sealed state still exists | same |
| Haptic counts: seal 2, unseal 1, reduced-motion seal 1 | `MotionTokenTests.swift` |
| `stagger(6) == 80`, `stagger(12) == 80`, `stagger(30) == 31` | same |
| Unseal runs once per round across relaunch | `LocalFlagsTests.swift` |


### AC-12 — Reactions are sealed until the answers

> A member can mark a card **Loved it**, **Interesting** or **Not for me** from the reveal
> onward, and no count of reactions — and no other member's reaction — is obtainable from the
> API until the round is `scored`. Counts are anonymous in every phase.

| Test | Location |
|---|---|
| `GET /rounds/{group}/current` during `revealed` carries `my_reactions` and no aggregate; golden captured | `tests/golden/round_revealed_reactions.json`, `tests/functions/leak.test.ts` |
| `my_reactions` is **absent**, not null, in `open`, `voided` and `scored` | `tests/functions/reactions.test.ts` |
| The `open` and `voided` goldens are byte-identical to before reactions shipped | existing AC-1 goldens |
| `PUT …/reactions` returns the caller's own marks only, in both writable phases, and performs no aggregate read | `tests/functions/reactions.test.ts` |
| Phase, membership, `joined_late`, card range, enum validity, idempotency, rate limit | same |
| A past round refuses the write and still serves its counts | same |
| One row per member per card; change replaces, clear deletes; reacting to your own card is permitted | `tests/db/reactions.sql` |
| Counts are computed `group by kind`; no stored tally column exists | same |
| A member's own token cannot read `reactions` through PostgREST | `tests/functions/postgrest_locked.test.ts` |
| `cards[].reactions` carries all three keys including zeros on every card, and is never `null` | `tests/functions/reactions.test.ts` |
| No route, in any phase, returns a reactor's identity | `tests/functions/leak.test.ts` |
| The three marks read as one family at `large` and `accessibility5`, SE and 15 Pro Max | `QuickPassSnapshotTests.swift`, `ResultsSnapshotTests.swift` (`Results-reactions`) |
| VoiceOver reads mark, word and count, and announces the caller's own as selected | `ReactionTests.swift`, `ReactionCountTests.swift` |
| Nothing about reactions reaches the share card, standings, profiles or insights | `ReactionCountTests.swift`, plus the **share-card goldens not moving** — `ShareCardSnapshotTests.swift` |
| `cards[].reactions` absent (a night from before reactions) decodes to three zeros, and that card draws no row at all | `ReactionCountTests.swift`, `ResultsSnapshotTests.swift` (`Results-reactions-none`) |
| A mark placed at the answers moves the count with it, reverts with it on a failed write, and survives a refetch that lands mid-write | `ReactionCountTests.swift` |
| The counts round-trip against the fixture server, and the write carries no round id | `FixtureRoundTests.swift`, `ReactionCountTests.swift` |
| A past round's row is read-only — no control at all, rather than a disabled one | `PastResultsScreen` passes no `place`; `ResultsSnapshotTests.swift` goldens render that state |

---

## 2. Additional gates not in the original AC list

Introduced by the owner amendments and by decisions in `docs/`.

| Gate | Test |
|---|---|
| **Light mode only** — no `colorScheme` branch exists; app renders identically with the system in dark mode | `ScreenSnapshotTests` run with `.dark` forced at the OS level |
| **Contrast** — every pair in `07-DESIGN-SYSTEM.md` §2 | `PaletteContrastTests.swift` |
| **Dynamic Type** — 5 screens × `{large, a11y1, a11y5}` × `{SE, 15 Pro Max}` with no truncation | `ScreenSnapshotTests.swift` |
| **12 members on an SE at a11y5** — every chip and card reachable | `A11yReachabilityTests.swift` |
| **Spotify bridging** — a track with an ISRC resolves to a `spotify_url`; one without is marked `unresolvable`; submission succeeds either way | `tests/functions/spotify.test.ts` |
| **Spotify export** — playlist created with the right tracks in the right order; unresolved count stated | `SpotifyExporterTests.swift` (against a stub) |
| **Every archive row is linkable** — for every `scored` submission, either `spotify_url` is present or `track_links.unresolvable` is true | `tests/db/links.sql` |
| **Copy discipline** — no exclamation mark, no banned word, in `Localizable.strings` | CI lint |
| **No inline strings** — no string literal passed to `Text(_:)` in `Features/` | CI lint |
| **No design literals** — no hex/size/spacing literal in `Features/` | CI lint |
| **Three pushes max** — no user receives more than 3 in any 24h across a simulated 14-day season | `tests/db/notification_budget.sql` |

---

## 3. Test infrastructure

### Server

```
server/supabase/tests/
├── db/            pgTAP, run against a fresh local DB seeded from seed.sql
├── functions/     Deno test, run against `supabase start` + served functions
└── golden/        JSON key-set and byte-length fixtures
```

Time travel for the DB tests uses a `test_now()` indirection: `tick_rounds()` calls
`public.now_()` which is `now()` in production and a settable session variable under test. Do
**not** use `pg_sleep` or real waiting anywhere.

```
npm run test:db          pgTAP
npm run test:functions   Deno
npm run audit:leak       the AC-1 group, run separately because it gates release
npm run test             all three
```

### iOS

One scheme, `BlindDrop`, with three test targets: Unit, Snapshot, UI. Snapshot testing is
hand-rolled against golden PNGs in `BlindDropTests/__Snapshots__/` — no third-party snapshot
library (`13-IOS-APP-ARCHITECTURE.md`: zero dependencies).

UI tests run against a **fixture server**: a Deno script serving canned responses for each
phase, launched by the test harness before the scheme. The app points at it via a launch
argument. This makes phase testing instant and deterministic.

### CI

On every push: lints → `npm run test` → iOS unit + snapshot against the pinned current
Xcode/simulator destination. The destination is configured centrally rather than repeated in
scripts. Before release, run the same suite once on the minimum supported iOS 17.4 runtime and
once on the current runtime.
On PR to main: the above plus UI tests.
Before release: the above plus `audit:leak`, the Instruments performance run, and the §10
checklist in `14-SECURITY-AND-THREAT-MODEL.md`.

---

## 4. Manual pilot checks

Automation cannot cover these. Run them once with a real group before shipping.

- [ ] At 8:00 PM, all devices show the reveal within 20 seconds of each other
- [ ] The seal feels good on a real device in a real hand. If it does not, it is wrong,
      regardless of what the frame counter says.
- [ ] A results screenshot pasted into iMessage looks right at the thumbnail size iMessage
      actually renders
- [ ] Someone who has never seen the app understands the game from the submit screen's empty
      state, unprompted
- [ ] Nobody in the group can tell, from the app, who had submitted before 8:00 PM — ask them
      directly and see if anyone found a tell
