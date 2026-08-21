-- The demo trigger helpers were added after the hosted privilege-hardening migration. PostgreSQL
-- grants EXECUTE on a new function to PUBLIC unless told otherwise, so the hosted project made
-- these SECURITY DEFINER helpers directly callable even though they exist only as trigger
-- implementations. Triggers do not require the invoking role to hold EXECUTE on their function.

revoke execute on function public.rounds_inherit_is_demo()
  from public, anon, authenticated, service_role;
revoke execute on function public.groups_propagate_is_demo()
  from public, anon, authenticated, service_role;
