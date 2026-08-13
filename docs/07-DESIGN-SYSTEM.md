# 07 — Design system

**Light mode only.** Owner amendment A1 (`00-PROJECT-BRIEF.md` §6) supersedes the original
PRD's dark palette. There is no dark mode in v1, no `colorScheme` branching, and no
`Color(light:dark:)` constructors. The root sets `.preferredColorScheme(.light)`.

Everything in this file lives in `ios/BlindDrop/DesignSystem/`. **A raw hex, font size, or
spacing number inside `Features/` is a review failure.**

---

## 1. The idea

A blind tasting flight. Cool paper, numbered samples, one thing to do per screen. The
interface is quiet so that two things can be loud: the **album artwork** and the **phase
colour**.

Explicitly avoided, because they are the current defaults and read as generic:
warm cream + terracotta/clay · near-black with one neon accent · hairline-ruled broadsheet
layouts with zero corner radius · gradients or illustrations over artwork · decorative blobs
· glassmorphism.

---

## 2. Colour

Two accents carry meaning and appear nowhere decoratively:

> **Amber = sealed. Information is hidden.**
> **Ultramarine = revealed. Information is open.**

A user should be able to tell what phase the round is in from across the room. **Exactly one
accent per screen**, except during the reveal transition where amber gives way to
ultramarine.

### Tokens

```swift
// DesignSystem/Palette.swift
enum Palette {
    // Neutrals — cool, never warm. No cream, no oat, no beige.
    static let paper       = Color(hex: 0xEFF1F5)  // base background
    static let paperSunk   = Color(hex: 0xE7EAEF)  // sticky strips, disabled fills, skeletons
    static let surface     = Color(hex: 0xFFFFFF)  // cards, rows, fields
    static let edge        = Color(hex: 0xDCE0E7)  // hairline borders
    static let edgeStrong  = Color(hex: 0xD3D8E0)  // emphasised borders, dividers, grab bars
    static let hairline    = Color(hex: 0xEAEDF1)  // the rule *inside* a card
    static let track       = Color(hex: 0xEEF0F4)  // the empty part of a meter or a bar

    static let ink         = Color(hex: 0x14161A)  // primary text
    static let inkDim      = Color(hex: 0x454B55)  // secondary text, every micro-label
    static let inkFaint    = Color(hex: 0x767C88)  // large text ≥ 24pt and UI only
    static let inkQuiet    = Color(hex: 0xB9BEC7)  // disabled labels, a spent chip, the strike

    // Amber — four tiers, each with a job. Do not interchange them.
    static let amber       = Color(hex: 0xB26A06)  // fill (white label) and mark
    static let amberDeep   = Color(hex: 0x96590A)  // pressed fill
    static let amberText   = Color(hex: 0x8A5205)  // text and labels on paper/surface/wash
    static let amberWash   = Color(hex: 0xF6EAD6)  // tinted surface behind sealed content
    static let amberEdge   = Color(hex: 0xE6CFA6)  // the border that closes the wash

    // Ultramarine — one token does text, fill, and graphics.
    static let ultramarine     = Color(hex: 0x2233C4)
    static let ultramarineDeep = Color(hex: 0x1B29A0)  // pressed state
    static let ultramarineWash = Color(hex: 0xE3E6FA)  // tinted surface
    static let ultramarineEdge = Color(hex: 0xC3C9F2)  // the border that closes the wash

    static let alert       = Color(hex: 0xB3261E)  // errors ONLY. Never a game state.
}
```

### Contrast — verified, and unit-tested

`PaletteContrastTests` asserts every row. If you change a hex, the test tells you what broke.

| Pair | Ratio | Requirement | Verdict |
|---|---|---|---|
| `ink` on `paper` | 16.02 : 1 | 4.5 (body) | pass |
| `inkDim` on `paper` | 7.77 : 1 | 4.5 (body) | pass |
| `inkFaint` on `paper` | 3.71 : 1 | 3.0 (large text ≥ 24pt / UI) | pass — **not for body text, not for a micro-label** |
| `amberText` on `paper` | 5.65 : 1 | 4.5 (body) | pass |
| `white` on `amber` fill | 4.24 : 1 | 3.0 (large text) | pass — **the 17pt semibold button label and nothing smaller** |
| `amber` on `surface` | 4.24 : 1 | 3.0 (non-text graphics) | pass |
| `amberText` on `amberWash` | 5.37 : 1 | 4.5 (body) | pass |
| `ultramarine` on `paper` | 7.94 : 1 | 4.5 | pass |
| `white` on `ultramarine` fill | 8.98 : 1 | 4.5 | pass |
| `alert` on `paper` | 5.78 : 1 | 4.5 | pass |

The tiered amber exists because a single warm amber cannot be both a satisfying fill and an
accessible label. Reach for `amberText` when writing words, `amber` when filling an area or
drawing a mark, `amberDeep` when a fill is pressed, `amberEdge` when a wash needs closing.

`white` on `amber` is the one pair in the table pinned from **both** sides: it must clear 3.0,
and it must not clear 4.5. A minimum on its own erodes — somebody sets a 13pt caption on amber,
the row still passes, and the caption is illegible. The day the fill is light enough to carry
body text is the day this restriction should be removed deliberately rather than outlived.

`inkFaint` is the same rule stated for a neutral: it is quiet enough to look like apparatus and
too quiet to be text at apparatus sizes, so **micro-labels are set in `inkDim`**, not in it.

### Usage rules

| Element | Colour |
|---|---|
| Screen background | `paper` |
| Card, sheet, row background | `surface` + 1pt `edge` border. **Never a drop shadow.** |
| Primary button, `open` phase | `amber` fill, `ink` label |
| Primary button, `revealed`/`scored` | `ultramarine` fill, `white` label |
| Sealed card treatment | `amberWash` fill, `amberDeep` 1pt border, `amberDeep` stamp |
| Live card treatment | `surface`, `edge` border, `ultramarine` card number |
| Correct answer mark | `ultramarine` |
| Incorrect answer mark | `inkFaint` strike — **never red** |
| Error text | `alert` |
| Disabled control | `paperSunk` fill, `inkFaint` label |

Correct/incorrect uses ultramarine/neutral, not green/red. Two accents mean two accents. Red
is reserved so that when it appears, it means something is broken.

### Elevation

There is no shadow in this app. Raised surfaces are `surface` on `paper` with a 1pt `edge`
border. Depth comes from the value step between `paper` and `surface`, which is deliberately
small — the app is flat paper with things resting on it, not a stack of floating panels.

The single exception: the seal **cover** casts a 0–4pt `ink` @ 8% shadow while it is in
motion, and it resolves to zero when it lands. Motion is the only thing allowed to be
dimensional (`09-MOTION-SPEC.md`).

---

## 3. Typography

Three roles, three faces. Do not use one for another's job.

| Role | Face | Where |
|---|---|---|
| **Display / numerals** | Bricolage Grotesque (variable, `wdth` widest, `wght 600`) | Card numbers. The countdown. Results headlines. **Nothing else.** |
| **Body / UI** | SF Pro Text (system) | Everything else. Do not fight the platform. |
| **Data / timers** | SF Mono (`.system(design: .monospaced)`) | Countdown digits, percentages, scores, counts. |

Bricolage Grotesque is SIL OFL and ships in the bundle as a variable font
(`Resources/Fonts/BricolageGrotesque.ttf`), with its licence beside it. Set the `wdth` axis to
**the widest cut the face carries** — the expanded cut is what gives the numbers character.
Read that value off the font rather than writing it down: today the axis runs 75–100, so the
numerals are set at 100, and a release that widens the axis is picked up with no code change.
`wght` is 600, which sits inside the face's 200–800 range and is set exactly.

The `opsz` axis is set to the size the glyphs are actually drawn at, scaling included. The
file's own default is 96pt — spacing designed for a poster — and leaving it there would set a
28pt screen title in it. This is the one axis that is not a fixed value, because it is the
one whose right value depends on the size.

Do not use the display face below 20pt; at small sizes its personality reads as noise.

### The scale

```swift
// DesignSystem/Typography.swift  — all sizes scale with Dynamic Type
enum TypeStyle {
    case displayXL   // 56/56  Bricolage 800 wdth max — the hero countdown, a stat number
    case displayL    // 44/42  Bricolage 700, -0.9    — the screen headline
    case displayM    // 32/34  Bricolage 700, -0.5    — a screen title
    case displayS    // 24/26  Bricolage 700, -0.2    — a card title, a name as a result
    case numberL     // 44/44  Bricolage 800, tabular — the answer card's number
    case numberM     // 26/26  Bricolage 800, tabular — the flight card's number
    case bodyL       // 17/24  SF Pro Text Regular    — default
    case bodyLStrong // 17/24  SF Pro Text Semibold   — track titles
    case bodyM       // 15/20  SF Pro Text Regular    — artist, supporting
    case bodyS       // 13/18  SF Pro Text Regular    — the line under a control
    case label       // 11/14  SF Mono Medium, +1.3, UPPERCASE — every micro-label
    case caption     // 13/18  SF Pro Text Regular    — helper text
    case monoXL      // 34/36  SF Mono Medium         — a large monospaced figure
    case monoM       // 15/20  SF Mono Medium         — percentages, scores
    case monoS       // 12/16  SF Mono Regular        — small counts, a badge's digits
}
```

**Tabular figures are mandatory anywhere a number changes.** Every mono style and every
numeral in a display style uses `.monospacedDigit()`. Nothing shifts horizontally as a timer
ticks. This is not a nicety — a countdown that jitters is the most visible possible signal
that the app is amateur.

**`label` is monospaced, and that is the app's second voice.** Everything that names a thing
rather than saying it — `DROPPED BY`, `SEALS IN 04:12:33`, `EAR 78 · READ 62` — is set in the
mono micro-label, uppercase and widely tracked. It is what makes a four-word caption read as
apparatus instead of as a sentence somebody forgot to finish, and it is why the display face
can stay rare: the texture of the app comes from the labels, not from more big type.

The display face is used for headlines, card numbers and the countdown, and nowhere else. If
you find yourself reaching for it somewhere that is none of those, use `bodyLStrong`.

---

## 4. Space, shape, and rhythm

```swift
enum Space {  // points
    static let xxs =  2, xs =  4, sm =  8, md = 12
    static let lg  = 16, xl = 20, xxl = 24
    static let x3  = 32, x4 = 40, x5 = 56, x6 = 72
}

enum Radius {
    static let artwork   =  8   // album art — softened, never a circle, never square
    static let card      = 20   // the subject card
    static let panel     = 16   // a panel of supporting information
    static let row       = 14   // one row of a list, drawn as its own surface
    static let control   = 14   // a button, a field
    static let sheet     = 24
    static let pill      = 999
}

enum Stroke {
    static let hairline = 1.0 / UIScreen.main.scale   // list separators
    static let border   = 1.0                          // card and control borders
    static let mark     = 2.0                          // the seal stamp outline
}
```

Layout law: **single column, one primary action per screen, generous vertical rhythm.**
Screen horizontal inset is `Space.xxl` (24). Vertical gap between distinct blocks is
`Space.x3` (32); within a block, `Space.md` (12). A card is padded `Space.xl` (20) and a row
`Space.md` (12) — the two paddings are what tell a subject from a list item before any of the
type is read.

Controls are 56pt tall and fields 54pt, which is the one place a single point of difference is
deliberate: a field above a button reads as *a thing to fill in, then a thing to press* rather
than as two halves of one control.

Album artwork is the only imagery in the app. It is large, sharp, unmodified, and the visual
anchor of every card. Nothing is layered over it — no gradient scrim, no play-button
overlay chrome beyond a small solid control beside it, no rounded-corner mask beyond
`Radius.artwork`.

---

## 5. Components

Built in `DesignSystem/Components/`. Every screen composes from these.

### `PrimaryButton`
Full-width, 52pt tall, `Radius.control`, `bodyLStrong` label. Accent from the current phase
(`amber` + `ink` label during `open`; `ultramarine` + white during `revealed`/`scored`).
Pressed: fill darkens to the `Deep` variant, scale 0.985, 120ms. Disabled: `paperSunk` fill,
`inkFaint` label, no press animation.

### `SecondaryButton`
Text-only, `inkDim`, `bodyL`. No border, no fill. For **Replace song**, **Open in Spotify**,
**Skip**.

### `TrackRow`
Search results and The Record. 56pt artwork, `Radius.artwork` · `bodyLStrong` title · `bodyM`
`inkDim` artist (1 line) · optional 28pt preview play control on the trailing edge. At normal
Dynamic Type sizes the title is one line and may truncate to keep results scannable. From
`.accessibility1` upward it wraps without a line limit, so essential track identity is never
lost. Whole row is the tap target; the play control is a nested button with its own 44pt target.

### `FlightCard`
The reveal card. Reads like a tasting flight sheet.

```
┌────────────────────────────────────────────────┐
│                                                │
│   4      ▓▓▓▓▓▓▓   Motion Sickness             │
│          ▓▓▓▓▓▓▓   Phoebe Bridgers        ▶︎    │
│          ▓▓▓▓▓▓▓                               │
│                    ┌──────────────────────┐    │
│                    │  Who dropped this?   │    │
│                    └──────────────────────┘    │
└────────────────────────────────────────────────┘
 ↑ displayXL          ↑ 88pt artwork      ↑ assignment chip
   ultramarine
```

Vertical stack, **never a grid**. The number sits large and left in the display face; artwork
and metadata to the right. The number is `ultramarine` when live, `amberDeep` when sealed.

### `SealedCard`
`amberWash` fill, `amberDeep` border, artwork covered by the seal cover, the stamp mark at
the lower-right of the cover. See `09-MOTION-SPEC.md` for how it arrives.

### `NameChip`
The guess sheet's name tokens. Pill, `Radius.pill`, 36pt tall, `bodyM`.
- Unused: `surface` fill, `edge` border, `ink` label.
- Consumed (already assigned to a card): `paperSunk` fill, `inkFaint` label, 0.6 opacity —
  still tappable, tapping moves it.
- Selected: `ultramarine` fill, white label.

### `CountdownView`
`monoXL`, tabular, `HH:MM:SS` under one hour → `MM:SS`. Driven by `ServerClock`
(`13-IOS-APP-ARCHITECTURE.md` §5), a 1Hz timer, never `Date()`. Colour follows phase. At zero
it does not change state — it triggers a refetch.

### `StatMeter`
The readability spectrum. A horizontal track, `paperSunk`, with a single `ultramarine` marker
at the position. **No fill from the left** — filling implies more is better, and readability
has no better. Show one active, one-word band label only, in `caption` `ink`: Clear, Legible,
Mixed, Elusive, or Unreadable. No arrow, no rank, no delta.

### `EmptyState`
`displayM` line + `bodyM` `inkDim` line + one `PrimaryButton`. Empty states are invitations,
not apologies (`11-COPY-DECK.md`).

---

## 6. Phase language, summarised

| Phase | Background | Accent | Primary action | Card treatment |
|---|---|---|---|---|
| `open`, nothing dropped | `paper` | amber | **Drop a song** | empty invitation |
| `open`, sealed | `paper` | amber | *(none)* — countdown only | `SealedCard` |
| `revealed` | `paper` | ultramarine | **Lock in guesses** | `FlightCard` live |
| reveal transition | `paper` | amber → ultramarine | — | unsealing |
| `scored` | `paper` | ultramarine | **Share tonight** | resolved cards |
| `voided` | `paper` | amber, muted | *(none)* | own card, returned |

Someone glancing at a screen from three feet away should know, from colour alone, whether the
information is hidden or open.

---

## 7. Checklist before any UI PR

- [ ] No hex, no font size, no spacing literal outside `DesignSystem/`
- [ ] Exactly one accent on the screen (or a documented transition)
- [ ] No shadows except the moving seal cover
- [ ] Every changing number uses tabular figures
- [ ] Display face used only for a card number, the countdown, or a results headline
- [ ] Nothing layered on top of album artwork
- [ ] Renders at `.accessibility5` Dynamic Type without truncation or overlap
- [ ] Contrast test still passes
