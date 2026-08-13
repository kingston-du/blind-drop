-- Code-free TestFlight enrollment is configurable and capacity-safe.
begin;
set search_path = public, extensions, tests;
select plan(10);

-- This suite exercises the generic rollover with one known row; release configuration adds a
-- dedicated review cohort in the following migration.
delete from public.pilot_cohorts where name = 'App Review';
update public.pilot_cohorts set position = 1 where name = 'Initial TestFlight';

insert into auth.users (id) values
  ('e1400000-0000-4000-8000-000000000001'),
  ('e1400000-0000-4000-8000-000000000002');
insert into public.profiles (id, display_name) values
  ('e1400000-0000-4000-8000-000000000001', 'Pilot One'),
  ('e1400000-0000-4000-8000-000000000002', 'Pilot Two');

select is(public.assign_pilot_cohort('e1400000-0000-4000-8000-000000000001'), null::uuid,
  'a disabled cohort is a no-op');

update public.pilot_cohorts set enabled = true, capacity = 1 where position = 1;
select isnt(public.assign_pilot_cohort('e1400000-0000-4000-8000-000000000001'), null::uuid,
  'the first profile is assigned when the cohort is enabled');
select is((select count(*)::int from public.groups where name = 'Initial TestFlight'), 1,
  'the first assignment creates exactly one backing group');
select is((select role from public.memberships where user_id = 'e1400000-0000-4000-8000-000000000001'),
  'admin', 'the first profile can administer the cohort group');
select is((select count(*)::int from public.memberships m join public.pilot_cohorts c
           on c.group_id = m.group_id where c.position = 1 and m.left_at is null), 1,
  'the active roster is at capacity');
select is(public.assign_pilot_cohort('e1400000-0000-4000-8000-000000000002'), null::uuid,
  'a full cohort does not over-enroll');

insert into public.pilot_cohorts
  (name, timezone, reveal_hour, capacity, position, enabled)
values ('Second TestFlight', 'America/Los_Angeles', 20, 12, 2, true);
select isnt(public.assign_pilot_cohort('e1400000-0000-4000-8000-000000000002'), null::uuid,
  'adding a second enabled cohort accepts the next profile without an app release');
select is((select role from public.memberships where user_id = 'e1400000-0000-4000-8000-000000000002'),
  'admin', 'the first profile in the second cohort is its admin');
select is((select count(*)::int from public.groups where name like '%TestFlight'), 2,
  'there is one backing group per claimed cohort');
select is(public.assign_pilot_cohort('e1400000-0000-4000-8000-000000000002'),
  (select group_id from public.pilot_cohorts where position = 2),
  'assignment is idempotent for an existing member');

select * from finish();
rollback;
