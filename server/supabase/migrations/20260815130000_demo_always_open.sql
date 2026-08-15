-- 20260815130000_demo_always_open.sql — a demo round has to be droppable the instant it
-- exists, at any hour. `opens_at` said otherwise.
--
-- `demo_tick()` gave every demo round the *real* `opens_at` — ten hours before its real
-- `reveals_at`, i.e. 10:00 local for the default 20:00 reveal hour. `RoundContext.isBeforeOpen`
-- (`ios/…/Round/RoundStore.swift`) reads that against the client's clock and, before it,
-- `SubmitScreen` renders the dark-hours "closed" copy and blocks the search flow entirely —
-- correct behaviour for a real group, and exactly backwards for one whose entire purpose is
-- being playable "no matter the time" (docs/02 §6). A reviewer opening the app at 1:00 AM saw
-- "Tonight's round is done. The next one opens at 10:00 AM." and could not drop a song — caught
-- live against the hosted project, the account signed in and blocked by its own fixture.
--
-- The fix touches only `opens_at`, and only while a demo round has not yet been dropped into.
-- `reveals_at`/`scores_at` keep carrying the real schedule pre-submission (docs/02 §6: "Before
-- the reviewer drops... indistinguishable from production") — that property was correct and
-- stays. `opens_at` is pinned to `least(<real opens_at>, now_())` at the two moments `demo_tick`
-- writes it (the roll, and the "room incomplete, slide to next reveal" branch), so it is never
-- in the future: `isBeforeOpen` is false from the instant the round exists, unconditionally.
-- `rounds_window`'s demo clause only asks `opens_at <= reveals_at <= scores_at`, which
-- `least(x, now_()) <= x` preserves trivially.
--
-- `demo_arm()` (called after a drop) already computes its own past `opens_at` and is untouched.

create or replace function public.demo_tick(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz        text;
  v_hour      int;
  v_now       timestamptz;
  v_today     date;
  v_round     record;
  v_order     uuid[];
  v_reveals   timestamptz;
  v_finished  uuid;
  v_carry     uuid;
  v_date      date;
  v_rounds    int;
begin
  select g.timezone, g.reveal_hour into v_tz, v_hour
    from public.groups g
   where g.id = p_group_id and g.is_demo;
  if not found then
    return;
  end if;

  -- Per group, not global: two concurrent reads from the same device must not both roll.
  perform pg_advisory_xact_lock(
    hashtextextended('blind-drop-demo-tick:' || p_group_id::text, 0));

  v_now   := public.now_();
  v_today := pg_catalog.timezone(v_tz, v_now)::date;

  -- ── 1. score ───────────────────────────────────────────────────────────────
  update public.rounds
     set state = 'scored'
   where group_id = p_group_id
     and state = 'revealed'
     and scores_at <= v_now;

  -- ── 2. reveal ──────────────────────────────────────────────────────────────
  for v_round in
    select r.id
      from public.rounds r
     where r.group_id = p_group_id
       and r.state = 'open'
       and r.reveals_at <= v_now
     order by r.reveals_at, r.id
     for update
  loop
    if exists (
      select 1
        from public.memberships m
       where m.group_id = p_group_id
         and m.left_at is null
         and not exists (
           select 1 from public.submissions s
            where s.round_id = v_round.id and s.user_id = m.user_id
         )
    ) then
      -- The room is incomplete: this is the real 20:00 arriving on a round nobody played,
      -- not an armed reveal. Slide to the next one rather than revealing a partial round or
      -- voiding — a demo round never voids. `opens_at` is pinned to `now_()`, not the real
      -- ten-hours-before-reveal offset: this round was already open and droppable, and sliding
      -- its reveal a day forward must not put it back behind a dark-hours gate.
      v_reveals := public.demo_next_reveal(v_tz, v_hour, v_now);
      update public.rounds
         set reveals_at = v_reveals,
             opens_at   = least(v_reveals - interval '10 hours', v_now),
             scores_at  = v_reveals + interval '2 hours'
       where id = v_round.id;
    else
      v_order := public.shuffle_submissions(v_round.id);
      update public.rounds
         set state = 'revealed',
             card_order = pg_catalog.to_jsonb(v_order)
       where id = v_round.id
         and state = 'open';
    end if;
  end loop;

  -- ── 3. roll ────────────────────────────────────────────────────────────────
  -- Either there is no round for today at all — the reviewer's first visit, or their first
  -- visit on a later day — or today's round finished at least two minutes ago and they are
  -- ready to go around again. The two-minute settle keeps a results screen from being pulled
  -- out from under someone who is still reading it.
  if not exists (
    select 1 from public.rounds r
     where r.group_id = p_group_id and r.local_date = v_today
  ) then
    -- Midnight arrived while a round was still unplayed. That round is not history and it is
    -- not spent — it is the round this reviewer is in the middle of — so it moves to today
    -- rather than being abandoned there and replaced. Without this, a session that straddles
    -- local midnight would strand an open round that `demo_tick()` then re-anchors nightly
    -- for ever, and lose the companion submissions already in it.
    select r.id into v_carry
      from public.rounds r
     where r.group_id = p_group_id
       and r.state in ('open', 'revealed')
       and r.local_date < v_today
     order by r.local_date desc
     limit 1;

    if v_carry is not null then
      update public.rounds set local_date = v_today where id = v_carry;
      return;
    end if;
  end if;

  select r.id into v_finished
    from public.rounds r
   where r.group_id = p_group_id
     and r.local_date = v_today
     and (
       (r.state = 'scored' and r.scores_at <= v_now - interval '2 minutes')
       or r.state = 'voided'
     );

  if v_finished is null and exists (
    select 1 from public.rounds r
     where r.group_id = p_group_id and r.local_date = v_today
  ) then
    return;   -- today's round is live; nothing to roll
  end if;

  -- Make room at today's date. Every earlier round shifts back one day, oldest first so each
  -- move lands on a date the row below has just vacated and `rounds_group_date` is never
  -- violated; the finished round then takes yesterday. The Record reads newest-first, so this
  -- keeps the finished night at the top of it rather than burying it under the fixtures.
  if v_finished is not null then
    for v_date in
      select r.local_date
        from public.rounds r
       where r.group_id = p_group_id and r.local_date < v_today
       order by r.local_date
    loop
      update public.rounds
         set local_date = v_date - 1
       where group_id = p_group_id and local_date = v_date;
    end loop;

    update public.rounds set local_date = v_today - 1 where id = v_finished;
  end if;

  select count(*)::int into v_rounds
    from public.rounds r where r.group_id = p_group_id;

  v_reveals := public.demo_next_reveal(v_tz, v_hour, v_now);
  -- Pinned to `now_()`, not the real ten-hours-before-reveal offset — see the migration header.
  insert into public.rounds (group_id, local_date, state, opens_at, reveals_at, scores_at)
  values (p_group_id, v_today, 'open',
          least(v_reveals - interval '10 hours', v_now), v_reveals, v_reveals + interval '2 hours')
  on conflict (group_id, local_date) do nothing;

  perform public.demo_seed_companion_submissions(
    (select r.id from public.rounds r
      where r.group_id = p_group_id and r.local_date = v_today),
    v_rounds);
end $$;

comment on function public.demo_tick(uuid) is
  'Advances a demo group''s round: scores a revealed round whose window has run out, reveals '
  'an open one once every member has submitted, and rolls a fresh round two minutes after the '
  'last one scored. opens_at is always now_() or earlier, so a demo round is droppable the '
  'instant it exists regardless of the hour. Never voids and never writes '
  'notification_outbox. A no-op on any group that is not a demo group.';

revoke all on function public.demo_tick(uuid) from public, anon, authenticated;
grant execute on function public.demo_tick(uuid) to service_role;

-- ─── heal what is already live ────────────────────────────────────────────────
-- The bug above is not hypothetical — it is the state of the hosted App Review group right
-- now, caught by the reviewer signing in and being blocked. Every open demo round whose
-- `opens_at` is still in the future is pulled back to now, immediately, so nothing has to wait
-- for a `demo_tick()` call that would not otherwise touch it (the reveal-phase slide branch
-- above only fires once `reveals_at` has passed, which for an unblocked round hours from its
-- real reveal is not yet). `rounds_window`'s demo clause tolerates this: `opens_at` only ever
-- moves earlier here, and `reveals_at` is untouched.
update public.rounds
   set opens_at = now()
 where is_demo
   and state = 'open'
   and opens_at > now();
