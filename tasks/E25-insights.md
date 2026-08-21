# E25 — Insights

Deeper statistics, kept off the daily path. The Drop → Guess → Answers loop stays exactly as
simple as it is; Insights is somewhere to go afterwards, reached from the menu or a profile.
No tab bar (`docs/16` §3), and nothing here appears on the round screens.

Circle-scoped, like profiles. Cross-circle aggregation is banned by ADR-011.

**Ship this after there is data.** Every statistic here is a ratio, and ratios over a two-week
beta with five rounds are decoration. `E25-01` has a temporary owner-approved beta exception:
show relationships immediately so testers can exercise the surface, and always show the raw
shared-read denominator next to the percentage. Do not label the page as early data. Revisit the
threshold before public beta; `E25-02` still needs more history.

---

### E25-01 — Who you know, and who knows you

**Status:** done · **Deps:** E24-02 · **Parallel:** yes — against E26
**Reads:** `docs/02` §4, `docs/16` §3, `docs/11`
**Touches:** `server/supabase/functions/`, a new Insights feature, `Localizable.strings`,
`docs/11-COPY-DECK.md`, tests
**Verify:** `npm run test:functions`; `./ios/scripts/lint.sh`; unit + snapshot; `audit:leak`.
Simulator: a circle with real history and one with almost none.

Who you read best. Who reads you best. Who you cannot read at all. Mutual recognition — the
pairs who see each other, and the pairs who never do, which is the more interesting half.

All of it is `guess_results` aggregated by pair. The engineering is small; the judgement is
where to stop. Every person named drills into their profile.

The thin-data rule from `E24-02` is suspended for this tester-facing slice. Results appear after
the first shared scored round, with both the percentage and its raw shared-read denominator. That
makes the small sample unmistakable without adding an early-data label; restore a threshold before
public beta.

- [x] Who you know best, who knows you best, hardest to read, mutual recognition
- [x] Everyone named drills into their profile
- [x] Results appear immediately after a shared scored round, with an explicit raw denominator
- [x] Reached from the root header menu; no tab bar, nothing on the round screens
- [x] Nothing reachable from an unscored round — asserted by the leak audit

> **Completed:** Local Docker/Supabase verification passed: all 267 Edge Function tests, including
> the Insights relationship and open-phase golden tests. The four AC-1 audit suites also pass.

---

### E25-02 — Who you get mistaken for

**Status:** done · **Deps:** E25-01 · **Parallel:** no
**Reads:** `docs/02` §4, `docs/11`
**Touches:** `server/supabase/functions/`, the Insights feature, tests
**Verify:** `npm run test:functions`; `audit:leak`; simulator.

Confusion: whose songs get mistaken for whose. The most genuinely interesting number the game
produces, and the one needing the most history before it says anything — it is a matrix, so it
needs roughly a member-count squared of rounds before a cell means more than one person's one
odd evening.

Defer without hesitation if the data is thin. A confusion statistic that is wrong is worse than
absent, because people believe matrices.

- [x] Confusion pairs, per circle, from existing guess data
- [x] A stated minimum before any cell is shown; below it, the surface says so plainly
- [x] Reads as a curiosity, not a judgement — copy checked against `CLAUDE.md` §6

> **Completed:** The circle must have active-member-count squared scored rounds before any
> confusion pair appears; the response carries its progress throughout. The server keeps the
> three most repeated wrong actual-owner → guessed-member pairs, excluding correct duplicate-track
> reads and former members. Focused server suites, the four-part leak audit, iOS lint, Insights
> unit/snapshot tests, and the fixture-backed iPhone 17 route to a member profile all pass.
