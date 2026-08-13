-- rate_limits.sql — tasks/E02-01, E02-04. docs/04 §8, docs/14 §8.
--
-- The window slides by moving public.now_(), never by waiting (tasks/E01-05).
begin;
set search_path = public, extensions, tests;
create extension if not exists dblink with schema extensions;
select plan(19);

select has_function('public', 'consume_rate_limit',
       array['text','int','interval'], 'consume_rate_limit(text,int,interval) exists');

-- ─── the window admits exactly `limit` requests ──────────────────────────────
select tests.set_test_now('2026-08-10T12:00:00Z');

select is(public.consume_rate_limit('u:ana:join', 3, interval '1 hour'), 0, 'first is allowed');
select is(public.consume_rate_limit('u:ana:join', 3, interval '1 hour'), 0, 'second is allowed');
select is(public.consume_rate_limit('u:ana:join', 3, interval '1 hour'), 0, 'third is allowed');
select ok(public.consume_rate_limit('u:ana:join', 3, interval '1 hour') > 0,
          'the fourth inside the window is refused');

-- The refusal says how long to wait, and that is the age-out of the oldest event.
select is(public.consume_rate_limit('u:ana:join', 3, interval '1 hour'), 3600,
          'Retry-After is the seconds until the window frees up');

-- ─── a refusal does not itself consume the window ────────────────────────────
select is((select count(*)::int from public.rate_limit_events where bucket = 'u:ana:join'),
          3, 'a refused request is not recorded — being throttled cannot extend the block');

-- ─── the window really slides ────────────────────────────────────────────────
select tests.set_test_now('2026-08-10T12:59:59Z');
select ok(public.consume_rate_limit('u:ana:join', 3, interval '1 hour') > 0,
          'one second before the window frees up, still refused');

select tests.set_test_now('2026-08-10T13:00:01Z');
select is(public.consume_rate_limit('u:ana:join', 3, interval '1 hour'), 0,
          'once the oldest event ages out, the next request is allowed');
select is((select count(*)::int from public.rate_limit_events where bucket = 'u:ana:join'),
          1, 'aged-out rows are deleted, so the table tracks activity and not history');

-- ─── buckets are independent ─────────────────────────────────────────────────
-- Bucket keys are per user or per hashed IP and never per group (docs/14 §3): one member
-- hitting a limit must not be observable by another.
select is(public.consume_rate_limit('u:ben:join', 3, interval '1 hour'), 0,
          'a different user has their own window');

-- Activity in a different bucket clears an inactive bucket once its own expiry passes. This is
-- what bounds hashed-IP retention even when an address never sends another request.
insert into public.rate_limit_events (bucket, at, expires_at)
values ('ip:inactive', public.now_() - interval '2 hours', public.now_() - interval '1 hour');
select is(public.consume_rate_limit('u:cleanup', 3, interval '1 hour'), 0,
          'a request triggers global expiry cleanup');
select is((select count(*)::int from public.rate_limit_events where bucket = 'ip:inactive'),
          0, 'expired inactive buckets are deleted');

-- ─── concurrent calls cannot both pass the same last slot ───────────────────
select dblink_connect('rate_worker_a',
       'host=supabase_db_blind-drop port=5432 dbname=postgres user=postgres password=postgres');
select dblink_connect('rate_worker_b',
       'host=supabase_db_blind-drop port=5432 dbname=postgres user=postgres password=postgres');
select dblink_exec('rate_worker_a', $$set app.test_now = '2026-08-10T13:00:01Z'$$);
select dblink_exec('rate_worker_b', $$set app.test_now = '2026-08-10T13:00:01Z'$$);
select dblink_exec('rate_worker_a', 'begin');
select is((select result::int from dblink(
              'rate_worker_a',
              $$select public.consume_rate_limit('u:concurrent', 1, interval '1 hour')::text$$
            ) as t(result text)),
          0, 'worker A consumes the only slot inside its transaction');
select is(dblink_send_query(
            'rate_worker_b',
            $$select public.consume_rate_limit('u:concurrent', 1, interval '1 hour')::text$$),
          1, 'worker B starts a request for the same slot');
select is(dblink_is_busy('rate_worker_b'), 1,
          'worker B waits on the per-bucket transaction lock');
select dblink_exec('rate_worker_a', 'commit');
select ok((select result::int > 0
             from dblink_get_result('rate_worker_b') as t(result text)),
          'after worker A commits, worker B observes the full window and is refused');
select * from dblink_get_result('rate_worker_b') as drained(result text);
select is((select result::int from dblink(
              'rate_worker_b',
              $$select count(*)::text from public.rate_limit_events
                 where bucket = 'u:concurrent'$$
            ) as t(result text)),
          1, 'the two concurrent workers record exactly one event');
select dblink_exec('rate_worker_b',
                   $$delete from public.rate_limit_events where bucket = 'u:concurrent'$$);
select dblink_disconnect('rate_worker_a');
select dblink_disconnect('rate_worker_b');

-- ─── and the client-facing roles cannot call it ──────────────────────────────
set local role authenticated;
select throws_ok(
  $$ select public.consume_rate_limit('x', 1, interval '1 hour') $$,
  '42501', null, 'authenticated cannot execute consume_rate_limit');
reset role;

select * from finish();
rollback;
