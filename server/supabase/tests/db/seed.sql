-- seed.sql — tasks/E01-04, AC-8. The docs/02 §4.4 fixture, asserted row by row.
--
-- This runs against the raw tables, not the E05 scoring views, on purpose: a seed that has
-- drifted must be caught here and not blamed on the views later.
--
-- Two numbers differ from docs/02 §4.4 as printed, because §4.4 as printed is unsatisfiable
-- — "Cal guesses all 7; 7 correct" forces every card but Cal's own to hold at least one
-- correct guess, which contradicts Gus's stated readability of 0/7. The repair keeps every
-- stated guess-activity number and adjusts only the readability table, which the doc
-- introduces hypothetically: Gus 0 -> 1, Hal 5 -> 4. See seed.sql's header and tasks/E01.
begin;
set search_path = public, extensions, tests;
select plan(51);

-- ─── the cast ────────────────────────────────────────────────────────────────
select is((select count(*)::int from public.profiles), 9, 'nine profiles');
select is_empty($$
  select n from unnest(array['Ana','Ben','Cal','Dee','Eli','Fay','Gus','Hal','Ivy']) as n
  where not exists (select 1 from public.profiles p where p.display_name = n)
$$, 'the nine §4.4 names are all present');

select is((select count(*)::int from public.groups), 1, 'one group');
select is((select timezone from public.groups), 'America/New_York', 'the group is in New York');
select is((select reveal_hour from public.groups), 20, 'reveal_hour is 20');
select is((select count(*)::int from public.memberships where left_at is null), 9,
          'all nine are active members');

select is((select count(*)::int from public.rounds), 3, 'three rounds');
select bag_eq(
  $$ select local_date::text || ' ' || state::text from public.rounds $$,
  $$ values ('2026-08-08 scored'), ('2026-08-09 revealed'), ('2026-08-10 open') $$,
  'one scored round, one revealed, one open');

-- ─── the scored round: S = 8, Ivy sat out ───────────────────────────────────
select is(tests.guesses_made('2026-08-08','Ivy'), 0, 'Ivy made no guesses — she did not submit');
select is((select count(*)::int from public.submissions
           where round_id = tests.round_on('2026-08-08')), 8, 'S = 8 submitters');
select is((select count(*)::int from public.submissions
           where round_id = tests.round_on('2026-08-08')
             and user_id = tests.person('Ivy')), 0, 'Ivy has no submission in the scored round');

-- The duplicate case: Ana and Ben both dropped Ribs (docs/02 §4.3).
select is(
  (select s.track_key from public.submissions s
   where s.round_id = tests.round_on('2026-08-08') and s.user_id = tests.person('Ana')),
  (select s.track_key from public.submissions s
   where s.round_id = tests.round_on('2026-08-08') and s.user_id = tests.person('Ben')),
  'Ana and Ben share a track_key');
select is((select count(distinct track_key)::int from public.submissions
           where round_id = tests.round_on('2026-08-08')), 7,
          '8 submissions, 7 distinct tracks');

-- Card order, as printed in §4.4: 1=Dee 2=Ben 3=Hal 4=Ana 5=Gus 6=Cal 7=Eli 8=Fay
select is(
  (select string_agg(p.display_name, ' ' order by c.ord)
   from public.rounds r
   cross join lateral jsonb_array_elements_text(r.card_order) with ordinality as c(sid, ord)
   join public.submissions s on s.id = c.sid::uuid
   join public.profiles p on p.id = s.user_id
   where r.local_date = '2026-08-08'),
  'Dee Ben Hal Ana Gus Cal Eli Fay',
  'card_order is the §4.4 order');

-- ─── guesses made ────────────────────────────────────────────────────────────
select is(tests.guesses_made('2026-08-08', n), c, format('%s made %s guesses', n, c))
from (values ('Ana',7),('Ben',4),('Cal',7),('Dee',7),('Eli',0),
             ('Fay',7),('Gus',7),('Hal',7)) as t(n, c);

select is(tests.guesses_made('2026-08-08','Eli'), 0,
          'Eli opened the app and assigned nothing — the 0/0 ear case');
select is(7 - tests.guesses_made('2026-08-08','Ben'), 3, 'Ben left exactly 3 cards blank');

-- ─── ear: correct guesses made, out of S − 1 = 7 ─────────────────────────────
select is(tests.ear_correct('2026-08-08', n), c, format('%s ear %s/7', n, c))
from (values ('Ana',5),('Ben',3),('Cal',7),('Dee',2),('Eli',0),
             ('Fay',4),('Gus',1),('Hal',4)) as t(n, c);

-- ─── readability: correct guesses landing on each card ───────────────────────
select is(tests.read_correct('2026-08-08', n), c, format('%s readability %s/7', n, c))
from (values ('Ana',6),('Ben',5),('Cal',3),('Dee',4),('Eli',1),
             ('Fay',2),('Gus',1),('Hal',4)) as t(n, c);

select is(tests.read_correct('2026-08-08','Eli'), 1,
          'Eli guessed nothing and still has a readability (docs/02 §4.4)');
select is(tests.read_correct('2026-08-08','Ivy'), 0, 'Ivy has no card, so no readability');

-- The two totals are the same 26 guesses counted from opposite ends.
select is(
  (select sum(tests.ear_correct('2026-08-08', display_name))::int from public.profiles),
  (select sum(tests.read_correct('2026-08-08', display_name))::int from public.profiles),
  'ear total and readability total agree — the fixture is internally consistent');
select is(
  (select sum(tests.ear_correct('2026-08-08', display_name))::int from public.profiles),
  26, '26 correct guesses in the round');

-- The duplicate rule is load-bearing here, not incidental.
select cmp_ok(
  (select count(*)::int from public.guesses g
   join public.submissions card on card.id = g.submission_id
   where g.round_id = tests.round_on('2026-08-08')
     and card.user_id = tests.person('Ana')
     and g.guessed_user_id = tests.person('Ben')),
  '>', 0,
  'someone named Ben on Ana''s card and it counted — docs/02 §4.3');

-- ─── the other two rounds ────────────────────────────────────────────────────
select cmp_ok((select count(*)::int from public.submissions
               where round_id = tests.round_on('2026-08-09')), '>=', 3,
              'the revealed round has enough submissions not to have voided');
select cmp_ok((select count(*)::int from public.guesses
               where round_id = tests.round_on('2026-08-09')), '>', 0,
              'the revealed round has a sheet in progress');
select cmp_ok((select count(*)::int from public.submissions
               where round_id = tests.round_on('2026-08-10')), '>', 0,
              'the open round has submissions to keep hidden');
select is((select count(*)::int from public.guesses
           where round_id = tests.round_on('2026-08-10')), 0,
          'nobody has guessed in the open round — there is nothing to guess at yet');

-- ─── track_links: every seeded track is linkable (docs/06 §5) ───────────────
select is_empty($$
  select distinct s.track_key from public.submissions s
  where not exists (select 1 from public.track_links l where l.track_key = s.track_key)
$$, 'every submitted track has a track_links row');
select is_empty($$
  select track_key from public.track_links
  where spotify_url is null and unresolvable = false
$$, 'every track_links row is either resolved to Spotify or marked unresolvable');

select * from finish();
rollback;
