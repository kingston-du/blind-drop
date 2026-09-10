-- 20260909130000_admin_set_round_cue.sql — E43-01. The admin writes the next round's cue by
-- hand, and the derivation stops overwriting it. docs/18-CUES.md §11.6 (owner amendment,
-- 2026-09-09), tasks/E43-set-tomorrows-cue.md.
--
-- docs/18 §11.6 said custom cues were "explicitly not built". The owner reverses that here, on
-- the same footing as ADR-011. The ban has been worked around by hand five times already
-- (20260901130000, 20260905110000, and the plain data updates alongside them), each time by
-- writing the text straight into `rounds.prompt` and pointing `prompt_key` at an unrelated
-- placeholder key so `cueDTO()` would still build a cue. That is a button, not a migration.
--
-- Two things this migration is careful about:
--
--   1. **A hand-set cue must survive a cadence change.** `rewrite_open_round_cues()` rewrites
--      `prompt`/`prompt_key` on exactly the rounds this feature edits — `state = 'open' AND
--      opens_at > now_()`. Without the `not prompt_custom` guard below, an admin who set
--      tonight's cue and then toggled the cadence picker would silently lose it. That is the
--      single most load-bearing line in the file.
--
--   2. **`prompt_key` goes null on a custom cue, and that is correct.** §5 describes it as
--      being "for joins and future localisation"; `prompt` is the frozen text that actually
--      ships. A custom line has no catalog entry and is never promoted into one (owner
--      decision, 2026-09-09) — the catalog stays the shared default. The FK stays; the column
--      was always nullable.
--
-- `ensure_rounds()` is untouched: its `on conflict (group_id, local_date) do nothing` already
-- means it never rewrites an existing row, so a materialised round's hand-set cue is safe from
-- it without a guard.

-- ─── provenance ─────────────────────────────────────────────────────────────

alter table public.rounds
  add column prompt_custom boolean not null default false,
  add column prompt_set_at timestamptz,
  add column prompt_set_by uuid references auth.users(id) on delete set null;

comment on column public.rounds.prompt_custom is
  'True when this round''s cue was written by an admin rather than derived by cue_for_round() '
  '(docs/18-CUES.md §11.6 owner amendment). Every derivation path skips a flagged row.';

-- ─── rewrite_open_round_cues: leave hand-set cues alone ─────────────────────
-- Forward-only replacement of 20260827120000's definition. Identical but for the
-- `not r2.prompt_custom` filter, and for returning the earliest date it *could* affect
-- unchanged — a circle whose only unopened round is hand-set still reports that date as the
-- cadence's effective-from, because the cadence genuinely does take effect from that night
-- for every round after it.

create or replace function public.rewrite_open_round_cues(p_group_id uuid, p_cadence smallint)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_effective date;
begin
  select pg_catalog.min(r.local_date) into v_effective
    from public.rounds r
   where r.group_id = p_group_id
     and r.state = 'open'
     and r.opens_at > public.now_();

  update public.rounds r
     set prompt_key = cue.prompt_key,
         prompt     = cue.prompt
    from (
      select r2.id,
             (select pg_catalog.count(*)::int
                from public.rounds r3
               where r3.group_id = r2.group_id
                 and r3.local_date < r2.local_date) as n
        from public.rounds r2
       where r2.group_id = p_group_id
         and r2.state = 'open'
         and r2.opens_at > public.now_()
         -- The admin wrote this one. A cadence change is a change to the *derivation*, and a
         -- cue that was not derived is not its to rewrite.
         and not r2.prompt_custom
    ) ord,
    lateral public.cue_for_round(p_group_id, ord.n, p_cadence) as cue
   where r.id = ord.id;

  return v_effective;
end $$;

comment on function public.rewrite_open_round_cues(uuid, smallint) is
  'Rewrites the cue on every open round that has not yet opened *and was not hand-set by an '
  'admin*, and returns the earliest date it could affect (null when none). Called by the '
  'cadence PATCH path (docs/18-CUES.md §10, §11.6): a change never reaches a round somebody '
  'may already have sealed against, nor one an admin wrote themselves.';

revoke all on function public.rewrite_open_round_cues(uuid, smallint)
  from public, anon, authenticated;
grant execute on function public.rewrite_open_round_cues(uuid, smallint) to service_role;

-- ─── the editable round ─────────────────────────────────────────────────────
-- One definition of "the next cue", shared by the setter, the clearer and the reader, so the
-- three cannot drift: the earliest round that is open and has not yet opened. During the dark
-- hours (local midnight → opens_at) that is *today's* round, not tomorrow's — which is why
-- nothing in this feature is labelled "tomorrow".

create or replace function public.next_uncued_round(p_group_id uuid)
returns table (id uuid, local_date date, opens_at timestamptz, prompt text, prompt_custom boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.local_date, r.opens_at, r.prompt, r.prompt_custom
    from public.rounds r
   where r.group_id = p_group_id
     and r.state = 'open'
     and r.opens_at > public.now_()
   order by r.local_date
   limit 1;
$$;

comment on function public.next_uncued_round(uuid) is
  'The one round an admin may still write a cue onto: the earliest open round that has not yet '
  'opened (docs/18-CUES.md §11.6). Named for the slot, not its contents — the round may well '
  'already carry a derived or hand-set cue. During the dark hours this is today''s round.';

-- Internal helper, not an RPC: the API reads the same row with a plain select (it already
-- does, in `cueEffectiveFrom`). Granted to nobody, exactly like `cue_for_round` — reached only
-- through the two definer functions below. tests/db/rls.sql asserts the allowlist.
revoke all on function public.next_uncued_round(uuid) from public, anon, authenticated, service_role;

-- ─── set_round_cue ──────────────────────────────────────────────────────────
-- The edit window is `opens_at > now_()`, not a wall-clock hour: opens_at is reveals_at minus
-- ten hours, so a circle revealing at 20:00 is editable until 10:00 local, and the rule stays
-- correct if the admin moves reveal_hour. Enforced here rather than only in the UI, for the
-- same reason CLAUDE.md §2.3 puts the submitter check in the database.

create or replace function public.set_round_cue(
  p_group_id uuid,
  p_text     text,
  p_user     uuid
) returns table (local_date date, opens_at timestamptz, prompt text, prompt_custom boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round uuid;
  v_text  text := pg_catalog.btrim(p_text);
begin
  if v_text = '' or v_text is null then
    raise exception 'cue text is empty' using errcode = '22023';
  end if;
  -- The same 56-character bar cue_catalog.text carries, so a hand-written line cannot overflow
  -- where a catalog line cannot (docs/18 §6).
  if pg_catalog.char_length(v_text) > 56 then
    raise exception 'cue text is too long' using errcode = '22023';
  end if;

  select n.id into v_round from public.next_uncued_round(p_group_id) n;
  if v_round is null then
    raise exception 'no round is open for editing' using errcode = 'P0002';
  end if;

  return query
    update public.rounds r
       set prompt        = v_text,
           prompt_key    = null,
           prompt_custom = true,
           prompt_set_at = public.now_(),
           prompt_set_by = p_user
     where r.id = v_round
    returning r.local_date, r.opens_at, r.prompt, r.prompt_custom;
end $$;

comment on function public.set_round_cue(uuid, text, uuid) is
  'Writes an admin-authored cue onto the next round that has not yet opened, clearing '
  'prompt_key (a custom line has no catalog entry and is never promoted into one — owner '
  'decision, 2026-09-09). Raises 22023 on empty or over-long text, P0002 when no round is '
  'editable. docs/18-CUES.md §11.6.';

revoke all on function public.set_round_cue(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.set_round_cue(uuid, text, uuid) to service_role;

-- ─── clear_round_cue ────────────────────────────────────────────────────────
-- Reverting means "back to whatever the sequence would have given", which on an uncued night
-- is legitimately *no cue at all* — cue_for_round() returns a row with both columns null in
-- that case, and writing those nulls back is the correct outcome, not a failure.

create or replace function public.clear_round_cue(p_group_id uuid)
returns table (local_date date, opens_at timestamptz, prompt text, prompt_custom boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   uuid;
  v_n       int;
  v_cadence smallint;
begin
  select n.id into v_round from public.next_uncued_round(p_group_id) n;
  if v_round is null then
    raise exception 'no round is open for editing' using errcode = 'P0002';
  end if;

  select g.cue_cadence into v_cadence from public.groups g where g.id = p_group_id;

  -- The round's true ordinal among its circle's rounds — the same correlated count
  -- rewrite_open_round_cues() uses, so a cleared cue lands on exactly the line the derivation
  -- would have assigned in the first place.
  select pg_catalog.count(*)::int into v_n
    from public.rounds r3
   where r3.group_id = p_group_id
     and r3.local_date < (select r4.local_date from public.rounds r4 where r4.id = v_round);

  return query
    update public.rounds r
       set prompt        = cue.prompt,
           prompt_key    = cue.prompt_key,
           prompt_custom = false,
           prompt_set_at = null,
           prompt_set_by = null
      from public.cue_for_round(p_group_id, v_n, v_cadence) as cue
     where r.id = v_round
    returning r.local_date, r.opens_at, r.prompt, r.prompt_custom;
end $$;

comment on function public.clear_round_cue(uuid) is
  'Reverts the next unopened round to its derived cue (docs/18-CUES.md §3), clearing the '
  'hand-set flag. On an uncued night the derived value is null and that is the correct result.';

revoke all on function public.clear_round_cue(uuid) from public, anon, authenticated;
grant execute on function public.clear_round_cue(uuid) to service_role;
