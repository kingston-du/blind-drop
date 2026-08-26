-- notification_settle.sql — E31-01, docs/05 §3.
--
-- claim_notification_outbox's audience-trim for seal_reminder/guess_reminder lives inside the
-- same UPDATE that claims the row (20260826120100_conditional_reminders.sql) rather than as a
-- second, independent data-modifying CTE, because Postgres does not define what happens when two
-- CTEs in one statement touch the same row — and a row due to settle is usually also due to
-- claim. This file exercises that trim directly against the function, at the granularity of one
-- recipient inside a shared audience, which is the part the fixture-clock walkthrough in
-- push.test.ts (E31-01's Deno coverage) can only exercise indirectly through HTTP.
begin;
set search_path = public, extensions, tests;
select plan(8);

insert into public.rounds
       (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values ('e3150000-0000-4000-8000-000000000001', tests.the_group(), date '2031-05-01', 'open',
        '2031-05-01T10:00:00Z', '2031-05-01T20:00:00Z', '2031-05-01T22:00:00Z');

insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values
  ('e3150000-0000-4000-8000-000000000011', 'e3150000-0000-4000-8000-000000000001',
   tests.person('Cal'), 'isrc:E315SETTLE001', '{}'::jsonb, '2031-05-01T14:00:00Z'),
  ('e3150000-0000-4000-8000-000000000012', 'e3150000-0000-4000-8000-000000000001',
   tests.person('Dee'), 'isrc:E315SETTLE002', '{}'::jsonb, '2031-05-01T14:00:00Z'),
  ('e3150000-0000-4000-8000-000000000013', 'e3150000-0000-4000-8000-000000000001',
   tests.person('Fay'), 'isrc:E315SETTLE003', '{}'::jsonb, '2031-05-01T14:00:00Z');

-- ── seal_reminder: Ana and Ben are enqueued while neither has sealed; Ben then does. ──────────
select tests.set_test_now('2031-05-01T18:00:00Z');
select public.enqueue_round_notification(
  'e3150000-0000-4000-8000-000000000001', 'seal_reminder',
  jsonb_build_array(tests.person('Ana'), tests.person('Ben')),
  '2031-05-01T18:00:00Z'
);
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
values ('e3150000-0000-4000-8000-000000000014', 'e3150000-0000-4000-8000-000000000001',
        tests.person('Ben'), 'isrc:E315SETTLE004', '{}'::jsonb, '2031-05-01T18:05:00Z');

select tests.set_test_now('2031-05-01T18:06:00Z');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3150000-0000-4000-8000-000000000001' and o.kind = 'seal_reminder' $$,
  $$ values (tests.person('Ana')), (tests.person('Ben')) $$,
  'before any claim, the enqueued row still lists both recipients — the trim has not run yet');

select is(
  (select audience from public.claim_notification_outbox(gen_random_uuid(), 20)
    where round_id = 'e3150000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
  jsonb_build_array(tests.person('Ana')),
  'claiming trims Ben, who sealed between enqueue and claim, and returns only Ana');
select set_eq(
  $$ select value::uuid from public.notification_outbox o,
       lateral jsonb_array_elements_text(o.audience) t(value)
       where o.round_id = 'e3150000-0000-4000-8000-000000000001' and o.kind = 'seal_reminder' $$,
  $$ values (tests.person('Ana')) $$,
  'the trim is persisted on the row, not just returned for this one call');

-- ── guess_reminder: Cal (complete) and Dee (partial) are enqueued; Dee then finishes too. ─────
-- This round now has four submitters (Ben sealed above, for the seal_reminder scenario), so a
-- complete sheet here is three guesses (S−1), not two — Cal is given all three below.
select tests.set_test_now('2031-05-01T21:30:00Z');
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id, created_at)
values
  ('e3150000-0000-4000-8000-000000000001', tests.person('Cal'),
   'e3150000-0000-4000-8000-000000000012', tests.person('Dee'), '2031-05-01T20:30:00Z'),
  ('e3150000-0000-4000-8000-000000000001', tests.person('Cal'),
   'e3150000-0000-4000-8000-000000000013', tests.person('Fay'), '2031-05-01T20:30:00Z'),
  ('e3150000-0000-4000-8000-000000000001', tests.person('Cal'),
   'e3150000-0000-4000-8000-000000000014', tests.person('Ben'), '2031-05-01T20:30:00Z'),
  ('e3150000-0000-4000-8000-000000000001', tests.person('Dee'),
   'e3150000-0000-4000-8000-000000000011', tests.person('Cal'), '2031-05-01T20:35:00Z');

select public.enqueue_round_notification(
  'e3150000-0000-4000-8000-000000000001', 'guess_reminder',
  jsonb_build_array(tests.person('Cal'), tests.person('Dee')),
  '2031-05-01T21:30:00Z'
);

-- Dee makes the two remaining guesses a complete (three-card) sheet needs, after enqueue but
-- before claim.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id, created_at)
values
  ('e3150000-0000-4000-8000-000000000001', tests.person('Dee'),
   'e3150000-0000-4000-8000-000000000013', tests.person('Fay'), '2031-05-01T21:35:00Z'),
  ('e3150000-0000-4000-8000-000000000001', tests.person('Dee'),
   'e3150000-0000-4000-8000-000000000014', tests.person('Ben'), '2031-05-01T21:35:00Z');

select is(
  (select audience from public.claim_notification_outbox(gen_random_uuid(), 20)
    where round_id = 'e3150000-0000-4000-8000-000000000001' and kind = 'guess_reminder'),
  '[]'::jsonb,
  'both recipients had already resolved their condition by claim time — the row settles empty');

select is((select sent_at is null from public.notification_outbox
            where round_id = 'e3150000-0000-4000-8000-000000000001' and kind = 'guess_reminder'),
          true,
          'settling to empty does not itself mark sent_at — that is finish_notification_outbox''s '
          'job, exercised by push-worker once it sees zero devices to send to (push.test.ts)');

-- ── a settled row is genuinely reclaimed without error, and stays settled ──────────────────────
-- `claim_notification_outbox`'s own 55-second lease (statement_timestamp(), real wall-clock —
-- not the fixture's mockable now_()) would otherwise skip a row this test only just claimed a
-- few milliseconds of real time ago, making a same-second retry claim nothing and pass
-- vacuously. Backdating claimed_at forces a genuine reclaim of the very rows the trim already
-- touched, which is the actual scenario the single-UPDATE design (comment above) has to survive.
update public.notification_outbox
   set claimed_at = statement_timestamp() - interval '60 seconds'
 where round_id = 'e3150000-0000-4000-8000-000000000001'
   and kind in ('seal_reminder', 'guess_reminder');
select lives_ok(
  $$ select * from public.claim_notification_outbox(gen_random_uuid(), 20)
       where round_id = 'e3150000-0000-4000-8000-000000000001' $$,
  'reclaiming already-trimmed rows is not an error — no "tuple already modified" hazard'
);
select is(
  (select audience from public.notification_outbox
    where round_id = 'e3150000-0000-4000-8000-000000000001' and kind = 'seal_reminder'),
  jsonb_build_array(tests.person('Ana')),
  'the seal_reminder row is unchanged by a second claim — Ana still has not sealed');

-- ── reveal and results keep the old frozen-forever guarantee; claiming never trims them ────────
select public.enqueue_round_notification(
  'e3150000-0000-4000-8000-000000000001', 'reveal',
  jsonb_build_array(tests.person('Ana'), tests.person('Ben'), tests.person('Cal')),
  '2031-05-01T20:00:00Z'
);
-- set_eq, not exact array equality: enqueue_round_notification stores recipients sorted by
-- uuid value, not by the order this test passed them in.
select set_eq(
  $$ select value::uuid from public.claim_notification_outbox(gen_random_uuid(), 20) c,
       lateral jsonb_array_elements_text(c.audience) t(value)
       where c.round_id = 'e3150000-0000-4000-8000-000000000001' and c.kind = 'reveal' $$,
  $$ values (tests.person('Ana')), (tests.person('Ben')), (tests.person('Cal')) $$,
  'reveal is untouched by the settle-check — its audience is frozen at enqueue, same as before E31-01'
);

select * from finish();
rollback;
