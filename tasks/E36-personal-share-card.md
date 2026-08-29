# E36 — The share card becomes yours

One slice, from an owner request of 2026-08-28. The `E30-01` redesign made the card *look* like
something worth posting; it did not change what the card knows. It still says one group-level
sentence and shows four pieces of artwork, which is exactly what anybody in the circle could
screenshot from the Results screen.

This gives the card the one thing the Results screen has and the artifact doesn't: **the data
only you can see**. Your ear, your readability, and what the room actually guessed for your card
— plus tonight's Ear top 3, so the sentence has a table behind it.

It also carries a layout mandate that is not decoration: **nothing may be cut off, in any shape,
on any night**. `ImageRenderer` does not clip — it draws past the canvas and the pixels are
simply gone — so an overflowing card does not look broken, it looks *edited*. The fit work below
exists to make that impossible rather than unlikely.

---

## What this changes about the product, and why it needs the owner

`docs/10` §2 has said since the beginning: **no scores for anybody who is not the headline.** The
card was a *group artifact* — "it works because it looks like something the group made, not like
an ad". Two of the three additions below break that rule as written, so it is amended here rather
than worked around.

> **Owner amendment (2026-08-28), same footing as ADR-011 and `E31`'s cap change.**
>
> The share card stops being a purely group artifact and becomes **the sharer's account of the
> night**. `docs/10` §2's "no scores for anyone but the headline" is replaced by a closed list.
> The card may carry:
>
> 1. **The caller's own numbers** — ear rate and fraction, readability rate, fraction and band.
> 2. **What the room guessed for the caller's own card**, aggregated as a tally of the names
>    people *named*, never attributed to the people who named them.
> 3. **Tonight's Ear top 3** — the same round-scoped ranking `E29-01` already renders in-app
>    (`TonightTopEarView`), with the same ties-share-a-rank shape.
>
> And nothing else. Specifically still banned, and not softened by this amendment:
>
> - **Anyone else's readability, at any scope.** `docs/02` §4.5 and `docs/16` §5's "Ranking
>   readability" are untouched. There is no readability podium and there never will be. Your own
>   readability is on the card because it is *yours*.
> - **Any all-time number for anybody**, including the caller. The card is about one night.
> - **Naming a guesser.** "Maya thought you were Cal" does not go on an image that leaves the
>   circle; "Cal ×3" does. See the open question below for the reasoning and the alternative.
> - Everything on `docs/10` §2's "What is not" list: no QR code, no install link, no store badge,
>   no avatars, no user IDs, no invite code, no group ID, nothing laid over artwork.
>
> `docs/10` §2 and §5 are rewritten in the same commit that ships this, and `docs/16` §5's list
> gets a line recording that the "no scores for anyone but the headline" bullet was amended here
> — not deleted, amended, so the next agent finds the trail.

**Not a gamification change.** `CLAUDE.md` §2.7 bans streaks, badges, XP, levels and cosmetics.
A single night's Ear ranking is none of those, it is derived from `guesses × submissions` on read
(§2.8), and it already ships on the Results screen. Nothing here persists a score, awards a thing,
or rewards showing up.

**No server work.** Every field is already on the wire and already decoded:
`ResultsDTO.me` (`PersonalScoreDTO` — ear, readability, and both fractions),
`ResultsDTO.tonightTopEar` (`[TonightEarDTO]`, ranked), and `ResultCardDTO.guesses`
(`[CardGuessDTO]`, non-`nil` on exactly one card: the caller's own — that `nil`-ness *is* how the
caller's card is identified, the same trick `ResultsScreen`'s `GuessedYouDisclosure` already
plays). `ReadabilityBand(readability:)` derives the band client-side.

---

## Open questions

> **Open question — do we name the guesser?**
> `CardGuessDTO` carries `guesserName`, and "Maya thought you were Cal" is unquestionably the
> funnier line. It is not on the card, for two reasons. First, it publishes a named person's wrong
> answer outside the circle, on an artifact whose whole privacy story (`docs/10` §5) is that it
> contains nothing a recipient can act on — a screenshot that says a named friend was wrong is
> something a recipient *can* act on. Second, it is the caller who decides to send it, and the
> named person never gets asked. The tally form keeps the joke ("three people thought I was Cal")
> and drops the accusation. Recorded as the interpretation most protective of the people who are
> not doing the sharing, per `CLAUDE.md` §1. **The owner may reverse this**; if so it is a one-line
> change plus a `docs/10` §5 rewrite, and the goldens for the long-name worst case get
> considerably tighter.

> **Open question — top 3 of what?**
> "A top 3 for the night" has exactly one honest reading in this product: **Ear**, because it is
> the only per-round ranking that exists and the only one `docs/02` §4.5 permits. There is no
> "best song" — no votes, no reactions, no ratings (`docs/16` §1 bans reactions outright), so a
> song podium would have to invent a metric, and an invented metric on the artifact that leaves
> the device is the worst place in the app to invent one. Tonight's Ear top 3 it is. If the owner
> wants a *song* top 3, that is a new feature with a new data model, not a share-card slice.

---

## The card this slice is aiming at

Square-tall, 1080 × 1350. Bands, top to bottom, each with a fixed vertical budget:

```
  ┌────────────────────────────────────┐
  │  THE COVE            10 AUGUST     │  masthead — unchanged
  │                                    │
  │  YOUR NIGHT                        │  kicker (was "Tonight's drop")
  │  Nobody got                        │  displayXL — still the hero, still ≤ 2 lines
  │  you                               │
  │                                    │
  │  EAR        READ                   │  your two numbers, labels at `label`
  │  71%        4 of 7 · Legible       │  ear in the display face; band in words
  │                                    │
  │  THE ROOM THOUGHT YOU WERE         │  the private payload
  │  Cal ×3 · Maya ×2 · Kingston ×2    │  descending; your own name in ultramarine
  │                                    │
  │  TONIGHT'S EAR                     │
  │  1 Cal 100% · 2 Maya 71% · 3 Gus…  │  top 3, ties share a rank
  │                                    │
  │  ▓▓  ▓▓  ▓▓  ▓▓   + 4 more         │  filmstrip, demoted
  │                                    │
  │  Blind Drop                        │
  └────────────────────────────────────┘
```

**The accent carries the correctness, not a word and never a colour pair.** In "the room thought
you were", the caller's own name is set in ultramarine and every other name in `ink`. That is the
whole legend — the people in that bucket got it right. `docs/16` §5's green/red ban is why there
is no other way to say it, and the ban is a good one: the accent already means "revealed, live"
everywhere else on this card.

**Amber must still not appear anywhere** (`docs/10` §3, asserted on the pixels by
`ShareCardSnapshots.nothingOnTheCardIsAmber`). Nothing on a scored round is sealed.

**Something has to give, and it is the filmstrip.** Five content bands do not fit under a 56pt
hero at the current 180px artwork. The filmstrip shrinks (to 132pt, four across, order and
selection unchanged — still the first four by `card_no`, still no title, owner or numeral on or
near it) and keeps its overflow caption. It is texture now, and the personal bands are the reason
to look.

**When there is no personal night, the card is today's card.** A member who did not submit has a
`nil` ear, a `nil` readability and no card of their own, so the personal bands have nothing true
to say. They collapse, the headline falls back to `ShareHeadline`'s existing group precedence, and
the filmstrip returns to its full `E30-01` size. This is not a special case bolted on — it is why
the `E30-01` layout is kept rather than replaced.

---

### E36-01 — The share card becomes yours

**Status:** wip
**Deps:** —
**Parallel:** yes
**Reads:** this file, `docs/10-SHARE-CARD-SPEC.md`, `docs/11-COPY-DECK.md`,
`docs/02-DOMAIN-RULES.md` §4.4–4.5, `docs/07-DESIGN-SYSTEM.md`, `docs/16-OUT-OF-SCOPE.md` §5,
`tasks/E30-share-card-redesign.md`
**Touches:** `ios/BlindDrop/Features/Results/Share/ShareHeadline.swift`,
`ios/BlindDrop/Features/Results/Share/ShareCardView.swift`,
`ios/BlindDrop/DesignSystem/ShareCard.swift`, `ios/BlindDrop/Resources/Localizable.strings`,
`docs/10-SHARE-CARD-SPEC.md`, `docs/11-COPY-DECK.md`, `docs/16-OUT-OF-SCOPE.md`,
`ios/BlindDropTests/Unit/ShareHeadlineTests.swift`,
`ios/BlindDropTests/Snapshot/ShareCardSnapshotTests.swift`,
`ios/BlindDropTests/Unit/ShareRendererTests.swift`
**Verify:** `-only-testing:BlindDropSnapshotTests/ShareCardSnapshots -only-testing:BlindDropUnitTests/ShareRendererTests -only-testing:BlindDropUnitTests/ShareHeadlineTests`
(the suite is `ShareCardSnapshots`, **not** `ShareCardSnapshotTests` — the stale name matches zero
tests and reports a false green); `./ios/scripts/lint.sh`. Simulator: open the share sheet from a
scored round and screenshot the live preview, both variants rendered.
**Proves:** AC-9

- [x] `ShareHeadline.line(for:)` gains a personal precedence **in front of** the existing group
      precedence — see the table below — while staying a pure function of `ResultsDTO`.
- [x] `ShareCardContent` gains the personal facts as values, derived in its initialiser the way
      `bestEar` used to be: your ear/readability, the room's tally on your card, tonight's top 3.
      Nothing new is fetched and no new type reaches `Features/Results/`.
- [x] **Your two numbers.** Ear as a percentage, readability as its fraction *and* its band word
      (`Copy.band`), never as a rank and never beside anybody else's. Neither is set from a
      literal size — see the closing notes on why the display face itself dropped out entirely.
- [x] **The room's read on you.** A descending tally of the names people guessed on the caller's
      card, the caller's own name in ultramarine and every other name in `ink`. No guesser is
      named. No green, no red, no tick, no cross (`docs/16` §5). Zero guesses renders the empty
      line, not an empty band.
- [x] **Tonight's Ear top 3**, from `tonightTopEar`. Capped at `ShareCard.maximumPodiumRows` (3)
      for this fixed-height artifact, with the same "+N more" overflow shape the filmstrip
      already uses — see the closing notes for why a boundary tie can now lose rows to that
      caption, and why that is not the same thing as the server splitting the tie.
- [x] **The Best Ear footer is reconciled, not doubled.** The old `bestEarFooter` is gone; the
      podium's rank 1 says what it used to say.
- [x] Filmstrip **not** demoted — dropped entirely on a personal night, full `E30-01` size
      unchanged on the fallback. See the closing notes: a demoted-but-present filmstrip was the
      original plan and did not survive contact with `ShareCardFitTests`.
- [x] The kicker string changes from `reveal.title` ("Tonight's drop") to a new one, `share.kicker`
      ("Your night"), on a personal night; `reveal.title` is reused unchanged on the fallback.
- [x] **The no-personal-night fallback**: a `nil`-ear, `nil`-readability, no-own-card sharer gets
      the `E30-01` card back — group headline, full-size filmstrip, podium, no empty bands, no "—".
- [x] Both variants still render at exactly 1080 × 1350 and 1080 × 1920. Story's extra height goes
      into air between bands, not into one hole.
- [x] Amber still absent from both, on the pixels.
- [x] **Nothing falls off the edge.** Every band's `Spacer` is a named `ShareCard` constant
      (`stackGap`, new — one step tighter than `rowGap` below the hero, `docs/10` §3 explains
      why); no raw literal in `ShareCardView`. Every text run that can be long has an explicit
      `minimumScaleFactor` floor. Long content shrinks or truncates by an explicit decision,
      never by running off the canvas; the tally and the podium each drop a whole item to their
      own overflow caption rather than half-drawing one. `ShareCardFitTests`
      (`ShareCardSnapshots.theCardFits`) proves the fit by measurement, not by inspection.
- [x] Worst-case goldens, both variants: `Share-*-longestname` (24-character name as both the
      headline subject and tonight's Ear leader, in headline **and** podium at once) ·
      `Share-*-personalstress` (six distinct room-tally names past the cap, two of them
      24-character, forcing its overflow; a six-way podium tie past its own cap, two more long
      names, forcing that overflow too) · `Share-*-nonsubmitter` (the fallback, `nil` ear,
      `nil` readability, no own card). A one-submitter round and a zero-eligible own card are
      covered at the `ShareHeadline` level (`aSoloRoundReachesNeitherPersonalCardRule`), which is
      where that edge actually lives — the headline, not the layout.
- [x] `docs/10` §2, §3, §5 and §6 rewritten to describe what ships. `docs/16` §5 gains the
      amendment trail described at the top of this file.
- [x] Nine new/changed strings — four headline rules, `share.kicker`, `share.ear.label`,
      `share.read.label`, `share.read.fraction`, `share.room.title`, `share.room.tally.multiple`,
      `share.room.tally.single`, `share.tonight.title` — in `Localizable.strings` **and**
      `docs/11-COPY-DECK.md`, same commit (`CLAUDE.md` §6). `share.bestear.label` retired, noted
      rather than silently deleted. Sentence case, no exclamation.

**Headline precedence table** (rules 1–4 new, in front; 5–9 are today's five group rules,
unchanged):

| # | Condition | Line |
|---|---|---|
| 1 | The caller's own card (`guesses != nil`): `correctGuessCount == 0`, ≥ 1 eligible guesser | *"Nobody got you"* |
| 2 | The caller's own card: `correctGuessCount == eligibleGuesserCount`, ≥ 1 eligible | *"Everybody got you"* |
| 3 | `me.ear == 1`, with `earPossible ?? 0 > 0` | *"You read the whole room"* |
| 4 | `ReadabilityBand(readability: me.readability) == .unreadable` | *"You were unreadable"* |
| 5–9 | *(existing group rules, unchanged — see `docs/10` §2 as it stood before this slice)* | |

Rule 4 is **stricter than its group counterpart**, deliberately. Group rule (old #4) names the
literal least-readable person whatever their rate — an owner decision recorded in
`tasks/E12-results-and-share.md`, and it stands unchanged for that rule. The new personal rule
fires only inside the `unreadable` band, because *"You were unreadable"* on a 71% night is a false
claim the sharer would be publishing about themselves.

---

## Closing notes

**The plan's layout math was wrong, and the fit test is what caught it.** The original sketch
kept the filmstrip on every card, demoted to `canvas(132)` artwork, and gave the podium up to
five rows as one joined sentence ("1 Cal 100% · 2 Ana 71% · ..."). Both looked reasonable on
paper and neither survived `ShareCardStack` actually being measured: the joined podium line
routinely needed two lines at the card's content width (a name, a rank and a rate is a wide
string, and four of them joined is wider than the 312pt square-tall content width almost every
night), and a demoted-but-present filmstrip plus five new bands still overflowed the 402pt
content height even *before* any worst-case name was involved — the base `tonight` fixture alone
measured 483pt against 402pt available on the first real run. Four changes, each verified by
re-running `theCardFits` rather than by re-deriving the arithmetic, closed the gap:

1. The podium became a **compact per-person row** (rank, name, rate on one short line each,
   `TypeStyle.bodyS`) instead of one joined sentence — the layout `TonightTopEarView` already
   uses in-app, just smaller. Four short rows fit more reliably than one wide line wrapping twice.
2. **Your two numbers collapsed from two labeled columns into one inline row** — "Ear 71% Read 4
   of 7 Legible" — dropping a whole label row's height for a legibility cost the goldens show is
   small.
3. **The filmstrip stopped being demoted and started being conditional.** It draws at full
   `E30-01` size on the no-personal-night fallback and not at all once the personal bands have
   something to show — there was never a version of "smaller but still present" that both fit
   and looked like more than a smear of colour under everything else.
4. A new `ShareCard.stackGap` (8pt) — one step under `rowGap` (12pt) — replaced `rowGap`/
   `blockGap` for the seams **below the hero headline** specifically, once the podium started
   appearing on every card rather than only the group fallback's old, smaller footer.

**The podium's cap can now split a tie, and that is a considered trade, not an oversight.**
`docs/02` §4.5's "never split a tie" governs how the **server** computes `tonight_top_ear` —
`ResultsDTO.tonightTopEar`'s own doc comment already says a boundary tie can produce more than
three rows there. `ShareCard.maximumPodiumRows` (3) is a **display** cap on a fixed-height
artifact, the same kind of cap the filmstrip has always had on its four cards. A four-way tie at
rank 3 now shows the first three and folds the rest into "+N more" — the same shape as everything
else this card cuts off with an explicit caption rather than a silent crop. Recorded here because
it is a real, visible product effect (`Share-squareTall-personalstress` shows it), not because it
is hidden.

**The card's last literal type size is gone.** `ShareCard.Variant.numberSize` (the old standalone
Best Ear rate's 96pt/112pt Bricolage literal, `docs/07`'s two-literal exception) had no production
caller left once the podium replaced that footer with a `TypeStyle.bodyS` row, so it was deleted
rather than left as dead code. `ShareCardSnapshots.theNumeralsAreNotTheSystemFace` no longer
borrows a card literal for its display-face check; it uses an arbitrary test-only size, since the
check was always about *which face*, not *which size*.

**Verified.** `-only-testing:BlindDropSnapshotTests/ShareCardSnapshots
-only-testing:BlindDropUnitTests/ShareRendererTests -only-testing:BlindDropUnitTests/ShareHeadlineTests`
— 42 tests, all passing (10 snapshot, 20 headline unit including 10 new for the personal rules
and precedence, 12 renderer). `./ios/scripts/lint.sh` clean. Goldens re-recorded and visually
reviewed: the base night, the longest-name worst case, the personal-bands worst case, and the
non-submitter fallback, at both variants, plus both share-sheet device goldens (the sheet's
preview draws the live card). **Not run**: the full `BlindDropUnitTests`/`BlindDropSnapshotTests`
suites end to end — this slice's `Touches` list is confined to the share card, and a whole-suite
run was started twice as a broader sanity check but superseded by further edits both times before
it finished; nothing outside `Features/Results/Share`, `DesignSystem/ShareCard.swift`, the
headline/copy files, and their own tests was touched, so the risk of an unrelated regression is
low but not exercised here. Simulator pass **not performed** — no interactive simulator session
was available in this environment; the goldens above are the actual rendered pixels reviewed in
place of it, which is a real but different form of verification than tapping through the share
sheet on a booted device.

---

## Progress

| Slice | Status |
|---|---|
| E36-01 The share card becomes yours | done |
