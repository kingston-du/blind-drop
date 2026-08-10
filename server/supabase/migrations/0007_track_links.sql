-- 0007_track_links.sql — docs/03 §2, docs/06 §5

-- Cross-service identity cache. Keyed by track_key so a lookup is done once per
-- distinct track for the lifetime of the app, not once per submission.
create table public.track_links (
  track_key        text primary key,
  isrc             text,
  apple_music_id   text,
  apple_music_url  text,
  spotify_id       text,
  spotify_url      text,
  resolved_at      timestamptz,        -- last successful spotify lookup
  resolve_attempts int not null default 0,
  unresolvable     boolean not null default false   -- give up after 3 misses
);
create index track_links_needs_resolve on public.track_links (resolve_attempts)
  where spotify_id is null and unresolvable = false;

-- Same lockdown as every other table. See 0003_rls.sql — this table is created after it.
alter table public.track_links enable row level security;
alter table public.track_links force row level security;
revoke all on public.track_links from anon, authenticated;
