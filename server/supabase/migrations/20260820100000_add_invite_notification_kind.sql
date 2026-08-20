-- 20260820100000_add_invite_notification_kind.sql — E20-03.
--
-- Kept separate from the migration that uses this value. PostgreSQL permits adding an enum
-- label inside a transaction but does not permit using the new label until that transaction
-- commits, so combining these two changes makes a fresh `supabase db reset` fail.

alter type public.notif_kind add value if not exists 'invite';
