-- 0018_submission_upsert.sql — docs/04 §4, docs/02 §3. tasks/E04-01.
--
-- `PUT /rounds/current/submission` has two requirements that look contradictory until you say
-- them precisely. docs/04 §4:
--
--   · "Replacement is a plain upsert. `created_at` is preserved, `updated_at` moves."
--   · "Idempotent: the same body twice produces one row and the same response."
--
-- They are both true because a *replacement* and a *repeat* are different events. Sealing
-- *Ribs* when *Ribs* is already sealed has not replaced anything, so `updated_at` — which the
-- API returns as `sealed_at`, the moment the currently-sealed thing was sealed — must not
-- move. Sealing *Nights* over *Ribs* has, so it must.
--
-- The test is `track_key`, not `track_meta`. Two reasons:
--
--   · `track_meta` legitimately changes without the song changing: `spotify_id` may arrive on
--     a later attempt (0017), and a retry after Spotify timed out would otherwise register as
--     a replacement and move the seal.
--   · `track_key` is already the game's identity for a track (docs/06 §3). If two inputs
--     produce the same key they are the same recording, which is exactly the question being
--     asked here.
--
-- Expressing this in PostgREST's upsert is not possible — its `merge-duplicates` writes every
-- column in the payload unconditionally — so it is a function, which also lets the timestamp
-- come from `public.now_()` and be movable by the pgTAP suite (tasks/E01-05).

create or replace function public.upsert_submission(
  p_round_id   uuid,
  p_user_id    uuid,
  p_track_key  text,
  p_track_meta jsonb
) returns table (track_meta jsonb, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  insert into public.submissions as s (round_id, user_id, track_key, track_meta,
                                       created_at, updated_at)
  values (p_round_id, p_user_id, p_track_key, p_track_meta,
          public.now_(), public.now_())
  on conflict (round_id, user_id) do update
    set track_key  = excluded.track_key,
        track_meta = excluded.track_meta,
        -- created_at is absent on purpose: the day you first sealed something in this round
        -- is not changed by changing your mind (docs/04 §4).
        updated_at = case
                       when s.track_key is distinct from excluded.track_key
                       then public.now_()
                       else s.updated_at
                     end
  returning s.track_meta, s.updated_at;
end $$;

comment on function public.upsert_submission(uuid, uuid, text, jsonb) is
  'Drop or replace a song. Preserves created_at always, and preserves updated_at when the '
  'track_key is unchanged so that a repeated request is genuinely idempotent — docs/04 §4.';

-- Nothing about this function decides *whether* the caller may submit. The round''s phase, the
-- caller''s membership and the rate limit are all checked by the handler before it is reached
-- (docs/14 §4): RLS and this grant are the second lock, not the only one.
revoke all on function public.upsert_submission(uuid, uuid, text, jsonb) from public;
grant execute on function public.upsert_submission(uuid, uuid, text, jsonb) to service_role;
