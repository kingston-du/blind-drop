-- 20260815090500_demo_lifecycle.sql — the App Review demo environment, part 2 of 2.
--
-- 20260815090000 took demo groups out of the scheduler's hands. This gives them a lifecycle
-- of their own: one driven by the reviewer's actions rather than by the clock, so the whole
-- loop — drop, seal, reveal, guess, results — is reachable at 02:00 as readily as at 20:00.
--
-- Three rules shape everything below, and none of them is relaxed for the demo:
--
--   1. **The server still owns time** (CLAUDE.md §2.2). The transitions happen here, in SQL,
--      against `public.now_()`. The client does exactly what it does in production: renders a
--      countdown from `server_now`, refetches when it reaches zero, and draws whatever state
--      the server then reports. There is no client-side demo mode and no second code path in
--      the app — this ships without an iOS change.
--   2. **A demo round is still an ordinary row.** Every trigger in 0002 applies to it: state
--      moves forward only, `card_order` is a permutation of the round's submissions, a guess
--      belongs to somebody who submitted. The single thing 20260815090000 relaxes for it is
--      `rounds_window`, and only into "open before reveal, reveal before score".
--   3. **Nothing here can touch a real group.** Every function returns immediately unless
--      `groups.is_demo`, which is settable only from a server-only pilot cohort row.
--
-- What a demo round does *not* do: it never voids (the companions guarantee the count, and a
-- reviewer watching the app void is the exact failure this was built to prevent), and it never
-- writes to `notification_outbox` — the reviewer is holding the phone, and a push they cannot
-- see is noise.

-- ─── the companion roster ────────────────────────────────────────────────────
-- The fixture players a demo group needs in order to have a reveal at all. Server-only, like
-- `pilot_cohorts`: there is no API path to this table, and `demo_provision()` is the only
-- thing that writes it.
--
-- It exists so `demo_tick()` can tell a companion from the reviewer without inferring it from
-- membership role or signup order — the difference is a fact about the fixture, so it is
-- stored as one rather than guessed at.

create table public.demo_companions (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  group_id   uuid not null references public.groups(id) on delete cascade,
  position   int not null check (position > 0),
  created_at timestamptz not null default now(),
  unique (group_id, position)
);

alter table public.demo_companions enable row level security;
alter table public.demo_companions force row level security;

comment on table public.demo_companions is
  'Fixture players in a demo group, so demo_tick() can pre-seed their submissions and know '
  'that the only outstanding one is the reviewer''s. Server-only; written by demo_provision().';

revoke all on table public.demo_companions from public, anon, authenticated, service_role;

-- ─── demo_arm ────────────────────────────────────────────────────────────────
-- Bring the round's next transition `p_seconds` away. Which transition that is depends on
-- where the round already is, and each one moves only the timestamp the client is counting to:
--
--   · `open` → `reveals_at`. The seal countdown on `SealedScreen` counts to exactly this.
--     `opens_at` follows it down so the round is never "not open yet"; `scores_at` follows so
--     the guess window that comes next starts out looking like a normal one.
--   · `revealed` → `scores_at`, and **nothing else**. `reveals_at` is left exactly where it
--     was. That matters more than it looks: `cannotGuessReason()` (`rounds/index.ts`) compares
--     `reveals_at` against the caller's `joined_at`, so moving it after the reveal can tell a
--     reviewer who signed in this evening that they joined too late to guess.
--
-- A no-op on any round outside a demo group — the guard is the join below, not the caller's
-- good manners.

create or replace function public.demo_arm(p_round_id uuid, p_seconds int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state  public.round_state;
  v_target timestamptz;
begin
  select r.state into v_state
    from public.rounds r
    join public.groups g on g.id = r.group_id
   where r.id = p_round_id
     and g.is_demo;
  if not found then
    return;
  end if;

  v_target := public.now_() + pg_catalog.make_interval(secs => p_seconds);

  if v_state = 'open' then
    update public.rounds
       set reveals_at = v_target,
           opens_at   = v_target - interval '10 hours',
           scores_at  = v_target + interval '2 hours'
     where id = p_round_id;
  elsif v_state = 'revealed' then
    update public.rounds
       set scores_at = v_target
     where id = p_round_id;
  end if;
  -- A scored or voided round has no next transition to bring forward.
end $$;

comment on function public.demo_arm(uuid, int) is
  'Brings a demo round''s next transition p_seconds away — the reveal while it is open, the '
  'score once it is revealed. Never moves reveals_at after the reveal, which would misread as '
  'a late join. A no-op on any round outside a demo group.';

revoke all on function public.demo_arm(uuid, int) from public, anon, authenticated;
grant execute on function public.demo_arm(uuid, int) to service_role;

-- ─── the fixture catalogue ───────────────────────────────────────────────────
-- Real songs with real identifiers, so search results, artwork, links and the share card all
-- render as they would for a member. `preview_url` is null throughout: these rows are written
-- directly rather than resolved through Apple Music, and a fabricated preview URL that 404s
-- would look worse than none.

create or replace function public.demo_track(p_index int)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select (array[
    '{"track_key":"isrc:USQX91600321","isrc":"USQX91600321","title":"Nights","artist":"Frank Ocean","album":"Blonde","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440765580/{w}x{h}bb.jpg","artwork_bg_color":"2b2b2b","duration_ms":307000,"preview_url":null,"apple_music_id":"1440765580","apple_music_url":"https://music.apple.com/us/song/1440765580","spotify_id":"7eqoqGkKwgOaWNNHx90uEZ","spotify_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ"}',
    '{"track_key":"isrc:USQX91601480","isrc":"USQX91601480","title":"Redbone","artist":"Childish Gambino","album":"“Awaken, My Love!”","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1452874255/{w}x{h}bb.jpg","artwork_bg_color":"6b3a1f","duration_ms":326000,"preview_url":null,"apple_music_id":"1452874255","apple_music_url":"https://music.apple.com/us/song/1452874255","spotify_id":"0wXuerDYiBnERgIpbb3JBR","spotify_url":"https://open.spotify.com/track/0wXuerDYiBnERgIpbb3JBR"}',
    '{"track_key":"isrc:USQX91901234","isrc":"USQX91901234","title":"Bags","artist":"Clairo","album":"Immunity","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1468055107/{w}x{h}bb.jpg","artwork_bg_color":"93a7c4","duration_ms":258000,"preview_url":null,"apple_music_id":"1468055107","apple_music_url":"https://music.apple.com/us/song/1468055107","spotify_id":"3AwF0Ea5jUqLDWWDaXocxT","spotify_url":"https://open.spotify.com/track/3AwF0Ea5jUqLDWWDaXocxT"}',
    '{"track_key":"isrc:USDW11700831","isrc":"USDW11700831","title":"Motion Sickness","artist":"Phoebe Bridgers","album":"Stranger in the Alps","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440830827/{w}x{h}bb.jpg","artwork_bg_color":"3d4a52","duration_ms":239000,"preview_url":null,"apple_music_id":"1440830827","apple_music_url":"https://music.apple.com/us/song/1440830827","spotify_id":"0YSjKUbxJYuJ4Zk9CWjWLu","spotify_url":"https://open.spotify.com/track/0YSjKUbxJYuJ4Zk9CWjWLu"}',
    '{"track_key":"isrc:USUM71812409","isrc":"USUM71812409","title":"Sunflower","artist":"Post Malone & Swae Lee","album":"Spider-Man: Into the Spider-Verse","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1442571948/{w}x{h}bb.jpg","artwork_bg_color":"c46a2a","duration_ms":158000,"preview_url":null,"apple_music_id":"1442571948","apple_music_url":"https://music.apple.com/us/song/1442571948","spotify_id":"3KkXRkHbMCARz0aVfEt68P","spotify_url":"https://open.spotify.com/track/3KkXRkHbMCARz0aVfEt68P"}',
    '{"track_key":"isrc:USRC12204245","isrc":"USRC12204245","title":"Kill Bill","artist":"SZA","album":"SOS","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1656689279/{w}x{h}bb.jpg","artwork_bg_color":"1a1a2e","duration_ms":153000,"preview_url":null,"apple_music_id":"1656689279","apple_music_url":"https://music.apple.com/us/song/1656689279","spotify_id":"1Qrg8KqiBpW07V7PNxwwwL","spotify_url":"https://open.spotify.com/track/1Qrg8KqiBpW07V7PNxwwwL"}',
    '{"track_key":"isrc:USUM71311296","isrc":"USUM71311296","title":"Ribs","artist":"Lorde","album":"Pure Heroine","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440818664/{w}x{h}bb.jpg","artwork_bg_color":"1d2b3a","duration_ms":249000,"preview_url":null,"apple_music_id":"1440818664","apple_music_url":"https://music.apple.com/us/song/1440818664","spotify_id":"2QjOHCTQ1JF3zJyfWY7EMU","spotify_url":"https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"}',
    '{"track_key":"isrc:GBAHT1600302","isrc":"GBAHT1600302","title":"Green Light","artist":"Lorde","album":"Melodrama","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1440871009/{w}x{h}bb.jpg","artwork_bg_color":"3b2f6b","duration_ms":234000,"preview_url":null,"apple_music_id":"1440871009","apple_music_url":"https://music.apple.com/us/song/1440871009","spotify_id":"6ie2Bw3xLj2JcGowOlcMhb","spotify_url":"https://open.spotify.com/track/6ie2Bw3xLj2JcGowOlcMhb"}',
    '{"track_key":"isrc:USAT21902956","isrc":"USAT21902956","title":"Cellophane","artist":"FKA twigs","album":"MAGDALENE","artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/fixture/1479305371/{w}x{h}bb.jpg","artwork_bg_color":"5a2b3a","duration_ms":195000,"preview_url":null,"apple_music_id":"1479305371","apple_music_url":"https://music.apple.com/us/song/1479305371","spotify_id":"1CQ2sGCLNVjMIhFbHzkeVW","spotify_url":"https://open.spotify.com/track/1CQ2sGCLNVjMIhFbHzkeVW"}'
  ])[1 + (p_index % 9)]::jsonb
$$;

comment on function public.demo_track(int) is
  'Fixture track_meta by index, wrapping at nine. Real identifiers so artwork, links and the '
  'share card render exactly as they would for a member (docs/06 §2).';

revoke all on function public.demo_track(int) from public, anon, authenticated;

-- ─── demo_seed_companion_submissions ─────────────────────────────────────────
-- Every companion drops a song into the round. Called at roll time, so the only submission
-- outstanding when the reviewer opens the app is the reviewer's own — which is what makes
-- "the room is complete" a usable reveal trigger in `demo_tick()`.
--
-- `p_offset` rotates the catalogue so two rounds do not hold the same songs; The Record wants
-- nine nights that look like nine nights.

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
    v_meta := public.demo_track(p_offset * 3 + v_c.position);
    insert into public.submissions (round_id, user_id, track_key, track_meta)
    values (p_round_id, v_c.user_id, v_meta ->> 'track_key', v_meta)
    on conflict (round_id, user_id) do nothing;
  end loop;
end $$;

revoke all on function public.demo_seed_companion_submissions(uuid, int)
  from public, anon, authenticated;

-- ─── demo_next_reveal ────────────────────────────────────────────────────────
-- The next `reveal_hour`:00 group-local strictly after `p_now`, as a UTC instant. Same
-- spelling as `ensure_rounds()`: the date is resolved through the zone and the hour is added
-- to the local date before converting back, so the offset used is the one in force on the day
-- rather than a stored one (docs/02 §1).

create or replace function public.demo_next_reveal(p_tz text, p_hour int, p_now timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select min(t.at)
    from (
      select pg_catalog.timezone(
               p_tz,
               (pg_catalog.timezone(p_tz, p_now)::date + d)
                 + pg_catalog.make_interval(hours => p_hour)) as at
        from pg_catalog.generate_series(0, 1) as d
    ) t
   where t.at > p_now
$$;

revoke all on function public.demo_next_reveal(text, int, timestamptz)
  from public, anon, authenticated;

-- ─── demo_tick ───────────────────────────────────────────────────────────────
-- The whole state machine, called by `GET /rounds/current` before it looks the round up.
-- Score, then reveal, then roll — the same reveal-before-score ordering discipline as
-- `tick_rounds()`, for the same reason: one call must be able to advance a round more than one
-- step when the reviewer has been away, rather than leaving them a stale screen.
--
-- The reveal trigger is **"every member has submitted, and the countdown has run out"**. The
-- companions are seeded at roll, so the only outstanding submission is the reviewer's, and
-- `demo_arm(round, 12)` on their submit is what makes `reveals_at` due twelve seconds later.
-- A reviewer who never drops a song is never revealed past: the round's real 20:00 arrives,
-- the room is not complete, and the window slides to the next one. They keep seeing an honest
-- wait, which is the correct thing to show someone who has not played.

create or replace function public.demo_tick(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz        text;
  v_hour      int;
  v_now       timestamptz;
  v_today     date;
  v_round     record;
  v_order     uuid[];
  v_reveals   timestamptz;
  v_finished  uuid;
  v_carry     uuid;
  v_date      date;
  v_rounds    int;
begin
  select g.timezone, g.reveal_hour into v_tz, v_hour
    from public.groups g
   where g.id = p_group_id and g.is_demo;
  if not found then
    return;
  end if;

  -- Per group, not global: two concurrent reads from the same device must not both roll.
  perform pg_advisory_xact_lock(
    hashtextextended('blind-drop-demo-tick:' || p_group_id::text, 0));

  v_now   := public.now_();
  v_today := pg_catalog.timezone(v_tz, v_now)::date;

  -- ── 1. score ───────────────────────────────────────────────────────────────
  update public.rounds
     set state = 'scored'
   where group_id = p_group_id
     and state = 'revealed'
     and scores_at <= v_now;

  -- ── 2. reveal ──────────────────────────────────────────────────────────────
  for v_round in
    select r.id
      from public.rounds r
     where r.group_id = p_group_id
       and r.state = 'open'
       and r.reveals_at <= v_now
     order by r.reveals_at, r.id
     for update
  loop
    if exists (
      select 1
        from public.memberships m
       where m.group_id = p_group_id
         and m.left_at is null
         and not exists (
           select 1 from public.submissions s
            where s.round_id = v_round.id and s.user_id = m.user_id
         )
    ) then
      -- The room is incomplete: this is the real 20:00 arriving on a round nobody played,
      -- not an armed reveal. Slide to the next one rather than revealing a partial round or
      -- voiding — a demo round never voids.
      v_reveals := public.demo_next_reveal(v_tz, v_hour, v_now);
      update public.rounds
         set reveals_at = v_reveals,
             opens_at   = v_reveals - interval '10 hours',
             scores_at  = v_reveals + interval '2 hours'
       where id = v_round.id;
    else
      v_order := public.shuffle_submissions(v_round.id);
      update public.rounds
         set state = 'revealed',
             card_order = pg_catalog.to_jsonb(v_order)
       where id = v_round.id
         and state = 'open';
    end if;
  end loop;

  -- ── 3. roll ────────────────────────────────────────────────────────────────
  -- Either there is no round for today at all — the reviewer's first visit, or their first
  -- visit on a later day — or today's round finished at least two minutes ago and they are
  -- ready to go around again. The two-minute settle keeps a results screen from being pulled
  -- out from under someone who is still reading it.
  if not exists (
    select 1 from public.rounds r
     where r.group_id = p_group_id and r.local_date = v_today
  ) then
    -- Midnight arrived while a round was still unplayed. That round is not history and it is
    -- not spent — it is the round this reviewer is in the middle of — so it moves to today
    -- rather than being abandoned there and replaced. Without this, a session that straddles
    -- local midnight would strand an open round that `demo_tick()` then re-anchors nightly
    -- for ever, and lose the companion submissions already in it.
    select r.id into v_carry
      from public.rounds r
     where r.group_id = p_group_id
       and r.state in ('open', 'revealed')
       and r.local_date < v_today
     order by r.local_date desc
     limit 1;

    if v_carry is not null then
      update public.rounds set local_date = v_today where id = v_carry;
      return;
    end if;
  end if;

  select r.id into v_finished
    from public.rounds r
   where r.group_id = p_group_id
     and r.local_date = v_today
     and (
       (r.state = 'scored' and r.scores_at <= v_now - interval '2 minutes')
       or r.state = 'voided'
     );

  if v_finished is null and exists (
    select 1 from public.rounds r
     where r.group_id = p_group_id and r.local_date = v_today
  ) then
    return;   -- today's round is live; nothing to roll
  end if;

  -- Make room at today's date. Every earlier round shifts back one day, oldest first so each
  -- move lands on a date the row below has just vacated and `rounds_group_date` is never
  -- violated; the finished round then takes yesterday. The Record reads newest-first, so this
  -- keeps the finished night at the top of it rather than burying it under the fixtures.
  if v_finished is not null then
    for v_date in
      select r.local_date
        from public.rounds r
       where r.group_id = p_group_id and r.local_date < v_today
       order by r.local_date
    loop
      update public.rounds
         set local_date = v_date - 1
       where group_id = p_group_id and local_date = v_date;
    end loop;

    update public.rounds set local_date = v_today - 1 where id = v_finished;
  end if;

  select count(*)::int into v_rounds
    from public.rounds r where r.group_id = p_group_id;

  v_reveals := public.demo_next_reveal(v_tz, v_hour, v_now);
  insert into public.rounds (group_id, local_date, state, opens_at, reveals_at, scores_at)
  values (p_group_id, v_today, 'open',
          v_reveals - interval '10 hours', v_reveals, v_reveals + interval '2 hours')
  on conflict (group_id, local_date) do nothing;

  perform public.demo_seed_companion_submissions(
    (select r.id from public.rounds r
      where r.group_id = p_group_id and r.local_date = v_today),
    v_rounds);
end $$;

comment on function public.demo_tick(uuid) is
  'Advances a demo group''s round: scores a revealed round whose window has run out, reveals '
  'an open one once every member has submitted, and rolls a fresh round two minutes after the '
  'last one scored. Never voids and never writes notification_outbox. A no-op on any group '
  'that is not a demo group.';

revoke all on function public.demo_tick(uuid) from public, anon, authenticated;
grant execute on function public.demo_tick(uuid) to service_role;

-- ─── demo_provision ──────────────────────────────────────────────────────────
-- Everything a demo group needs before a reviewer opens the app, in one idempotent call:
-- the reviewer's display name, three companions, three finished nights so The Record,
-- standings, results and the share card all have real content, and one live open round.
--
-- Deliberately **not** granted to `service_role`. Provisioning is an owner action run through
-- `server/scripts/seed-app-review-demo.sql`; no API path should be able to manufacture
-- players or backdated rounds, demo group or not.
--
-- Replaces the hand-written script that used to do this. That one had to be re-run within
-- about two hours of the reviewer opening the app, because it faked a `revealed` round
-- anchored to `now()` and hosted cron swept it into `scored` on the next tick. Nothing here
-- decays: the loop is driven by `demo_tick()` on the reviewer's own actions, so re-running is
-- a convenience rather than a deadline.

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
  v_names     constant text[] := array['Kai', 'Mo', 'Nell'];
  v_companions constant uuid[] := array[
    'f0000000-0000-4000-8000-0000000000a1'::uuid,
    'f0000000-0000-4000-8000-0000000000a2'::uuid,
    'f0000000-0000-4000-8000-0000000000a3'::uuid];
  v_members   uuid[];
  v_subs      uuid[];
  v_round     uuid;
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
  -- (see server/supabase/seed.sql). These three never sign in, but the row shape is kept
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
    v_subs := array[gen_random_uuid(), gen_random_uuid(),
                    gen_random_uuid(), gen_random_uuid()];

    insert into public.rounds
           (id, group_id, local_date, state, opens_at, reveals_at, scores_at, card_order)
    values (v_round, p_group_id, v_date, 'scored',
            v_reveals - interval '10 hours', v_reveals, v_reveals + interval '2 hours',
            pg_catalog.to_jsonb(array[
              v_subs[1 + (v_k % 4)], v_subs[1 + ((v_k + 1) % 4)],
              v_subs[1 + ((v_k + 2) % 4)], v_subs[1 + ((v_k + 3) % 4)]]));

    for v_i in 1..4 loop
      v_meta := public.demo_track(v_k * 4 + v_i);
      insert into public.submissions (id, round_id, user_id, track_key, track_meta, created_at)
      values (v_subs[v_i], v_round, v_members[v_i], v_meta ->> 'track_key', v_meta,
              v_reveals - pg_catalog.make_interval(hours => v_i));
    end loop;

    -- Everyone guesses every card but their own, right about two nights in three. A clean
    -- sweep or a blank sheet would make the results screen and the standings look broken.
    for v_i in 1..4 loop
      for v_j in 1..4 loop
        continue when v_i = v_j;
        if ((v_i + v_j + v_k) % 3) <> 0 then
          v_guessed := v_members[v_j];
        else
          v_guessed := v_members[1 + (v_j % 4)];
          if v_guessed = v_members[v_i] then
            v_guessed := v_members[1 + ((v_j + 1) % 4)];
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
  'three companions, writes three finished nights of archive, and opens tonight''s round. '
  'Idempotent. Owner-run only — deliberately not granted to service_role.';

revoke all on function public.demo_provision(uuid) from public, anon, authenticated, service_role;
