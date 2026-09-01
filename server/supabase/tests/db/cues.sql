-- cues.sql — tasks/E35-02. docs/18-CUES.md §3, §5, §6, §11.4.
--
-- The four properties this feature stands on, asserted in SQL:
--
--   1. The catalog is bounded and exactly the list `docs/11-COPY-DECK.md` records — the
--      56-char cap is the SE-at-accessibility5 discipline. The active count no longer needs to
--      be prime (20260831190000): `cue_for_round()` reads it live and searches for a stride
--      coprime with it, which is what §3's no-repeat-before-exhaustion actually depends on.
--   2. Over every active cue at `cue_cadence = 1`, each one appears exactly once before any
--      repeat.
--   3. `ensure_rounds()` assigns a cue on insert and never rewrites one afterwards.
--   4. `ensure_rounds()` assigns the true chronological ordinal across repeated day-to-day
--      rollovers, not just a single instant — 20260827130000 fixed a permanent off-by-one here.
--   5. A cadence change rewrites only not-yet-opened rounds, and a demo group ships with the
--      cue off, reproducibly, whatever the clock says.

begin;
set search_path = public, extensions, tests;
select plan(26);

-- ─── 1 · the catalog ─────────────────────────────────────────────────────────

select is((select pg_catalog.count(*)::int from public.cue_catalog where active), 40,
  '40 active cues, as docs/18-CUES.md §6 records');

select ok((select pg_catalog.bool_and(char_length(text) <= 56) from public.cue_catalog),
  'every cue text is 56 characters or fewer');

select ok((select pg_catalog.bool_and(char_length(btrim(text)) > 0) from public.cue_catalog),
  'every cue text is non-empty');

select bag_eq(
  $$ select key, text from public.cue_catalog where active order by key $$,
  $$ values
    ('aux_song','Your go-to aux song'),
    ('before_you_were_born','A song from before you were born'),
    ('deny_liking','A song you''d lie about liking'),
    ('driving_at_night','A song for driving at night'),
    ('embarrassed_to_love','A song you''re embarrassed to love'),
    ('falling_asleep','A song for falling asleep'),
    ('family_always_played','A song that was always on in your house'),
    ('first_phone_song','A song from your first phone'),
    ('first_you_remember_loving','A song you loved as a kid'),
    ('from_a_movie','A song you only know because of a movie'),
    ('genre_you_never_listen','A song from a genre you never listen to'),
    ('get_ready_to','The song you get ready to'),
    ('getting_hyped','A song that excites you'),
    ('guilty_pleasure_alone','A song you only play with headphones on'),
    ('hate_and_know_words','A song you hate and know every word of'),
    ('know_all_the_lyrics','A song you know all the lyrics to'),
    ('language_you_dont_speak','A song in a language you don''t speak'),
    ('loved_as_a_kid','A song you were obsessed with at 13'),
    ('loved_by_all_not_you','A song everyone loves that you don''t'),
    ('middle_school','A song from middle school'),
    ('most_played_this_year','Your favorite song this year'),
    ('never_play_in_their_car','A song you''d never play in someone else''s car'),
    ('never_tired_of','A song you never get tired of'),
    ('nobody_guesses_yours','A song nobody here would guess is yours'),
    ('nobody_has_heard','Your song you fall asleep to'),
    ('older_sibling_put_you_on','A song your friend put you onto'),
    ('oldest_you_still_play','The oldest song you still play'),
    ('on_repeat','A song you''ve had on repeat this week'),
    ('one_specific_summer','A song stuck to one specific summer'),
    ('parents_would_play','A song your parents would put on'),
    ('play_at_a_party','The song you''d put on to save a party'),
    ('should_be_more_famous','A song that should be more famous'),
    ('skipped_the_most','The song you skip the most'),
    ('slow_morning','A song for a slow morning'),
    ('someone_got_you_into','A song you got someone else into'),
    ('song_you_hate','A song you hate'),
    ('tied_to_someone','A song tied to a specific person'),
    ('tired_of_hearing','A song that got ruined for you'),
    ('unexpected_from_you','A song that would give the wrong impression of you'),
    ('worst_by_favorite_artist','The worst song by an artist you love')
  $$,
  'the catalog matches docs/11-COPY-DECK.md''s cue.catalog verbatim'
);

-- ─── 2 · no repeat before exhaustion at cadence 1 ────────────────────────────

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by, cue_cadence)
values ('e1000000-0000-4000-8000-0000000000f1','Cue cycle','America/New_York',20,'CUE66A',
        tests.person('Ana'), 1);

create temporary view cycle as
  select gs as n, cue.prompt_key, cue.prompt
    from pg_catalog.generate_series(0, 39) as gs
    cross join lateral public.cue_for_round(
      'e1000000-0000-4000-8000-0000000000f1', gs, 1::smallint) as cue;

select is((select pg_catalog.count(*)::int from cycle), 40,
  'every one of 40 rounds at cadence 1 carries a cue');

select is((select pg_catalog.count(distinct prompt_key)::int from cycle), 40,
  'no cue key repeats across 40 consecutive cued rounds');

select is((select pg_catalog.count(*)::int from cycle where prompt_key is null), 0,
  'and none of them is null');

select ok(
  not exists (
    select key from public.cue_catalog where active
    except
    select prompt_key from cycle
  ),
  'the 40 cued rounds exhaust the whole catalog before any repeat'
);

-- ─── 3 · ensure_rounds assigns once, never rewrites ──────────────────────────

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by, cue_cadence)
values ('e1000000-0000-4000-8000-0000000000f2','Cue idempotence','America/New_York',20,'CUEC62',
        tests.person('Ana'), 2);

select tests.set_test_now('2026-09-01T14:00:00Z');   -- 10:00 in New York
select lives_ok('select public.ensure_rounds()', 'ensure_rounds() runs for a cued group');

select is((select pg_catalog.count(*)::int from public.rounds
            where group_id = 'e1000000-0000-4000-8000-0000000000f2'), 2,
  'today and tomorrow materialise, and nothing further out');

select is((select pg_catalog.count(*)::int from public.rounds
            where group_id = 'e1000000-0000-4000-8000-0000000000f2'
              and prompt_key is not null), 1,
  'cadence 2 cues exactly one of two consecutive nights');

create temporary table snap as
  select id, local_date, prompt_key, prompt
    from public.rounds where group_id = 'e1000000-0000-4000-8000-0000000000f2';

select lives_ok('select public.ensure_rounds()', 'a second call at the same instant');

select bag_eq(
  $$ select id, local_date, prompt_key, prompt from public.rounds
      where group_id = 'e1000000-0000-4000-8000-0000000000f2' order by local_date $$,
  $$ select id, local_date, prompt_key, prompt from snap order by local_date $$,
  'running ensure_rounds() twice never changes a round''s cue');

update public.rounds
   set state = 'voided', prompt_key = null, prompt = null
 where group_id = 'e1000000-0000-4000-8000-0000000000f2'
   and local_date = date '2026-09-01';

select lives_ok('select public.ensure_rounds()', 'ensure_rounds() after one round voids');

select is((select prompt_key from public.rounds
            where group_id = 'e1000000-0000-4000-8000-0000000000f2'
              and local_date = date '2026-09-01'), null,
  'a round that is no longer open keeps its cue — ensure_rounds() never rewrites one');

-- ─── 4 · the ordinal survives repeated day-to-day rollovers ──────────────────
-- 20260827130000: a tick that runs before "today"'s own reveal sees both today (already
-- materialised) and tomorrow as candidates. The original formula double-counted today —
-- once in its batch `count(*)`, once in the shared `row_number()` — so the very first round
-- inserted after a rollover got `n + 1` instead of `n`, permanently. Three rollovers, each
-- ticked well before that day's own reveal, is what it takes to exercise the bug: a single
-- `ensure_rounds()` call (as in §3 above) never sees "today" as both existing and a candidate
-- for the *next* insertion in the same call.

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by, cue_cadence)
values ('e1000000-0000-4000-8000-0000000000f4','Cue rollover','America/New_York',20,'CUER64',
        tests.person('Ana'), 1);

select tests.set_test_now('2026-09-01T13:00:00Z');   -- 09:00 in New York, well before reveal
select lives_ok('select public.ensure_rounds()', 'rollover day 1: today and tomorrow materialise');

select tests.set_test_now('2026-09-02T13:00:00Z');   -- 09:00 the next day, before its own reveal
select lives_ok('select public.ensure_rounds()',
  'rollover day 2: a new day rolls over while today already exists');

select tests.set_test_now('2026-09-03T13:00:00Z');   -- 09:00 the day after that, same shape
select lives_ok('select public.ensure_rounds()', 'rollover day 3: one more rollover');

select is(
  (select pg_catalog.array_agg(prompt_key order by local_date)
     from public.rounds where group_id = 'e1000000-0000-4000-8000-0000000000f4'),
  (select pg_catalog.array_agg(cue.prompt_key order by gs)
     from pg_catalog.generate_series(0, 3) as gs
     cross join lateral public.cue_for_round(
       'e1000000-0000-4000-8000-0000000000f4', gs, 1::smallint) as cue),
  'four rounds across three rollovers get ordinals 0..3, in order — no skipped n'
);

-- ─── 5 · a cadence change rewrites only not-yet-opened rounds ────────────────

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by, cue_cadence)
values ('e1000000-0000-4000-8000-0000000000f3','Cue rewrite','America/New_York',20,'CUER63',
        tests.person('Ana'), 2);

select tests.set_test_now('2026-09-01T18:00:00Z');   -- 14:00: today has opened, not revealed
select lives_ok('select public.ensure_rounds()', 'the rewrite group materialises its two rounds');

create temporary table today_cue as
  select id, prompt_key, prompt
    from public.rounds where group_id = 'e1000000-0000-4000-8000-0000000000f3'
      and local_date = date '2026-09-01';

select is(public.rewrite_open_round_cues('e1000000-0000-4000-8000-0000000000f3', 3::smallint),
  date '2026-09-02',
  'a cadence change returns the first not-yet-opened round''s date');

select bag_eq(
  $$ select id, prompt_key, prompt from public.rounds
      where group_id = 'e1000000-0000-4000-8000-0000000000f3'
        and local_date = date '2026-09-01' $$,
  $$ select id, prompt_key, prompt from today_cue $$,
  'the already-opened round''s cue is untouched by a cadence change');

select is(
  (select prompt_key from public.rounds
    where group_id = 'e1000000-0000-4000-8000-0000000000f3'
      and local_date = date '2026-09-02'),
  (select prompt_key from public.cue_for_round('e1000000-0000-4000-8000-0000000000f3', 1, 3::smallint)),
  'the not-yet-opened round is rewritten under the new cadence');

-- ─── 6 · demo groups ship with the cue off, reproducibly ─────────────────────

update public.pilot_cohorts set enabled = true where name = 'App Review';
insert into auth.users (id) values ('d0000000-0000-4000-8000-000000000002');
insert into public.profiles (id, display_name)
  values ('d0000000-0000-4000-8000-000000000002', 'Reviewer Two');

select isnt(public.assign_pilot_cohort('d0000000-0000-4000-8000-000000000002'), null::uuid,
  'the App Review cohort admits a reviewer');

select is((select cue_cadence from public.groups where is_demo), 0::smallint,
  'a demo group is created with the cue off');

select is(
  (select prompt_key from public.cue_for_round(
    (select id from public.groups where is_demo), 0, 0::smallint)),
  null,
  'and the derivation returns no cue at cadence 0, whatever the clock'
);

select * from finish();
rollback;
