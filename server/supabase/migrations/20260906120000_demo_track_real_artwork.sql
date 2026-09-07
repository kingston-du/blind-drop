-- 20260906120000_demo_track_real_artwork.sql
--
-- `public.demo_track` (20260815090500_demo_lifecycle.sql) documents itself as using "real
-- songs with real identifiers, so search results, artwork, links and the share card all
-- render as they would for a member." The identifiers and links were real; the artwork was
-- not — every `artwork_url` pointed at `.../fixture/{id}/{w}x{h}bb.jpg`, a path segment that
-- never resolves (it is the same non-resolving convention `_shared/music/fixtures.ts` uses on
-- purpose for the *test* catalogue, docs/06 §2). For the App Review demo account a reviewer
-- actually looks at, that leaves every sealed and revealed card showing the placeholder tint
-- instead of the album art the comment already promised.
--
-- This redefines the same nine rows with each song's real Apple Music artwork URL, still as
-- a `{w}x{h}` template so `ArtworkView`'s sizing math keeps exercising exactly as before.
-- Nothing else about the row (title, artist, album, isrc, ids, links, bg color) changes.

create or replace function public.demo_track(p_index int)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select (array[
    '{"track_key":"isrc:USQX91600321","isrc":"USQX91600321","title":"Nights","artist":"Frank Ocean","album":"Blonde","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/bb/45/68/bb4568f3-68cd-619d-fbcb-4e179916545d/BlondCover-Final.jpg/{w}x{h}bb.jpg","artwork_bg_color":"2b2b2b","duration_ms":307000,"preview_url":null,"apple_music_id":"1440765580","apple_music_url":"https://music.apple.com/us/song/1440765580","spotify_id":"7eqoqGkKwgOaWNNHx90uEZ","spotify_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ"}',
    '{"track_key":"isrc:USQX91601480","isrc":"USQX91601480","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/f1/3c/d7/f13cd7ab-7319-028a-8807-5991d0b308d4/0044003187658_Cover.jpg/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326000,"preview_url":null,"apple_music_id":"1452874255","apple_music_url":"https://music.apple.com/us/song/1452874255","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}',
    '{"track_key":"isrc:USQX91901234","isrc":"USQX91901234","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/47/06/f24706bc-a90c-f730-bd8a-586ddde8af3e/829299184631.jpg/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":258000,"preview_url":null,"apple_music_id":"1468055107","apple_music_url":"https://music.apple.com/us/song/1468055107","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}',
    '{"track_key":"isrc:USDW11700831","isrc":"USDW11700831","title":"Motion Sickness","artist":"Phoebe Bridgers","album":"Stranger in the Alps","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/20/4c/6e/204c6ef3-8e95-4cee-2256-202ca62aebed/60220.jpg/{w}x{h}bb.jpg","artwork_bg_color":"3d4a52","duration_ms":239000,"preview_url":null,"apple_music_id":"1440830827","apple_music_url":"https://music.apple.com/us/song/1440830827","spotify_id":"0YSjKUbxJYuJ4Zk9CWjWLu","spotify_url":"https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu"}',
    '{"track_key":"isrc:USUM71812409","isrc":"USUM71812409","title":"Sunflower","artist":"Post Malone & Swae Lee","album":"Spider-Man: Into the Spider-Verse","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4b/30/2c/4b302cb6-7a14-5464-4e97-0577e9d0be49/18UMGIM82277.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"c46a2a","duration_ms":158000,"preview_url":null,"apple_music_id":"1442571948","apple_music_url":"https://music.apple.com/us/song/1442571948","spotify_id":"3KkXRkHbMCARz0aVfEt68P","spotify_url":"https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P"}',
    '{"track_key":"isrc:USRC12204245","isrc":"USRC12204245","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/bd/3b/a9/bd3ba9fb-9609-144f-bcfe-ead67b5f6ab3/196589564931.jpg/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153000,"preview_url":null,"apple_music_id":"1656689279","apple_music_url":"https://music.apple.com/us/song/1656689279","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}',
    '{"track_key":"isrc:USUM71311296","isrc":"USUM71311296","title":"Ribs","artist":"Lorde","album":"Pure Heroine","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/96/a5/09/96a50916-169b-724c-b722-b8c474406352/13UAAIM68691.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"1d2b3a","duration_ms":249000,"preview_url":null,"apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":"2QjOHCTQ1JF3zJyfWY7EMU","spotify_url":"https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"}',
    '{"track_key":"isrc:GBAHT1600302","isrc":"GBAHT1600302","title":"Green Light","artist":"Lorde","album":"Melodrama","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/8d/0d/15/8d0d1532-493b-52ec-6a29-a239ced6931b/17UMGIM81023.rgb.jpg/{w}x{h}bb.jpg","artwork_bg_color":"3b2f6b","duration_ms":234000,"preview_url":null,"apple_music_id":"1440871009","apple_music_url":"https://music.apple.com/us/song/1440871009","spotify_id":"6ie2Bw3xLj2JcGowOlcMhb","spotify_url":"https://open.spotify.com/track/6ie2Bw3xLj2JcGowOlcMhb"}',
    '{"track_key":"isrc:USAT21902956","isrc":"USAT21902956","title":"Cellophane","artist":"FKA twigs","album":"MAGDALENE","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/f5/90/ea/f590eabf-d737-e907-338b-73148d9fc898/889030019158.png/{w}x{h}bb.jpg","artwork_bg_color":"5a2b3a","duration_ms":195000,"preview_url":null,"apple_music_id":"1479305371","apple_music_url":"https://music.apple.com/us/song/1479305371","spotify_id":"1CQ2sGCLNVjMIhFbHzkeVW","spotify_url":"https://open.spotify.com/track/1CQ2sGCLNVjMIhFbHzkeVW"}'
  ])[1 + (p_index % 9)]::jsonb
$$;

comment on function public.demo_track(int) is
  'Fixture track_meta by index, wrapping at nine. Real identifiers and real artwork so a '
  'member''s cards, links and the share card render exactly as they would for a live '
  'submission (docs/06 §2).';

revoke all on function public.demo_track(int) from public, anon, authenticated;
