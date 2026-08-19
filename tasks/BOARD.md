# Board

Conventions: [`tasks/README.md`](README.md). Statuses: `todo` · `wip` · `blocked` · `done`.

`E18-01` closed 2026-08-18, unblocking `E18-02` and `E18-03` (parallel to each other). `E18-02`
closed 2026-08-19 — `GET /groups`, the switcher's data source — leaving `E18-03` and `E19-01`
(now unblocked on the server side) open.
`E22-01`, `E23-01` and all five `E27` spikes closed 2026-08-18 too — see each epic file for what
each actually needed (E22-01's one open item is a credentials-gated manual check, named there
rather than silently skipped). `E26` remains open — an earlier batch attempt on all four slices
ran out of budget before any of them produced usable work; all four went back to `todo` and were
picked up again separately, surviving several more session-limit cutoffs along the way (worked
worktrees were resumed rather than restarted where anything had actually landed). `E26-01`,
`E26-02` and `E26-03` closed 2026-08-19 — `E26-01` results laid out and playable, with one known
narrow-device title-truncation limit recorded as an open question in the epic file; `E26-02`
closed the committing-drag test gap this note used to flag below; `E26-03` gave search results
the room an `.accessibility5` subhead was eating. `E26-04` remains in progress.

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
```

E17-10 gated the **iOS** work, because it is what left the app's goldens and its one failing
test in a known state. That gate is open. E23-01 and E27 touch neither, so they never waited —
their `Deps` columns say `—` and mean it. E19-03 and E20-03 join the two lanes back together and need both.

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
| E18-03 The same song, twice, in one evening | todo | E18-01 | vs E18-02 | — |

## E19 — Multi-circle: the app holds more than one · [file](E19-circles-app.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E19-01 Every screen knows which circle it is showing | todo | E18-01, E18-02 | no | AC-1, AC-10 |
| E19-02 The switcher | todo | E19-01 | no | — |
| E19-03 A notification opens the circle it came from | todo | E19-02, E23-01 | no | — |

## E20 — Circle creation and invitations · [file](E20-invitations.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E20-01 Pending invitations | todo | E18-01 | vs E21, E24 | AC-3, AC-5 |
| E20-02 Starting a circle, and filling it | todo | E20-01, E19-02 | no | — |
| E20-03 Invitations in the switcher, and the push | todo | E20-02, E23-01 | no | AC-3 |

## E21 — Circle settings and roles · [file](E21-circle-settings.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E21-01 The circle's own screen | todo | E19-02 | vs E20, E24 | — |
| E21-02 Who is in charge | todo | E21-01 | no | — |

## E22 — Sealed-song privacy · [file](E22-sealed-privacy.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E22-01 Hold to peek | done | E17-10 | **yes, vs everything** | AC-1 |

## E23 — Notifications, working and verified · [file](E23-notifications.md)

Push does not work today. `E23-01` diagnoses before anything is repaired.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E23-01 Find out why, then fix it | done | — | **yes, vs E19–E21** | AC-3 |
| E23-02 Three deliveries, whatever the circle count | todo | E23-01, E18-01 | no | AC-3 |
| E23-03 It arrives, and it opens the right thing | todo | E23-02, E19-03 | no | AC-3 |

## E24 — The leaderboard and profiles · [file](E24-leaderboard-profiles.md)

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E24-01 Best Ear | todo | E18-01 | vs E20, E21 | — |
| E24-02 A person, in this circle | todo | E24-01 | no | AC-1 |

## E25 — Insights · [file](E25-insights.md)

Needs history to mean anything. Defer without regret if the beta has not produced it.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E25-01 Who you know, and who knows you | todo | E24-02 | vs E26 | — |
| E25-02 Who you get mistaken for | todo | E25-01 | no | — |

## E26 — UI polish and known bugs · [file](E26-ui-polish.md)

Only what does not belong to another slice. Everything else is fixed on the screen that owns it.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E26-01 Results, laid out for the numbers it produces, and playable | done | E17-10 | **yes** | AC-9 |
| E26-02 Guessing, without the fidget | done | E17-10 | **yes** | — |
| E26-03 Searching for a song with a keyboard in the way | done | E17-10 | **yes** | — |
| E26-04 The clock hits zero and the screen does not follow | wip | E17-10 | **yes** | AC-2 |

## E27 — Spikes · [file](E27-spikes.md)

Investigation only. Each ends in a recommendation, not code.

| Slice | Status | Deps | Parallel | Proves |
|---|---|---|---|---|
| E27-01 Opening a song in Spotify | done | — | **yes** | — |
| E27-02 Pick for me | done | — | **yes** | — |
| E27-03 A web page | done | — | **yes** | — |
| E27-04 Themed prompts | done | — | **yes** | — |
| E27-05 Streaks | done | — | **yes** | — |

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
| E18 circles: server | 1 / 3 |
| E19 circles: the app | 0 / 3 |
| E20 invitations | 0 / 3 |
| E21 circle settings | 0 / 2 |
| E22 sealed privacy | 1 / 1 |
| E23 notifications | 1 / 3 |
| E24 leaderboard + profiles | 0 / 2 |
| E25 insights | 0 / 2 |
| E26 UI polish | 3 / 4 |
| E27 spikes | 5 / 5 |
| **Beta total** | **11 / 28** |
