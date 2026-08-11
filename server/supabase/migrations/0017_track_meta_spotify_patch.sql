-- 0017_track_meta_spotify_patch.sql — docs/06 §2, §5. tasks/E07-04.
--
-- `submissions.track_meta` is a denormalised snapshot written once at submission time and
-- never rewritten. That is deliberate and it is what makes The Record survive catalogue
-- churn: a song pulled from Apple Music in 2027 still shows its title, artist and artwork URL
-- in the 2026 archive (docs/06 §2).
--
-- `spotify_id` and `spotify_url` are the one documented exception. They may arrive later —
-- inline at submission if Spotify answers inside 700ms, otherwise from the backfill (docs/06
-- §5) — and when they do, every submission already carrying that `track_key` should gain the
-- link, not just the one being written now.
--
-- Doing that as a `jsonb ||` merge of exactly two keys, in SQL, is the point of this function.
-- A read-modify-write in the Edge Function would have to send the whole snapshot back, which
-- is both a lost-update race between two members sealing the same song at once and a standing
-- invitation to rewrite a field that is supposed to be immutable. Here, `track_meta` can lose
-- nothing: the only reachable change is those two keys.

create or replace function public.patch_track_meta_spotify(
  p_track_key   text,
  p_spotify_id  text,
  p_spotify_url text
) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare v_patched int;
begin
  if p_track_key is null or p_spotify_id is null or p_spotify_url is null then
    return 0;
  end if;

  update public.submissions
     set track_meta = track_meta || jsonb_build_object(
           'spotify_id',  p_spotify_id,
           'spotify_url', p_spotify_url)
   where track_key = p_track_key
     -- Only rows that do not already have it. Eight people can be dropping the same song in
     -- the same minute; without this, each of their lookups rewrites all eight rows.
     and coalesce(track_meta ->> 'spotify_id', '') <> p_spotify_id;

  get diagnostics v_patched = row_count;
  return v_patched;
end $$;

comment on function public.patch_track_meta_spotify(text, text, text) is
  'Backfills spotify_id/spotify_url into every submission snapshot sharing a track_key. '
  'The only sanctioned mutation of track_meta after write — docs/06 §2, §5.';

-- The statement above deliberately leaves `updated_at` alone. There is no `updated_at`
-- trigger anywhere in this schema — every writer sets it explicitly — so a backfill landing
-- on somebody else's submission cannot move the `sealed_at` they see on their sealed card
-- (docs/04 §4). If a generic touch-`updated_at` trigger is ever added to `submissions`, this
-- function needs a `set updated_at = updated_at` to stay honest.
revoke all on function public.patch_track_meta_spotify(text, text, text) from public;
grant execute on function public.patch_track_meta_spotify(text, text, text) to service_role;
