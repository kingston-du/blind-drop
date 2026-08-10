-- constraints.sql — tasks/E01-03, AC-5, AC-6. One case per invariant in docs/02 §5.
--
-- These are the last line of defence if an Edge Function's authorization has a hole, so
-- every case here is a *direct SQL write*, bypassing every application-level check.
begin;
set search_path = public, extensions, tests;
select plan(22);

-- Handles into the seed (docs/02 §4.4 fixture).
create temporary table h as
select tests.round_on('2026-08-08') as scored_round,
       tests.round_on('2026-08-09') as revealed_round,
       tests.round_on('2026-08-10') as open_round,
       tests.person('Ana') as ana, tests.person('Ben') as ben,
       tests.person('Cal') as cal, tests.person('Ivy') as ivy,
       tests.card_of('2026-08-08','Ana') as ana_card,
       tests.card_of('2026-08-08','Cal') as cal_card;

-- ─── Invariant 1 — state only moves forward along docs/02 §2 ─────────────────
select throws_ok(
  format($$ update public.rounds set state = 'open' where id = %L $$, (select scored_round from h)),
  'P0001', null, '1: scored cannot go back to open');
select throws_ok(
  format($$ update public.rounds set state = 'open' where id = %L $$, (select revealed_round from h)),
  'P0001', null, '1: revealed cannot go back to open — there is no un-reveal');
select throws_ok(
  format($$ update public.rounds set state = 'revealed' where id = %L $$, (select scored_round from h)),
  'P0001', null, '1: scored cannot go back to revealed');
select lives_ok(
  format($$ update public.rounds set state = 'scored' where id = %L $$, (select revealed_round from h)),
  '1: revealed -> scored is allowed');

-- ─── Invariant 2 — card_order is non-null iff state ∈ {revealed, scored} ─────
select throws_ok(
  format($$ update public.rounds set card_order = '[]'::jsonb where id = %L $$,
         (select open_round from h)),
  '23514', null, '2: an open round cannot carry a card_order');
select throws_ok(
  format($$ update public.rounds set state = 'voided', card_order = '[]'::jsonb where id = %L $$,
         (select open_round from h)),
  '23514', null, '2: a voided round cannot carry a card_order');
select throws_ok(
  format($$ update public.rounds set card_order = null where id = %L $$,
         (select revealed_round from h)),
  '23514', null, '2: a revealed round cannot have a null card_order');

-- ─── Invariant 3 — card_order is a permutation of the round's submissions ────
-- Deferred to commit, so the test forces the check with SET CONSTRAINTS.
select throws_ok($$
  do $x$
  begin
    update public.rounds set card_order = card_order || to_jsonb(gen_random_uuid()::text)
      where local_date = '2026-08-08';
    set constraints all immediate;
  end $x$
$$, 'P0001', null, '3: card_order cannot be longer than the submission list');

select throws_ok($$
  do $x$
  begin
    update public.rounds set card_order = card_order - 0 where local_date = '2026-08-08';
    set constraints all immediate;
  end $x$
$$, 'P0001', null, '3: card_order cannot be shorter than the submission list');

select throws_ok($$
  do $x$
  begin
    update public.rounds
       set card_order = jsonb_set(card_order, '{0}', to_jsonb(gen_random_uuid()::text))
     where local_date = '2026-08-08';
    set constraints all immediate;
  end $x$
$$, 'P0001', null, '3: card_order cannot name a submission from another round');

select is(
  (select jsonb_array_length(card_order) from public.rounds where local_date = '2026-08-08'),
  (select count(*)::int from public.submissions where round_id = (select scored_round from h)),
  '3: the seeded card_order length equals the submission count');

-- ─── Invariant 4 — a guess never crosses rounds ─────────────────────────────
select throws_ok(
  format($$ insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
            values (%L, %L, %L, %L) $$,
         (select revealed_round from h), (select ana from h),
         (select cal_card from h), (select ben from h)),
  'P0001', 'guess round_id does not match submission round',
  '4: a guess cannot point at a submission from a different round');

-- ─── Invariant 5 — only submitters may guess (AC-6) ─────────────────────────
-- Ivy did not submit in the 2026-08-08 round.
select throws_ok(
  format($$ insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
            values (%L, %L, %L, %L) $$,
         (select scored_round from h), (select ivy from h),
         (select cal_card from h), (select ben from h)),
  'P0001', 'guesser did not submit in this round',
  '5: a non-submitter cannot guess, even by direct insert');

-- ─── Invariant 6 — you cannot name yourself ─────────────────────────────────
select throws_ok(
  format($$ insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
            values (%L, %L, %L, %L) $$,
         (select scored_round from h), (select ana from h),
         (select cal_card from h), (select ana from h)),
  '23514', null, '6: guessed_user_id cannot equal guesser_id');

-- ─── Invariant 7 — you cannot guess on your own card ────────────────────────
select throws_ok(
  format($$ insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
            values (%L, %L, %L, %L) $$,
         (select scored_round from h), (select ana from h),
         (select ana_card from h), (select ben from h)),
  'P0001', 'cannot guess on own card',
  '7: a guesser cannot guess on their own submission');

-- ─── Invariant 8 — one submission per user per round ────────────────────────
select throws_ok(
  format($$ insert into public.submissions (round_id, user_id, track_key, track_meta)
            values (%L, %L, 'isrc:USUM71311296', '{}'::jsonb) $$,
         (select scored_round from h), (select ana from h)),
  '23505', null, '8: a user cannot have two submissions in one round');

-- ─── Invariant 9 — one guess per (round, card) ──────────────────────────────
select throws_ok(
  format($$ insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
            values (%L, %L, %L, %L) $$,
         (select scored_round from h), (select ana from h),
         (select cal_card from h), (select ben from h)),
  '23505', null, '9: a guesser cannot hold two guesses on one card');

-- ─── Invariant 10 — voided rounds contribute to no aggregate ────────────────
-- A voided round can never hold a card_order, so it has no cards and no guesses can be
-- attached to it in the reveal sense. The aggregate half of this invariant is asserted
-- against the scoring views in E05-03 (tests/db/scoring.sql), which do not exist yet.
select is(
  (select count(*)::int from public.rounds r
   where r.state = 'voided' and r.card_order is not null),
  0, '10: no voided round carries a card_order');

-- ─── Invariant 11 — the window is exactly 10h before / 2h after ─────────────
select throws_ok(
  format($$ update public.rounds set scores_at = reveals_at + interval '3 hours'
            where id = %L $$, (select open_round from h)),
  '23514', null, '11: the guess window is always exactly two hours');
select throws_ok(
  format($$ update public.rounds set opens_at = reveals_at - interval '9 hours'
            where id = %L $$, (select open_round from h)),
  '23514', null, '11: submissions always open exactly ten hours before the reveal');
select is(
  (select count(*)::int from public.rounds
   where scores_at <> reveals_at + interval '2 hours'
      or opens_at  <> reveals_at - interval '10 hours'),
  0, '11: every seeded round obeys the window');

-- ─── The duplicate-track rule is never blocked (AC-7) ───────────────────────
-- Two people submitting the same track must be accepted without a murmur — a rejection
-- would itself leak that the song is already in play (docs/02 §3).
select lives_ok(
  format($$ insert into public.submissions (round_id, user_id, track_key, track_meta)
            values (%L, %L,
                    (select track_key from public.submissions where id = %L),
                    '{}'::jsonb) $$,
         (select open_round from h), (select ivy from h),
         (select cal_card from h)),
  'AC-7: a duplicate track_key is accepted with no signal');

select * from finish();
rollback;
