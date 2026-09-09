-- retime_unopened_rounds.sql — docs/02 §1 (owner amendment, 2026-09-09), docs/03 §4.
--
-- The rule under test: a `reveal_hour` change reaches every round that has not yet opened, and
-- stops dead at one that has. Before the amendment a change waited for a round nobody had
-- created yet, which on `ensure_rounds()`'s two-day horizon meant an evening change took two
-- nights to land.
--
-- The clock travels with tests.set_test_now() and the file is one transaction, so no fixture is
-- ever reloaded and there is no pg_sleep anywhere (tasks/E01-05; the runner greps for it).
-- Every assertion is scoped to a named group id, because ensure_rounds() runs over every group
-- in the database including whatever `npm run test:functions` left behind.
begin;
set search_path = public, extensions, tests;
select plan(28);

-- ─── the function's own shape ────────────────────────────────────────────────
select has_function('public', 'retime_unopened_rounds', 'retime_unopened_rounds() exists');

select is(
  (select p.prosecdef from pg_proc p
    where p.proname = 'retime_unopened_rounds' and p.pronamespace = 'public'::regnamespace),
  true, 'retime_unopened_rounds() is security definer (docs/03 §4)');

select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p
    where p.proname = 'retime_unopened_rounds' and p.pronamespace = 'public'::regnamespace),
  'retime_unopened_rounds() pins an empty search_path');

select ok(not has_function_privilege(
            'anon', 'public.retime_unopened_rounds(uuid)', 'execute'),
          'anon cannot re-time anybody''s rounds');
select ok(not has_function_privilege(
            'authenticated', 'public.retime_unopened_rounds(uuid)', 'execute'),
          'nor can an authenticated member — the admin check lives in the Edge Function, and '
          'a member reaching the RPC directly would bypass it');
select ok(has_function_privilege(
            'service_role', 'public.retime_unopened_rounds(uuid)', 'execute'),
          'the service role can, which is how the PATCH path calls it');

-- ─── 1 · an evening change: today's round is open and stays put ──────────────
-- 14:00 EDT on 2026-08-11. A 20:00 round opened at 10:00 EDT, four hours ago.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e2000000-0000-4000-8000-000000000001','Evening change','America/New_York',20,'EVENT2',
   tests.person('Ana'));

select tests.set_test_now('2026-08-11T18:00:00Z'::timestamptz);
select public.ensure_rounds();

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001')::int,
          2, 'two rounds on the books: tonight''s, already open, and tomorrow''s');

select ok((select opens_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001'
              and local_date = date '2026-08-11') < public.now_(),
          'tonight''s round has opened — this is the one that must not move');

update public.groups set reveal_hour = 18
 where id = 'e2000000-0000-4000-8000-000000000001';

select is(
  public.retime_unopened_rounds('e2000000-0000-4000-8000-000000000001'),
  date '2026-08-12',
  'the change lands on tomorrow — the NEXT round, not the one after it');

select is((select reveals_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001'
              and local_date = date '2026-08-11'),
          '2026-08-12T00:00:00Z'::timestamptz,
          'tonight''s round still reveals at 20:00 local: somebody may have sealed against it');

select is((select timezone('America/New_York', reveals_at)::time from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001'
              and local_date = date '2026-08-12'),
          time '18:00', 'and tomorrow''s has moved to the new hour');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001'
              and opens_at = reveals_at - interval '10 hours'
              and scores_at = reveals_at + interval '2 hours')::int,
          2, 'the whole window moves with it, on both rounds (docs/02 §1)');

select is((select timezone('America/New_York', opens_at)::time from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000001'
              and local_date = date '2026-08-12'),
          time '08:00', 'an 18:00 reveal opens at 08:00 local');

-- ─── 2 · a morning change: nothing has opened, so tonight moves too ──────────
-- 08:00 EDT. A 20:00 round does not open until 10:00, so it is still fair game.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e2000000-0000-4000-8000-000000000002','Morning change','America/New_York',20,'MRNNG3',
   tests.person('Ana'));

select tests.set_test_now('2026-08-11T12:00:00Z'::timestamptz);
select public.ensure_rounds();

select ok((select opens_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000002'
              and local_date = date '2026-08-11') > public.now_(),
          'tonight''s round has not opened yet');

update public.groups set reveal_hour = 18
 where id = 'e2000000-0000-4000-8000-000000000002';

select is(
  public.retime_unopened_rounds('e2000000-0000-4000-8000-000000000002'),
  date '2026-08-11',
  'so the change lands tonight, and the settings screen has nothing to wait for');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000002'
              and timezone('America/New_York', reveals_at)::time = time '18:00')::int,
          2, 'both rounds are on the new hour');

-- ─── 2b · the boundary: moving the hour earlier can open the round at once ───
-- 10:59 EDT. A 21:00 round opens at 11:00 — one minute from now, so still fair game — and
-- 18:00 opens at 08:00, which is three hours gone. `rounds_window` (0002) requires
-- `opens_at = reveals_at - 10h` exactly, so there is no clamp available: the round opens
-- immediately and its drop window is eight hours instead of ten. Documented in the migration
-- header as the intended answer; asserted here so it stays a decision rather than a surprise.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e2000000-0000-4000-8000-000000000005','Boundary','America/New_York',21,'BNDRY6',
   tests.person('Ana'));

select tests.set_test_now('2026-08-11T14:59:00Z'::timestamptz);
select public.ensure_rounds();

select ok((select opens_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11') > public.now_(),
          'the round has not opened — by one minute, which is what makes it eligible');

update public.groups set reveal_hour = 18
 where id = 'e2000000-0000-4000-8000-000000000005';
select public.retime_unopened_rounds('e2000000-0000-4000-8000-000000000005');

select ok((select opens_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11') < public.now_(),
          'and now it has: 18:00 opens at 08:00, which is behind us');

select is((select state from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11')::text,
          'open', 'the round is open and taking songs, not stuck in some in-between state');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000005'
              and local_date = date '2026-08-11'
              and opens_at = reveals_at - interval '10 hours'
              and reveals_at > public.now_())::int,
          1, 'the window is still exactly ten hours wide and the reveal is still ahead — '
             'what shrank is how much of it is left, which is what moving a reveal earlier means');

-- ─── 3 · DST — the offset is per local date, not per group ───────────────────
-- 07:00 EST on 2026-03-07. Tomorrow, 2026-03-08, is the spring-forward date: the same
-- wall-clock hour is a different UTC instant on the two days, and re-timing has to know that.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e2000000-0000-4000-8000-000000000003','Spring forward','America/New_York',20,'SPRNG4',
   tests.person('Ana'));

select tests.set_test_now('2026-03-07T12:00:00Z'::timestamptz);
select public.ensure_rounds();

update public.groups set reveal_hour = 18
 where id = 'e2000000-0000-4000-8000-000000000003';
select public.retime_unopened_rounds('e2000000-0000-4000-8000-000000000003');

select is((select reveals_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000003'
              and local_date = date '2026-03-07'),
          '2026-03-07T23:00:00Z'::timestamptz,
          '18:00 EST (UTC-5) on the day before the transition');

select is((select reveals_at from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000003'
              and local_date = date '2026-03-08'),
          '2026-03-08T22:00:00Z'::timestamptz,
          '18:00 EDT (UTC-4) on the transition date itself — one hour earlier in UTC, the '
          'same hour on the wall');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000003'
              and timezone('America/New_York', reveals_at)::time = time '18:00')::int,
          2, 'read back through the zone, both are 18:00 local');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000003'
              and opens_at = reveals_at - interval '10 hours')::int,
          2, 'and the window is subtracted in UTC, which is what keeps rounds_window (0002) '
             'satisfied across the transition');

-- ─── 4 · a demo circle's clock is not ours to move ───────────────────────────
-- docs/02 §11: demo rounds advance on the reviewer's actions. `demo_tick()` owns reveals_at
-- there, and would overwrite anything written here on its next run.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by) values
  ('e2000000-0000-4000-8000-000000000004','Demo circle','America/New_York',20,'DMNCR5',
   tests.person('Ana'));

select tests.set_test_now('2026-08-11T12:00:00Z'::timestamptz);
select public.ensure_rounds();

update public.groups set is_demo = true, reveal_hour = 18
 where id = 'e2000000-0000-4000-8000-000000000004';

select is(
  public.retime_unopened_rounds('e2000000-0000-4000-8000-000000000004'),
  null::date,
  'a demo circle reports no effective date');

select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000004'
              and timezone('America/New_York', reveals_at)::time = time '20:00')::int,
          2, 'and its rounds are left exactly where demo_tick() put them');

-- ─── 5 · a group that does not exist ─────────────────────────────────────────
select is(
  public.retime_unopened_rounds('e2000000-0000-4000-8000-0000000000ff'),
  null::date,
  'an unknown group is null, not an exception — the caller has already 404''d by then');

-- ─── 6 · ensure_rounds() itself still refuses to re-time ─────────────────────
-- The conflict clause is about outage recovery, not about settings (docs/03 §4). Re-timing is
-- now a separate, explicit operation, and a late cron run must still not rewrite a clock.
select tests.set_test_now('2026-08-11T18:00:00Z'::timestamptz);
update public.groups set reveal_hour = 21
 where id = 'e2000000-0000-4000-8000-000000000002';
select public.ensure_rounds();

-- Scoped to the two dates this block is about. Blocks 3 and 4 moved the clock to March and
-- called ensure_rounds(), which runs over *every* group — so this group has rounds on four
-- dates by now, and a global count would be asserting the fixture, not the rule.
select is((select count(*) from public.rounds
            where group_id = 'e2000000-0000-4000-8000-000000000002'
              and local_date in (date '2026-08-11', date '2026-08-12')
              and timezone('America/New_York', reveals_at)::time = time '18:00')::int,
          2, 'ensure_rounds() left both rounds on 18:00 despite the column now saying 21 — '
             'only an admin''s explicit change re-times a round');

select * from finish();
rollback;
