-- shuffle.sql — tasks/E03-04, docs/02 §2, docs/01 ADR-003.
--
-- Spearman correlation is Pearson correlation over ranks. Each rank is computed within its
-- round, then all 8,000 observations are pooled. Submission-time order is intentionally a
-- different permutation from UUID order so the two leak checks are independent.
begin;
set search_path = public, extensions, tests;
select plan(12);

insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select ('e3040000-0000-4000-8000-' || lpad(round_no::text, 12, '0'))::uuid,
       tests.the_group(),
       date '2040-01-01' + (round_no - 1),
       'open',
       (date '2040-01-01' + (round_no - 1))::timestamp + interval '10 hours',
       (date '2040-01-01' + (round_no - 1))::timestamp + interval '20 hours',
       (date '2040-01-01' + (round_no - 1))::timestamp + interval '22 hours'
  from generate_series(1, 1000) round_no;

insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
select r.id, participant.user_id,
       format('synthetic:%s:%s', r.id, participant.user_rank),
       '{}'::jsonb,
       r.opens_at + participant.time_rank * interval '1 minute'
  from public.rounds r
 cross join (
   values
     (tests.person('Ana'), 1, 3),
     (tests.person('Ben'), 2, 6),
     (tests.person('Cal'), 3, 1),
     (tests.person('Dee'), 4, 5),
     (tests.person('Eli'), 5, 8),
     (tests.person('Fay'), 6, 2),
     (tests.person('Gus'), 7, 7),
     (tests.person('Hal'), 8, 4)
 ) participant(user_id, user_rank, time_rank)
 where r.local_date between date '2040-01-01' and date '2042-09-26';

select is((select count(*)::int from public.rounds
            where id::text like 'e3040000-0000-4000-8000-%'
              and state = 'open' and card_order is null),
          1000, 'all synthetic rounds begin open with no stored order');

select tests.set_test_now('2043-01-01T00:00:00Z');
select lives_ok('select public.tick_rounds()', 'one late tick shuffles every synthetic round');
select is((select count(*)::int from public.rounds
            where id::text like 'e3040000-0000-4000-8000-%' and state = 'scored'),
          1000, 'all 1,000 rounds advance through reveal and score without skipping');
select is_empty($$
  select r.id
    from public.rounds r
   where r.id::text like 'e3040000-0000-4000-8000-%'
     and (jsonb_typeof(r.card_order) <> 'array'
          or jsonb_array_length(r.card_order) <> 8)
$$, 'each stored order is an eight-element JSON array');
select is_empty($$
  select r.id
    from public.rounds r
   where r.id::text like 'e3040000-0000-4000-8000-%'
     and exists (
       (select value::uuid
          from jsonb_array_elements_text(r.card_order) item(value)
        except
        select s.id from public.submissions s where s.round_id = r.id)
       union all
       (select s.id from public.submissions s where s.round_id = r.id
        except
        select value::uuid
          from jsonb_array_elements_text(r.card_order) item(value))
     )
$$, 'every stored array is exactly a permutation of that round submissions');

create temporary table shuffle_observations as
select r.id as round_id,
       item.ordinality::int as card_no,
       row_number() over (partition by r.id order by s.created_at, s.id)::int as time_rank,
       row_number() over (partition by r.id order by s.user_id)::int as user_rank
  from public.rounds r
 cross join lateral jsonb_array_elements_text(r.card_order)
                       with ordinality as item(submission_id, ordinality)
  join public.submissions s
    on s.round_id = r.id and s.id = item.submission_id::uuid
 where r.id::text like 'e3040000-0000-4000-8000-%';

select is((select count(*)::int from shuffle_observations), 8000,
          'card_no is the one-based JSON position for all 8,000 cards');
select cmp_ok(abs((select corr(time_rank::double precision, card_no::double precision)
                    from shuffle_observations)), '<', 0.1::double precision,
             'Spearman correlation with submission-time rank is within ±0.1');
select cmp_ok(abs((select corr(user_rank::double precision, card_no::double precision)
                    from shuffle_observations)), '<', 0.1::double precision,
             'Spearman correlation with user-id rank is within ±0.1');

create temporary table stored_orders as
select id, card_order
  from public.rounds
 where id::text like 'e3040000-0000-4000-8000-%';

-- The production state machine makes this impossible. Disable only its test transaction's
-- forward trigger to force one selected round through the same shuffle a second time.
set constraints rounds_card_order_is_permutation_trg immediate;
alter table public.rounds disable trigger rounds_state_forward_only_trg;
update public.rounds
   set state = 'open', card_order = null
 where id = 'e3040000-0000-4000-8000-000000000001';

select lives_ok('select public.tick_rounds()', 'a test-forced second shuffle completes');
set constraints rounds_card_order_is_permutation_trg immediate;
alter table public.rounds enable trigger rounds_state_forward_only_trg;
select is((select r.card_order from public.rounds r
            where r.id = 'e3040000-0000-4000-8000-000000000001'),
          (select s.card_order from stored_orders s
            where s.id = 'e3040000-0000-4000-8000-000000000001'),
          'the same round id and submissions deterministically produce the same order');

select lives_ok(
  $$ do $do$ begin for i in 1..10 loop perform public.tick_rounds(); end loop; end $do$ $$,
  'ten ordinary retries cannot reach the shuffle path again');
select is_empty($$
  select r.id
    from public.rounds r
    join stored_orders s using (id)
   where r.card_order is distinct from s.card_order
$$, 'stored card_order remains authoritative and immutable after reveal');

select * from finish();
rollback;
