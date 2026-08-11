-- standings_perf.sql — the budget, and the plan. tasks/E05-05, and the `explain` assertion
-- E05-03 deliberately deferred to here.
--
-- Two claims, both of which need *data*, which is exactly why neither is in `scoring.sql`:
--
--   1. `GET /groups/current/standings` answers inside 150ms with 12 members and 200 rounds
--      behind it. ADR-004 says scores are derived and never stored; that is only tenable while
--      the derivation is fast, and this is the number that decides it. Over budget, the escape
--      hatch is a materialised view refreshed at score time — **not** a score column on
--      `submissions`.
--   2. The duplicate-track existence test in `guess_results` resolves through an index on
--      `submissions`, keyed on `round_id` — never a scan.
--
-- **On the size of the fixture, because it is the whole difficulty of (2).** E05-03 left the
-- `explain` check unticked and said why: on the nine-row §4.4 fixture the planner correctly
-- chooses a sequential scan, so asserting index usage there would be asserting the fixture's
-- size, and forcing it with `enable_seqscan = off` proves only that the index *can* be used —
-- which `has_index` already said.
--
-- Building the group under test at 12 × 200 is not by itself enough to escape that. With only
-- that group's 2,400 rows in `submissions`, Postgres hashes the whole table once and beats any
-- index fairly; asserting otherwise would be asserting a worse plan. What makes an index the
-- right answer is the thing a live database has and a test fixture usually does not: **other
-- groups.** `submissions` is not partitioned by group, and in production it holds every group's
-- whole history, so the `exists` in `guess_results` is a needle-in-a-large-table lookup. This
-- file therefore seeds fifteen neighbouring groups with a season each, and the planner reaches
-- for an index on its own, without a single planner knob touched.
--
-- **Which index, though — and this is where the fixture disagreed with the spec.** 0005's
-- comment and E05-03's checklist both name `submissions_round_trackkey` as "exactly this join".
-- At a realistic size the planner usually prefers `submissions_one_per_user_per_round` instead,
-- and it is right to: the predicate is three equalities — `round_id`, `user_id`, `track_key` —
-- and the *unique* index on `(round_id, user_id)` finds at most one row and then checks the
-- track, where `(round_id, track_key)` can match several and then filters by user. Which of the
-- two wins moves with the statistics, and both are correct. So the assertions below pin the
-- property that actually matters and is actually stable — the check is a keyed lookup inside
-- one round, not a scan of the table — rather than naming a plan the planner is entitled to
-- improve on. See the open question in tasks/E05.

begin;
set search_path = public, extensions, tests;
set local role postgres;
select plan(11);

-- Codes are drawn from the invite alphabet in 0002, which has no I, L, O, 0 or 1 in it.
create temporary table perf_ids (group_id uuid, member_no int, user_id uuid) on commit drop;

insert into perf_ids (group_id, member_no, user_id)
select 'f0000000-0000-4000-8000-000000000001'::uuid,
       n,
       ('f1000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid
  from generate_series(1, 12) as n;

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, email_change, email_change_token_new, recovery_token)
select '00000000-0000-0000-0000-000000000000', user_id, 'authenticated', 'authenticated',
       'perf-' || member_no || '@fixture.blinddrop.test', now(),
       '{}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''
  from perf_ids;

insert into public.profiles (id, display_name)
select user_id, 'Perf' || lpad(member_no::text, 2, '0') from perf_ids;

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
select 'f0000000-0000-4000-8000-000000000001', 'Perf', 'America/New_York', 20, 'PERF99', user_id
  from perf_ids where member_no = 1;

insert into public.memberships (group_id, user_id, role)
select group_id, user_id, case when member_no = 1 then 'admin' else 'member' end from perf_ids;

-- ─── the group under test: 200 nights ────────────────────────────────────────
-- `card_order` is filled after the submissions exist, because
-- `rounds_card_order_is_permutation_trg` (0002) will not have it any other way.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select ('f2000000-0000-4000-8000-0000000' || lpad(d::text, 5, '0'))::uuid,
       'f0000000-0000-4000-8000-000000000001',
       date '2030-01-01' + d,
       'open',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'America/New_York' - interval '10 hours',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'America/New_York',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'America/New_York' + interval '2 hours'
  from generate_series(0, 199) as d;

-- Twelve submissions a night. Every third round member 2 drops member 1's track — the duplicate
-- case from docs/02 §4.3, so the `(round_id, track_key)` join has somewhere to match twice
-- rather than being uniformly selective and therefore uninteresting.
insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('f3000000-0000-4000-8000-' || lpad(d::text, 6, '0') || lpad(p.member_no::text, 6, '0'))::uuid,
       ('f2000000-0000-4000-8000-0000000' || lpad(d::text, 5, '0'))::uuid,
       p.user_id,
       case when d % 3 = 0 and p.member_no = 2
            then 'isrc:PERF' || lpad(d::text, 5, '0') || '01'
            else 'isrc:PERF' || lpad(d::text, 5, '0') || lpad(p.member_no::text, 2, '0')
       end,
       '{}'::jsonb
  from generate_series(0, 199) as d
  cross join perf_ids p;

update public.rounds r
   set card_order = (select jsonb_agg(s.id order by s.id)
                       from public.submissions s where s.round_id = r.id),
       state = 'revealed'
 where r.group_id = 'f0000000-0000-4000-8000-000000000001';

-- Everybody guesses every card but their own, naming the member one seat along: wrong most of
-- the time, right often enough, and correct twice over on the rounds carrying a duplicate.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select card.round_id,
       g.user_id,
       card.id,
       (select user_id from perf_ids where member_no = (owner.member_no % 12) + 1)
  from public.submissions card
  join perf_ids owner on owner.user_id = card.user_id
  cross join perf_ids g
 where card.round_id in (select id from public.rounds
                          where group_id = 'f0000000-0000-4000-8000-000000000001')
   and g.user_id <> card.user_id
   and (select user_id from perf_ids where member_no = (owner.member_no % 12) + 1) <> g.user_id;

update public.rounds set state = 'scored'
 where group_id = 'f0000000-0000-4000-8000-000000000001';

-- ─── the neighbours ──────────────────────────────────────────────────────────
-- Fifteen other groups with a season behind them. No guesses: their only job is to make
-- `submissions` the size a live table is, because `submissions` is not partitioned by group and
-- the plan for a one-round lookup depends on how much of it there is to avoid reading.

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
select ('f5000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'Neighbour ' || n, 'America/New_York', 20,
       'PADAA' || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', n, 1),
       (select user_id from perf_ids where member_no = 1)
  from generate_series(1, 15) as n;

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select ('f6000000-0000-4000-8000-00000' || lpad(n::text, 2, '0') || lpad(d::text, 5, '0'))::uuid,
       ('f5000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       date '2030-01-01' + d,
       'open',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'UTC' - interval '10 hours',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'UTC',
       ((date '2030-01-01' + d) + time '20:00') at time zone 'UTC' + interval '2 hours'
  from generate_series(1, 15) as n, generate_series(0, 199) as d;

insert into public.submissions (round_id, user_id, track_key, track_meta)
select ('f6000000-0000-4000-8000-00000' || lpad(n::text, 2, '0') || lpad(d::text, 5, '0'))::uuid,
       p.user_id,
       'isrc:PAD' || lpad(n::text, 2, '0') || lpad(d::text, 5, '0') || lpad(p.member_no::text, 2, '0'),
       '{}'::jsonb
  from generate_series(1, 15) as n, generate_series(0, 199) as d
  cross join perf_ids p;

analyze public.submissions;
analyze public.guesses;
analyze public.rounds;

-- ─── the fixture is the size it claims to be ─────────────────────────────────

select is((select count(*)::int from public.rounds
            where group_id = 'f0000000-0000-4000-8000-000000000001'),
          200, '200 scored rounds in the group under test');
select is((select count(*)::int from public.submissions s
            join public.rounds r on r.id = s.round_id
           where r.group_id = 'f0000000-0000-4000-8000-000000000001'),
          2400, '12 submitters a night, 2400 submissions');
select ok((select count(*) from public.guesses g
            join public.rounds r on r.id = g.round_id
           where r.group_id = 'f0000000-0000-4000-8000-000000000001') > 20000,
          'and north of twenty thousand guesses to aggregate');
select ok((select count(*) from public.submissions) > 30000,
          'submissions holds the neighbours too — a live table, not a lonely one');
select is((select count(*)::int from public.standings
            where group_id = 'f0000000-0000-4000-8000-000000000001'),
          12, 'a standings row for each of the twelve');

-- ─── 1. the 150ms budget ─────────────────────────────────────────────────────
-- Best of three. The budget is about the query's steady state, which is what a member
-- refreshing the results screen meets; charging it for a cold buffer cache would be measuring
-- whichever machine happened to run the suite.
--
-- `row_to_json` is not decoration. `count(*)` over the view lets the planner prune every
-- computed column — including the correlated `exists` behind `is_correct` — and answer in a
-- fraction of the time by never doing the work the endpoint needs done. Referencing the whole
-- row forces the values to actually be produced, which is what `GET /groups/current/standings`
-- asks for.

create or replace function tests.standings_ms() returns numeric
language plpgsql as $$
declare
  v_started timestamptz;
  v_best    numeric := null;
  v_taken   numeric;
  v_sink    bigint;
begin
  for i in 1..3 loop
    v_started := clock_timestamp();
    select count(row_to_json(t)) into v_sink
      from (select user_id, ear_all_time, ear_correct_total, readability_all_time, band
              from public.standings
             where group_id = 'f0000000-0000-4000-8000-000000000001') t;
    v_taken := extract(epoch from (clock_timestamp() - v_started)) * 1000;
    if v_best is null or v_taken < v_best then v_best := v_taken; end if;
  end loop;
  return v_best;
end $$;

select ok(tests.standings_ms() < 150,
          format('standings answers inside 150ms at 12 members x 200 rounds (best of 3: %sms)',
                 round(tests.standings_ms(), 1)));

-- ─── 2. the plan ─────────────────────────────────────────────────────────────
-- The assertion E05-03 deferred. This is the query behind `GET /rounds/{id}/results`: one
-- round's guesses, resolved against a `submissions` table holding every group's history.
-- `guess_results` decides correctness with an `exists` on `(round_id, user_id, track_key)`, and
-- `submissions_round_trackkey` is the index built for it. No planner setting is touched — if
-- the index stops being the obvious choice, that is the regression.

-- `explain` is a utility statement, so its output cannot be selected from directly. A plpgsql
-- wrapper that iterates it is the plain way to get the plan into a table.
create or replace function tests.explain_lines(p_sql text) returns setof text
language plpgsql as $$
declare r record;
begin
  for r in execute 'explain ' || p_sql loop
    return next r."QUERY PLAN";
  end loop;
end $$;

create temporary table perf_plan (line text) on commit drop;

insert into perf_plan
select tests.explain_lines(
  'select * from public.guess_results where round_id = ''f2000000-0000-4000-8000-000000000100''');

select ok((select bool_or(line like '%Index Scan using %on submissions dup%') from perf_plan),
          'the "did they drop this track?" test is an index scan on submissions');
select ok((select bool_or(line like '%Index Cond: ((round_id =%') from perf_plan),
          'keyed on round_id first, so it never looks outside the round');
select ok((select bool_or(line like '%using submissions_round_trackkey%'
                       or line like '%using submissions_one_per_user_per_round%')
             from perf_plan),
          'through one of the two round-keyed indexes, whichever the planner prefers');
select ok((select not bool_or(line like '%Seq Scan on submissions dup%') from perf_plan),
          'and never sequentially — a scan per guess is the regression this catches');

-- ─── and the numbers still hold at this size ─────────────────────────────────
-- A perf fixture that produced wrong numbers would only prove we can be wrong quickly. Member 1
-- is named on every one of their cards by member 12, and the duplicate on every third round
-- means member 1 is also read correctly whenever somebody names member 2 — so their readability
-- is above the 1/11 that a single reader alone would give.

select ok((select readability_all_time from public.standings
            where group_id = 'f0000000-0000-4000-8000-000000000001'
              and user_id = (select user_id from perf_ids where member_no = 1))
          between (1.0 / 11) and 1,
          'readability stays a rate, and the duplicate rule still lifts it, across 200 rounds');

select * from finish();
rollback;
