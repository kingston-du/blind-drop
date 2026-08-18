-- circles.sql — tasks/E18-01, ADR-011. The circle cap replaces ADR-005's one-group index.
begin;
set search_path = public, extensions, tests;
select plan(7);

-- Ana already holds one active membership (The Cove, docs/02 §4.4 fixture). The cap is 3
-- (public.active_circle_cap()), so two more circles should succeed and a fourth should not.
create temporary table h as
select tests.person('Ana') as ana, tests.person('Ben') as ben;

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values
  ('c1800000-0000-4000-8000-0000000000a1', 'Ana''s second circle', 'UTC', 20, 'E9ANA2',
   (select ana from h)),
  ('c1800000-0000-4000-8000-0000000000a2', 'Ana''s third circle',  'UTC', 20, 'E9ANA3',
   (select ana from h)),
  ('c1800000-0000-4000-8000-0000000000a3', 'Ana''s fourth circle', 'UTC', 20, 'E9ANA4',
   (select ana from h));

select lives_ok(
  format($$ insert into public.memberships (group_id, user_id, role)
            values (%L, %L, 'member') $$,
         'c1800000-0000-4000-8000-0000000000a1', (select ana from h)),
  'a second active circle is allowed — Ana is under the cap');

select lives_ok(
  format($$ insert into public.memberships (group_id, user_id, role)
            values (%L, %L, 'member') $$,
         'c1800000-0000-4000-8000-0000000000a2', (select ana from h)),
  'a third active circle is allowed — Ana is now exactly at the cap');

select throws_ok(
  format($$ insert into public.memberships (group_id, user_id, role)
            values (%L, %L, 'member') $$,
         'c1800000-0000-4000-8000-0000000000a3', (select ana from h)),
  'BD002', null,
  'a fourth active circle is refused at the cap — the trigger, not a bare unique violation');

-- Leaving one frees a slot straight back up.
update public.memberships set left_at = now()
 where group_id = 'c1800000-0000-4000-8000-0000000000a1' and user_id = (select ana from h);
select lives_ok(
  format($$ insert into public.memberships (group_id, user_id, role)
            values (%L, %L, 'member') $$,
         'c1800000-0000-4000-8000-0000000000a3', (select ana from h)),
  'leaving a circle frees a slot for another');

-- `create_group()` runs the caller's own membership insert through the same trigger, so a
-- caller at the cap is refused there too, and with the same code.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values
  ('c1800000-0000-4000-8000-0000000000b1', 'Ben''s second circle', 'UTC', 20, 'E9BEN2',
   (select ben from h)),
  ('c1800000-0000-4000-8000-0000000000b2', 'Ben''s third circle',  'UTC', 20, 'E9BEN3',
   (select ben from h));
insert into public.memberships (group_id, user_id, role)
values
  ('c1800000-0000-4000-8000-0000000000b1', (select ben from h), 'member'),
  ('c1800000-0000-4000-8000-0000000000b2', (select ben from h), 'member');

select throws_ok(
  format($$ select public.create_group(%L, 'Ben''s fourth circle', 'UTC', 20, 'E9BEN4') $$,
         (select ben from h)),
  'BD002', null,
  'create_group() refuses a fourth circle at the cap, through the same trigger as join');

-- A no-op re-check: rejoining a circle already held is still the pair index (23505), not the
-- cap — the two failures stay distinguishable by SQLSTATE even though both begin at the
-- same "another row already exists" shape.
select throws_ok(
  format($$ insert into public.memberships (group_id, user_id, role)
            values (%L, %L, 'member') $$,
         'c1800000-0000-4000-8000-0000000000b1', (select ben from h)),
  '23505', null,
  'rejoining a circle already held fails the pair index, not the cap');

-- ADR-005's index really is gone.
select hasnt_index('public', 'memberships', 'memberships_one_active_per_user',
                   'memberships_one_active_per_user no longer exists');

select * from finish();
rollback;
