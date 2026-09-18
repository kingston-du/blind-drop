# Icebox

Good ideas that are out of scope. Adding one here is the correct response to having one
(`docs/16-OUT-OF-SCOPE.md` §4).

**Format:** what it is · what it would change · what it would cost the blind window.

Anything in `docs/16` §5 does not belong here — those are spec violations, not deferred
features, and they need the owner.

---

## Seeded from the PRD

### ~~Themed prompts~~ — promoted 2026-08-27, as "cues"
Now `docs/18-CUES.md`, built under `E35`. The warning that stood here — a prompt changes the
game's texture and needs its own design pass — was answered by that design pass rather than
dropped: a fixed, seeded catalog, deterministic per-circle assignment, no admin authoring, off
switch in circle settings.

### ~~Multiple groups per user~~ — promoted 2026-08-17
Now `E18`–`E21`, under ADR-011. The warning that stood here was right and survives into the
ADR: every "which group?" parameter is a new authorization surface, so every group-scoped
route proves membership of that group explicitly.

### ~~Reactions~~ — promoted 2026-09-17 · comments still iced
Reactions are now `docs/19-REACTIONS.md`, built under `E46`. The warning that stood here was the
right one and it was answered rather than dropped: **a reaction count during the guess window is
a signal about who is looking at what**, so there is no count during the guess window. A mark is
placed blind at the reveal and the room resolves at 22:00, exactly like a guess. Counts are
anonymous, there is no push, and nothing reaches a score.

**Comments are not promoted.** Free text on a song is still out — that half of the original
entry, and `docs/16` §1's row, stand unchanged. The group already has a group chat.

### Head-to-head or cross-group play
**Blind window cost:** unclear, which is itself a reason to defer it.

---

## From `E27` spikes

### Streaks — declined, `E27-05`
Two shapes, assessed separately. **Player streaks** ("dropped N days running") are the literal
target of `CLAUDE.md` §2.7's ban and reverse a design choice already made — `docs/02` §4.1
deliberately excludes a zero-guess round from `ear` instead of scoring it as a loss, and a
streak's whole premise is scoring the lapse. It also punishes multi-circle members precisely for
having several circles, the opposite of what `E18`–`E21` were built to support. Not worth
revisiting. **Circle streaks** ("the circle completed N rounds running") are the more defensible
shape — a derived, group-level fact closer to the minimum-submitters mechanic than to a badge —
but a visible reset is still the dreaded screen the ban defends against, just retargeted at a
group instead of a person, and `CLAUDE.md` §2.7's text bans "streaks" without a group-level
carve-out. **Blind window cost:** none directly — a streak count doesn't leak anything about
who submitted what — but it is still a `CLAUDE.md` §2.7 rule change, not a blind-window
question, and needs the owner's explicit amendment before anyone builds it (same pattern as
`E17-05`/`E17-07`). If revisited, the circle-streak shape rendered as a plain spectrum-style
fact (no break animation) is the version worth discussing, not the player-facing one.

---

## Add new entries below

<!--
### Name
One paragraph: what it is, what it would change, what it would cost the blind window.
Date and the task you were working on when you thought of it.
-->
