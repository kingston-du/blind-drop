# Board

Conventions: [`tasks/README.md`](README.md). Statuses: `todo` · `wip` · `blocked` · `done`.

`E18-01` closed 2026-08-18, unblocking `E18-02` and `E18-03` (parallel to each other). `E18-02`
closed 2026-08-19 — `GET /groups`, the switcher's data source. `E18-03` closed 2026-08-19 too —
the cross-circle repeat refusal, `BD003`/`TRACK_ALREADY_USED`, folded into `upsert_submission`
itself. `E18` is fully done. `E19-01` closed 2026-08-19 too — the client moved off every
`current`-shaped route onto a new `CircleStore` (`GET /groups`, resolving an active id the same
way `/groups/current` always did), which every group-scoped store now re-resolves on its own
`load()` rather than being handed once at construction. No new UI, by design. `E19-02` closed
2026-08-19 too — the group's name in the header is now the switcher's own control: a bottom sheet
listing the caller's circles (name and state, needs-action ones first, no visible heading),
picking one calls `CircleStore.select(_:)` and re-scopes `RoundStore` via a new `invalidate()`
that clears to `.loading` before the refetch rather than racing it. Two real bugs surfaced by
actually looking at the rendered output rather than trusting green tests, both fixed before
closing — see the epic file's entry for both. `E19-03` closed 2026-08-19 too — a deep link's
circle prefix (parsed since `E19-01`) now actually switches: a new
`Router.resolvePendingCircle(against:)`, called from `RoundStore.load()` before it resolves the
active id, switches to a held circle or drops the link if the caller does not hold it.
`RoundScreen` gained an `.onChange(of: env.router.pending)` to cover the one gap cold/warm launch
already handled for free — a notification tapped while the round screen is already up. A race the
reviewer caught (a manual switcher pick racing a still-in-flight link-driven switch could silently
revert to the link) was fixed before closing with a new `Router.clearPending()`, called by the
switcher's own selection. `E23-03` remains hardware-only work in progress. `E24-02` closed 2026-08-20:
circle-scoped profiles now show only scored Ear, Readability, drops, recent songs and pairwise
reads, with thin history withheld rather than exaggerated. Its new open-phase golden is part of
AC-1. The full Group snapshot baseline's 44 stale mismatches were not ignored: `ImageRenderer`
had been asked to render a `ScrollView`, producing blank goldens; the harness now renders the
actual static content and the reviewed replacements pass.
`E22-01`, `E23-01` and all five `E27` spikes closed 2026-08-18 too — see each epic file for what
each actually needed (E22-01's one open item is a credentials-gated manual check, named there
rather than silently skipped). `E26` — a first batch attempt on all four slices ran out of budget
before any of them produced usable work; all four went back to `todo` and were picked up again
separately, surviving several more session-limit cutoffs along the way (worked worktrees were
resumed rather than restarted where anything had actually landed). All four closed 2026-08-19:
`E26-01` results laid out and playable, with one known narrow-device title-truncation limit
recorded as an open question in the epic file; `E26-02` closed the committing-drag test gap this
note used to flag below; `E26-03` gave search results the room an `.accessibility5` subhead was
eating; `E26-04` found `CountdownTimer.hasElapsed` was a computed property `@Observable` never
re-invalidated readers of on the tick alone, and made it stored, written (guarded to real
transitions) from the same `refresh()` call that already updates the visible countdown.

`E00`–`E13`, `E15`, `E16-01` and **all of `E17`** are done, as are `E14-01`, `E14-02` and
`E14-04`.

`E17` closed on 2026-08-17, and it was not the re-record it looked like. Five real defects were
behind the goldens, three of the nine slices were not doing what their own checklists claimed,
and `CLAUDE.md` §5's re-record recipe was itself wrong. What was found and what was done about it
is in [E17's *What E17-10 actually found*](E17-polish-pass.md). The call sheet's drag-vs-tap
regression this note originally flagged is fixed (2026-08-18, plus an accessibility regression
the same fix introduced). The *committing* drag — crossing the threshold, not just the
springback — now has one: `E26-02` extracted the decision into `CallSheetDetent.resolved` and
pinned it with `CallSheetDetentTests` (both directions, the exact-threshold edge, the floor).
Driving it live on a real device or simulator is still open — see `E26-02`'s entry for what was
tried and why it stayed out of reach this pass.

`E14-03`, `E14-05` and `E16-02` need a physical iPhone and the owner; none can be closed from
the simulator. They are not blocking the beta work.

`E18` onward is the beta. **One task there is one slice** (`tasks/README.md`), worked under
`CLAUDE.md` §8 — plan, implement, verify, run it, review, close.

---

## Dependency graph

```
E00 tooling
 └─ E01 database
     ├─ E02 auth & groups ─ E03 lifecycle ─ E04 submissions ─ E05 reveal/score ─ E06 push
     └─ E07 music services  (parallel with E02–E06 after E02-01)

E00-05 fixture server
 └─ E08 iOS foundation ─ E09 onboarding ─ E10 submit+seal ─ E11 reveal+guess
                                                              └─ E12 results+share ─ E13 record+export

E04..E07 + E13  ─ E14 QA & release

E03 + E04 + E05 ─ E16 App Review demo environment  (server only; no iOS change)

E08 iOS foundation ─ E15 how to play  (parallel with E09..E14; E15 → E14-05)
```

### The beta

```
E17-10 close the polish pass          done — the iOS lane is unblocked
 ├─ E18 circles: server ─ E19 circles: the app ─┬─ E20 invitations
 │            └─ E24 leaderboard+profiles ─ E25 insights
 │                                              └─ E21 circle settings
 ├─ E22 sealed privacy      one slice, parallel with anything
 └─ E26 UI polish           three independent slices

(no dep on E17-10 — server-side or investigation only)
    E23 notifications       E23-01 free; E23-02 then needs E18-01
    E27 spikes              investigation only, parallel with everything

E28 polish and personality   five independent bug/layout slices, then three in order
 ├─ E28-01 … E28-05          parallel with each other and with E28-06
 └─ E28-06 ─ E28-07 ─ E28-08
```

E17-10 gated the **iOS** work, because it is what left the app's goldens and its one failing
test in a known state. That gate is open. E23-01 and E27 touch neither, so they never waited —
their `Deps` columns say `—` and mean it. E19-03 and E20-03 join the two lanes back together and need both.

### Next progression

```
E29 results & record depth      E29-03 independent; E29-01/E29-02 exclusive (both touch ResultsScreen)
E30 share card                  one slice
E31 conditional reminders       one slice, amends CLAUDE.md §2.6 — see the epic file
E32 two small fixes             two independent slices
E33 record chip                 done — landed, goldens re-recorded
E34 marketing website           one slice — mostly outside this repo
E35 cues                        six slices, mostly sequential — see the epic file; promotes
                                 "themed prompts" from docs/16 §1 to scope, owner amendment
E36 personal share card         one slice — amends docs/10 §2's "no scores for anyone but the
                                 headline", owner amendment; see the epic file
E37 drop screen redesign        one slice — header reflow, cue card, paste-fallback removal
E38 circles end to end          four slices; E38-01 → E38-02/E38-03, E38-04 independent
```

None of `E29`–`E37` depends on the beta epics above or on each other. `docs/17-NEXT-FEATURES.md`
is the spec `E29`–`E34` were cut from; `E35` is cut from `docs/18-CUES.md`, written separately
after an owner request. `E36` is cut from an owner request of 2026-08-28 and revisits `E30`'s
surface — it is the only epic here that depends on another (`E30`, done). `E37` is cut from an
owner request, no spec section — see the epic file. `E38` is cut from an owner request of
2026-08-31 ahead of production, no spec section; it amends `docs/11`'s switcher note — *"the row is still
just a name and a state"* — so the active row is visible to everyone and not only to VoiceOver.

`E35` closed 2026-08-27 — all six slices done. **Flag for the next iOS slice:** the simulator is
now iOS 26.5, and the snapshot baseline recorded under `E28`/`E29` has drifted across the board
(rendering-height changes of hundreds of points on screens E35 did not touch — FlightCard,
Insights, CircleSwitcher, Group, etc.). The suites E35 actually changed (HowTo, Record, Group, and
the new Cue suite) were re-recorded; the rest were deliberately **not** re-recorded here, because
that is a whole-baseline re-record that needs eyes on every diff, not a slice-sized change. See
`E35-cues.md`'s E35-04 note for the two remaining E35 verification gaps (the Cue Submit/Sealed
snapshot goldens crash `ImageRenderer` even serialized, and the visual simulator pass couldn't be
performed without image input).

`E36` closed 2026-08-28 — one slice. The card is now the sharer's account of the night on a
personal-night render (own ear, own readability, what the room guessed for the caller's own card,
tonight's Ear top 3) and falls back to `E30-01`'s group shape when the caller has nothing personal
to report. The original layout sketch (filmstrip demoted-but-present, podium as one joined line)
did not fit a fixed 1080×1350 canvas once measured by the slice's own new `theCardFits` test —
see `E36-personal-share-card.md`'s closing notes for what actually shipped instead and why. No
interactive simulator pass was available in this environment; the re-recorded, visually-reviewed
goldens stand in its place (same rendering path, same pixels a device would produce).

---

## E00 — Repo, tooling, CI · [file](E00-repo-and-tooling.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E00-01 Repo skeleton and npm scripts | done | — | — |
| E00-02 Supabase local project | done | E00-01 | — |
| E00-03 Xcode project skeleton | done | E00-01 | — |
| E00-04 CI pipeline and lint rules | done | E00-02, E00-03 | AC-2 |
| E00-05 Fixture server for iOS tests | done | E00-01 | AC-10 |

## E01 — Database foundation · [file](E01-database.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E01-01 Extensions and core tables | done | E00-02 | — |
| E01-02 RLS lockdown | done | E01-01 | AC-1 |
| E01-03 Constraints and triggers | done | E01-01 | AC-5, AC-6 |
| E01-04 Seed data (§4.4 fixture) | done | E01-03 | AC-8 |
| E01-05 pgTAP harness and `now_()` | done | E01-01 | AC-3 |

## E02 — Auth, profiles, groups · [file](E02-auth-and-groups.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E02-01 `_shared` http, auth, dto, db | done | E01-02 | AC-1 |
| E02-02 `/me` | done | E02-01 | — |
| E02-03 `/groups` create, join, current, patch, leave | done | E02-02 | AC-1 |
| E02-04 Invite code generation | done | E02-03 | — |
| E02-05 Account deletion | done | E02-03 | — |

## E03 — Round lifecycle and scheduler · [file](E03-round-lifecycle.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E03-01 `ensure_rounds()` | done | E01-05, E02-03 | AC-3 |
| E03-02 `tick_rounds()` reveal and void | done | E03-01 | AC-3, AC-4 |
| E03-03 `tick_rounds()` score and nudge | done | E03-02 | AC-3 |
| E03-04 `card_order` shuffle | done | E03-02 | AC-5 |
| E03-05 `pg_cron` registration | done | E03-03 | AC-3 |
| E03-06 Outage and idempotency tests | done | E03-05 | AC-3, AC-4 |

## E04 — Submissions API · [file](E04-submissions.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E04-01 `PUT /rounds/current/submission` | done | E03-01, E07-03 | AC-7 |
| E04-02 `GET /rounds/current` — open and voided | done | E04-01 | AC-1, AC-4 |
| E04-03 Golden leak fixtures | done | E04-02 | AC-1 |
| E04-04 `audit:leak` script | done | E04-03 | AC-1 |

## E05 — Reveal, guesses, scoring · [file](E05-reveal-and-scoring.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E05-01 `GET /rounds/current` — revealed | done | E03-04, E04-02 | AC-1, AC-5, AC-6 |
| E05-02 `PUT /rounds/current/guesses` | done | E05-01 | AC-6 |
| E05-03 Scoring views | done | E01-04 | AC-7, AC-8 |
| E05-04 `GET /rounds/{id}/results` | done | E05-03 | AC-8 |
| E05-05 `GET /groups/current/standings` | done | E05-03 | AC-8 |
| E05-06 §4.4 hand-checked scoring test | done | E05-03 | AC-7, AC-8 |

## E06 — Push notifications · [file](E06-push.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E06-01 Outbox and APNs JWT | done | E03-03 | AC-3 |
| E06-02 `push-worker` | done | E06-01 | AC-3, AC-4 |
| E06-03 `POST /devices` | done | E02-02 | — |
| E06-04 Idempotency, expiry, 410 handling | done | E06-02 | AC-3 |

## E07 — Music services · [file](E07-music-services.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E07-01 Apple Music developer token | done | E02-01 | — |
| E07-02 `GET /tracks/search` and cache | done | E07-01 | AC-10 |
| E07-03 `POST /tracks/resolve` and `track_key` | done | E07-02 | AC-7 |
| E07-04 Spotify client-credentials ISRC lookup | done | E07-03 | — |
| E07-05 `track_links` backfill in the tick | done | E07-04, E03-05 | — |
| E07-06 Record and export endpoints | done | E07-04, E05-03 | — |

## E08 — iOS foundation · [file](E08-ios-foundation.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E08-01 App skeleton, light mode, environment | done | E00-03 | — |
| E08-02 Palette and contrast test | done | E08-01 | AC-2 gates |
| E08-03 Typography and font bundling | done | E08-01 | — |
| E08-04 Component library | done | E08-02, E08-03 | — |
| E08-05 `APIClient` and DTOs | done | E08-01 | AC-1 |
| E08-06 `ServerClock` and the `Date()` lint | done | E08-05 | AC-2 |
| E08-07 Snapshot test harness | done | E08-04 | AC-9 |

## E09 — Onboarding · [file](E09-onboarding.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E09-01 Sign in with Apple | done | E08-05 | — |
| E09-02 Display name | done | E09-01 | — |
| E09-03 Join or create group | done | E09-02 | — |
| E09-04 Invite code screen and deep link | done | E09-03 | — |

## E10 — Submit and the seal · [file](E10-submit-and-seal.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E10-01 `SubmitScreen` | done | E08-04, E08-06, E09-03 | AC-1 |
| E10-02 `SearchSheet` and preview player | done | E10-01 | AC-10 |
| E10-03 `ConfirmScreen` | done | E10-02 | — |
| E10-04 **The seal animation** | done | E10-03 | AC-11 |
| E10-05 `SealedScreen` and countdown | done | E10-04 | AC-1, AC-2 |
| E10-06 `VoidedScreen` | done | E10-05 | AC-4 |
| E10-07 Push permission prompt | done | E10-05, E06-03 | — |

## E11 — Reveal and guess · [file](E11-reveal-and-guess.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E11-01 `FlightCard` | done | E08-04 | AC-5 |
| E11-02 Guess interaction | done | E11-01 | AC-10 |
| E11-03 Name pool and the 12-member layout | done | E11-02 | — |
| E11-04 **The unseal animation** | done | E11-01 | AC-11 |
| E11-05 Non-submitter and joined-late states | done | E11-02 | AC-6 |
| E11-06 Debounced guess save | done | E11-02, E05-02 | — |

## E12 — Results and share · [file](E12-results-and-share.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E12-01 Answer reveal | done | E11-04, E05-04 | AC-8 |
| E12-02 Personal stats and `StatMeter` | done | E12-01 | AC-8 |
| E12-03 Standings | done | E12-02, E05-05 | AC-8 |
| E12-04 Share card views | done | E12-03 | AC-9 |
| E12-05 Share renderer and share sheet | done | E12-04 | AC-9 |

## E13 — The Record and exports · [file](E13-record-and-export.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E13-01 `RecordScreen`, pagination, filter | done | E08-04, E07-06 | — |
| E13-02 Per-track Spotify and Apple links | done | E13-01 | — |
| E13-03 Spotify PKCE auth | done | E13-01 | — |
| E13-04 Spotify playlist export | done | E13-03 | — |
| E13-05 Apple Music playlist export | done | E13-01 | — |

## E14 — QA and release · [file](E14-qa-and-release.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E14-01 Leak audit, full pass | done | E04-04, E05-02 | AC-1 |
| E14-02 Accessibility pass | done | E12-03, E13-01 | AC-2 gates |
| E14-03 Animation performance pass | wip | E10-04, E11-04 | AC-11 |
| E14-04 Full-loop UI test | done | E12-05 | AC-10 |
| E14-05 Release checklist | wip | E14-01..04, E15 | all |

## E15 — How to play · [file](E15-how-to-play.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E15-01 Copy deck: How to play | done | — | — |
| E15-02 `HowToSheet` | done | E15-01, E08-04 | — |
| E15-03 `HelpButton` and its three entry points | done | E15-02 | — |

## E16 — App Review demo environment · [file](E16-app-review-demo.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E16-01 Demo groups, lifecycle, provisioning | done | E03-03, E04-01, E05-02 | AC-1, AC-3 |
| E16-02 Hosted activation | blocked | E16-01 | — |

## E17 — Polish pass · [file](E17-polish-pass.md)

Amends three owner-level rules: `CLAUDE.md` §2.5 (E17-05), `docs/09` §1 (E17-07),
`docs/10` §1 (E17-02). None is an agent's call; all three are recorded in the epic.

| Task | Status | Deps | Proves |
|---|---|---|---|
| E17-01 The phase flash on foreground | done | — | AC-2 |
| E17-02 One share variant | done | — | — |
| E17-03 The answer card's links become an overflow menu | done | — | — |
| E17-04 The chrome sits where a header sits | done | E17-01 | — |
| E17-05 How to play is the legend | done | — | — |
| E17-06 The call sheet collapses | done | — | — |
| E17-07 Two haptics for the reveal | done | E17-06 | — |
| E17-08 The answers land harder | done | E17-03 | — |
| E17-09 The group's name on every phase | done | E17-01 | — |
| **E17-10 Close the polish pass** | **done** | — | AC-2, AC-11 |

`E17-10` verified all nine, fixed what was actually broken behind them, and re-recorded 47
goldens after opening every diff. Lint clean; 389 unit and 58 snapshot tests green.

---

# The beta

From here a task is a **slice** — `tasks/README.md`. **Parallel** says whether it can run in
another worktree beside its siblings.

## E18 — Multi-circle: the server foundation · [file](E18-circles-server.md)

Lifts ADR-005. Read `docs/01` ADR-011 first — it owns the circle cap and the rules the
replacement inherits.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E18-01 A user may hold several circles | done | E17-10 | no | AC-1 |
| E18-02 What every circle needs from me right now | done | E18-01 | no | AC-1 |
| E18-03 The same song, twice, in one evening | done | E18-01 | vs E18-02 | — |

## E19 — Multi-circle: the app holds more than one · [file](E19-circles-app.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E19-01 Every screen knows which circle it is showing | done | E18-01, E18-02 | no | AC-1, AC-10 |
| E19-02 The switcher | done | E19-01 | no | — |
| E19-03 A notification opens the circle it came from | done | E19-02, E23-01 | no | — |

## E20 — Circle creation and invitations · [file](E20-invitations.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E20-01 Pending invitations | done | E18-01 | vs E21, E24 | AC-3, AC-5 |
| E20-02 Starting a group, and filling it | done | E20-01, E19-02 | no | — |
| E20-03 Invitations in the switcher, and the push | done | E20-02, E23-01 | no | AC-3 |

## E21 — Circle settings and roles · [file](E21-circle-settings.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E21-01 The circle's own screen | done | E19-02 | vs E20, E24 | — |
| E21-02 Who is in charge | done | E21-01 | no | — |

## E22 — Sealed-song privacy · [file](E22-sealed-privacy.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E22-01 Hold to peek | done | E17-10 | **yes, vs everything** | AC-1 |

## E23 — Notifications, working and verified · [file](E23-notifications.md)

Push does not work today. `E23-01` diagnoses before anything is repaired.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E23-01 Find out why, then fix it | done | — | **yes, vs E19–E21** | AC-3 |
| E23-02 Three deliveries, whatever the circle count | done | E23-01, E18-01 | no | AC-3 |
| E23-03 It arrives, and it opens the right thing | wip | E23-02, E19-03 | no | AC-3 |

## E24 — The leaderboard and profiles · [file](E24-leaderboard-profiles.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E24-01 Best Ear | done | E18-01 | vs E20, E21 | — |
| E24-02 A person, in this circle | done | E24-01 | no | AC-1 |

## E25 — Insights · [file](E25-insights.md)

E25-01 closed 2026-08-20: tester-visible relationships arrive from the first shared scored round,
with raw shared-read denominators beside every percentage. Revisit its data threshold before public
beta. E25-02 closed 2026-08-20: confusion stays absent until the circle has active-member-count
squared scored rounds, then shows its three most repeated wrong owner-to-name attributions.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E25-01 Who you know, and who knows you | done | E24-02 | vs E26 | — |
| E25-02 Who you get mistaken for | done | E25-01 | no | — |

## E26 — UI polish and known bugs · [file](E26-ui-polish.md)

Only what does not belong to another slice. Everything else is fixed on the screen that owns it.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E26-01 Results, laid out for the numbers it produces, and playable | done | E17-10 | **yes** | AC-9 |
| E26-02 Guessing, without the fidget | done | E17-10 | **yes** | — |
| E26-03 Searching for a song with a keyboard in the way | done | E17-10 | **yes** | — |
| E26-04 The clock hits zero and the screen does not follow | done | E17-10 | **yes** | AC-2 |

## E27 — Spikes · [file](E27-spikes.md)

Investigation only. Each ends in a recommendation, not code.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E27-01 Opening a song in Spotify | done | — | **yes** | — |
| E27-02 Pick for me | done | — | **yes** | — |
| E27-03 A web page | done | — | **yes** | — |
| E27-04 Themed prompts | done | — | **yes** | — |
| E27-05 Streaks | done | — | **yes** | — |

## E28 — Polish and personality · [file](E28-polish-and-personality.md)

Owner-driven pass over the beta build. Records three owner amendments in the epic file: the
thin-history gates come off for the test stage (**A1**), hold to peek plays the preview
(**A2**), and The Record's entry point moves to the Group screen (**A3**). All eight slices
closed in one pass: build clean, 442 unit tests and all 81 snapshot tests pass (goldens
re-recorded for the nine suites this actually changed, each looked at before recording — that
look caught a real bug, a `MonogramMark` squeezing a member's name to nothing on the ranked
leaderboard row, fixed before it landed), and a live simulator pass against the fixture server
confirmed hold-to-peek, the header menu, Group, and the Insights → leaderboard → profile
navigation chain. The epic file's own *Verified* section says what was and was not driven live.
`server/` ran for real too, against an already-up local stack: `test:db` and `audit:leak` both
green, `test:functions` 267/271 — the 4 failures are `circle_switcher.test.ts`, pre-existing and
confirmed unrelated (a time-of-day-dependent reveal-hour bug in `circleCallerState`, filed
separately, not this epic's).

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E28-01 The keyboard stops shoving Start a group off the screen | done | — | **yes** | — |
| E28-02 Searching for a replacement, without the grey box or the ghost rows | done | — | **yes** | AC-10 |
| E28-03 The call sheet answers a flick | done | — | **yes** | — |
| E28-04 Hold to peek, actually held, and heard | done | — | **yes** | — |
| E28-05 Answers with room for the song | done | — | **yes** | AC-9 |
| E28-06 Every stat, shown; every screen, quieter | done | — | vs E28-01…05 | — |
| E28-07 Insights that rank, and rank fairly | done | E28-06 | no | — |
| E28-08 The printed sheet: Group, Profile and Insights get a face | done | E28-06, E28-07 | no | AC-2 gates |

---

# Next progression

Nine improvements the owner named as the next progression for the app, spec'd in
`docs/17-NEXT-FEATURES.md` and cut into epics here.

## E29 — Results and Record, deepened · [file](E29-results-and-record-depth.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E29-01 Who guessed you, and how tonight stacked up | done | — | vs E29-03 | AC-1, AC-8 |
| E29-02 Preview playback on past results | done | — | vs E29-03 | — |
| E29-03 Song links, consistent across every card state | done | — | vs E29-01, E29-02 | — |

## E30 — A share card worth sharing · [file](E30-share-card-redesign.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E30-01 Lead with the moment, not the table | done | — | yes | AC-9 |

## E31 — Conditional reminders, not a universal nudge · [file](E31-conditional-reminders.md)

Amends `CLAUDE.md` §2.6 (the 3-deliveries/day cap). Not an agent's call — recorded as an owner
amendment in the epic file.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E31-01 Two conditions replace one universal nudge | done | — | yes | AC-3 |

## E32 — Two small, independent fixes · [file](E32-two-small-fixes.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E32-01 The call sheet commits instead of springing back | done | — | vs E32-02 | — |
| E32-02 The menu doesn't peek through the pop transition | done | — | vs E32-01 | — |

## E33 — Finish the record chip · [file](E33-record-chip-finish.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E33-01 Finish, verify, and commit the in-flight record chip | done | — | yes | AC-2 gates |

## E34 — Marketing website (separate repo) · [file](E34-marketing-website.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E34-01 Coordinate this repo's half | done | — | yes | — |

## E35 — Cues · [file](E35-cues.md)

Promotes "themed prompts" from `docs/16` §1 to scope — owner amendment, 2026-08-27, recorded in
`docs/18-CUES.md` and this epic's header, the same footing as ADR-011. On by default for every
circle, existing and new, at `cue_cadence = 2` ("every other night").

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E35-01 Docs and copy deck | done | — | yes | — |
| E35-02 Database: catalog, cadence, assignment | done | E35-01 | no | — |
| E35-03 API: rounds, results, record, settings | done | E35-02 | no | AC-1 (leak) |
| E35-04 iOS: CueDTO, CueBanner, placements | done | E35-03 | vs E35-05, E35-06 | — |
| E35-05 Circle settings: cadence control | done | E35-03 | vs E35-04, E35-06 | — |
| E35-06 seal_reminder carries the cue | done | E35-03 | vs E35-04, E35-05 | — |

## E36 — The share card becomes yours · [file](E36-personal-share-card.md)

Amends `docs/10` §2's *"no scores for anyone but the headline"* — owner amendment, 2026-08-28,
same footing as ADR-011 and `E31`'s cap change. The card stops being a purely group artifact and
becomes the sharer's account of the night: their own ear and readability, what the room guessed
for their card, and tonight's Ear top 3. The closed list of what that permits — and everything it
still bans, including naming a guesser and ranking readability — is in the epic file's header, not
here. No server work; every field is already on the wire.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E36-01 The share card becomes yours | done | — | yes | AC-9 |

## E37 — The drop screen, cleared · [file](E37-drop-screen-redesign.md)

One slice, from an owner request. The header drops from three rows to two (date and badge share
a row, `ViewThatFits`-measured), the paste-a-link fallback comes out of both `SongSearch` hosts,
and the room both changes free goes to a new `CueCard` on the one phase that has something to
brief. `docs/18` §2 carries the one real exception this needs: the card's micro-label is
`amberText`, scoped to that single rendering and that single phase.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E37-01 Header reflow, cue card, paste-fallback removal | done | — | yes | — |

## E38 — Circles, end to end · [file](E38-circles-end-to-end.md)

Four slices, from an owner request, over the least-exercised surface in the app. The hole they
close: since ADR-011 a person may hold three circles, but every way *into* a second one still
assumes they hold none — a `/j/<CODE>` link is discarded outright for anybody already `.ready`,
and the only field that takes a code lives behind `session == .noGroup`. The mirror is that an
existing circle has no invite affordance at all. Nothing on the server changes.

Closed 2026-08-31. Three bugs turned up on the way that were not in the plan and are worth
knowing about: `CloseButton`'s glyph never scaled with Dynamic Type (every sheet in the app, and
every `accessibility5` golden containing one, was drawing a control the device would not); the
invite-code field's normalisation never reached the text field, so a **pasted** code showed as
typed while the store held something else; and `error.alreadyingroup` was still worded for
one-circle-per-person. See the epic file for each.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E38-01 The switcher, remade | done | — | no | — |
| E38-02 Join with a code, when you already have one | done | E38-01 | no | — |
| E38-03 Inviting out of a circle you already have | done | E38-01 | no | — |
| E38-04 The switch is quiet | done | — | vs E38-03 | — |

---

## E40 — Reads mean what they say

The pairwise-read maths behind Insights and the profile's "You and them" panel, corrected in four
places: a round only counts if the reader guessed in it, credit follows the person named rather
than the card it was written on, the two mutual lists now partition the pairs instead of leaving
some in neither, and the query feeding all of it stops being truncated at PostgREST's 1000-row
cap. `E39` proposes the opposite reading of a blank sheet and is set aside, not superseded.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E40-01 A read counts the rounds you guessed in, and credits the person you named | done | — | no | — |

---

## E41 — The quick pass · [file](E41-quick-pass.md)

The guessing on-ramp: one card at a time, full screen, and where a reveal push now lands. Three
slices, all client-only — no migration, no endpoint, no push-worker change. Design brief:
`docs/prompts/QUICK-PASS-DESIGN-PROMPT.md`.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E41-01 One card, one tap, next | done | — | no | AC-4 |
| E41-02 Where the push lands, and how the run ends | done | E41-01 | no | AC-4 |
| E41-03 A way back | done | E41-02 | no | AC-4 |

---

## E43 — Set tomorrow's cue · [file](E43-set-tomorrows-cue.md)

The admin writes the next round's cue by hand, from circle settings, until that round opens.
Reverses `docs/18-CUES.md` §11.6's "no admin-authored custom cues" — an owner amendment on the
same footing as ADR-011, made because the ban had been worked around as a migration five times.
Free text only, and a custom line is never promoted into the catalog.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E43-01 The override survives a cadence change | done | — | no | — |
| E43-02 The API reads and writes the next cue | done | E43-01 | no | AC-1 (leak) |
| E43-03 The row in circle settings | done | E43-02 | no | — |

---

## E44 — Five pieces of polish · [file](E44-four-pieces-of-polish.md)

Five owner-reported defects from an app walk, 2026-09-11, all client-only. The first three are
small and certain; the fourth touches the drop screen's keyboard arrangement and is bounded by an
owner constraint — the cued night's layout does not change, and the keyboard-ownership rewrite
that would have fixed the chrome's snap-down outright is explicitly out of scope.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E44-01 Sheets put the keyboard away when they close | done | — | yes | — |
| E44-02 A circle you have already seen does not show a skeleton | done | — | yes | — |
| E44-03 Past results keeps its store too | done | E44-02 | no | — |
| E44-04 The uncued drop screen is centred, not resting on the keyboard | done | — | no | — |
| E44-05 The shortlist draws like the pool it came from | done | — | vs E44-02, E44-03 | — |

---

## E45 — Report a member · [file](E45-report-a-member.md)

App Review's UGC rule (1.2) wants a filter, a report, a block, and contact information. Three of
the four Blind Drop already answers — the catalog is Apple's, leaving a circle *is* the block
(per-user hiding would leak the blind window), and the support page is published. This epic is
the fourth: one action in the group page's existing `⋯` menu, open to every member.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E45-01 A member can report a member | done | — | no | AC-11 |

---

## E46 — Reactions · [file](E46-reactions.md)

An owner request — *"a heart, a dislike, at either the reveal or the answers"* — and a rule
change to go with it: `docs/16` §1 and `tasks/ICEBOX.md` banned reactions outright, and both are
amended by `docs/19-REACTIONS.md` (2026-09-17). The ICEBOX's objection is answered, not waived:
**a reaction is placed blind at the reveal and the counts resolve at 22:00, exactly like a
guess.** Three closed kinds, anonymous counts, no push, no score. Read `docs/19` first.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E46-01 The reaction model and the route | done | — | no | AC-12 |
| E46-02 Placing a mark at the reveal | done | E46-01 | no | AC-12 |
| E46-03 Counts at the answers | done | E46-02 | no | AC-12 |

---

## E47 — Sign in with Apple, as Apple requires it · [file](E47-sign-in-with-apple-name.md)

App Review rejected build 1.0 (2) on 2026-09-21 under guideline 4: the app asked for a display
name after Sign in with Apple, which the Authentication Services framework had already provided.
It had, and the app never asked for it — `requestedScopes` was empty. The name now comes from
Apple, `docs/08` §1.2 is skipped, and 1.3 shows the adopted name with one tap to change it.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E47-01 The name comes from Apple | wip | — | no | Guideline 4 |

---

## Progress

| Epic | Done / Total |
|---|---|
| E00 | 5 / 5 |
| E01 | 5 / 5 |
| E02 | 5 / 5 |
| E03 | 6 / 6 |
| E04 | 4 / 4 |
| E05 | 6 / 6 |
| E06 | 4 / 4 |
| E07 | 6 / 6 |
| E08 | 7 / 7 |
| E09 | 4 / 4 |
| E10 | 7 / 7 |
| E11 | 6 / 6 |
| E12 | 5 / 5 |
| E13 | 5 / 5 |
| E14 | 3 / 5 |
| E15 | 3 / 3 |
| E16 | 1 / 2 |
| E17 | 10 / 10 |
| **v1 total** | **92 / 95** |

| Beta epic | Done / Total |
|---|---|
| E18 circles: server | 3 / 3 |
| E19 circles: the app | 3 / 3 |
| E20 invitations | 3 / 3 |
| E21 circle settings | 2 / 2 |
| E22 sealed privacy | 1 / 1 |
| E23 notifications | 2 / 3 |
| E24 leaderboard + profiles | 2 / 2 |
| E25 insights | 2 / 2 |
| E26 UI polish | 4 / 4 |
| E27 spikes | 5 / 5 |
| **Beta total** | **26 / 28** |

| Next-progression epic | Done / Total |
|---|---|
| E29 results & record depth | 3 / 3 |
| E30 share card | 1 / 1 |
| E31 conditional reminders | 1 / 1 |
| E32 two small fixes | 2 / 2 |
| E33 record chip | 1 / 1 |
| E34 marketing website | 1 / 1 |
| E35 cues | 6 / 6 |
| E36 personal share card | 1 / 1 |
| E37 drop screen redesign | 1 / 1 |
| E43 set tomorrow's cue | 3 / 3 |
| E38 circles end to end | 4 / 4 |
| E40 reads maths | 1 / 1 |
| E41 quick pass | 3 / 3 |
| E44 five pieces of polish | 5 / 5 |
| E45 report a member | 1 / 1 |
| E46 reactions | 3 / 3 |
| E47 sign in with Apple | 0 / 1 |
| **Next-progression total** | **30 / 32** |
