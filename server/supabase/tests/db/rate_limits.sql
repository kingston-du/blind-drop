-- rate_limits.sql — tasks/E02-01, E02-04. docs/04 §8, docs/14 §8.
--
-- The window slides by moving public.now_(), never by waiting (tasks/E01-05).
begin;
set search_path = public, extensions, tests;
select plan(12);

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

-- ─── and the client-facing roles cannot call it ──────────────────────────────
set local role authenticated;
select throws_ok(
  $$ select public.consume_rate_limit('x', 1, interval '1 hour') $$,
  '42501', null, 'authenticated cannot execute consume_rate_limit');
reset role;

select * from finish();
rollback;
