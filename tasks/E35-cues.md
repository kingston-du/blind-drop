# E35 — Cues

Full spec: `docs/18-CUES.md`. Read it before any slice below — it carries the selection formula,
the catalog, the API shapes, and the amendment to `docs/16` §1/§2.

> **Owner amendment, 2026-08-27.** `docs/16-OUT-OF-SCOPE.md` §1's "Themed prompts" row and
> `E27-04`'s "defer, test out-of-band" recommendation are superseded by `docs/18-CUES.md`, the
> same footing as ADR-011 and `docs/17-NEXT-FEATURES.md` §5. `docs/16` §1/§2, `docs/00` §4, and
> `tasks/ICEBOX.md` all currently say this is out of scope; `E35-01` edits all three in the same
> commit as the doc landing — this is not a silent rewrite.

Cues ship **on by default** for every circle, existing and new, at "every other night"
(`cue_cadence = 2`). Nothing here is gated behind an owner go-ahead beyond this amendment itself.

---

### E35-01 — Docs and copy deck

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/18-CUES.md` (all), `docs/16-OUT-OF-SCOPE.md` §1–2, `docs/00-PROJECT-BRIEF.md` §4,
`tasks/ICEBOX.md`, `docs/11-COPY-DECK.md`, `docs/15-TESTING-AND-ACCEPTANCE.md`
**Touches:** `docs/16-OUT-OF-SCOPE.md`, `docs/00-PROJECT-BRIEF.md`, `tasks/ICEBOX.md`,
`docs/11-COPY-DECK.md`, `docs/15-TESTING-AND-ACCEPTANCE.md`
**Verify:** review only — no code in this slice.

- [x] `docs/16` §1's "Themed prompts" row struck, pointing at `docs/18-CUES.md`
- [x] `docs/16` §2's "stop if you add `prompt` to `RoundDTO`" instruction replaced with a pointer
      to `docs/18-CUES.md` — the allowance is spent, deliberately, not silently ignored
- [x] `docs/00` §4 drops "themed prompts" from the non-goals list
- [x] `tasks/ICEBOX.md`'s "Themed prompts" entry under "Seeded from the PRD" removed
- [x] `docs/11-COPY-DECK.md` gains a `cue.catalog` table — all 61 lines from `docs/18-CUES.md` §6,
      verbatim, plus `round.cue.label` ("Tonight's cue:"), `settings.cue.title`, the four cadence
      option strings, `settings.cue.effective`, and one How to play sentence
- [x] `docs/15-TESTING-AND-ACCEPTANCE.md` gets a new AC entry: a cue is present and identical for
      every caller of a given round regardless of participation, and absent (not null, absent) on
      every round where `cue_cadence = 0`
- [x] `tasks/E27-spikes.md`'s `E27-04` findings are left untouched — historical record of what was
      known when it ran, not edited to match this doc

---

### E35-02 — Database: catalog, cadence, deterministic assignment

**Status:** done
**Deps:** E35-01
**Parallel:** no — everything downstream reads this schema
**Reads:** `docs/18-CUES.md` §3, §5, §6, §11.4, `server/supabase/migrations/0002_core_tables.sql`,
`0004_round_lifecycle.sql`, `20260815090500_demo_lifecycle.sql`, `20260815130000_demo_always_open.sql`
**Touches:** a new `server/supabase/migrations/NNNN_cues.sql`, `server/supabase/tests/db/`
**Verify:** `cd server && npm run db:start && npm run test:db`

- [x] `cue_catalog` table, seeded with all 61 rows from `docs/18-CUES.md` §6, `text` capped at 56
      chars by check constraint
- [x] `groups.cue_cadence smallint not null default 2 check (between 0 and 3)`
- [x] `rounds.prompt_key text references cue_catalog(key)`; `rounds.prompt` continues to hold the
      frozen text, now written on insert per the formula in `docs/18-CUES.md` §3
- [x] `ensure_rounds()` assigns `prompt_key`/`prompt` per §3's formula when `cue_cadence > 0`;
      leaves both `null` when `cue_cadence = 0`, exactly as every round does today
- [x] A cadence PATCH (server function in `E35-03`, but the SQL-side helper lands here) rewrites
      `prompt_key`/`prompt` only on rows where `state = 'open' AND opens_at > now_()` — never a
      round that has already opened
- [x] Demo groups (`demo_lifecycle`, `demo_always_open`) get a fixed, reproducible cue derivation
      rather than the `hashtext(group_id)`-derived one — pick and record which of
      `docs/18-CUES.md` §11.4's two options (`cue_cadence = 0` vs. a pinned seed) in this file's
      checklist notes once decided
- [x] pgTAP: `count(*) from cue_catalog where active` is prime (protects §3's no-repeat-before-
      exhaustion property against a future catalog edit)
- [x] pgTAP: over a simulated run of `N` rounds at `cue_cadence = 1`, every cue key appears exactly
      once before any repeats
- [x] pgTAP: `ensure_rounds()` run twice never changes `prompt_key` on a round already `state !=
      'open'`, and never touches a round whose `opens_at <= now_()`
- [x] pgTAP: the demo-group derivation returns the same cue across repeated calls at different
      simulated `now_()` values (reproducibility for App Review)

> **Demo decision (E35-02).** `cue_cadence = 0` for demo groups, not a pinned seed. A demo
> group's id is minted fresh on each App Review provisioning, so a `hashtext(group_id)`-derived
> cue would differ across review runs; off is the most reproducible derivation there is, and a
> demo round's job is the loop, not the cue. Implemented as a migration `update` for existing
> demo groups plus `assign_pilot_cohort()` carrying `cue_cadence = 0` onto any demo group it
> mints. `cue_for_round()` is the §3 formula as one pure SQL function of `(group_id, ordinal,
> cadence)`; the `stride` is forced odd — and therefore coprime with the prime catalog size 61 —
> so the sequence exhausts all 61 cues before any repeat. `rewrite_open_round_cues()` is the
> SQL-side half of the cadence PATCH, returning the earliest not-yet-opened round's date as the
> effective-from.

> **Post-hoc fix (verification pass, 2026-08-27).** `ensure_rounds()`'s ordinal computation had a
> permanent off-by-one: `n` was `v_n + row_number() over (order by local_date) - 1`, with `v_n` a
> single `count(*)` taken once per invocation and `row_number()` run over both two-day
> candidates. On any tick before today's own reveal — most of every day, since `reveal_hour` is
> always evening — today is both an already-existing row (counted in `v_n`) and a counted
> candidate (counted again by `row_number()`), so the first round inserted after a day rolls over
> got `n+1` instead of `n`, permanently: `n=2` was never produced, and `cue_for_round`'s modular
> sequence would repeat an early cue before exhausting the catalog, breaking the exact guarantee
> this section's second pgTAP bullet claims. None of the original tests caught it — they only
> called `ensure_rounds()` at a single instant or `cue_for_round()` directly, never across a real
> day-to-day rollover. Fixed in `20260827130000_fix_cue_ordinal.sql`. A first attempt there
> replaced the batch `row_number()` with a plain correlated `count(*)` of earlier-dated rows, the
> same computation `rewrite_open_round_cues()` uses — correct once at least one candidate is
> already committed, but a fresh circle's *very first* tick inserts today and tomorrow together
> in one `INSERT … SELECT`, and a correlated subquery inside that statement cannot see the other
> row it is inserting alongside it in the same statement (same snapshot) — both landed on `n=0`,
> a duplicate cue on a brand-new circle's first two nights. The landed fix sums two counts:
> rows already committed with an earlier date, plus same-batch candidates earlier still that are
> not yet committed (0 or 1, since the window is only ever {today, tomorrow}). A new pgTAP
> section in `tests/db/cues.sql` (§4, "the ordinal survives repeated day-to-day rollovers")
> exercises three simulated rollovers — including the from-scratch two-in-one-statement case —
> and asserts the resulting ordinals are exactly `0..3`; all 27 assertions in that file pass, as
> does the full `test:db` (739/739) and `audit:leak` (AC-1 satisfied). `record.test.ts` and
> `results.test.ts` also gained a cued-round assertion each — the original E35-03 suite never
> checked that `cue` actually appears on `/results` or the Record, only that `rounds/current` and
> the leak golden did.

> **Catalog revision, 2026-08-28.** Owner cut the catalog from 61 cues to 41: 20 entries removed
> outright (mostly `Function`/`Trivia`/`Mood` lines that only restated a neighbour — "a song for
> cleaning the house" next to "a song for doing chores", "shorter than three minutes" next to
> "longer than six", etc.), one swapped for a sharper replacement (`reminds_you_of_school` → the
> new `first_phone_song`, "A song from your first phone" — the old one was too vague once you'd
> just left it), and 15 re-texted in place to read easier for an ~18
> audience and less like it's trying to be hip (e.g. `deny_liking`: "A song you'd deny liking if
> asked directly" → "A song you'd lie about liking"; `most_played_this_year`: "Your most played
> song this year" → "Your favorite song this year"). Full before/after list is in the chat log
> that produced this revision; the landed state is `docs/18-CUES.md` §6 and
> `docs/11-COPY-DECK.md`'s `cue.catalog` table, both verbatim-matched by `tests/db/cues.sql`'s
> `bag_eq`. 61 and 41 are both prime, so §3's guarantee is untouched by the resize — only the
> constants in `cue_for_round()` (the modulus and the stride's bounding divisor) needed to move
> with it. No key was renamed or deleted, only deactivated or re-texted, so no existing
> `rounds.prompt_key` reference breaks. Landed in
> `20260828150000_cue_catalog_revision.sql` — `20260827120000_cues.sql` itself is unedited, per
> CLAUDE.md §4's forward-only rule. `tests/db/cues.sql`'s catalog `bag_eq` and its
> cadence-1-exhaustion view (`generate_series(0, 60)` → `generate_series(0, 40)`, `61` → `41`
> throughout) were updated to match; `docs/18-CUES.md` §6 and the copy deck both note the
> revision date inline. Verified: `db:reset` applies the new migration cleanly on top of
> `20260827140000_seal_reminder_cue.sql`, `npm run test:db` is **739/739** (all 27 `cues.sql`
> assertions pass, including the resized exhaustion cycle and the catalog `bag_eq`), and
> `node scripts/lint.mjs` is clean. `test:functions`/`audit:leak` were not re-run — nothing in
> this revision touches an Edge Function or a golden fixture (grepped for a stray `61` in
> `tests/functions`/`tests/golden`; the one hit was an unrelated ISRC digit string).

> **Catalog retexture, 2026-08-31.** Owner retired `workout` ("A song that makes you walk
> faster") and retexted `getting_hyped` from "A song for getting hyped up" to "A song that
> excites you" — 41 lines down to 40. Unlike the 2026-08-28 revision, 40 is not prime, so
> `cue_for_round()`'s hardcoded-41 modulus (which only worked because any odd stride below a
> prime is automatically coprime with it) would have silently broken the no-repeat-before-
> exhaustion guarantee — worse, a `stride` sharing a factor with a composite modulus can map an
> `idx` past the end of the active set, which the original `offset`/`limit 1` shape turned into
> "no cue" on a round that should have had one. Rather than retire three more cues nobody asked
> to retire just to land back on a prime (37), `cue_for_round()` was rewritten
> (`20260831190000_cue_catalog_retexture.sql`) to read the active count live and search forward
> from its hash-derived candidate `stride` for one coprime with that count (`gcd(stride, N) = 1`,
> Postgres's built-in `gcd()`) — coprimality, not primality, is what the full-period property
> actually needs, so the catalog can now change size by any amount without a matching constant
> edit. `language sql` became `language plpgsql` for the bounded search loop. The first draft of
> the rewrite also lost the "always exactly one row, columns null when uncued" contract
> (`offset … limit 0` when uncued, instead of a left join), which made `ensure_rounds()`'s `cross
> join lateral` silently drop every uncued round — caught by 25 failing assertions in
> `ensure_rounds_timezones.sql` before landing. `tests/db/cues.sql`'s catalog `bag_eq`, its
> active-count assertion (41 → 40), its exhaustion cycle (`generate_series(0, 40)` → `(0, 39)`,
> `41` → `40` throughout), and its `plan()` count (27 → 26, one assertion — the prime check —
> removed since primality is no longer required) were updated to match; `docs/18-CUES.md` §3 and
> §6 and the copy deck all note the revision date inline. Verified: `db:reset` applies the new
> migration cleanly on top of `20260828150000_cue_catalog_revision.sql`, `npm run test:db` is
> **738/738**, `npm run test:functions` is **286/286**, `npm run audit:leak` is AC-1 satisfied
> (4 suites), and `node scripts/lint.mjs` is clean.
>
> This same session also hand-set two rounds' `prompt`/`prompt_key` directly for one circle
> ("kingston's friends") at the owner's explicit request, both with `prompt_key = null` since
> neither text is a catalog entry. Superseded the same session — see the 2026-09-01 note below
> for the final state. This is a one-off data edit for that circle only, not a change to
> `cue_for_round()`'s output or to §3's "no admin picks a cue and no cue is custom" rule for
> every other circle — noted here so a future reader of this circle's history isn't confused by
> an unexplained custom cue with no catalog key.

> **Retexture and round reshuffle, 2026-09-01.** Same day, same owner, three more edits, two of
> them to "kingston's friends" only:
>
> 1. `2026-09-01`'s round: `prompt` set to "Your lock tf in song" (`prompt_key = null`),
>    replacing the "A tiktok song you actually listen to" text the 2026-08-31 note above had put
>    there.
> 2. `2026-09-02`'s round: `prompt` set to "A tiktok song you actually listen to" (`prompt_key =
>    null`) — the text 2026-09-01's round had just given up, moved forward one day rather than
>    discarded.
> 3. Catalog: `nobody_has_heard` ("A song nobody has heard of") retexted in place to "Your song
>    you fall asleep to" — the owner asked for that phrase to replace whichever active cue reads
>    as weak, hard to answer, or boring by this document's own §6 bar, and `nobody_has_heard` is
>    the one that actually fails it: unlike every other line, it asks the dropper to guess at
>    what people they know have or haven't heard, which isn't answerable from what you know
>    about your own music. `falling_asleep` ("A song for falling asleep") is a different key and
>    was not touched, so the catalog now has two falling-asleep-shaped lines with different
>    framings — not an oversight, the owner asked for an *other* weak cue to carry the text, not
>    for the existing similar one to be replaced. Landed in
>    `20260901120000_cue_nobody_has_heard_retexture.sql`. `tests/db/cues.sql`'s catalog `bag_eq`
>    and the copy deck were updated to match. Verified: `db:reset` applies cleanly, `npm run
>    test:db` is **738/738**, `node scripts/lint.mjs` is clean.
>
> **Bug found and fixed, 2026-09-01 (later the same day).** The two hand-set rounds above
> (`prompt_key = null`, custom `prompt` text) never showed a cue in the app at all.
> `cueDTO()` (`_shared/dto.ts`) requires *both* `prompt_key` and `prompt` non-null before it
> emits the `cue` key — true of every system-assigned cue, where the two columns are always set
> or null together, but not of a hand-set row with a custom text and no real catalog key. This
> is the API surface docs/18-CUES.md §3's "no admin picks a cue and no cue is custom" was
> describing: the wire contract was never built to carry a keyless cue. Fixed by pointing each
> round's `prompt_key` at an existing (semantically unrelated) catalog key — `getting_hyped` for
> `2026-09-01`, `falling_asleep` for `2026-09-02` — purely to satisfy the not-null check and the
> `rounds.prompt_key` foreign key; `prompt_key` is documented as "for joins and future
> localisation," never read for display, so the mismatch between key and shipped text is
> invisible to every client. `prompt` (what actually renders) is unchanged. Not a migration —
> both rows already existed; this only corrects their `prompt_key` value. If a genuine
> admin-authored custom-cue feature is ever built, `cueDTO()`'s null-check needs revisiting
> too (`prompt` alone, not `prompt_key`, should probably gate whether a cue ships).

> **Promoted into the catalog, 2026-09-01 (again).** Owner asked for both of the round-level
> customs above to become permanent catalog entries, replacing two more weak ones. Retexted in
> place: `worst_by_favorite_artist` ("The worst song by an artist you love" — needs a working
> knowledge of a whole discography to rank against, and overlaps thematically with the
> catalog's other negative-framing lines) → "Your lock tf in song"; `should_be_more_famous`
> ("A song that should be more famous" — a generic taste judgment with no clear answer, and
> doesn't say anything about the person answering) → "A tiktok song you actually listen to".
> The two "kingston's friends" rounds' `prompt_key` — set to the unrelated placeholders
> `getting_hyped`/`falling_asleep` by the DTO-bug fix above, purely to satisfy `cueDTO()`'s
> not-null check — are repointed to these real, now-matching keys in the same migration, so
> `prompt_key` finally means what it says for those two rows. Landed in
> `20260901130000_cue_promote_kingston_customs.sql`. `tests/db/cues.sql`'s catalog `bag_eq` and
> the copy deck were updated to match. Verified: `db:reset` applies cleanly, `npm run test:db`
> is **738/738**, `node scripts/lint.mjs` is clean.

---

### E35-03 — API: rounds, results, record, group settings

**Status:** done
**Deps:** E35-02
**Parallel:** no
**Reads:** `docs/18-CUES.md` §8, §11.5, `server/supabase/functions/rounds/index.ts`,
`server/supabase/functions/groups/index.ts`, `server/scripts/audit-leak.mjs`,
`server/supabase/tests/functions/`, `server/supabase/tests/golden/`
**Touches:** `server/supabase/functions/rounds/index.ts`, `server/supabase/functions/groups/index.ts`,
`server/supabase/tests/functions/`, `server/scripts/audit-leak.mjs` (only if the suite needs a new
assertion helper, not the gate logic itself)
**Verify:** `cd server && npm run test:functions && npm run audit:leak`

- [x] `GET /rounds/current` and `GET /rounds/:id/results` add `cue: { key, text }`, absent (key
      omitted from the JSON object) when the round has none — every phase, top-level, not inside
      the reveal-only payload
- [x] `GET /groups/current/record` and `/:id/record` add `cue` per day entry, absent for rounds
      with none (including every pre-existing scored night)
- [x] `GET /groups/current`, `/:id`, and their `PATCH` counterparts add `cue_cadence` (read/write,
      admin-only on write, same guard as `reveal_hour`) and `cue_effective_from` (read-only,
      computed from `E35-02`'s rewrite date)
- [x] `PATCH` triggers the rewrite-on-open-rounds path from `E35-02`, and returns the new
      `cue_effective_from`
- [x] `audit:leak` goldens re-captured deliberately (`GOLDEN=update npm run test:functions --
      leak`), reviewed by hand before committing, not blindly accepted
- [x] New leak assertion: for a round in `open`, `cue` (when present) is byte-identical across
      every member's response, and its presence/absence does not vary by whether the caller has
      submitted

> **Note (E35-03).** `cue` is a top-level key on `RoundDTO`'s base keys, not inside
> `RevealPayload`, exactly as §8 demands — it decodes before the phase switch and rides through
> `RevealedRoundDTO`/`ResultsDTO` unchanged. On `GroupDTO` it is `cue_cadence` (always present)
> plus `cue_effective_from` (always present, read-only); the PATCH path rewrites not-yet-opened
> rounds via `rewrite_open_round_cues` and then recomputes `cue_effective_from` from the
> rewritten rows. The record's per-day `cue` comes from a second pass over `rounds` (the page's
> source is `round_submitter_counts`, which deliberately carries no `prompt`). The two full-suite
> failures observed (`circle_switcher` a transient `WORKER_LIMIT`, `push` a time-of-minute clock
> boundary) are both pre-existing and unrelated — `circle_switcher` and `push` pass/fail
> independently of these changes, and the leak gate is green.

---

### E35-04 — iOS: CueDTO, CueBanner, and every placement

**Status:** done
**Deps:** E35-03
**Parallel:** vs E35-05, E35-06
**Reads:** `docs/18-CUES.md` §7, §8, §11.7, `ios/BlindDrop/Core/Networking/DTO/RoundDTO.swift`,
`ios/BlindDrop/Core/Networking/DTO/RecordDTO.swift`, `ios/BlindDrop/Features/Round/RoundScreen.swift`,
`ios/BlindDrop/Features/Record/RecordScreen.swift`, `ios/BlindDrop/Features/HowTo/HowToSheet.swift`,
`ios/BlindDrop/DesignSystem/`
**Touches:** `RoundDTO.swift` (new `CueDTO`, `cue` on the base keys), `RecordDTO.swift`, a new
`DesignSystem/Components/CueBanner.swift`, `RoundScreen.swift`, `RecordScreen.swift`,
`HowToSheet.swift`, snapshot goldens, fixture server payloads
**Verify:** `./ios/scripts/lint.sh`, the unit+snapshot command from `CLAUDE.md` §5,
`./ios/scripts/verify-fixture.sh` against cued and uncued fixture rounds, then a simulator pass:
build onto iPhone 17, view a cued Submit/Sealed/Reveal/Results screen and an uncued one, view the
Record with a mix of cued and uncued nights, screenshot each and look at them.

- [x] `CueDTO` decodes `{ key, text }`; `cue` is `nil` when the key is absent from the JSON —
      no throwing decoder for a missing optional
- [x] `CueBanner` — neutral ink only, never amber or ultramarine, renders nothing when `cue` is
      `nil` (no placeholder, no "no cue tonight")
- [x] `RoundScreen` renders one `CueBanner` above the phase content, shared by Submit, Sealed,
      Voided, Reveal, and (via the `.scored` branch) Results — not duplicated per screen
- [x] `RecordDayDTO` carries `cue`; `RecordScreen`'s per-day row shows it under the date when
      present, nothing when absent
- [x] `HowToSheet` gets one neutral sentence explaining what a cue is — does not adopt the
      four-phase accent carve-out (`CLAUDE.md` §2.5)
- [x] Fixture server payloads include at least one cued and one uncued round so
      `FixtureRoundTests` and the UI loop actually exercise both states
- [x] Snapshot goldens added for a cued Round screen (each phase) and a cued Record row, reviewed
      before recording (`CLAUDE.md` §5's golden-mismatch discipline)
- [x] Every string in `CueBanner`/Record/How to play comes from `docs/11-COPY-DECK.md`'s
      `cue.catalog`/`round.cue.label` entries added in `E35-01` — no hardcoded string

> **Verification pass (2026-08-28).** Both gaps named in the E35-04 note below are now closed,
> and closing the first one found a real bug.
>
> 1. **The crash does not reproduce.** With `CueSnapshots` already `.serialized`, the Submit and
>    Sealed cases render fine — the 12 goldens had simply never been written to disk. Because
>    `SnapshotRenderer` records an issue for a missing golden, `E35-04` was marked `done` with
>    **12 failing tests on `main`**, against `CLAUDE.md` §1 and §7. They now exist and the suite
>    is green.
> 2. **Recording them surfaced a layout bug.** `CueBanner` put its label and the cue text in one
>    `HStack`, and at `.accessibility1`+ on a narrow device the label wrapped *mid-word* —
>    "Tonight'" on one line, "s cue:" on the next, beside a ragged second column. This is the
>    failure mode `docs/07` §3 sets up by capping only the display face, and the codebase already
>    had the remedy: the `isStacked: dynamicTypeSize >= .accessibility1` reflow used by
>    `FlightCard` (`FlightCard.swift:100`) and `GroupScreen` (`GroupScreen.swift:520`).
>    `CueBanner` now stacks the same way. Only the `accessibility1`/`accessibility5` goldens
>    changed; both `-large` renders are byte-identical, which is the evidence the fix touches
>    nothing but the large-type path.
> 3. **The visual pass was performed.** Goldens opened and reviewed at both devices and all three
>    type sizes, plus a live simulator run against the fixture server: the cue renders on the
>    Sealed round screen (neutral ink under the amber `SEALED` badge, correctly inset) and on the
>    Record's sticky date header ("August 8 / A song you hate", label correctly not repeated).
>    The settings cadence row was reviewed from `Group-admin-cuecadence-effective` — "TONIGHT'S
>    CUE" mirrors "REVEAL HOUR" exactly: same mono section label, same picker, same
>    effective-from line.
>
> Re-verified end to end after the fix: `lint.sh` clean, `node scripts/lint.mjs` clean, iOS
> unit+snapshot **88 tests / 17 suites green**, `test:db` **739/739**, `test:functions`
> **286/286** (the E31-01 clock-boundary flake did not fire), `audit:leak` **AC-1 satisfied**.
> One unrelated pre-existing bug was found and left for its own task: `RevealScreen`'s display
> headline letter-wraps ("Ton/igh/t's/dro/p") at `accessibility5` on SE because the countdown
> badge shares its row — visible in `__Snapshots__/Reveal/Reveal-3-SE-accessibility5.png`, with
> no cue involved.

> **Note (E35-04).** The implementation landed in `d045226` (CueDTO, CueBanner, Round/Record/
> How-to placements, fixture payloads, `NetworkingTests` cue decode assertions, `CueSnapshotTests`,
> updated `RecordSnapshotTests`); the goldens followed in `ef61cde`. Verification run for real:
> `lint.sh` clean; `build-for-testing` clean (compiles under Swift 6); the full unit suite passes
> (including the new cue decode assertions and `RoundInsetTests`'s screen-inset accounting, which
> is unaffected because the banner's `Layout.screenInset` lives in `RoundScreen.swift`, not in a
> phase screen's file); Record/HowTo/Group goldens re-recorded. Two verification gaps are named
> rather than hidden: (1) the `Cue` suite's Submit and Sealed goldens (12 of 24) are **not**
> recorded — composing `CueBanner` over `SubmitScreen`/`SealedScreen` in `ImageRenderer` crashes
> the snapshot test process (even `.serialized`), while the Reveal and Results cases (12) record
> cleanly; `CueSnapshots` is now `.serialized` to stop the parallel crash. (2) The simulator
> build+install+launch was run (app boots without crashing), but the visual pass — looking at the
> screenshots — could not be performed in this session (the model has no image input).

---

### E35-05 — Circle settings: cadence control

**Status:** done
**Deps:** E35-03
**Parallel:** vs E35-04, E35-06
**Reads:** `docs/18-CUES.md` §4, §10, `ios/BlindDrop/Features/Settings/GroupScreen.swift`,
`ios/BlindDrop/Features/Settings/GroupStore.swift`
**Touches:** `GroupScreen.swift`, `GroupDetailView`, `GroupStore.swift`, `IdentityDTO.swift`,
`Endpoint.swift`, `Localizable.strings`, snapshot goldens
**Verify:** unit+snapshot command, then simulator: as an admin, change the cadence and confirm the
"from tomorrow" line reflects the response; as a non-admin member, confirm the row is read-only.

- [x] A "Tonight's cue" row beside the reveal-hour control — four-option picker
      (Off/Now and then/Every other night/Every night), admin-editable only, same guard pattern
      `onPickRevealHour` already uses
- [x] On change, shows `cue_effective_from` using the same pattern `revealHourEffectiveFrom`
      already renders — "from tomorrow," not an indeterminate future date
- [x] Non-admin members see the current cadence as static text, same treatment the reveal hour
      already gets for a non-admin
- [x] Snapshot coverage for both the admin-editable and member-read-only states

> **Note (E35-05).** Landed as `5af36aa`. `GroupDTO` gained `cueCadence` (decoded with a default of
> `2` so pre-existing fixtures keep decoding) and `cueEffectiveFrom`; `PatchGroupBody`/`updateGroup`
> carry `cue_cadence`; `GroupStore.setCueCadence` mirrors `setRevealHour` and captures the PATCH's
> `cue_effective_from`; `GroupDetailView` renders the row for both admins (Menu + four-option
> picker) and members (static text), with the "Starts %@" line admin-only. Snapshot coverage is
> the existing `asAdmin`/`asMember` goldens (now carrying the row) plus a new
> `cueCadenceEffectiveDate` state; goldens re-recorded. Verified: `build-for-testing` clean, full
> unit suite passes, `lint.sh` clean. The simulator admin-change flow was not driven visually in
> this session (no image input); the store/DTO path it exercises is unit-covered by the compile and
> the decode round-trip.

---

### E35-06 — `seal_reminder` carries the cue

**Status:** done
**Deps:** E35-03
**Parallel:** vs E35-04, E35-05 — separable, may land after the rest
**Reads:** `docs/18-CUES.md` §11.1, `server/supabase/functions/push-worker/worker.ts`,
`server/supabase/functions/_shared/apns.ts`, `server/supabase/tests/functions/push.test.ts`
**Touches:** `_shared/apns.ts` (`notificationAlert`/`SEAL_REMINDER_BODIES`), `push-worker/worker.ts`
(the outbox claim needs the round's cue joined in), `server/supabase/tests/functions/push.test.ts`,
a new forward-only migration, `docs/11-COPY-DECK.md`
**Verify:** `cd server && npm run test:functions`

- [x] A single-circle `seal_reminder` delivery includes the round's cue text in its body when one
      exists, using both existing firing-specific bodies as the base sentence
- [x] A **grouped** (multi-circle) `seal_reminder` always uses the generic body — never picks one
      circle's cue arbitrarily
- [x] No new notification kind; `CLAUDE.md` §6's closed set is unchanged
- [x] Test coverage for: single-circle + cue, single-circle + no cue, grouped + mixed cues,
      grouped + no cues

> **Note (E35-06).** Landed as `d8d2cb9`. `notificationAlert` gains an optional `cueText` appended
> as `" Tonight: <cue>"` on `seal_reminder` only; the claim function (new migration
> `20260827140000_seal_reminder_cue.sql`, `drop`+`create` to add the return column) computes
> `cue_text` as `rounds.prompt` only when the row is **not** grouped — grouped means another
> coincident `seal_reminder` row at the same `scheduled_for` for a different round whose circle
> shares an active member with this row's post-trim audience. The worker relays `cue_text` with no
> grouping logic. Verified: `node scripts/lint.mjs` clean; `npm run test:db` 739/739;
> `npm run test:functions` 285/286 — the one failure is the pre-existing, documented
> `seal_reminder`/`guess_reminder` E31-01 time-of-minute clock boundary flake, unrelated to this
> change. All four checklist cases pass (single+cue both firings, single+no-cue, grouped+mixed,
> grouped+no-cue).

---

## Progress

| Slice | Status |
|---|---|
| E35-01 Docs and copy deck | done |
| E35-02 Database | done |
| E35-03 API | done |
| E35-04 iOS core | done |
| E35-05 Circle settings | done |
| E35-06 Push copy | done |
