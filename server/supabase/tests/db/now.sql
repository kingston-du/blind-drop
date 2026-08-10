-- now.sql — tasks/E01-05, AC-3. The time-travel indirection.
--
-- Every lifecycle function calls public.now_(). This is what lets the whole suite move the
-- clock instead of waiting, which is why there is no pg_sleep anywhere (the runner greps for
-- it and fails the run).
begin;
set search_path = public, extensions, tests;
select plan(8);

-- ─── falls back to now() when nothing is set ─────────────────────────────────
select tests.clear_test_now();
select ok(public.now_() is not null, 'now_() returns a time with no override set');
select cmp_ok(abs(extract(epoch from (public.now_() - now()))), '<', 1.0,
              'with no override, now_() is now()');

-- ─── honours app.test_now ────────────────────────────────────────────────────
select tests.set_test_now('2026-08-08T23:59:00Z'::timestamptz);
select is(public.now_(), '2026-08-08T23:59:00Z'::timestamptz,
          'now_() returns the overridden instant');
select ok(public.now_() < (select reveals_at from public.rounds where local_date = '2026-08-08'),
          'one minute before the reveal, now_() is still before reveals_at');

select tests.set_test_now('2026-08-09T00:00:00Z'::timestamptz);
select ok(public.now_() >= (select reveals_at from public.rounds where local_date = '2026-08-08'),
          'at 8:00 PM New York on 2026-08-08, now_() has reached reveals_at');

select tests.set_test_now('2029-01-01T00:00:00Z'::timestamptz);
select is(public.now_(), '2029-01-01T00:00:00Z'::timestamptz,
          'the clock travels years without complaint');

-- ─── an empty override is not a parse error ──────────────────────────────────
select tests.clear_test_now();
select cmp_ok(abs(extract(epoch from (public.now_() - now()))), '<', 1.0,
              'clearing the override falls back to now(), it does not fail');

-- ─── the function is stable and readable by the service role only ────────────
select is(
  (select provolatile::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'now_'),
  's', 'now_() is STABLE, so it is constant within a statement');

select * from finish();
rollback;
