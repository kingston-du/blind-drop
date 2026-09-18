# 08 — Screen specs

Five flows. Every state that exists is listed. Strings come from `11-COPY-DECK.md` — do not
write copy here or in code.

Navigation model: a single root that renders the phase-appropriate screen for today's round,
plus three pushed destinations (The Record, Group, Settings) and one modal (Search). **There is
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
├─ GroupScreen               pushed, roster + admin settings + leave
│   └─ MemberProfileScreen    pushed from a roster row
└─ SettingsScreen            pushed, profile and account actions
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

**The search screen is the screen.** There is no lobby in front of it: a screen whose only
content is a headline and a button that opens the real screen is a tap charged for nothing,
and the round is on a clock. The field is up and focused on arrival, so the first thing
somebody can do is the thing they came to do.

```
┌─────────────────────────────┐
│  The Cove              [?] [≡] │  group name bodyLStrong ink; menu → Record, Group, Settings
│  ───────────────────────────   │  hairline
│  Sunday, August 30  (SEALS IN 03:12:48) │  date caption inkDim; countdown badge, amber
│                             │             wash + amberEdge, label — one row, see below
│                             │
│                             │   ← the block sits mid-screen while there is nothing to show
│   Today's song.             │   displayL, ink
│   Nobody sees it until      │   bodyM, inkDim  ← this is the entire tutorial
│   8:00 PM.                  │
│  ┌───────────────────────┐  │
│  │ TONIGHT'S CUE         │  │   label, amberText
│  │ A song you loved as   │  │   displayS, ink
│  │ a kid                 │  │   surface, edge, radius 20, inset 20
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Search for a song    │  │   InsetField, surface + edge; ink border while focused
│  └───────────────────────┘  │
│                             │
│  Nobody can tell whether    │   bodyS, inkDim
│  you've dropped. You can't  │
│  tell either.               │
│                             │
└─────────────────────────────┘
```

**The header is two rows, not three.** Who you are looking at on the first — the circle's name
and the menu, separated from the rest by the app's one chrome hairline — and what the round is
doing on the second: the date leading, the badge trailing. They share that row only while both
fit; a narrow device at a large type size stacks them, measured rather than predicted.

**The cue is a card here, and only here.** Everywhere else it is `CueBanner`, one neutral line
riding above the phase screen. On this screen it is the brief for the field directly beneath it,
so it moves into the column between the subhead and the field and takes the card treatment
above. Its micro-label is `amberText` — the one exception to `docs/18` §2, argued there.

At accessibility sizes the subhead steps aside so the card and the field keep their room; the
card itself stays. As soon as results exist they take the space under the field, the subhead
*and* the card step aside, and the block rises to the top of the screen. Choosing a row pushes
**Confirm** (§3.2).

**There is no paste-a-link box.** There was one, under the blind line. It was removed by the
owner: a second full-width field standing permanently under the first one, on a screen whose
whole job is one field, read as two equal choices rather than as one choice and an escape
hatch. `POST /tracks/resolve` and the link parser still exist and are still tested; nothing
presents them.

**It answered two failures, and both costs are real.** Name them rather than only the loud one:

1. *Search is down.* While the Apple Music API is unavailable there is now no way to drop a
   song at all. `search.error` says so plainly instead of pointing at a control that is not
   there.
2. *The song is not findable by name.* This is the everyday one and it does not need an outage:
   an obscure title, an alternate spelling, a track credited differently in the catalog than
   the person typing remembers it. Previously a link from Spotify or Apple Music got them
   through anyway. Now they either find the words search wants or they drop something else,
   on an ordinary night with nothing wrong.

The second cost is the one worth revisiting first if this is reopened — most likely as
something the *failure* surfaces (offered under `search.empty`, where it is an escape hatch by
construction) rather than as furniture standing under every successful search.

**This screen leaks nothing.** No submission count, no "3 of 8 in", no avatars, no activity
indicator, no "waiting on Sam". The only shared fact on it is the clock, which everybody
already has. A reviewer should be able to look at this screen and at `GET /rounds/current`'s
`open` payload and see that neither could possibly express how many people have dropped.

### States
| State | Change |
|---|---|
| Default | as above, field focused, nothing under it |
| Searching | rows under the field, headline and field at the top of the screen |
| < 2h to reveal | The nudge line appears above the blind line: *"Two hours left to drop."* in `amberText`. Nothing else changes. This is an in-interface nudge, distinct from the push. |
| Before `opens_at` (dark hours) | No field. The headline says the round is done, and the countdown reads to `opens_at`. Last night's cue as a card, and — when that night `scored` — an `OutlineButton` into its answers (`docs/18` §7). |
| Offline | Inline banner under the header. Last known phase is shown, greyed. No optimistic submission — sealing offline is not supported and must fail honestly. |

---

## 3. Search and confirm *(modal over Submit)*

### 3.1 Search
The same `SongSearch` the Submit screen is built from, presented as a sheet **only when
somebody comes back to change a song they have already sealed**. The first search of a round
is not a modal; it is §2. Search field auto-focused, `surface` with an `edge` border that goes
`ink` while focused, keyboard up immediately.

- Debounce 250ms, minimum 2 characters. Results are `TrackRow`s in `.surface` style — each row is its own white card with an `edge` border, because a result is a target rather than a line to read past.
- Each row's play control plays the 30-second preview inline. One at a time.
- Empty query: no results list, no suggestions, no trending. A blank sheet with the field
  focused. This app does not have opinions about what you should drop.
- Zero results: one line, `alert`, directly under the field that was typed into.
- Search error: the copy from `11-COPY-DECK.md`, in the same place. No paste fallback — see
  §2, which removed it from both hosts at once, this sheet included.

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
│       Hold to peek          │   bodyM, inkDim — title/artist while held
│                             │
│      Sealed until 8:00.     │   bodyL, amberText
│                             │
│         03:12:48            │   monoXL, amberText, tabular
│         until reveal        │   caption, inkFaint
│                             │
│       Replace song          │   SecondaryButton
└─────────────────────────────┘
```

**Amended by `E22-01`.** The title and artist used to sit under the cover in plain view, on the
reasoning that hiding them from their own owner was theatre, not security — true of the *group*,
but this is one over a shoulder, and a cover reads better when it is actually covering something.
So, now:

- Both the artwork (already under the cover) and the title/artist beneath it are **hidden by
  default**. The title/artist's spot is taken by **Hold to peek**, `sealed.peek`
  (`11-COPY-DECK.md`), in the same place, at the same minimum size.
- **The hold target is the whole card** (`E28-04`), not only the title/artist strip — a finger
  anywhere on the artwork or the metadata opens it. Opening plays the caller's own 30-second
  preview for as long as the hold lasts, through the same shared player Reveal and Search already
  use, and crossfades the cover and the metadata over `Motion.Peek` (180ms) rather than snapping.
  > **Amended by the owner:** the preview is audible to anyone nearby, and `.playback` ignores
  > the silent switch. Deliberate, not an oversight — if it comes back as a bug report, it isn't
  > one.
- Held, both come back — exactly as long as the finger is down. Released, dragged off the card,
  or the screen leaves the foreground for any reason (navigation, the app backgrounding, the app
  switcher appearing, a call arriving), it reseals **immediately, with no animation, and the
  preview stops**: a closing cover is allowed to take a moment; a peek that lingers into a
  screenshot is not, and neither is a sound that keeps playing after it.
- VoiceOver needs no hold. The sealed card's own accessibility label always names the title and
  artist, peeking or not — the non-gesture path `12-ACCESSIBILITY.md` §5 requires, and a normal
  touch cannot reach the hold at all while VoiceOver is running, since the OS routes it to
  VoiceOver first.
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
│  The Cove          [?] [≡]  │   RoundHeader, pinned: the group's name on every
├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┤   phase (E17-09) — and on this one, nothing else
│  Monday 10 August           │   caption inkDim, the eyebrow over the headline
│  Tonight's drop  (01:42:19) │   displayL ink + ultramarine countdown badge
│                             │   the badge takes its own row above .accessibility1
│  8 songs                    │   bodyM inkDim
│  ┌───────────────────────┐  │   TONIGHT'S CUE / A song you hate — CueBanner,
│  │ TONIGHT'S CUE         │  │   paperSunk, the last thing before the cards
│  │ A song you hate       │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 01 ▓▓ Redbone    (Cal)│  │   FlightCard row: numberM, 56pt art,
│  │       Childish…    ▶︎  │  │   title/artist, chip on the same line
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 02 ▓▓ Ribs   ⌐Name them│ │   unassigned → dashed outline chip
│  │       Lorde        ▶︎  │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 04 ▓▓ Motion Sick…    │  │   YOUR card: no chip,
│  │       Phoebe B.  Yours│  │   "Yours" label in amberText
│  └───────────────────────┘  │   ← the ONE place amber appears here,
│              ⋮              │     because your card is still your secret
│                             │
├─────────────────────────────┤   surface, rounded at the top two corners only
│            ▁▁▁              │   grab bar — inside the header's tap region, not
│  YOUR CALL SHEET  6/7 ASSIGNED │  a control of its own (E17-10)
│                             │   the whole row toggles the detent; the trailing
│                             │   slot reads NAMING NO. 4 while a card is focused
│                             │   and CHANGE A GUESS once locked
│  Ana  Ben  C̶a̶l̶  Dee  Eli    │   name pool, pinned, horizontally scrollable;
│  ┌───────────────────────┐  │   a spent name is struck through as well as dimmed
│  │  Lock in guesses      │  │   PrimaryButton, ultramarine
│  └───────────────────────┘  │
└─────────────────────────────┘
```

**The date and the cue scroll; only the name row is pinned.** *(Owner, 2026-09-06.)* Both used to
stand above the scroll view — the date on `RoundHeader`'s second row, the cue as a `CueBanner`
between it and the flight — which is roughly a third of a phone of permanent header over the one
screen in the app that is a *list*. Neither has anything to say after the first read, and the date
was the same fact as *"Tonight's drop"* stated twice across a seam. A pinned row earns its height
from something that changes while somebody is reading; on this phase the badge beside the date is
`EmptyView`, because this screen counts to the answers in its own header. So the date is the
eyebrow over that headline and the cue is the last thing before the cards — brief, then the work,
the same order §3 gives the drop screen. `RoundDTO.Phase.scrollsItsOwnDate` and
`RoundDTO.Phase.drawsItsOwnCue` are where the two are decided; Sealed and Voided do not scroll and
keep both above the phase exactly as before.

The countdown scrolls away with the header, as it always has. It is not repeated in the call
sheet's peek row — a second copy of one number is two things to keep in sync — and if a persistent
deadline is ever wanted, that row is where it goes, not back into the chrome.

Once the sheet is locked in, a `ultramarineWash` panel appears under the header reading
*"Locked in."* The countdown is **not** repeated in it — it is already in the header badge, and
two copies of one number is two things to keep in sync.

### Interaction
Two directions, both supported, because 16-year-olds will try both:
1. **Tap card → tap name.** The tapped card gets a `ultramarine` focus ring; tapping a name
   assigns and advances focus to the next unassigned card.
2. **Tap name → tap card.** The name chip becomes selected; the next card tap assigns it.

Assigned names appear **consumed** in the pool — struck through in `inkQuiet` at 0.6 opacity,
so the state is carried by shape as well as by colour (`docs/12` §3) — but they remain tappable — tapping a consumed name moves it, clearing its previous card. Double
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

### Your own marks, on the flight
Each card shows the mark you placed in the quick pass — one glyph in `inkDim`, beside the number,
read-only (`E46-02`, `docs/19` §8.2). No count, no control: the row already carries a number,
artwork, two lines, a preview control and a name chip, and this is here so the flight agrees with
what you did in the cover rather than being a second place to do it.

`inkDim` and **not** the accent, which on this screen belongs to the guessing apparatus. It sits on
the **leading** side, against the number, and not beside the corner `⋯` — *Interesting*'s mark is
an enclosed ellipsis and the menu is a bare one, and 8pt apart they read as one control drawn
twice. Your own card carries no mark during `revealed`, because the run skips it.

### The unseal
On arriving at this screen for the first time in the round, cards unseal in a staggered
sequence, amber giving way to ultramarine (`09-MOTION-SPEC.md` §3). Runs once per round,
tracked by a persisted `hasSeenUnseal(roundId)` flag. Never on a re-open.

---

### 6.1 The quick pass — `revealed`, one card at a time (`E41`)

A `fullScreenCover` over the flight. The first in the app; every other modal is a `.sheet`, and
the reason for the difference is that a sheet's grabber and inset corners keep the flight visible
behind the one screen that is deliberately about a single card, with its detent chrome sitting
exactly where the name grid needs to be.

```
┌─────────────────────────────┐
│  ✕                          │   close, and deliberately nothing else
│                             │
│  04 / 08                    │   displayXL ultramarine + displayS inkFaint,
│                             │   both %02lld. The flight position, never a
│  ┌───────────────────────┐  │   count of what is left
│  │                       │  │
│  │        artwork        │  │   the largest in the app; side is what the
│  │                       │  │   column has not claimed, clamped 140…360
│  └───────────────────────┘  │
│  Motion Sickness       ▶︎   │   bodyLStrong / bodyM inkDim / PreviewControl
│  Phoebe Bridgers            │
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐ │   NameChip .large, 52pt, filling an adaptive
│  │ Ana  │ │ Ben  │ │ C̶a̶l̶  │ │   grid — 3 columns, 2 on an SE, 1 at
│  └──────┘ └──────┘ └──────┘ │   accessibility sizes
│  ┌──────┐ ┌──────┐          │
│  │ Dee  │ │ Eli  │          │
│  └──────┘ └──────┘          │
│  ‹        Skip              │   back glyph, leading · Skip, centred
└─────────────────────────────┘
```

**No prompt text and no countdown.** *"Who dropped this?"* is not drawn: a numeral, one song and a
grid of names is already the question. The countdown is not drawn either — eight ultramarine
digits in the corner take the eye before the numeral does, and a clock over a single card is a
per-card stopwatch. It is on the recap instead, and on the flight underneath.

**The run** is every card the caller may name, in flight order; their own card is passed over
silently, so the numeral can read `03` then `05`. The cursor starts at the first card without a
name, so a cover closed mid-run resumes where it was. Tapping a name fills the chip ultramarine
for ~100ms, fires `.impact(.light)`, and the card leaves leading while the next arrives trailing —
one spring, 220ms, cross-dissolve under Reduce Motion. Skip is the same transition with
`.impact(.soft)`.

**Going back.** The chevron beside Skip steps one card back, and so does a right swipe. Nothing is
undone: a name already placed stays placed and its chip returns struck through, so tapping another
name moves it exactly as on the flight. The transition takes its direction from the cursor — a card
arriving from the trailing edge on the way back would make going back feel like going on. Absent,
not disabled, on the first card. There is no back from the recap: its rows are the way back, and
they name the card you are going to.

**The recap** replaces the card when the run ends: `reveal.callsheet` as the heading with the
countdown beside it, one row per card — numeral, thumbnail, title, and the name in ultramarine,
*Yours* in `amberText`, or an `inkQuiet` em dash on a card left blank — and **Lock in guesses** at
the foot. Tapping a row goes back to that card, and answering it returns here rather than walking
out the rest of the run. Above `.accessibility1` the numeral and thumbnail take their own line and
the text has the full column.

**Getting in.** The reveal screen's primary action reads *Start naming* while the sheet is empty
and reverts to *Lock in guesses* once anything is assigned; tapping a card still opens the call
sheet, unchanged. The cover also opens itself, on three clauses in priority order
(`QuickPassPresentation`):

1. **Never** when the caller cannot guess, when every card is named, or while the round's unseal
   is still to run. The unseal carries half the app's motion budget and plays once a round; a
   modal over it spends the signature moment on nothing.
2. **Always** on a consumed `.round` deep link — a `reveal` or `guess_reminder` push tap. An
   explicit intent, and it re-presents however often it happens.
3. **Once otherwise**, per round per install. Dismissing the cover to browse the flight is a thing
   the person said.

Nothing on the server carries this: those pushes already deep-link to the round root, which during
`revealed` is the reveal host.

**Non-submitters never reach it.** No entry control, and the cover cannot present. They keep the
flight with the guess apparatus disabled but whole, per §6 — they must see exactly what they missed.

**The reaction bar** (`E46-02`, `docs/19-REACTIONS.md` §8.1). Under the name grid, above `‹ Skip`:
one `paperSunk` strip divided into three — **Loved it**, **Interesting**, **Not for me**, each a
mark over its word. Not three pills: `navigation` above rejects a bordered pill for Skip because
*"a bordered pill beside a grid of bordered pills reads as one more name"*, and three of them under
four `NameChip`s would read as three more candidates, of which three are not people. One sunk
object cannot be mistaken for a chip.

The chosen segment switches from its outline symbol to its filled one and takes the screen's
ultramarine, the word with it — shape as well as colour, per `docs/12` §3. Tapping it again clears
it. A tap fires `.impact(.light)` and **never advances the card**: naming still moves on
immediately, and a mark is a thing you do on the way past, not a second question you must answer.
Above `.accessibility1` the three segments become three rows, mark leading.

**No count is drawn here, because there is none yet.** `docs/19` §3 — the room's totals arrive at
the answers. Your own card is skipped by the run as it always was, so the only place your own drop
can be marked is §7.1.

## 7. Results — `scored`

Accent: **ultramarine**. Three sections in one scroll, under the same `RoundHeader` §6 draws —
which on this phase, as on the reveal, is the group's name and nothing else (E17-09). *"Answers"*
is the screen's own title and the date is its eyebrow, both inside the scroll, for the reasons §6
gives: a scored round is counting to nothing, so the pinned row it used to sit on held one short
date and no badge. The two registers still do not compete — `caption inkDim` over `displayL ink`,
one block.

### 7.1 Answers, card by card
**The cue heads the section, as a `CueCard`** — under *"Answers"*, above the first card.
*(Owner, 2026-09-03.)* Everywhere else the cue is `CueBanner`, one line of context above a phase
that is still running; here the cards are the room's replies to it, and a night read three weeks
later in The Record is unintelligible without it. `RoundScreen` therefore withholds its banner on
`scored` the same way it already does on the drop screen (`Phase.drawsItsOwnCue`). The label is
`results.cue.label` — *"The cue"*, neutral `inkDim`, and not *"Tonight's"*, because this is the
same screen `PastResultsScreen` pushes for a night from three weeks ago. Absent on an uncued
night, and on every night from before cues shipped.

Each card resolves: the number, the artwork, the track, and the owner's name arriving in
`bodyLStrong`. Beneath, `monoS`: *"4 of 7 got it"*. If you guessed, your guess is shown with
an `ultramarine` check or an `inkFaint` strike — never red, never a cross.

Each card's play control plays the 30-second preview inline, on the artist line — the same
control and the same shared player as Submit's search (§3.1) and the reveal flight. One at a
time: starting a second preview stops the first. Absent, not disabled, when the track carries
no preview URL.

Reveal is progressive on first view: cards resolve top to bottom, 120ms apart, each a
220ms crossfade of name-in. Skippable by scrolling — a scroll gesture completes the whole
sequence immediately. Runs once per round.

**Who guessed you** (`E29-01`). Under the caller's own card only, a disclosure lists every
guesser and what they picked — name, name, and whether it landed in the same neutral
ultramarine/inkDim word-mark the resolved cards themselves use, never a green/red glyph
(`docs/16` §5). This is not a grid: no other card carries this list, and there is no route to
see who guessed someone else.

### 7.2 You

Two equal tiles: **Readability** and **Accuracy**, each showing its percentage and underlying
counts. Accuracy wears the ultramarine accent; Readability remains neutral. At accessibility
sizes, stack the tiles. Accuracy is the percentage of possible answers the caller got right in
this round; the API retains the field name `ear`.

Readability's spectrum stays in its own panel below the pair, with a tick, both ends named,
and the active band. No fill from the left: neither end is better.

Accuracy with no guesses renders **—** and *"You sat this one out."*, never `0%`.
Readability for a non-submitter is absent, not zero, and its spectrum is absent with it.

### 7.3 Standings

**Tonight** is a separate module above the recent standings. It shows the server's top ranks,
with a correct-answer count beside each name: **4 correct**. Its caption is **This round**.
Historical results use **That night** as the heading. Ties share a rank and a tie crossing the
third-place boundary stays whole. No Readability ranking.

Everyone in a round has the same denominator, `submitter_count − 1`, so sorting by the raw
per-round rate already sorts by correct counts. The client converts that unformatted rate to
an integer count and preserves the server's order and ranks. At accessibility sizes, the count
moves below the name rather than squeezing it.

**Standings** ranks on **Ear**, the number of correct answers over the circle's last 14 scored
rounds (or its actual shorter history). The window is stated beside the heading. Rows use
**Ear 42**, never a percentage. Readability may accompany each row as a trait with its spectrum;
it is not a second ranking.

### 7.4 Share
One `PrimaryButton`: **Share tonight**. See `10-SHARE-CARD-SPEC.md`. This is the app's
distribution mechanism and one of its best-looking surfaces. It is not an afterthought and it
is not buried in a menu.

---

## 8. The Record

Reachable from the header menu in every phase. An archive, not a feed.

```
┌─────────────────────────────┐
│  ‹ The Record   [Ana ▾] [↑] │   member filter, then export
│                             │
│  Every song anyone has      │   lede, bodyM, inkDim
│  dropped, newest first.     │
│                             │
│  10 August              ›   │   displayS, ink, sticky; rule beneath
│  ┌───────────────────────┐  │
│  │ ▓▓  Redbone           │  │   TrackRow + attribution
│  │ ▓▓  Childish Gambino  │  │
│  │     Cal            ▶︎  │  │   attribution in bodyM, ink
│  └───────────────────────┘  │
│              ⋮              │
└─────────────────────────────┘
```

- Newest first, grouped by date, sticky date headers, cursor-paginated at 50.
- Only `scored` rounds appear (`04-API-CONTRACT.md` §5).
- Member filter as a menu; filtering to one person is the most-used view — it is how you
  learn someone's taste.
- Each row's overflow offers **Open in Spotify** / **Open in Apple Music** where the link exists,
  and nothing else — every item in it acts on the one song it hangs off.
- **The date header is the way into that night's results** → `PastResultsScreen` for that round.
  *(Owner, 2026-09-03; it was a third item in the row overflow.)* The results belong to the night,
  not to a song: as a row item the action was repeated identically on all of a night's rows and
  reaching it meant picking an arbitrary song first. The whole header is the button, with a
  trailing chevron — not an ellipsis, because there is exactly one night-scoped action and an
  overflow holding one item promises a set and charges two taps for it.
- **Amended: no `displayL` title, and the date headers carry the page.** The screen used to
  print *The Record* a second time directly under a navigation bar already saying it, then a
  subtitle, before the first night. The heading is gone and the lede is one line.
  `InsightsScreen` has never drawn its own title over the inline one and reads the better for
  it. The date moves the other way — from an 11pt tracked `SectionLabel` in `inkDim` up to
  `displayS` in `ink` — because a date is the unit this screen is organised by, and so is the
  thing a reader scrolls *to*.
- **The sticky header is `paper` with a rule, not a `paperSunk` fill.** The fill existed so a
  pinned header read as on top of the list — a real problem solved the wrong way. It made the
  strip a plate wedged under a translucent bar, crisp along its top edge and mushy along its
  bottom, which is what read as *clipped*. An opaque navigation bar removes the ghosting the
  fill was compensating for; a full-bleed rule then gives the strip the one boundary it needs.
- A night's cue sits under the date in `bodyLStrong` — the face a cue wears everywhere else —
  in `inkDim` rather than `CueBanner`'s `ink`, because the roles invert here: on a live round
  the cue is the brief, while in the archive the night is what you navigate by and the cue is a
  fact about it. The live round's *"Tonight's cue:"* label is not repeated; the date already
  names the night.
- **Export is a trailing toolbar item**, not a pinned footer. Two full-width buttons held the
  bottom of every screenful to advertise an action taken once a month, and the archive is a
  thing you scroll. It is declared in the same `toolbar` as the filter so the order is ours —
  filter, then export — rather than SwiftUI's, which put the glyph on the wrong side.
- Export: see `06-MUSIC-INTEGRATION.md` §6. Unresolved counts are stated plainly.
- Empty state (first week): *"Nothing in the record yet. It starts filling tonight."*

---

## 9. Group

Pushed from the header menu (`E21-01`). Its own name, when it reveals, who is in it and their
role, its timezone, how to **invite**, and how to leave. It carries no submitted state and no
join date — those stay outside this screen's data source, `GET /groups/{group_id}`, which is safe
in every round phase.

**Amended by `E38-03`: the invite code is drawn here**, directly under the leaderboard, with the
share link above it and the people-you-played-with shortlist below. The original sentence ruled
out the code along with submitted state and join dates, and that grouped three unlike things:
the other two are *members' state* and would be leaks, whereas a code is a property of the
circle, carries no count, names nobody, and is already in this screen's payload —
`GET /groups/{group_id}` has always returned `invite_code`. Ruling it out cost the product the
only way an existing circle could grow: the affordance lived solely in the sheet that creates a
group, so a circle could be filled for about thirty seconds after birth and never again, and a
person already in a circle could only be reached by a direct invitation from somebody they had
already played with. It is one `InvitePanel`, shared with that creation sheet, drawn quiet here
because this screen's subject is the standings above it.

**Amended again: the screen opens on a masthead.** The navigation bar carries no title — the
word *Group* named a category, not this circle — and the screen's first block is the circle's
own name at `displayM`, the `N MEMBERS · N ROUNDS` fact on its own full-width line beneath it,
and The Record's entry point as a full-width row between two rules. Three changes are folded
into that. The meta fact no longer shares a row with a control, so it stops wrapping to two
ragged lines on a circle with a long enough count. The Record stops being a pill chip — card
vocabulary at a fifth of a card's size, and the only rounded object in a flat header — and
becomes the same text-plus-chevron row The Record's own date headers already use, with no
leading glyph. And the name, which used to be an editable field two thirds of the way down the
screen, is the title: an admin taps it to open a rename sheet, the same way the next cue is
edited, so the screen holds one copy of the name rather than two that have to agree.

**Admin sees more, not different.** Renaming and the reveal-hour picker are absent for a member,
not shown disabled — a wall of greyed-out controls tells a member what they cannot have, and
that is not the point. Both are `PATCH /groups/{group_id}`, admin-enforced server-side
(`NOT_ADMIN`), so a member never sees them regardless of what a stale or tampered client would
try. The reveal hour states when a change actually lands (`03-DATA-MODEL.md` §4: the first
round not yet created, never tonight's) rather than leaving that to be discovered later.
Timezone is shown to everyone, plainly stated as fixed at creation — it is never a control.

Leaving is available to everyone and is the one destructive action here, so it is behind a
confirmation naming what stays (`11-COPY-DECK.md`'s `group.leave.confirm.*`): songs and guesses
remain in the circle's history, and the caller can rejoin later with an invite. The circle's
sole active admin cannot leave while other active members remain (`04-API-CONTRACT.md` §3,
`LAST_ADMIN_MUST_TRANSFER`) — unreachable through this app's own UI until `E21-02` gives it a
way to promote or remove anyone, and enforced server-side regardless.

## 10. Settings

Pushed separately from Group. Profile contains the caller's display name and **Save name**.
Account contains **Sign out** and **Delete account** behind the confirmation copy in
`11-COPY-DECK.md`. About links to the public Privacy Policy.

Sign out unregisters this device's APNs token before revoking the session, clears delivered
notifications, and removes local Spotify credentials. Account deletion requires a fresh
Sign in with Apple credential for Apple-authenticated users, revokes the Apple authorization,
then anonymises history and deletes the authentication principal.

No notification settings. No theme setting.

## 10.1 Member profile

Tapping a roster row opens a **circle-scoped** profile. The header uses the person's name,
monogram, and recent artwork. The caller's own profile omits the **You read them / They read
you** comparison; other profiles show both rates with their underlying counts.

Keep one ruled stats panel, in this order:

- **Ear**: the recent correct count, accented, with **Last N rounds**. No progress bar.
- **Accuracy**: the all-time percentage in a full-size stat row, with a blue proportion bar
  underneath and **All time · N rounds** as context. The number remains neutral so Ear leads.
- **Readability**: the all-time percentage with the same gradient spectrum, blue tick, and
  active band as the group page. It never uses a progress fill. Show **All time · N rounds**.
- **Drops**: the count.

Absent rates show **—** and **No rounds**, with no bar or tick. A real zero
retains its meter. Accuracy retains the API's pooled calculation and excludes zero-guess
rounds. The profile loading skeleton represents four stats.

Below, **Recent songs** is a newest-first list of up to five scored drops with their local dates.
There is no bio, edit control, follower/following count, activity feed, or non-scored round
information. The profile is a quiet explanation of finished play, not a social layer.

---

## 11. Cross-cutting states

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
