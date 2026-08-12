# 02 — Domain rules

The single source of truth for game logic. Client and server both implement against this
file. Where they disagree, the server wins.

---

## 1. The daily schedule

All times are **group-local**, resolved against the group's IANA timezone, fixed at group
creation.

| Phase | Default window | What is possible |
|---|---|---|
| `open` | 10:00 – 20:00 | Submit or replace your song. See nothing about others. |
| `revealed` | 20:00 – 22:00 | Songs visible, anonymised and numbered. Assign names. Submissions locked. |
| `scored` | 22:00 onward | Answers, per-card breakdown, personal stats, standings. |
| *(dark)* | 22:00 – 10:00 | Not a state. The round stays `scored`; the next round has not opened. |

`voided` replaces `revealed`/`scored` when fewer than 3 submissions exist at reveal time.

**Why the reveal is not the last event:** guessing has to happen while people are awake and
talking to each other, and the payoff has to land before the group goes quiet. **22:00 is a
hard ceiling. Never schedule anything after it.**

### Configurable surface

Group admins may change **one** thing: `reveal_hour`, allowed `18…21` inclusive. The guess
window is always exactly two hours, so `scores_at = reveals_at + 2h`. `opens_at` is always
`reveals_at − 10h`.

Submission open/close are **not** independently configurable in v1. Too many knobs.

| `reveal_hour` | opens | reveals | scores |
|---|---|---|---|
| 18 | 08:00 | 18:00 | 20:00 |
| 19 | 09:00 | 19:00 | 21:00 |
| 20 *(default)* | 10:00 | 20:00 | 22:00 |
| 21 | 11:00 | 21:00 | 23:00 |

Changing `reveal_hour` takes effect from the **next** round. It never mutates a round that
already exists. Enforce this in the API.

### DST

Round times are computed by materialising the group-local wall-clock time into UTC at round
creation, using the group timezone's offset **for that local date**. A round created for
2026-03-08 in `America/New_York` stores `reveals_at` as the UTC instant corresponding to
20:00 EST/EDT on that date — whichever applies. Rounds are created at most 48h ahead so the
offset is never stale. Never store a fixed UTC hour per group.

---

## 2. Round state machine

```
                 ┌──────────────► voided        (at reveals_at, submissions < 3)
                 │
  (created) ──► open ──► revealed ──► scored
                 ▲          │
                 │          └── submissions locked, card_order frozen
        opens_at │
```

| Transition | Trigger | Guard | Side effects |
|---|---|---|---|
| *none* → `open` | `now >= opens_at` | round exists | none |
| `open` → `voided` | `now >= reveals_at` | `count(submissions) < 3` | enqueue `void` notification to all members |
| `open` → `revealed` | `now >= reveals_at` | `count(submissions) >= 3` | generate + store `card_order`; enqueue `reveal` notification to all members |
| `revealed` → `scored` | `now >= scores_at` | always | enqueue `results` notification to members who submitted **or** guessed |

Rules:

- Transitions are **server-only**, evaluated by the tick job (`05-JOBS-AND-NOTIFICATIONS.md`).
- Transitions are **idempotent**: guarded by `UPDATE … WHERE state = <expected>` returning
  row count, inside one transaction with the outbox insert.
- Transitions are **monotonic**: a round never moves backwards. There is no un-reveal.
- A round that is late (job outage) still transitions on the next tick, and still fires its
  notifications once. It does not skip.
- The client **never** infers a transition. It polls / refreshes and takes the server's
  `state` verbatim. It may render a countdown, and when the countdown hits zero it may
  *refetch* — it may not change state locally.

### `card_order`

Generated once, at the `open → revealed` transition, stored on the round as an ordered array
of `submission_id`. Position `i` (0-based) is `card_no = i + 1`.

- Shuffle is a Fisher–Yates seeded with `hash(round_id)` so it is reproducible in tests, but
  the stored array — not the seed — is authoritative.
- Order **must not** correlate with submission time, user id, or track. Test: over 1000
  synthetic rounds, the rank correlation between submission `created_at` order and `card_no`
  must be within ±0.1 of zero.
- Identical for every member. Never re-shuffled, never per-user.

---

## 3. Participation rules

| Situation | Behaviour |
|---|---|
| **< 3 submissions at reveal time** | Round is **voided**. No reveal. Submissions are returned to their owners, unseen and unscored. Notification: *"Not enough drops tonight. Nothing revealed."* The round is excluded from every average. |
| **≥ 3 submissions** | Round proceeds. |
| **Two people submit the same track** | Allowed, and never blocked — the block itself would leak that the song is already in play. Both appear as separate cards. Scoring: see §4.3. |
| **User doesn't submit** | Cannot guess. Can view the reveal and the results. Earns no readability for that round; the round is excluded from their readability average. |
| **User submits but doesn't guess at all** | Still scored for readability. Their ear for the round is `0/0` — **excluded** from their ear average, not counted as a failure. |
| **User submits and guesses partially** | Unassigned cards score as wrong. Denominator is still `S − 1`. |
| **User joins before reveal time** | Can submit. Fully in the round. |
| **User joins after reveal time** | Can view the reveal. Cannot guess. Excluded from the round's scoring entirely — they are not in the name pool, not a submitter, not a denominator. |
| **User leaves the group** | Historical rounds keep their submissions and attribution. The user disappears from all future name pools. Past rounds are not recomputed. |
| **Device clock manipulation** | Irrelevant. All phase state is server-authoritative. |
| **App opened during `open` after already submitting** | Show the sealed card and the countdown. Nothing else. |
| **User replaces their song** | Allowed any number of times before reveal. Not penalised, not announced, not counted. `updated_at` moves; `created_at` does not. |
| **User un-submits** | **Not supported.** There is no delete. Once sealed, you are in the round. |

### The name pool

During `revealed`, the guess sheet's name pool is **exactly the set of users who submitted
this round**, minus yourself.

This leaks who participated. That is unavoidable — the game is unsolvable otherwise. Accept
it, and do not try to pad the pool with non-submitters: a padded pool makes the game
noticeably harder in a way that is not fun, and players will work out the padding within two
rounds.

Corollary: **the name pool must not be visible before `revealed`.** It is derived from
submissions, so it is a submission-count leak with extra steps.

### Who may guess

Only users who submitted a song in this round. Enforced server-side (`403 NOT_A_SUBMITTER`),
and reflected in the UI as a disabled sheet with an explanation — never as a hidden feature.
This is the participation-pressure mechanic. Keep it.

---

## 4. Scoring

Simple and legible. **Do not invent a composite score.**

### 4.1 Per round

Let `S` = number of submitters in the round (`S ≥ 3`, else voided).

```
readability(u) = correct_guesses_on_us_card / (S − 1)
ear(u)         = correct_guesses_made_by_u  / (S − 1)
```

- `readability` denominator is `S − 1` — **every other submitter**, whether or not they
  guessed. A submitter who never opened the guess sheet counts as a miss against everyone's
  readability. This is deliberate: readability measures "how much of the room read you", and
  a room that didn't look is a room that didn't read you.
- `ear` denominator is `S − 1` — every card you could have been asked about. Unassigned
  cards are wrong.
- **Exception:** if `u` made **zero** guesses, `ear` for that round is undefined (`0/0`) and
  the round is dropped from `u`'s ear average. It is not a zero.
- A non-submitter has neither value for that round.

### 4.2 All-time (within the group)

```
Ear (all-time)         = Σ correct_guesses / Σ possible_guesses     → percentage
                         (rounds where the user made zero guesses are excluded
                          from both sums)
                         also display raw Σ correct_guesses

Readability (all-time) = mean( readability(u, r) over rounds r )    → percentage
                         (per-round mean, NOT total-correct / total-possible)
```

Ear is pooled; readability is a mean of per-round rates. That asymmetry is intentional:
"Best Ear" is a leaderboard and should reward volume, while readability is a character trait
and should not be dominated by whichever round had the most participants.

Standings contain the **active roster only**. When a member leaves, their row disappears from
current standings, but their submissions and guesses remain in historical rounds and continue
to affect every other member's historical scores.

Voided rounds (`S < 3`) are excluded from everything.

### 4.3 Correctness under duplicate tracks

A guess is correct if **the guessed person did in fact submit that track this round.**

```
correct(guess g on card c by p, naming q)
  ⟺ ∃ submission s' in this round
       where s'.user_id = q
         and s'.track_key = track_key(submission behind card c)
```

Consequences, all intended:

- If A and B both dropped *Kelly Watch the Stars*, naming either A or B on **either** of
  their cards is correct.
- That correct guess counts toward the ear of the guesser **and** toward the readability of
  the card's actual owner.
- Duplicates therefore inflate readability for both owners. Fine — it is genuinely true that
  the room read them.

`track_key` is the dedupe identity, defined in `06-MUSIC-INTEGRATION.md` §3:
`coalesce(isrc, 'am:' || apple_music_id)`. Two Apple catalog IDs sharing an ISRC are the same
track. Never compare on title/artist strings.

### 4.4 Worked example — hand-check this

Group of 9. Round with **S = 8** submitters (Ivy did not submit). `S − 1 = 7`.

Submissions:

| User | Track | `track_key` |
|---|---|---|
| Ana | *Ribs* | `isrc:USUM71...A` |
| Ben | *Ribs* | `isrc:USUM71...A` ← duplicate of Ana |
| Cal | *Nights* | `isrc:USQX91...B` |
| Dee | *Redbone* | `isrc:USUM71...C` |
| Eli | *Motion Sickness* | `isrc:USDW11...D` |
| Fay | *Sunflower* | `isrc:USUM71...E` |
| Gus | *Kill Bill* | `isrc:USRC12...F` |
| Hal | *Bags* | `isrc:USQX91...G` |
| Ivy | — did not submit | — |

Card order at reveal (server-shuffled): `1=Dee 2=Ben 3=Hal 4=Ana 5=Gus 6=Cal 7=Eli 8=Fay`.

Guess activity:

- **Ana** guesses all 7 of her cards; 5 correct.
- **Ben** guesses 4 cards, leaves 3 blank; 3 of the 4 correct.
- **Cal** guesses all 7; 7 correct.
- **Dee** guesses all 7; 2 correct.
- **Eli** opens the app but assigns nothing. **Zero guesses.**
- **Fay** guesses all 7; 4 correct.
- **Gus** guesses all 7; 1 correct.
- **Hal** guesses all 7; 4 correct.
- **Ivy** did not submit → cannot guess.

**Ear for the round:**

| User | correct / 7 | Ear |
|---|---|---|
| Ana | 5/7 | 71.4% |
| Ben | 3/7 | 42.9% (3 blanks count as wrong) |
| Cal | 7/7 | 100% |
| Dee | 2/7 | 28.6% |
| Eli | — | **excluded** (0 guesses) |
| Fay | 4/7 | 57.1% |
| Gus | 1/7 | 14.3% |
| Hal | 4/7 | 57.1% |
| Ivy | — | not eligible |

**Readability**, say the correct-guess counts on each person's card were:

| Card owner | correct guesses on their card | Readability |
|---|---|---|
| Ana | 6 (incl. 2 people who named Ben — correct under the duplicate rule) | 6/7 = 85.7% |
| Ben | 5 (incl. 3 who named Ana) | 5/7 = 71.4% |
| Cal | 3 | 42.9% |
| Dee | 4 | 57.1% |
| Eli | 1 | 14.3% |
| Fay | 2 | 28.6% |
| Gus | 1 | 14.3% |
| Hal | 4 | 57.1% |
| Ivy | — | no card, excluded |

Note that Eli, who guessed nothing, **still has a readability** (14.3%), and Eli's
non-participation lowers everyone else's readability by up to 1/7. Both are correct.

`15-TESTING-AND-ACCEPTANCE.md` turns this exact table into a fixture. Do not change the
numbers without changing the test.

### 4.5 Framing (this is a product rule, not a copy suggestion)

Readability is presented as a **spectrum**, never a rank, never with judgement language. Low
readability is its own kind of win.

| Readability (all-time) | Label |
|---|---|
| 80–100% | Clear |
| 60–79% | Legible |
| 40–59% | Mixed |
| 20–39% | Elusive |
| 0–19% | Unreadable |

**Best Ear** is a straightforward leaderboard and *is* ranked 1..N.
**Readability has no rank position and no arrow.** Render it as a position on the spectrum.

---

## 5. Invariants a test must be able to assert

1. `state` only ever moves forward along the machine in §2.
2. `card_order` is non-null iff `state ∈ {revealed, scored}`.
3. `|card_order| = count(submissions in round)` and it is a permutation of them.
4. No guess row exists whose `round_id` differs from its submission's `round_id`.
5. No guess row exists where `guesser_id` has no submission in that round.
6. No guess row exists where `guessed_user_id = guesser_id`.
7. No guess row exists pointing at the guesser's own submission.
8. A user has at most one submission per round (unique constraint).
9. A user has at most one guess per (round, card) (unique constraint).
10. Rounds with `state = voided` contribute to no aggregate.
11. `scores_at = reveals_at + 2h` and `opens_at = reveals_at − 10h`, always.
