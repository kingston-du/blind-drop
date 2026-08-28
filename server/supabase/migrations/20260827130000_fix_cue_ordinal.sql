-- 20260827130000_fix_cue_ordinal.sql — fixes a permanent off-by-one in `ensure_rounds()`'s
-- ordinal computation, found reviewing E35-02/03. docs/18-CUES.md §3, tasks/E35-cues.md.
--
-- `20260827120000_cues.sql`'s `ensure_rounds()` computed each candidate round's ordinal `n` as
-- `v_n + row_number() over (order by local_date) - 1`, where `v_n` was a single `count(*)` over
-- the group's existing rounds taken once per invocation, and `row_number()` ran over *both*
-- candidates in the two-day window (today, tomorrow), regardless of whether today's row already
-- existed. On every tick that runs before today's own reveal — which, given `reveal_hour` is
-- always somewhere in the evening, is most of every day — today is both an existing row *and* a
-- counted candidate, so `v_n` already includes it and `row_number()` counts it a second time.
-- The result: the very first time a circle's third round is inserted (the first tick that finds
-- today already materialised), its `n` comes out one higher than its true position, and every
-- round after it inherits the same permanent +1.
--
-- **A first attempt at this fix (superseded within this same migration during review) replaced
-- the batch `row_number()` with a plain correlated `count(*) from rounds where local_date <
-- d.local_date`** — matching `rewrite_open_round_cues()`. That is correct once at least one of
-- the two candidates already exists as a committed row, but a fresh circle's *very first* tick
-- inserts today and tomorrow together, in the same `INSERT … SELECT`, and neither is a committed
-- row yet: Postgres evaluates every row of one statement against the same snapshot, so the
-- correlated subquery for tomorrow's candidate cannot see today's candidate row being inserted
-- alongside it in the same statement. Both landed on `n=0` — a duplicate cue on the group's
-- first two nights, caught by `tests/db/cues.sql`'s "cadence 2 cues exactly one of two
-- consecutive nights" and the new rollover test both regressing.
--
-- The fix below counts two things and adds them: `existing_before`, a correlated count against
-- the *committed* table (exactly what `rewrite_open_round_cues()` already does, so the two
-- functions still agree whenever a row is already committed), plus `new_before`, a count of
-- *other candidates in the same batch* whose local_date is earlier and who are not already a
-- committed row — i.e. candidates about to be inserted by this very statement ahead of this one.
-- Since the candidate window is only ever {today, tomorrow}, `new_before` is 0 or 1.

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
    select g.id, g.timezone, g.reveal_hour, g.cue_cadence
      from public.groups g
     where not g.is_demo
     order by g.id
  loop
    begin
      v_today := pg_catalog.timezone(v_group.timezone, v_now)::date;

      with candidates as (
        select t.ld as local_date,
               pg_catalog.timezone(
                 v_group.timezone,
                 t.ld + pg_catalog.make_interval(hours => v_group.reveal_hour)) as reveals_at
          from pg_catalog.unnest(array[v_today, v_today + 1]) as t(ld)
      ),
      future_candidates as (
        select * from candidates where reveals_at > v_now
      ),
      ordinals as (
        select fc.local_date,
               fc.reveals_at,
               -- Rounds already committed for this circle with an earlier local_date — the
               -- same count `rewrite_open_round_cues()` uses.
               (select pg_catalog.count(*)::int
                  from public.rounds r2
                 where r2.group_id = v_group.id
                   and r2.local_date < fc.local_date) as existing_before,
               -- Other candidates in *this* batch, earlier still, that are not already a
               -- committed row — i.e. about to be inserted by this same statement ahead of
               -- this one, and therefore invisible to the correlated count above.
               (select pg_catalog.count(*)::int
                  from future_candidates fc2
                 where fc2.local_date < fc.local_date
                   and not exists (
                     select 1 from public.rounds r3
                      where r3.group_id = v_group.id
                        and r3.local_date = fc2.local_date
                   )) as new_before
          from future_candidates fc
      )
      insert into public.rounds
             (group_id, local_date, state, opens_at, reveals_at, scores_at, prompt_key, prompt)
      select v_group.id,
             o.local_date,
             'open',
             o.reveals_at - interval '10 hours',
             o.reveals_at,
             o.reveals_at + interval '2 hours',
             cue.prompt_key,
             cue.prompt
        from ordinals o
        cross join lateral public.cue_for_round(
          v_group.id, o.existing_before + o.new_before, v_group.cue_cadence) as cue
      on conflict (group_id, local_date) do nothing;

    exception when others then
      raise warning 'ensure_rounds: group % skipped (%): %',
                    v_group.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.ensure_rounds() is
  'Idempotently materialises today''s and tomorrow''s round for every non-demo group '
  '(docs/03 §4), assigning each round its cue per docs/18-CUES.md §3 when the circle''s '
  'cadence is on. Two days only, so the DST offset used is never stale; on conflict do '
  'nothing, so an existing round is never re-timed and a reveal_hour change lands on the '
  'first uncreated round. Each candidate''s cue ordinal is existing_before (committed rows '
  'with an earlier local_date) plus new_before (earlier same-batch candidates not yet '
  'committed) — see 20260827130000''s comment for why the plain correlated count it replaced '
  'still undercounted a fresh circle''s first two rounds, inserted together in one statement. '
  'Demo groups are materialised by demo_tick() instead.';

revoke all on function public.ensure_rounds() from public, anon, authenticated;
grant execute on function public.ensure_rounds() to service_role;
