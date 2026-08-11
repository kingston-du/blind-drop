-- scoring.sql — the docs/02 §4.4 table, asserted row by row. tasks/E05-06, docs/15 AC-8.
--
-- **Do not change the numbers here without changing docs/02 §4.4.** They were worked out by
-- hand before any of this was built, and their whole value is that they were not derived from
-- the implementation. A view that produces different numbers is wrong; a doc that disagrees
-- with the view is a decision somebody has to make deliberately.
--
-- The one departure is recorded in `seed.sql`'s open question: §4.4 as written is
-- unsatisfiable, because "Cal guesses all 7; 7 correct" forces every card but Cal's to hold at
-- least one correct guess, which contradicts Gus's stated readability of 0/7. The seed applies
-- the smallest repair — Gus 0 → 1, Hal 5 → 4 — and leaves every stated *guess activity* number
-- untouched. Both totals still balance at 26. That repair is asserted here too, so nobody can
-- quietly re-break it.

begin;
set search_path = public, extensions, tests;
select plan(35);

-- ─── the fixture is the one §4.4 describes ───────────────────────────────────

select is((select submitter_count::int from public.round_submitter_counts
            where round_id = tests.round_on('2026-08-08')),
          8, 'S = 8 — Ivy did not submit');
select is((select denominator::int from public.round_submitter_counts
            where round_id = tests.round_on('2026-08-08')),
          7, 'S − 1 = 7, the denominator of both rates');

-- ─── ear, per §4.4 ───────────────────────────────────────────────────────────
-- "correct / 7", with Eli excluded for having made no guesses at all.

create or replace function tests.ear_of(p_name text) returns numeric
language sql stable as $$
  select ear from public.round_scores
   where round_id = tests.round_on('2026-08-08') and user_id = tests.person(p_name)
$$;

select is(tests.ear_of('Ana'), (5::numeric / 7), 'Ana ear 5/7');
select is(tests.ear_of('Ben'), (3::numeric / 7), 'Ben ear 3/7 — three blanks count as wrong');
select is(tests.ear_of('Cal'), (7::numeric / 7), 'Cal ear 7/7');
select is(tests.ear_of('Dee'), (2::numeric / 7), 'Dee ear 2/7');
select is(tests.ear_of('Fay'), (4::numeric / 7), 'Fay ear 4/7');
select is(tests.ear_of('Gus'), (1::numeric / 7), 'Gus ear 1/7');
select is(tests.ear_of('Hal'), (4::numeric / 7), 'Hal ear 4/7');

-- The one that the product turns on. docs/02 §4.1: a user who made zero guesses has an
-- undefined ear for the round, and the round is dropped from their average. Rendering this as
-- 0% would turn "you sat out" into "you scored nothing", which is the single judgement this
-- product refuses to make (docs/04 §4).
select ok(tests.ear_of('Eli') is null, 'Eli made no guesses, so Eli has no ear — null, not zero');
select is((select guesses_made from public.round_scores
            where round_id = tests.round_on('2026-08-08') and user_id = tests.person('Eli')),
          null, 'and nothing was recorded as made');

-- ─── readability, per §4.4 (with the seed's recorded repair) ─────────────────
-- Denominator is S−1 whether or not the person guessed: readability measures how much of the
-- room read you, and a room that did not look is a room that did not read you.

create or replace function tests.read_of(p_name text) returns numeric
language sql stable as $$
  select readability from public.round_scores
   where round_id = tests.round_on('2026-08-08') and user_id = tests.person(p_name)
$$;

select is(tests.read_of('Ana'), (6::numeric / 7), 'Ana readability 6/7');
select is(tests.read_of('Ben'), (5::numeric / 7), 'Ben readability 5/7');
select is(tests.read_of('Cal'), (3::numeric / 7), 'Cal readability 3/7');
select is(tests.read_of('Dee'), (4::numeric / 7), 'Dee readability 4/7');
select is(tests.read_of('Fay'), (2::numeric / 7), 'Fay readability 2/7');
select is(tests.read_of('Gus'), (1::numeric / 7), 'Gus readability 1/7 — the seed''s repair');
select is(tests.read_of('Hal'), (4::numeric / 7), 'Hal readability 4/7 — the seed''s repair');

-- §4.4 calls this out explicitly, and it is the asymmetry that makes non-participation
-- everybody's problem rather than only the absentee's.
select is(tests.read_of('Eli'), (1::numeric / 7),
          'Eli guessed nothing and still has a readability');

-- ─── Ivy: no card, no row ────────────────────────────────────────────────────
-- A non-submitter has neither value and must not appear as a zero anywhere (docs/02 §4.1).

select is((select count(*)::int from public.round_scores
            where round_id = tests.round_on('2026-08-08') and user_id = tests.person('Ivy')),
          0, 'Ivy did not submit, so Ivy is absent from the round entirely');
select is((select count(*)::int from public.round_scores
            where round_id = tests.round_on('2026-08-08')),
          8, 'eight rows, one per submitter');

-- ─── the duplicate rule — docs/02 §4.3 ───────────────────────────────────────
-- Ana and Ben both dropped *Ribs*. Naming either of them, on either card, is correct.

select is((select count(*)::int
             from public.guess_results
            where round_id = tests.round_on('2026-08-08')
              and submission_id = tests.card_of('2026-08-08', 'Ben')
              and guessed_user_id = tests.person('Ana')
              and is_correct),
          (select count(*)::int
             from public.guesses
            where round_id = tests.round_on('2026-08-08')
              and submission_id = tests.card_of('2026-08-08', 'Ben')
              and guessed_user_id = tests.person('Ana')),
          'every guess of "Ana" on Ben''s card is correct — they dropped the same track');
select ok((select count(*) from public.guess_results
            where round_id = tests.round_on('2026-08-08')
              and submission_id = tests.card_of('2026-08-08', 'Ben')
              and guessed_user_id = tests.person('Ana')
              and is_correct) > 0,
          'and there is at least one, so the assertion above is not vacuous');

-- The same guess counts twice over: toward the guesser's ear, and toward the readability of
-- the card's actual owner. §4.4's note that duplicates inflate readability for both owners.
select is((select count(*)::int from public.guess_results
            where round_id = tests.round_on('2026-08-08') and is_correct),
          26, 'twenty-six correct guesses in the round');
select is((select sum(readability_correct)::int from public.round_scores
            where round_id = tests.round_on('2026-08-08')),
          26, 'readability numerators sum to the same 26');
select is((select sum(ear_correct)::int from public.round_scores
            where round_id = tests.round_on('2026-08-08')),
          26, 'and so do the ear numerators — the fixture is internally consistent');

-- Correctness must never be "did the guessed person own this card". If it were, the two
-- duplicate cards would score differently from every other card.
select ok(
  not exists (
    select 1 from public.guess_results
     where round_id = tests.round_on('2026-08-08')
       and is_correct
       and guessed_user_id <> card_owner_id
       and guessed_user_id not in (tests.person('Ana'), tests.person('Ben'))),
  'the only correct guesses naming someone other than the card owner are the Ribs pair');

-- ─── voided and revealed rounds contribute nothing ───────────────────────────
-- docs/02 §4.2 and §3: a voided round is excluded from everything, and a revealed round is not
-- finished — its sheets are still being edited.

select is((select count(*)::int from public.round_scores
            where round_id = tests.round_on('2026-08-09')),
          0, 'the revealed round has no scores yet, though it has guesses');
select ok((select count(*) from public.guesses where round_id = tests.round_on('2026-08-09')) > 0,
          'and it really does have guesses, so that is not vacuous either');

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e5060000-0000-4000-8000-000000000001', tests.the_group(), date '2031-05-01', 'voided',
        '2031-05-01T10:00:00Z', '2031-05-01T20:00:00Z', '2031-05-01T22:00:00Z');
insert into public.submissions (id, round_id, user_id, track_key, track_meta)
values ('e5060000-0000-4000-8000-000000000011', 'e5060000-0000-4000-8000-000000000001',
        tests.person('Ana'), 'isrc:E506VOID001', '{}'::jsonb),
       ('e5060000-0000-4000-8000-000000000012', 'e5060000-0000-4000-8000-000000000001',
        tests.person('Ben'), 'isrc:E506VOID002', '{}'::jsonb);

select is((select count(*)::int from public.round_submitter_counts
            where round_id = 'e5060000-0000-4000-8000-000000000001'),
          0, 'a voided round is not in round_submitter_counts');
select is((select count(*)::int from public.round_scores
            where round_id = 'e5060000-0000-4000-8000-000000000001'),
          0, 'and contributes no scores');

-- ─── the index the duplicate join needs ──────────────────────────────────────
-- docs/03: `submissions_round_trackkey` exists for exactly this correlated existence test. On
-- a nine-row fixture the planner will sensibly seq-scan, so asserting the plan here would
-- assert the fixture's size rather than the schema. Assert the index instead, and leave the
-- plan check to a data volume that can justify one.

select has_index('public', 'submissions', 'submissions_round_trackkey',
                 'the duplicate-rule join has its index');
select is(
  (select array_agg(a.attname::text order by a.attnum)
     from pg_index i
     join pg_class c on c.oid = i.indexrelid
     join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
    where c.relname = 'submissions_round_trackkey'),
  array['round_id', 'track_key'],
  'and it is on (round_id, track_key), which is the join predicate');

-- ─── the views are locked down like the tables ───────────────────────────────
-- A view over locked tables that ran as its owner would be a way around 0003. These run as the
-- invoker, so they inherit the wall rather than tunnelling under it.

select ok(
  (select bool_and((reloptions::text[] @> array['security_invoker=on'])
                   or (reloptions::text[] @> array['security_invoker=true']))
     from pg_class
    where relname in ('round_submitter_counts', 'guess_results', 'round_scores', 'standings')
      and relkind = 'v'),
  'every scoring view is security_invoker');

select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('round_submitter_counts', 'guess_results', 'round_scores', 'standings')
      and grantee in ('anon', 'authenticated')),
  0, 'and neither anon nor authenticated holds any grant on them');

select * from finish();
rollback;
