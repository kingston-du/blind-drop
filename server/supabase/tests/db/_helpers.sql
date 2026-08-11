-- _helpers.sql — loaded once by scripts/test-db.mjs before any test file runs.
-- Not a test itself (the leading underscore keeps it out of the glob).
--
-- Everything here lives in the `tests` schema so `public` stays exactly what the migrations
-- made it — schema.sql asserts that.

create schema if not exists tests;

-- ─── time travel ─────────────────────────────────────────────────────────────
-- public.now_() reads `app.test_now`. These two make a test read like prose, and mean the
-- suite never needs pg_sleep (tasks/E01-05).

create or replace function tests.set_test_now(t timestamptz) returns void
language sql as $$
  select set_config('app.test_now', t::text, true);   -- true = transaction-local
$$;

create or replace function tests.clear_test_now() returns void
language sql as $$
  select set_config('app.test_now', '', true);
$$;

-- ─── fixture handles ─────────────────────────────────────────────────────────
-- The seed uses stable uuids so a test can name a person instead of pasting a uuid.



create or replace function tests.the_group() returns uuid
language sql stable as $$
  select id from public.groups where invite_code = 'K7MQ2X'
$$;

-- Scoped to the fixture group, not to the whole table: `npm run test:functions` creates its
-- own profiles in the same local database and some of them are called Ana too.
create or replace function tests.person(p_name text) returns uuid
language sql stable as $$
  select p.id from public.profiles p
  join public.memberships m on m.user_id = p.id and m.group_id = tests.the_group()
  where p.display_name = p_name
$$;

create or replace function tests.round_on(p_date date) returns uuid
language sql stable as $$
  select id from public.rounds where local_date = p_date and group_id = tests.the_group()
$$;

-- The submission `p_name` made in the round on `p_date`.
create or replace function tests.card_of(p_date date, p_name text) returns uuid
language sql stable as $$
  select s.id from public.submissions s
  where s.round_id = tests.round_on(p_date) and s.user_id = tests.person(p_name)
$$;

-- ─── scoring, computed straight from the rows ────────────────────────────────
-- Deliberately independent of the E05 views: E01-04 has to catch seed drift before those
-- views exist, and once they do exist the two must agree.

-- Correct guesses made by p_name in the round (their "ear" numerator).
create or replace function tests.ear_correct(p_date date, p_name text) returns int
language sql stable as $$
  select count(*)::int
  from public.guesses g
  join public.submissions card on card.id = g.submission_id
  where g.round_id = tests.round_on(p_date)
    and g.guesser_id = tests.person(p_name)
    and exists (
      select 1 from public.submissions s2
      where s2.round_id = g.round_id
        and s2.user_id  = g.guessed_user_id
        and s2.track_key = card.track_key)
$$;

-- Correct guesses landing on p_name's card (their "readability" numerator).
create or replace function tests.read_correct(p_date date, p_name text) returns int
language sql stable as $$
  select count(*)::int
  from public.guesses g
  join public.submissions card on card.id = g.submission_id
  where g.round_id = tests.round_on(p_date)
    and card.user_id = tests.person(p_name)
    and exists (
      select 1 from public.submissions s2
      where s2.round_id = g.round_id
        and s2.user_id  = g.guessed_user_id
        and s2.track_key = card.track_key)
$$;

create or replace function tests.guesses_made(p_date date, p_name text) returns int
language sql stable as $$
  select count(*)::int from public.guesses
  where round_id = tests.round_on(p_date) and guesser_id = tests.person(p_name)
$$;
