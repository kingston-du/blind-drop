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
underneath it. `E36-01` then made the card the **sharer's account of the night** rather than a
purely group artifact — their own ear and readability, what the room guessed for their own card,
and tonight's Ear top 3 — replacing this section's old "no scores for anyone but the headline"
rule with the closed list below (owner amendment, `tasks/E36-personal-share-card.md`). Nothing from `E30-01`'s hierarchy changed: the headline is still
the hero, the filmstrip is still texture, nothing is ever laid over artwork.

**The card has two shapes, chosen by whether the caller has a night of their own to report** —
`ShareHeadline.ownCard(in:)` finds it, or doesn't:

```
  ┌────────────────────────────────────┐   Personal — the caller submitted a card
  │                                    │
  │  THE COVE            10 AUGUST     │   masthead: displayS + label
  │                                    │
  │  YOUR NIGHT                        │   label, inkDim, letterspaced — the kicker
  │  Nobody got                        │   displayXL, ink — the card's hero
  │  you                               │
  │                                    │
  │  EAR 71%      READ 4 of 7 Legible  │   one row: your two numbers
  │                                    │
  │  THE ROOM THOUGHT YOU WERE         │   label, inkDim
  │  Cal ×3 · Maya ×2 · Kingston ×2    │   a tally, caller's own name in ultramarine
  │                                    │
  │  TONIGHT'S EAR                     │   label, inkDim
  │  1  Cal      100%                  │   up to 3 compact rows, ties never split within them
  │  2  Ana       71%                  │
  │  3  Fay       57%                  │
  │                                    │
  │  Blind Drop                        │   label, inkDim, bottom-left
  └────────────────────────────────────┘

  ┌────────────────────────────────────┐   Fallback — no card of the caller's own
  │                                    │
  │  THE COVE            10 AUGUST     │
  │                                    │
  │  TONIGHT'S DROP                    │   the old kicker (`reveal.title`), unchanged
  │  Cal read the                      │
  │  whole room                        │
  │                                    │
  │  TONIGHT'S EAR                     │   the podium replaces the old standalone
  │  1  Cal      100%                  │   Best Ear footer — that line was always
  │  2  Ana       71%                  │   rank 1 of this same ranking, said twice
  │  3  Fay       57%                  │
  │                                    │
  │  ▓▓▓▓  ▓▓▓▓  ▓▓▓▓  ▓▓▓▓            │   the filmstrip, full `E30-01` size —
  │  + 4 more                          │   drawn only on this fallback card
  │                                    │
  │  Blind Drop                        │
  └────────────────────────────────────┘
```

Both shapes come from the same `ShareCardView`; `content.hasPersonalNight` picks the branch.
A fixed 1080×1350 canvas does not have room for the filmstrip **and** the personal bands at
once — measured by `ShareCardFitTests`, not assumed — so the filmstrip is the thing that gives:
present at full size on the fallback, entirely absent once the personal bands have something to
show instead.

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

**Always:** group name · date · the headline, as the card's one hero element · tonight's Ear top
3, ties sharing a rank up to `ShareCard.maximumPodiumRows` · the wordmark.

**On a personal night** (`content.hasPersonalNight`): a "Your night" kicker in place of "Tonight's
drop" · the caller's own ear (a percentage) and readability (a fraction and a band word, never a
rank) · a tally of who the room guessed for the caller's own card, the caller's own name in
ultramarine and everybody else in `ink` — the one legend this card needs, `docs/16` §5's
green/red ban being why there's no other way to say it.

**On the fallback** (no personal night): up to 4 pieces of bare artwork (no title, no owner, no
number) and an overflow count, in place of the personal bands.

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

**Also gone as of `E30-01`, on purpose, and still true:** song titles, owner names, and the row
number that used to sit beside each piece of artwork, on the fallback card's filmstrip. Anyone who
wants the per-song detail already has the full Results screen; this artifact's job is to make
somebody want to open it.

### Artwork shown

The first 4 cards by `card_no`, not by any interest ranking, on the fallback card. Numbering is
the game's spine, which is exactly why the filmstrip keeps the order even though it no longer
prints the numeral — resorting it for the share card would misrepresent the night.

### Tonight's Ear top 3

The same round-scoped ranking `TonightTopEarView` already renders in-app (`E29-01`), capped to
`ShareCard.maximumPodiumRows` for this fixed-height artifact — **not** the same thing as the
server's own "never split a tie" rule, which governs how `ResultsDTO.tonightTopEar` is computed,
not how much of it a given surface chooses to draw. A tie wide enough to push past the cap loses
its overflow rows to a `share.overflow` caption, the same trade the filmstrip already makes with
its own four-row cap. There is no readability counterpart, here or anywhere (`docs/02` §4.5).

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
- Every number below the headline is a `TypeStyle` token, not a literal — `E36-01` retired the
  card's one literal-size exception (the old standalone Best Ear rate) along with the footer it
  lived on; the podium's own rate is `bodyS`, the same as its rank and its name.
- Filmstrip artwork at 180pt, `Radius.artwork`, unmodified — no scrim, no gradient, no rounding
  beyond the token — on the no-personal-night fallback card, the only one that still draws it.
  Bigger than the pre-`E30-01` 96pt thumbnail, which was the "bigger, bolder album art" half of
  that redesign's brief; sized to the **story** variant's narrower content width, the binding
  constraint for fitting four across in either shape.
- Generous margins: 72pt square-tall, 96pt story with an extra 240pt of bottom safe space so
  the Instagram UI does not cover the wordmark. Below the hero headline, the gap between
  vertically stacked bands (`ShareCard.stackGap`, 8pt) is one step tighter than the gap
  everywhere else on the card (`ShareCard.rowGap`, 12pt) — the room `E36-01`'s extra bands
  needed, found and measured by `ShareCardFitTests` rather than assumed.
- Nothing is ever laid over artwork — no caption, no number, no gradient. The filmstrip's
  overflow count sits in its own line below the pictures, never on them.
- The one legend the card allows: in the room's tally, the caller's own name is set in
  `Palette.ultramarine`, every other name in `ink`. No tick, no cross, no colour pair — `docs/16`
  §5 bans green/red for correct/incorrect, and the accent already means "revealed" everywhere
  else on this card.

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
| AC-9: renders at both dimensions | Snapshot tests at 1080×1350 and 1080×1920 against golden PNGs |
| Display face present | Snapshot test asserts the numeral glyph is not SF Pro |
| Artwork loaded | Unit test: renderer awaits all image loads before producing output |
| Headline precedence | Unit test over every rule in §2 — the four personal rules and the five group rules, plus precedence-order and non-submitter-falls-through cases |
| Longest name, in the headline and the podium at once | Snapshot with a 24-character display name (`DisplayName.maximumLength`) as both the headline subject and tonight's Ear leader |
| The no-personal-night fallback | Snapshot with no own card and both rates `nil` — the `E30-01` shape, unchanged |
| The room tally and the podium at their own worst case | Snapshot with six distinct guessed names (two of them `DisplayName.maximumLength`, forcing the tally's own overflow) and a six-way podium tie (two more long names, forcing the podium's) |
| **The card fits.** `ImageRenderer` does not clip a view that overflows its frame — it draws past the canvas and the pixels are gone — so this is measured, not assumed: `ShareCardStack`'s natural height, rendered without the fixed outer frame, must be no taller than the frame `ShareCardView` actually gives it, for every fixture above at both variants | `ShareCardSnapshots.theCardFits` |
| Temp file cleanup | Unit test: file absent after share-sheet completion handler |
| The sheet fits its detent | Snapshot test measures the rendered sheet on an SE against `Layout.shareSheetHeight` |
