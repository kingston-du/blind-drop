-- idempotency.sql — tasks/E03-06, docs/05 §2 and §6, AC-3/AC-4.
begin;
set search_path = public, extensions, tests;
create extension if not exists dblink with schema extensions;
select plan(29);

select has_extension('dblink', 'dblink is available for the two-session concurrency proof');

-- ─── two workers, one locked round ──────────────────────────────────────────
-- The fixture is committed through worker B so both worker transactions can see it. Worker
-- A locks the row, starts tick_rounds asynchronously, and keeps its transaction open. Worker
-- B must complete its own tick by skipping that row; only A's later commit becomes visible.
select dblink_connect('e306_worker_a',
       'host=supabase_db_blind-drop port=5432 dbname=postgres user=postgres password=postgres');
select dblink_connect('e306_worker_b',
       'host=supabase_db_blind-drop port=5432 dbname=postgres user=postgres password=postgres');

select dblink_exec('e306_worker_b', $remote$
  insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
  values ('e3060000-0000-4000-8000-000000000010', 'Concurrency fixture', 'UTC', 20,
          'CNCR26', 'a0000000-0000-4000-8000-000000000001')
$remote$);
select dblink_exec('e306_worker_b', $remote$
  insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
  values
    ('e3060000-0000-4000-8000-000000000011',
     'e3060000-0000-4000-8000-000000000010', date '2026-08-09', 'open',
     '2026-08-09T10:00:00Z', '2026-08-09T20:00:00Z', '2026-08-09T22:00:00Z'),
    -- Pre-materialise tomorrow too. Otherwise both workers legitimately contend inside
    -- ensure_rounds() before reaching the SKIP LOCKED lifecycle selector.
    ('e3060000-0000-4000-8000-000000000012',
     'e3060000-0000-4000-8000-000000000010', date '2026-08-10', 'open',
     '2026-08-10T10:00:00Z', '2026-08-10T20:00:00Z', '2026-08-10T22:00:00Z')
$remote$);
select dblink_exec('e306_worker_b', $remote$
  insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
  values
    ('e3060000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000001',
     'isrc:E306CONCUR01','{}','2026-08-09T12:00:00Z'),
    ('e3060000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000002',
     'isrc:E306CONCUR02','{}','2026-08-09T13:00:00Z'),
    ('e3060000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000003',
     'isrc:E306CONCUR03','{}','2026-08-09T14:00:00Z')
$remote$);

select dblink_exec('e306_worker_a', $$set app.test_now = '2026-08-09T20:00:00Z'$$);
select dblink_exec('e306_worker_b', $$set app.test_now = '2026-08-09T20:00:00Z'$$);
select dblink_exec('e306_worker_a', 'begin');
select * from dblink('e306_worker_a', $remote$
  select id::text from public.rounds
   where id = 'e3060000-0000-4000-8000-000000000011'
   for update
$remote$) as locked(id text);

select is(dblink_send_query('e306_worker_a', 'select public.tick_rounds()::text'), 1,
          'worker A starts a tick while holding the due round lock');
select lives_ok($test$
  select * from dblink('e306_worker_b', 'select public.tick_rounds()::text') as t(result text)
$test$, 'worker B completes while worker A transaction still owns the row');
select is((select state from public.rounds
            where id = 'e3060000-0000-4000-8000-000000000011'),
          'open'::round_state, 'worker B skipped the locked round rather than waiting or moving it');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3060000-0000-4000-8000-000000000011'),
          0, 'worker B did not enqueue for the skipped round');
select * from dblink_get_result('e306_worker_a') as worker_a_result(result text);
-- libpq exposes a final empty result after an asynchronous query; drain it before issuing
-- COMMIT on the same connection.
select * from dblink_get_result('e306_worker_a') as worker_a_drained(result text);
select pass('worker A tick finishes in its still-open transaction');
select dblink_exec('e306_worker_a', 'commit');
select is((select state from public.rounds
            where id = 'e3060000-0000-4000-8000-000000000011'),
          'revealed'::round_state, 'worker A commit publishes the one transition');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3060000-0000-4000-8000-000000000011' and kind = 'reveal'),
          1, 'the concurrent workers leave exactly one reveal row');
select is((select jsonb_array_length(card_order) from public.rounds
            where id = 'e3060000-0000-4000-8000-000000000011'),
          3, 'the one winning transition stores the complete card order');

select dblink_exec('e306_worker_b', $remote$
  delete from public.groups where id = 'e3060000-0000-4000-8000-000000000010'
$remote$);
select dblink_disconnect('e306_worker_a');
select dblink_disconnect('e306_worker_b');

-- ─── three-hour outage catch-up and rollback atomicity ───────────────────────
insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values
  ('e3060000-0000-4000-8000-000000000021', tests.the_group(), date '2035-05-01', 'open',
   '2035-05-01T10:00:00Z', '2035-05-01T20:00:00Z', '2035-05-01T22:00:00Z'),
  ('e3060000-0000-4000-8000-000000000022', tests.the_group(), date '2035-05-02', 'open',
   '2035-05-02T10:00:00Z', '2035-05-02T20:00:00Z', '2035-05-02T22:00:00Z'),
  ('e3060000-0000-4000-8000-000000000023', tests.the_group(), date '2035-05-03', 'open',
   '2035-05-03T10:00:00Z', '2035-05-03T20:00:00Z', '2035-05-03T22:00:00Z');

insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
values
  ('e3060000-0000-4000-8000-000000000021',tests.person('Ana'),'isrc:E306OUTAGE01','{}','2035-05-01T12:00:00Z'),
  ('e3060000-0000-4000-8000-000000000021',tests.person('Ben'),'isrc:E306OUTAGE02','{}','2035-05-01T13:00:00Z'),
  ('e3060000-0000-4000-8000-000000000021',tests.person('Cal'),'isrc:E306OUTAGE03','{}','2035-05-01T14:00:00Z'),
  ('e3060000-0000-4000-8000-000000000022',tests.person('Dee'),'isrc:E306VOID001','{}','2035-05-02T12:00:00Z'),
  ('e3060000-0000-4000-8000-000000000022',tests.person('Fay'),'isrc:E306VOID002','{}','2035-05-02T13:00:00Z'),
  ('e3060000-0000-4000-8000-000000000023',tests.person('Ana'),'isrc:E306FAIL001','{}','2035-05-03T12:00:00Z'),
  ('e3060000-0000-4000-8000-000000000023',tests.person('Ben'),'isrc:E306FAIL002','{}','2035-05-03T13:00:00Z'),
  ('e3060000-0000-4000-8000-000000000023',tests.person('Cal'),'isrc:E306FAIL003','{}','2035-05-03T14:00:00Z');

select tests.set_test_now('2035-05-01T19:00:00Z');
select is((select count(*)::int from public.rounds
            where id in ('e3060000-0000-4000-8000-000000000021',
                         'e3060000-0000-4000-8000-000000000022',
                         'e3060000-0000-4000-8000-000000000023') and state = 'open'),
          3, 'at 19:00 all outage fixtures are still open');

-- No tick occurs at 20:00, 21:00, or 22:00. The next invocation is 23:00.
select tests.set_test_now('2035-05-01T23:00:00Z');
select lives_ok('select public.tick_rounds()', 'the first tick after a three-hour outage catches up');
select is((select state from public.rounds where id = 'e3060000-0000-4000-8000-000000000021'),
          'scored'::round_state, 'one invocation advances open through revealed to scored');
select is((select jsonb_array_length(card_order) from public.rounds
            where id = 'e3060000-0000-4000-8000-000000000021'),
          3, 'the intermediate reveal generated and retained its card order');
select set_eq(
  $$ select kind::text from public.notification_outbox
      where round_id = 'e3060000-0000-4000-8000-000000000021' $$,
  $$ values ('reveal'::text), ('results'::text) $$,
  'catch-up preserves both transition outbox rows exactly once');

select tests.set_test_now('2035-05-02T23:00:00Z');
select lives_ok('select public.tick_rounds()', 'the same outage path handles an underfilled round');
select is((select state from public.rounds where id = 'e3060000-0000-4000-8000-000000000022'),
          'voided'::round_state, 'two submitters void after the outage');
select is((select card_order from public.rounds where id = 'e3060000-0000-4000-8000-000000000022'),
          null::jsonb, 'the void outage path never creates a card order');
select set_eq(
  $$ select kind::text from public.notification_outbox
      where round_id = 'e3060000-0000-4000-8000-000000000022' $$,
  $$ values ('void'::text) $$,
  'the void outage path produces only one void notification');

create function pg_temp.fail_e306_outbox() returns trigger
language plpgsql as $$
begin
  if new.round_id = 'e3060000-0000-4000-8000-000000000023' and new.kind = 'reveal' then
    raise exception using errcode = 'E3060', message = 'forced failure after outbox insert';
  end if;
  return new;
end $$;
create trigger fail_e306_outbox_trg
  after insert on public.notification_outbox
  for each row execute function pg_temp.fail_e306_outbox();

select tests.set_test_now('2035-05-03T20:00:00Z');
select lives_ok('select public.tick_rounds()', 'a per-round outbox failure is isolated and retriable');
select is((select state from public.rounds where id = 'e3060000-0000-4000-8000-000000000023'),
          'open'::round_state, 'failure after the state update rolls the state back');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3060000-0000-4000-8000-000000000023'),
          0, 'the failed subtransaction leaves no partial outbox row');

drop trigger fail_e306_outbox_trg on public.notification_outbox;
select lives_ok('select public.tick_rounds()', 'the next tick retries the rolled-back round');
select is((select state from public.rounds where id = 'e3060000-0000-4000-8000-000000000023'),
          'revealed'::round_state, 'the retry performs the reveal once the fault is gone');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3060000-0000-4000-8000-000000000023' and kind = 'reveal'),
          1, 'the successful retry leaves exactly one reveal row');

select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten more ticks cannot duplicate any outage or retry side effect');
select is((select count(*)::int from public.notification_outbox
            where round_id in ('e3060000-0000-4000-8000-000000000021',
                               'e3060000-0000-4000-8000-000000000022',
                               'e3060000-0000-4000-8000-000000000023')),
          4, 'all repeated ticks leave the four expected transition rows');

-- ─── query-plan gate ────────────────────────────────────────────────────────
-- Populate enough pending rows for the normal planner to prefer the partial index. The
-- transaction rolls the rows back, and the final ANALYZE below restores table statistics.
insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select ('e3069000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       tests.the_group(), date '2060-01-01' + (n - 1), 'open',
       (date '2060-01-01' + (n - 1))::timestamp + interval '10 hours',
       (date '2060-01-01' + (n - 1))::timestamp + interval '20 hours',
       (date '2060-01-01' + (n - 1))::timestamp + interval '22 hours'
  from generate_series(1, 5000) n;
set constraints rounds_card_order_is_permutation_trg immediate;
analyze public.rounds;

create function pg_temp.explain_json(p_sql text) returns jsonb
language plpgsql as $$
declare v_plan json;
begin
  execute 'explain (format json) ' || p_sql into v_plan;
  return v_plan::jsonb;
end $$;

create temporary table e306_plans (name text primary key, plan jsonb not null);
insert into e306_plans values
('reveal', pg_temp.explain_json($query$
  select r.id, r.group_id from public.rounds r
   where r.state = 'open' and r.reveals_at <= '2059-12-31T18:00:00Z'
   order by r.reveals_at, r.id for update skip locked
$query$)),
('score', pg_temp.explain_json($query$
  select r.id, r.group_id from public.rounds r
   where r.state = 'revealed'
     and r.reveals_at <= '2059-12-31T18:00:00Z'::timestamptz - interval '2 hours'
   order by r.reveals_at, r.id for update skip locked
$query$)),
('nudge', pg_temp.explain_json($query$
  select r.id, r.group_id from public.rounds r
   where r.state = 'open'
     and r.reveals_at > '2060-01-01T18:00:00Z'
     and r.reveals_at <= '2060-01-01T18:00:00Z'::timestamptz + interval '2 hours'
     and not exists (select 1 from public.notification_outbox o
                      where o.round_id = r.id and o.kind = 'nudge')
   order by r.reveals_at, r.id for update skip locked
$query$));

select set_eq(
  $$ select name from e306_plans
      where jsonb_path_exists(plan, '$.** ? (@."Index Name" == "rounds_pending_tick")') $$,
  $$ values ('reveal'::text), ('score'::text), ('nudge'::text) $$,
  'every due-round selector uses rounds_pending_tick');
select is_empty($$
  select name from e306_plans
   where jsonb_path_exists(plan,
     '$.** ? (@."Node Type" == "Seq Scan" && @."Relation Name" == "rounds")')
$$, 'no lifecycle selector performs a sequential scan on rounds');
select is_empty($$
  select name from e306_plans
   where regexp_count(plan::text, '"Index Name": "rounds_pending_tick"') <> 1
$$, 'each lifecycle selector contains exactly one pending-round index scan');

select * from finish();
rollback;
analyze public.rounds;
