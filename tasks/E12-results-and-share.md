# E12 — Results and share

The share card is the app's distribution mechanism (`docs/00` §5). `E12-04` and `E12-05` are
not cleanup tasks at the end of the epic — they are the point of it.

---

### E12-01 — Answer reveal

**Status:** wip · **Deps:** E11-04, E05-04 · **Reads:** `docs/08` §7.1, `docs/09` §4, `docs/11` (results)
**Touches:** `Features/Results/{ResultsScreen,ResultsStore}.swift`
**Verify:** snapshot matrix; `PHASE=scored` fixture run

- [ ] Each card resolves to its owner's name in `bodyLStrong`, with "%lld of %lld got it"
- [ ] Your guess marked with an `ultramarine` check or an `inkFaint` strike — **never red,
      never a cross** (`docs/07` §2)
- [ ] Correct/incorrect distinguished by **shape as well as colour** (`docs/12` §3)
- [ ] Progressive reveal top-to-bottom, 120ms apart, 220ms crossfade, the mark 80ms after its
      name
- [ ] **Any scroll gesture completes the whole sequence immediately** — never make a user who
      already knows what they want wait for an animation
- [ ] Runs once per round, persisted flag
- [ ] Special copy for "Nobody got it" / "Everybody got it"

---

### E12-02 — Personal stats and `StatMeter`

**Status:** todo · **Deps:** E12-01 · **Reads:** `docs/08` §7.2, `docs/02` §4.5, `docs/11`
**Touches:** `Features/Results/ResultsScreen.swift`, `DesignSystem/Components/StatMeter.swift`
**Verify:** `ScoringFormatTests`; snapshot at three type sizes

The one place a formatting bug becomes a product bug.

- [ ] Readability and Ear as `monoXL` percentages, tabular
- [ ] **`null` ear renders as "—" with *"You sat this one out."* — never `0%`.** Getting this
      wrong turns "you sat out" into "you scored nothing", which is the one judgement the
      product refuses to make.
- [ ] Readability absent (not zero) for a non-submitter
- [ ] `StatMeter`: marker only, **no fill from the left**, with its active one-word band label
      only in `ink`
- [ ] Band names from `docs/02` §4.5, presented without judgement — no arrow, no rank, no
      comparison to yesterday
- [ ] Above `.accessibility1` the pair stacks (`docs/12` §1)
- [ ] VoiceOver announces the percentage **and** the band name

---

### E12-03 — Standings

**Status:** todo · **Deps:** E12-02, E05-05 · **Reads:** `docs/08` §7.3, `docs/02` §4.5
**Touches:** `Features/Results/StandingsView.swift`
**Verify:** snapshot; unit test asserting no rank on readability

- [ ] **Best Ear** ranked 1..N, `monoM` percentage, raw correct count in `monoS` `inkDim`
- [ ] **Readability** sorted but **unranked** — no numbers in front of names, each row a
      compact `StatMeter` and a band label
- [ ] Test: the readability list renders no rank position. This is a spec violation
      (`docs/02` §4.5), so it gets a test, not a comment.
- [ ] Ties in Best Ear share a rank; the next rank skips

---

### E12-04 — Share card views

**Status:** todo · **Deps:** E12-03 · **Reads:** `docs/10` §1–3, `docs/11` (share)
**Touches:** `Features/Results/Share/{ShareCardView,ShareHeadline}.swift`
**Verify:** `ShareCardSnapshotTests` against goldens at both sizes

One view, a `variant` parameter, two artifacts — so a copy change lands in both.

- [ ] Square-tall 1080×1350 and Story 1080×1920, both at scale 3
- [ ] Content per `docs/10` §2: group name, date, up to 4 flight rows **by `card_no`** (not
      resorted by interest), overflow count, one headline, Best Ear leader, wordmark
- [ ] Headline precedence, five rules, first match wins — with a unit test per rule
- [ ] **Ultramarine only. Amber must not appear** — nothing on this card is sealed.
- [ ] No QR code, no install link, no store badge, no avatars. The card works because it looks
      like something the group made, not like an ad.
- [ ] Story variant stacks the headline pair and adds 240pt bottom safe space so the Instagram
      UI doesn't cover the wordmark
- [ ] Long titles: middle ellipsis on the title, tail on the owner; owner never truncates
      before the title

---

### E12-05 — Share renderer and share sheet

**Status:** todo · **Deps:** E12-04 · **Reads:** `docs/10` §4–6
**Touches:** `Features/Results/Share/ShareRenderer.swift`
**Verify:** `ShareRendererTests`; AC-9

- [ ] `ImageRenderer` at scale 3, PNG, off the main thread, target < 250ms
- [ ] **Fonts registered before rendering** — `ImageRenderer` silently falls back to the
      system face otherwise. Snapshot test asserts the numerals aren't SF Pro.
- [ ] **All artwork fully loaded before rendering**, 3s timeout, then `artwork_bg_color`
      blocks and a log. A share image of placeholders is worthless.
- [ ] Variant picker with two thumbnails, square-tall preselected (iMessage is where this
      actually gets pasted)
- [ ] Skeleton in `paperSunk` if the render isn't ready
- [ ] Written only to the app's temporary directory and **deleted after the share sheet
      dismisses** (`docs/10` §5)
- [ ] Entry point exists in **no phase but `scored`**
- [ ] Test: temp file absent after the completion handler
