-- lifecycle.sql — tasks/E03-02, AC-3 and AC-4.
begin;
set search_path = public, extensions, tests;
select plan(25);

select has_function('public', 'tick_rounds', 'tick_rounds() exists');
select is(
  (select p.prosecdef from pg_proc p
    where p.proname = 'tick_rounds' and p.pronamespace = 'public'::regnamespace),
  true, 'tick_rounds() is security definer');
select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p
    where p.proname = 'tick_rounds' and p.pronamespace = 'public'::regnamespace),
  'tick_rounds() pins an empty search_path');
select ok(not has_function_privilege('anon', 'public.tick_rounds()', 'execute'),
          'anon cannot advance rounds');
select ok(has_function_privilege('service_role', 'public.tick_rounds()', 'execute'),
          'the scheduler service role can run the tick');

-- Two due rounds in the fixture group: exactly two submitters must void; exactly three must
-- reveal. Stable ids make a failed assertion readable and make the shuffle reproducible.
insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3020000-0000-4000-8000-000000000002', tests.the_group(), date '2031-04-05', 'open',
        '2031-04-05T05:00:00Z', '2031-04-05T15:00:00Z', '2031-04-05T17:00:00Z'),
       ('e3020000-0000-4000-8000-000000000003', tests.the_group(), date '2031-04-06', 'open',
        '2031-04-05T05:00:00Z', '2031-04-05T15:00:00Z', '2031-04-05T17:00:00Z');

insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values
  ('e3020000-0000-4000-8000-000000000021', 'e3020000-0000-4000-8000-000000000002',
   tests.person('Ana'), 'isrc:E30200000001', '{}'::jsonb, '2031-04-05T10:00:00Z'),
  ('e3020000-0000-4000-8000-000000000022', 'e3020000-0000-4000-8000-000000000002',
   tests.person('Ben'), 'isrc:E30200000002', '{}'::jsonb, '2031-04-05T11:00:00Z'),
  ('e3020000-0000-4000-8000-000000000031', 'e3020000-0000-4000-8000-000000000003',
   tests.person('Cal'), 'isrc:E30200000003', '{}'::jsonb, '2031-04-05T10:00:00Z'),
  ('e3020000-0000-4000-8000-000000000032', 'e3020000-0000-4000-8000-000000000003',
   tests.person('Dee'), 'isrc:E30200000004', '{}'::jsonb, '2031-04-05T11:00:00Z'),
  ('e3020000-0000-4000-8000-000000000033', 'e3020000-0000-4000-8000-000000000003',
   tests.person('Fay'), 'isrc:E30200000005', '{}'::jsonb, '2031-04-05T12:00:00Z');

-- A group with no rounds proves ensure_rounds() is called at the top of the tick.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('e3020000-0000-4000-8000-000000000010', 'Tick creation', 'UTC', 20, 'TCK223',
        tests.person('Ana'));

select tests.set_test_now('2031-04-05T14:59:59Z');
select lives_ok('select public.tick_rounds()', 'one second before reveal, the tick is harmless');
select is((select state from public.rounds where id = 'e3020000-0000-4000-8000-000000000002'),
          'open'::round_state, 'exactly two submissions stay open before reveals_at');
select is((select state from public.rounds where id = 'e3020000-0000-4000-8000-000000000003'),
          'open'::round_state, 'exactly three submissions stay open before reveals_at');

select tests.set_test_now('2031-04-05T15:00:00Z');
select lives_ok('select public.tick_rounds()', 'at reveals_at, due rounds advance');

select is((select state from public.rounds where id = 'e3020000-0000-4000-8000-000000000002'),
          'voided'::round_state, 'exactly two submitters voids');
select is((select state from public.rounds where id = 'e3020000-0000-4000-8000-000000000003'),
          'revealed'::round_state, 'exactly three submitters reveals');
select is((select card_order from public.rounds where id = 'e3020000-0000-4000-8000-000000000002'),
          null::jsonb, 'a voided round has no card_order');
select is((select jsonb_array_length(card_order) from public.rounds
            where id = 'e3020000-0000-4000-8000-000000000003'),
          3, 'a revealed round stores one card-order entry per submission');
select set_eq(
  $$ select value::uuid from public.rounds r,
       lateral jsonb_array_elements_text(r.card_order) t(value)
       where r.id = 'e3020000-0000-4000-8000-000000000003' $$,
  $$ select id from public.submissions
       where round_id = 'e3020000-0000-4000-8000-000000000003' $$,
  'the stored card_order is a permutation of the submissions');

select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000002' and kind = 'void'),
          1, 'voiding enqueues exactly one void row');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000002' and kind = 'reveal'),
          0, 'a voided round never enqueues reveal');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000003' and kind = 'reveal'),
          1, 'revealing enqueues exactly one reveal row');
select is((select count(*)::int from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000003' and kind = 'void'),
          0, 'a revealed round never enqueues void');
select is((select enqueued_at from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000003' and kind = 'reveal'),
          '2031-04-05T15:00:00Z'::timestamptz,
          'the outbox timestamp comes from public.now_(), not the host clock');
select is((select jsonb_array_length(audience) from public.notification_outbox
            where round_id = 'e3020000-0000-4000-8000-000000000003' and kind = 'reveal'),
          9, 'the reveal audience is all nine active members');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3020000-0000-4000-8000-000000000003' and o.kind = 'reveal' $$,
  $$ select user_id from public.memberships
       where group_id = tests.the_group() and left_at is null $$,
  'the frozen audience is exactly the active roster');

select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'running the same tick ten more times is harmless');
select is((select count(*)::int from public.notification_outbox
            where round_id in ('e3020000-0000-4000-8000-000000000002',
                               'e3020000-0000-4000-8000-000000000003')
              and kind in ('reveal', 'void')),
          2, 'ten repeated ticks still leave one transition outbox row per round');
select is((select count(*)::int from public.rounds
            where id in ('e3020000-0000-4000-8000-000000000002',
                         'e3020000-0000-4000-8000-000000000003')
              and state in ('voided', 'revealed')),
          2, 'ten repeated ticks do not move or duplicate either transition');
select is((select count(*)::int from public.rounds
            where group_id = 'e3020000-0000-4000-8000-000000000010'),
          2, 'tick_rounds() calls ensure_rounds() and materialises today and tomorrow');

select * from finish();
rollback;
