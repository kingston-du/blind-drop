# Board

Conventions: [`tasks/README.md`](README.md). Statuses: `todo` · `wip` · `blocked` · `done`.

**Start here:** `E00-01`.

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
```

---

## E00 — Repo, tooling, CI · [file](E00-repo-and-tooling.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E00-01 Repo skeleton and npm scripts | wip | — | — |
| E00-02 Supabase local project | wip | E00-01 | — |
| E00-03 Xcode project skeleton | wip | E00-01 | — |
| E00-04 CI pipeline and lint rules | wip | E00-02, E00-03 | AC-2 |
| E00-05 Fixture server for iOS tests | wip | E00-01 | AC-10 |

## E01 — Database foundation · [file](E01-database.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E01-01 Extensions and core tables | wip | E00-02 | — |
| E01-02 RLS lockdown | wip | E01-01 | AC-1 |
| E01-03 Constraints and triggers | wip | E01-01 | AC-5, AC-6 |
| E01-04 Seed data (§4.4 fixture) | wip | E01-03 | AC-8 |
| E01-05 pgTAP harness and `now_()` | wip | E01-01 | AC-3 |

## E02 — Auth, profiles, groups · [file](E02-auth-and-groups.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E02-01 `_shared` http, auth, dto, db | todo | E01-02 | AC-1 |
| E02-02 `/me` | todo | E02-01 | — |
| E02-03 `/groups` create, join, current, patch, leave | todo | E02-02 | AC-1 |
| E02-04 Invite code generation | todo | E02-03 | — |
| E02-05 Account deletion | todo | E02-03 | — |

## E03 — Round lifecycle and scheduler · [file](E03-round-lifecycle.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E03-01 `ensure_rounds()` | todo | E01-05, E02-03 | AC-3 |
| E03-02 `tick_rounds()` reveal and void | todo | E03-01 | AC-3, AC-4 |
| E03-03 `tick_rounds()` score and nudge | todo | E03-02 | AC-3 |
| E03-04 `card_order` shuffle | todo | E03-02 | AC-5 |
| E03-05 `pg_cron` registration | todo | E03-03 | AC-3 |
| E03-06 Outage and idempotency tests | todo | E03-05 | AC-3, AC-4 |

## E04 — Submissions API · [file](E04-submissions.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E04-01 `PUT /rounds/current/submission` | todo | E03-01, E07-03 | AC-7 |
| E04-02 `GET /rounds/current` — open and voided | todo | E04-01 | AC-1, AC-4 |
| E04-03 Golden leak fixtures | todo | E04-02 | AC-1 |
| E04-04 `audit:leak` script | todo | E04-03 | AC-1 |

## E05 — Reveal, guesses, scoring · [file](E05-reveal-and-scoring.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E05-01 `GET /rounds/current` — revealed | todo | E03-04, E04-02 | AC-1, AC-5, AC-6 |
| E05-02 `PUT /rounds/current/guesses` | todo | E05-01 | AC-6 |
| E05-03 Scoring views | todo | E01-04 | AC-7, AC-8 |
| E05-04 `GET /rounds/{id}/results` | todo | E05-03 | AC-8 |
| E05-05 `GET /groups/current/standings` | todo | E05-03 | AC-8 |
| E05-06 §4.4 hand-checked scoring test | todo | E05-03 | AC-7, AC-8 |

## E06 — Push notifications · [file](E06-push.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E06-01 Outbox and APNs JWT | todo | E03-03 | AC-3 |
| E06-02 `push-worker` | todo | E06-01 | AC-3, AC-4 |
| E06-03 `POST /devices` | todo | E02-02 | — |
| E06-04 Idempotency, expiry, 410 handling | todo | E06-02 | AC-3 |

## E07 — Music services · [file](E07-music-services.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E07-01 Apple Music developer token | todo | E02-01 | — |
| E07-02 `GET /tracks/search` and cache | todo | E07-01 | AC-10 |
| E07-03 `POST /tracks/resolve` and `track_key` | todo | E07-02 | AC-7 |
| E07-04 Spotify client-credentials ISRC lookup | todo | E07-03 | — |
| E07-05 `track_links` backfill in the tick | todo | E07-04, E03-05 | — |
| E07-06 Record and export endpoints | todo | E07-04, E05-03 | — |

## E08 — iOS foundation · [file](E08-ios-foundation.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E08-01 App skeleton, light mode, environment | todo | E00-03 | — |
| E08-02 Palette and contrast test | todo | E08-01 | AC-2 gates |
| E08-03 Typography and font bundling | todo | E08-01 | — |
| E08-04 Component library | todo | E08-02, E08-03 | — |
| E08-05 `APIClient` and DTOs | todo | E08-01 | AC-1 |
| E08-06 `ServerClock` and the `Date()` lint | todo | E08-05 | AC-2 |
| E08-07 Snapshot test harness | todo | E08-04 | AC-9 |

## E09 — Onboarding · [file](E09-onboarding.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E09-01 Sign in with Apple | todo | E08-05 | — |
| E09-02 Display name | todo | E09-01 | — |
| E09-03 Join or create group | todo | E09-02 | — |
| E09-04 Invite code screen and deep link | todo | E09-03 | — |

## E10 — Submit and the seal · [file](E10-submit-and-seal.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E10-01 `SubmitScreen` | todo | E08-04, E08-06, E09-03 | AC-1 |
| E10-02 `SearchSheet` and preview player | todo | E10-01 | AC-10 |
| E10-03 `ConfirmScreen` | todo | E10-02 | — |
| E10-04 **The seal animation** | todo | E10-03 | AC-11 |
| E10-05 `SealedScreen` and countdown | todo | E10-04 | AC-1, AC-2 |
| E10-06 `VoidedScreen` | todo | E10-05 | AC-4 |
| E10-07 Push permission prompt | todo | E10-05, E06-03 | — |

## E11 — Reveal and guess · [file](E11-reveal-and-guess.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E11-01 `FlightCard` | todo | E08-04 | AC-5 |
| E11-02 Guess interaction | todo | E11-01 | AC-10 |
| E11-03 Name pool and the 12-member layout | todo | E11-02 | — |
| E11-04 **The unseal animation** | todo | E11-01 | AC-11 |
| E11-05 Non-submitter and joined-late states | todo | E11-02 | AC-6 |
| E11-06 Debounced guess save | todo | E11-02, E05-02 | — |

## E12 — Results and share · [file](E12-results-and-share.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E12-01 Answer reveal | todo | E11-04, E05-04 | AC-8 |
| E12-02 Personal stats and `StatMeter` | todo | E12-01 | AC-8 |
| E12-03 Standings | todo | E12-02, E05-05 | AC-8 |
| E12-04 Share card views | todo | E12-03 | AC-9 |
| E12-05 Share renderer and share sheet | todo | E12-04 | AC-9 |

## E13 — The Record and exports · [file](E13-record-and-export.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E13-01 `RecordScreen`, pagination, filter | todo | E08-04, E07-06 | — |
| E13-02 Per-track Spotify and Apple links | todo | E13-01 | — |
| E13-03 Spotify PKCE auth | todo | E13-01 | — |
| E13-04 Spotify playlist export | todo | E13-03 | — |
| E13-05 Apple Music playlist export | todo | E13-01 | — |

## E14 — QA and release · [file](E14-qa-and-release.md)

| Task | Status | Deps | Proves |
|---|---|---|---|
| E14-01 Leak audit, full pass | todo | E04-04, E05-02 | AC-1 |
| E14-02 Accessibility pass | todo | E12-03, E13-01 | AC-2 gates |
| E14-03 Animation performance pass | todo | E10-04, E11-04 | AC-11 |
| E14-04 Full-loop UI test | todo | E12-05 | AC-10 |
| E14-05 Release checklist | todo | E14-01..04 | all |

---

## Progress

| Epic | Done / Total |
|---|---|
| E00 | 0 / 5 |
| E01 | 0 / 5 |
| E02 | 0 / 5 |
| E03 | 0 / 6 |
| E04 | 0 / 4 |
| E05 | 0 / 6 |
| E06 | 0 / 4 |
| E07 | 0 / 6 |
| E08 | 0 / 7 |
| E09 | 0 / 4 |
| E10 | 0 / 7 |
| E11 | 0 / 6 |
| E12 | 0 / 5 |
| E13 | 0 / 5 |
| E14 | 0 / 5 |
| **Total** | **0 / 80** |
