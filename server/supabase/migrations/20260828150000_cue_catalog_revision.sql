-- 20260828150000_cue_catalog_revision.sql — cue catalog revision. docs/18-CUES.md §6,
-- tasks/E35-cues.md's dated note under E35-02.
--
-- Owner cut the catalog from 61 to 41: sharper for the actual audience (~18, easy to answer,
-- not straining for hip) and trimmed a few entries that only restated a neighbour. `61` and
-- `41` are both prime, so §3's no-repeat-before-exhaustion property (modular arithmetic over
-- a prime-sized catalog) holds before and after.
--
-- `20260827120000_cues.sql` is already merged and is never edited (CLAUDE.md §4). This
-- migration is the forward-only follow-up:
--   1. `active = false` on 21 retired rows — never deleted, since `rounds.prompt_key` may
--      already reference one, and a round's `prompt` is the frozen text anyway (§3's whole
--      point: the catalog can change under a round without touching what already shipped).
--   2. `text` updated in place on 15 rows whose key still fits the (sharper) new wording.
--   3. One new row, `first_phone_song`, replacing `reminds_you_of_school` (too vague once you
--      just left it) rather than editing that row's meaning under its old key.
--   4. `cue_for_round()` recreated with the modulus and stride bound moved from 61 to 41 —
--      the active count changed, so the formula's constants must too, or the coprimality
--      argument in the original migration's comment no longer holds.
--
-- No key is ever renamed or deleted here, only deactivated or re-texted, so no existing
-- `rounds.prompt_key` reference breaks.

-- ─── retire 21 rows ───────────────────────────────────────────────────────────

update public.cue_catalog set active = false
 where key in (
   'aged_badly', 'doesnt_match_taste', 'outside_comfort_zone', 'walk_home_alone',
   'end_the_night_on', 'cleaning_the_house', 'long_car_ride', 'rainy_day', 'doing_chores',
   'road_trip', 'found_this_month', 'one_word_title', 'shorter_than_three', 'longer_than_six',
   'one_hit_wonder', 'from_a_video_game', 'decade_you_were_born', 'different_decade',
   'favorite_hype_song', 'good_mood', 'reminds_you_of_school'
 );

-- ─── re-text 15 rows in place ────────────────────────────────────────────────

update public.cue_catalog set text = 'A song you''d lie about liking'
 where key = 'deny_liking';
update public.cue_catalog set text = 'A song you only play with headphones on'
 where key = 'guilty_pleasure_alone';
update public.cue_catalog set text = 'A song that got ruined for you'
 where key = 'tired_of_hearing';
update public.cue_catalog set text = 'A song that would give the wrong impression of you'
 where key = 'unexpected_from_you';
update public.cue_catalog set text = 'The song you''d put on to save a party'
 where key = 'play_at_a_party';
update public.cue_catalog set text = 'A song you got someone else into'
 where key = 'someone_got_you_into';
update public.cue_catalog set text = 'A song that was always on in your house'
 where key = 'family_always_played';
update public.cue_catalog set text = 'Your favorite song this year'
 where key = 'most_played_this_year';
update public.cue_catalog set text = 'The song you skip the most'
 where key = 'skipped_the_most';
update public.cue_catalog set text = 'A song you loved as a kid'
 where key = 'first_you_remember_loving';
update public.cue_catalog set text = 'A song you''ve had on repeat this week'
 where key = 'on_repeat';
update public.cue_catalog set text = 'A song you only know because of a movie'
 where key = 'from_a_movie';
update public.cue_catalog set text = 'A song you were obsessed with at 13'
 where key = 'loved_as_a_kid';
update public.cue_catalog set text = 'A song your friend put you onto'
 where key = 'older_sibling_put_you_on';
update public.cue_catalog set text = 'A song that makes you walk faster'
 where key = 'workout';

-- ─── one new row, replacing reminds_you_of_school ────────────────────────────

insert into public.cue_catalog (key, text) values
  ('first_phone_song', 'A song from your first phone');

-- ─── cue_for_round: modulus and stride bound move from 61 to 41 ─────────────
-- Forward-only replacement of the 20260827120000 definition. Identical shape; every literal
-- `61` becomes `41` (the new active count), and the stride's bounding divisor moves from
-- `30` (= (61-1)/2) to `20` (= (41-1)/2) so `stride` stays in `[1, 39]` — always less than the
-- prime modulus 41 and therefore always coprime with it, the same reasoning the original
-- migration's comment gives for `[1, 59]` under 61.

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
  -- `stride` is forced odd and bounded below 41 (and therefore coprime with the prime catalog
  -- size 41), which is what makes i -> catalog[(i*stride + seed) mod 41] visit all 41 cues
  -- before any repeat.
  with u as (
    select (pg_catalog.hashtext(p_group_id::text)::bigint & 4294967295::bigint) as h
  ),
  d as (
    select
      h % 41                          as seed,
      1 + 2 * (((h / 64) % 20)::int)  as stride,
      ((h / 4096) % 41)::int          as off
    from u
  ),
  pick as (
    select case
             when p_cadence > 0 and (p_n + off) % p_cadence = 0
             then ((p_n + off) / p_cadence * stride + seed) % 41
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
  'stride is bounded below the prime catalog size 41, so no cue repeats before all 41 have '
  'been drawn. Revised 2026-08-28 from a 61-cue catalog; see this migration''s header comment.';

revoke all on function public.cue_for_round(uuid, int, smallint)
  from public, anon, authenticated;
