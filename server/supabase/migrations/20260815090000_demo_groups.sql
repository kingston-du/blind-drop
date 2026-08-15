-- 20260815090000_demo_groups.sql — the App Review demo environment, part 1 of 2.
--
-- The problem this exists for: `demo@blinddrop.dev` sits alone in a capacity-1 "App Review"
-- pilot cohort (20260813010000). Its group runs the real schedule, so the core loop is only
-- reachable between 20:00 and 22:00 group-local, and `tick_rounds()` voids anything under
-- three submitters. An App Review that happens at 23:00 cannot see the app work at all —
-- Guideline 2.1, and not a risk we can schedule our way out of.
--
-- The fix, in two migrations. This one marks a group as a demo group and takes it out of the
-- scheduler's hands. 20260815090500 gives it a lifecycle driven by the reviewer's own actions
-- instead of by the clock.
--
-- **The safety property is the exclusion, and it runs both ways.** Nothing on the real
-- schedule may touch a demo round, and nothing in the demo path may touch a real one. That is
-- why `is_demo` defaults to false and is reachable only through a pilot cohort row, which is
-- itself server-only (20260813000000): there is no API surface, for any caller, that can turn
-- a real group into a demo group.
--
-- Note what is *not* here. No column on `rounds`, no relaxation of `rounds_window`, no second
-- copy of the state machine. A demo round is an ordinary row obeying every constraint in 0002;
-- all that differs is who moves it and when.

-- ─── the flag ────────────────────────────────────────────────────────────────

alter table public.groups add column is_demo boolean not null default false;
alter table public.pilot_cohorts add column is_demo boolean not null default false;

comment on column public.groups.is_demo is
  'A demo group''s rounds are advanced by public.demo_tick() on the submitting/guessing '
  'action, not by tick_rounds() on the clock. Set only from pilot_cohorts.is_demo, which is '
  'server-only; no API path can set it. See 20260815090500.';

comment on column public.pilot_cohorts.is_demo is
  'Marks the group this cohort creates as a demo group. Kept on the cohort rather than set by '
  'hand so App Review enrollment stays code-free (20260813000000).';

update public.pilot_cohorts set is_demo = true, updated_at = now() where name = 'App Review';

-- ─── and the same fact on the round ──────────────────────────────────────────
-- Denormalised onto `rounds` for one reason: `rounds_window` needs it, and a check constraint
-- cannot reach another table.
--
-- 0002 pins the window at exactly ten hours before and two hours after the reveal. That is
-- right for a real round and impossible for a demo one, whose whole purpose is a countdown a
-- reviewer will actually sit through. The first draft of this kept the constraint intact by
-- *sliding* the window — back-dating `reveals_at` by two hours so `scores_at` landed twenty
-- seconds out — and that was wrong in a way worth recording: `cannotGuessReason()` compares
-- `reveals_at` against the caller's `joined_at`, so a reviewer who signed in that same evening
-- was told they had joined after the reveal and refused the guess sheet. The constraint was
-- satisfied and the game was broken. Better to say plainly that a demo round has its own
-- window than to keep a shape that no longer means what it says.
--
-- The column is set by trigger rather than by the writer, so it cannot disagree with the
-- group: there is no path that inserts a round with the wrong value, including a hand-written
-- one in a psql session.

alter table public.rounds add column is_demo boolean not null default false;

comment on column public.rounds.is_demo is
  'Mirrors groups.is_demo, set by trigger. Exists so rounds_window can exempt a demo round '
  'from the fixed ten-hour/two-hour window it is otherwise pinned to.';

create or replace function public.rounds_inherit_is_demo() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select g.is_demo into new.is_demo from public.groups g where g.id = new.group_id;
  return new;
end $$;

create trigger rounds_inherit_is_demo_trg
  before insert on public.rounds
  for each row execute function public.rounds_inherit_is_demo();

-- Marking a group after its rounds already exist has to reach them too, or the group is a demo
-- group whose live round still carries a real round's constraint — and the first `demo_arm()`
-- against it fails a check nobody was looking at. Rare in production (`assign_pilot_cohort()`
-- sets the flag as the group is created, before any round exists) and routine in the Edge
-- Function tests, which is precisely the kind of gap worth closing in the schema rather than
-- in the caller.
--
-- Note that this fires in the other direction too: demoting a demo group whose round has a
-- compressed window will fail `rounds_window` rather than silently leaving an impossible row.
-- That is the intended answer to "can I turn this back?" — not while a round is mid-flight.
create or replace function public.groups_propagate_is_demo() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.rounds set is_demo = new.is_demo where group_id = new.id;
  return null;
end $$;

create trigger groups_propagate_is_demo_trg
  after update of is_demo on public.groups
  for each row when (new.is_demo is distinct from old.is_demo)
  execute function public.groups_propagate_is_demo();

update public.rounds r set is_demo = g.is_demo
  from public.groups g where g.id = r.group_id and g.is_demo;

alter table public.rounds drop constraint rounds_window;
alter table public.rounds add constraint rounds_window check (
  case when is_demo
    -- A demo round only has to make sense: open before reveal, reveal before score. The
    -- distances between them are whatever `demo_arm()` last set, which is the point.
    then opens_at <= reveals_at and reveals_at <= scores_at
    else scores_at = reveals_at + interval '2 hours'
         and opens_at = reveals_at - interval '10 hours'
  end);

-- ─── assign_pilot_cohort: carry the flag onto the group it creates ───────────
-- Forward-only replacement of the 20260813000000 definition. Identical but for the two
-- `is_demo` references — the advisory lock, the capacity selection and the invite-code retry
-- loop are unchanged, and their reasoning is documented at the original.

create or replace function public.assign_pilot_cohort(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cohort public.pilot_cohorts;
  v_group_id uuid;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  -- A single lock is intentional: pilot signup volume is tiny, while serialising selection
  -- prevents two signups from both taking the final seat or creating two backing groups.
  perform pg_advisory_xact_lock(hashtextextended('blind-drop-pilot-cohort-assignment', 0));

  select m.group_id into v_group_id
  from public.memberships m
  where m.user_id = p_user and m.left_at is null;
  if v_group_id is not null then
    return v_group_id;
  end if;

  select c.* into v_cohort
  from public.pilot_cohorts c
  where c.enabled
    and (
      c.group_id is null
      or (select count(*) from public.memberships m
          where m.group_id = c.group_id and m.left_at is null) < c.capacity
    )
  order by c.position
  limit 1
  for update;

  if not found then
    return null;
  end if;

  if v_cohort.group_id is null then
    loop
      select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1), '')
      into v_code
      from generate_series(1, 6);
      begin
        insert into public.groups (name, timezone, reveal_hour, invite_code, created_by, is_demo)
        values (btrim(v_cohort.name), v_cohort.timezone, v_cohort.reveal_hour, v_code, p_user,
                v_cohort.is_demo)
        returning id into v_group_id;
        exit;
      exception when unique_violation then
        -- Only an invite-code collision is possible while the advisory lock is held.
      end;
    end loop;

    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'admin');

    update public.pilot_cohorts
    set group_id = v_group_id, updated_at = now()
    where id = v_cohort.id;
  else
    v_group_id := v_cohort.group_id;
    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'member');
  end if;

  return v_group_id;
end $$;

revoke all on function public.assign_pilot_cohort(uuid) from public, anon, authenticated;
grant execute on function public.assign_pilot_cohort(uuid) to service_role;

-- ─── ensure_rounds: skip demo groups ─────────────────────────────────────────
-- Forward-only replacement of the 0004 definition. One clause added to the driving query;
-- read 0004's header for why the horizon is two days and why the offset is resolved per date.
--
-- A demo group gets its rounds from `demo_tick()` instead, which needs to control `local_date`
-- and the window directly. Leaving both functions free to insert would race them for the same
-- `(group_id, local_date)` unique key.

create or replace function public.ensure_rounds()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now   timestamptz := public.now_();
  v_group record;
  v_today date;
begin
  for v_group in
    select g.id, g.timezone, g.reveal_hour
      from public.groups g
     where not g.is_demo
     order by g.id          -- deterministic, so a warning in the log names a stable order
  loop
    begin
      v_today := pg_catalog.timezone(v_group.timezone, v_now)::date;

      insert into public.rounds
             (group_id, local_date, state, opens_at, reveals_at, scores_at)
      select v_group.id,
             d.local_date,
             'open',
             d.reveals_at - interval '10 hours',
             d.reveals_at,
             d.reveals_at + interval '2 hours'
        from (
          select t.ld as local_date,
                 pg_catalog.timezone(
                   v_group.timezone,
                   t.ld + pg_catalog.make_interval(hours => v_group.reveal_hour)) as reveals_at
            from pg_catalog.unnest(array[v_today, v_today + 1]) as t(ld)
        ) d
       where d.reveals_at > v_now
      on conflict (group_id, local_date) do nothing;

    exception when others then
      raise warning 'ensure_rounds: group % skipped (%): %',
                    v_group.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.ensure_rounds() is
  'Idempotently materialises today''s and tomorrow''s round for every non-demo group '
  '(docs/03 §4). Two days only, so the DST offset used is never stale; on conflict do '
  'nothing, so an existing round is never re-timed and a reveal_hour change lands on the '
  'first uncreated round. A group with an unusable timezone is skipped with a warning and the '
  'loop continues (docs/05 §6). Demo groups are materialised by demo_tick() instead.';

revoke all on function public.ensure_rounds() from public, anon, authenticated;
grant execute on function public.ensure_rounds() to service_role;

-- ─── the shuffle, extracted ──────────────────────────────────────────────────
-- Lifted verbatim out of `tick_rounds()` (0015) so that `demo_tick()` can reveal a round
-- without a second copy of it. Two implementations would mean `tests/db/shuffle.sql` — which
-- owns the statistical proof in E03-04 — proving only one of them.
--
-- Deterministic Fisher-Yates seeded on the round id: the same round always shuffles the same
-- way, which is what makes a reveal replayable and the test suite able to assert a specific
-- order. The stored `card_order` remains the authority regardless (docs/02 §2).

create or replace function public.shuffle_submissions(p_round_id uuid)
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order  uuid[];
  v_swap   uuid;
  v_seed   bigint;
  v_digest text;
  v_i      int;
  v_j      int;
begin
  select array_agg(s.id order by s.created_at, s.id)
    into v_order
    from public.submissions s
   where s.round_id = p_round_id;

  if v_order is null then
    return null;
  end if;

  v_seed := pg_catalog.hashtext(p_round_id::text)::bigint;
  for v_i in reverse pg_catalog.array_length(v_order, 1)..2 loop
    v_digest := pg_catalog.md5(v_seed::text || ':' || v_i::text);
    v_j := (
      (('x' || pg_catalog.substr(v_digest, 1, 8))::bit(32)::bigint % v_i) + 1
    )::int;
    v_swap := v_order[v_i];
    v_order[v_i] := v_order[v_j];
    v_order[v_j] := v_swap;
  end loop;

  return v_order;
end $$;

comment on function public.shuffle_submissions(uuid) is
  'The round''s submission ids in reveal order: deterministic Fisher-Yates seeded on the '
  'round id (docs/02 §2, tasks/E03-04). Null when the round has no submissions. The single '
  'implementation behind both tick_rounds() and demo_tick().';

revoke all on function public.shuffle_submissions(uuid) from public, anon, authenticated;

-- ─── tick_rounds: skip demo groups ───────────────────────────────────────────
-- Forward-only replacement of the 0015 definition. Each of the three loops gains the same
-- `exists` clause; everything else — the subtransaction per round, the Fisher-Yates, the
-- reveal-before-score-before-nudge ordering after an outage — is unchanged from 0015, whose
-- header explains all three.
--
-- The clause is an `exists` against `groups` rather than a join so that `rounds_pending_tick`
-- still drives the scan. Demo groups number one; this filters a handful of rows at most.

create or replace function public.tick_rounds()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now          timestamptz := public.now_();
  v_round        record;
  v_submitters   int;
  v_audience     jsonb;
  v_order        uuid[];
  v_updated      int;
begin
  perform public.ensure_rounds();

  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at <= v_now
       and exists (select 1 from public.groups g where g.id = r.group_id and not g.is_demo)
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select count(*)::int
        into v_submitters
        from public.submissions s
       where s.round_id = v_round.id;

      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb)
        into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id
         and m.left_at is null;

      if v_submitters < 3 then
        update public.rounds
           set state = 'voided'
         where id = v_round.id
           and state = 'open';
        get diagnostics v_updated = row_count;

        if v_updated = 1 then
          insert into public.notification_outbox
                 (round_id, kind, audience, enqueued_at)
          values (v_round.id, 'void', v_audience, v_now)
          on conflict (round_id, kind) do nothing;
        end if;
      else
        v_order := public.shuffle_submissions(v_round.id);

        update public.rounds
           set state = 'revealed',
               card_order = pg_catalog.to_jsonb(v_order)
         where id = v_round.id
           and state = 'open';
        get diagnostics v_updated = row_count;

        if v_updated = 1 then
          insert into public.notification_outbox
                 (round_id, kind, audience, enqueued_at)
          values (v_round.id, 'reveal', v_audience, v_now)
          on conflict (round_id, kind) do nothing;
        end if;
      end if;
    exception when others then
      raise warning 'tick_rounds reveal: round % skipped (%): %',
                    v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'revealed'
       and r.reveals_at <= v_now - interval '2 hours'
       and exists (select 1 from public.groups g where g.id = r.group_id and not g.is_demo)
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(participant.user_id order by participant.user_id), '[]'::jsonb)
        into v_audience
        from (
          select s.user_id
            from public.submissions s
           where s.round_id = v_round.id
          union
          select g.guesser_id
            from public.guesses g
           where g.round_id = v_round.id
        ) participant
       where exists (
         select 1 from auth.users u where u.id = participant.user_id
       );

      update public.rounds
         set state = 'scored'
       where id = v_round.id
         and state = 'revealed';
      get diagnostics v_updated = row_count;

      if v_updated = 1 then
        insert into public.notification_outbox
               (round_id, kind, audience, enqueued_at)
        values (v_round.id, 'results', v_audience, v_now)
        on conflict (round_id, kind) do nothing;
      end if;
    exception when others then
      raise warning 'tick_rounds score: round % skipped (%): %',
                    v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at > v_now
       and r.reveals_at <= v_now + interval '2 hours'
       and exists (select 1 from public.groups g where g.id = r.group_id and not g.is_demo)
       and not exists (
         select 1
           from public.notification_outbox o
          where o.round_id = r.id
            and o.kind = 'nudge'
       )
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb)
        into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id
         and m.left_at is null
         and not exists (
           select 1
             from public.submissions s
            where s.round_id = v_round.id
              and s.user_id = m.user_id
         );

      insert into public.notification_outbox
             (round_id, kind, audience, enqueued_at)
      values (v_round.id, 'nudge', v_audience, v_now)
      on conflict (round_id, kind) do nothing;
    exception when others then
      raise warning 'tick_rounds nudge: round % skipped (%): %',
                    v_round.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.tick_rounds() is
  'Ensures rounds, advances due non-demo rounds through reveal/void and score, and freezes '
  'one non-submitter nudge audience per open round. Every transition and matching outbox '
  'insert is atomic, guarded, and idempotent (docs/02 §2, docs/05 §2-3). Demo groups are '
  'skipped entirely — their rounds belong to demo_tick().';

revoke all on function public.tick_rounds() from public, anon, authenticated;
grant execute on function public.tick_rounds() to service_role;
