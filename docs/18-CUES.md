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
>
> **Revision, 2026-09-05.** Two more of the same circle's round customs promoted into the
> catalog: `tied_to_someone` ("A song tied to a specific person") retexted to "A song that makes
> you think of them" — the two were near-duplicates, so this is really a rewording, not a
> replacement — and `unexpected_from_you` ("A song that would give the wrong impression of
> you" — asks the dropper to model a stranger's misreading of their own taste, a level of
> indirection nothing else in the catalog asks for) retexted to "A song for your current mood".
> A third round that day ("A song you hate") pointed at the catalog's existing `song_you_hate`
> verbatim — no catalog change there. Still 40 lines. See the dated note in
> `tasks/E35-cues.md`'s E35-02 section.

**Confession**
A song you're embarrassed to love · A song you'd never play in someone else's car · A song you
hate and know every word of · A song you'd lie about liking · A song you only play with
headphones on

**Refusal**
A song you hate · A song everyone loves that you don't · Your lock tf in song · A song that got
ruined for you

**Misdirection**
A song nobody here would guess is yours · A song from a genre you never listen to · A song your
parents would put on · A song for your current mood

**Function**
Your go-to aux song · The song you get ready to · A song for driving at night · The song you'd put
on to save a party

**Memory**
A song stuck to one specific summer · A song you got someone else into · A song from your first
phone · A song that makes you think of them · A song from middle school · A song that was always
on in your house

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

Two components — `CueBanner` and `CueCard` (`ios/BlindDrop/DesignSystem/Components/`) — and **one
placement per phase**, decided in a single predicate, `RoundDTO.Phase.drawsItsOwnCue`. Not inside
`RoundHeader` on any of them: that view is already tight rows built around one uncapped label
having caused a starved-sibling bug once (`ios-snapshot-renderer-constraints`-adjacent — see
`RoundScreen.swift`'s own header comment); another line competing for that space is the wrong
place to put this.

It began as one placement for the whole app — `RoundScreen` drawing the banner above whichever
phase view was up — and came apart twice, both times for the same reason. **A phase that reads as
a column wants the cue inside the column**, because a cue above a scroll is a header on the work
and a cue is a brief you read once before it.

- **Sealed and Voided — above the phase, as originally specified.** `CueBanner`, neutral ink,
  drawn by `RoundScreen`. These two do not scroll, so there is no "before the work" to move it to;
  above the phase is already where that is.
- **Submit — a `CueCard`, between the subhead and the field.** The drop screen's whole job is to
  answer the cue, and the answer is typed immediately below it. The one amber label in the app's
  cue treatment, argued in §2.
- **Reveal — a `CueBanner`, inside the flight's own header, under the song count.** *(Owner,
  2026-09-06.)* Pinned above the scroll it was a two-line strip standing permanently over a list
  it has nothing further to say to; the same position `CueCard` holds on the drop screen, with the
  cards in the field's place. It moved together with the round's date, which became the eyebrow
  over *"Tonight's drop"* — `docs/08` §6 carries that argument.
- **Results — a `CueCard`, under *"Answers"*.** *(Owner, 2026-09-03.)* There the cards below it
  are the room's replies to it, and a night read three weeks later is unintelligible without it.
  Labelled *"The cue"*, not *"Tonight's"*: `PastResultsScreen` pushes this same screen for a night
  from weeks ago.
- **The quick pass — a `CueBanner` at a new `prominent` density, sharing the close button's row.**
  *(`E41-04`, owner 2026-09-11.)* `CueBanner`'s material, `CueCard`'s type, and no micro-label:
  the strip filling whatever width the 44pt close button leaves, at `displayS`.

  **The label is dropped because of where in a night this is read.** Anybody inside this run has
  already met tonight's cue twice — on the drop screen as a `CueCard` under an amber *"Tonight's
  cue"*, and again in the flight header as the standard strip. A label introduces; on third sight
  it restates something the reader has been told twice. What is left has to hold the space alone,
  which is why the line goes **up** to `displayS` — the size the drop screen already sets the cue
  in, so it is recognised rather than re-read. VoiceOver keeps the label regardless: a person who
  cannot see where the strip sits has none of the context the sighted reader is trusted with.

  **Two wrong turns, kept because the second looked right.** It was first a `bodyS` capsule on
  this same row — correct position, wrong thing: fitting the cue into a gap forced the app's most
  incidental type and no label, so it read as a caption for an absent control, in a shape that
  hugged its text and aligned with nothing. The fix looked like retreating to the standard strip
  on a full-width row of its own, and that was legible and cost 64pt of artwork every cued night
  — 340pt down to 276pt on a 15 Pro Max, and an SE pinned to `Artwork.quickPassRange`'s floor.
  What had been wrong the first time was the type and the label, not the row. So the row came
  back, with the type raised instead of lowered.

  The close row is a full touch target with one glyph in it and an empty `Spacer` after —
  height `quickPassFixedChrome` has already been charged for. A one-line cue therefore costs the
  artwork nothing; the catalog's longest, at 45 characters, wraps to two and costs one line, and
  `Layout.quickPassCueRow` spends that worst case on every cued night rather than measuring the
  wrap. Above `.accessibility1` there is no width left to wrap into and the strip takes the full
  column beneath the button instead.

  Hoisted out of the run's per-card transition, because it is the one element on this screen that
  is constant across all eight cards and the recap alike — the round's own standing condition, not
  something that arrives with card `04` and leaves with it. This is also why the cue cannot sit
  beside the numeral, which is the other candidate row: `01 / 06` is the card's identity and rides
  that transition by design, so a cue next to it would slide off and back on every tap.

On every one of them: absent entirely when `cue` is `null` — no "no cue tonight" line; absence is
silent, matching how the rest of the open phase already treats "nothing to report."
- **The dark hours — last night's cue, not the coming one.** *(Owner, 2026-09-02.)* Between
  local midnight and `opens_at`, `GET /rounds/current` already returns the **coming** night's
  round, and the screen over it is *"Tonight's round is done."* — so its `cue` is a brief nobody
  has dropped against yet, and showing it hands the cue out hours before the round it belongs to
  opens. That screen shows `previous_cue` instead, labelled `round.cue.card.last.label`
  (*"Last night's cue"*), which is the night it is actually talking about. Two consequences:
  the server sends `previous_cue` only in that window (§8), and the card's label goes back to
  neutral `inkDim` there — §2's amber carve-out was argued from the card being the brief for the
  field below it, and in the dark hours there is no field and nothing being asked. No cue behind
  the round means no card: absence stays silent, as everywhere else.

  **And a way into that night's results.** *(Owner, 2026-09-03.)* The dark hours are the one
  phase with nothing to do — a headline, a card and a countdown — and the headline names a night
  the screen cannot otherwise reach, because `round_id` there is the *coming* one. So the server
  also sends `previous_round_id` in that window and the screen draws one quiet link under the
  card, `submit.closed.results` (*"See last night's results"*). Neutral, not a button: the
  countdown is the screen's subject, and results are ultramarine while this screen is amber
  (`CLAUDE.md` §2.5) — a second accent here would be the rule's one-screen violation for a link.

  The link does **not** replace the cue card. The cue is content — what last night's brief was,
  readable without going anywhere — and the link is a route; and the two are independently
  present, since a `voided` night has a cue and no results while an uncued night that scored has
  results and no cue. Which is exactly why `previous_round_id` is gated on `scored` rather than
  riding along with `previous_cue`.
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
"cue": { "key": "custom", "text": "A song for 3am" }           // an admin-written line: key always present

// GET /rounds/current — the dark hours only (state `open`, `opens_at` still ahead), and only
// when the circle has a finished round behind it. The cue of the round that just ended.
"previous_cue": { "key": "aux_song", "text": "Your go-to aux song" }

// GET /rounds/current — the dark hours only, and only when the round behind them is `scored`.
// The night the screen is talking about, so it can link to its results. Independent of
// `previous_cue` in both directions: a voided night has the cue and not this, an uncued
// scored night has this and not the cue.
"previous_round_id": "8f2c…"

// GET /rounds/:id/results — same shape, same key
"cue": { "key": "aux_song", "text": "Your go-to aux song" }

// GET /groups/current/record — per day
{ "local_date": "2026-08-20", "round_id": "…", "cue": { "key": "…", "text": "…" }, "entries": […] }

// GET /groups/current, GET /groups/:id — the admin-set cadence, and when a change takes effect
"cue_cadence": 2,
"cue_effective_from": "2026-08-29"

// PATCH /groups/current, PATCH /groups/:id — admin only
{ "cue_cadence": 0 | 1 | 2 | 3 }

// GET /groups/current, GET /groups/:id — **admin only**, absent (not null) for a member.
// The next round that has not opened, and whether its cue can still be changed (§11.6's
// amendment). `local_date` is the round's own date and never the word "tomorrow": during the
// dark hours the next unopened round is *today's*.
"next_cue": {
  "local_date": "2026-09-10",
  "text": "A song you hate",              // null when the cadence gives that night no cue
  "is_custom": false,
  "editable_until": "2026-09-10T10:00:00Z"
}

// PUT /groups/current/cue, PUT /groups/:id/cue — admin only. Free text, trimmed, 1–56 chars.
{ "text": "Your lock tf in song" }        // → the group DTO, next_cue included

// DELETE /groups/current/cue, DELETE /groups/:id/cue — admin only. Back to the derived line
// for that round's ordinal, which on an uncued night is correctly no line at all.
```

`next_cue` is the only key on the group payload whose presence depends on the caller's role, and
`WRONG_PHASE` is what the two writes answer with once the round has opened.

`previous_cue` and `previous_round_id` are the only keys on this endpoint whose presence depends
on the clock, and that decides a *payload*, never a phase (`CLAUDE.md` §2.2): `rounds.state` is still whatever
`tick_rounds()` wrote, and the instant compared against is `opens_at`, which the client is
already counting down to. Nothing is added once the round has opened, so the blind window's
response — the one `docs/14` §3 times and `roundFields()` pins byte for byte — is unchanged.

`cue` sits on `RoundDTO`'s **base keys**, not inside `RevealPayload` — it is present (or absent)
identically across all four phases, so modelling it as part of the reveal-only payload would be
wrong. `RoundDTO`'s phase decoder (`docs/13` §2 — "there is exactly one place `state` is
assigned") is untouched; `cue` decodes alongside `id`/`localDate`/`opensAt` before the phase
switch runs.

**Old clients.** `RoundDTO`'s decoder reads an explicit `CodingKeys` set and ignores unknown JSON
keys, so a build from before this feature simply never reads `cue` — the round plays exactly as it
does today, no crash, no missing-field error. No migration-in-place is needed for compatibility;
this is additive on both the DB and the wire.

### 8.1 `key` is always on the wire — including for a hand-written cue

An admin-written cue has no catalog entry (§11.6), so `prompt_key` is `null` in the database.
It is **not** null on the wire: `cueDTO` emits the sentinel `"custom"`, and `key` is always a
string.

This is a compatibility rule, not a modelling one, and it is load-bearing. Builds already in
users' hands decode `key` as a **non-optional** string. A cue object without it fails to decode,
and because the cue is nested inside the round payload that failure takes the *whole*
`GET /rounds/current` response with it — the screen does not lose its cue, it fails to load and
shows `error.generic`. Omitting the key for a custom cue did exactly that in production on
2026-09-10, for every user on the shipped build whose circle had a hand-written cue. `null` is
not an escape hatch: a non-optional string fails just as hard on an explicit null as on a
missing field.

`"custom"` is deliberately not a `cue_catalog` key and is never joined against one. Nothing in
the app reads `key` at all — it is carried for joins and future localisation — which is what
makes the sentinel harmless.

**Do not remove it** until no shipped build decodes `key` as non-optional. Tidying it away
early reintroduces the outage, and the shape is pinned by a test in
`tests/functions/rounds.test.ts` for that reason.

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

**And the cue itself, under the cadence** (`E43`, §11.6's amendment). Admin-only: the next
unopened round's date as an eyebrow, its current cue as a row, and a sheet with one free-text
field behind it. Neutral throughout — §2's amber carve-out is `CueCard` on the drop screen,
argued from that card being the brief for the field below it, and a settings row inherits
nothing from it. Once the round has opened the row goes read-only and says so, rather than
offering a control the server would refuse.

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
6. **No admin-authored custom cues.** ~~Explicitly not built.~~ That is content moderation, abuse
   surface, and a length-policing job this spec does not take on — the catalog in §6 is the
   complete, closed set, the same way the notification kinds in `CLAUDE.md` §6 are closed.

   > **Amended by the owner, 2026-09-09 (`E43`).** Struck. An admin can now write the next
   > round's cue by hand, from circle settings, until that round opens. Decided directly by the
   > owner, on the same footing as ADR-011 and `docs/17` §5's amendment to the notification cap
   > — not inferred by an agent.
   >
   > **Why the original reasoning did not hold.** It was written as a scope refusal, and the
   > scope arrived anyway: the ban was worked around by hand five times in nine days
   > (`20260901130000_cue_promote_kingston_customs.sql`,
   > `20260905110000_cue_promote_more_kingston_customs.sql`, and the plain data updates
   > alongside them), each time by writing the text straight into `rounds.prompt`, pointing
   > `prompt_key` at an unrelated placeholder key to satisfy `cueDTO()`'s not-null check, and
   > retexting a weak catalog line so the new one had somewhere to live. A feature that ships
   > as a migration every time is a feature, just an expensive one. The moderation objection is
   > also weaker than it read: a circle is at most a handful of people who know each other
   > (ADR-011 caps membership), the admin is one of them, and the line is visible to exactly
   > that room — this is not a public surface. The length-policing objection is the one that
   > survived, and it is answered rather than dismissed: `set_round_cue()` holds a hand-written
   > line to `cue_catalog.text`'s own 56-character constraint, so nothing an admin types can
   > overflow where a catalog line could not.
   >
   > **The bounds, which are the amendment:**
   > - **Free text, no picker.** The admin types a line; they do not browse the catalog. Owner
   >   decision — the line is already in mind, and listing the 40 is a different screen for a
   >   different need.
   > - **A custom cue is never promoted into the catalog.** Owner decision. It is that night's
   >   text and nothing more; `prompt_key` is null on it, and §6's catalog stays the shared
   >   default rather than growing from one circle's usage. Promoting a good line remains a
   >   deliberate migration, exactly as it is today.
   > - **One round, and only before it opens.** `state = 'open' AND opens_at > now_()` — the
   >   same predicate §10 already uses, enforced in `set_round_cue()` rather than by a disabled
   >   button, because a round that has opened may already have been sealed against the brief
   >   it carries.
   > - **A hand-set cue is not the derivation's to rewrite.** `rewrite_open_round_cues()` skips
   >   `prompt_custom` rows, so touching the cadence picker does not erase the line.
   > - **Admin-only, on the read as well as the write.** `next_cue` is absent — not null — for a
   >   member, because §7's argument against showing the coming night's cue early does not stop
   >   applying just because the screen is settings.
   >
   > Everything else in this document is unchanged. §3's derivation is still what assigns a cue
   > on every night nobody touches, which is nearly all of them.
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
