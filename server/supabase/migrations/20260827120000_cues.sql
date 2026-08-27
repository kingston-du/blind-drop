-- 20260827120000_cues.sql — cues. docs/18-CUES.md, tasks/E35-02.
--
-- A cue is one short line, identical for every member, attached to some nights' rounds. It
-- ships on by default for every circle (`groups.cue_cadence = 2`, "every other night"). The
-- catalog below is a closed, seeded set — never admin-authored (§11.6) — and which entry a
-- round draws is a pure function of the round's position in its circle's timeline (§3), so
-- nothing needs to be remembered across rounds to keep the sequence coherent.
--
-- Three pieces land here:
--   1. `cue_catalog` (61 rows, prime by construction — §6), `groups.cue_cadence`, and
--      `rounds.prompt_key`. `rounds.prompt` (0002's long-nullable column) now holds the
--      *frozen* cue text at assignment time; `prompt_key` is for joins and future
--      localisation, never for re-reading a live catalog line.
--   2. `cue_for_round()` — the §3 formula as a single deterministic function of
--      (group_id, ordinal, cadence). Used by `ensure_rounds()` on insert and by
--      `rewrite_open_round_cues()` on a cadence change.
--   3. `ensure_rounds()` gains the assignment step, and a cadence change rewrites only
--      rounds that have not yet opened (`state = 'open' AND opens_at > now_()`), never one
--      somebody may already have sealed against (§10).
--
-- Demo groups (§11.4) get `cue_cadence = 0` — no cue at all — rather than the
-- `hashtext(group_id)`-derived one. A demo group's id is minted fresh on provisioning, so a
-- hash-derived cue would differ across App Review runs; the whole point of the demo is the
-- loop, not the cue, and "no cue" is the most reproducible derivation there is. See the
-- decision note in tasks/E35-cues.md.

-- ─── the catalog ──────────────────────────────────────────────────────────────
-- N (count(*) where active) must stay prime — §3's no-repeat-before-exhaustion property is
-- modular arithmetic over a prime-sized catalog, and tests/db/cues.sql asserts it on every
-- migration. Text is capped at 56 chars so nothing overflows on an SE at accessibility5.

create table public.cue_catalog (
  key    text primary key,
  text   text not null check (char_length(text) <= 56),
  active boolean not null default true
);

alter table public.cue_catalog enable row level security;
alter table public.cue_catalog force row level security;

comment on table public.cue_catalog is
  'The fixed, seeded set of cues (docs/18-CUES.md §6). Never admin-authored and never read by '
  'the API directly — a round''s frozen `prompt`/`prompt_key` are what reach the wire. The '
  'active count must stay prime (§3).';

revoke all on table public.cue_catalog from public, anon, authenticated, service_role;

insert into public.cue_catalog (key, text) values
  ('embarrassed_to_love',      'A song you''re embarrassed to love'),
  ('never_play_in_their_car',  'A song you''d never play in someone else''s car'),
  ('hate_and_know_words',      'A song you hate and know every word of'),
  ('deny_liking',              'A song you''d deny liking if asked directly'),
  ('guilty_pleasure_alone',    'A guilty pleasure you play alone'),
  ('song_you_hate',            'A song you hate'),
  ('loved_by_all_not_you',     'A song everyone loves that you don''t'),
  ('worst_by_favorite_artist', 'The worst song by an artist you love'),
  ('aged_badly',               'A song that has aged badly'),
  ('tired_of_hearing',         'A song you''re tired of hearing'),
  ('nobody_guesses_yours',     'A song nobody here would guess is yours'),
  ('genre_you_never_listen',   'A song from a genre you never listen to'),
  ('parents_would_play',       'A song your parents would put on'),
  ('doesnt_match_taste',       'A song that doesn''t match your taste at all'),
  ('unexpected_from_you',      'A song people wouldn''t expect from you'),
  ('outside_comfort_zone',     'A song outside your comfort zone'),
  ('aux_song',                 'Your go-to aux song'),
  ('get_ready_to',             'The song you get ready to'),
  ('driving_at_night',         'A song for driving at night'),
  ('walk_home_alone',          'A song for the walk home alone'),
  ('end_the_night_on',         'A song to end the night on'),
  ('cleaning_the_house',       'A song for cleaning the house'),
  ('long_car_ride',            'A song for a long car ride'),
  ('play_at_a_party',          'A song to play at a party'),
  ('rainy_day',                'A song for a rainy day'),
  ('doing_chores',             'A song for doing chores'),
  ('one_specific_summer',      'A song stuck to one specific summer'),
  ('someone_got_you_into',     'A song someone else got you into'),
  ('reminds_you_of_school',    'A song that reminds you of school'),
  ('road_trip',                'A song from a road trip'),
  ('tied_to_someone',          'A song tied to a specific person'),
  ('middle_school',            'A song from middle school'),
  ('family_always_played',     'A song your family always played'),
  ('most_played_this_year',    'Your most played song this year'),
  ('skipped_the_most',         'The song you''ve skipped the most'),
  ('oldest_you_still_play',    'The oldest song you still play'),
  ('before_you_were_born',     'A song from before you were born'),
  ('found_this_month',         'A song you found this month'),
  ('first_you_remember_loving','The first song you remember loving'),
  ('never_tired_of',           'A song you never get tired of'),
  ('on_repeat',                'A song you could listen to on repeat'),
  ('language_you_dont_speak',  'A song in a language you don''t speak'),
  ('should_be_more_famous',    'A song that should be more famous'),
  ('one_word_title',           'A song with a one-word title'),
  ('shorter_than_three',       'A song shorter than three minutes'),
  ('longer_than_six',          'A song longer than six minutes'),
  ('one_hit_wonder',           'A one-hit wonder you still love'),
  ('from_a_movie',             'A song from a movie'),
  ('from_a_video_game',        'A song from a video game'),
  ('know_all_the_lyrics',      'A song you know all the lyrics to'),
  ('nobody_has_heard',         'A song nobody has heard of'),
  ('decade_you_were_born',     'A song from the decade you were born'),
  ('different_decade',         'A song that feels like a different decade'),
  ('loved_as_a_kid',           'A song you loved as a kid'),
  ('older_sibling_put_you_on', 'A song your older sibling or friend put you onto'),
  ('slow_morning',             'A song for a slow morning'),
  ('getting_hyped',            'A song for getting hyped up'),
  ('favorite_hype_song',       'Your favorite hype song'),
  ('workout',                  'A song for a workout'),
  ('falling_asleep',           'A song for falling asleep'),
  ('good_mood',                'A song for a good mood');

-- ─── the two new columns ─────────────────────────────────────────────────────

alter table public.groups
  add column cue_cadence smallint not null default 2
    check (cue_cadence between 0 and 3);

comment on column public.groups.cue_cadence is
  'How often this circle''s rounds carry a cue: 0 off, 1 every night, 2 every other night '
  '(the default), 3 now and then. Admin-set, circle-scoped, the same reasoning as '
  'reveal_hour (docs/18-CUES.md §4).';

alter table public.rounds
  add column prompt_key text references public.cue_catalog(key);

comment on column public.rounds.prompt_key is
  'The catalog key of the cue frozen onto this round at assignment time. For joins and future '
  'localisation; `prompt` is the text that actually shipped that night. Null when the round '
  'has no cue — every round created before this migration, and every round whose circle''s '
  'cadence is 0 (docs/18-CUES.md §5).';

-- ─── cue_for_round ───────────────────────────────────────────────────────────
-- The §3 formula, pure in (group_id, ordinal, cadence). Returns exactly one row, with both
-- columns null when the round is not cued, so callers can `cross join lateral` it and still
-- insert/rewrite an uncued round.

create or replace function public.cue_for_round(
  p_group_id uuid,
  p_n        int,
  p_cadence  smallint
) returns table (prompt_key text, prompt text)
language sql
stable
set search_path = ''
as $$
  -- offset/stride/seed derive once from the group id's hash, so two circles on the same
  -- cadence draw different cues and a circle does not always start its cycle on cue #0.
  -- `stride` is forced odd (and therefore coprime with the prime catalog size 61), which is
  -- what makes i -> catalog[(i*stride + seed) mod 61] visit all 61 cues before any repeat.
  with u as (
    select (pg_catalog.hashtext(p_group_id::text)::bigint & 4294967295::bigint) as h
  ),
  d as (
    select
      h % 61                          as seed,
      1 + 2 * (((h / 64) % 30)::int)  as stride,
      ((h / 4096) % 61)::int          as off
    from u
  ),
  pick as (
    select case
             when p_cadence > 0 and (p_n + off) % p_cadence = 0
             then ((p_n + off) / p_cadence * stride + seed) % 61
             else null
           end as idx
    from d
  )
  select c.key, c.text
    from pick p
    left join lateral (
      select c2.key, c2.text
        from public.cue_catalog c2
       where c2.active
       order by c2.key
       offset coalesce(p.idx, 0)
       limit 1
    ) c on p.idx is not null;
$$;

comment on function public.cue_for_round(uuid, int, smallint) is
  'The cue for a circle''s n-th round under a cadence, or null when the round is not cued '
  '(docs/18-CUES.md §3). Deterministic: offset/stride/seed derive from the group id, and the '
  'stride is coprime with the prime catalog size so no cue repeats before all 61 have been '
  'drawn.';

revoke all on function public.cue_for_round(uuid, int, smallint)
  from public, anon, authenticated;

-- ─── ensure_rounds: assign the cue on insert ────────────────────────────────
-- Forward-only replacement of the 20260815090000 definition. Identical but for the
-- `cue_cadence` column in the driving query and the two cue columns on the insert. A group
-- with `cue_cadence = 0` inserts null for both, exactly as every round does today.

create or replace function public.ensure_rounds()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now   timestamptz := public.now_();
  v_group record;
  v_today date;
  v_n     int;
begin
  for v_group in
    select g.id, g.timezone, g.reveal_hour, g.cue_cadence
      from public.groups g
     where not g.is_demo
     order by g.id
  loop
    begin
      v_today := pg_catalog.timezone(v_group.timezone, v_now)::date;

      -- The next round's ordinal among the circle's rounds, by local_date, starting at 0.
      -- The candidates below add their own 0-based position among the survivors on top, so
      -- tomorrow's round is n+1 when today's also materialises and n when today's is skipped
      -- for being already past its own reveal.
      select pg_catalog.count(*)::int into v_n
        from public.rounds r
       where r.group_id = v_group.id;

      insert into public.rounds
             (group_id, local_date, state, opens_at, reveals_at, scores_at, prompt_key, prompt)
      select c.group_id,
             c.local_date,
             'open',
             c.opens_at,
             c.reveals_at,
             c.scores_at,
             cue.prompt_key,
             cue.prompt
        from (
          select v_group.id as group_id,
                 d.local_date,
                 d.reveals_at - interval '10 hours' as opens_at,
                 d.reveals_at,
                 d.reveals_at + interval '2 hours' as scores_at,
                 v_n + (pg_catalog.row_number() over (order by d.local_date))::int - 1 as n
            from (
              select t.ld as local_date,
                     pg_catalog.timezone(
                       v_group.timezone,
                       t.ld + pg_catalog.make_interval(hours => v_group.reveal_hour)) as reveals_at
                from pg_catalog.unnest(array[v_today, v_today + 1]) as t(ld)
            ) d
           where d.reveals_at > v_now
        ) c
        cross join lateral public.cue_for_round(v_group.id, c.n, v_group.cue_cadence) as cue
      on conflict (group_id, local_date) do nothing;

    exception when others then
      raise warning 'ensure_rounds: group % skipped (%): %',
                    v_group.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.ensure_rounds() is
  'Idempotently materialises today''s and tomorrow''s round for every non-demo group '
  '(docs/03 §4), assigning each round its cue per docs/18-CUES.md §3 when the circle''s '
  'cadence is on. Two days only, so the DST offset used is never stale; on conflict do '
  'nothing, so an existing round is never re-timed and a reveal_hour change lands on the '
  'first uncreated round. Demo groups are materialised by demo_tick() instead.';

revoke all on function public.ensure_rounds() from public, anon, authenticated;
grant execute on function public.ensure_rounds() to service_role;

-- ─── rewrite_open_round_cues ────────────────────────────────────────────────
-- A cadence change rewrites the cue on every round that has not yet opened — the round
-- somebody may already be about to seal against is never touched (§10). The Edge Function
-- (E35-03) calls this after updating `groups.cue_cadence`, then returns `cue_effective_from`
-- as the earliest date this touched.

create or replace function public.rewrite_open_round_cues(p_group_id uuid, p_cadence smallint)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_effective date;
begin
  select pg_catalog.min(r.local_date) into v_effective
    from public.rounds r
   where r.group_id = p_group_id
     and r.state = 'open'
     and r.opens_at > public.now_();

  update public.rounds r
     set prompt_key = cue.prompt_key,
         prompt     = cue.prompt
    from (
      select r2.id,
             (select pg_catalog.count(*)::int
                from public.rounds r3
               where r3.group_id = r2.group_id
                 and r3.local_date < r2.local_date) as n
        from public.rounds r2
       where r2.group_id = p_group_id
         and r2.state = 'open'
         and r2.opens_at > public.now_()
    ) ord,
    lateral public.cue_for_round(p_group_id, ord.n, p_cadence) as cue
   where r.id = ord.id;

  return v_effective;
end $$;

comment on function public.rewrite_open_round_cues(uuid, smallint) is
  'Rewrites the cue on every open round that has not yet opened, and returns the earliest '
  'date it touched (null when none). Called by the cadence PATCH path (docs/18-CUES.md §10): '
  'a change never reaches a round somebody may already have sealed against.';

revoke all on function public.rewrite_open_round_cues(uuid, smallint)
  from public, anon, authenticated;
grant execute on function public.rewrite_open_round_cues(uuid, smallint) to service_role;

-- ─── demo groups: no cue ────────────────────────────────────────────────────
-- §11.4. The App Review group's id is minted fresh each provisioning, so a hash-derived cue
-- would change across review runs. Off is the most reproducible derivation there is — and a
-- demo round is the loop, not the cue.

update public.groups set cue_cadence = 0 where is_demo;

-- And on create: `assign_pilot_cohort()` is what mints a demo group when the reviewer signs
-- in, so it carries the same "off for demo" rule forward for any group created after this
-- migration. Forward-only replacement of the 20260815090000 definition — identical but for
-- the `cue_cadence` column on the insert.

create or replace function public.assign_pilot_cohort(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cohort public.pilot_cohorts;
  v_group_id uuid;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  perform pg_advisory_xact_lock(hashtextextended('blind-drop-pilot-cohort-assignment', 0));

  select m.group_id into v_group_id
  from public.memberships m
  where m.user_id = p_user and m.left_at is null;
  if v_group_id is not null then
    return v_group_id;
  end if;

  select c.* into v_cohort
  from public.pilot_cohorts c
  where c.enabled
    and (
      c.group_id is null
      or (select count(*) from public.memberships m
          where m.group_id = c.group_id and m.left_at is null) < c.capacity
    )
  order by c.position
  limit 1
  for update;

  if not found then
    return null;
  end if;

  if v_cohort.group_id is null then
    loop
      select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1), '')
      into v_code
      from generate_series(1, 6);
      begin
        insert into public.groups (name, timezone, reveal_hour, invite_code, created_by, is_demo, cue_cadence)
        values (btrim(v_cohort.name), v_cohort.timezone, v_cohort.reveal_hour, v_code, p_user,
                v_cohort.is_demo,
                case when v_cohort.is_demo then 0 else 2 end)
        returning id into v_group_id;
        exit;
      exception when unique_violation then
        -- Only an invite-code collision is possible while the advisory lock is held.
      end;
    end loop;

    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'admin');

    update public.pilot_cohorts
    set group_id = v_group_id, updated_at = now()
    where id = v_cohort.id;
  else
    v_group_id := v_cohort.group_id;
    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'member');
  end if;

  return v_group_id;
end $$;

revoke all on function public.assign_pilot_cohort(uuid) from public, anon, authenticated;
grant execute on function public.assign_pilot_cohort(uuid) to service_role;
