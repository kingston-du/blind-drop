# Quick-pass design prompt — Blind Drop's guessing flow

Paste this into Claude Design. Nothing needs to be attached; this is a **new flow**, not a
redesign, so the brief carries its own context. Its sibling `REDESIGN-PROMPT.md` covers the
"here is a screenshot, tighten it" case and its no-adding rule does **not** apply here.

---

You are designing a new flow for **Blind Drop**, an iOS app. Read all of this before drawing
anything. The tokens, the rules and the existing components are not suggestions — they are a
shipped design system with unit-tested contrast, and a design that ignores them cannot be built.

---

## 1. What the app is

A blind tasting flight, for music.

A **circle** is a small group of friends — realistically 3 to 12 people. Every day the circle
plays one **round**, and a round has three phases on a fixed clock in the circle's own timezone:

| Phase | Default hours | What happens |
|---|---|---|
| `open` | 10:00 – 20:00 | Everyone drops **one song**. You see nothing about anyone else — not who has dropped, not how many. The blind window is the product. |
| `revealed` | 20:00 – 22:00 | Every song appears at once, anonymous and numbered `No. 1 … No. N`. You put a name on each card. |
| `scored` | 22:00 onward | Answers, per-card breakdown, stats, the circle's running record. |

Fewer than three drops and the round is **voided** — nothing is revealed.

Two stats come out of it, both deliberately unranked: **Ear** (how well you read the room) and
**Readability** (how legible your taste is to others). Neither has a "good" end.

The interface is quiet cool paper so exactly two things can be loud: **the album artwork** and
**the phase colour**. There is no tab bar. One primary action per screen, always.

Deliberately avoided, because they read as generic defaults:
warm cream + terracotta · near-black with one neon accent · hairline broadsheet rules at zero
radius · gradients or illustrations over artwork · decorative blobs · glassmorphism · card
shadows · gamified progress UI.

---

## 2. The problem you are solving

People drop a song reliably. **They don't guess.** The two acts look symmetric and aren't:

|  | Drop | Guess |
|---|---|---|
| Window | 10 hours, any time of day | **2 hours**, a fixed evening slot |
| Decisions | 1 | **N − 1**, one per card |
| Prep | none | read (and often preview) every card first |
| Partial attempt | doesn't exist | currently framed as `6 of 7 assigned` — as a shortfall |

Guessing is a scheduled appointment with homework, landing at dinnertime, and it gets *worse*
as circles grow. This is a friction problem, not a motivation problem. Anything that reads as
"make them care more" — pressure, streaks, scolding — is solving the wrong thing and is banned
outright by rule 4 below.

**The fix you are designing: a quick pass.** One card at a time, full screen, tap a name, next
card. The same N decisions, but arranged as a ninety-second posture instead of a five-minute
one. It is an *entry path*, not a replacement — it ends by handing the player to the existing
call sheet with everything already filled in and editable.

Success looks like: a person who gets the 20:00 push while walking home taps it, names four
cards before they reach the door, and never feels they left something unfinished.

---

## 3. What exists today (the screen you are relieving, not deleting)

`RevealScreen`, at 393pt wide:

```
┌─────────────────────────────────┐
│  The Cove              [?] [≡]  │  circle name + monospaced date beneath
│  Monday 10 August               │
│                                 │
│  Tonight's drop      (01:42:19) │  display headline + ultramarine countdown badge
│  8 songs                        │  the countdown runs to the 22:00 answers, not the reveal
│                                 │
│  ┌───────────────────────────┐  │
│  │ 01  ▓▓  Redbone     (Cal) │  │  FlightCard: big display numeral, 88pt artwork,
│  │         Childish…     ▶︎  │  │  title + artist, preview control, assignment chip
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ 02  ▓▓  Ribs  ⌐Name them  │  │  unassigned → dashed outline chip
│  │         Lorde         ▶︎  │  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ 04  ▓▓  Motion Sick…      │  │  YOUR card: no chip, "Yours" in amber —
│  │         Phoebe B.   Yours │  │  the one amber element on an ultramarine screen,
│  └───────────────────────────┘  │  because your own drop is still your secret
│               ⋮                 │
├─────────────────────────────────┤  a draggable call sheet, pinned to the bottom
│              ▁▁▁                │  grab bar; the whole header row toggles the detent
│  YOUR CALL SHEET  6/7 ASSIGNED  │
│  Ana  Ben  C̶a̶l̶  Dee  Eli        │  name pool, horizontally scrollable,
│  ┌───────────────────────────┐  │  a spent name struck through as well as dimmed
│  │     Lock in guesses       │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

It works, and for the person who sits down with it at 20:05 it is the right screen: a
simultaneous assignment puzzle where you can see the whole flight and reason across it. Two
directions are supported — tap a card then a name, or tap a name then a card — and every edit
saves immediately (debounced 600ms). **Lock in guesses** is a confirmation, not the save.

Its problem is the posture it demands. It asks you to solve a permutation, and `6 of 7
assigned` reads as *you are not done*, which at 1 of 7 reads as *don't bother*.

**Keep the call sheet.** You are designing the on-ramp to it and, in doing so, fixing how a
partial sheet is framed.

---

## 4. Rules you cannot break

1. **Light mode only.** One palette, no dark variant, ever.
2. **Two accents, semantic only.** Amber = sealed / hidden. Ultramarine = revealed / live /
   correct. **Exactly one accent per screen.** Guessing happens during `revealed`, so this
   whole flow is **ultramarine** — with the single documented exception that the player's own
   card is marked in amber, because their own drop is still hidden from everyone else. Accent
   is never decorative: if a colour isn't carrying that meaning, the element is neutral.
3. **No shadows.** Elevation is `surface` on `paper` plus a 1pt `edge` border. Flat paper with
   things resting on it, never floating panels.
4. **No gamification.** No streaks, badges, XP, levels, trophies, confetti, cosmetics, per-card
   timers, combo counters, or "nice one" affirmations. This is the rule a card-at-a-time flow
   is most likely to break, because every quiz app on earth looks like one. **Do not build a
   quiz.** The answers do not exist until 22:00, so there is nothing correct to celebrate and
   nothing wrong to buzz at. A card resolves into *a name written down*, and that is all.
5. **No leaks.** Never show — in any phase — who else has guessed, how many have, or how far
   along anyone else is. No "4 of 6 have played", no member dots, no activity feed.
6. **Correct / incorrect is ultramarine vs a neutral strike, never green / red.** Not relevant
   in this flow (no answers yet), but it tells you the palette's temperature: red `#B3261E` is
   errors only.
7. **Skipping is first-class and costs nothing to look at.** At 22:00 the server fills any card
   you left blank with a randomly chosen name (planned as `E39`, not yet shipped — design as if
   it is true, because this flow ships alongside it), so a skip is an honest "I don't know", not a
   failure. Design it as an equal sibling to naming, not as an escape hatch in small grey text.
   It must be reachable with the same thumb, in the same reach zone, as the names.
8. **Server owns time.** The countdown to 22:00 comes from the server clock. Never imply the
   player can extend it, and never invent a per-card clock.

---

## 5. Tokens — use these exact values, invent none

**Neutrals (cool, never warm — no cream, no oat, no beige)**
`paper #EFF1F5` screen background · `paperSunk #E7EAEF` sunk strips, disabled fills ·
`surface #FFFFFF` cards, rows, fields · `edge #DCE0E7` hairline border ·
`edgeStrong #D3D8E0` dividers, grab bars · `hairline #EAEDF1` the rule *inside* a card ·
`track #EEF0F4` the empty part of a meter or bar

**Ink** `ink #14161A` primary text · `inkDim #454B55` secondary text and **every micro-label** ·
`inkFaint #767C88` only for text ≥ 24pt and for UI marks — never body, never a micro-label ·
`inkQuiet #B9BEC7` disabled labels, a spent chip, the strike

**Amber — sealed** `amber #B26A06` fill and marks · `amberDeep #96590A` pressed ·
`amberText #8A5205` words on paper or surface · `amberWash #F6EAD6` sealed surface ·
`amberEdge #E6CFA6` the border that closes the wash

**Ultramarine — revealed** `ultramarine #2233C4` · `ultramarineDeep #1B29A0` pressed ·
`ultramarineWash #E3E6FA` · `ultramarineEdge #C3C9F2`

**Alert** `#B3261E` — errors only, never a game state.

Contrast is unit-tested against WCAG. Two consequences: body text never sits on an amber fill
(only a 17pt semibold button label does), and `inkFaint` is never used for a micro-label.

### Type — three faces, three jobs, none borrows another's

- **Display / numerals** — Bricolage Grotesque, widest cut, tabular. Card numbers, the
  countdown, results headlines, **and nothing else**. Never below 20pt.
  `displayXL 56/56` · `displayL 44/42` · `displayM 32/34` · `displayS 24/26` ·
  `numberL 44/44` · `numberM 26/26`
- **Body / UI** — SF Pro Text. Everything else; don't fight the platform.
  `bodyL 17/24` · `bodyLStrong 17/24 semibold` · `bodyM 15/20` · `bodyS 13/18` · `caption 13/18`
- **Data / timers** — SF Mono. `monoXL 34/36` · `monoM 15/20` · `monoS 12/16`, plus
  `label 11/14, +1.3 tracking, UPPERCASE` and `labelSmall 10/13, +1.1` — the monospaced
  micro-label that runs above a block and beside every number.

**The micro-label is the app's second voice.** Anything that *names* a thing rather than saying
it — `DROPPED BY`, `UNTIL ANSWERS`, `NO. 4 OF 8` — is set in it. That texture is why the display
face can stay rare. Use it; don't sprinkle it on everything.

Every number is tabular. Nothing shifts horizontally as a timer ticks.

### Space, shape, size

Scale: `2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56 · 72`.
Screen inset **24** · gap between blocks **32** · gap within a block **12** · card padding **20**
· row padding **12**.
Radii: artwork **8** · row/control **14** · panel **16** · card **20** · sheet **24** · pill full.
Primary button **56** tall (52 in the older component; either is fine, pick one and hold it) ·
field **54** · name chip **36–38** · **minimum touch target 44**.

---

## 6. Components that already exist — reuse them, recognisably

`FlightCard` (numbered reveal card, display numeral left, 88pt artwork, title/artist, preview
control, assignment chip) · `NameChip` (pill, 36pt; unused = `surface` + `edge` + `ink`,
consumed = `paperSunk` + `inkFaint` at 0.6 with a strike, selected = `ultramarine` fill + white)
· `PrimaryButton` (full width, phase accent) · `SecondaryButton` (text only, `inkDim`, no fill,
no border) · `CountdownView` (`monoXL`, tabular, `HH:MM:SS` and `MM:SS` under an hour) ·
`ArtworkTile` (radius 8, never a circle, **nothing layered over it** — no scrim, no play overlay
chrome) · `PreviewControl` (28pt, beside the artwork, its own 44pt target) · `TrackRow` ·
`CueBanner` · `EmptyState` · `SealedCard` · `StatMeter` · `ProportionBar` · `MonogramMark`.

Some nights the round carries a **cue** — one short line, identical for everyone, e.g. *"Tonight's
cue: a song you hate."* It appears on every surface that shows the round, or on none. Decide
whether it belongs in the quick pass and say why either way.

---

## 7. What to design

Four artboards minimum, at **393pt** (iPhone 15/17 class), light mode, with plausible real
content — real song titles, real first names, a circle of **six** so five cards need naming.

### A. The way in
How does the quick pass start, from the reveal screen shown in §3? It has to be obvious to
someone arriving cold from a push notification and unobtrusive to someone who wants the call
sheet directly. Both routes must survive. The reveal screen already has exactly one primary
action; do not give it two competing ones. Consider whether the quick pass is what an unstarted
sheet offers by default and the full flight is the alternative, rather than the other way round.

### B. The quick pass itself — the important one
One card, full screen. Everything the player needs to answer *"who dropped this?"* and nothing
else. Think about, and show your answer to:

- **What the card looks like at full-screen scale.** `FlightCard` was drawn as a list row; this
  is the same object with the whole screen to itself. Artwork can be much larger. The display
  numeral has to stay the anchor — `No. 4` is how two people in a circle talk about a song.
- **Where the names sit.** Five to eleven chips, one tap each, in the bottom third where a thumb
  is. Consider what happens at eleven, and what a *spent* name looks like here (a name can
  legitimately be used twice — the app permits it and does not block it).
- **Skip.** Rule 7. Equal weight, same reach.
- **The preview control**, for the person who needs to hear four seconds of it to know.
- **Progress**, honestly and without pressure — `No. 4 of 8` in the micro-label voice is
  probably enough. Not a ring, not a bar that shames, not a percentage.
- **The exit.** Leaving mid-run is normal and everything is already saved. Say so once, quietly,
  or make it so obvious it needs no saying.
- **The countdown to 22:00** — present, but it must not become a per-card stopwatch.

### C. The advance
What happens between tapping a name and the next card appearing. **Read the motion budget in §8
before you design this** — it is far smaller than the pattern invites.

### D. The end of the run, and the handoff
The last card is named or skipped. Where does the player land? The intended answer is the
existing call sheet with everything filled in — the reveal screen from §3, now showing their
work, still editable, **Lock in guesses** ready. Design that arrival so it reads as *here is
what you said*, not as *here is another screen of the same task*.

And design the fix that comes with it: **a partial sheet must stop reading as a failure.**
`6 of 7 assigned` is the current line. Two named cards out of seven is a real contribution and
should look like one. This is a copy and hierarchy problem, not a new component.

### States to account for (show the ones that change the layout, note the rest)

- Re-entering after a partial run — does it resume at the first unnamed card, or start over?
- The player's **own card** comes up in the sequence. It is displayed (the numbering must never
  have a hole) but has no chip and is labelled *Yours* in amber. What does a full-screen version
  of that look like, and does the quick pass stop on it or pass through?
- A three-person circle: two cards to name, one of them yours. The flow must not feel absurd.
- A twelve-person circle: eleven cards and eleven chips.
- Every card named already, and the player opens the quick pass anyway.
- Already **locked in**, and they come back to change one.
- A card whose track has no artwork and no preview.
- A very long title and a very long artist name.
- **Dynamic Type at `accessibility5` on an iPhone SE (320pt).** Nothing truncates, nothing
  overlaps — this combination is tested and is the worst case in the app. Above `accessibility1`
  the name pool becomes a two-column wrapping grid, side-by-side pairs stack, and the countdown
  drops to a coarse form ("12 minutes") that updates per minute instead of per second. Show at
  least a note, ideally an artboard.
- **Non-submitters cannot guess at all** and are shown the flight with the whole guess apparatus
  visibly disabled, not hidden — they must see exactly what they missed. They should never reach
  the quick pass; say how you'd keep them out of it without hiding its existence.

---

## 8. Motion — the budget is nearly zero, and that is deliberate

The entire motion budget of this app is spent on two moments: **the seal** (600ms, when you
commit your song — a cover slides, a stamp lands off-axis by 4°, one ring dissipates, two
haptics) and **the unseal** (380ms per card, staggered, at the reveal). Everything else is
standard iOS springs. Button press is 120ms at scale 0.985. There is exactly one shadow in the
app and it belongs to the moving seal cover.

So: **the card-to-card advance is not a set piece.** No flick-away, no deck of cards, no
3D flip, no swipe-to-dismiss physics, no confetti, no page-turn. A standard iOS transition,
possibly a brief token of the name landing on the card, and on to the next. If you propose
anything more than that, argue for it in one paragraph and accept that the default answer is no.

One haptic on assignment is fine and probably right. A haptic per card *plus* a sound plus an
animation is a slot machine, which is rule 4.

---

## 9. Voice, if you write any label

Dry, plain, active, a little arch. Sentence case. No exclamation marks. **The app never cheers.**
Buttons name what happens and keep the name through the flow: **Drop a song → Seal it → Sealed.**
Never "Submit". Never "Submitted".

Strings you can reuse verbatim: `Tonight's drop` · `Who dropped this?` · `Name them` · `Yours` ·
`Your call sheet` · `Naming No. %lld` · `Lock in guesses` · `Locked in.` · `Change a guess` ·
`until answers` · `%lld songs`.

Any new string is a proposal: list it separately at the end with the key you'd give it, so it
can go into the copy deck. Don't scatter invented copy through the artboards without flagging it.

Good register for this flow: *"Filled in for you"*, *"You didn't say"*, *"Name the ones you're
sure about"*. Bad register: *"Great job!"*, *"You're on a roll"*, *"Only 3 left!"*, *"Oops."*

---

## 10. Accessibility floor

Not a stretch goal — a build that fails these is not done.

- A card is a **single** VoiceOver element announcing number, title, artist, and current guess.
  Do not let VoiceOver walk into the artwork, the title and the artist separately; that is 36
  swipes to read a twelve-card reveal. The preview control is the one nested child, exposed
  both as a child and as a custom action.
- Assigning a name posts an announcement: *"No. 3 assigned to Cal."* Design what the quick pass
  announces on advance, so a VoiceOver user is not silently moved to a different card.
- State is never carried by colour alone — a spent chip is struck through *as well as* dimmed.
- Minimum target 44pt, including the skip and the preview control.
- Full Dynamic Type to `accessibility5`, per §7.

---

## 11. What to hand back

1. **Artboards** — A, B, C (as a short sequence or a described transition), and D, at 393pt,
   light mode, real content, a six-person circle. Plus the state artboards from §7 that change
   the layout.
2. **The reasoning, in six bullets or fewer.** Why the card is composed the way it is, where
   the names sit and why, how skip is weighted, what the advance does.
3. **The partial-sheet reframe** — the old line, the new line, and one sentence on why it reads
   differently.
4. **New strings**, listed with proposed keys.
5. **Anything you deliberately left out**, and why it was ornament.
6. **Concerns you did not act on** — a state you think is under-designed, a label you'd reword,
   a rule you think is fighting the flow. As notes, not as drawings.

Aim for: quiet, exact, a little severe. Fewer boxes. One thing to do per screen. Generous but
disciplined whitespace. A single accent doing real work. If a change can't be defended as making
the screen faster to read or act on, don't make it.
