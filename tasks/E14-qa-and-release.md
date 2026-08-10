# E14 — QA and release

Every acceptance criterion in `docs/15` must have a **passing automated test**, not a manual
check. This epic closes the gaps left by the feature epics and runs the passes that only make
sense end to end.

---

### E14-01 — Leak audit, full pass

**Status:** todo · **Deps:** E04-04, E05-02 · **Reads:** `docs/14` §3, §10, `docs/15` AC-1
**Touches:** `tests/functions/leak*.ts`, `BlindDropTests/Unit/A11yLabelTests.swift`
**Verify:** `npm run audit:leak` green; iOS a11y leak test green

The feature epics each covered their own endpoint. This is the sweep across all of them,
including the two channels nobody thinks about.

- [ ] Every route in `functions/` has a golden file; a route without one fails the suite
- [ ] Latency correlation with submitter count: |r| < 0.2 over 100 samples
- [ ] Byte-length invariance across 0/1/5/11 other submitters
- [ ] Accessibility labels on Submit and Sealed contain no digit but the countdown
- [ ] No client model has a `submissionCount`, `hasSubmitted`, or `participants` field — grep,
      then fix
- [ ] `GET /groups/current` still carries no `joined_at`
- [ ] Rate limiting is per-user, never per-group (`docs/14` §3)
- [ ] Write the pass/fail summary into `docs/` as a dated release note

---

### E14-02 — Accessibility pass

**Status:** todo · **Deps:** E12-03, E13-01 · **Reads:** `docs/12` (all), `docs/15` §2
**Touches:** `BlindDropTests/Snapshot/*`, `BlindDropTests/Unit/A11y*`
**Verify:** the full snapshot matrix + `A11yReachabilityTests`

- [ ] Five screens × `{large, a11y1, a11y5}` × `{SE, 15 Pro Max}` — no truncation, no overlap
- [ ] Every element has a non-empty VoiceOver label (UI test walks each screen)
- [ ] Every card announces number, title, artist, and current guess
- [ ] Every hit region ≥ 44×44
- [ ] SE × 12 members × `.accessibility5`: everything reachable
- [ ] `PaletteContrastTests` green
- [ ] Snapshot run with the OS in dark mode produces identical output to light
- [ ] Reduced-motion final states pixel-identical to normal
- [ ] Plurals via `.stringsdict` for every `%lld` count
- [ ] Copy lint: no exclamation mark, no banned word

---

### E14-03 — Animation performance pass

**Status:** todo · **Deps:** E10-04, E11-04 · **Reads:** `docs/09` §6, `docs/15` AC-11
**Touches:** `perf/*.instruments`, CI config
**Verify:** Instruments run recorded and attached to the release note

**On a physical iPhone 12**, not the simulator. Simulator frame timings mean nothing here.

- [ ] 10 consecutive seals, zero animation hitches
- [ ] 12-card unseal, zero hitches
- [ ] No SwiftUI layout pass during either animation
- [ ] Cold launch → today's round rendered < 1.2s
- [ ] Search p95 < 400ms against staging
- [ ] `GET /rounds/current` p95 < 300ms against staging
- [ ] If the seal misses 60fps, fix the view hierarchy — **do not shorten the animation** to
      hit the number

---

### E14-04 — Full-loop UI test

**Status:** todo · **Deps:** E12-05 · **Reads:** `docs/15` AC-10, `docs/00` §7
**Touches:** `BlindDropTests/UI/FullLoopUITests.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropUITests/FullLoopUITests`

Drives submit → seal → reveal → guess (7 cards) → results against the fixture server,
measuring **interaction time only** — server waits are stubbed. It is a regression guard on
tap count and animation length, which are the things that actually drift.

- [ ] Asserts total interaction time < 90s
- [ ] Asserts tap count ≤ 18
- [ ] Asserts first search results within 400ms of the second keystroke
- [ ] Runs with a fake device clock set 5 years forward (AC-2) and with a foreign timezone
- [ ] Runs the reduced-motion variant
- [ ] Fails loudly with a per-step timing breakdown so a regression names its own cause

---

### E14-05 — Release checklist

**Status:** todo · **Deps:** E14-01, E14-02, E14-03, E14-04 · **Reads:** `docs/14` §10, `docs/15` §4
**Touches:** `docs/RELEASE-<date>.md`
**Verify:** every box ticked, with evidence

- [ ] All ten boxes of `docs/14` §10 ticked with output attached
- [ ] All eleven acceptance criteria have a named passing test
- [ ] The additional gates in `docs/15` §2 pass
- [ ] `strings` on the `.ipa` finds no secret
- [ ] App Privacy nutrition label matches `docs/14` §9 — no tracking
- [ ] Spotify dev-mode tester emails added in the Spotify dashboard
- [ ] APNs production key configured; a real device receives a real 8:00 PM push
- [ ] Manual pilot checks in `docs/15` §4 run **with a real group**, including the one that
      matters most: ask everyone afterwards whether anyone found a tell about who had
      submitted before 8:00 PM
- [ ] The seal feels good in a real hand. If it doesn't, it's wrong regardless of the frame
      counter.
