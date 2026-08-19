-- 20260819090000_track_reuse_overlap.sql — docs/02 §3, docs/14 §2. tasks/E18-03.
--
-- With one circle, submitting the same track twice in a day was structurally impossible — you
-- get one submission per round (`submissions_one_per_user_per_round`) and a round is one day.
-- With several circles that stops being true: the same user can drop the same song into two
-- circles the same night, and if a third person sits in both circles, that person can read the
-- two revealed cards and learn "the same person dropped this in both rooms" — narrowing who
-- that person is in whichever circle has fewer plausible candidates. Two circles that share
-- nobody but the submitter carry no such channel: nobody who can see both reveals exists to
-- draw the line, so a repeat there is exactly as harmless as two strangers picking the same
-- song ever was (docs/02 §3 — that rule is about two *different* people in one round, and is
-- unchanged).
--
-- So the refusal is conditioned on overlap, not on repetition itself, and it lives inside
-- `upsert_submission` (0018) — the one place every submission, first or replacement, already
-- passes through — under the same advisory-lock discipline `enforce_circle_cap` established
-- (20260818090000), with a distinct key: the two locks guard unrelated invariants and have no
-- reason to contend with each other.

create or replace function public.upsert_submission(
  p_round_id   uuid,
  p_user_id    uuid,
  p_track_key  text,
  p_track_meta jsonb
) returns table (track_meta jsonb, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id   uuid;
  v_local_date date;
begin
  select r.group_id, r.local_date into v_group_id, v_local_date
  from public.rounds r
  where r.id = p_round_id;

  perform pg_advisory_xact_lock(hashtext('submit:' || p_user_id::text));

  -- BD003: refused only when the repeat would actually deanonymise somebody — same
  -- `track_key`, same group-local night, a *different* circle, and at least one other person
  -- who is an active member of both circles and could therefore read both reveals. This query
  -- runs unconditionally, on both the accepted and the refused path, so a refusal costs
  -- exactly what a success costs (docs/14 §2's timing-channel rule, checked by
  -- `npm run audit:leak`).
  if exists (
    select 1
    from public.submissions s
    join public.rounds r on r.id = s.round_id
    where s.user_id = p_user_id
      and s.track_key = p_track_key
      and r.local_date = v_local_date
      and r.group_id <> v_group_id
      and exists (
        select 1
        from public.memberships mine
        join public.memberships theirs
          on theirs.user_id = mine.user_id
         and theirs.group_id = r.group_id
         and theirs.left_at is null
        where mine.group_id = v_group_id
          and mine.left_at is null
          and mine.user_id <> p_user_id
      )
  ) then
    raise exception 'track already used tonight in an overlapping circle' using errcode = 'BD003';
  end if;

  return query
  insert into public.submissions as s (round_id, user_id, track_key, track_meta,
                                       created_at, updated_at)
  values (p_round_id, p_user_id, p_track_key, p_track_meta,
          public.now_(), public.now_())
  on conflict (round_id, user_id) do update
    set track_key  = excluded.track_key,
        track_meta = excluded.track_meta,
        -- created_at is absent on purpose: the day you first sealed something in this round
        -- is not changed by changing your mind (docs/04 §4).
        updated_at = case
                       when s.track_key is distinct from excluded.track_key
                       then public.now_()
                       else s.updated_at
                     end
  returning s.track_meta, s.updated_at;
end $$;

comment on function public.upsert_submission(uuid, uuid, text, jsonb) is
  'Drop or replace a song. Preserves created_at always, and preserves updated_at when the '
  'track_key is unchanged so that a repeated request is genuinely idempotent — docs/04 §4. '
  'Raises BD003 (tasks/E18-03) when the same track_key was already used by this user tonight '
  'in a different circle that shares another active member with this one.';

revoke all on function public.upsert_submission(uuid, uuid, text, jsonb) from public;
grant execute on function public.upsert_submission(uuid, uuid, text, jsonb) to service_role;
