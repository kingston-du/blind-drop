# Board

Conventions: [`tasks/README.md`](README.md). Statuses: `todo` · `wip` · `blocked` · `done`.

**Start here:** `E11-03`. `E00`–`E10` are done.

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
| E11-03 Name pool and the 12-member layout | todo | E11-02 | — |
| E11-04 **The unseal animation** | blocked | E11-01 | AC-11 |
| E11-05 Non-submitter and joined-late states | done | E11-02 | AC-6 |
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
| E11 | 3 / 6 |
| E12 | 0 / 5 |
| E13 | 0 / 5 |
| E14 | 0 / 5 |
| **Total** | **62 / 80** |
