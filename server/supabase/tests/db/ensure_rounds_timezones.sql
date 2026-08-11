-- ensure_rounds_timezones.sql — tasks/E03-01, AC-3. docs/02 §1, docs/03 §4.
--
-- The filename carries two names on purpose: the epic's Verify command filters on
-- `ensure_rounds` and docs/15 §? names this file `timezones.sql`. One file satisfies both
-- (the runner matches on substring), and splitting it would mean E03-01's own DST assertions
-- do not run under E03-01's own Verify command.
--
-- Every block moves the clock with tests.set_test_now() and calls public.ensure_rounds()
-- again. set_test_now is transaction-local and this file is one transaction, so the clock
-- travels freely and no fixture is ever reloaded. There is no pg_sleep here or anywhere
-- (tasks/E01-05; the runner greps for it).
--
-- ensure_rounds() runs over *every* group in the database, including the seed group and
-- anything `npm run test:functions` left behind, so no assertion below counts rounds
-- globally. Each one is scoped to a named group id, and each group is created immediately
-- before the block that uses it — otherwise an earlier block's clock would have already
-- materialised the very dates that block is about to assert are absent.
begin;
set search_path = public, extensions, tests;
select plan(46);

-- The per-group `raise warning` from the invalid-timezone group is the point of §6 of
-- docs/05, but it lands on stderr once per ensure_rounds() call and the runner prints stderr
-- in red. Silence it: what this file actually asserts is the *consequence* — the broken
-- group gets no rounds and every group after it does.
set local client_min_messages = error;

-- ─── the function's own shape ────────────────────────────────────────────────
select has_function('public', 'ensure_rounds', 'ensure_rounds() exists');

select is(
  (select p.prosecdef from pg_proc p
    where p.proname = 'ensure_rounds' and p.pronamespace = 'public'::regnamespace),
  true, 'ensure_rounds() is security definer (docs/03 §4)');

select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p
    where p.proname = 'ensure_rounds' and p.pronamespace = 'public'::regnamespace),
  'ensure_rounds() pins an empty search_path — a definer function without one is an '
  'escalation hole');

-- 0003 turned on `force row level security` with no policies precisely so a definer function
-- owned by postgres cannot be an accidental bypass. The scheduler needs the bypass anyway,
-- and it gets it from the owner's BYPASSRLS bit. If that ever changes, ensure_rounds()
-- silently sees zero groups and creates nothing — a no-op, not an error. Assert it.
select ok(
  (select r.rolbypassrls from pg_proc p join pg_roles r on r.oid = p.proowner
    where p.proname = 'ensure_rounds' and p.pronamespace = 'public'::regnamespace),
  'the owner of ensure_rounds() can bypass RLS, so force RLS (0003) does not turn the '
  'scheduler into a silent no-op');

select ok(not has_function_privilege('anon', 'public.ensure_rounds()', 'execute'),
          'anon cannot call ensure_rounds()');
select ok(has_function_privilege('service_role', 'public.ensure_rounds()', 'execute'),
          'the service role can call ensure_rounds() — it creates rounds, it never advances one');

-- ─── fixture groups ──────────────────────────────────────────────────────────
-- No memberships: ensure_rounds() is a pure function of (group, clock) and never reads them,
-- and `memberships_one_active_per_user` would refuse to put a seeded profile in a second
-- group anyway. `created_by` has to be a real profile, so it is Ana's.
--
-- The ids are chosen so the broken group sorts BEFORE the others (the loop is `order by
-- g.id`). A group that only ever appeared last would prove nothing about the loop continuing.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e1000000-0000-4000-8000-000000000003','Vanished zone','Not/AZone',          20,'BRKN22', tests.person('Ana')),
  ('e1000000-0000-4000-8000-000000000005','Lord Howe',    'Australia/Lord_Howe',20,'HWEZ23', tests.person('Ana'));

-- ─── 1 · Australia/Lord_Howe, standard time (UTC+10:30) ──────────────────────
-- 00:30 local on 2026-08-11 — deliberately an instant where the group's local date is one
-- day ahead of UTC's, so a lazy `v_now::date` would fail here.
select tests.set_test_now('2026-08-11T00:00:00Z'::timestamptz);

select lives_ok('select public.ensure_rounds()',
                'a group whose timezone is not in tzdata does not abort the run (docs/05 §6)');

select throws_ok($$ select pg_catalog.timezone('Not/AZone', now()) $$, '22023', null,
  'and it is not silently benign either: that timezone genuinely raises, ensure_rounds() '
  'catches it per group');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000003')::int,
          0, 'the group with the unusable timezone got no rounds at all');

select bag_eq(
  $$ select local_date from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000005' $$,
  $$ values (date '2026-08-11'), (date '2026-08-12') $$,
  'the group sorted after the broken one still got today and tomorrow — the loop continues, '
  'and it materialises exactly two days');

select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11'),
          '2026-08-11T09:30:00Z'::timestamptz,
          'Lord Howe standard time is UTC+10:30, so 20:00 local is 09:30Z');

select is((select extract(minute from reveals_at)::int from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11'),
          30, 'a 30-minute zone offset survives the round trip');

select is((select timezone('Australia/Lord_Howe', reveals_at)::time from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11'),
          time '20:00', 'and read back through the zone it is reveal_hour:00 local');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and opens_at = reveals_at - interval '10 hours')::int,
          2, 'opens_at = reveals_at - 10h on both days (docs/02 §1)');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and scores_at = reveals_at + interval '2 hours')::int,
          2, 'scores_at = reveals_at + 2h on both days — the guess window is never wider');

-- The seed's rounds predate this clock by days. ensure_rounds() must not have looked at them.
select is((select state from public.rounds where id = tests.round_on('2026-08-08')),
          'scored'::round_state,
          'ensure_rounds() never advances a state — the seeded scored round is still scored');
select is((select reveals_at from public.rounds where id = tests.round_on('2026-08-08')),
          '2026-08-09T00:00:00Z'::timestamptz,
          'and it never re-times one either');

-- ─── 2 · Australia/Lord_Howe in its DST (UTC+11) ─────────────────────────────
-- Lord Howe shifts by 30 minutes, not an hour: +10:30 becomes +11:00.
select tests.set_test_now('2026-12-14T00:00:00Z'::timestamptz);
select lives_ok('select public.ensure_rounds()', 'the clock jumps four months, nothing breaks');

select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-12-14'),
          '2026-12-14T09:00:00Z'::timestamptz,
          'in Lord Howe DST the offset is UTC+11, so the same 20:00 local is 09:00Z');
select is((select timezone('Australia/Lord_Howe', reveals_at)::time from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-12-14'),
          time '20:00', 'still 20:00 local — the wall clock is what is fixed, not the offset');
select is((select extract(minute from reveals_at)::int from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000005'
              and local_date = date '2026-12-14'),
          0, 'and the half-hour has moved with the transition, which a stored offset could '
             'never do');

-- ─── 3 · America/New_York, spring forward ────────────────────────────────────
-- 2027-03-14 is the second Sunday in March: EST (UTC-5) becomes EDT (UTC-4) at 02:00. The
-- clock starts the day BEFORE, so the same group holds one round on each side of the
-- transition and the two must not share an offset.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e1000000-0000-4000-8000-000000000006','Spring forward','America/New_York',20,'SPRNG2',
        tests.person('Ana'));

select tests.set_test_now('2027-03-13T14:00:00Z'::timestamptz);
select lives_ok('select public.ensure_rounds()', 'the day before the spring-forward transition');

select bag_eq(
  $$ select local_date from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000006' $$,
  $$ values (date '2027-03-13'), (date '2027-03-14') $$,
  'a brand-new group gets today and tomorrow, and nothing further out');

select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000006'
              and local_date = date '2027-03-13'),
          '2027-03-14T01:00:00Z'::timestamptz,
          'the day before, New York is EST (UTC-5): 20:00 local is 01:00Z the next day');
select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000006'
              and local_date = date '2027-03-14'),
          '2027-03-15T00:00:00Z'::timestamptz,
          'on the spring-forward date it is EDT (UTC-4): 20:00 local is 00:00Z. One group, '
          'two consecutive rounds, two different offsets — this is the whole reason rounds '
          'are materialised two days out and no further');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000006'
              and timezone('America/New_York', reveals_at)::time = time '20:00')::int,
          2, 'both sides of the spring-forward transition reveal at 20:00 local');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000006'
              and opens_at = reveals_at - interval '10 hours'
              and scores_at = reveals_at + interval '2 hours')::int,
          2, 'and `rounds_window` still holds across the transition — which it would not if '
             'opens_at had been materialised as 10:00 local instead of reveals_at - 10h');

-- ─── 4 · America/New_York, fall back ─────────────────────────────────────────
-- 2027-11-07 is the first Sunday in November: EDT becomes EST at 02:00. The 25-hour day.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e1000000-0000-4000-8000-000000000007','Fall back','America/New_York',20,'FAB223',
        tests.person('Ana'));

select tests.set_test_now('2027-11-06T14:00:00Z'::timestamptz);
select lives_ok('select public.ensure_rounds()', 'the day before the fall-back transition');

select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000007'
              and local_date = date '2027-11-06'),
          '2027-11-07T00:00:00Z'::timestamptz,
          'the day before, New York is still EDT (UTC-4)');
select is((select reveals_at from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000007'
              and local_date = date '2027-11-07'),
          '2027-11-08T01:00:00Z'::timestamptz,
          'on the fall-back date it is EST (UTC-5) by 20:00, an hour later in UTC');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000007'
              and timezone('America/New_York', reveals_at)::time = time '20:00')::int,
          2, 'both sides of the fall-back transition reveal at 20:00 local');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000007'
              and opens_at = reveals_at - interval '10 hours'
              and scores_at = reveals_at + interval '2 hours')::int,
          2, '`rounds_window` holds on the 25-hour day too');

-- ─── 5 · idempotence, and where a reveal_hour change lands ───────────────────
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e1000000-0000-4000-8000-000000000008','The re-timers','America/New_York',20,'NYCTZ2',
        tests.person('Ana'));

select tests.set_test_now('2028-05-10T14:00:00Z'::timestamptz);   -- 10:00 in New York
select lives_ok('select public.ensure_rounds()', 'a fresh group at 10:00 local');

select bag_eq(
  $$ select local_date from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000008' $$,
  $$ values (date '2028-05-10'), (date '2028-05-11') $$,
  'today and tomorrow, exactly — never a third day, because the offset that far out is a guess');

select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000008'
              and state = 'open' and card_order is null)::int,
          2, 'a round is born open with no card_order (docs/02 §2)');

-- Snapshot every timing column, then run it again at the same instant.
create temporary table snap as
select id, local_date, opens_at, reveals_at, scores_at
  from public.rounds where group_id = 'e1000000-0000-4000-8000-000000000008';

select lives_ok('select public.ensure_rounds()', 'called twice at the same instant');
select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000008')::int,
          2, 'a second call at the same instant creates nothing — on conflict do nothing');
select bag_eq(
  $$ select id, local_date, opens_at, reveals_at, scores_at from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000008' $$,
  $$ select id, local_date, opens_at, reveals_at, scores_at from snap $$,
  'and it changes nothing about the rounds that already exist');

-- docs/02 §1: "Changing reveal_hour takes effect from the next round. It never mutates a
-- round that already exists." That rule is not enforced by the API — it falls out of
-- `on conflict (group_id, local_date) do nothing`, which is why it is tested here.
update public.groups set reveal_hour = 18
  where id = 'e1000000-0000-4000-8000-000000000008';
select lives_ok('select public.ensure_rounds()', 'reveal_hour moved from 20 to 18');

select bag_eq(
  $$ select id, local_date, opens_at, reveals_at, scores_at from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000008' $$,
  $$ select id, local_date, opens_at, reveals_at, scores_at from snap $$,
  'the two rounds that already existed are not re-timed — today does not move under the '
  'feet of someone who has already sealed a song');

-- Two days on: the first rounds the change could reach.
select tests.set_test_now('2028-05-12T14:00:00Z'::timestamptz);
select lives_ok('select public.ensure_rounds()', 'two days later');

select is((select timezone('America/New_York', reveals_at)::time from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000008'
              and local_date = date '2028-05-12'),
          time '18:00', 'the reveal_hour change lands on the first uncreated round');
select is((select timezone('America/New_York', reveals_at)::time from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000008'
              and local_date = date '2028-05-11'),
          time '20:00', 'while the round that already existed keeps the old hour');
select is((select count(*) from public.rounds
            where group_id = 'e1000000-0000-4000-8000-000000000008'
              and local_date >= date '2028-05-12'
              and opens_at = reveals_at - interval '10 hours'
              and scores_at = reveals_at + interval '2 hours')::int,
          2, 'the new window is still 10h before and 2h after — reveal_hour is the only knob '
             '(docs/02 §1)');

-- ─── 6 · a round whose reveal is already behind us is not created ────────────
-- See the open question in tasks/E03-round-lifecycle.md. 22:00 in New York: today's reveal
-- passed two hours ago, so only tomorrow is materialised.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e1000000-0000-4000-8000-000000000009','Late arrival','America/New_York',20,'ATE225',
        tests.person('Ana'));

select tests.set_test_now('2028-06-01T02:00:00Z'::timestamptz);   -- 22:00 on 05-31 in New York
select lives_ok('select public.ensure_rounds()', 'a group created after tonight''s reveal');

select bag_eq(
  $$ select local_date from public.rounds
      where group_id = 'e1000000-0000-4000-8000-000000000009' $$,
  $$ values (date '2028-06-01') $$,
  'today''s round is not born already past its own reveal — the group is in from tomorrow '
  '(docs/11 `reveal.blocked.joinedlate`)');

select * from finish();
rollback;
