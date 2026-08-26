# 10 — Share card spec

> Results get screenshotted into the group chat. That is one of three pilot success criteria
> (`00-PROJECT-BRIEF.md` §5). **This is the distribution mechanism, not an afterthought.** It
> must be one of the best-looking surfaces in the app.

Rendered client-side with `ImageRenderer` in
`ios/BlindDrop/Features/Results/Share/`. No server image pipeline — server-side rendering
would mean shipping the fonts and the whole design system twice, and the data is already on
the device.

---

## 1. Two artifacts

| Variant | Size | Scale | Target |
|---|---|---|---|
| **Square-tall** | 1080 × 1350 (4:5) | 3× | iMessage, group chats, camera roll |
| **Story** | 1080 × 1920 (9:16) | 3× | Instagram / Snapchat Stories |

Both are produced from one `ShareCardView` with a `variant` parameter, so a copy change lands
in both. **The model keeps both shapes; the sheet ships square-tall** — iMessage is where this
actually gets pasted, and a chooser between one good default and one shape almost nobody wanted
charged every sharer a decision to save a few of them a detour. Story is spec'd here, rendered on
demand and covered by the goldens; it has no entry point in the UI (E17-02).

`ImageRenderer.scale = 3`. Output PNG. Typical size ~800KB — acceptable; do not JPEG the
artwork.

---

## 2. Content

`E30-01` redesigned this from a compact data table to one hero-scale moment: the headline
sentence, set at the display face's largest size, with everything else built as quieter support
underneath it. Same information as before — nothing new was added and nothing on the "what is
not" list below changed — but the headline now carries the card, and the four-row song table it
used to sit beside is gone.

```
  ┌────────────────────────────────────┐   1080 × 1350
  │                                    │
  │  THE COVE            10 AUGUST     │   masthead: displayS + label
  │                                    │
  │  TONIGHT'S DROP                    │   label, inkDim, letterspaced — a kicker
  │                                    │
  │  Nobody got                        │   displayXL, ink — the card's hero
  │  No. 7                             │
  │                                    │
  │  ▓▓▓▓  ▓▓▓▓  ▓▓▓▓  ▓▓▓▓            │   the filmstrip: up to 4 pieces of
  │  + 4 more                          │   bare artwork, caption, inkDim
  │                                    │
  │  BEST EAR                          │   label, inkDim
  │  Cal  100%                         │   bodyL name + display-face rate
  │                                    │
  │  Blind Drop                        │   label, inkDim, bottom-left
  └────────────────────────────────────┘
```

### The headline stat

One line chosen by this precedence, first match wins:

1. A card **nobody** got → *"Nobody got No. 7"*
2. A card **everybody** got → *"Everybody got No. 3"*
3. Someone scored **100% ear** → *"Cal read the whole room"*
4. Lowest readability of the night → *"Gus was unreadable"*
5. Fallback → *"8 songs, 56 guesses"*

Never more than one headline. Never a superlative that requires a comparison the viewer can't
see on the card. Unchanged by `E30-01` — the redesign changed how loudly this line is said, not
which line gets chosen (`ShareHeadline.swift`, still a pure function of the results, untouched).

### What is on the card

Group name · date · a small "Tonight's drop" kicker · the headline, as the card's one hero
element · up to 4 pieces of bare artwork (no title, no owner, no number) · overflow count · the
Best Ear leader · the wordmark.

### What is not

No QR code. No "download Blind Drop". No install link. No app-store badge. No user avatars.
No scores for people who aren't the headline (the Best Ear leader is the one exception this
document has always carried). The card is a **group artifact** — it works because it looks like
something the group made, not like an ad. The name at the bottom is the whole marketing.

**Also gone as of `E30-01`, on purpose:** song titles, owner names, and the row number that used
to sit beside each piece of artwork. The filmstrip is decoration under the headline, not a second
thing asking to be read — see the design-critique rationale in `tasks/E30-share-card-redesign.md`
for why the table was cut rather than merely shrunk further. Anyone who wants the per-song detail
already has the full Results screen; this artifact's job is to make somebody want to open it.

### Artwork shown

The first 4 cards by `card_no`, not by any interest ranking. Numbering is the game's spine, which
is exactly why the filmstrip keeps the order even though it no longer prints the numeral —
resorting it for the share card would misrepresent the night.

---

## 3. Style

Identical tokens to the app (`07-DESIGN-SYSTEM.md`) — the card must look like it came from
the app, because that is the entire distribution mechanism.

- Background `paper` throughout. No card surface, no hairlines — `E30-01` retired the table's
  `surface` + `edge` frame along with the table itself; the filmstrip is artwork directly on
  `paper`.
- Accent **ultramarine** only. The share card is a post-results artifact; nothing on it is
  sealed. **Amber must not appear.**
- The headline is set in `TypeStyle.displayXL` (56pt), the largest step the display face has —
  a token, not a literal, and the first place on this card that size has ever been used. It
  shrinks (`minimumScaleFactor`, never truncates) on its longest possible sentence, for the same
  reason everything fixed-size on this card shrinks rather than clips: the artifact is a fixed
  rectangle, and a line that doesn't fit doesn't grow the card, it pushes the wordmark off it.
- The Best Ear rate is the one number still set from a literal size rather than a `TypeStyle` —
  Bricolage Grotesque at 96pt (square-tall) / 112pt (story), `docs/07`'s two-literal exception,
  unchanged by the redesign.
- Filmstrip artwork at 180pt, `Radius.artwork`, unmodified — no scrim, no gradient, no rounding
  beyond the token. Bigger than the pre-redesign 96pt thumbnail, which is the "bigger, bolder
  album art" half of the brief; sized to the **story** variant's narrower content width, the
  binding constraint for fitting four across in either shape.
- Generous margins: 72pt square-tall, 96pt story with an extra 240pt of bottom safe space so
  the Instagram UI does not cover the wordmark.
- Nothing is ever laid over artwork — no caption, no number, no gradient. The filmstrip's
  overflow count sits in its own line below the pictures, never on them.

### Story variant differences
Same content, more vertical air — the canvas is taller and the `Spacer`s between blocks absorb
the difference, so nothing about the layout branches by shape beyond the margins, the bottom
safe space and the Best Ear rate's literal size (all three already covered above). Nothing is
added.

---

## 4. Behaviour

- **Share tonight** on `ResultsScreen` → the share sheet: one square-tall preview, its caption,
  and **Share tonight** → system share sheet with the rendered PNG. No variant picker — the sheet
  shows the card rather than asking which one.
- Render happens off the main thread, target < 250ms. Show the sheet immediately with a
  `paperSunk` skeleton if the render is not ready.
- Fonts must be registered before rendering. `ImageRenderer` silently falls back to the system
  face if Bricolage is not loaded — a snapshot test asserts the rendered numerals are not the
  system face.
- Artwork must be **fully loaded** before rendering. Render placeholders into a share image
  and the card is worthless. Await all four image loads, 3s timeout; on timeout render with
  `artwork_bg_color` blocks and log it.
- No watermark burn-in beyond the wordmark. No timestamp beyond the date.

---

## 5. Privacy

The card contains real display names and real song choices from a private group. Consequences
for the implementation:

- It is generated **only** on explicit user action. Never pre-rendered into a cache directory
  that another app could read, never written outside the app's temporary directory, and the
  temporary file is deleted after the share sheet dismisses.
- It contains no user IDs, no invite code, no group ID, and no join link. Someone who receives
  the image cannot use it to enter the group.
- Nothing about a round that is not `scored` is ever renderable. The share entry point does
  not exist in any other phase.

---

## 6. Verification

| Check | How |
|---|---|
| AC-9: renders at both dimensions | Snapshot tests at 1080×1350 and 1080×1920 against golden PNGs |
| Display face present | Snapshot test asserts the numeral glyph is not SF Pro |
| Artwork loaded | Unit test: renderer awaits all image loads before producing output |
| Headline precedence | Unit test over five fixtures, one per rule in §2 |
| Longest name + 100% Best Ear rate | Snapshot with a 24-character display name (`DisplayName.maximumLength`) as both the headline subject and the Best Ear leader |
| Temp file cleanup | Unit test: file absent after share-sheet completion handler |
| The sheet fits its detent | Snapshot test measures the rendered sheet on an SE against `Layout.shareSheetHeight` |
