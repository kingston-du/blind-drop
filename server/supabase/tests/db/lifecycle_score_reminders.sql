-- lifecycle_score_reminders.sql — tasks/E03-03, E31-01, docs/02 §2, docs/05 §3.
--
-- Was lifecycle_score_nudge.sql. E31-01 retired the unconditional nudge for two conditional
-- reminders — this file now proves tick_rounds()'s three new conditional scan windows
-- (seal_reminder × 2, guess_reminder × 1) instead of the old "everyone" audience. The scoring
-- assertions below are unchanged from before this slice.
begin;
set search_path = public, extensions, tests;
select plan(31);

-- ── seal_reminder: two firings, each a real condition re-evaluated fresh ──────────────────────
insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3030000-0000-4000-8000-000000000001', tests.the_group(), date '2031-04-07', 'open',
        '2031-04-07T10:00:00Z', '2031-04-07T20:00:00Z', '2031-04-07T22:00:00Z');

-- Ben seals well before either window opens.
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3030000-0000-4000-8000-000000000011',
        'e3030000-0000-4000-8000-000000000001', tests.person('Ben'),
        'isrc:E303NUDGE001', '{}'::jsonb, '2031-04-07T16:00:00Z');

select tests.set_test_now('2031-04-07T17:59:59Z');
select lives_ok('select public.tick_rounds()', 'a seal_reminder is not early by even one second');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
          0, 'no seal_reminder exists before reveals_at minus two hours');

select tests.set_test_now('2031-04-07T18:00:00Z');
select lives_ok('select public.tick_rounds()', 'the 2h deadline enqueues without transitioning');
select is((select enqueued_at from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'
              and scheduled_for = '2031-04-07T18:00:00Z'::timestamptz),
          '2031-04-07T18:00:00Z'::timestamptz, 'the 2h reminder''s enqueue time uses public.now_()');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3030000-0000-4000-8000-000000000001' and o.kind = 'seal_reminder'
         and o.scheduled_for = '2031-04-07T18:00:00Z'::timestamptz $$,
  $$ select m.user_id from public.memberships m
       where m.group_id = tests.the_group() and m.left_at is null
         and m.user_id <> tests.person('Ben') $$,
  'the 2h reminder reaches every member except Ben, who already sealed a song');

-- Ana seals after the 2h reminder is frozen but before the 30m one is even due.
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3030000-0000-4000-8000-000000000012',
        'e3030000-0000-4000-8000-000000000001', tests.person('Ana'),
        'isrc:E303NUDGE002', '{}'::jsonb, '2031-04-07T18:05:00Z');

select tests.set_test_now('2031-04-07T18:10:00Z');
select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten later ticks neither duplicate the 2h row nor open the 30m window early');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
          1, 'still exactly one seal_reminder row — the 30m window has not opened yet');
select ok((select audience ? tests.person('Ana')::text from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'
              and scheduled_for = '2031-04-07T18:00:00Z'::timestamptz),
          'the 2h row is not rewritten by Ana sealing afterward — frozen at enqueue, same as '
          'every other round-kind audience (the claim-time trim is a different mechanism, '
          'tested in notification_settle.sql)');

select tests.set_test_now('2031-04-07T19:30:00Z');
select lives_ok('select public.tick_rounds()', 'the 30m deadline enqueues a second, distinct row');
select is((select enqueued_at from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'
              and scheduled_for = '2031-04-07T19:30:00Z'::timestamptz),
          '2031-04-07T19:30:00Z'::timestamptz, 'the 30m reminder''s enqueue time uses public.now_()');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3030000-0000-4000-8000-000000000001' and o.kind = 'seal_reminder'
         and o.scheduled_for = '2031-04-07T19:30:00Z'::timestamptz $$,
  $$ select m.user_id from public.memberships m
       where m.group_id = tests.the_group() and m.left_at is null
         and m.user_id not in (tests.person('Ben'), tests.person('Ana')) $$,
  'the 30m reminder is a fresh computation: Ana has since sealed and is excluded, unlike the '
  'frozen 2h row above');

select tests.set_test_now('2031-04-07T19:35:00Z');
select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten more ticks do not add a third seal_reminder row');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
          2, 'seal_reminder fires at most twice a round — one row per scheduled instant');
select is((select count(distinct scheduled_for)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
          2, 'the widened (round_id, kind, scheduled_for) key is what let the second row exist');

-- ── scoring, and guess_reminder ahead of it ────────────────────────────────────────────────────
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

-- Cal completes their sheet (both other cards); Dee never opens it; Fay guesses only one of two.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id, created_at)
values
  ('e3030000-0000-4000-8000-000000000002', tests.person('Cal'),
   'e3030000-0000-4000-8000-000000000022', tests.person('Dee'), '2031-04-09T20:30:00Z'),
  ('e3030000-0000-4000-8000-000000000002', tests.person('Cal'),
   'e3030000-0000-4000-8000-000000000023', tests.person('Fay'), '2031-04-09T20:30:00Z'),
  ('e3030000-0000-4000-8000-000000000002', tests.person('Fay'),
   'e3030000-0000-4000-8000-000000000021', tests.person('Cal'), '2031-04-09T20:35:00Z');

select tests.set_test_now('2031-04-09T21:29:59Z');
select lives_ok('select public.tick_rounds()', 'guess_reminder is not early by even one second');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'guess_reminder'),
          0, 'no guess_reminder exists before scores_at minus thirty minutes');

select tests.set_test_now('2031-04-09T21:30:00Z');
select lives_ok('select public.tick_rounds()', 'the guess_reminder deadline enqueues, still revealed');
select is((select state from public.rounds where id = 'e3030000-0000-4000-8000-000000000002'),
          'revealed'::round_state, 'the round does not score early just because the reminder fired');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3030000-0000-4000-8000-000000000002' and o.kind = 'guess_reminder' $$,
  $$ values (tests.person('Dee')), (tests.person('Fay')) $$,
  'guess_reminder reaches submitters with an incomplete sheet — Cal is done, so excluded');

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
  'results audience is exactly the live users who submitted or guessed, unaffected by E31-01');

select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten repeated score ticks are harmless');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'results'),
          1, 'the guarded score transition leaves exactly one results row');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3030000-0000-4000-8000-000000000002' and kind = 'guess_reminder'),
          1, 'guess_reminder fires at most once a round, even after scoring and ten more ticks');

select * from finish();
rollback;
