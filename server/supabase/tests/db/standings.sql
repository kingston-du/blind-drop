-- standings.sql — all-time, and the asymmetry that makes it worth testing. tasks/E05-06.
--
-- docs/02 §4.2:
--
--   Ear (all-time)         = Σ correct / Σ possible       — pooled, zero-guess rounds excluded
--   Readability (all-time) = mean( readability per round ) — a mean of rates, not a ratio
--
-- Those two are the same number whenever every round is the same size, which is exactly why
-- this file builds rounds of **8, 5 and 3 submitters**. With sizes that differ, pooling and
-- averaging disagree, and a regression that conflates them — one `avg()` in the wrong place —
-- produces a wrong number instead of an identical one. A test on equal-sized rounds would pass
-- against the bug.
--
-- The seed's single scored round is round one. Two more are built here, inside the
-- transaction, with hand-computed expectations.

begin;
set search_path = public, extensions, tests;
select plan(17);

-- ─── round two: 5 submitters, S−1 = 4 ────────────────────────────────────────
-- Ana, Ben, Cal, Dee, Eli. Ana guesses all four and gets three right; nobody else guesses, so
-- only Ana has an ear this round.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order)
values ('e5061000-0000-4000-8000-000000000001', tests.the_group(), date '2031-06-01', 'open',
        '2031-06-01T10:00:00Z', '2031-06-01T20:00:00Z', '2031-06-01T22:00:00Z', null);

insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('e5061000-0000-4000-8000-00000000001' || n)::uuid,
       'e5061000-0000-4000-8000-000000000001',
       tests.person(name),
       'isrc:E506R2000' || n,
       '{}'::jsonb
  from (values (1,'Ana'), (2,'Ben'), (3,'Cal'), (4,'Dee'), (5,'Eli')) as t(n, name);

-- Ana names each card's true owner on three of the four, and gets the fourth wrong.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
values ('e5061000-0000-4000-8000-000000000001', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000012', tests.person('Ben')),
       ('e5061000-0000-4000-8000-000000000001', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000013', tests.person('Cal')),
       ('e5061000-0000-4000-8000-000000000001', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000014', tests.person('Dee')),
       ('e5061000-0000-4000-8000-000000000001', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000015', tests.person('Cal'));  -- wrong: Eli's card

-- ─── round three: 3 submitters, S−1 = 2 ──────────────────────────────────────
-- Ana, Ben, Cal. Ana guesses both and gets both right. Nobody names Ana, so her readability
-- for this round is 0/2 — a real zero, and it must average in rather than be dropped.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order)
values ('e5061000-0000-4000-8000-000000000002', tests.the_group(), date '2031-06-02', 'open',
        '2031-06-02T10:00:00Z', '2031-06-02T20:00:00Z', '2031-06-02T22:00:00Z', null);

insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('e5061000-0000-4000-8000-00000000002' || n)::uuid,
       'e5061000-0000-4000-8000-000000000002',
       tests.person(name),
       'isrc:E506R3000' || n,
       '{}'::jsonb
  from (values (1,'Ana'), (2,'Ben'), (3,'Cal')) as t(n, name);

insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
values ('e5061000-0000-4000-8000-000000000002', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000022', tests.person('Ben')),
       ('e5061000-0000-4000-8000-000000000002', tests.person('Ana'),
        'e5061000-0000-4000-8000-000000000023', tests.person('Cal'));

-- Both rounds have to be `scored` to count, and the card_order constraint requires an order
-- once they are. Written directly rather than through `tick_rounds()`: the transitions are
-- E03's to prove, and this file is about the arithmetic on the far side of them.
update public.rounds
   set card_order = (select jsonb_agg(s.id order by s.id)
                       from public.submissions s where s.round_id = public.rounds.id),
       state = 'revealed'
 where id in ('e5061000-0000-4000-8000-000000000001', 'e5061000-0000-4000-8000-000000000002');
update public.rounds set state = 'scored'
 where id in ('e5061000-0000-4000-8000-000000000001', 'e5061000-0000-4000-8000-000000000002');

-- ─── the per-round numbers these depend on ───────────────────────────────────

select is((select submitter_count::int from public.round_submitter_counts
            where round_id = 'e5061000-0000-4000-8000-000000000001'), 5, 'round two has S = 5');
select is((select submitter_count::int from public.round_submitter_counts
            where round_id = 'e5061000-0000-4000-8000-000000000002'), 3, 'round three has S = 3');

select is((select ear from public.round_scores
            where round_id = 'e5061000-0000-4000-8000-000000000001'
              and user_id = tests.person('Ana')),
          (3::numeric / 4), 'Ana ear 3/4 in round two');
select is((select ear from public.round_scores
            where round_id = 'e5061000-0000-4000-8000-000000000002'
              and user_id = tests.person('Ana')),
          (2::numeric / 2), 'Ana ear 2/2 in round three');
select ok((select ear from public.round_scores
            where round_id = 'e5061000-0000-4000-8000-000000000001'
              and user_id = tests.person('Ben')) is null,
          'Ben guessed nothing in round two, so Ben has no ear for it');

select is((select readability from public.round_scores
            where round_id = 'e5061000-0000-4000-8000-000000000002'
              and user_id = tests.person('Ana')),
          0::numeric, 'nobody named Ana in round three — a real zero, not a null');

-- ─── ear pools ───────────────────────────────────────────────────────────────
-- Ana guessed in all three rounds: 5/7, 3/4, 2/2 → (5+3+2) / (7+4+2) = 10/13.
-- The mean of the three *rates* would be 0.7976; pooling gives 0.7692. They differ, which is
-- the entire point of building rounds of three sizes.

select is((select ear_correct_total::int from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          10, 'Ana has ten correct guesses all-time');
select is((select ear_possible_total::int from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          13, 'out of thirteen possible');
select is((select ear_all_time from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          (10::numeric / 13), 'ear_all_time pools: 10/13, not the mean of the three rates');
select ok((select ear_all_time from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group())
          <> ((5::numeric/7 + 3::numeric/4 + 2::numeric/2) / 3),
          'and it is genuinely different from the mean of rates — the sizes make it so');

-- ─── readability averages ────────────────────────────────────────────────────
-- Ana's readability: 6/7 in round one, and in rounds two and three nobody named her, so 0/4
-- and 0/2. Mean of the rates = (6/7 + 0 + 0) / 3 = 2/7 ≈ 0.2857.
-- Pooled would be 6 / (7+4+2) = 6/13 ≈ 0.4615. They differ.

select is((select readability_all_time from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          ((6::numeric/7 + 0 + 0) / 3),
          'readability_all_time is the mean of per-round rates');
select ok((select readability_all_time from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group())
          <> (6::numeric / 13),
          'and it is not the pooled ratio — conflating the two is the regression this catches');

-- ─── zero-guess rounds leave the ear sums entirely ───────────────────────────
-- Ben: guessed in round one (3/7), not in round two, and round three has no guesses from him
-- either. His pooled ear must be 3/7 exactly — a round he sat out must not add 0 to the
-- numerator while adding 4 to the denominator.

select is((select ear_all_time from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()),
          (3::numeric / 7), 'a round Ben sat out is in neither sum');
select is((select ear_rounds::int from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()),
          1, 'so only one round counts toward his ear');
select is((select rounds_played::int from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()),
          3, 'though he played three — sitting out the sheet is not sitting out the round');

-- ─── the band, and the rank that must not exist ──────────────────────────────
-- docs/02 §4.5 and docs/04 §4: readability is a spectrum, never a leaderboard. The API carries
-- no rank for it, and the view must not invent one for a handler to pass along.

select is(
  (select band from public.standings
    where user_id = tests.person('Cal') and group_id = tests.the_group()),
  (select case
     when avg(readability) >= 0.80 then 'open_book'
     when avg(readability) >= 0.60 then 'legible'
     when avg(readability) >= 0.40 then 'mixed_signals'
     when avg(readability) >= 0.20 then 'hard_to_place'
     else 'unreadable' end
     from public.round_scores
    where user_id = tests.person('Cal') and group_id = tests.the_group()),
  'band follows the docs/02 §4.5 table');

select hasnt_column('public', 'standings', 'rank',
                    'standings carries no rank — a client that receives one will render it');

select * from finish();
rollback;
