# E43 — Set tomorrow's cue

The admin writes the next round's cue by hand, from circle settings, up until that round opens.

`docs/18-CUES.md` §11.6 says custom cues are "explicitly not built" — that is reversed by the
owner here, on the same footing as ADR-011 and `docs/17` §5's amendment to the notification cap.
The reason is empirical: the ban has been worked around by hand five times
(`20260901130000_cue_promote_kingston_customs.sql`,
`20260905110000_cue_promote_more_kingston_customs.sql` and the plain data updates alongside
them), each time by writing the text straight into `rounds.prompt`, pointing `prompt_key` at an
unrelated placeholder key to satisfy `cueDTO()`, and then retexting a weak catalog entry so the
line had somewhere to live. A feature that ships as a migration every time is a feature that
should be a button.

**Two owner decisions, recorded 2026-09-09:**

1. **Free text only.** No catalog picker. The admin types a line; they do not browse the 40.
   Listing `cue_catalog` would need a new security-definer function anyway (`revoke all … from
   service_role` is on that table deliberately), and the point of the feature is the line the
   admin already has in mind.
2. **A custom cue is never promoted into the catalog.** It is that night's text and nothing
   more. The catalog stays the shared default and stops growing from one circle's usage — which
   means the good ones no longer propagate to every circle by accident, and promoting one is a
   deliberate migration, exactly as it is today.

**The edit window is `state = 'open' AND opens_at > now_()`** — the same predicate
`rewrite_open_round_cues()` and `cueEffectiveFrom()` already use. `opens_at = reveals_at −
10 hours`, so a circle revealing at 20:00 is editable until 10:00 local; the rule is expressed
against `opens_at` rather than a wall-clock hour so it stays correct when `reveal_hour` changes,
and it is enforced server-side rather than by a disabled control (`CLAUDE.md` §2.3's discipline,
applied to a different guard).

**What `prompt_key` costs, and the one-line fix.** `cueDTO()` refuses to build a cue when
*either* `prompt_key` or `prompt` is null, so a keyless custom cue would silently vanish from
every surface in the app — that is the bug the placeholder keys in the migrations above were
working around. `key` becomes optional on `CueDTO` (server and iOS) and the guard drops to
`prompt === null`. `prompt` was always the text that ships; §5 describes `prompt_key` as being
"for joins and future localisation", and nothing reads it at render time.

---

### E43-01 — The override survives a cadence change

**Status:** done
**Deps:** —
**Reads:** docs/18-CUES.md §3, §5, §10, this file
**Touches:** server/supabase/migrations/, server/supabase/tests/db/cues.sql
**Verify:** `cd server && npm run test:db -- cues`
**Parallel:** no
**Proves:** —

A round grows a flag saying its cue was set by a person, and every derivation path learns to
leave those alone. Without this, toggling cadence silently erases a hand-set cue —
`rewrite_open_round_cues()` rewrites `prompt`/`prompt_key` on exactly the rounds this feature
edits.

- [x] `rounds.prompt_custom boolean not null default false`, plus `prompt_set_at timestamptz`
      and `prompt_set_by uuid references auth.users` for provenance
- [x] `rewrite_open_round_cues()` gains `and not r.prompt_custom`
- [x] `set_round_cue(p_group_id uuid, p_text text, p_user uuid)` — resolves the earliest round
      with `state = 'open' and opens_at > now_()`, sets `prompt`, nulls `prompt_key`, flags it;
      returns the round's `local_date`, text and `opens_at`. Raises when there is no such round.
- [x] `clear_round_cue(p_group_id uuid)` — recomputes the derived cue from `cue_for_round()` at
      that round's true ordinal and writes it back, clearing the flag. Reverting on an uncued
      night correctly yields *no cue*.
- [x] `ensure_rounds()` untouched — `on conflict do nothing` already never rewrites a row
- [x] pgTAP: a custom cue survives a cadence change; clear restores the derived value; a round
      past `opens_at` is refused; clearing on an uncued night leaves `prompt` null

### E43-02 — The API reads and writes the next cue

**Status:** done
**Deps:** E43-01
**Reads:** docs/18-CUES.md §7, §8, §10, this file
**Touches:** server/supabase/functions/groups/index.ts, server/supabase/functions/_shared/dto.ts,
server/supabase/tests/functions/, server/supabase/tests/golden/groups_current.json
**Verify:** `cd server && npm test`
**Parallel:** no
**Proves:** AC-1 (leak)

Three additive, admin-only surfaces, all on the group so the client never needs a round id:
`next_cue` on `GET /groups/current` and `GET /groups/:id`, `PUT /groups/current/cue` and
`DELETE /groups/current/cue` (and their `:group_id` twins, per the existing shared-handler
pattern).

**Admin-gated, deliberately.** §7 argues that showing the *coming* night's cue early is wrong —
it is the whole reason the dark hours render `previous_cue` instead of the base `cue`. Sending
`next_cue` to a member would hand out tomorrow's brief today. This is not a `CLAUDE.md` §2.1
matter (a cue is not participation-derived), but it is the same product instinct, and gating it
keeps `/rounds/current` — the byte-pinned blind-window response — entirely untouched.

```jsonc
"next_cue": {
  "local_date": "2026-09-10",
  "text": "A song you hate",       // null when that night is uncued
  "is_custom": false,
  "editable_until": "2026-09-10T10:00:00Z"
}
```

- [x] `CueDTO.key` optional; `cueDTO()` guards on `prompt === null` only
- [x] `next_cue` on both group reads, absent entirely for a non-admin caller
- [x] `PUT`/`DELETE .../cue`, admin-guarded by the same check `reveal_hour` uses
- [x] Validation: trimmed, non-empty, ≤ 56 characters (the `cue_catalog` check constraint's own
      bar, and what keeps an SE at `accessibility5` from overflowing). No style policing.
- [x] `409` when no unopened round exists; `403` for a member
- [x] `groups_current.json` golden re-captured deliberately, and a new assertion that `next_cue`
      is absent for a non-admin
- [x] `npm run audit:leak` green

### E43-03 — The row in circle settings

**Status:** done
**Deps:** E43-02
**Reads:** docs/11-COPY-DECK.md `settings.cue.*`, docs/18-CUES.md §2, §10, this file
**Touches:** ios/BlindDrop/Features/Settings/GroupScreen.swift,
ios/BlindDrop/Features/Settings/GroupStore.swift,
ios/BlindDrop/Core/Networking/, ios/BlindDrop/Resources/Localizable.strings,
docs/11-COPY-DECK.md
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropUnitTests
-only-testing:BlindDropSnapshotTests`; simulator: admin edits the cue and sees it, a member sees
no row at all
**Parallel:** no
**Proves:** —

Under the existing cadence picker in `cueSection`, admin only: a row showing the next round's cue
with its **date** as the eyebrow — not "Tomorrow", because during the dark hours the next
unopened round is *today's*, and the date is the only label that is always true. Tapping opens a
sheet with one field.

- [x] The row, admin-only, with the date eyebrow and an empty state when the night is uncued
- [x] Edit sheet: prefilled field, live count against 56, **Save it** primary, quiet **Use the
      automatic cue** reset shown only when `is_custom`
- [x] Setting a cue on an otherwise-uncued night works
- [x] Past `editable_until` the row is read-only and says the round has opened
- [x] Neutral colour throughout — §2's amber carve-out is `CueCard` on the drop screen only, and
      a settings row inherits nothing from it
- [x] New copy-deck strings in the same commit; tone per `CLAUDE.md` §6
- [x] Simulator: admin edits, member sees nothing, and the edited text then renders on the drop
      screen's `CueCard` (driven from a fixture round, not by waiting for morning)
