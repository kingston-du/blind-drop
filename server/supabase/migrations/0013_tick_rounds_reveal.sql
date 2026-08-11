-- 0013_tick_rounds_reveal.sql — tasks/E03-02, docs/02 §2–3, docs/03 §4.
--
-- `0004_round_lifecycle.sql` was already applied when E03-01 landed. This forward-only
-- migration completes the next slice without rewriting migration history. E03-03 can
-- replace this function to add score/nudge branches; E03-04 adds the distribution proof for
-- the Fisher–Yates implementation already used here.
--
-- The function is SECURITY DEFINER because every game table forces RLS and has no policies.
-- An empty search path and fully-qualified names are mandatory for any definer function.

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
  -- docs/03 §4: round creation is part of the tick, not a third cron job.
  perform public.ensure_rounds();

  for v_round in
    select r.id, r.group_id
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at <= v_now
     order by r.reveals_at, r.id
     for update skip locked
  loop
    -- A block with an exception handler is a subtransaction. One malformed round therefore
    -- rolls back its own transition/outbox pair and is retried next minute without stopping
    -- every other group's reveal.
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
        -- Fisher–Yates over a stable input array. The deterministic stream starts at exactly
        -- hashtext(round_id::text), as docs/02 §2 requires. The stored array is authoritative;
        -- determinism exists only so E03-04 can prove and reproduce the shuffle.
        select array_agg(s.id order by s.created_at, s.id)
          into v_order
          from public.submissions s
         where s.round_id = v_round.id;

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
      raise warning 'tick_rounds: round % skipped (%): %',
                    v_round.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.tick_rounds() is
  'Advances due open rounds to voided (<3 submissions) or revealed (>=3), writing the '
  'matching notification outbox row atomically and idempotently (docs/03 §4). Calls '
  'ensure_rounds() first. E03-03 extends it with score and nudge branches.';

revoke all on function public.tick_rounds() from public, anon, authenticated;
grant execute on function public.tick_rounds() to service_role;
