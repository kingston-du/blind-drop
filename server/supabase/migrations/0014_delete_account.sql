-- 0014_delete_account.sql — tasks/E02-05, docs/03 §6, docs/14 §9.
--
-- A profile id begins life as the matching auth.users id, but it must outlive that auth row:
-- submissions and guesses use it as their stable historical principal. The original cascade
-- made those requirements mutually exclusive, so account deletion first turns the profile
-- into a tombstone and then removes the authentication principal.

alter table public.profiles drop constraint profiles_id_fkey;

comment on column public.profiles.id is
  'Stable game principal. Matches auth.users.id for a live account; survives as a Former '
  'member tombstone after account deletion so historical submissions and guesses remain.';

create or replace function public.delete_account(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := public.now_();
begin
  -- A user may delete during onboarding before a profile exists, so each cleanup is allowed
  -- to affect zero rows. For an established account, the profile remains as the stable
  -- historical identity referenced by submissions, guesses, memberships, and groups.
  update public.profiles
     set display_name = 'Former member',
         updated_at = v_now
   where id = p_user;

  update public.memberships
     set left_at = v_now
   where user_id = p_user
     and left_at is null;

  -- Device tokens and short-lived abuse-control rows have no historical value and are not
  -- retained after deletion.
  delete from public.devices where user_id = p_user;
  delete from public.rate_limit_events
   where bucket like '%:u:' || p_user::text;

  -- Frozen notification audiences are operational data, not score history. Remove the id
  -- from sent and unsent rows; with no devices it could not be delivered anyway.
  update public.notification_outbox
     set audience = audience - p_user::text
   where audience ? p_user::text;

  -- GoTrue's dependent identities, sessions, factors, and tokens cascade from auth.users.
  -- Once this row is gone, even an otherwise-unexpired access token fails getUser().
  delete from auth.users where id = p_user;
end $$;

comment on function public.delete_account(uuid) is
  'Deletes authentication and non-historical device data while retaining an anonymised '
  'profile principal, submissions, guesses, and past attribution as Former member.';

revoke all on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;
