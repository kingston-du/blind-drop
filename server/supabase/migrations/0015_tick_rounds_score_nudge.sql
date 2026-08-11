-- 0015_tick_rounds_score_nudge.sql — tasks/E03-03, docs/02 §2, docs/05 §3.
--
-- Forward-only replacement of tick_rounds(): 0013 remains the migration that introduced
-- reveal/void. This version keeps that branch intact, then processes scoring before nudges.
-- That order matters after an outage: a tick at 23:00 advances open -> revealed -> scored
-- without also sending an already-expired nudge.

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
  v_swap         uuid;
  v_seed         bigint;
  v_digest       text;
  v_i            int;
  v_j            int;
  v_updated      int;
begin
  perform public.ensure_rounds();

  -- First, every due open round reveals or voids. Each loop body is a subtransaction so one
  -- malformed round is retried next minute without stopping every other group.
  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at <= v_now
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
        select array_agg(s.id order by s.created_at, s.id)
          into v_order
          from public.submissions s
         where s.round_id = v_round.id;

        -- Deterministic Fisher-Yates. The stored order remains authoritative; E03-04 owns
        -- the statistical proof, while this branch owns generating it exactly once.
        v_seed := pg_catalog.hashtext(v_round.id::text)::bigint;
        for v_i in reverse pg_catalog.array_length(v_order, 1)..2 loop
          v_digest := pg_catalog.md5(v_seed::text || ':' || v_i::text);
          v_j := (
            (('x' || pg_catalog.substr(v_digest, 1, 8))::bit(32)::bigint % v_i) + 1
          )::int;
          v_swap := v_order[v_i];
          v_order[v_i] := v_order[v_j];
          v_order[v_j] := v_swap;
        end loop;

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

  -- A scores_at deadline is always reveals_at + 2h (rounds_window), so spelling this in
  -- terms of reveals_at lets rounds_pending_tick satisfy both lifecycle scans.
  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'revealed'
       and r.reveals_at <= v_now - interval '2 hours'
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      -- Only live principals who participated receive results. Submission and guess ids are
      -- unioned explicitly even though the guess invariant currently requires a submission;
      -- that keeps the notification rule independent of that implementation detail.
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

  -- Nudge last. A late tick must reveal/void rather than enqueue a reminder whose deadline
  -- has passed. The audience is resolved once and stored; it is deliberately never revised
  -- when someone submits a few minutes later.
  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at > v_now
       and r.reveals_at <= v_now + interval '2 hours'
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
  'Ensures rounds, advances due rounds through reveal/void and score, and freezes one '
  'non-submitter nudge audience per open round. Every transition and matching outbox insert '
  'is atomic, guarded, and idempotent (docs/02 §2, docs/05 §2-3).';

revoke all on function public.tick_rounds() from public, anon, authenticated;
grant execute on function public.tick_rounds() to service_role;
