-- notification_budget.sql — tasks/E03-03, docs/15 §2.
--
-- Every active member receives the nudge, including people who already submitted, so each
-- member exercises the maximum legitimate delivery set: nudge + reveal + results. Fourteen
-- daily rounds prove the rolling, half-open 24-hour budget.
begin;
set search_path = public, extensions, tests;
select plan(7);

insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select ('e3031400-0000-4000-8000-' || lpad(day_no::text, 12, '0'))::uuid,
       tests.the_group(),
       date '2032-02-01' + (day_no - 1),
       'open',
       (date '2032-02-01' + (day_no - 1))::timestamp + interval '10 hours',
       (date '2032-02-01' + (day_no - 1))::timestamp + interval '20 hours',
       (date '2032-02-01' + (day_no - 1))::timestamp + interval '22 hours'
  from generate_series(1, 14) day_no;

-- Ben and Dee seal before the nudge every day; they remain eligible for it.
insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
select r.id, p.user_id,
       format('isrc:E303BUDGET%02s%s', extract(day from r.local_date)::int, p.suffix),
       '{}'::jsonb,
       r.opens_at + interval '4 hours'
  from public.rounds r
 cross join (values (tests.person('Ben'), 'B'), (tests.person('Dee'), 'D')) p(user_id, suffix)
 where r.local_date between date '2032-02-01' and date '2032-02-14';

do $$
declare
  v_day date;
  v_round uuid;
begin
  for v_offset in 0..13 loop
    v_day := date '2032-02-01' + v_offset;
    select r.id into v_round
      from public.rounds r
     where r.group_id = tests.the_group() and r.local_date = v_day;

    perform tests.set_test_now(v_day::timestamp + interval '18 hours');
    perform public.tick_rounds();

    -- Ana seals five minutes after the nudge audience has been frozen.
    insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
    values (v_round, tests.person('Ana'), format('isrc:E303BUDGET%02sA', v_offset + 1),
            '{}'::jsonb, v_day::timestamp + interval '18 hours 5 minutes');

    perform tests.set_test_now(v_day::timestamp + interval '20 hours');
    perform public.tick_rounds();
    perform tests.set_test_now(v_day::timestamp + interval '22 hours');
    perform public.tick_rounds();
  end loop;
end $$;

select is((select count(*)::int
             from public.notification_outbox o
             join public.rounds r on r.id = o.round_id
            where r.group_id = tests.the_group()
              and r.local_date between date '2032-02-01' and date '2032-02-14'),
          42, 'fourteen valid rounds enqueue exactly three notification kinds each');
select is((select count(*)::int
             from public.notification_outbox o
            join public.rounds r on r.id = o.round_id
            where r.local_date between date '2032-02-01' and date '2032-02-14'
              and r.group_id = tests.the_group()
              and o.kind = 'nudge'),
          14, 'one nudge is enqueued per day');
select is((select count(*)::int
             from public.notification_outbox o
            join public.rounds r on r.id = o.round_id
            where r.local_date between date '2032-02-01' and date '2032-02-14'
              and r.group_id = tests.the_group()
              and o.kind = 'reveal'),
          14, 'one reveal is enqueued per day');
select is((select count(*)::int
             from public.notification_outbox o
            join public.rounds r on r.id = o.round_id
            where r.local_date between date '2032-02-01' and date '2032-02-14'
              and r.group_id = tests.the_group()
              and o.kind = 'results'),
          14, 'one results row is enqueued per day');

create temporary table simulated_deliveries as
select audience.value::uuid as user_id, o.enqueued_at
  from public.notification_outbox o
  join public.rounds r on r.id = o.round_id
 cross join lateral jsonb_array_elements_text(o.audience) audience(value)
 where r.group_id = tests.the_group()
   and r.local_date between date '2032-02-01' and date '2032-02-14';

select is((select count(*)::int from simulated_deliveries where user_id = tests.person('Ana')),
          42, 'a late submitter exercises the maximum three deliveries every day');
select is((select count(*)::int from simulated_deliveries where user_id = tests.person('Ben')),
          42, 'an early submitter receives the nudge, reveal, and results');
select is(
  (select max(delivery_count)::int
     from (
       select d.user_id, d.enqueued_at,
              (select count(*)
                 from simulated_deliveries in_window
                where in_window.user_id = d.user_id
                  and in_window.enqueued_at > d.enqueued_at - interval '24 hours'
                  and in_window.enqueued_at <= d.enqueued_at) as delivery_count
         from simulated_deliveries d
     ) rolling),
  3, 'no user receives more than three notifications in any rolling 24-hour window');

select * from finish();
rollback;
