-- Keep the Edge Function database role least-privileged on hosted projects.
--
-- The initial hosted bootstrap was applied while the project still had Supabase's legacy
-- service-role auto-grants. That gave service_role ALL on every public relation and made the
-- explicit verb-by-verb grants in 0010 ineffective in production. Revoke the platform defaults
-- and rebuild the same allowlist the application is tested against locally.

alter default privileges for role postgres in schema public
  revoke all on tables from service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from service_role;

revoke all on all tables in schema public from service_role;
revoke all on all sequences in schema public from service_role;
revoke all on all functions in schema public from service_role;

-- Identity and membership.
grant select, insert, update on public.profiles to service_role;
grant select, insert, update on public.groups to service_role;
grant select, insert, update on public.memberships to service_role;

-- Rounds and scoring. The API may read rounds but only the scheduler may create or advance them.
grant select on public.rounds to service_role;
grant select, insert, update on public.submissions to service_role;
grant select, insert, update, delete on public.guesses to service_role;
grant select on public.round_submitter_counts to service_role;
grant select on public.guess_results to service_role;
grant select on public.round_scores to service_role;
grant select on public.standings to service_role;

-- Operational tables.
grant select, insert, update on public.devices to service_role;
grant select, update on public.notification_outbox to service_role;
grant select, insert, update on public.track_links to service_role;
grant select, insert, delete on public.rate_limit_events to service_role;
grant usage on sequence public.rate_limit_events_id_seq to service_role;
grant select, insert, update, delete on public.pilot_cohorts to service_role;

-- RPC allowlist. Trigger helpers and the scheduler toggle intentionally stay unreachable.
grant execute on function public.now_() to service_role;
grant execute on function public.ensure_rounds() to service_role;
grant execute on function public.tick_rounds() to service_role;
grant execute on function public.timezone_is_valid(text) to service_role;
grant execute on function public.create_group(uuid, text, text, int, text) to service_role;
grant execute on function public.consume_rate_limit(text, int, interval) to service_role;
grant execute on function public.delete_account(uuid) to service_role;
grant execute on function public.patch_track_meta_spotify(text, text, text) to service_role;
grant execute on function public.upsert_submission(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
grant execute on function public.finish_notification_outbox(uuid, uuid) to service_role;
grant execute on function public.release_notification_outbox(uuid, uuid, text) to service_role;
grant execute on function public.assign_pilot_cohort(uuid) to service_role;
