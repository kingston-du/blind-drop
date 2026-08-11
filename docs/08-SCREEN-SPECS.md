# 08 — Screen specs

Five flows. Every state that exists is listed. Strings come from `11-COPY-DECK.md` — do not
write copy here or in code.

Navigation model: a single root that renders the phase-appropriate screen for today's round,
plus two pushed destinations (The Record, Group settings) and one modal (Search). **There is
no tab bar.** One primary action per screen, always.

```
RootView
├─ OnboardingFlow            (no profile / no group)
├─ RoundScreen               (switches on round.state)
│   ├─ SubmitScreen          open, no submission
│   ├─ SealedScreen          open, submitted
│   ├─ VoidedScreen          voided
│   ├─ RevealScreen          revealed
│   └─ ResultsScreen         scored
├─ RecordScreen              pushed, always reachable
└─ GroupSettingsScreen       pushed, admin fields conditional
```

---

## 1. Onboarding

Four steps, no tutorial carousel, no permission asks. The submit screen's empty state teaches
the game in one sentence.

### 1.1 Sign in
Single screen. App name in `displayL`, one line of what this is, **Sign in with Apple**
button (Apple's own, black, `Radius.control`). Phone number is behind a build flag and
disabled in v1 (needs an SMS provider — `01-ARCHITECTURE.md` §5).

### 1.2 Display name
`displayM` prompt, one text field (`paperSunk`, `Radius.control`, 52pt), **Continue**.
Copy makes the stakes clear: this is the name people will be guessing with, so use the one
your friends call you.
Validation: 1–24 characters after trimming. Inline error under the field in `alert`. Continue
is disabled until valid.

### 1.3 Join or create
Two options, join first — most users arrive via a link.
- **Join a group:** 6-character code field, `monoM`, auto-uppercasing, auto-advancing, paste
  handled. If the app was opened from `blinddrop://join/<CODE>` the field is prefilled and
  the button is focused.
- **Create a group:** `SecondaryButton` below.

### 1.4 Create a group *(creator path only)*
Group name field · timezone picker defaulting to the device timezone · reveal-hour picker
(18/19/20/21, default 20, shown as "8:00 PM"). Copy states the consequence: songs open at
10:00 AM and answers land at 10:00 PM.
On create: the invite code screen, code in `displayL`, **Share invite** (share sheet), and
**Go to today's round**.

### 1.5 Land
Straight onto today's round. No confirmation, no welcome.

**Edge:** if the user has a profile but no group (left a group), onboarding resumes at 1.3.
If they have a group but no profile (shouldn't happen), at 1.2.

---

## 2. Submit — `open`, no submission

Accent: **amber**.

```
┌─────────────────────────────┐
│  The Cove            [≡]    │   header: group name, bodyM inkDim; menu → Record, Settings
│                             │
│  Monday 10 August           │   label, inkDim
│                             │
│  ────────────────────────   │
│                             │
│   Drop one song.            │   displayM, ink
│   Nobody sees it until      │   bodyL, inkDim  ← this is the entire tutorial
│   8:00 PM.                  │
│                             │
│         09:47:12            │   monoXL, amberText, tabular — time until reveal
│         until reveal        │   caption, inkFaint
│                             │
│  ┌───────────────────────┐  │
│  │     Drop a song       │  │   PrimaryButton, amber fill, ink label
│  └───────────────────────┘  │
└─────────────────────────────┘
```

**This screen leaks nothing.** No submission count, no "3 of 8 in", no avatars, no activity
indicator, no "waiting on Sam". A reviewer should be able to look at this screen and at
`GET /rounds/current`'s `open` payload and see that neither could possibly express how many
people have dropped.

### States
| State | Change |
|---|---|
| Default | as above |
| < 2h to reveal | The nudge line appears above the button: *"Two hours left to drop."* in `amberText`. Nothing else changes. This is an in-interface nudge, distinct from the push. |
| Before `opens_at` (dark hours) | Countdown reads to `opens_at`; button disabled; copy says the next drop opens at 10:00 AM. |
| Offline | Inline banner above the button. Last known phase is shown, greyed. No optimistic submission — sealing offline is not supported and must fail honestly. |

---

## 3. Search and confirm *(modal over Submit)*

### 3.1 Search
Sheet, `Radius.sheet`, presented from **Drop a song**. Search field auto-focused,
`paperSunk`, keyboard up immediately.

- Debounce 250ms, minimum 2 characters. Results are `TrackRow`s.
- Each row's play control plays the 30-second preview inline. One at a time.
- Below the results, always: **Paste a Spotify or Apple Music link** →
  `POST /tracks/resolve`.
- Empty query: no results list, no suggestions, no trending. A blank sheet with the field
  focused. This app does not have opinions about what you should drop.
- Zero results: one line, `inkDim`, plus the paste affordance.
- Search error: the copy from `11-COPY-DECK.md`, plus the paste affordance.

### 3.2 Confirm
Pushed within the sheet. This is the screen the seal happens on.

```
┌─────────────────────────────┐
│  ✕                          │
│                             │
│      ┌───────────────┐      │
│      │               │      │   280pt artwork, Radius.artwork
│      │   artwork     │      │
│      │               │      │
│      └───────────────┘      │
│                             │
│      Motion Sickness        │   displayM, ink, centred
│      Phoebe Bridgers        │   bodyL, inkDim
│                             │
│      ▶︎ ──────────── 0:30    │   preview scrub, inkDim; absent if no preview
│                             │
│  ┌───────────────────────┐  │
│  │       Seal it         │  │   PrimaryButton, amber
│  └───────────────────────┘  │
│        Pick another         │   SecondaryButton
└─────────────────────────────┘
```

Tapping **Seal it** calls `PUT /rounds/current/submission`, and **on success** runs the seal
animation (`09-MOTION-SPEC.md`), then dismisses to `SealedScreen` with the card already
sealed — the animation is not replayed on the screen behind.

Failure: the button returns to rest, an `alert`-coloured line appears, nothing is sealed. The
seal animation never runs speculatively. It is a confirmation of a fact, and it must never
have lied.

---

## 4. Sealed — `open`, submitted

Accent: **amber**.

```
┌─────────────────────────────┐
│  The Cove            [≡]    │
│                             │
│  ┌───────────────────────┐  │
│  │ ░░░░░░░░░░░░░░░░░░░░░ │  │   SealedCard: amberWash fill,
│  │ ░░  cover over art ░░ │  │   amberDeep border, cover over artwork,
│  │ ░░░░░░░░░░░░░ ⊛ ░░░░░ │  │   amberDeep stamp lower-right
│  └───────────────────────┘  │
│                             │
│      Sealed until 8:00.     │   bodyL, amberText
│                             │
│         03:12:48            │   monoXL, amberText, tabular
│         until reveal        │   caption, inkFaint
│                             │
│       Replace song          │   SecondaryButton
└─────────────────────────────┘
```

- The user's own track title and artist **are** shown beneath the cover, small, in `inkDim` —
  it is their song and hiding it from them is theatre, not security.
- **Replace song** reopens search. Replacing is never penalised, never announced, and the
  replaced-song count is never displayed. After replacing, the seal animation runs again.
- The countdown ticks from `ServerClock`. At zero it refetches; it does not transition
  locally.
- Nothing else is on this screen. No "you're the 4th to drop", no roster, no preview of the
  reveal.

**Notification permission** is requested once, ~1.2s after the first successful seal, with the
copy from `11-COPY-DECK.md`. Never at launch.

---

## 5. Voided — `voided`

Accent: **amber, muted** (`amberText` on `paper`, no fills).

One line: *"Not enough drops tonight. Nothing revealed."* Beneath it, the user's own card,
unsealed and plain, with the copy *"Your song came back."* No count of how many did drop —
in a group of eight, "only 2 dropped" is a statement about six specific people. Below,
the countdown to tomorrow's open.

---

## 6. Reveal + Guess — `revealed`

Accent: **ultramarine**. This screen must work equally well at 6 cards and 12.

```
┌─────────────────────────────┐
│  Tonight's drop      [≡]    │
│  8 songs · 01:42:19         │   bodyM inkDim + monoM tabular
│                             │
│  ┌───────────────────────┐  │
│  │ 1  ▓▓▓  Redbone       │  │   FlightCard
│  │    ▓▓▓  Childish…  ▶︎  │  │
│  │    ┌────────────────┐ │  │
│  │    │  Cal        ✕  │ │  │   assigned → NameChip inline
│  │    └────────────────┘ │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 2  ▓▓▓  Ribs          │  │
│  │    ▓▓▓  Lorde      ▶︎  │  │
│  │    ┌────────────────┐ │  │
│  │    │ Who dropped…?  │ │  │   unassigned → empty chip
│  │    └────────────────┘ │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 4  ▓▓▓  Motion Sick…  │  │   YOUR card: no chip,
│  │    ▓▓▓  Phoebe B.  ▶︎  │  │   "Yours" label in amberText
│  └───────────────────────┘  │   ← the ONE place amber appears here,
│              ⋮              │     because your card is still your secret
│                             │
├─────────────────────────────┤
│  Ana  Ben  Cal  Dee  Eli    │   name pool, pinned, horizontally scrollable
│  ┌───────────────────────┐  │
│  │  Lock in guesses      │  │   PrimaryButton, ultramarine
│  └───────────────────────┘  │   subtitle: "6 of 7 assigned"
└─────────────────────────────┘
```

### Interaction
Two directions, both supported, because 16-year-olds will try both:
1. **Tap card → tap name.** The tapped card gets a `ultramarine` focus ring; tapping a name
   assigns and advances focus to the next unassigned card.
2. **Tap name → tap card.** The name chip becomes selected; the next card tap assigns it.

Assigned names appear **consumed** in the pool (`paperSunk`, `inkFaint`, 0.6 opacity) but
remain tappable — tapping a consumed name moves it, clearing its previous card. Double
assignment is permitted by the API; the UI discourages it by making the move the default
behaviour rather than blocking it.

Clearing: tap the `✕` on an inline chip.

### Rules
- Your own card is **displayed** (the numbering must not have a hole) but has no chip and is
  labelled *Yours*. Your own name is absent from the pool.
- The name pool is exactly this round's submitters. Duplicate display names get a
  disambiguating suffix: `Sam B.` / `Sam K.`, first letter of nothing available → `Sam (2)`.
- **Non-submitters:** the whole guess apparatus is visibly disabled — chips greyed, pool
  greyed, button replaced by an explanatory line. Not hidden. The user must see exactly what
  they missed. Copy: *"You didn't drop tonight, so you're sitting this one out."*
- **Joined after reveal:** same treatment, different line.
- Guesses save on every change (debounced 600ms) via `PUT /rounds/current/guesses`. **Lock in
  guesses** is a confirmation and a dismissal, not the only save — a user who closes the app
  keeps their sheet. The button's job is to let them feel done.
- After locking, the screen stays, chips become read-only-styled but still editable via an
  **Edit** affordance, and the countdown continues to 10:00 PM.

### 12 members on a small device
The name pool is a pinned horizontal scroller at the bottom with a fade-out gradient on the
trailing edge — the affordance that says "more names this way". The card list scrolls
independently. At `.accessibility3` and above, the pool switches to a 2-row wrapping grid
capped at 40% of screen height with its own vertical scroll. Test at iPhone SE with 12
members at `.accessibility5`; nothing may be unreachable.

### The unseal
On arriving at this screen for the first time in the round, cards unseal in a staggered
sequence, amber giving way to ultramarine (`09-MOTION-SPEC.md` §3). Runs once per round,
tracked by a persisted `hasSeenUnseal(roundId)` flag. Never on a re-open.

---

## 7. Results — `scored`

Accent: **ultramarine**. Three sections in one scroll.

### 7.1 Answers, card by card
Each card resolves: the number, the artwork, the track, and the owner's name arriving in
`bodyLStrong`. Beneath, `monoS`: *"4 of 7 got it"*. If you guessed, your guess is shown with
an `ultramarine` check or an `inkFaint` strike — never red, never a cross.

Reveal is progressive on first view: cards resolve top to bottom, 120ms apart, each a
220ms crossfade of name-in. Skippable by scrolling — a scroll gesture completes the whole
sequence immediately. Runs once per round.

### 7.2 You

```
   Readability                     Ear
   ┌──────────────────────┐        ┌──────────────────────┐
   │        86%           │        │        71%           │   monoXL, tabular
   │  6 of 7 read you     │        │  5 of 7 correct      │   caption, inkDim
   │  ──────────●─────    │        │                      │   StatMeter
   │  open book           │        │                      │   band label
   └──────────────────────┘        └──────────────────────┘
```

- Readability uses `StatMeter` with a marker, **no fill from the left**, and its band label.
  No rank, no arrow, no comparison to yesterday.
- Ear with no guesses renders as **—** with the line *"You sat this one out."* Never `0%`.
- Readability for a non-submitter is absent, not zero.

### 7.3 Standings
Two lists.
- **Best Ear** — ranked 1..N, `monoM` percentage, raw correct count in `monoS` `inkDim`.
- **Readability** — sorted but **unranked**, no numbers in front of names, each row a compact
  `StatMeter` and a band label. Rendering a rank position here is a spec violation
  (`02-DOMAIN-RULES.md` §4.5).

### 7.4 Share
One `PrimaryButton`: **Share tonight**. See `10-SHARE-CARD-SPEC.md`. This is the app's
distribution mechanism and one of its best-looking surfaces. It is not an afterthought and it
is not buried in a menu.

---

## 8. The Record

Reachable from the header menu in every phase. An archive, not a feed.

```
┌─────────────────────────────┐
│  ‹ The Record       [Ana ▾] │   member filter
│                             │
│  10 August                  │   label, inkDim, sticky section header
│  ┌───────────────────────┐  │
│  │ ▓▓  Redbone           │  │   TrackRow + attribution
│  │ ▓▓  Childish Gambino  │  │
│  │     Cal            ▶︎  │  │   attribution in bodyM, ink
│  └───────────────────────┘  │
│              ⋮              │
│                             │
│  ─────────────────────────  │
│  Export to Spotify          │   pinned footer, two SecondaryButtons
│  Export to Apple Music      │
└─────────────────────────────┘
```

- Newest first, grouped by date, sticky date headers, cursor-paginated at 50.
- Only `scored` rounds appear (`04-API-CONTRACT.md` §5).
- Member filter as a menu; filtering to one person is the most-used view — it is how you
  learn someone's taste.
- Each row's overflow offers **Open in Spotify** / **Open in Apple Music** where the link
  exists, and **See that night's results** → `ResultsScreen` for that round.
- Export: see `06-MUSIC-INTEGRATION.md` §6. Unresolved counts are stated plainly.
- Empty state (first week): *"Nothing in the record yet. It starts filling tonight."*

---

## 9. Group settings

Pushed from the header menu. Group name · timezone (read-only after creation, with a line
saying so) · reveal hour (admin only, with the `effective_from` date stated precisely) ·
invite code with **Share invite** · member list · **Leave group** in `alert`, behind a
confirmation.

No notification settings. No theme setting. No account settings beyond display name and sign
out.

---

## 10. Cross-cutting states

| State | Treatment |
|---|---|
| Loading, first launch | Skeleton of the phase-appropriate layout in `paperSunk`. No spinner, no logo animation. Under 1.2s or it is a bug. |
| Loading, refresh | Nothing. Silent refetch. |
| Offline | Persistent inline banner below the header. Cached round state renders greyed with the banner stating it may be stale. Mutations are disabled, not queued. |
| Error | Inline, `alert`, stating what happened and what to do. Never a modal alert for anything the user can retry. |
| Round not yet open | Covered in §2. |
| No group | Onboarding 1.3. |
| Deep link into a wrong phase | Land on the correct phase screen silently (`05-JOBS-AND-NOTIFICATIONS.md` §5). |
| App backgrounded across a transition | On foreground, refetch. If the phase changed, animate into the new screen (unseal if entering `revealed`). |
