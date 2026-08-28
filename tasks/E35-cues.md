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

**Status:** wip
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

- [ ] `CueDTO` decodes `{ key, text }`; `cue` is `nil` when the key is absent from the JSON —
      no throwing decoder for a missing optional
- [ ] `CueBanner` — neutral ink only, never amber or ultramarine, renders nothing when `cue` is
      `nil` (no placeholder, no "no cue tonight")
- [ ] `RoundScreen` renders one `CueBanner` above the phase content, shared by Submit, Sealed,
      Voided, Reveal, and (via the `.scored` branch) Results — not duplicated per screen
- [ ] `RecordDayDTO` carries `cue`; `RecordScreen`'s per-day row shows it under the date when
      present, nothing when absent
- [ ] `HowToSheet` gets one neutral sentence explaining what a cue is — does not adopt the
      four-phase accent carve-out (`CLAUDE.md` §2.5)
- [ ] Fixture server payloads include at least one cued and one uncued round so
      `FixtureRoundTests` and the UI loop actually exercise both states
- [ ] Snapshot goldens added for a cued Round screen (each phase) and a cued Record row, reviewed
      before recording (`CLAUDE.md` §5's golden-mismatch discipline)
- [ ] Every string in `CueBanner`/Record/How to play comes from `docs/11-COPY-DECK.md`'s
      `cue.catalog`/`round.cue.label` entries added in `E35-01` — no hardcoded string

---

### E35-05 — Circle settings: cadence control

**Status:** wip
**Deps:** E35-03
**Parallel:** vs E35-04, E35-06
**Reads:** `docs/18-CUES.md` §4, §10, `ios/BlindDrop/Features/Settings/GroupScreen.swift`,
`ios/BlindDrop/Features/Settings/GroupStore.swift`
**Touches:** `GroupScreen.swift`, `GroupDetailView`, `GroupStore.swift`, snapshot goldens
**Verify:** unit+snapshot command, then simulator: as an admin, change the cadence and confirm the
"from tomorrow" line reflects the response; as a non-admin member, confirm the row is read-only.

- [ ] A "Tonight's cue" row beside the reveal-hour control — four-option picker
      (Off/Now and then/Every other night/Every night), admin-editable only, same guard pattern
      `onPickRevealHour` already uses
- [ ] On change, shows `cue_effective_from` using the same pattern `revealHourEffectiveFrom`
      already renders — "from tomorrow," not an indeterminate future date
- [ ] Non-admin members see the current cadence as static text, same treatment the reveal hour
      already gets for a non-admin
- [ ] Snapshot coverage for both the admin-editable and member-read-only states

---

### E35-06 — `seal_reminder` carries the cue

**Status:** wip
**Deps:** E35-03
**Parallel:** vs E35-04, E35-05 — separable, may land after the rest
**Reads:** `docs/18-CUES.md` §11.1, `server/supabase/functions/push-worker/worker.ts`,
`server/supabase/functions/_shared/apns.ts`, `server/supabase/tests/functions/push.test.ts`
**Touches:** `_shared/apns.ts` (`notificationAlert`/`SEAL_REMINDER_BODIES`), `push-worker/worker.ts`
(the outbox claim needs the round's cue joined in), `server/supabase/tests/functions/push.test.ts`
**Verify:** `cd server && npm run test:functions`

- [ ] A single-circle `seal_reminder` delivery includes the round's cue text in its body when one
      exists, using both existing firing-specific bodies as the base sentence
- [ ] A **grouped** (multi-circle) `seal_reminder` always uses the generic body — never picks one
      circle's cue arbitrarily
- [ ] No new notification kind; `CLAUDE.md` §6's closed set is unchanged
- [ ] Test coverage for: single-circle + cue, single-circle + no cue, grouped + mixed cues,
      grouped + no cues

---

## Progress

| Slice | Status |
|---|---|
| E35-01 Docs and copy deck | done |
| E35-02 Database | done |
| E35-03 API | done |
| E35-04 iOS core | todo |
| E35-05 Circle settings | todo |
| E35-06 Push copy | todo |
