# E10 — Submit and the seal

Two things matter in this epic: the submit screen leaks nothing, and the seal is excellent.
`E10-04` is the single highest-craft task in the project.

---

### E10-01 — `SubmitScreen`

**Status:** todo · **Deps:** E08-04, E08-06, E09-03 · **Reads:** `docs/08` §2, `docs/11` (submit), `docs/07` §6
**Touches:** `Features/Round/{RoundScreen,RoundStore}.swift`, `Features/Submit/SubmitScreen.swift`
**Verify:** snapshot matrix; `PHASE=open` fixture run

Accent **amber**. The empty state is the entire tutorial: *"Drop one song. Nobody sees it
until 8:00 PM."*

- [ ] Layout per `docs/08` §2, single column, one primary action
- [ ] Countdown from `ServerClock`, tabular, `amberText`
- [ ] Nudge line appears inside the interface under 2h — distinct from the push
- [ ] Pre-`opens_at` state: countdown to open, button disabled
- [ ] **Nothing on this screen can express how many people have dropped.** No count, no
      avatars, no activity indicator, no roster.
- [ ] `RoundStore` refetches when the countdown hits zero; it **never** sets `state` locally
- [ ] Test: no accessibility label on this screen contains a digit other than the countdown
      (`docs/12` §2)

---

### E10-02 — `SearchSheet` and preview player

**Status:** todo · **Deps:** E10-01 · **Reads:** `docs/08` §3.1, `docs/06` §4 (previews), `docs/11` (search)
**Touches:** `Features/Submit/SearchSheet.swift`, `Core/Audio/PreviewPlayer.swift`
**Verify:** search returns results < 400ms against the fixture server

- [ ] Field auto-focused, keyboard immediate; debounce 250ms, minimum 2 characters
- [ ] Empty query shows a blank sheet — no suggestions, no trending. The app has no opinion
      about what you should drop.
- [ ] **Paste a Spotify or Apple Music link** always present, below the results
- [ ] `PreviewPlayer`: one at a time, never autoplays, audio session configured on first play
      only and deactivated at the end so the user's music resumes
- [ ] Error states from `docs/11`, each with the paste affordance still available
- [ ] No preview available → no control at all, not a disabled one

---

### E10-03 — `ConfirmScreen`

**Status:** todo · **Deps:** E10-02 · **Reads:** `docs/08` §3.2, `docs/11` (confirm)
**Touches:** `Features/Submit/ConfirmScreen.swift`, `SubmitStore.swift`
**Verify:** snapshot matrix

- [ ] 280pt artwork, `displayM` title, `bodyL` artist, optional 30s scrub
- [ ] **Seal it** / **Pick another**
- [ ] Calls `PUT /rounds/current/submission` and runs the seal **only on success**
- [ ] Failure returns the button to rest with an `alert` line; nothing is sealed
- [ ] Artwork pre-decoded before the seal begins (`docs/09` §2) — this is the most likely
      source of a dropped frame
- [ ] Dismisses to `SealedScreen` already sealed; the animation is not replayed underneath

---

### E10-04 — The seal animation

**Status:** todo · **Deps:** E10-03 · **Reads:** `docs/09` §1–2, §5, `docs/07` §2 (shadow rule)
**Touches:** `DesignSystem/Motion/{SealAnimation,MotionTokens}.swift`, `DesignSystem/Components/SealedCard.swift`
**Verify:** Instruments — 10 consecutive seals, zero hitches on iPhone 12

**The one moment the app is remembered by.** Six phases over ~600ms, specified frame by frame
in `docs/09` §2. Implement it against that timeline, not from memory.

- [ ] Phases A–F at the exact timings and curves in `docs/09` §2
- [ ] Driven by **one** `phase` enum through a single animation chain — not six
      `asyncAfter` calls. It must be interruptible and testable.
- [ ] The stamp lands **off-axis by 4°**. This is deliberate. Do not "fix" it.
- [ ] Two haptics: `.soft` at 100ms, `.rigid` at 380ms — at contact, not at phase start
- [ ] The cover's shadow exists only while moving and resolves to zero on land — the only
      shadow in the app
- [ ] Reduced motion: 240ms crossfade, same final state, **haptic still fires once**
- [ ] Test: zero SwiftUI layout passes during the animation
- [ ] Test: haptic counts (2 normal, 1 reduced)
- [ ] Test: reduced-motion final state is pixel-identical to the normal path's

---

### E10-05 — `SealedScreen` and countdown

**Status:** todo · **Deps:** E10-04 · **Reads:** `docs/08` §4, `docs/11` (sealed), `docs/12` §1
**Touches:** `Features/Submit/SealedScreen.swift`
**Verify:** snapshot matrix; `PHASE=open` with a submission

- [ ] `SealedCard` with `amberWash`, `amberDeep` border, stamp
- [ ] The user's **own** title and artist shown small in `inkDim` — hiding their own song from
      them is theatre, not security
- [ ] **Replace song** reopens search; replacing re-runs the seal and is never announced or
      counted
- [ ] Countdown ticks from `ServerClock`; at zero it refetches, it does not transition
- [ ] Coarse countdown form above `.accessibility2`
- [ ] VoiceOver: `a11y.sealed` announces song, artist, and time to reveal
- [ ] Nothing else on the screen

---

### E10-06 — `VoidedScreen`

**Status:** todo · **Deps:** E10-05 · **Reads:** `docs/08` §5, `docs/11` (voided)
**Touches:** `Features/Submit/VoidedScreen.swift`
**Verify:** snapshot; `PHASE=voided` fixture run

- [ ] Muted amber — `amberText` on `paper`, no fills
- [ ] The user's own card, unsealed and plain, with *"Your song came back."*
- [ ] Countdown to tomorrow's open
- [ ] **No count of how many did drop.** In a group of eight, "only 2 dropped" is a statement
      about six specific people.

---

### E10-07 — Push permission prompt

**Status:** todo · **Deps:** E10-05, E06-03 · **Reads:** `docs/05` §4, `docs/11` (push.permission)
**Touches:** `Core/Push/{PushRegistrar,PushRouter}.swift`
**Verify:** prompt appears once, ~1.2s after the first successful seal

- [ ] Requested **after** the first successful seal, never at launch — the ask lands when the
      user has just learned something happens at 8:00
- [ ] Pre-prompt copy from `docs/11` states exactly what they'll get and that there's nothing
      else
- [ ] `POST /devices` on grant and on every launch (cheap upsert)
- [ ] `PushRouter` maps the payload's `deep_link` to a `pendingRoute`
- [ ] A deep link **never** shortcuts a phase gate (`docs/05` §5)
- [ ] Declining is remembered; never re-prompted in v1
