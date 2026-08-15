-- The App Review demo environment: a group whose rounds advance on the reviewer's actions
-- rather than on the clock (20260815090000, 20260815090500).
--
-- Two things this file has to prove, and the second matters more than the first:
--
--   1. The loop works at an arbitrary hour — drop, seal, reveal, guess, results, and around
--      again — with no wall-clock wait anywhere in it. Every instant below comes from
--      `tests.set_test_now()`, and the reviewer's session starts at 03:17 in the morning to
--      make the point that the hour is irrelevant.
--   2. **Nothing leaks between the two worlds.** A demo group is invisible to `ensure_rounds()`
--      and to all three `tick_rounds()` loops, and a real group is untouched by `demo_arm()`.
--      The seed's own group runs its real lifecycle in the same transaction, precisely so that
--      a regression in the exclusion shows up here as two failures rather than none.
--
-- All times are UTC; the demo group is America/Los_Angeles, so 10:17Z is 03:17 local and the
-- whole played session below sits inside local 2026-08-15.
begin;
set search_path = public, extensions, tests;
select plan(38);

-- ─── a demo group, via the cohort that creates one ───────────────────────────
-- `seed.sql` disables every cohort locally, so that a `PUT /me` in the Edge Function suite
-- does not silently enrol a test user. This suite is one of the two that wants one to fire.

update public.pilot_cohorts set enabled = true where name = 'App Review';

insert into auth.users (id) values ('d0000000-0000-4000-8000-000000000001');
insert into public.profiles (id, display_name)
  values ('d0000000-0000-4000-8000-000000000001', 'Whoever');

select isnt(public.assign_pilot_cohort('d0000000-0000-4000-8000-000000000001'), null::uuid,
  'the App Review cohort admits its one reviewer');

create or replace function tests.demo_group() returns uuid
language sql stable as $$
  select group_id from public.pilot_cohorts where name = 'App Review'
$$;

create or replace function tests.demo_round() returns uuid
language sql stable as $$
  select r.id from public.rounds r
   join public.groups g on g.id = r.group_id
  where r.group_id = tests.demo_group()
    and r.local_date = pg_catalog.timezone(g.timezone, public.now_())::date
$$;

create or replace function tests.demo_state() returns text
language sql stable as $$
  select state::text from public.rounds where id = tests.demo_round()
$$;

create or replace function tests.demo_rounds() returns int
language sql stable as $$
  select count(*)::int from public.rounds where group_id = tests.demo_group()
$$;

select ok((select is_demo from public.groups where id = tests.demo_group()),
  'the cohort flag lands on the group it creates');
select ok(not (select bool_or(is_demo) from public.groups where id <> tests.demo_group()),
  'no other group is a demo group');

-- ─── provisioning ────────────────────────────────────────────────────────────
-- 03:17 local. Nowhere near a reveal hour, which is the entire point.

select tests.set_test_now('2026-08-15 10:17:00+00');
select public.demo_provision(tests.demo_group());

select is((select display_name from public.profiles
            where id = 'd0000000-0000-4000-8000-000000000001'),
  'App Reviewer', 'the founding member is renamed for review');
select is((select count(*)::int from public.demo_companions
            where group_id = tests.demo_group()), 3,
  'three companions join the demo group');
select is((select count(*)::int from public.rounds
            where group_id = tests.demo_group() and state = 'scored'), 3,
  'three finished nights are in the archive before the reviewer opens the app');
select is((select count(distinct is_correct)::int from public.guess_results gr
            join public.rounds r on r.id = gr.round_id
           where r.group_id = tests.demo_group()), 2,
  'the archive holds both hits and misses, so results and standings look played');

-- ─── the live round, before the reviewer drops ───────────────────────────────

select is(tests.demo_state(), 'open', 'a live open round exists at 03:17');
select is((select count(*)::int from public.submissions where round_id = tests.demo_round()), 3,
  'the companions are already in it; the reviewer is the only one outstanding');
select is((select reveals_at from public.rounds where id = tests.demo_round()),
  '2026-08-16 03:00:00+00'::timestamptz,
  'and it carries the real schedule — tonight''s 20:00 — until the reviewer acts');

-- ─── the scheduler cannot see any of this ────────────────────────────────────
-- 20:30 local, so the demo round is past its own reveals_at with a room that is one short.
-- In a real group that combination reveals or voids. Here it must do nothing whatsoever.

select tests.set_test_now('2026-08-16 03:30:00+00');
select public.tick_rounds();

select is(tests.demo_state(), 'open',
  'tick_rounds() does not reveal a demo round whose reveal hour has passed');
select is(tests.demo_rounds(), 4,
  'and ensure_rounds() materialises nothing for a demo group');
select is((select count(*)::int from public.notification_outbox o
            join public.rounds r on r.id = o.round_id
           where r.group_id = tests.demo_group()), 0,
  'nor is a single notification enqueued for one');
select is((select count(*)::int from public.rounds r
           where r.group_id = tests.demo_group() and r.state = 'voided'), 0,
  'a demo round is never voided, however few have dropped');

-- The same call, in the same transaction, ran the seed group's lifecycle for real: its
-- `revealed` round of 2026-08-09 is hours past its scores_at by now.
select is((select state::text from public.rounds where id = tests.round_on('2026-08-09')),
  'scored', 'while the seed group''s real lifecycle still ran');

-- A demo round nobody played slides to the next reveal rather than stalling or voiding.
select public.demo_tick(tests.demo_group());
select is((select reveals_at from public.rounds where id = tests.demo_round()),
  '2026-08-17 03:00:00+00'::timestamptz,
  'an unplayed demo round slides to the next reveal rather than revealing without its room');
select is(tests.demo_state(), 'open', 'and stays open');

-- ─── drop → seal → reveal ────────────────────────────────────────────────────
-- 21:00 local: past tonight's reveal hour, which for a real group is the dead zone this
-- whole feature exists to escape.

select tests.set_test_now('2026-08-16 04:00:00+00');
insert into public.submissions (round_id, user_id, track_key, track_meta)
values (tests.demo_round(), 'd0000000-0000-4000-8000-000000000001',
        public.demo_track(0) ->> 'track_key', public.demo_track(0));
select public.demo_arm(tests.demo_round(), 12);

select is((select reveals_at from public.rounds where id = tests.demo_round()),
  '2026-08-16 04:00:12+00'::timestamptz, 'sealing arms the reveal twelve seconds out');
select ok((select opens_at <= reveals_at and reveals_at <= scores_at
             from public.rounds where id = tests.demo_round()),
  'and the round still makes sense: open before reveal, reveal before score');

select tests.set_test_now('2026-08-16 04:00:11+00');
select public.demo_tick(tests.demo_group());
select is(tests.demo_state(), 'open', 'one second early is still open');

select tests.set_test_now('2026-08-16 04:00:13+00');
select public.demo_tick(tests.demo_group());
select is(tests.demo_state(), 'revealed', 'and the countdown reaching zero reveals it');
select is((select jsonb_array_length(card_order) from public.rounds where id = tests.demo_round()),
  4, 'with all four cards in the shuffled order');

-- ─── guess → score ───────────────────────────────────────────────────────────

select public.demo_arm(tests.demo_round(), 180);
select is((select scores_at from public.rounds where id = tests.demo_round()),
  '2026-08-16 04:03:13+00'::timestamptz,
  'a partial sheet gets the three-minute backstop');

-- The reveal instant must not move here. `cannotGuessReason()` compares it against the
-- caller's `joined_at`, so a demo_arm that dragged it backwards would tell a reviewer who
-- signed in this evening that they had joined too late to guess — the constraint satisfied
-- and the game broken.
select public.demo_arm(tests.demo_round(), 20);
select is((select scores_at from public.rounds where id = tests.demo_round()),
  '2026-08-16 04:00:33+00'::timestamptz, 'completing the sheet pulls the score in to twenty');
select is((select reveals_at from public.rounds where id = tests.demo_round()),
  '2026-08-16 04:00:12+00'::timestamptz,
  'and leaves the reveal instant alone, so nobody is told they joined late');

select tests.set_test_now('2026-08-16 04:00:34+00');
select public.demo_tick(tests.demo_group());
select is(tests.demo_state(), 'scored', 'and the answers land');

-- ─── around again ────────────────────────────────────────────────────────────

select public.demo_tick(tests.demo_group());
select is(tests.demo_state(), 'scored',
  'a results screen is not pulled out from under someone still reading it');

select tests.set_test_now('2026-08-16 04:03:00+00');
select public.demo_tick(tests.demo_group());
select is(tests.demo_state(), 'open', 'two minutes later a fresh round is open');
select is((select count(*)::int from public.submissions where round_id = tests.demo_round()), 3,
  'with the companions in it and the reviewer outstanding again');
select is((select count(*)::int from public.rounds
            where group_id = tests.demo_group() and state = 'scored'), 4,
  'and the night just played joins the archive');
select is((select max(local_date) from public.rounds
            where group_id = tests.demo_group() and state = 'scored'),
  '2026-08-14'::date,
  'as yesterday — The Record reads newest first, so it lands at the top rather than the bottom');

-- ─── across local midnight ───────────────────────────────────────────────────
-- The round the reviewer is in the middle of is carried to the new date, not abandoned there
-- and replaced. Otherwise a session that straddles midnight strands an open round the tick
-- would re-anchor nightly for ever, and loses the companion submissions already in it.

select tests.set_test_now('2026-08-16 08:00:00+00');   -- 01:00 local, the next day
select public.demo_tick(tests.demo_group());
select is(tests.demo_rounds(), 5,
  'crossing midnight carries the unplayed round rather than opening a second one');
select is(tests.demo_state(), 'open', 'and it is still the round they were in');

-- ─── marking a group that already has rounds ─────────────────────────────────
-- The production case, and the one 20260815090000 alone does not cover: the App Review group
-- was created before its cohort was ever flagged, so `assign_pilot_cohort()` never carried
-- `is_demo` onto it. 20260815120000 backfills it, and the propagation trigger has to reach the
-- rounds already sitting in the group — otherwise the first `demo_arm()` against one fails
-- `rounds_window` on a round still holding a real round's constraint.

update public.groups set is_demo = true where id = tests.the_group();
select ok((select bool_and(is_demo) from public.rounds where group_id = tests.the_group()),
  'marking an existing group carries is_demo down to the rounds it already has');
update public.groups set is_demo = false where id = tests.the_group();
select ok(not (select bool_or(is_demo) from public.rounds where group_id = tests.the_group()),
  'and unmarking it carries back, so the column can never disagree with the group');

-- ─── demo_arm cannot reach a real group ──────────────────────────────────────

select public.demo_arm(tests.round_on('2026-08-10'), 5);
select isnt((select reveals_at from public.rounds where id = tests.round_on('2026-08-10')),
  '2026-08-16 08:00:05+00'::timestamptz,
  'demo_arm is a no-op outside a demo group');
select ok((select bool_and(scores_at = reveals_at + interval '2 hours'
                       and opens_at = reveals_at - interval '10 hours')
             from public.rounds where not is_demo),
  'and every non-demo round still keeps the fixed ten-hour/two-hour window');
select ok((select bool_and(is_demo) from public.rounds where group_id = tests.demo_group()),
  'the demo flag reaches every round in the group by trigger, never by the writer');

select * from finish();
rollback;
