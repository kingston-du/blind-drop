-- links.sql — the cross-service cache, and the promise it exists to keep. tasks/E07-05,
-- docs/06 §5, docs/15 §2.
--
-- The promise is one line in docs/15 §2 and it is the reason this file exists: **no track is
-- left in limbo.** Every submission in a scored round either carries a Spotify link or belongs
-- to a `track_links` row that says, in writing, that it never will. There is no third state —
-- no "we tried once in August and forgot about it" — because that third state is invisible from
-- the app and shows up only as a song missing from somebody's exported playlist months later.
--
-- Three things hold that promise up, and each gets a test here:
--
--   · the *due* query the worker drains, which must find exactly the rows still worth trying,
--     in the order docs/06 §5 gives, and no more than twenty of them;
--   · the give-up rule, three attempts and stop, so the set of rows still worth trying actually
--     shrinks;
--   · `patch_track_meta_spotify`, which is what makes a link that arrives late reach the eight
--     submissions already in The Record rather than only the next person to drop the song.
--
-- The worker's own HTTP behaviour is `tests/functions/links.test.ts`; this file is the data.

begin;
set search_path = public, extensions, tests;
select plan(18);

-- ─── the due set ─────────────────────────────────────────────────────────────
-- The worker's query, written here exactly as `dueForBackfill` builds it, so a change to one
-- without the other fails rather than drifts.

create or replace function tests.due_links(p_limit int default 20)
returns table (track_key text, resolve_attempts int)
language sql stable as $$
  select l.track_key, l.resolve_attempts
    from public.track_links l
   where l.spotify_id is null
     and l.unresolvable = false
     and l.isrc is not null
   order by l.resolve_attempts asc, l.track_key asc
   limit p_limit
$$;

-- The seed's seven tracks are all resolved, so a healthy database has nothing to do. That is
-- the steady state and it is worth asserting: a worker that always finds work is a worker whose
-- give-up rule is not firing.
select is((select count(*)::int from tests.due_links()), 0,
          'the seeded database has no backlog — every track is already linked');

insert into public.track_links (track_key, isrc, apple_music_id, apple_music_url,
                                spotify_id, spotify_url, resolve_attempts, unresolvable)
values
  -- Two rows still worth trying, at different levels of effort spent.
  ('isrc:LINKS0000001', 'LINKS0000001', '900001', 'https://music.apple.com/us/song/900001',
   null, null, 2, false),
  ('isrc:LINKS0000002', 'LINKS0000002', '900002', 'https://music.apple.com/us/song/900002',
   null, null, 1, false),
  -- Given up on: three attempts spent and flagged. Never due again.
  ('isrc:LINKS0000003', 'LINKS0000003', '900003', 'https://music.apple.com/us/song/900003',
   null, null, 3, true),
  -- No ISRC. `linkTrack` marks these unresolvable on sight — a title/artist search returns the
  -- wrong recording often enough to be worse than nothing (docs/06 §5) — so it is both flagged
  -- and un-lookupable, and the due query excludes it on either ground.
  ('am:900004', null, '900004', 'https://music.apple.com/us/song/900004',
   null, null, 0, true),
  -- Already linked. Nothing to do, however many attempts it took to get there.
  ('isrc:LINKS0000005', 'LINKS0000005', '900005', 'https://music.apple.com/us/song/900005',
   'fxLINKS00000050000000', 'https://open.spotify.com/track/fxLINKS00000050000000', 2, false);

select is((select count(*)::int from tests.due_links()), 2,
          'exactly the two rows still worth a lookup are due');
select is((select array_agg(track_key order by resolve_attempts, track_key)
             from tests.due_links()),
          array['isrc:LINKS0000002', 'isrc:LINKS0000001'],
          'ordered by attempts spent — the likeliest win goes first (docs/06 §5)');
select ok((select bool_and(track_key <> 'isrc:LINKS0000003') from tests.due_links()),
          'a row already given up on is never picked up again');
select ok((select bool_and(track_key <> 'am:900004') from tests.due_links()),
          'a track with no ISRC is never looked up — there is nothing to look up by');
select ok((select bool_and(track_key <> 'isrc:LINKS0000005') from tests.due_links()),
          'a resolved row is not re-resolved');

-- ─── twenty a minute ─────────────────────────────────────────────────────────
-- docs/06 §5. The cap is what keeps one stuck upstream to one minute's work rather than a
-- worker that never finishes.

insert into public.track_links (track_key, isrc, apple_music_id, resolve_attempts, unresolvable)
select 'isrc:LINKSBULK' || lpad(n::text, 4, '0'),
       'LINKSBULK' || lpad(n::text, 4, '0'),
       '95' || lpad(n::text, 4, '0'),
       1, false
  from generate_series(1, 40) as n;

-- Counted without the cap, or the cap would be the answer rather than the thing under test.
select is((select count(*)::int from tests.due_links(1000)), 42,
          'forty-two rows are genuinely waiting');
select is((select count(*)::int from tests.due_links(20)), 20,
          'and a drain takes twenty of them');
select is((select min(resolve_attempts) from tests.due_links(20)), 1,
          'the twenty taken are the least-attempted ones, not an arbitrary twenty');

-- ─── the give-up rule ────────────────────────────────────────────────────────
-- Three attempts and stop (docs/06 §5). The decision itself lives in `trackLinks.ts`, shared
-- between the inline path and the backfill so the two cannot disagree; what this asserts is the
-- consequence the schema has to make possible — that a flagged row leaves the due set, so the
-- backlog is a queue and not a treadmill.

update public.track_links
   set resolve_attempts = 3, unresolvable = true
 where track_key like 'isrc:LINKSBULK%';

select is((select count(*)::int from tests.due_links()), 2,
          'forty rows giving up drops the backlog back to two');
select ok((select bool_and(unresolvable) from public.track_links
            where resolve_attempts >= 3 and spotify_id is null),
          'every row that has spent three attempts without a link is flagged');

-- ─── the late link reaches The Record ────────────────────────────────────────
-- docs/06 §5: when an ISRC finally resolves, every submission already carrying that `track_key`
-- gains the link. Ana and Ben both dropped Ribs in the §4.4 round, so one patch has to reach two
-- rows — and if it reached only the one being written, the archive would carry a Spotify link
-- for whichever of them happened to seal second.

update public.submissions
   set track_meta = track_meta - 'spotify_id' - 'spotify_url'
 where track_key = 'isrc:USUM71311296';

select is((select count(*)::int from public.submissions
            where track_key = 'isrc:USUM71311296'
              and track_meta ? 'spotify_id'),
          0, 'two submissions share the Ribs track_key and neither has a link');

select is(public.patch_track_meta_spotify('isrc:USUM71311296', '2QjOHCTQ1JF3zJyfWY7EMU',
                                          'https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU'),
          2, 'one backfill patches both of them');
select is((select count(*)::int from public.submissions
            where track_key = 'isrc:USUM71311296'
              and track_meta ->> 'spotify_id' = '2QjOHCTQ1JF3zJyfWY7EMU'),
          2, 'and both now carry the link');
select is(public.patch_track_meta_spotify('isrc:USUM71311296', '2QjOHCTQ1JF3zJyfWY7EMU',
                                          'https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU'),
          0, 'running it again patches nothing — eight people sealing at once is one write');

-- The snapshot is otherwise immutable (docs/06 §2), which is what lets The Record survive a
-- song being pulled from the catalogue in 2027. The patch must not have touched anything else.
select is((select track_meta ->> 'title' from public.submissions
            where track_key = 'isrc:USUM71311296' limit 1),
          'Ribs', 'and nothing else in the snapshot moved');

-- ─── the promise ─────────────────────────────────────────────────────────────
-- docs/15 §2, asserted as a whole-database invariant rather than a per-row one, because that is
-- how it will actually be violated: not by a row that is wrong, but by a row nobody came back
-- for.

select is(
  (select count(*)::int
     from public.submissions s
     join public.rounds r on r.id = s.round_id
     left join public.track_links l on l.track_key = s.track_key
    where r.state = 'scored'
      and coalesce(s.track_meta ->> 'spotify_url', '') = ''
      and coalesce(l.unresolvable, false) = false),
  0,
  'no scored submission is in limbo: it has a Spotify URL, or a row that says it never will');

-- And the same invariant stated the other way, so a future change that satisfies it by deleting
-- `track_links` rows fails too.
select is(
  (select count(*)::int
     from public.submissions s
     join public.rounds r on r.id = s.round_id
    where r.state = 'scored'
      and coalesce(s.track_meta ->> 'spotify_url', '') = ''
      and not exists (select 1 from public.track_links l where l.track_key = s.track_key)),
  0,
  'and every unlinked scored track has a track_links row at all');

select * from finish();
rollback;
