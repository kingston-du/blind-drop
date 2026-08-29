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
| **Square-tall** | 1080 × 1800 (3:5) | 3× | iMessage, group chats, camera roll |
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

The card returns to the original numbered song table, then uses the added height for the
sharer's own results. It is one coherent artifact rather than a hero sentence with small facts
around it: the flight establishes the night, the one-line headline summarizes it, and the two
meters plus room table make the sharer's result legible at a glance.

```
  ┌────────────────────────────────────┐
  │                                    │
  │  The Cove             10 AUGUST    │   masthead
  │  Tonight's drop                    │
  │                                    │
  │  01  ▓▓  Redbone             Dee   │   surfaced, numbered song table
  │  02  ▓▓  Ribs                Ben   │   first four cards by card_no
  │  03  ▓▓  Bags                Hal   │
  │  04  ▓▓  Ribs                Ana   │
  │  + 4 more                         │
  │                                    │
  │  You read the whole room           │   displayS, exactly one line
  │                                    │
  │  YOUR EAR        READABILITY        │
  │  100%            25%  1 of 4 · ... │
  │  ━━━━━━━━━━      ━━━━━┃━━━━         │   native Results/Insights meters
  │                                    │
  │  THE ROOM THOUGHT YOU WERE         │
  │  Kingston                       3  │   surfaced tally table
  │  Leo                            2  │   correct row in ultramarine
  │  Mira                           1  │
  │                                    │
  │  Blind Drop                        │   label, inkDim, bottom-left
  └────────────────────────────────────┘
```

Both artifacts come from the same `ShareCardView`. A non-submitter keeps the masthead, song
table, group headline and wordmark; the personal meters and room tally are omitted rather than
replaced by unavailable values.

### The headline stat

One line chosen by this precedence, **first match wins**. Rules 1–4 are personal (`E36-01`) and
fire only when the caller's own card and rates make them true; rules 5–9 are `E30-01`'s original
five, unchanged:

1. The caller's **own card**, and nobody got it → *"Nobody got you"*
2. The caller's own card, and **everybody** got it → *"Everybody got you"*
3. The caller scored **100% ear** → *"You read the whole room"*
4. The caller was in the **unreadable band** → *"You were unreadable"*
5. A card **nobody** got → *"Nobody got No. 7"*
6. A card **everybody** got → *"Everybody got No. 3"*
7. Someone scored **100% ear** → *"Cal read the whole room"*
8. Lowest readability of the night, whatever it is → *"Gus was unreadable"*
9. Fallback → *"8 songs, 56 guesses"*

Never more than one headline. Never a superlative that requires a comparison the viewer can't
see on the card. Rule 4 is deliberately **stricter** than rule 8: rule 8 names the literal least
readable person regardless of their actual rate (an owner decision, `tasks/E12-results-and-share.md`);
rule 4 only fires inside the `unreadable` band, because *"You were unreadable"* on a 71% night is
a claim the sharer would be publishing about themselves, and it would be false.

A non-submitter (no own card) reaches no personal rule at all and falls straight through to the
group precedence — the same nine rules a submitter can reach, just without rules 1–4 ever being
true for them.

### What is on the card

**Always:** group name · date · "Tonight's drop" · the first four numbered song rows · overflow
count · one-line headline · wordmark.

**On a personal night** (`content.hasPersonalNight`): the caller's own ear as a percentage and
left-fill proportion bar · readability as a percentage, fraction, band and neutral spectrum
marker (never a rank) — each on its own `surface` panel, the same card treatment the results
screen's two `StatTile`s wear · a surfaced tally table of who the room guessed for the caller's
own card. The correct identity is ultramarine and every other row is `ink`.

The readability detail prefers `N of M · Band`. If that entire phrase cannot fit beside the
percentage, it falls back to the full band word; it never truncates the meaning into an ellipsis.

**On the fallback** (no personal night): omit the personal meters and tally.

### What is not

No QR code. No "download Blind Drop". No install link. No app-store badge. No user avatars. No
user IDs, no invite code, no group ID. **No guesser is ever named** — a tally of *"Cal ×3"* is on
the card; *"Maya thought you were Cal"* is not, because publishing a named person's wrong guess
outside the circle is not something the guesser agreed to (`tasks/E36-personal-share-card.md`'s
open question has the full reasoning, including how to reverse it if the owner wants to). **No
readability for anybody but the caller, at any scope** — `docs/02` §4.5's ban on ranking
readability is untouched; the caller's own readability is on the card because it is theirs. **No
all-time number for anybody**, the caller included — the card is about one night. The name at the
bottom is the whole marketing.

### Artwork shown

The first 4 cards by `card_no`, not by any interest ranking. Each row contains its zero-padded
number, unmodified artwork, song title and owner. Nothing is laid over the artwork. Resorting the
rows would misrepresent the night because numbering is the game's spine.

---

## 3. Style

Identical tokens to the app (`07-DESIGN-SYSTEM.md`) — the card must look like it came from
the app, because that is the entire distribution mechanism.

- Background `paper`. The flight, the two personal scores and the room tally are `surface`
  panels with an `edge` border; the flight and the tally add hairline row separators. No shadows.
- Accent **ultramarine** only. The share card is a post-results artifact; nothing on it is
  sealed. **Amber must not appear.**
- The headline is `TypeStyle.displayS`, kept on one line with a measured scale floor. It stays
  larger than the surrounding body copy without overwhelming the music table.
- Percentages and tally counts use the app's Bricolage `numberM`; tally names use
  `bodyLStrong`. The flight numbers keep the oversized Bricolage treatment, one step under the
  original 96px so the flight shares the canvas with the personal bands and the tally without
  cropping (`theCardFits` measures the worst case).
- Artwork is 84px, `Radius.artwork`, unmodified — no scrim, gradient or overlay.
- Both variants use 72px margins. Story reserves an extra 72px at the bottom for sharing chrome.
- Ear uses `ProportionTrack`; readability uses `StatMeter` with one solid gray track and its
  blue position marker. The distinct meter semantics remain: readability is not a better/worse
  fill.
- The one legend the card allows: in the room's tally, the caller's own name is set in
  `Palette.ultramarine`, every other name in `ink`. No tick, no cross, no colour pair — `docs/16`
  §5 bans green/red for correct/incorrect, and the accent already means "revealed" everywhere
  else on this card.

### Story variant differences
Same content and columns. Story has a 72px bottom reserve; nothing is added.

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

The card contains real display names, real song choices, and — as of `E36-01` — the caller's own
ear and readability, from a private group. Consequences for the implementation:

- It is generated **only** on explicit user action, and **only the caller's own** data is ever
  on it — never another member's readability, ear, or all-time number, at any scope. The card is
  the sharer's account of the night, not a leaderboard export.
- No guesser is ever named. The room tally names who was *guessed*, aggregated to a count; it
  never attributes a guess to the person who made it. A screenshot that says a named friend was
  wrong about something is exactly the kind of thing a recipient can act on outside the circle,
  and the guesser never agreed to that (`tasks/E36-personal-share-card.md`'s open question).
- Never pre-rendered into a cache directory that another app could read, never written outside
  the app's temporary directory, and the temporary file is deleted after the share sheet
  dismisses.
- It contains no user IDs, no invite code, no group ID, and no join link. Someone who receives
  the image cannot use it to enter the group.
- Nothing about a round that is not `scored` is ever renderable. The share entry point does
  not exist in any other phase.

---

## 6. Verification

| Check | How |
|---|---|
| AC-9: renders at both dimensions | Snapshot tests at 1080×1800 and 1080×1920 against golden PNGs |
| Display face present | Snapshot test asserts the numeral glyph is not SF Pro |
| Artwork loaded | Unit test: renderer awaits all image loads before producing output |
| Headline precedence | Unit test over every rule in §2 — the four personal rules and the five group rules, plus precedence-order and non-submitter-falls-through cases |
| Longest name plus 100% | Snapshot with a 24-character display name (`DisplayName.maximumLength`) in the one-line headline and a visible 100% Ear value |
| The no-personal-night fallback | Snapshot with no own card and both rates `nil` — flight and headline remain; personal bands disappear |
| The room tally at its worst case | Snapshot with six distinct guessed names, two of them `DisplayName.maximumLength`, forcing the tally overflow |
| **The card fits.** `ImageRenderer` does not clip a view that overflows its frame — it draws past the canvas and the pixels are gone — so this is measured, not assumed: `ShareCardStack`'s natural height, rendered without the fixed outer frame, must be no taller than the frame `ShareCardView` actually gives it, for every fixture above at both variants | `ShareCardSnapshots.theCardFits` |
| Temp file cleanup | Unit test: file absent after share-sheet completion handler |
| The sheet fits its detent | Snapshot test measures the rendered sheet on an SE against `Layout.shareSheetHeight` |
