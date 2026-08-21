-- lifecycle_score_nudge.sql — tasks/E03-03, docs/02 §2, docs/05 §3.
begin;
set search_path = public, extensions, tests;
select plan(20);

-- Nudge targeting: Ben has already submitted; the nudge still leaves his choice open to change.
insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3030000-0000-4000-8000-000000000001', tests.the_group(), date '2031-04-07', 'open',
        '2031-04-07T10:00:00Z', '2031-04-07T20:00:00Z', '2031-04-07T22:00:00Z');

insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3030000-0000-4000-8000-000000000011',
        'e3030000-0000-4000-8000-000000000001', tests.person('Ben'),
        'isrc:E303NUDGE001', '{}'::jsonb, '2031-04-07T16:00:00Z');

select tests.set_test_now('2031-04-07T17:59:59Z');
select lives_ok('select public.tick_rounds()', 'a nudge is not early by even one second');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'nudge'),
          0, 'no nudge exists before reveals_at minus two hours');

select tests.set_test_now('2031-04-07T18:00:00Z');
select lives_ok('select public.tick_rounds()', 'the nudge deadline enqueues without transitioning');
select is((select enqueued_at from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'nudge'),
          '2031-04-07T18:00:00Z'::timestamptz, 'nudge enqueue time uses public.now_()');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3030000-0000-4000-8000-000000000001' and o.kind = 'nudge' $$,
  $$ select m.user_id from public.memberships m
       where m.group_id = tests.the_group() and m.left_at is null $$,
  'the nudge audience is the frozen active roster, including existing submitters');

-- Ana submits after audience resolution. The accepted product rule is that the frozen row
-- remains unchanged rather than teaching the push worker how to inspect submission state.
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3030000-0000-4000-8000-000000000012',
        'e3030000-0000-4000-8000-000000000001', tests.person('Ana'),
        'isrc:E303NUDGE002', '{}'::jsonb, '2031-04-07T18:05:00Z');

select tests.set_test_now('2031-04-07T18:10:00Z');
select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten later ticks neither duplicate nor rewrite a nudge');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'nudge'),
          1, 'only one nudge row is ever created');
select ok((select audience ? tests.person('Ana')::text from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'nudge'),
          'a member who submits after enqueue remains in the frozen audience');
select ok((select audience ? tests.person('Ben')::text from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'nudge'),
          'a member who submitted before enqueue can still open the round and change their song');

-- Scoring: create a normal three-person round, reveal it, then prove the second guarded
-- transition and its participant-only results audience.
insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3030000-0000-4000-8000-000000000002', tests.the_group(), date '2031-04-09', 'open',
        '2031-04-09T10:00:00Z', '2031-04-09T20:00:00Z', '2031-04-09T22:00:00Z');

insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values
  ('e3030000-0000-4000-8000-000000000021', 'e3030000-0000-4000-8000-000000000002',
   tests.person('Cal'), 'isrc:E303SCORE001', '{}'::jsonb, '2031-04-09T14:00:00Z'),
  ('e3030000-0000-4000-8000-000000000022', 'e3030000-0000-4000-8000-000000000002',
   tests.person('Dee'), 'isrc:E303SCORE002', '{}'::jsonb, '2031-04-09T15:00:00Z'),
  ('e3030000-0000-4000-8000-000000000023', 'e3030000-0000-4000-8000-000000000002',
   tests.person('Fay'), 'isrc:E303SCORE003', '{}'::jsonb, '2031-04-09T16:00:00Z');

select tests.set_test_now('2031-04-09T20:00:00Z');
select lives_ok('select public.tick_rounds()', 'the score fixture first reveals normally');
select is((select state from public.rounds where id = 'e3030000-0000-4000-8000-000000000002'),
          'revealed'::round_state, 'at reveals_at the round is revealed, not scored early');

insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id, created_at)
values ('e3030000-0000-4000-8000-000000000002', tests.person('Cal'),
        'e3030000-0000-4000-8000-000000000022', tests.person('Fay'),
        '2031-04-09T20:30:00Z');

select tests.set_test_now('2031-04-09T21:59:59Z');
select lives_ok('select public.tick_rounds()', 'scoring is not early by even one second');
select is((select state from public.rounds where id = 'e3030000-0000-4000-8000-000000000002'),
          'revealed'::round_state, 'the round remains revealed before scores_at');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'results'),
          0, 'no results row exists before scores_at');

select tests.set_test_now('2031-04-09T22:00:00Z');
select lives_ok('select public.tick_rounds()', 'at scores_at the round advances and enqueues');
select is((select state from public.rounds where id = 'e3030000-0000-4000-8000-000000000002'),
          'scored'::round_state, 'revealed advances to scored exactly at scores_at');
select is((select enqueued_at from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'results'),
          '2031-04-09T22:00:00Z'::timestamptz, 'results enqueue time uses public.now_()');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3030000-0000-4000-8000-000000000002' and o.kind = 'results' $$,
  $$ select user_id from public.submissions
       where round_id = 'e3030000-0000-4000-8000-000000000002'
     union
     select guesser_id from public.guesses
       where round_id = 'e3030000-0000-4000-8000-000000000002' $$,
  'results audience is exactly the live users who submitted or guessed');

select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten repeated score ticks are harmless');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'results'),
          1, 'the guarded score transition leaves exactly one results row');

select * from finish();
rollback;
