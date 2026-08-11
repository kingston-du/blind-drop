-- 20260811194721_claim_notifications.sql — atomic, leased outbox claims. tasks/E06-02.
--
-- An Edge Function cannot hold a PostgREST transaction open while it talks to APNs. The
-- short database transaction therefore claims work with SKIP LOCKED and leaves a one-minute
-- lease behind. A crashed worker's row becomes eligible on the following cron pass; a live
-- overlapping worker sees the lease and claims a different row.

alter table public.notification_outbox
  add column claimed_at timestamptz,
  add column claim_id uuid,
  add constraint notification_outbox_claim_pair
    check ((claimed_at is null) = (claim_id is null));

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
           claim_id = p_claim_id,
           last_error = null
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

create or replace function public.finish_notification_outbox(
  p_id uuid,
  p_claim_id uuid
)
returns boolean
language sql
volatile
strict
security invoker
set search_path = ''
as $$
  with finished as (
    update public.notification_outbox o
       set sent_at = statement_timestamp(),
           claimed_at = null,
           claim_id = null,
           last_error = null
     where o.id = p_id
       and o.claim_id = p_claim_id
       and o.sent_at is null
    returning true
  )
  select coalesce((select true from finished), false);
$$;

create or replace function public.release_notification_outbox(
  p_id uuid,
  p_claim_id uuid
)
returns boolean
language sql
volatile
strict
security invoker
set search_path = ''
as $$
  with released as (
    update public.notification_outbox o
       set claimed_at = null,
           claim_id = null
     where o.id = p_id
       and o.claim_id = p_claim_id
       and o.sent_at is null
    returning true
  )
  select coalesce((select true from released), false);
$$;

revoke all on function public.claim_notification_outbox(uuid, int) from public, anon, authenticated;
revoke all on function public.finish_notification_outbox(uuid, uuid) from public, anon, authenticated;
revoke all on function public.release_notification_outbox(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
grant execute on function public.finish_notification_outbox(uuid, uuid) to service_role;
grant execute on function public.release_notification_outbox(uuid, uuid) to service_role;
