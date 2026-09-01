# Redesign prompt — Blind Drop screens

Paste this into Claude Design, then attach the screenshot(s) of the screen(s) to redesign.

---

You are redesigning one or more screens of **Blind Drop**, an iOS app. I'll attach
screenshots. Redesign exactly what I attach — same screens, same purpose — nothing more.

## The single hardest rule

**Do not add anything.** No new buttons, tabs, filters, sort controls, search fields, avatars,
badges, icons, illustrations, banners, tooltips, progress rings, "pro tips", empty-state
mascots, or decorative shapes. If an element is not visible in my screenshot, it does not
exist in your redesign. You may re-arrange, re-group, re-space, re-weight and re-type what is
already there; you may merge two elements or drop pure ornament. Every interactive affordance
in the screenshot must still be present and still reachable.

If you genuinely think something is missing, say so in one line *below* the design — do not
draw it.

Likewise: don't invent copy. Reuse the exact strings in the screenshot. If a string must
change, list the change separately as a proposal, and keep the original in the design.

## What the app is

A blind-tasting flight for music. In a circle of friends, everybody drops one song into a
round while everyone else's drops stay hidden; at reveal the flight opens and people guess who
dropped what; then scores. The interface is quiet paper so two things can be loud: **album
artwork** and **the phase colour**.

Deliberately avoided, because they read as generic AI-design defaults:
warm cream + terracotta · near-black with one neon accent · hairline-ruled broadsheet layouts
with zero corner radius · gradients or illustrations over artwork · decorative blobs ·
glassmorphism · card shadows · gamified progress UI.

## Non-negotiable design rules

1. **Light mode only.** One palette. Never a dark variant.
2. **Two accents, semantic only.** Amber = sealed / hidden. Ultramarine = revealed / live /
   correct. **Exactly one accent per screen** (the only exceptions are the reveal transition
   and the How-to-play legend). Accent is never decorative — if a colour isn't carrying that
   meaning, the element is neutral.
3. **No shadows, ever.** Elevation is `surface` on `paper` plus a 1pt `edge` border. Flat
   paper with things resting on it, not floating panels.
4. **No gamification.** No streaks, badges, XP, levels, trophies, confetti, cosmetics.
5. **No leaks.** During a sealed round the UI must never imply who has or hasn't submitted, or
   how many have — no "3 of 5 in", no filled/empty member dots, no per-person status.
6. **Correct/incorrect is ultramarine vs a neutral strike — never green/red.** Red
   (`#B3261E`) is errors only.

## Tokens — use these exact values, invent none

**Neutrals (cool, never warm — no cream, no oat, no beige)**
`paper #EFF1F5` screen bg · `paperSunk #E7EAEF` sunk strips, disabled fills ·
`surface #FFFFFF` cards, rows, fields · `edge #DCE0E7` hairline border ·
`edgeStrong #D3D8E0` dividers · `hairline #EAEDF1` rule inside a card ·
`track #EEF0F4` empty part of a meter

**Ink** `ink #14161A` primary text · `inkDim #454B55` secondary text and *every micro-label* ·
`inkFaint #767C88` only for text ≥24pt and UI marks (never body, never a micro-label) ·
`inkQuiet #B9BEC7` disabled, spent chips, the strike

**Amber (sealed)** `amber #B26A06` fill + marks · `amberDeep #96590A` pressed ·
`amberText #8A5205` words on paper/surface · `amberWash #F6EAD6` sealed surface ·
`amberEdge #E6CFA6` the border that closes the wash

**Ultramarine (revealed)** `ultramarine #2233C4` · `ultramarineDeep #1B29A0` pressed ·
`ultramarineWash #E3E6FA` · `ultramarineWashLight #F4F6FD` · `ultramarineEdge #C3C9F2`

**Alert** `#B3261E` — errors only, never a game state.

Contrast is unit-tested. Body text on `amber` fill is not allowed — only a 17pt semibold
button label sits on an amber fill.

**Type — three faces, three jobs, nothing borrows another's**
- *Display / numerals*: Bricolage Grotesque, expanded width. Card numbers, the countdown,
  results headlines. **Never below 20pt.** Used in roughly six places in the whole app.
  `displayXL 56/56` · `displayL 44/42` · `displayM 32/34` · `displayS 24/26` ·
  `numberL 44/44` · `numberM 26/26` (all tabular).
- *Body / UI*: SF Pro Text. Everything else. `bodyL 17/24` · `bodyLStrong 17/24 semibold` ·
  `bodyM 15/20` · `bodyS 13/18` · `caption 13/18`.
- *Data / timers*: SF Mono. `monoXL 34/36` · `monoM 15/20` · `monoS 12/16`, plus
  `label 11/14 +1.3 UPPERCASE` and `labelSmall 10/13 +1.1 UPPERCASE` — the monospaced,
  widely-tracked micro-label that runs above a block and down the side of every number. That
  micro-label is the app's signature; keep using it, but don't sprinkle it on everything.

Numbers are always tabular. Nothing shifts horizontally as a timer ticks.

**Space (4pt-ish scale)** 2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56 · 72.
Screen inset 24 · gap between blocks 32 · gap between items 12 · card inset 20 · row inset 12.
**Radii** artwork 8 · row/control 14 · panel 16 · card 20 · pill full.
**Sizes** primary button height 56 · field height 54 · chip height 38 · minimum touch target 44.

## Components that already exist — reuse, don't reinvent

Artwork tile, close button, countdown, cue banner, empty state, flight card (numbered card
with a display numeral), help button, inset field, monogram mark, name chip, preview control,
primary button, secondary button, proportion bar, sealed card (amber wash + border + stamp),
stat figure / stat meter / stat tile, track row, track links.

If the screenshot shows one of these, keep it recognisably itself.

## Voice, if you touch any label

Dry, plain, active, a little arch. Sentence case. No exclamation marks. The app never cheers.
Buttons name what happens and keep the name through the flow: **Drop a song → Seal it →
Sealed**. Never "Submit". Never "Submitted".

## What to hand back, per screen

1. The redesigned screen at iPhone width (393pt), light mode, real content from my screenshot.
2. A short list of what you changed and *why* — hierarchy, rhythm, grouping, contrast. Three
   to six bullets, not an essay.
3. Any element you deliberately dropped, and why it was ornament.
4. Any concern you have that you did **not** act on (missing state, cramped label, a string
   you'd reword) — as a note, not as a drawing.

Aim for: fewer boxes, clearer one-thing-per-screen hierarchy, generous but disciplined
whitespace, and a single accent doing real work. Quiet, exact, a little severe. If a change
can't be defended as making the screen easier to read or act on, don't make it.
