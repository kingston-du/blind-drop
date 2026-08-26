-- notification_budget.sql — tasks/E03-03, E31-01, docs/15 §2, docs/05 §3.
--
-- Before E31-01 this file proved a rolling, half-open 3-deliveries/24h ceiling. That ceiling is
-- gone — lifted by the owner (docs/17 §5) so seal_reminder/guess_reminder can exist at all. What
-- this file proves now: a member who does everything at the last possible moment legitimately
-- receives all five kinds for one round (docs/05 §3's stated worst case), nothing throttles the
-- fourth or fifth, and a diligent member's count stays low because their own condition resolves
-- before each reminder's window opens — the audience conditions themselves are the only limiter
-- left, not an artificial count.
begin;
set search_path = public, extensions, tests;
select plan(12);

-- guess_reminder's audience query excludes any submitter without a live auth.users row
-- (docs/03 §6 — a deleted account's submissions stay, but it never receives a push), so these
-- synthetic profiles need one each, same as pilot_cohorts.sql's fixtures.
insert into auth.users (id) values
  ('e3140000-0000-4000-8000-000000000001'),
  ('e3140000-0000-4000-8000-000000000002'),
  ('e3140000-0000-4000-8000-000000000003'),
  ('e3140000-0000-4000-8000-000000000004');
insert into public.profiles (id, display_name)
values
  ('e3140000-0000-4000-8000-000000000001', 'Budget Ana'),
  ('e3140000-0000-4000-8000-000000000002', 'Budget Ben'),
  ('e3140000-0000-4000-8000-000000000003', 'Budget Cal'),
  ('e3140000-0000-4000-8000-000000000004', 'Budget Dee');

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e3140000-0000-4000-8000-000000000010', 'Budget Circle', 'UTC', 20, 'E3BUDG',
        'e3140000-0000-4000-8000-000000000002');

insert into public.memberships (group_id, user_id, role)
values
  ('e3140000-0000-4000-8000-000000000010', 'e3140000-0000-4000-8000-000000000001', 'member'),
  ('e3140000-0000-4000-8000-000000000010', 'e3140000-0000-4000-8000-000000000002', 'admin'),
  ('e3140000-0000-4000-8000-000000000010', 'e3140000-0000-4000-8000-000000000003', 'member'),
  ('e3140000-0000-4000-8000-000000000010', 'e3140000-0000-4000-8000-000000000004', 'member');

insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3140000-0000-4000-8000-000000000020', 'e3140000-0000-4000-8000-000000000010',
        date '2032-02-01', 'open',
        '2032-02-01T10:00:00Z', '2032-02-01T20:00:00Z', '2032-02-01T22:00:00Z');

-- Ben, Cal, and Dee drop early — hours before the first reminder window even opens.
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values
  ('e3140000-0000-4000-8000-000000000031', 'e3140000-0000-4000-8000-000000000020',
   'e3140000-0000-4000-8000-000000000002', 'isrc:E314BUDGET-BEN', '{}'::jsonb, '2032-02-01T14:00:00Z'),
  ('e3140000-0000-4000-8000-000000000032', 'e3140000-0000-4000-8000-000000000020',
   'e3140000-0000-4000-8000-000000000003', 'isrc:E314BUDGET-CAL', '{}'::jsonb, '2032-02-01T14:00:00Z'),
  ('e3140000-0000-4000-8000-000000000033', 'e3140000-0000-4000-8000-000000000020',
   'e3140000-0000-4000-8000-000000000004', 'isrc:E314BUDGET-DEE', '{}'::jsonb, '2032-02-01T14:00:00Z');

-- reveals_at − 2h: only Ana, who hasn't dropped yet, is reminded.
select tests.set_test_now('2032-02-01T18:00:00Z');
select lives_ok('select public.tick_rounds()', 'the 2h seal_reminder fires');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3140000-0000-4000-8000-000000000020' and o.kind = 'seal_reminder'
         and o.scheduled_for = '2032-02-01T18:00:00Z'::timestamptz $$,
  $$ values ('e3140000-0000-4000-8000-000000000001'::uuid) $$,
  'only Ana — still unsealed — is in the 2h reminder''s audience');

-- reveals_at − 30m: Ana still hasn't dropped, so the second reminder reaches her too.
select tests.set_test_now('2032-02-01T19:30:00Z');
select lives_ok('select public.tick_rounds()', 'the 30m seal_reminder fires');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3140000-0000-4000-8000-000000000020' and o.kind = 'seal_reminder'
         and o.scheduled_for = '2032-02-01T19:30:00Z'::timestamptz $$,
  $$ values ('e3140000-0000-4000-8000-000000000001'::uuid) $$,
  'Ana is reminded a second time — the 30m window is a fresh check, not a rewrite of the first');

-- Ana finally drops, right before reveal — after both reminders, before anyone has scored.
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3140000-0000-4000-8000-000000000034', 'e3140000-0000-4000-8000-000000000020',
        'e3140000-0000-4000-8000-000000000001', 'isrc:E314BUDGET-ANA', '{}'::jsonb,
        '2032-02-01T19:55:00Z');

select tests.set_test_now('2032-02-01T20:00:00Z');
select lives_ok('select public.tick_rounds()', 'the round reveals with all four submitters');
select is((select state from public.rounds where id = 'e3140000-0000-4000-8000-000000000020'),
          'revealed'::round_state, 'four submitters is enough to reveal');

-- Ben, Cal, and Dee each complete their sheet (three cards to name); Ana never opens hers.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id, created_at)
select 'e3140000-0000-4000-8000-000000000020', guesser, card.id, card.user_id, '2032-02-01T20:30:00Z'
  from (values
    ('e3140000-0000-4000-8000-000000000002'::uuid),
    ('e3140000-0000-4000-8000-000000000003'::uuid),
    ('e3140000-0000-4000-8000-000000000004'::uuid)
  ) g(guesser)
  cross join public.submissions card
 where card.round_id = 'e3140000-0000-4000-8000-000000000020'
   and card.user_id <> g.guesser;

-- scores_at − 30m: only Ana, whose sheet is still empty, is reminded to guess.
select tests.set_test_now('2032-02-01T21:30:00Z');
select lives_ok('select public.tick_rounds()', 'guess_reminder fires for the one incomplete sheet');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3140000-0000-4000-8000-000000000020' and o.kind = 'guess_reminder' $$,
  $$ values ('e3140000-0000-4000-8000-000000000001'::uuid) $$,
  'Ben, Cal, and Dee finished guessing; only Ana is reminded');

select tests.set_test_now('2032-02-01T22:00:00Z');
select lives_ok('select public.tick_rounds()', 'the round scores');

create temporary table deliveries as
select audience.value::uuid as user_id, o.kind
  from public.notification_outbox o
 cross join lateral jsonb_array_elements_text(o.audience) audience(value)
 where o.round_id = 'e3140000-0000-4000-8000-000000000020';

-- The point of this file: nothing capped Ana's evening at three. A fully-last-minute member
-- legitimately receives every kind docs/05 §3 lists for one round — five in total, one more
-- than the ceiling this file used to enforce.
select is((select count(*)::int from deliveries where user_id = 'e3140000-0000-4000-8000-000000000001'),
          5, 'Ana — both reminders, reveal, guess_reminder, and results — the stated worst case');
select is((select count(*)::int from deliveries where user_id = 'e3140000-0000-4000-8000-000000000002'),
          2, 'Ben — reveal and results only; he never qualified for either reminder');
select is((select count(*)::int from deliveries
             where user_id in ('e3140000-0000-4000-8000-000000000003',
                                'e3140000-0000-4000-8000-000000000004')),
          4, 'Cal and Dee, two deliveries each, for the same reason as Ben');

select * from finish();
rollback;
