-- standings_window.sql — Best Ear ranks on a moving window, not an all-time rate.
--
-- 20260909140000 added `ear_reads`: correct guesses over the **group's** last 14 scored rounds.
-- Two properties make it the ranked figure, and neither is provable on a rate:
--
--   1. **A night you skipped counts as zero for you**, because the window is the group's and
--      you are in it whether or not you showed up. Scoped to the member instead, a five-nights-
--      a-month player is measured only on the nights they chose, which is the hole this closes.
--   2. **A perfect rate on a thin, old record ranks nowhere.** Ben below guesses four cards and
--      gets four right; every one of them falls outside the window, so the board says 0.
--
-- Sixteen rounds of three submitters are built here, so rounds fall off the back and the
-- boundary is a real edge rather than a hypothetical one. The seed's round (2026-08-08) is
-- older than all of them and sits outside the window throughout, which is itself the point of
-- assertion 2.

begin;
set search_path = public, extensions, tests;
select plan(10);

-- ─── sixteen nights ──────────────────────────────────────────────────────────
-- Ana, Ben and Cal drop in every one. S = 3, so S−1 = 2 and a perfect night is two reads.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order)
select ('e5071000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       tests.the_group(),
       date '2032-01-01' + (n - 1),
       'open',
       (date '2032-01-01' + (n - 1))::timestamptz + interval '10 hours',
       (date '2032-01-01' + (n - 1))::timestamptz + interval '20 hours',
       (date '2032-01-01' + (n - 1))::timestamptz + interval '22 hours',
       null
  from generate_series(1, 16) as n;

insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('e5072000-0000-4000-8000-00000000' || lpad(n::text, 2, '0') || lpad(p.idx::text, 2, '0'))::uuid,
       ('e5071000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       tests.person(p.name),
       'isrc:E507R' || n || 'P' || p.idx,
       '{}'::jsonb
  from generate_series(1, 16) as n,
       (values (1, 'Ana'), (2, 'Ben'), (3, 'Cal')) as p(idx, name);

-- Ana names the true owner of both cards, every night. Two reads a night, sixteen nights.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select s.round_id, tests.person('Ana'), s.id, s.user_id
  from public.submissions s
  join public.rounds r on r.id = s.round_id
 where r.group_id = tests.the_group()
   and r.local_date between date '2032-01-01' and date '2032-01-16'
   and s.user_id <> tests.person('Ana');

-- Ben is perfect on the first two nights and never opens the sheet again. Both nights fall
-- outside the window by the time the sixteenth round scores.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select s.round_id, tests.person('Ben'), s.id, s.user_id
  from public.submissions s
  join public.rounds r on r.id = s.round_id
 where r.group_id = tests.the_group()
   and r.local_date between date '2032-01-01' and date '2032-01-02'
   and s.user_id <> tests.person('Ben');

-- Cal turns up for the last fourteen and gets one of his two right each time. Half Ben's rate,
-- and it is Cal who will be ahead.
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select s.round_id, tests.person('Cal'), s.id, s.user_id
  from public.submissions s
  join public.rounds r on r.id = s.round_id
 where r.group_id = tests.the_group()
   and r.local_date between date '2032-01-03' and date '2032-01-16'
   and s.user_id = tests.person('Ana');

update public.rounds
   set card_order = (select jsonb_agg(s.id order by s.id)
                       from public.submissions s where s.round_id = public.rounds.id),
       state = 'revealed'
 where group_id = tests.the_group()
   and local_date between date '2032-01-01' and date '2032-01-16';
update public.rounds set state = 'scored'
 where group_id = tests.the_group()
   and local_date between date '2032-01-01' and date '2032-01-16';

-- ─── the window is fourteen rounds wide ──────────────────────────────────────

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          28, 'Ana reads both cards on all sixteen nights; only the last fourteen count');

select ok((select ear_correct_total from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group())
          > (select ear_reads from public.standings
              where user_id = tests.person('Ana') and group_id = tests.the_group()),
          'the rounds that fell off the back are still in the all-time total, just not the rank');

-- ─── a perfect rate outside the window ranks nowhere ─────────────────────────

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()),
          0, 'Ben guessed four cards and got four right, all of them too long ago: zero reads');

select ok((select ear_all_time from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()) > 0.5,
          'while his all-time rate stays healthy — which is exactly what the board stopped using');

select is((select rounds_played::int from public.standings
            where user_id = tests.person('Ben') and group_id = tests.the_group()),
          17, 'and he was present for every one of them, so the zero is turnout, not absence');

-- ─── turning up beats a better rate ──────────────────────────────────────────

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Cal') and group_id = tests.the_group()),
          14, 'Cal gets one of two right, fourteen nights running');

select ok((select ear_reads from public.standings
            where user_id = tests.person('Cal') and group_id = tests.the_group())
          > (select ear_reads from public.standings
              where user_id = tests.person('Ben') and group_id = tests.the_group()),
          'so Cal is ahead of Ben on half his accuracy — the whole point of the change');

-- ─── a seventeenth night: the window is a treadmill ──────────────────────────
-- One round on the front pushes one off the back. Ana, who is perfect throughout, does not
-- climb; Cal, who sat this one out, drops by exactly the night that left.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order)
values ('e5071000-0000-4000-8000-000000000017', tests.the_group(), date '2032-01-17', 'open',
        '2032-01-17T10:00:00Z', '2032-01-17T20:00:00Z', '2032-01-17T22:00:00Z', null);

insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('e5072000-0000-4000-8000-0000000017' || lpad(p.idx::text, 2, '0'))::uuid,
       'e5071000-0000-4000-8000-000000000017',
       tests.person(p.name),
       'isrc:E507R17P' || p.idx,
       '{}'::jsonb
  from (values (1, 'Ana'), (2, 'Ben'), (3, 'Cal')) as p(idx, name);

insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select s.round_id, tests.person('Ana'), s.id, s.user_id
  from public.submissions s
 where s.round_id = 'e5071000-0000-4000-8000-000000000017'
   and s.user_id <> tests.person('Ana');

update public.rounds
   set card_order = (select jsonb_agg(s.id order by s.id)
                       from public.submissions s where s.round_id = public.rounds.id),
       state = 'revealed'
 where id = 'e5071000-0000-4000-8000-000000000017';
update public.rounds set state = 'scored'
 where id = 'e5071000-0000-4000-8000-000000000017';

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          28, 'a perfect seventeenth night leaves Ana exactly where she was: one on, one off');

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Cal') and group_id = tests.the_group()),
          13, 'and Cal, who sat it out, loses the night that fell off the back');

-- ─── only scored rounds enter the window ─────────────────────────────────────
-- An eighteenth night, revealed but not yet scored, is newer than everything above. If it
-- entered the window it would push 2032-01-04 off and move both numbers. It must not: the
-- window is built on `round_submitter_counts`, which is scored rounds and nothing else.

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order)
values ('e5071000-0000-4000-8000-000000000018', tests.the_group(), date '2032-01-18', 'open',
        '2032-01-18T10:00:00Z', '2032-01-18T20:00:00Z', '2032-01-18T22:00:00Z', null);

insert into public.submissions (id, round_id, user_id, track_key, track_meta)
select ('e5072000-0000-4000-8000-0000000018' || lpad(p.idx::text, 2, '0'))::uuid,
       'e5071000-0000-4000-8000-000000000018',
       tests.person(p.name),
       'isrc:E507R18P' || p.idx,
       '{}'::jsonb
  from (values (1, 'Ana'), (2, 'Ben'), (3, 'Cal')) as p(idx, name);

update public.rounds
   set card_order = (select jsonb_agg(s.id order by s.id)
                       from public.submissions s where s.round_id = public.rounds.id),
       state = 'revealed'
 where id = 'e5071000-0000-4000-8000-000000000018';

select is((select ear_reads::int from public.standings
            where user_id = tests.person('Ana') and group_id = tests.the_group()),
          28, 'a revealed round is not in the window — tonight never moves the board');

select * from finish();
rollback;
