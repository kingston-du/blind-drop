-- seed-marketing-demo.sql — the marketing circle. Owner-run, idempotent, hosted.
--
-- A four-person fixture circle for shooting video, deliberately built *outside* every demo
-- mechanism App Review depends on. It shares no user, no group and no function with the App
-- Review fixture, and it writes nothing to `pilot_cohorts` or `demo_companions`.
--
-- Three things this file is careful about, each a trap found while planning it:
--
--   1. **The account never goes through cohort assignment.** `assign_pilot_cohort()` picks the
--      lowest-position enabled cohort with room; App Review (position 1, capacity 1) is full,
--      so the next one is the real 12-seat pilot cohort — a marketing account signing in cold
--      would land in the circle with the actual testers. Creating the group and the membership
--      here, before the account's first `PUT /me`, makes that function return early on the
--      membership it finds and never select a cohort at all.
--
--   2. **It does not call `demo_provision()`.** `demo_companions.user_id` is the primary key
--      and that function upserts `group_id` onto it, so provisioning a second demo group would
--      *move* App Review's five companions into this one, leaving that group's live round short
--      of members for ever (`demo_tick()` will not reveal a short room). This file uses its own
--      UUIDs on their own fixture email domain and never touches that table.
--
--   3. **The round is written straight at `revealed`, not played forward.** The archive nights
--      in `seed-app-review-demo.sql` already do this. It means the flight is on screen at any
--      hour, re-shootable, and independent of `demo_tick()`'s timers.
--
-- `groups.is_demo` is still set, but only as a hands-off flag: it keeps `ensure_rounds()` and
-- all three `tick_rounds()` loops away from this group, so nothing sweeps the round mid-shoot.
--
-- Run *after* creating the auth user for m@blinddrop.app (the CLI cannot create a user with a
-- password; that is one call to /auth/v1/admin/users). Then:
--
--   npx supabase db query --linked --file server/scripts/seed-marketing-demo.sql
--
-- Re-running is safe, and re-running is also how you reset between takes: the roster is
-- upserted and the round is deleted and rebuilt, which restores `revealed`, re-anchors the
-- clock, and clears your own guesses while restoring the room's nine. There is deliberately no
-- separate reset script — `rounds_state_forward_only()` forbids `scored -> revealed`, and that
-- guard is right, so a take is reset by rebuilding the round rather than rewinding it.

set local role postgres;

do $$
declare
  v_group   constant uuid := 'fa000000-0000-4000-8000-00000000e001';
  v_round   constant uuid := 'fa000000-0000-4000-8000-00000000e002';
  v_seo     constant uuid := 'fa000000-0000-4000-8000-0000000000a1';
  v_joc     constant uuid := 'fa000000-0000-4000-8000-0000000000a2';
  v_rao     constant uuid := 'fa000000-0000-4000-8000-0000000000a3';
  -- Submission ids are fixed so `card_order` is written by hand rather than discovered, and so
  -- the score and reset scripts can address a card without a lookup.
  v_c1      constant uuid := 'fa000000-0000-4000-8000-00000000d001';  -- No. 1  Jocelyn
  v_c2      constant uuid := 'fa000000-0000-4000-8000-00000000d002';  -- No. 2  Seo   ← the answer
  v_c3      constant uuid := 'fa000000-0000-4000-8000-00000000d003';  -- No. 3  Raoul
  v_c4      constant uuid := 'fa000000-0000-4000-8000-00000000d004';  -- No. 4  Kingston (Yours)
  v_king    uuid;
  v_reveals timestamptz;
begin
  select u.id into v_king from auth.users u where u.email = 'm@blinddrop.app';
  if v_king is null then
    raise exception
      'No auth user for m@blinddrop.app. Create it first with a POST to '
      '/auth/v1/admin/users (email_confirm true), then re-run this.';
  end if;

  -- ─── the roster ──────────────────────────────────────────────────────────
  -- The four empty-string token columns are not optional: GoTrue reads them as `string`, not
  -- `*string` (see server/supabase/seed.sql). These three never sign in; the row shape is kept
  -- identical to a real one rather than relying on that.
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new,
                          email_change)
  select '00000000-0000-0000-0000-000000000000', c.id, 'authenticated', 'authenticated',
         c.handle || '@marketing.blinddrop.fixture', now(),
         '{"provider":"apple","providers":["apple"]}'::jsonb, '{}'::jsonb, now(), now(),
         '', '', '', ''
    from (values (v_seo, 'seo'), (v_joc, 'jocelyn'), (v_rao, 'raoul'))
         as c(id, handle)
  on conflict (id) do nothing;

  insert into public.profiles (id, display_name)
  values (v_king, 'Kingston'), (v_seo, 'Seo'), (v_joc, 'Jocelyn'), (v_rao, 'Raoul')
  on conflict (id) do update
    set display_name = excluded.display_name, updated_at = now();

  -- ─── the circle ──────────────────────────────────────────────────────────
  insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
  values (v_group, 'The Cove', 'America/Los_Angeles', 20, 'MKTG99', v_king)
  on conflict (id) do nothing;

  update public.groups
     set is_demo = true,      -- hands off, schedulers
         cue_cadence = 1      -- every night carries a cue
   where id = v_group;

  -- Backdated so the circle does not read as founded sixty seconds ago.
  insert into public.memberships (group_id, user_id, role, joined_at)
  select v_group, m.id, m.role, public.now_() - interval '9 days'
    from (values (v_king, 'admin'), (v_seo, 'member'),
                 (v_joc, 'member'), (v_rao, 'member')) as m(id, role)
   where not exists (
     select 1 from public.memberships x
      where x.group_id = v_group and x.user_id = m.id and x.left_at is null);

  -- ─── tonight ─────────────────────────────────────────────────────────────
  -- Scoped to this group id and nothing else. Submissions and guesses follow by cascade.
  delete from public.rounds where group_id = v_group;

  -- Half an hour into the reveal window, so the client renders a live "1:30 to answers"
  -- countdown from `server_now` rather than something that has already expired.
  v_reveals := public.now_() - interval '30 minutes';

  -- Inserted `open` with a null `card_order`, because the permutation trigger checks it
  -- against the round's submissions and there are none yet.
  insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                             prompt, prompt_key, prompt_custom, prompt_set_at, prompt_set_by)
  values (v_round, v_group,
          (v_reveals at time zone 'America/Los_Angeles')::date, 'open',
          v_reveals - interval '10 hours', v_reveals, v_reveals + interval '2 hours',
          -- A hand-set cue: no catalog entry, `prompt_key` null, `prompt_custom` true, and so
          -- exempt from `rewrite_open_round_cues()` (20260909130000).
          'Your favorite song rn', null, true, now(), v_king);

  insert into public.submissions (id, round_id, user_id, track_key, track_meta)
  select s.id, v_round, s.user_id, s.meta ->> 'track_key', s.meta
    from (values
      (v_c1, v_joc,
       '{"track_key":"am:1591107493","isrc":null,"title":"God In Wilson","artist":"Dijon","album":"Absolutely","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/f3/c8/3e/f3c83e4f-8b8a-0038-ceca-094b969b67ab/093624878216.jpg/{w}x{h}bb.jpg","artwork_bg_color":"b8442c","duration_ms":135350,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/b6/13/8b/b6138b10-9ede-1f35-a6a3-8d5b338c7816/mzaf_15362872562608523626.plus.aac.p.m4a","apple_music_id":"1591107493","apple_music_url":"https://music.apple.com/us/song/1591107493","spotify_id":null,"spotify_url":null}'::jsonb),
      (v_c2, v_seo,
       '{"track_key":"am:1497701336","isrc":null,"title":"In a Jar","artist":"Dinosaur Jr.","album":"You''re Living All Over Me (Bonus Track Version)","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/9c/73/59/9c73597a-d4fd-6726-4524-ad87333fe2b9/cover.jpg/{w}x{h}bb.jpg","artwork_bg_color":"6d7b55","duration_ms":208667,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/85/00/a7/8500a76a-7ca3-fc2a-a1e5-48623250ecc5/mzaf_14054056410320552143.plus.aac.p.m4a","apple_music_id":"1497701336","apple_music_url":"https://music.apple.com/us/song/1497701336","spotify_id":null,"spotify_url":null}'::jsonb),
      (v_c3, v_rao,
       '{"track_key":"am:1708308996","isrc":null,"title":"Style (Taylor''s Version)","artist":"Taylor Swift","album":"1989 (Taylor''s Version)","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/11/a6/80/11a680e6-2e48-08fa-5e87-3f18e838d31f/23UM1IM11868.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"c9b9a6","duration_ms":231000,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/bd/5d/72/bd5d726f-f082-732a-bfac-102ab3739ec7/mzaf_13805328136345741566.plus.aac.p.m4a","apple_music_id":"1708308996","apple_music_url":"https://music.apple.com/us/song/1708308996","spotify_id":null,"spotify_url":null}'::jsonb),
      (v_c4, v_king,
       '{"track_key":"am:1761703506","isrc":null,"title":"Chihiro","artist":"Gravagerz","album":"Chihiro - Single","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/de/7c/9b/de7c9b2e-af9f-687e-f67e-a6c1396eb084/68.jpg/{w}x{h}bb.jpg","artwork_bg_color":"2a2f3a","duration_ms":128576,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/81/88/ae/8188aeba-0833-a6e4-8d19-dd9dcdd584eb/mzaf_3074252582678508423.plus.aac.p.m4a","apple_music_id":"1761703506","apple_music_url":"https://music.apple.com/us/song/1761703506","spotify_id":null,"spotify_url":null}'::jsonb)
    ) as s(id, user_id, meta);

  -- Now the cards exist, so the permutation trigger can be satisfied.
  update public.rounds
     set state = 'revealed',
         card_order = jsonb_build_array(v_c1, v_c2, v_c3, v_c4)
   where id = v_round;

  -- ─── the room's guesses ──────────────────────────────────────────────────
  -- Engineered, not arbitrary. Each member guesses the three cards that are not their own.
  --
  --   No. 2 (Seo)      → nobody has it. This is the video's whole premise, and it is what
  --                      makes the share card's headline read "Nobody got No. 2" (rule 5 of
  --                      docs/10's precedence).
  --   No. 4 (Kingston) → exactly one member has it. One is deliberate: zero would fire rule 1
  --                      ("Nobody got you") and pre-empt rule 5, while 1-of-3 puts readability
  --                      at 33% — `hard_to_place`, comfortably clear of the `unreadable` band
  --                      that would fire rule 4 (0005_scoring.sql:179).
  --
  -- Kingston's own three guesses are left empty on purpose: he makes them on camera. **He must
  -- get No. 2 wrong** or the headline above changes under him.
  insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
  values
    (v_round, v_seo, v_c1, v_rao),    -- wrong
    (v_round, v_seo, v_c3, v_joc),    -- wrong
    (v_round, v_seo, v_c4, v_king),   -- correct — the single read of Kingston's card
    (v_round, v_joc, v_c2, v_king),   -- wrong, and must stay wrong
    (v_round, v_joc, v_c3, v_rao),    -- correct
    (v_round, v_joc, v_c4, v_seo),    -- wrong
    (v_round, v_rao, v_c1, v_joc),    -- correct
    (v_round, v_rao, v_c2, v_king),   -- wrong, and must stay wrong
    (v_round, v_rao, v_c4, v_seo)     -- wrong
  on conflict (round_id, guesser_id, submission_id) do nothing;

  raise notice
    'Marketing circle ready. group=% round=% — four cards, revealed, cue "Your favorite song '
    'rn". No. 2 is Seo (In a Jar). Sign in as m@blinddrop.app via App Review Sign In.',
    v_group, v_round;
end $$;
