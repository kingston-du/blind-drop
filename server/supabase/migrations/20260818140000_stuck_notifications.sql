-- 20260818140000_stuck_notifications.sql — E23-01, docs/05 §1, §6.
--
-- Diagnosis (tasks/E23-notifications.md has the full writeup, with evidence):
--
--   1. `app.functions_url` / `app.service_key` are never set by any migration, `config.toml`,
--      or `seed.sql` — confirmed locally: `select current_setting('app.functions_url');`
--      raises `42704 unrecognized configuration parameter` against a freshly-migrated
--      database, this one included. When the `push` cron job runs `net.http_post(url :=
--      current_setting('app.functions_url') || …)`, it hits the same error before it ever
--      builds a request. pg_cron records that as a failed run in `cron.job_run_details` — a
--      table nothing in this app queries — and the outbox is left looking exactly like a
--      worker with nothing to send.
--   2. There is no deploy step anywhere in this repo (`.github/workflows/ci.yml` starts the
--      *local* stack and stops there) and `docs/APP-REVIEW-NOTES.md` §2, the one place that
--      records what has actually been pushed to the hosted project, does not mention
--      `push-worker` at all. Whether it is deployed, and whether `supabase secrets set` has
--      ever been run for the `APNS_*` names, is not answerable from the repo. This migration
--      cannot answer it either — it needs the owner and the hosted project.
--
-- This migration does not (and, being a forward migration committed to git, must not) set the
-- two GUCs itself — 0016_cron.sql's own tests already assert no host or key literal ever lands
-- in `cron.job`, and a settings value is exactly that. Setting them is now a documented,
-- one-time operator step (docs/05 §1). What this migration adds is a way to see the symptom
-- regardless of which suspect (or a third, unnamed one) turns out to be the cause: any outbox
-- row that has sat unsent well past the round's own accuracy target is stuck, whatever the
-- reason, and up to now nobody would notice without thinking to query for it.

create or replace function public.stuck_notifications(p_after interval default interval '5 minutes')
returns table (
  id          uuid,
  round_id    uuid,
  kind        public.notif_kind,
  attempts    int,
  last_error  text,
  enqueued_at timestamptz,
  claimed_at  timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select o.id, o.round_id, o.kind, o.attempts, o.last_error, o.enqueued_at, o.claimed_at
    from public.notification_outbox o
   where o.sent_at is null
     and o.enqueued_at <= public.now_() - p_after
   order by o.enqueued_at;
$$;

comment on function public.stuck_notifications(interval) is
  'docs/05 §6 — outbox rows unsent past the reveal-accuracy target (default 5 minutes; the '
  'target itself is 60s, docs/01 §6). A non-empty result means the push path is broken, '
  'whatever the cause: unset app.functions_url/app.service_key (docs/05 §1), an undeployed '
  'push-worker, missing APNs secrets, or APNs itself being down. `select '
  'public.stuck_notifications();` from the SQL editor, or a periodic check against it, is the '
  'query a person would actually run — nothing surfaced this before.';

-- Same posture as claim/finish/release_notification_outbox: an operational tool, not a client
-- endpoint. PostgREST is off-limits to the client anyway (docs/01 §2), but this keeps the
-- table's own deny-by-default (0006_notifications.sql) from having a silent exception.
revoke all on function public.stuck_notifications(interval) from public, anon, authenticated;
grant execute on function public.stuck_notifications(interval) to service_role;
