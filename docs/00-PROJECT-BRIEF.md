# 00 — Project brief

**Version:** 1.0 (MVP) · **Platform:** iOS only · **Audience:** private friend groups, 6–12
people, ages ~16–22.

---

## 1. The product in one breath

Every day your group drops one song each, anonymously, and you find out who's readable and
who surprised you.

Songs go in blind — nobody sees what anyone picked or even *whether* they picked. At 8:00 PM
they're revealed as an anonymous numbered list. Two hours to guess who dropped what. At
10:00 PM the answers, per-person stats, and standings land.

## 2. Why it works

Music taste is identity at this age. Existing apps let you *broadcast* taste; none turn it
into a legible game. The pleasure here is the argument — "no way that was you" — and the
app's only real job is to protect the blind window that makes the argument possible.

The organizing metaphor is a **blind tasting flight**: numbered, unlabeled samples you assess
and then guess at. This justifies the app's single structural device — during the reveal,
songs are genuinely No. 1 through No. N, and the number is information the player uses, not
decoration.

## 3. Goals

- The full daily loop takes each user **under 90 seconds** of active time.
- The 8:00 PM reveal is a synchronized moment the whole group experiences together.
- The integrity of the blind window is guaranteed. **This is the product.**
- The accumulating group playlist ("The Record") becomes more valuable over time.

## 4. Non-goals for v1

Public discovery · feeds · multiple groups per user · in-app audio hosting or a real player ·
streaks, badges, XP, levels, cosmetics · comments or chat (the group already has a group
chat; do not compete with it) · themed prompts · Android · web · iPad-specific layouts.

See `16-OUT-OF-SCOPE.md` for the enforceable list.

## 5. Pilot success criteria

With a real group of 6–12 testers over two weeks:

- ≥70% of members submit on a given day **without** being reminded in their group chat.
- ≥80% of submitters return between 8:00 and 10:00 PM to guess.
- Results get screenshotted into the group chat at least twice in the first week.

The third criterion is why the share card is a first-class surface, not an afterthought.

## 6. Owner-approved amendments to the original PRD

These **supersede** the original PRD text where they conflict. They are already folded into
the rest of `docs/`; this section exists so the divergence is traceable.

| # | Change | Effect |
|---|---|---|
| A1 | **Light mode wins.** One fully realized light theme. No dark mode in v1. | `07-DESIGN-SYSTEM.md` defines a cool near-white base. The original dark palette is void. |
| A2 | **High Spotify compatibility.** Apple Music remains the search/preview engine; every track must also be linkable and exportable to Spotify. | `06-MUSIC-INTEGRATION.md` — ISRC bridging, per-track Spotify links, Spotify playlist export as a first-class feature rather than a nice-to-have. |

Everything else in the original PRD stands.

## 7. The 90-second budget

The loop is timed because it is the product's main constraint. Budget:

| Step | Target |
|---|---|
| Open app, tap **Drop a song** | 3s |
| Search, scan results, tap a track | 25s |
| Confirm screen, tap **Seal it** | 5s + 0.6s seal |
| — later — open at 8:00 PM, read 8 cards | 30s |
| Assign 7 names, tap **Lock in guesses** | 20s |
| — later — read results | 15s |
| **Total active** | **~98s → must be trimmed to <90s** |

Implication: search must return results in under 400ms and the guess sheet must not require
a scroll to see the name pool. Every added tap has to be justified against this table.
