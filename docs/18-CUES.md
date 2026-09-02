# 18 — Cues

> **Owner amendment, 2026-08-27.** `docs/16-OUT-OF-SCOPE.md` §1's "Themed prompts" row and
> `E27-04`'s "defer — test out-of-band first" recommendation are both superseded by this
> document, the same way ADR-011 superseded the original single-circle ban and the way
> `docs/17-NEXT-FEATURES.md` §5 superseded the unconditional-nudge rule. Decided directly by
> the owner, not inferred by an agent. `docs/16` §1's row is struck (§9 below), and
> `tasks/ICEBOX.md`'s "Themed prompts" entry is removed in the same commit that lands `E35-01`.

A cue is one short line, identical for every member, attached to some nights' rounds — *"Tonight's
cue: a song you hate."* It changes what people drop, not how the game is scored, and it is off by
default for no one: every circle ships with it **on**.

The product name is **cue**, not "prompt" — matches the app's own dialect (call sheet, the Record,
seal). Never call it a prompt in copy, code, or comments; `Round.prompt` stays the column name
because renaming a shipped column is its own migration this feature doesn't need.

---

## 1. What ships, in one sentence

Some nights a round carries a cue; every surface that shows the round — Submit, Sealed, Reveal,
Results, the Record — shows it identically or not at all, and a circle's admin controls how often
in circle settings.

## 2. Rule interactions

Nothing in `CLAUDE.md` §2 changes. In particular:

- **§1, no leak during `open`.** A cue is identical for every member and independent of anyone's
  participation — it is assigned before the round opens and never touches submission or guess
  state. It is exactly as safe as `opens_at`/`revealsAt`, which are also shown to everyone
  unconditionally during `open`.
- **§4/§5, colour.** A cue is never amber or ultramarine *where it is shared*. `CueBanner`
  appears on both the sealed and the revealed phases, so a semantic accent on it would violate
  whichever phase it isn't currently colouring for. Neutral ink only, on every surface it rides
  above (unlike How to play's phase-colour carve-out, which this does not touch).

  **Amended by the owner (drop-screen redesign, `E37-01`):** the drop screen draws the cue itself, as
  `CueCard`, and there the micro-label is `amberText`. This is not a hole in the rule, it is the
  rule's own reasoning applied: the objection was to *one* rendering wearing an accent that is
  wrong on half the phases it appears on, and this rendering appears on exactly one phase —
  `open` with nothing dropped — which is amber-accented top to bottom, in both its live and its
  dark-hours state. (Not "from the badge down": the dark hours draw no badge at all, and the
  screen is still `PhaseAccent.sealed` throughout.) Every other phase, Sealed
  included, keeps `CueBanner` neutral and unchanged. The accent is on the label only; the cue
  text stays `ink`, because the cue is content and the label is apparatus. A second phase
  adopting the card, or the card's *text* taking an accent, is a product change and needs the
  owner again.
- **§6, notification kinds.** No new kind. `seal_reminder`'s body may *carry* the cue text
  (§7 below) — that is a body change on an existing kind, not a seventh kind.
- **§7, no gamification.** A cue is not a streak, badge, or score input. It never changes
  readability, Ear, or standings.
- **§8, scores are derived.** Unaffected — a cue has no scoring relationship at all.

## 3. Selection: deterministic, no admin authoring, no stored assignment history

No admin picks a cue and no cue is "custom." The full set lives in a seed catalog
(`cue_catalog`, §5), and which entry a given round gets is a pure function of the round's
position in its circle's timeline — nothing is rolled at insert time, and nothing needs to be
remembered across rounds to keep the sequence coherent.

```
n     = the round's ordinal among its circle's rounds, by local_date, starting at 0
k     = the circle's cadence (1, 2, or 3 — see §4); k = 0 means cues are off
cued  = k > 0 AND (n + offset(group_id)) mod k == 0
i     = (n + offset(group_id)) div k                     -- the i-th cue this circle has drawn
cue   = catalog[(i * stride(group_id) + seed(group_id)) mod N]
```

`offset`, `stride`, and `seed` are derived once from `hashtext(group_id)`, so two circles on the
same cadence don't draw the same cue on the same night, and a circle doesn't always start its
cycle on cue #0.

**Why this is enough, with no drawn-history table.** The sequence `i ↦ catalog[(i·stride + seed)
mod N]` visits every one of the `N` cues exactly once before any repeat — a full period — as long
as `stride` is coprime with `N`. Nothing needs to be recorded to guarantee "no repeat before
exhaustion" or "no two cue nights in a row share a cue"; it falls out of modular arithmetic.
`ensure_rounds()` computes `n` from a `count(*)` over that circle's existing rounds at insert
time — see §5.

> **Revision, 2026-08-31.** `cue_for_round()` originally relied on `N` being prime (41) so that
> any nonzero odd `stride` below it was automatically coprime, and it hardcoded that count. That
> made the catalog's size load-bearing: the pgTAP suite asserted `count(*) from cue_catalog where
> active` was prime on every migration, and shrinking the active set by anything other than a
> prime-preserving amount would have silently broken the guarantee (some `stride` values share a
> factor with a composite `N`, which shortens the cycle and can even leave a round's cue-slot
> mapping to an inactive row entirely). `20260831190000_cue_catalog_retexture.sql` retired the
> `workout` entry and re-texted `getting_hyped`, landing the active count at 40 — not prime — so
> the function now reads `N` live from `count(*) from cue_catalog where active` and hunts forward
> from its hash-derived candidate `stride` until it lands on one coprime with the live `N`
> (`gcd(stride, N) = 1`, using Postgres's built-in `gcd()`). Coprimality, not primality, is what
> the full-period property actually needs; the catalog can now shrink or grow by any amount and
> the guarantee still holds without a matching modulus edit. See the dated note in
> `tasks/E35-cues.md`'s E35-02 section.

## 4. Cadence: per circle, admin-only, four settings

| Setting | `groups.cue_cadence` | Cadence |
|---|---|---|
| Off | `0` | never |
| Now and then | `3` | about two nights a week |
| Every other night | `2` | **the default for every circle, existing and new** |
| Every night | `1` | every night |

Per **circle**, not per member — a round is one shared thing, and a cue that one member sees and
another doesn't is incoherent, the same reasoning that keeps `reveal_hour` circle-scoped. Only the
admin sets it (`PATCH /groups/:id`, the same guard `reveal_hour` already has); members read it.

## 5. Storage

```sql
-- cue_catalog: the fixed, seeded set. Never admin-writable (§8).
create table public.cue_catalog (
  key    text primary key,
  text   text not null check (char_length(text) <= 56),
  active boolean not null default true
);
-- N (count(*) where active) must stay prime — see §6 and the pgTAP assertion in E35-02.

alter table public.groups
  add column cue_cadence smallint not null default 2
    check (cue_cadence between 0 and 3);

alter table public.rounds
  add column prompt_key text references public.cue_catalog(key);
-- rounds.prompt (docs/16 §2's existing nullable column) now holds the *frozen* cue text at
-- assignment time. prompt_key is for joins and future localisation; prompt is what actually
-- shipped that night, so retiring or editing a catalog line never rewrites a past round's cue.
-- prompt is null on every round created before this migration and on any round whose circle's
-- cadence is 0 — "no cue" is the same absent-value state the column has always had.
```

`ensure_rounds()` (`0004_round_lifecycle.sql`) gains the assignment step: for a group with
`cue_cadence > 0`, compute `n`/`i`/`cue` per §3 (using `count(*) from rounds where group_id =
$1` for `n`) and set `prompt_key`/`prompt` on insert. A group with `cue_cadence = 0` inserts
`null` for both, exactly as every round does today.

## 6. The catalog — 40 cues

Sentence case, no trailing period, **56 characters or fewer** (a pgTAP/lint assertion, so nothing
overflows on SE at `accessibility5` — the same discipline `docs/12` already asks of every string).
Every one answerable in the time it takes to think of a song — nothing that needs research, a
specific memory a person might not have, or a joke that only lands with the right timing. `N`
no longer needs to be prime (§3's 2026-08-31 revision) — `cue_for_round()` reads the active count
live and hunts for a coprime `stride`, so the catalog can grow or shrink by any amount without a
matching modulus edit.

> **Revision, 2026-08-28.** Cut from the original 61 to sharpen for the actual audience (~18,
> easy to answer, not straining for hip) and cut duplicate-feeling entries. See the dated note in
> `tasks/E35-cues.md`'s E35-02 section for the full before/after and which migration carries it.

> **Revision, 2026-08-31.** Owner retired `workout` ("A song that makes you walk faster") and
> retexted `getting_hyped` from "A song for getting hyped up" to "A song that excites you" — 41
> lines down to 40. See the dated note in `tasks/E35-cues.md`'s E35-02 section.

> **Revision, 2026-09-01.** Owner retexted `nobody_has_heard` from "A song nobody has heard of"
> to "Your song you fall asleep to" — picked as the weakest remaining line by this section's own
> bar (unfalsifiable; you cannot actually answer it from what you know about your own music).
> `falling_asleep` ("A song for falling asleep") is unrelated and untouched, so the catalog now
> carries two falling-asleep-shaped lines with different framings. Still 40 lines. See the dated
> note in `tasks/E35-cues.md`'s E35-02 section.
>
> **Revision, 2026-09-01 (later the same day).** Two cues that started as one circle's hand-set,
> keyless round overrides were promoted into the catalog permanently: `worst_by_favorite_artist`
> ("The worst song by an artist you love" — needs a working knowledge of a whole discography to
> rank against) retexted to "Your lock tf in song", and `should_be_more_famous` ("A song that
> should be more famous" — a generic taste judgment with no clear answer) retexted to "A tiktok
> song you actually listen to". Still 40 lines. See the dated note in `tasks/E35-cues.md`'s
> E35-02 section.

**Confession**
A song you're embarrassed to love · A song you'd never play in someone else's car · A song you
hate and know every word of · A song you'd lie about liking · A song you only play with
headphones on

**Refusal**
A song you hate · A song everyone loves that you don't · Your lock tf in song · A song that got
ruined for you

**Misdirection**
A song nobody here would guess is yours · A song from a genre you never listen to · A song your
parents would put on · A song that would give the wrong impression of you

**Function**
Your go-to aux song · The song you get ready to · A song for driving at night · The song you'd put
on to save a party

**Memory**
A song stuck to one specific summer · A song you got someone else into · A song from your first
phone · A song tied to a specific person · A song from middle school · A song that was always on
in your house

**Superlative**
Your favorite song this year · The song you skip the most · The oldest song you still play · A
song from before you were born · A song you loved as a kid · A song you never get tired of · A
song you've had on repeat this week

**Trivia**
A song in a language you don't speak · A tiktok song you actually listen to · A song you only know
because of a movie · A song you know all the lyrics to · Your song you fall asleep to

**Mood**
A song you were obsessed with at 13 · A song your friend put you onto · A song for a slow morning
· A song that excites you · A song for falling asleep

40 lines. `docs/11-COPY-DECK.md` gets its own `cue.catalog` table matching this list verbatim —
one source of truth, the seed migration reads from it, and `E35-02`'s verify includes a test
diffing the two so they cannot drift.

## 7. Where a cue appears

One component, `CueBanner` (`ios/BlindDrop/DesignSystem/Components/`), rendered once by
`RoundScreen` above whichever phase view is on screen — Submit, Sealed, Voided, Reveal, and
Results (reached through `RoundScreen`'s own `.scored` branch) all get it from one placement, one
snapshot suite. Not inside `RoundHeader`: that view is already three tight rows built around one
uncapped label already having caused a starved-sibling bug once
(`ios-snapshot-renderer-constraints`-adjacent — see `RoundScreen.swift`'s own header comment); a
fourth line competing for that space is the wrong place to put this.

- **Round (Submit / Sealed / Voided / Reveal / Results).** `CueBanner`, neutral ink, absent
  entirely when `cue` is `null` — no "no cue tonight" line; absence is silent, matching how the
  rest of the open phase already treats "nothing to report."
- **The Record.** One line under each night's date (`RecordDayDTO`, §8). Nights before this
  feature shipped simply have none.
- **Share card.** A kicker line above the headline, once `E30`'s new layout has a slot for it;
  if `E30` hasn't landed yet, this bullet is deferred rather than added to the pre-`E30` layout.
- **How to play.** One neutral sentence explaining what a cue is. The §2.5 four-phase accent
  carve-out for that screen does not extend to this sentence — it stays neutral like the rest of
  the page's non-legend content.
- **Circle settings.** The cadence control (§10) and, for members, a read-only line naming the
  current cadence.

## 8. API — additive, absent when there is no cue

```jsonc
// GET /rounds/current — every phase, top-level, alongside opens_at/reveals_at/scores_at
"cue": { "key": "song_you_hate", "text": "A song you hate" }   // absent (not null) when there is none

// GET /rounds/:id/results — same shape, same key
"cue": { "key": "aux_song", "text": "Your go-to aux song" }

// GET /groups/current/record — per day
{ "local_date": "2026-08-20", "round_id": "…", "cue": { "key": "…", "text": "…" }, "entries": […] }

// GET /groups/current, GET /groups/:id — the admin-set cadence, and when a change takes effect
"cue_cadence": 2,
"cue_effective_from": "2026-08-29"

// PATCH /groups/current, PATCH /groups/:id — admin only
{ "cue_cadence": 0 | 1 | 2 | 3 }
```

`cue` sits on `RoundDTO`'s **base keys**, not inside `RevealPayload` — it is present (or absent)
identically across all four phases, so modelling it as part of the reveal-only payload would be
wrong. `RoundDTO`'s phase decoder (`docs/13` §2 — "there is exactly one place `state` is
assigned") is untouched; `cue` decodes alongside `id`/`localDate`/`opensAt` before the phase
switch runs.

**Old clients.** `RoundDTO`'s decoder reads an explicit `CodingKeys` set and ignores unknown JSON
keys, so a build from before this feature simply never reads `cue` — the round plays exactly as it
does today, no crash, no missing-field error. No migration-in-place is needed for compatibility;
this is additive on both the DB and the wire.

## 9. `docs/16` and `tasks/ICEBOX.md` changes (land with `E35-01`)

- `docs/16-OUT-OF-SCOPE.md` §1's "Themed prompts" row is struck, with a note pointing here.
- `docs/16-OUT-OF-SCOPE.md` §2's "no DTO field, no UI... if you find yourself adding `prompt` to
  `RoundDTO`, stop" instruction is replaced with a pointer to this document — the allowance it
  described is now spent, deliberately.
- `docs/00-PROJECT-BRIEF.md` §4's non-goals list drops "themed prompts."
- `tasks/ICEBOX.md`'s "Themed prompts" entry (under "Seeded from the PRD") is removed.
- `E27-04`'s recorded findings in `tasks/E27-spikes.md` are left as historical record — they
  answered the question asked at the time, honestly, and are not edited after the fact; this
  document is what supersedes the recommendation, not a rewrite of what the spike found.

## 10. Circle settings UI

`GroupScreen`/`GroupDetailView` gains a "Tonight's cue" row beside the reveal-hour control,
admin-editable, a four-option picker (§4's table). On change it shows the same "from tomorrow"
pattern `revealHourEffectiveFrom` already renders, driven by `cue_effective_from` from the PATCH
response. Non-admin members see the current cadence as static text, same treatment as the reveal
hour they cannot edit.

**Effective date, and why it is not "first uncreated round."** A cue must never be added to,
changed on, or removed from a round that has already opened — someone may have already sealed
against it. Unlike `reveal_hour` (which only affects rounds not yet created and therefore lands on
whatever gets created next, however far out that is), a cadence change **actively rewrites**
`prompt_key`/`prompt` on every existing row where `state = 'open' AND opens_at > now_()` — i.e.
tomorrow's already-materialised, not-yet-opened round, using the same §3 formula. So a change made
today always takes effect **tomorrow**, deterministically, and `cue_effective_from` names that
exact date rather than an indeterminate one.

## 11. Interactions this feature creates, and the calls made on each

1. **Push copy.** `seal_reminder`'s body (`_shared/apns.ts`) may include the round's cue text —
   *"Two hours left, and you haven't sealed a song. Tonight: a song you hate."* This is a body
   edit on an existing kind (§2, §6), not a seventh kind. A **grouped, multi-circle**
   `seal_reminder` cannot name three different circles' cues in one line, so a grouped
   notification always falls back to today's generic body; only a single-circle delivery gets the
   cue-specific one. Scoped to `E35-06`, kept separable because it touches the outbox claim query.
2. **Track-reuse collisions.** `E18-03`'s cross-circle "you already dropped this" refusal
   (`upsert_submission`) will fire more on cue nights that point at a specific song someone has
   likely dropped before ("your most played song," "your go-to aux song"). Accepted as-is — the
   rule is correct and this feature doesn't get an exception to it — but `E35-04` should look at
   whether the refusal's copy still reads naturally when it's a cue, not a coincidence, causing
   the repeat.
3. **Stats mix cued and uncued nights.** Readability and Ear average across both with no
   distinction. Splitting them by cue-status is a progression-system-shaped feature this document
   explicitly does not propose — `CLAUDE.md` §7 stays intact.
4. **Demo / App Review circles.** `demo_lifecycle`/`demo_always_open` (`20260815090500`,
   `20260815130000`) need a cue that is stable and reproducible for a reviewer regardless of the
   review date — `E35-02` pins the demo group's `offset`/`stride` derivation to a fixed seed
   rather than `hashtext(group_id)`, or sets `cue_cadence = 0` for demo groups specifically.
   `E35-02` decides and records which.
5. **Leak audit.** `cue` is a new key present during `open` — `audit:leak`'s golden files need a
   deliberate re-capture (`GOLDEN=update npm run test:functions -- leak`), and a new assertion
   that `cue` is byte-identical across every caller's response for the same round, independent of
   who has or hasn't submitted (`E35-03`).
6. **No admin-authored custom cues.** Explicitly not built. That is content moderation, abuse
   surface, and a length-policing job this spec does not take on — the catalog in §6 is the
   complete, closed set, the same way the notification kinds in `CLAUDE.md` §6 are closed.
7. **Fixture server.** `server/functions/tests` fixtures and the iOS `FixtureRoundTests` need at
   least one cued and one uncued round in their canned payloads, or none of the iOS surfaces in
   §7 get exercised by `-only-testing:BlindDropUnitTests` / the UI loop (`E35-04`).

## 12. Slices

| Slice | What | Verify |
|---|---|---|
| `E35-01` | Docs: this file (already written), `docs/16` §9's edits, `docs/00`, `tasks/ICEBOX.md`, copy-deck `cue.catalog` table, a new AC-N in `docs/15` | review only |
| `E35-02` | DB: `cue_catalog` seed, `groups.cue_cadence`, `rounds.prompt_key`, `ensure_rounds()` assignment, cadence-change rewrite, demo-group pin | `npm run test:db` — determinism, prime-catalog assertion, no mid-round rewrite, demo stability |
| `E35-03` | API: `cue` on rounds/results/record, `cue_cadence`/`cue_effective_from` on group GET/PATCH, leak golden re-capture + identical-for-everyone assertion | `npm run test:functions`, `npm run audit:leak` |
| `E35-04` | iOS: `CueDTO`, `CueBanner`, placement on Round/Reveal/Results/Record, fixture payloads, goldens, simulator pass | lint, unit+snapshot, fixture, simulator |
| `E35-05` | Circle settings: cadence picker, admin guard, "from tomorrow" line, How to play sentence | snapshot + simulator |
| `E35-06` | `seal_reminder` body carries the cue when single-circle; generic fallback when grouped | `npm run test:functions` |

Order: `E35-01 → E35-02 → E35-03 → E35-04`, required. `E35-05` and `E35-06` are independent of each
other and may run parallel to `E35-04` once `E35-03` is done; `E35-06` is separable and may ship
after the rest if it needs more time — nothing else in this document depends on it.
