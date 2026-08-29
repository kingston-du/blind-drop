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

- [ ] `ShareHeadline.line(for:)` gains a personal precedence **in front of** the existing group
      precedence — see the table below — while staying a pure function of `ResultsDTO`.
- [ ] `ShareCardContent` gains the personal facts as values, derived in its initialiser the way
      `bestEar` already is: your ear/readability, the room's tally on your card, tonight's top 3.
      Nothing new is fetched and no new type reaches `Features/Results/`.
- [ ] **Your two numbers.** Ear as a percentage in the display face. Readability as its fraction
      *and* its band word (`Copy.band`), never as a rank and never beside anybody else's.
- [ ] **The room's read on you.** A descending tally of the names people guessed on the caller's
      card, the caller's own name in ultramarine and every other name in `ink`. No guesser is
      named. No green, no red, no tick, no cross (`docs/16` §5). Zero guesses renders the empty
      line, not an empty band.
- [ ] **Tonight's Ear top 3**, from `tonightTopEar`, ties sharing a rank and never split — which
      means the band must survive four or five rows, not exactly three.
- [ ] **The Best Ear footer is reconciled, not doubled.** Today's `bestEarFooter` is rank 1 of
      exactly this ranking. It does not survive alongside the podium saying the same thing twice.
- [ ] Filmstrip demoted to 132pt artwork; selection and order unchanged; still nothing over the
      artwork, ever.
- [ ] The kicker string changes from `reveal.title` ("Tonight's drop") to a new one, `share.kicker`
      ("Your night"). Both new and changed strings land in `docs/11-COPY-DECK.md` in the same
      commit.
- [ ] **The no-personal-night fallback**: a `nil`-ear, `nil`-readability, no-own-card sharer gets
      the `E30-01` card back — group headline, full-size filmstrip, no empty bands, no "—".
- [ ] Both variants still render at exactly 1080 × 1350 and 1080 × 1920. Story's extra height goes
      into air between bands, not into one hole.
- [ ] Amber still absent from both, on the pixels.
- [ ] **Nothing falls off the edge.** Every band gets a fixed vertical budget expressed via
      `ShareCard.canvas(_:)`, no raw literal in `ShareCardView`. Every text run that can be long
      has an explicit `minimumScaleFactor` floor, above `docs/07`'s "never below 20pt" display-face
      limit where the display face is used, with the measured worst case recorded beside it —
      the `0.4` comment on `heroHeadline` is the model. Long content shrinks or truncates by an
      explicit decision, never by running off the canvas; where a tally or podium genuinely
      cannot fit, it drops a whole item and says so, rather than half-drawing one.
- [ ] Worst-case goldens, both variants: 24-character (`DisplayName.maximumLength`) names
      appearing simultaneously as the headline subject, every podium row, and every name in the
      room tally · a 100% ear beside a 100% podium rate · a four- and five-row podium from ties ·
      a room tally with several distinct names · zero guesses on your card · `nil` ear with a
      real readability and the reverse · the non-submitter fallback · a one-submitter round.
- [ ] `docs/10` §2, §3, §5 and §6 rewritten to describe what ships. `docs/16` §5 gains the
      amendment trail described at the top of this file.
- [ ] Five new headline strings, plus `share.kicker`, `share.ear.label`, `share.read.label`,
      `share.room.title`, `share.tonight.title`, in `Localizable.strings` **and**
      `docs/11-COPY-DECK.md`, same commit (`CLAUDE.md` §6). Sentence case, no exclamation.

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

## Progress

| Slice | Status |
|---|---|
| E36-01 The share card becomes yours | wip |
