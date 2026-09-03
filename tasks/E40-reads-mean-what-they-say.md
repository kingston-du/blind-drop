# E40 — Reads mean what they say

One slice. Four corrections to the pairwise-read maths behind **Insights** and the **profile**'s
"You and them" panel, all landing in `insightsForGroup` and `pairwiseRead`.

None of this is a new score. Every number here is still derived from `guesses` × `submissions` on
read (CLAUDE.md §2.8); what changes is which rounds go in the denominator, which person gets the
credit, how the two mutual lists divide the pairs between them, and whether the query that feeds
all of it actually returns the whole history.

> **Not in scope, deliberately.** `round_scores.readability` and `round_scores.ear` keep
> `docs/02-DOMAIN-RULES.md` §4.3's card attribution: a correct duplicate-track guess still lands
> on the card's owner. That is core scoring, it moves Results, Standings and the share card, and
> it is an owner call rather than a consequence of this slice. The divergence it leaves is stated
> under **E40-01** and in `docs/04-API-CONTRACT.md`.

> **Relationship to `E39`.** `tasks/E39-auto-assigned-guesses.md` proposes the opposite reading of
> a blank sheet — fill every unguessed card at chance, so abstention stops existing. The owner has
> set `E39` aside for now and chosen this reading instead: a round nobody guessed in is **excluded**
> from the pairwise denominators, exactly as `docs/02` §4.1 already excludes it from `ear`. If
> `E39` is ever revived, `E40-01`'s first change becomes unreachable rather than wrong — a filled
> sheet is a guessed round — and the other three stand unaffected.

---

### E40-01 — A read counts the rounds you guessed in, and credits the person you named

**Status:** done
**Deps:** —
**Parallel:** no
**Reads:** `docs/02-DOMAIN-RULES.md` §4.1–§4.3, `docs/04-API-CONTRACT.md` §4
(`/members/{user_id}/profile`, `/insights`), `docs/11-COPY-DECK.md` §Insights,
`server/supabase/migrations/0005_scoring.sql`, `tasks/E25-insights.md`,
`tasks/E28-polish-and-personality.md` (`E28-07`, the Wilson ranking this builds on)
**Touches:** `server/supabase/functions/_shared/insights.ts`,
`server/supabase/functions/_shared/db.ts`, `server/supabase/functions/groups/index.ts`,
`server/supabase/tests/functions/insights.test.ts`,
`server/supabase/tests/functions/standings.test.ts`,
`ios/BlindDrop/Resources/Localizable.strings`, `docs/04-API-CONTRACT.md`,
`docs/11-COPY-DECK.md`
**Verify:** `node server/scripts/lint.mjs`; `cd server && npm run test:functions`;
`cd server && npm run audit:leak`; `./ios/scripts/lint.sh`;
`-only-testing:BlindDropUnitTests -only-testing:BlindDropSnapshotTests`. Simulator: Insights and
a member profile against the fixture server — the two mutual lists, a "Your reads" card and its
leaderboard, and the profile's "You and them" panel.
**Proves:** —

**1. A round only counts if the reader guessed in it.** `possible` was every scored round both
people submitted in, whether or not the reader ever opened the sheet. `0005_scoring.sql` is
emphatic that a zero-guess round is `NULL` and not `0` for `ear` — *"NULL means you sat this one
out"* — and the pairwise number contradicted it: sitting out ten sheets left `ear` untouched while
dividing every "You read best" by ten extra rounds. A round the reader played but skipped *this*
card still counts as a miss, matching `ear`'s own `S − 1` denominator; only the round where they
guessed nothing at all leaves.

**2. Credit follows the name, not the card.** `is_correct` is an existence test on
`(round_id, guessed_user_id, track_key)`, and the aggregation attributed it to `card_owner_id`. So
if Ana and Ben both dropped *Ribs* and you named Ana on Ben's card, you were credited with reading
**Ben** — a person you never named. The direction is now keyed on `guessed_user_id`: that guess
credits Ana, Ben gets nothing, and the round still counts against your denominator for Ben. Credit
is counted as a **set of rounds**, not a row count, so naming Ana correctly on both duplicate cards
is one read rather than two, which is also what keeps `correct ≤ possible`. With no duplicate the
two rules agree exactly, so this is a no-op on every ordinary night.

**3. The two mutual lists partition the pairs.** Recognition needed a correct read in both
directions and misses needed zero in both, so a pair at 0-of-20 and 1-of-20 — the most interesting
miss in the circle — appeared in neither. Recognition keeps its gate, because "they read each
other" is false without it. Misses relaxes to *at least one direction is zero*, so every eligible
pair now lands in exactly one of the two lists, and re-sorts by the Wilson **upper** bound
ascending — `hardestToReadRanked`'s own convention — so a well-supported 0-of-20 outranks a thin
0-of-2 and a one-sided pair sits below the true double-zeroes.

**4. The 1000-row cap.** `max_rows = 1000` in `server/supabase/config.toml` truncates any select
that does not ask for a range, service role included. `insightsForGroup` read the circle's whole
guess feed unbounded and unordered: a six-person circle makes up to 30 guess rows a night, so
past roughly 33 scored rounds the numerators silently stopped growing against denominators that
did not. Insights decayed toward zero as a circle played, and diverged from the profile screen,
whose per-pair query was narrow enough to stay exact.

- [x] `_shared/db.ts` gains `selectAllRows`, a paged reader over PostgREST's `max_rows`. Callers
      supply a stable `.order(…)`; a runaway is an error, never a silent short read.
- [x] The four stats queries page through it, and every `.in("round_id", …)` chunks at `ID_CHUNK`
      — several hundred uuids in a query string is a URL-length bug as well as a row-count one.
- [x] The directed and pairwise maths move out of `groups/index.ts` into `_shared/insights.ts` as
      pure functions. They had no unit coverage because they were inline in a 1700-line handler.
- [x] `insights.test.ts` pins, on the pure functions: a zero-guess round leaving the denominator;
      a skipped card staying in it; duplicate-track credit landing on the named person; two
      correct duplicate namings counting as one round.
- [x] `standings.test.ts` pins the same four end to end, over `scoredRound()`'s fixture — Eli
      assigns nothing there, which is the zero-guess case already sitting in the harness.
- [x] `insights.mutual.misses` and `insights.empty` are restated in `Localizable.strings` **and**
      `docs/11-COPY-DECK.md` in the same commit (CLAUDE.md §6).
- [x] `docs/04-API-CONTRACT.md` §4 restates both denominators, the attribution rule, and the
      divergence from `round_scores` that change 2 deliberately leaves.
- [x] `npm run audit:leak` still passes: nothing here touches an `open` round, and the response
      shape does not change.

**Verified.** `node server/scripts/lint.mjs` clean; `npm run test:functions` 298/298;
`npm run audit:leak` AC-1 satisfied (timing r = 0.0214); `./ios/scripts/lint.sh` clean; iOS unit
480/480; snapshots 92/92 after re-recording all twelve `Insights` goldens. Live on iPhone 17
against the fixture server: Insights (the two mutual lists reading as a matched pair), a "Your
reads" card → its leaderboard → a member profile, and that profile's "You and them" panel.

**The goldens.** Ten of the twelve failed on the two copy changes; the diffs were looked at before
anything was recorded, and confined to the one section label. The other two — `populated` at
`large` on both devices — *passed* while holding the old string: a two-word label at default type
is a smaller fraction of a tall screen than `SnapshotRenderer.tolerance` (0.2%). All twelve were
re-recorded rather than only the ten, so no golden is left asserting text the app no longer has.

**Review.** Two findings, both accepted and fixed. The paginated `round_scores` read ordered on
`round_id` alone, which is not total over a view holding one row per (round_id, user_id) — a page
boundary inside a tied night could drop rows, and a dropped row is indistinguishable from "never
played", understating the exact denominator this slice exists to fix. It now orders on
(round_id, user_id); `profileScores` is filtered to one user and carries a comment saying why it
needs no tiebreaker. Second, the copy-deck note had been inserted mid-table, breaking GFM parsing
for every row after it; it now sits below the table.

**Pre-existing, not fixed here.** `Insights-populated` at `accessibility5` shows two labels
letter-wrapping and colliding — "Ana & Hal" in a mutual row, and "Dee as Gus" in a confusion row.
Both are present unchanged in the pre-`E40-01` goldens and are the shared-row Dynamic Type problem,
not anything this slice touched. Raised separately rather than folded in.
