-- 20260910120000_demo_room_of_six.sql — a fuller room for App Review, and songs that play.
--
-- Two changes to the demo fixture, both about what a reviewer actually sees.
--
-- **Five companions, not three.** A four-person room is the smallest one the game works in,
-- and it reads like the smallest one: the reveal is three cards, the guess sheet is two
-- names, and the standings are a list you take in without looking. Six is what a real circle
-- looks like — five cards to read, five names to place, a leaderboard with a middle. Nothing
-- about the loop changes; the room is just no longer at its floor. `demo_provision()` is
-- generalised over the roster rather than counting to four in six places, so the next change
-- of mind is one array literal.
--
-- **The catalogue is real, and it plays.** Every row already carried real titles and real
-- links, and 20260906120000 gave them real artwork — but `preview_url` was null throughout
-- and the `apple_music_id` on every row was the *album's* id, not the song's, so
-- `music.apple.com/us/song/<id>` opened the wrong page. That leaves the one control a
-- reviewer is most likely to press — the 30-second preview — absent from every card
-- (`docs/06` §7 gives a track with no preview no control at all, which is correct behaviour
-- for a fixture that lied about itself). Each row is re-resolved from the iTunes catalogue:
-- song id, song link, the song's own `previewUrl`, its real duration, its ISRC where one
-- could be verified against the same recording, and the artwork template as before. All
-- thirty-six URLs were fetched and checked before this was written.
--
-- Twelve rows rather than nine, because a round of six now takes six of them and The Record
-- should not show the same six songs on consecutive nights.
--
-- **The owner must re-run `server/scripts/seed-app-review-demo.sql` after this.** Redefining
-- the functions does not add the two companions to a group that has already been provisioned,
-- and a demo group whose live round is missing two of its members never completes its room —
-- so it would slide its reveal forward for ever. The script clears the rounds and provisions
-- from scratch, which is exactly what that situation wants.

-- ─── the fixture catalogue ───────────────────────────────────────────────────
-- Real songs, real song ids, real previews. `track_key` is the ISRC where the recording could
-- be confirmed and `am:<id>` where it could not (`docs/06` §3 defines both); nothing here is
-- invented, which is the whole point of a fixture a reviewer looks at.

create or replace function public.demo_track(p_index int)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select (array[
    '{"track_key":"isrc:QZ5C81600009","isrc":"QZ5C81600009","title":"Nights","artist":"Frank Ocean","album":"Blonde","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/bb/45/68/bb4568f3-68cd-619d-fbcb-4e179916545d/BlondCover-Final.jpg/{w}x{h}bb.jpg","artwork_bg_color":"2b2b2b","duration_ms":307151,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/a6/8c/70/a68c700b-0c96-2eff-79a7-b4c3607a4a0f/mzaf_6282991914472119670.plus.aac.p.m4a","apple_music_id":"1146195720","apple_music_url":"https://music.apple.com/us/song/1146195720","spotify_id":"7eqoqGkKwgOaWNNHx90uEZ","spotify_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ"}',
    '{"track_key":"isrc:USYAH1600107","isrc":"USYAH1600107","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/f1/3c/d7/f13cd7ab-7319-028a-8807-5991d0b308d4/0044003187658_Cover.jpg/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326933,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/05/f1/e2/05f1e25b-aa46-5a60-040a-a8d52483d487/mzaf_5014076935652388885.plus.aac.p.m4a","apple_music_id":"1771719595","apple_music_url":"https://music.apple.com/us/song/1771719595","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}',
    '{"track_key":"isrc:US4HB1900080","isrc":"US4HB1900080","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/47/06/f24706bc-a90c-f730-bd8a-586ddde8af3e/829299184631.jpg/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":260520,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/67/b9/3d/67b93d4e-07cb-cd11-7d64-88762c42a230/mzaf_15744728589488284514.plus.aac.p.m4a","apple_music_id":"1893175134","apple_music_url":"https://music.apple.com/us/song/1893175134","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}',
    '{"track_key":"isrc:USJ5G1714202","isrc":"USJ5G1714202","title":"Motion Sickness","artist":"Phoebe Bridgers","album":"Stranger in the Alps","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/20/4c/6e/204c6ef3-8e95-4cee-2256-202ca62aebed/60220.jpg/{w}x{h}bb.jpg","artwork_bg_color":"3d4a52","duration_ms":229760,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/88/0d/3c/880d3c6d-70f6-4628-a1dc-5b07ef90421c/mzaf_7359776133976251843.plus.aac.p.m4a","apple_music_id":"1256607810","apple_music_url":"https://music.apple.com/us/song/1256607810","spotify_id":"0YSjKUbxJYuJ4Zk9CWjWLu","spotify_url":"https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu"}',
    '{"track_key":"isrc:USUM71814888","isrc":"USUM71814888","title":"Sunflower","artist":"Post Malone & Swae Lee","album":"Spider-Man: Into the Spider-Verse","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4b/30/2c/4b302cb6-7a14-5464-4e97-0577e9d0be49/18UMGIM82277.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"c46a2a","duration_ms":158040,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/98/f0/d6/98f0d67e-f8bf-762d-cac7-1c6b3b6b35dd/mzaf_4543283896248560946.plus.aac.p.m4a","apple_music_id":"1445949267","apple_music_url":"https://music.apple.com/us/song/1445949267","spotify_id":"3KkXRkHbMCARz0aVfEt68P","spotify_url":"https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P"}',
    '{"track_key":"isrc:USRC12204584","isrc":"USRC12204584","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/bd/3b/a9/bd3ba9fb-9609-144f-bcfe-ead67b5f6ab3/196589564931.jpg/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153947,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/45/2b/ea/452bead6-c7f5-82d4-f5f7-ec876014b4cc/mzaf_2905911853279084717.plus.aac.p.m4a","apple_music_id":"1657869393","apple_music_url":"https://music.apple.com/us/song/1657869393","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}',
    '{"track_key":"isrc:NZUM71300122","isrc":"NZUM71300122","title":"Ribs","artist":"Lorde","album":"Pure Heroine","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/96/a5/09/96a50916-169b-724c-b722-b8c474406352/13UAAIM68691.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"1d2b3a","duration_ms":258969,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/13/8c/1a/138c1a93-5fdf-f1a3-c288-c0fd8d7c8d2f/mzaf_12940840614985303434.plus.aac.p.m4a","apple_music_id":"1440818666","apple_music_url":"https://music.apple.com/us/song/1440818666","spotify_id":"2QjOHCTQ1JF3zJyfWY7EMU","spotify_url":"https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"}',
    '{"track_key":"isrc:NZUM71700063","isrc":"NZUM71700063","title":"Green Light","artist":"Lorde","album":"Melodrama","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/8d/0d/15/8d0d1532-493b-52ec-6a29-a239ced6931b/17UMGIM81023.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"3b2f6b","duration_ms":234653,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/52/98/aa/5298aa77-f5d0-e6b7-7f24-5d06409abfc8/mzaf_4826261660034311199.plus.aac.p.m4a","apple_music_id":"1429663163","apple_music_url":"https://music.apple.com/us/song/1429663163","spotify_id":"6ie2Bw3xLj2JcGowOlcMhb","spotify_url":"https://open.spotify.com/track/6ie2Bw3xLj2JcGowOlcMhb"}',
    '{"track_key":"isrc:UK7MC1900009","isrc":"UK7MC1900009","title":"Cellophane","artist":"FKA twigs","album":"MAGDALENE","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/f5/90/ea/f590eabf-d737-e907-338b-73148d9fc898/889030019158.png/{w}x{h}bb.jpg","artwork_bg_color":"5a2b3a","duration_ms":204067,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/e2/7d/8f/e27d8f67-6cdb-2bca-ead5-09fabfd40938/mzaf_710285983220515190.plus.aac.p.m4a","apple_music_id":"1477652823","apple_music_url":"https://music.apple.com/us/song/1477652823","spotify_id":"1CQ2sGCLNVjMIhFbHzkeVW","spotify_url":"https://open.spotify.com/track/1CQ2sGCLNVjMIhFbHzkeVW"}',
    '{"track_key":"isrc:USWB10400046","isrc":"USWB10400046","title":"Dreams","artist":"Fleetwood Mac","album":"Rumours","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/4d/13/ba/4d13bac3-d3d5-7581-2c74-034219eadf2b/081227970949.jpg/{w}x{h}bb.jpg","artwork_bg_color":"9c8466","duration_ms":257800,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/d4/37/e7/d437e72a-c41b-332c-f196-bee295a9d673/mzaf_11574904347171701919.plus.aac.p.m4a","apple_music_id":"594061856","apple_music_url":"https://music.apple.com/us/song/594061856","spotify_id":null,"spotify_url":null}',
    '{"track_key":"isrc:USJ5G2022502","isrc":"USJ5G2022502","title":"Be Sweet","artist":"Japanese Breakfast","album":"Jubilee","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/93/8b/8b/938b8b5d-1022-414f-995e-a25608fc68c3/17251.jpg/{w}x{h}bb.jpg","artwork_bg_color":"c8562b","duration_ms":195371,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/c0/64/67/c0646729-fcb6-0ad1-b996-fd3408b4f4f4/mzaf_679024772755085459.plus.aac.p.m4a","apple_music_id":"1553364593","apple_music_url":"https://music.apple.com/us/song/1553364593","spotify_id":null,"spotify_url":null}',
    '{"track_key":"am:997914096","isrc":null,"title":"Space Song","artist":"Beach House","album":"Depression Cherry","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/09/e0/d5/09e0d559-0682-f0f0-5e0c-3cd11e3114fd/beachhouse_depressioncherry_2400_300.jpg/{w}x{h}bb.jpg","artwork_bg_color":"7a1f2b","duration_ms":320467,"preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/41/61/14/416114cc-282e-4c76-2808-a3eb9c3f973d/mzaf_6665874998714897722.plus.aac.p.m4a","apple_music_id":"997914096","apple_music_url":"https://music.apple.com/us/song/997914096","spotify_id":null,"spotify_url":null}'
  ])[1 + (p_index % 12)]::jsonb
$$;

comment on function public.demo_track(int) is
  'Fixture track_meta by index, wrapping at twelve. Real song ids, artwork and 30-second '
  'previews, so a card, its preview control, its links and the share card all render exactly '
  'as they would for a live submission (docs/06 §2).';

revoke all on function public.demo_track(int) from public, anon, authenticated;

-- ─── demo_seed_companion_submissions ─────────────────────────────────────────
-- Unchanged in shape; the stride moves from three to five so that consecutive rounds do not
-- share songs now that five companions draw from a catalogue of twelve. Five and twelve are
-- coprime, so the rotation visits every row before it repeats one.

create or replace function public.demo_seed_companion_submissions(p_round_id uuid, p_offset int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_c        record;
  v_meta     jsonb;
begin
  select r.group_id into v_group_id from public.rounds r where r.id = p_round_id;

  for v_c in
    select c.user_id, c.position
      from public.demo_companions c
     where c.group_id = v_group_id
     order by c.position
  loop
    v_meta := public.demo_track(p_offset * 5 + v_c.position);
    insert into public.submissions (round_id, user_id, track_key, track_meta)
    values (p_round_id, v_c.user_id, v_meta ->> 'track_key', v_meta)
    on conflict (round_id, user_id) do nothing;
  end loop;
end $$;

revoke all on function public.demo_seed_companion_submissions(uuid, int)
  from public, anon, authenticated;

-- ─── demo_provision ──────────────────────────────────────────────────────────
-- Same contract as 20260815090500: the reviewer's display name, the companions, three
-- finished nights of archive, one live open round, idempotent, owner-run only. Two
-- differences.
--
-- **The roster is data.** `v_names` and `v_companions` are the only place the size of the
-- room is written down; the archive loops read `array_length(v_members, 1)` rather than
-- counting to four. Adding a sixth companion is a line in each array and nothing else.
--
-- **An open round is backfilled before tonight is rolled.** A group provisioned under the
-- old three-companion roster is holding a live round that the two new members are not in,
-- and `demo_tick()` will not reveal a room that is short — it will slide the reveal to the
-- next hour, for ever. Seeding the open round first means the companions are in whatever the
-- reviewer is looking at, not only in rounds rolled after this ran.

create or replace function public.demo_provision(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz        text;
  v_hour      int;
  v_now       timestamptz;
  v_reviewer  uuid;
  v_names     constant text[] := array['Kai', 'Mo', 'Nell', 'Rae', 'Sol'];
  v_companions constant uuid[] := array[
    'f0000000-0000-4000-8000-0000000000a1'::uuid,
    'f0000000-0000-4000-8000-0000000000a2'::uuid,
    'f0000000-0000-4000-8000-0000000000a3'::uuid,
    'f0000000-0000-4000-8000-0000000000a4'::uuid,
    'f0000000-0000-4000-8000-0000000000a5'::uuid];
  v_members   uuid[];
  v_n         int;
  v_subs      uuid[];
  v_order     uuid[];
  v_round     uuid;
  v_open      uuid;
  v_rounds    int;
  v_date      date;
  v_reveals   timestamptz;
  v_meta      jsonb;
  v_guessed   uuid;
  v_i         int;
  v_j         int;
  v_k         int;
begin
  select g.timezone, g.reveal_hour into v_tz, v_hour
    from public.groups g
   where g.id = p_group_id and g.is_demo;
  if not found then
    raise exception 'group % is not a demo group', p_group_id;
  end if;

  v_now := public.now_();

  -- The reviewer is the cohort's founding member — `assign_pilot_cohort()` makes the first
  -- profile through the door the admin, and the companions below are all plain members.
  select m.user_id into v_reviewer
    from public.memberships m
   where m.group_id = p_group_id and m.left_at is null and m.role = 'admin'
   order by m.joined_at
   limit 1;
  if v_reviewer is null then
    raise exception
      'demo group % has no member yet. The reviewer signs in once first (that call to '
      'assign_pilot_cohort() creates the membership), then re-run this.', p_group_id;
  end if;

  update public.profiles
     set display_name = 'App Reviewer', updated_at = now()
   where id = v_reviewer;

  -- The archive below says this account played three nights ago, so its membership has to
  -- predate them. Left at the real signup instant it would contradict its own history, and
  -- `cannotGuessReason()` reads `joined_at` for exactly this kind of question.
  update public.memberships
     -- `least` is a SQL construct rather than a schema-qualifiable function, so it resolves
     -- under the empty search_path unqualified. Qualifying it is a syntax error, not caution.
     set joined_at = least(joined_at, v_now - interval '7 days')
   where group_id = p_group_id and left_at is null;

  -- ── companions ───────────────────────────────────────────────────────────
  -- The four empty-string token columns matter: GoTrue reads them as `string`, not `*string`
  -- (see server/supabase/seed.sql). These five never sign in, but the row shape is kept
  -- identical to a real one rather than relying on that.
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new,
                          email_change)
  select '00000000-0000-0000-0000-000000000000', c.id, 'authenticated', 'authenticated',
         pg_catalog.lower(v_names[c.pos]) || '@review.blinddrop.fixture', now(),
         '{"provider":"apple","providers":["apple"]}'::jsonb, '{}'::jsonb, now(), now(),
         '', '', '', ''
    from pg_catalog.unnest(v_companions) with ordinality as c(id, pos)
  on conflict (id) do nothing;

  insert into public.profiles (id, display_name)
  select c.id, v_names[c.pos]
    from pg_catalog.unnest(v_companions) with ordinality as c(id, pos)
  on conflict (id) do update set display_name = excluded.display_name, updated_at = now();

  insert into public.memberships (group_id, user_id, role)
  select p_group_id, c.id, 'member'
    from pg_catalog.unnest(v_companions) as c(id)
   where not exists (
     select 1 from public.memberships m
      where m.group_id = p_group_id and m.user_id = c.id and m.left_at is null
   );

  insert into public.demo_companions (user_id, group_id, position)
  select c.id, p_group_id, c.pos
    from pg_catalog.unnest(v_companions) with ordinality as c(id, pos)
  on conflict (user_id) do update
    set group_id = excluded.group_id, position = excluded.position;

  v_members := v_reviewer || v_companions;
  v_n       := pg_catalog.array_length(v_members, 1);

  -- ── a live round the new companions are not in ───────────────────────────
  -- Only `open` rounds: a revealed one carries a `card_order` that a late submission would
  -- contradict, and a scored one is history.
  select pg_catalog.count(*)::int into v_rounds
    from public.rounds r where r.group_id = p_group_id;
  for v_open in
    select r.id from public.rounds r
     where r.group_id = p_group_id and r.state = 'open'
  loop
    perform public.demo_seed_companion_submissions(v_open, v_rounds);
  end loop;

  -- ── three finished nights ────────────────────────────────────────────────
  -- Written directly at `scored` rather than played forward: these are the archive, and the
  -- reviewer should find The Record populated on their first launch rather than empty.
  --
  -- The round row carries `card_order` at insert — `rounds_card_order_iff_revealed` (0002) is
  -- an immediate check and a scored round may not have a null one — while the permutation
  -- trigger is deferred to commit, so the submission ids are generated first and the rows
  -- follow inside the same transaction.
  for v_k in 1..3 loop
    v_date := pg_catalog.timezone(v_tz, v_now)::date - v_k;
    continue when exists (
      select 1 from public.rounds r
       where r.group_id = p_group_id and r.local_date = v_date
    );

    v_reveals := pg_catalog.timezone(v_tz, v_date + pg_catalog.make_interval(hours => v_hour));
    v_round := gen_random_uuid();

    select pg_catalog.array_agg(gen_random_uuid()) into v_subs
      from pg_catalog.generate_series(1, v_n);
    -- The night's cards, rotated by the night, so no two archive rounds deal in the same
    -- order. Any permutation satisfies `rounds_card_order_permutation`; rotating one is the
    -- cheapest one to read six months from now.
    select pg_catalog.array_agg(v_subs[1 + ((v_k + i - 1) % v_n)] order by i) into v_order
      from pg_catalog.generate_series(1, v_n) as i;

    insert into public.rounds
           (id, group_id, local_date, state, opens_at, reveals_at, scores_at, card_order)
    values (v_round, p_group_id, v_date, 'scored',
            v_reveals - interval '10 hours', v_reveals, v_reveals + interval '2 hours',
            pg_catalog.to_jsonb(v_order));

    for v_i in 1..v_n loop
      v_meta := public.demo_track(v_k * v_n + v_i);
      insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
      values (v_subs[v_i], v_round, v_members[v_i], v_meta ->> 'track_key', v_meta,
              v_reveals - pg_catalog.make_interval(hours => v_i));
    end loop;

    -- Everyone guesses every card but their own, right about two nights in three. A clean
    -- sweep or a blank sheet would make the results screen and the standings look broken.
    for v_i in 1..v_n loop
      for v_j in 1..v_n loop
        continue when v_i = v_j;
        if ((v_i + v_j + v_k) % 3) <> 0 then
          v_guessed := v_members[v_j];
        else
          v_guessed := v_members[1 + (v_j % v_n)];
          if v_guessed = v_members[v_i] then
            v_guessed := v_members[1 + ((v_j + 1) % v_n)];
          end if;
        end if;
        insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
        values (v_round, v_members[v_i], v_subs[v_j], v_guessed);
      end loop;
    end loop;
  end loop;

  -- ── tonight ──────────────────────────────────────────────────────────────
  -- One live `open` round with the companions already in it, so the reviewer's own drop is
  -- the last one the room is waiting on.
  perform public.demo_tick(p_group_id);
end $$;

comment on function public.demo_provision(uuid) is
  'Prepares a demo group for App Review: names the founding member "App Reviewer", installs '
  'five companions, writes three finished nights of archive, and opens tonight''s round. '
  'Idempotent. Owner-run only — deliberately not granted to service_role.';

revoke all on function public.demo_provision(uuid) from public, anon, authenticated, service_role;
