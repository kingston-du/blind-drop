-- 20260826120000_add_conditional_reminder_kinds.sql — E31-01, docs/05 §3, docs/17 §5.
--
-- Kept separate from the migration that uses these values, same reason
-- `20260820100000_add_invite_notification_kind.sql` is separate from the migration that used
-- `invite`: PostgreSQL permits adding an enum label inside a transaction but does not permit
-- using the new label until that transaction commits, so combining these two changes makes a
-- fresh `supabase db reset` fail.
--
-- `nudge` is not removed — Postgres has no `ALTER TYPE ... DROP VALUE`, and recreating the type
-- to drop a label would mean rewriting every column, index, and function signature that
-- reference it. The label stays in place, permanently unused; `tick_rounds()` stops producing
-- it as of the next migration, and that is the retirement.

alter type public.notif_kind add value if not exists 'seal_reminder';
alter type public.notif_kind add value if not exists 'guess_reminder';
