# E25 — Insights

Deeper statistics, kept off the daily path. The Drop → Guess → Answers loop stays exactly as
simple as it is; Insights is somewhere to go afterwards, reached from the menu or a profile.
No tab bar (`docs/16` §3), and nothing here appears on the round screens.

Circle-scoped, like profiles. Cross-circle aggregation is banned by ADR-011.

**Ship this after there is data.** Every statistic here is a ratio, and ratios over a two-week
beta with five rounds are decoration. `E25-01` is worth building when circles have history;
`E25-02` needs more still. Deferring is the right call if the beta has not produced enough.

---

### E25-01 — Who you know, and who knows you

**Status:** todo · **Deps:** E24-02 · **Parallel:** yes — against E26
**Reads:** `docs/02` §4, `docs/16` §3, `docs/11`
**Touches:** `server/supabase/functions/`, a new Insights feature, `Localizable.strings`,
`docs/11-COPY-DECK.md`, tests
**Verify:** `npm run test:functions`; `./ios/scripts/lint.sh`; unit + snapshot; `audit:leak`.
Simulator: a circle with real history and one with almost none.

Who you read best. Who reads you best. Who you cannot read at all. Mutual recognition — the
pairs who see each other, and the pairs who never do, which is the more interesting half.

All of it is `guess_results` aggregated by pair. The engineering is small; the judgement is
where to stop. Every person named drills into their profile.

The thin-data rule from `E24-02` is stricter here, because a superlative is a claim: naming a
"hardest person to read" off three shared rounds is a sentence about a friendship that the data
does not support. Say nothing until it does.

- [ ] Who you know best, who knows you best, hardest to read, mutual recognition
- [ ] Everyone named drills into their profile
- [ ] Superlatives suppressed entirely below a stated threshold, not softened
- [ ] Reached from the menu or a profile; no tab bar, nothing on the round screens
- [ ] Nothing reachable from an unscored round — asserted by the leak audit

---

### E25-02 — Who you get mistaken for

**Status:** todo · **Deps:** E25-01 · **Parallel:** no
**Reads:** `docs/02` §4, `docs/11`
**Touches:** `server/supabase/functions/`, the Insights feature, tests
**Verify:** `npm run test:functions`; `audit:leak`; simulator.

Confusion: whose songs get mistaken for whose. The most genuinely interesting number the game
produces, and the one needing the most history before it says anything — it is a matrix, so it
needs roughly a member-count squared of rounds before a cell means more than one person's one
odd evening.

Defer without hesitation if the data is thin. A confusion statistic that is wrong is worse than
absent, because people believe matrices.

- [ ] Confusion pairs, per circle, from existing guess data
- [ ] A stated minimum before any cell is shown; below it, the surface says so plainly
- [ ] Reads as a curiosity, not a judgement — copy checked against `CLAUDE.md` §6
