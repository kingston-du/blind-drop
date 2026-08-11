-- 20260811201246_notification_retry.sql — the retry ceiling. tasks/E06-04, docs/05 §6.
--
-- 20260811194721 gave the outbox an atomic claim and a lease, which is what makes a crashed
-- worker's row eligible again on the next minute. What it did not give it is a stopping
-- condition. A row whose APNs send fails for a reason that will never stop failing — a topic
-- that does not match the key, a malformed payload — would otherwise be claimed, attempted and
-- released once a minute forever, and the only trace of why would be a log line that has
-- already rotated away.
--
-- Two changes, both from docs/05 §6:
--
--   1. `attempts >= 5` is no longer claimable. Five tries over five minutes is well past the
--      point where a transient failure has recovered, and a reveal push is worthless after
--      `scores_at` anyway.
--   2. `last_error` survives. The claim used to null it, which meant the field was empty
--      exactly when someone came looking — the row had stopped and nobody could say why. It is
--      now written by `release_notification_outbox` and cleared only by a successful send.

-- Five attempts, and then a human looks at it. Mirrored by PUSH_MAX_ATTEMPTS in
-- functions/push-worker/worker.ts, which uses it only to decide whether to log loudly; this
-- guard is the one that actually stops the retry.
create or replace function public.claim_notification_outbox(
  p_claim_id uuid,
  p_limit int default 20
)
returns table (
  id uuid,
  round_id uuid,
  kind public.notif_kind,
  audience jsonb,
  attempts int,
  reveals_at timestamptz,
  scores_at timestamptz
)
language sql
volatile
strict
security invoker
set search_path = ''
as $$
  with due as materialized (
    select o.id
      from public.notification_outbox o
     where o.sent_at is null
       and o.attempts < 5
       and (
         o.claimed_at is null
         or o.claimed_at <= statement_timestamp() - interval '55 seconds'
       )
     order by o.enqueued_at, o.id
     limit least(greatest(p_limit, 1), 20)
       for update skip locked
  ), claimed as (
    update public.notification_outbox o
       set attempts = o.attempts + 1,
           claimed_at = statement_timestamp(),
           claim_id = p_claim_id
      from due
     where o.id = due.id
    returning o.id, o.round_id, o.kind, o.audience, o.attempts
  )
  select c.id, c.round_id, c.kind, c.audience, c.attempts,
         r.reveals_at, r.scores_at
    from claimed c
    join public.rounds r on r.id = c.round_id
   order by c.id;
$$;

-- The two-argument form is dropped rather than left beside the new one: a default on the third
-- parameter would make `release_notification_outbox(uuid, uuid)` ambiguous, and PostgREST would
-- start refusing the call the worker has always made.
drop function if exists public.release_notification_outbox(uuid, uuid);

create or replace function public.release_notification_outbox(
  p_id uuid,
  p_claim_id uuid,
  p_error text default null
)
returns boolean
language sql
volatile
-- Not `strict`, unlike its siblings: a strict function returns null without running when any
-- argument is null, and `p_error` is null on the ordinary path. Strictness here would mean a
-- released row silently staying claimed for its full 55-second lease.
security invoker
set search_path = ''
as $$
  with released as (
    update public.notification_outbox o
       set claimed_at = null,
           claim_id = null,
           -- Truncated because this is an operator's breadcrumb, not a log sink, and an
           -- upstream that answers with a page of HTML should not become a page of a row.
           last_error = pg_catalog.left(p_error, 500)
     where o.id = p_id
       and o.claim_id = p_claim_id
       and o.sent_at is null
    returning true
  )
  -- `coalesce` is a SQL construct rather than a schema-resolved function, so it needs no
  -- qualification under `search_path = ''` — the same reason `least`/`greatest` are bare above.
  select coalesce((select true from released), false);
$$;

revoke all on function public.release_notification_outbox(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.release_notification_outbox(uuid, uuid, text) to service_role;
