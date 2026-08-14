-- Sign out detaches the caller's current APNs token through DELETE /devices.
--
-- Keep the grant at the table-and-verb minimum: the Edge Function still constrains the
-- deletion by both authenticated user_id and the exact token, while every other table keeps
-- the hardened allowlist from 20260814180926 unchanged.

grant delete on public.devices to service_role;
