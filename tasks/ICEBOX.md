# Icebox

Good ideas that are out of scope. Adding one here is the correct response to having one
(`docs/16-OUT-OF-SCOPE.md` §4).

**Format:** what it is · what it would change · what it would cost the blind window.

Anything in `docs/16` §5 does not belong here — those are spec violations, not deferred
features, and they need the owner.

---

## Seeded from the PRD

### Themed prompts
*"A song that reminds you of summer."* Changes the game's texture from taste-reading to
prompt-answering, which is a different product and needs its own design pass. The nullable
`Round.prompt` column exists; nothing else does. **Blind window cost:** none — a prompt is
public. **`E27-04` is a spike** — decide whether to test it, on evidence from the beta, before
anyone builds a prompt UI. Still frozen until that spike says otherwise.

### ~~Multiple groups per user~~ — promoted 2026-08-17
Now `E18`–`E21`, under ADR-011. The warning that stood here was right and survives into the
ADR: every "which group?" parameter is a new authorization surface, so every group-scoped
route proves membership of that group explicitly.

### Reactions or comments on songs
The group already has a group chat. Do not compete with it. **Blind window cost:** high if
reactions were ever visible before 10:00 PM — a reaction count during the guess window is a
signal about who is looking at what.

### Head-to-head or cross-group play
**Blind window cost:** unclear, which is itself a reason to defer it.

---

## Add new entries below

<!--
### Name
One paragraph: what it is, what it would change, what it would cost the blind window.
Date and the task you were working on when you thought of it.
-->
