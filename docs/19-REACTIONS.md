# 19 — Reactions

> **Owner amendment, 2026-09-17.** `docs/16-OUT-OF-SCOPE.md` §1's "Reactions or comments on
> songs" row and `tasks/ICEBOX.md`'s entry of the same name are **superseded by this file**, on
> the same footing as ADR-011 and the cues promotion. The ban is lifted for the shape described
> here and for nothing wider. The ICEBOX's objection — *"high cost if reactions were ever visible
> before 10:00 PM"* — is not waived. It is answered in §3, and §3 is the load-bearing section of
> this document.

---

## 1. What ships, in one sentence

Every card can be marked **Loved it**, **Interesting** or **Not for me**, one mark per person per
card, placed from the moment of the reveal — and **no one sees a count until the answers are
out.**

---

## 2. Rule interactions

| Rule | What this feature does about it |
|---|---|
| `CLAUDE.md` §2.1 — **no leak during `open`** | Untouched. There are no cards during `open`, so there is nothing to react to and no new key in the `open` payload. `audit:leak`'s golden key set is unchanged. |
| The blind window generally | §3. Aggregates do not exist before `scores_at`. A reaction you place is your own data and comes back to you; nobody else's does, by any route, at any URL, until the round is `scored`. |
| `CLAUDE.md` §2.6 — **closed set of push kinds** | No notification. *"Ben loved your song"* would be both a seventh kind and a push about another member's activity — two violations in one line. Reactions are something you find, never something that pages you. |
| `CLAUDE.md` §2.7 — **no gamification** | Reactions are a per-round fact, like `tonight_top_ear`. They never enter ear, readability, standings, profiles, insights, the share card or any all-time total. There is no "most loved" module in this version (§8). |
| `CLAUDE.md` §2.8 — **scores are derived** | Counts are derived on read from the `reactions` rows. No stored tally, no counter column. |
| `CLAUDE.md` §2.5 — **two accents, semantic only** | No new accent and no carve-out. Both screens that carry reactions are already ultramarine; an unset mark is `inkDim`, and your own selection fills with the screen's existing accent. This is **not** a fourth exception to §2.5 and must not be cited as one. |
| `docs/16` §5 — **no green/red** | The negative mark is never red. All three marks are the same colour as each other. |
| `docs/11` §Voice — **no emoji in app copy** | Upheld. These are monochrome marks in the app's own ink, not emoji. A colour emoji set was considered and declined: it breaks this rule and drops unmanaged colour into a two-accent palette. |
| `docs/02` §3.3 — **only submitters may guess** | Does not extend here. §4. |

---

## 3. The seal — what is visible, and when

This is the whole design, and it is one sentence: **a reaction behaves exactly like a guess.**

| Phase | You may place | You can see |
|---|---|---|
| `open` | nothing — there are no cards | nothing; the payload is unchanged |
| `revealed` | yes, on any card including your own | **your own marks only** |
| `scored` (current round) | yes | your own mark, and the count per kind on every card |
| `scored` (any past round, via The Record) | no — read-only | the counts that night ended with |
| `voided` | nothing | nothing |

Three consequences, each of which a test has to hold:

1. **No route returns another member's reaction, or any count of reactions, while a round is
   `revealed`.** Not filtered in the client — absent from the response. The write route returns
   the caller's own marks and nothing else, in every phase.
2. **The write route's work does not vary with how many others have reacted.** It is an upsert of
   one row plus a read of the caller's own rows. Nothing scans the round's reactions until
   `scored`, so there is no timing channel to measure.
3. **Reactions close with the round.** A night from three weeks ago does not accumulate new
   hearts. The unit of this game is an evening, and a reaction is part of that evening.

Why place at the reveal at all, when the counts only appear later? Because the reveal is when
people are actually *listening* — the previews play there, one card at a time, and asking someone
to come back two hours later to say what they thought of a song they heard at 20:05 is asking for
a thing that will not happen. The placing and the resolving are separated on purpose. The app
already does this once tonight; it is the same move.

---

## 4. Who may react

**Any member of the circle who could see the reveal** — `joined_at < reveals_at` — including a
member who did not drop a song.

This deliberately does not follow `docs/02` §3.3. That rule protects the *game*: guessing is
scored, so a non-submitter guessing would be scoring without staking anything. A reaction is
scored by nothing. And the reveal screen currently tells a non-submitter, correctly and rather
coldly, that they are sitting this one out; one honest thing to do with the songs is an
improvement on nothing to do at all.

**You may react to your own card — at the answers.** *(Owner, 2026-09-17.)* The symmetry with
guessing breaks here on purpose: a guess on your own card is cheating, and a mark on your own drop
is a person saying what they think of their own song, which is the same thing they did by dropping
it. The server permits it in both writable phases and there is no not-self constraint.

The *reveal* gives it no control, though. The quick pass skips your own card, for the reason
`E41-01` gave and this feature does not overturn: the run is the cards you have work on, and a
stop that exists to offer an optional mark is a tap charged to every member every night on the one
screen whose whole argument is that taps are scarce. So during `revealed` your card is the card it
was — *Yours*, in `amberText`, and nothing to do. The marks reach it two hours later, on the
results screen, where the control already exists for every other card and costs nothing to extend
to one more.

No member may hold two marks on one card. Changing your mind replaces; tapping your own mark
again clears it.

---

## 5. The vocabulary — three kinds, closed

| Kind | Copy | Mark |
|---|---|---|
| `loved` | **Loved it** | `heart.fill` |
| `interesting` | **Interesting** | a thinking ellipsis — see below |
| `not_for_me` | **Not for me** | `hand.thumbsdown.fill` |

Three, not two, because a like/dislike pair makes every card a verdict on somebody's taste.
*Interesting* is the one that lets a person say the true thing most often — *I would not have
found this, and I am glad it exists* — without either praising it or filing it under no.

**The set is closed.** A fourth kind is a product change and needs the owner, exactly as a
seventh push kind does. Reactions are not a palette.

**On the marks.** Monochrome, drawn at a per-symbol optical size rather than one shared point
size — a `heart.fill` and a three-dot mark set at the same size do not have the same visual mass,
and three marks of visibly different weight is the thing that will make this look cheap. The size
table lives with the component and is pinned by a snapshot golden.

**`interesting` is a thinking mark, and it is the hard one.** *(Owner, 2026-09-17: "a hmm,
thinking type thing.")* Not a star — a four-point sparkle reads "AI" in 2026 and says *notable*
where this kind means *hold on, let me sit with that*. The obvious glyph for the thinking beat is
the ellipsis, and the two off-the-shelf ellipses both collide with meanings this app has already
spent: bare `ellipsis` **is** the overflow menu (`TrackLinks.swift:170`), and any bubble variant —
`ellipsis.bubble.fill` and its relatives — draws a speech bubble on a song, which is the one thing
`docs/16` §1 still bans outright. A person who taps it expecting to type is a person the design
lied to.

So: **`ellipsis.circle.fill`** first — the enclosure is what separates it from the ⋯ menu, and
filled, it carries the same mass as `heart.fill`. If the simulator pass says it still reads as a
menu, the fallback is a custom `ReactionMark.thinking` in
`DesignSystem/Components/ReactionMark.swift`: three dots ascending in size, left to right, which
is the thinking ellipsis as distinct from the overflow ⋯ and is a shape no SF Symbol offers. That
would be the app's first custom vector mark, and it is worth it for a control a person taps every
night. Settle it against a screenshot, not in a document.

---

## 6. Storage

```sql
create type public.reaction_kind as enum ('loved', 'interesting', 'not_for_me');

create table public.reactions (
  id             uuid primary key default gen_random_uuid(),
  round_id       uuid not null references public.rounds(id) on delete cascade,
  reactor_id     uuid not null references public.profiles(id),
  submission_id  uuid not null references public.submissions(id) on delete cascade,
  kind           public.reaction_kind not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index reactions_one_per_card
  on public.reactions (round_id, reactor_id, submission_id);
create index reactions_round on public.reactions (round_id);
```

Deliberately the shape of `guesses` (`0002_core_tables.sql:104`), including the `profiles`
reference without a cascade — a member who leaves a circle keeps their history there, and only
`DELETE /me` removes it. There is **no** `reactions_not_self` constraint; §4 says why.

RLS enabled, deny-by-default, like every other table. Edge Functions use the service role and do
their own authorization.

No stored counts. `cards[].reactions` is a `group by kind` at read time.

---

## 7. API — two additive keys and one route

### `PUT /rounds/{group_id}/current/reactions`

One card at a time, because a reaction is one tap and the sheet-shaped upsert that guesses use
exists to reconcile a whole sheet a person filled in over ten minutes.

```jsonc
// request
{ "card_no": 3, "kind": "loved" }     // or "kind": null to clear
```

```jsonc
// response — the caller's own marks, in every phase, and nothing else
{ "data": { "my_reactions": [ { "card_no": 3, "kind": "loved" } ] } }
```

Guards, each `INVALID_INPUT` unless noted:

1. `state` must be `revealed` or `scored` → else `WRONG_PHASE`.
2. The round must be the circle's current round → else `WRONG_PHASE`. Past rounds are read-only.
3. Membership of `{group_id}` → else `FORBIDDEN`.
4. `joined_at < reveals_at` → else `JOINED_LATE` (403).
5. `card_no` in `1..N`. Your own card **is** in range (§4).
6. `kind` in the enum, or `null`.

Idempotent: the same body twice is one row and the same response. Rate limit 60/minute, per user,
matching guesses. The oldest-circle alias `PUT /rounds/current/reactions` exists for parity with
the other round routes.

### `GET /rounds/{group_id}/current`, phase `revealed`

Gains exactly one key:

```jsonc
"my_reactions": [ { "card_no": 3, "kind": "loved" } ]
```

Absent — not `null` — in every other phase. The caller's own data, so it may vary in length with
the caller's own activity and with nothing else. `open` and `voided` are byte-for-byte what they
were, which is what keeps AC-1's golden files untouched.

### `GET /rounds/{round_id}/results`

Each card gains two keys:

```jsonc
{ "card_no": 4,
  "track": { /* … */ },
  "owner": { /* … */ },
  "correct_guess_count": 6,
  "eligible_guesser_count": 7,
  "reactions": { "loved": 4, "interesting": 1, "not_for_me": 0 },
  "my_reaction": "loved"                  // null if you didn't mark this card
}
```

`reactions` always carries all three keys, zeros included, so the client never has to decide
whether an absent key means nought or means the feature was off that night. It is `null` — the
whole object — for a round that scored before this shipped. **No `reactors` array, in any form.**
Counts are anonymous, on every card, including your own; there is no disclosure, no list, and no
route that names who marked what. *(Owner, 2026-09-17.)* The reason is the same one `docs/16` §5
gives for never naming a guesser: a named **Not for me** on somebody's song is the single most
likely thing in this feature to hurt a real person in a real group of friends.

---

## 8. Where it appears

### 8.1 The quick pass — placing, at the reveal

Under the name grid, above `‹ Skip`: three `ReactionBar` pills, each a mark and its word.
Outlined by default; the one you pick fills with the screen's ultramarine and fires
`.impact(.light)`. Tapping it again clears it. No burst, no confetti, no count — there is nothing
to count yet, and the screen must not imply there is.

Reacting never advances the card. Naming still does, immediately, and the run is still the
ninety-second posture `E41` built it to be — the pills are an optional thing on the way past, not
a second question you must answer.

**Your own card is still skipped.** `E41-01`'s decision stands unamended: the run is the cards
you have work on, and it passes over yours silently, numeral and all. A stop that exists only to
offer an optional mark is a tap charged to every member every night, which is exactly the cost
that question weighed and refused. Your own drop is markable at the answers (§4, §8.3).

### 8.2 The flight — your own mark, read-only

Each `FlightCard` row shows the mark you placed, in `inkDim`, and nothing else. No count, no
control — the row is already carrying a number, artwork, two lines of text, a preview control and
a name chip. It is there so the flight agrees with what you did in the cover, not as a second
place to do it. Your own row carries no mark during `revealed`, because §8.1 gave you no way to
place one.

### 8.3 Results — the counts

Under each card's *"4 of 7 got it"* line, in the same `monoS` register: mark and count, all three
kinds, the zeros dimmed to `inkFaint`. A card nobody marked draws no row at all rather than three
zeros. Your own mark stays filled in ultramarine and stays tappable while this is tonight's round.

**Including your own card**, which is the only screen that offers you the marks for it (§4).
Nothing about that row says so; it is simply a card with a reaction row like the rest.

The counts arrive with the card in the progressive resolve (`docs/08` §7.1) rather than animating
separately. One reveal per card, not two.

### 8.4 The Record

Past results render the same DTO, so a night from three weeks ago shows the counts it ended with,
read-only. That is the whole integration; there is no new screen.

---

## 9. What this is not

- Not a comment. There is no free text anywhere in this feature, ever. The group has a group chat.
- Not a score. Nothing here reaches ear, readability, standings, profiles, insights or the share
  card.
- Not a leaderboard of songs. No "most loved" module in this version — deliberately held back
  until there is evidence people actually use the marks (owner, 2026-09-17). Adding it later is
  one derived read; removing it after people have played for it is a loss.
- Not a notification. §2.
- Not a fourth exception to `CLAUDE.md` §2.5. §2.

---

## 10. Verification

New, and gating:

| Claim | Where |
|---|---|
| No response during `revealed` carries another member's reaction or any count | `tests/functions/leak.test.ts`, new golden `round_revealed_reactions.json` |
| `GET /rounds/current` during `open` and `voided` is byte-identical to before this shipped | existing AC-1 goldens, unchanged — this is the assertion, not a side effect |
| `PUT …/reactions` has a reviewed golden, like every route in `functions/` | `tests/functions/leak.test.ts` |
| Phase, membership, `joined_late`, card range, enum, idempotency | `tests/functions/reactions.test.ts` |
| A past round refuses a write and still reads its counts | same |
| One row per member per card; a change replaces; a clear deletes | `tests/db/reactions.sql` |
| RLS denies a member's own token direct table access | `tests/functions/postgrest_locked.test.ts` |
| Counts are `group by`, never stored | `tests/db/reactions.sql` |
| The three marks read as one family at `large` and `accessibility5`, SE and 15 Pro Max | `ScreenSnapshotTests` |
| VoiceOver reads mark, word and count, and announces your own as selected | `A11yLabelTests.swift` |

This becomes **AC-12** in `docs/15-TESTING-AND-ACCEPTANCE.md`.

---

## 11. Slices

`tasks/E46-reactions.md`. Three, linear — the server route, placing at the reveal, counts at the
answers.
