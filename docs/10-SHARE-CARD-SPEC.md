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

Same information, two layouts.

```
  ┌────────────────────────────────────┐   1080 × 1350
  │                                    │
  │  THE COVE · 10 AUGUST              │   label, inkDim, letterspaced
  │                                    │
  │  Tonight's                         │   displayL, ink
  │  drop                              │
  │                                    │
  │  ┌──┬──────────────────────────┐   │
  │  │1 │ ▓▓  Redbone         Cal  │   │   up to 4 flight rows
  │  ├──┼──────────────────────────┤   │   number in display face,
  │  │2 │ ▓▓  Ribs            Ana  │   │   artwork 96pt, owner right-aligned
  │  ├──┼──────────────────────────┤   │
  │  │3 │ ▓▓  Bags            Hal  │   │
  │  ├──┼──────────────────────────┤   │
  │  │4 │ ▓▓  Motion Sick…    Eli  │   │
  │  └──┴──────────────────────────┘   │
  │  + 4 more                          │   caption, inkFaint
  │                                    │
  │  ┌──────────────┬──────────────┐   │
  │  │ NOBODY GOT   │ BEST EAR     │   │   the headline stat pair
  │  │ No. 7        │ Cal  100%    │   │   monoM tabular
  │  └──────────────┴──────────────┘   │
  │                                    │
  │  Blind Drop                        │   caption, inkFaint, bottom-left
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
see on the card.

### What is on the card

Group name · date · up to 4 flight rows (number, artwork, title, owner) · overflow count ·
one headline stat · the Best Ear leader · the wordmark.

### What is not

No QR code. No "download Blind Drop". No install link. No app-store badge. No user avatars.
No scores for people who aren't the headline. The card is a **group artifact** — it works
because it looks like something the group made, not like an ad. The name at the bottom is the
whole marketing.

### Rows shown

The first 4 cards by `card_no`, not by any interest ranking. Numbering is the game's spine;
resorting it for the share card would misrepresent the night.

---

## 3. Style

Identical tokens to the app (`07-DESIGN-SYSTEM.md`) — the card must look like it came from
the app, because that is the entire distribution mechanism.

- Background `paper`, rows on `surface` with `edge` hairlines.
- Accent **ultramarine** only. The share card is a post-results artifact; nothing on it is
  sealed. **Amber must not appear.**
- Numbers in Bricolage Grotesque at 96pt (square-tall) / 112pt (story).
- Artwork at 96pt, `Radius.artwork`, unmodified — no scrim, no gradient, no rounding beyond
  the token.
- Generous margins: 72pt square-tall, 96pt story with an extra 240pt of bottom safe space so
  the Instagram UI does not cover the wordmark.
- Long titles truncate at one line with a middle ellipsis for the title and a tail ellipsis
  for the owner. Owner names never truncate before the title does.

### Story variant differences
Same content, more vertical air. The headline pair stacks instead of sitting side by side.
The date moves under the group name. Nothing is added.

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
| Long titles | Snapshot with a 90-character title and a 24-character display name |
| Temp file cleanup | Unit test: file absent after share-sheet completion handler |
| The sheet fits its detent | Snapshot test measures the rendered sheet on an SE against `Layout.shareSheetHeight` |
