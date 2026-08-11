-- seed.sql — docs/03 §7, docs/02 §4.4
--
-- GENERATED FIXTURE, hand-verified. One group, nine profiles (Ana…Ivy), three rounds:
-- 2026-08-08 scored (the full §4.4 matrix), 2026-08-09 revealed, 2026-08-10 open.
--
-- Dates are fixed, not relative to now(), so every test is deterministic. Tests move the
-- clock with public.now_() / set_test_now() rather than re-seeding.
--
-- ┌─ Open question (tasks/E01, E01-04) ──────────────────────────────────────────────────┐
-- │ docs/02 §4.4 as written is unsatisfiable. "Cal guesses all 7; 7 correct" forces every │
-- │ card except Cal's own to hold at least one correct guess, which contradicts Gus's     │
-- │ stated readability of 0/7. The repair applied here is the smallest one that keeps     │
-- │ every stated *guess activity* number intact and touches only the readability table,   │
-- │ which the doc introduces hypothetically ("say the correct-guess counts … were"):      │
-- │     Gus readability 0 → 1     Hal readability 5 → 4                                   │
-- │ Ear is unchanged. Totals balance at 26 either way. Owner's call to confirm.           │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ISRCs and Apple/Spotify ids below are plausible-shaped fixtures, not live catalog ids.

set local role postgres;

-- ─── auth users ──────────────────────────────────────────────────────────────
--
-- The four empty-string token columns are not decoration: GoTrue reads them as `string`, not
-- `*string`, so a NULL there makes `GET /auth/v1/user` fail with a 500 and every fixture user
-- unusable from an Edge Function test (tasks/E02-01 found this the hard way).
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
values
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000001','authenticated','authenticated','ana@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000002','authenticated','authenticated','ben@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000003','authenticated','authenticated','cal@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000004','authenticated','authenticated','dee@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000005','authenticated','authenticated','eli@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000006','authenticated','authenticated','fay@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000007','authenticated','authenticated','gus@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000008','authenticated','authenticated','hal@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','',''),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000009','authenticated','authenticated','ivy@fixture.blinddrop.test','2026-08-01T12:00:00Z','{"provider":"apple","providers":["apple"]}'::jsonb,'{}'::jsonb,'2026-08-01T12:00:00Z','2026-08-01T12:00:00Z','','','','');

-- ─── profiles ────────────────────────────────────────────────────────────────
insert into public.profiles (id, display_name, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-000000000001','Ana','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000002','Ben','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000003','Cal','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000004','Dee','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000005','Eli','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000006','Fay','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000007','Gus','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000008','Hal','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z'),
  ('a0000000-0000-4000-8000-000000000009','Ivy','2026-08-01T12:00:00Z','2026-08-01T12:00:00Z');

-- ─── group ───────────────────────────────────────────────────────────────────
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by, created_at)
values ('b0000000-0000-4000-8000-000000000001','The Cove','America/New_York',20,'K7MQ2X',
        'a0000000-0000-4000-8000-000000000001','2026-08-01T12:00:00Z');

-- Ana created it, so Ana is the admin (docs/04 §3).
insert into public.memberships (group_id, user_id, role, joined_at)
values
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','admin','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000005','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','member','2026-08-01T12:00:00Z'),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000009','member','2026-08-01T12:00:00Z');

-- ─── rounds ──────────────────────────────────────────────────────────────────
-- reveals_at is the group-local wall clock materialised through the group's timezone, so
-- these instants are DST-correct for their date (docs/02 §1).
insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at,
                           card_order, created_at)
select r.id, g.id, r.local_date, r.state,
       ((r.local_date + time '20:00') at time zone g.timezone) - interval '10 hours',
       ((r.local_date + time '20:00') at time zone g.timezone),
       ((r.local_date + time '20:00') at time zone g.timezone) + interval '2 hours',
       r.card_order, '2026-08-01T12:00:00Z'
from public.groups g,
     (values
       ('c0000000-0000-4000-8000-000000000001'::uuid, date '2026-08-08', 'scored'::round_state,
         '["d1000000-0000-4000-8000-000000000004", "d1000000-0000-4000-8000-000000000002", "d1000000-0000-4000-8000-000000000008", "d1000000-0000-4000-8000-000000000001", "d1000000-0000-4000-8000-000000000007", "d1000000-0000-4000-8000-000000000003", "d1000000-0000-4000-8000-000000000005", "d1000000-0000-4000-8000-000000000006"]'::jsonb),
       ('c0000000-0000-4000-8000-000000000002'::uuid, date '2026-08-09', 'revealed'::round_state,
         '["d2000000-0000-4000-8000-000000000004", "d2000000-0000-4000-8000-000000000005", "d2000000-0000-4000-8000-000000000001", "d2000000-0000-4000-8000-000000000006", "d2000000-0000-4000-8000-000000000002", "d2000000-0000-4000-8000-000000000003"]'::jsonb),
       ('c0000000-0000-4000-8000-000000000003'::uuid, date '2026-08-10', 'open'::round_state,
         null::jsonb)
     ) as r(id, local_date, state, card_order)
where g.id = 'b0000000-0000-4000-8000-000000000001';

-- ─── submissions — 2026-08-08, scored (docs/02 §4.4) ───
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at, updated_at)
values
  ('d1000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','isrc:USUM71311296',
   '{"track_key":"isrc:USUM71311296","isrc":"USUM71311296","title":"Ribs","artist":"Lorde","album":"Pure Heroine","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440818664/{w}x{h}bb.jpg","artwork_bg_color":"1d2b3a","duration_ms":249000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440818664.m4a","apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":"2QjOHCTQ1JF3zJyfWY7EMU","spotify_url":"https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','isrc:USUM71311296',
   '{"track_key":"isrc:USUM71311296","isrc":"USUM71311296","title":"Ribs","artist":"Lorde","album":"Pure Heroine","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440818664/{w}x{h}bb.jpg","artwork_bg_color":"1d2b3a","duration_ms":249000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440818664.m4a","apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":"2QjOHCTQ1JF3zJyfWY7EMU","spotify_url":"https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','isrc:USQX91600321',
   '{"track_key":"isrc:USQX91600321","isrc":"USQX91600321","title":"Nights","artist":"Frank Ocean","album":"Blonde","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440765580/{w}x{h}bb.jpg","artwork_bg_color":"2b2b2b","duration_ms":307000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440765580.m4a","apple_music_id":"1440765580","apple_music_url":"https://music.apple.com/us/song/1440765580","spotify_id":"7eqoqGkKwgOaWNNHx90uEZ","spotify_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','isrc:USQX91601480',
   '{"track_key":"isrc:USQX91601480","isrc":"USQX91601480","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1452874255/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1452874255.m4a","apple_music_id":"1452874255","apple_music_url":"https://music.apple.com/us/song/1452874255","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000005','isrc:USDW11700831',
   '{"track_key":"isrc:USDW11700831","isrc":"USDW11700831","title":"Motion Sickness","artist":"Phoebe Bridgers","album":"Stranger in the Alps","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440830827/{w}x{h}bb.jpg","artwork_bg_color":"3d4a52","duration_ms":239000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440830827.m4a","apple_music_id":"1440830827","apple_music_url":"https://music.apple.com/us/song/1440830827","spotify_id":"0YSjKUbxJYuJ4Zk9CWjWLu","spotify_url":"https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000006','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','isrc:USUM71812409',
   '{"track_key":"isrc:USUM71812409","isrc":"USUM71812409","title":"Sunflower","artist":"Post Malone & Swae Lee","album":"Spider-Man: Into the Spider-Verse","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1442571948/{w}x{h}bb.jpg","artwork_bg_color":"c46a2a","duration_ms":158000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1442571948.m4a","apple_music_id":"1442571948","apple_music_url":"https://music.apple.com/us/song/1442571948","spotify_id":"3KkXRkHbMCARz0aVfEt68P","spotify_url":"https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000007','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','isrc:USRC12204245',
   '{"track_key":"isrc:USRC12204245","isrc":"USRC12204245","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1656689279/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1656689279.m4a","apple_music_id":"1656689279","apple_music_url":"https://music.apple.com/us/song/1656689279","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z'),
  ('d1000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','isrc:USQX91901234',
   '{"track_key":"isrc:USQX91901234","isrc":"USQX91901234","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1468055107/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":258000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1468055107.m4a","apple_music_id":"1468055107","apple_music_url":"https://music.apple.com/us/song/1468055107","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}'::jsonb,'2026-08-08T15:30:00Z','2026-08-08T15:30:00Z');

-- ─── submissions — 2026-08-09, revealed ───
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at, updated_at)
values
  ('d2000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','isrc:USQX91601480',
   '{"track_key":"isrc:USQX91601480","isrc":"USQX91601480","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1452874255/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1452874255.m4a","apple_music_id":"1452874255","apple_music_url":"https://music.apple.com/us/song/1452874255","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z'),
  ('d2000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003','isrc:USUM71812409',
   '{"track_key":"isrc:USUM71812409","isrc":"USUM71812409","title":"Sunflower","artist":"Post Malone & Swae Lee","album":"Spider-Man: Into the Spider-Verse","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1442571948/{w}x{h}bb.jpg","artwork_bg_color":"c46a2a","duration_ms":158000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1442571948.m4a","apple_music_id":"1442571948","apple_music_url":"https://music.apple.com/us/song/1442571948","spotify_id":"3KkXRkHbMCARz0aVfEt68P","spotify_url":"https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z'),
  ('d2000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000004','isrc:USQX91901234',
   '{"track_key":"isrc:USQX91901234","isrc":"USQX91901234","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1468055107/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":258000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1468055107.m4a","apple_music_id":"1468055107","apple_music_url":"https://music.apple.com/us/song/1468055107","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z'),
  ('d2000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000006','isrc:USQX91600321',
   '{"track_key":"isrc:USQX91600321","isrc":"USQX91600321","title":"Nights","artist":"Frank Ocean","album":"Blonde","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440765580/{w}x{h}bb.jpg","artwork_bg_color":"2b2b2b","duration_ms":307000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440765580.m4a","apple_music_id":"1440765580","apple_music_url":"https://music.apple.com/us/song/1440765580","spotify_id":"7eqoqGkKwgOaWNNHx90uEZ","spotify_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z'),
  ('d2000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000008','isrc:USRC12204245',
   '{"track_key":"isrc:USRC12204245","isrc":"USRC12204245","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1656689279/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1656689279.m4a","apple_music_id":"1656689279","apple_music_url":"https://music.apple.com/us/song/1656689279","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z'),
  ('d2000000-0000-4000-8000-000000000006','c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000007','isrc:USDW11700831',
   '{"track_key":"isrc:USDW11700831","isrc":"USDW11700831","title":"Motion Sickness","artist":"Phoebe Bridgers","album":"Stranger in the Alps","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440830827/{w}x{h}bb.jpg","artwork_bg_color":"3d4a52","duration_ms":239000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1440830827.m4a","apple_music_id":"1440830827","apple_music_url":"https://music.apple.com/us/song/1440830827","spotify_id":"0YSjKUbxJYuJ4Zk9CWjWLu","spotify_url":"https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu"}'::jsonb,'2026-08-09T15:30:00Z','2026-08-09T15:30:00Z');

-- ─── submissions — 2026-08-10, open — nothing about these may leak before 2026-08-11T00:00Z ───
insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at, updated_at)
values
  ('d3000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','isrc:USRC12204245',
   '{"track_key":"isrc:USRC12204245","isrc":"USRC12204245","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1656689279/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1656689279.m4a","apple_music_id":"1656689279","apple_music_url":"https://music.apple.com/us/song/1656689279","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}'::jsonb,'2026-08-10T15:30:00Z','2026-08-10T15:30:00Z'),
  ('d3000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000003','isrc:USQX91601480',
   '{"track_key":"isrc:USQX91601480","isrc":"USQX91601480","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1452874255/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1452874255.m4a","apple_music_id":"1452874255","apple_music_url":"https://music.apple.com/us/song/1452874255","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}'::jsonb,'2026-08-10T15:30:00Z','2026-08-10T15:30:00Z'),
  ('d3000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000006','isrc:USQX91901234',
   '{"track_key":"isrc:USQX91901234","isrc":"USQX91901234","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1468055107/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":258000,"preview_url":"https://audio-ssl.itunes.apple.com/fixture/1468055107.m4a","apple_music_id":"1468055107","apple_music_url":"https://music.apple.com/us/song/1468055107","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}'::jsonb,'2026-08-10T15:30:00Z','2026-08-10T15:30:00Z');

-- ─── guesses — 2026-08-08 ────────────────────────────────────────────────────
-- 46 rows. Ana 7 guesses/5 correct · Ben 4/3 (3 cards left blank) · Cal 7/7 · Dee 7/2 ·
-- Eli 0 (opened the app, assigned nothing) · Fay 7/4 · Gus 7/1 · Hal 7/4.
-- Correctness follows the duplicate rule: Ana and Ben both dropped Ribs, so naming either
-- on either of their cards is correct (docs/02 §4.3).
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id,
                            created_at, updated_at)
values
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000006','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000008','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000007','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000008','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000005','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000006','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000007','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000008','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000006','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000006','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000008','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000005','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000008','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000007','d1000000-0000-4000-8000-000000000008','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000003','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000001','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000004','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z'),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','d1000000-0000-4000-8000-000000000007','a0000000-0000-4000-8000-000000000002','2026-08-08T20:40:00Z','2026-08-08T20:40:00Z');

-- ─── guesses — 2026-08-09, a sheet still in progress ─────────────────────────
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id,
                            created_at, updated_at)
values
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z'),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000008','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z'),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003','d2000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z'),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003','d2000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000006','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z'),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000004','d2000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000008','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z'),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000006','d2000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000007','2026-08-09T20:15:00Z','2026-08-09T20:15:00Z');

-- ─── track_links — the cross-service cache (docs/06 §5) ──────────────────────
insert into public.track_links (track_key, isrc, apple_music_id, apple_music_url,
                                spotify_id, spotify_url, resolved_at, resolve_attempts,
                                unresolvable)
values
  ('isrc:USUM71311296','USUM71311296','1440818664','https://music.apple.com/us/song/1440818664','2QjOHCTQ1JF3zJyfWY7EMU','https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU','2026-08-08T15:31:00Z',1,false),
  ('isrc:USQX91600321','USQX91600321','1440765580','https://music.apple.com/us/song/1440765580','7eqoqGkKwgOaWNNHx90uEZ','https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ','2026-08-08T15:31:00Z',1,false),
  ('isrc:USQX91601480','USQX91601480','1452874255','https://music.apple.com/us/song/1452874255','0wXuerDYiBnERgIpbb3JBR','https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR','2026-08-08T15:31:00Z',1,false),
  ('isrc:USDW11700831','USDW11700831','1440830827','https://music.apple.com/us/song/1440830827','0YSjKUbxJYuJ4Zk9CWjWLu','https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu','2026-08-08T15:31:00Z',1,false),
  ('isrc:USUM71812409','USUM71812409','1442571948','https://music.apple.com/us/song/1442571948','3KkXRkHbMCARz0aVfEt68P','https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P','2026-08-08T15:31:00Z',1,false),
  ('isrc:USRC12204245','USRC12204245','1656689279','https://music.apple.com/us/song/1656689279','1Qrg8KqiBpW07V7PNxwwwL','https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL','2026-08-08T15:31:00Z',1,false),
  ('isrc:USQX91901234','USQX91901234','1468055107','https://music.apple.com/us/song/1468055107','3AwF0Ea5jUqLDWWDaXocxT','https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT','2026-08-08T15:31:00Z',1,false);

-- `supabase db reset` loads this dated fixture after migrations have registered the live
-- cron jobs. Pause them locally so the real wall clock cannot advance the fixture while a
-- developer or pgTAP is inspecting it. Hosted deployments apply migrations without this
-- seed and therefore leave both jobs active. README documents the explicit local opt-in.
select public.set_blind_drop_jobs_active(false);
