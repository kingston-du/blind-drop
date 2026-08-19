-- track_reuse.sql — tasks/E18-03, docs/02 §3, docs/14 §2.
--
-- With several circles, submitting the same track_key twice in one night stops being a
-- non-event: if a third person can see the reveal in both circles, the repeat itself narrows
-- who dropped it. `upsert_submission` (20260819090000) refuses only when that third person
-- exists — an active member of both circles, other than the submitter. No such person, no
-- refusal, exactly as within one circle (docs/02 §3, unchanged).
begin;
set search_path = public, extensions, tests;
select plan(9);

-- Ana starts this file already holding one active circle (`tests.the_group()`, the §4.4
-- fixture) and the cap is 3 — free it first so the three circles this file needs don't collide
-- with `enforce_circle_cap` (ADR-011). `circles.sql` covers the cap itself; this file is not
-- the place to re-prove it.
update public.memberships set left_at = now()
 where group_id = tests.the_group() and user_id = tests.person('Ana');

create temporary table h as
select tests.person('Ana') as ana, tests.person('Ben') as ben, tests.person('Cal') as cal;

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values
  ('e1803000-0000-4000-8000-000000000001', 'E18-03 West', 'UTC', 20, 'E9WEST', (select ana from h)),
  ('e1803000-0000-4000-8000-000000000002', 'E18-03 East', 'UTC', 20, 'E9EAST', (select ana from h)),
  ('e1803000-0000-4000-8000-000000000003', 'E18-03 North', 'UTC', 20, 'E9NRTH', (select ana from h));

-- West: Ana + Ben. East: Ana + Cal (no overlap with West besides Ana). North: Ana + Ben
-- (overlaps West, via Ben).
insert into public.memberships (group_id, user_id, role)
values
  ('e1803000-0000-4000-8000-000000000001', (select ana from h), 'admin'),
  ('e1803000-0000-4000-8000-000000000001', (select ben from h), 'member'),
  ('e1803000-0000-4000-8000-000000000002', (select ana from h), 'admin'),
  ('e1803000-0000-4000-8000-000000000002', (select cal from h), 'member'),
  ('e1803000-0000-4000-8000-000000000003', (select ana from h), 'admin'),
  ('e1803000-0000-4000-8000-000000000003', (select ben from h), 'member');

-- One round per circle for day 1, plus a second day for North to test the day boundary.
insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values
  ('e1803000-0000-4000-8000-0000000000a1', 'e1803000-0000-4000-8000-000000000001',
   date '2035-07-01', 'open', '2035-07-01T10:00:00Z', '2035-07-01T20:00:00Z', '2035-07-01T22:00:00Z'),
  ('e1803000-0000-4000-8000-0000000000a2', 'e1803000-0000-4000-8000-000000000002',
   date '2035-07-01', 'open', '2035-07-01T10:00:00Z', '2035-07-01T20:00:00Z', '2035-07-01T22:00:00Z'),
  ('e1803000-0000-4000-8000-0000000000a3', 'e1803000-0000-4000-8000-000000000003',
   date '2035-07-01', 'open', '2035-07-01T10:00:00Z', '2035-07-01T20:00:00Z', '2035-07-01T22:00:00Z'),
  ('e1803000-0000-4000-8000-0000000000a4', 'e1803000-0000-4000-8000-000000000003',
   date '2035-07-02', 'open', '2035-07-02T10:00:00Z', '2035-07-02T20:00:00Z', '2035-07-02T22:00:00Z');

-- Ana drops the same track in West.
select lives_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a1', (select ana from h)),
  'the first drop, in West, always succeeds');

-- East shares nobody with West but Ana (Ben is not in East, Cal is not in West): no overlap,
-- so the same track the same night is allowed, exactly as a duplicate always has been.
select lives_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a2', (select ana from h)),
  'no membership overlap — the same track in a second circle the same night is allowed');
select is((select count(*)::int from public.submissions
           where round_id = 'e1803000-0000-4000-8000-0000000000a2'),
          1, 'the East submission actually landed');

-- North shares Ben with West: Ben could read both reveals and line up the repeat. Refused.
select throws_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a3', (select ana from h)),
  'BD003', null,
  'membership overlap (Ben, in both West and North) refuses the repeat — no bare constraint');
select is((select count(*)::int from public.submissions
           where round_id = 'e1803000-0000-4000-8000-0000000000a3'),
          0, 'the refused North submission never wrote a row');

-- Same circle, same day, same track: this is a replace, not a repeat, and was never in
-- question — the refusal only ever looks at *other* circles.
select lives_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a1', (select ana from h)),
  'resubmitting the same track in the same circle the same day is a replace, never refused');

-- The next night, the same overlapping pair (West/North, sharing Ben) can carry the same
-- track again — the channel this rule closes is "tonight", not "ever".
select lives_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a4', (select ana from h)),
  'the same track the following night, in an overlapping circle, is allowed');
select is((select count(*)::int from public.submissions
           where round_id = 'e1803000-0000-4000-8000-0000000000a4'),
          1, 'the next-night submission landed');

-- Still refused the next time it's tried — BD003 carries nothing beyond the SQLSTATE itself,
-- which is all the handler maps to TRACK_ALREADY_USED (no state, no id, no circle name).
select throws_ok(
  format($$ select public.upsert_submission(%L, %L, 'isrc:E1803REPEAT01', '{}'::jsonb) $$,
         'e1803000-0000-4000-8000-0000000000a3', (select ana from h)),
  'BD003', null,
  'the refusal is stable across repeated attempts, not a one-shot fluke');

select * from finish();
rollback;
