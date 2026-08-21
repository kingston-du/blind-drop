# E24 — The leaderboard and profiles

The member list is a list of names. Standings already rank Ear and Readability per circle and
the rows are explicitly not tappable. This epic joins the two: the members of a circle, ranked
by Ear, each one a way into a profile.

**Not gamification.** `docs/16` bans streaks, badges, XP, levels and cosmetics; ranking on a
number the game already computes and already shows is none of those. But Readability is
deliberately not a ladder — being easy to read is not being good — so **Ear ranks, Readability
is shown**. An accent on Readability, or a sort by it, implies a better end where there is not
one.

Profiles are circle-scoped. A person is not the same person in two circles: they play to a
different room, and the numbers only mean anything against the people who produced them.

---

### E24-01 — Best Ear

**Status:** done · **Deps:** E18-01 · **Parallel:** yes — against E20, E21
**Reads:** `docs/02` §4, `docs/08` §9, `docs/11`, `docs/12` §2
**Touches:** `BlindDrop/Features/Settings/GroupScreen.swift`,
`BlindDrop/Features/Results/StandingsView.swift`, `Localizable.strings`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot. Simulator: a circle of 3 and one of 12, at
`accessibility5`.

The circle's member list becomes the all-time Ear leaderboard for that circle. Names open
profiles. Admin and membership controls stay on the screen but stop being what it is about —
this is a thing to look at, and a place to manage members second.

The small-sample problem is real from day one: a circle three rounds old ranked by a percentage
is noise presented as a standing. Show what the number rests on, or hold the ranking until it
means something. Do not print a confident percentage over four data points.

- [x] Members ranked by all-time Ear within the circle
- [x] Readability shown, not ranked, not accented
- [x] Names open profiles; rows are real controls with proper traits
- [x] Thin history handled honestly rather than rounded
- [x] Admin controls present and secondary
- [x] Ties resolved deterministically and identically everywhere

---

### E24-02 — A person, in this circle

**Status:** done · **Deps:** E24-01 · **Parallel:** no
**Reads:** `docs/02` §4, `docs/16` §3, `docs/11`
**Touches:** a new profile feature, `server/supabase/functions/groups/`, `Localizable.strings`,
`docs/08-SCREEN-SPECS.md`, `docs/11-COPY-DECK.md`, tests
**Verify:** `npm run test:functions`; `./ios/scripts/lint.sh`; unit + snapshot; `audit:leak`.
Simulator: own profile and another member's, thin history and long history.
**Proves:** AC-1

Ear, Readability, how many times they have dropped, their recent songs, and **You vs. them** —
how often you read them, how often they read you. The `guesses` table already holds every
(guesser, target, correct) triple; nothing new needs storing.

Two hard limits. **No misleading percentages** — "you have read them 100% of the time" over two
shared rounds is worse than saying nothing, and the fix is showing the denominator or withholding
the figure until it carries weight. And **no social network**: no bio, no followers, no counts of
either, no posts, nothing editable.

Recent songs are past rounds only. A profile must never be a hole in the blind window — check
that a `scored` round's contents are all it can ever reach, and prove it in `audit:leak`.

- [x] Ear, Readability, drop count, recent songs, You vs. them — circle-scoped
- [x] Small samples never rendered as confident percentages
- [x] Own profile and another member's both make sense
- [x] Nothing from an `open` or `revealed` round is reachable — asserted by the leak audit
- [x] No bio, followers, posts, or editable surface

Completed 2026-08-20. The server makes profile fields from scored views only, with an
open-phase golden captured after the named member has sealed a song, and AC-1 passes. The iOS
screen has reviewed regular and accessibility snapshots for both another member with history and
the caller with thin history. The Group snapshot harness was also repaired: it now renders the
actual non-scrolling content instead of ImageRenderer's blank `ScrollView` result, replacing the
44 unrelated stale Group goldens with reviewed views of the real settings screen.
