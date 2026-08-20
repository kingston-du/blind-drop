-- 20260820100100_invitation_notifications.sql — E20-03, docs/05 §2–3.
--
-- A direct invitation is the first notification not owned by a round. It uses the established
-- outbox and worker rather than opening a second push path, but keeps a real invitation id so
-- a tap can be authorised against the recipient's own pending invitations before any details
-- render. An invitation can be created from any group; the recipient's budget is therefore
-- always checked across every existing outbox audience, not just the inviting group.

alter table public.notification_outbox
  alter column round_id drop not null,
  add column invitation_id uuid references public.invitations(id) on delete cascade;

alter table public.notification_outbox
  add constraint notification_outbox_source check (
    (
      kind = 'invite'
      and round_id is null
      and invitation_id is not null
      and coalesce(
        pg_catalog.jsonb_typeof(audience) = 'array'
        and pg_catalog.jsonb_array_length(audience) = 1,
        false
      )
    )
    or (
      kind <> 'invite'
      and round_id is not null
      and invitation_id is null
    )
  );

-- The round+kind unique key remains the idempotency key for scheduled notifications. A direct
-- invitation has no round, so it receives its own key instead. It is intentionally partial:
-- several invitation rows may coalesce into one notification and therefore do not all have an
-- outbox row of their own.
create unique index notification_outbox_invitation_once
  on public.notification_outbox (invitation_id)
  where invitation_id is not null;

create index notification_outbox_pending_invites
  on public.notification_outbox (enqueued_at)
  where kind = 'invite' and sent_at is null;

-- Serialise only one recipient's decision at a time. Without this lock, two invite requests
-- arriving together can both observe no unsent invitation row and both enqueue a push before
-- either commits. The lock is transaction-scoped, so a failed invitation releases it naturally.
create or replace function public.enqueue_invitation_notification(
  p_invitation uuid,
  p_user uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := public.now_();
  v_deliveries int;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text, 2_003)
  );

  -- The function is not an endpoint, but keep its caller honest: only a pending invitation
  -- actually addressed to this person is allowed to create an invite alert.
  if not exists (
    select 1
      from public.invitations i
     where i.id = p_invitation
       and i.invited_user = p_user
       and i.status = 'pending'
       and i.expires_at > v_now
  ) then
    raise exception 'invitation is not pending for this user' using errcode = 'BD004';
  end if;

  -- One unprocessed invite row is the coalescing bucket. A person invited to several circles
  -- before the worker runs receives one prompt, whose link opens the first pending invitation;
  -- the switcher contains the rest. Once that prompt has been sent, a later invitation can use
  -- another of the day's delivery slots.
  if exists (
    select 1
      from public.notification_outbox o
     where o.kind = 'invite'
       and o.sent_at is null
       and o.audience ? p_user::text
  ) then
    return false;
  end if;

  -- The outbox is the delivery source of truth: rows are audience-frozen and the worker sends
  -- each row once to every active device. Count it in the same rolling, half-open 24-hour window
  -- that the original notification-budget test proves for round notifications.
  select count(*)::int
    into v_deliveries
    from public.notification_outbox o
   where o.audience ? p_user::text
     and o.enqueued_at > v_now - interval '24 hours'
     and o.enqueued_at <= v_now;

  if v_deliveries >= 3 then
    return false;
  end if;

  insert into public.notification_outbox (invitation_id, kind, audience, enqueued_at)
  values (p_invitation, 'invite', pg_catalog.jsonb_build_array(p_user), v_now);
  return true;
end $$;

comment on function public.enqueue_invitation_notification(uuid, uuid) is
  'Queues one pending direct-invitation push when its recipient has fewer than three outbox '
  'deliveries in the preceding rolling 24 hours. Concurrent invitations for the same recipient '
  'coalesce into the one unsent invite row. Called only by create_invitation(), in the same '
  'transaction as the invitation itself.';

revoke all on function public.enqueue_invitation_notification(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_invitation_notification(uuid, uuid) to service_role;

-- E20-01 introduced this function. Replacing it, rather than asking the Edge Function to make a
-- second RPC call, makes the invitation and any notification row one transaction: an API retry
-- cannot produce a notification for an invitation that did not commit.
create or replace function public.create_invitation(
  p_group        uuid,
  p_invited_by   uuid,
  p_invited_user uuid
) returns public.invitations
language plpgsql
set search_path = ''
as $$
declare
  v_invitation public.invitations;
begin
  update public.invitations
     set status = 'expired', responded_at = public.now_()
   where group_id = p_group
     and invited_user = p_invited_user
     and status = 'pending'
     and expires_at <= public.now_();

  insert into public.invitations (group_id, invited_user, invited_by)
  values (p_group, p_invited_user, p_invited_by)
  returning * into v_invitation;

  perform public.enqueue_invitation_notification(v_invitation.id, p_invited_user);
  return v_invitation;
end $$;

comment on function public.create_invitation(uuid, uuid, uuid) is
  'Invites invited_user to group as pending, first lazily expiring a stale pending row for '
  'the same pair so a live invitation is always insertable after one goes terminal. Queues a '
  'budgeted, coalesced invitation alert in the same transaction. Lets 23505 (a live pending '
  'invite to this pair already exists) through unhandled — the handler maps it to '
  'ALREADY_INVITED.';

-- The original function's privileges survive CREATE OR REPLACE, but state the contract here so
-- a later migration does not accidentally reopen an internal operation to clients.
revoke all on function public.create_invitation(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.create_invitation(uuid, uuid, uuid) to service_role;

-- Invite rows do not join a round. Claimed invitation rows still carry their own expiry so APNs
-- cannot deliver one after the invitation has expired. Terminal invitations are settled before
-- they are claimed; they were handled in-app, so retrying their alert would only lead to a 404.
-- PostgreSQL regards the OUT columns as the function's return type, so adding the invitation
-- fields requires a drop/recreate rather than CREATE OR REPLACE. Nothing depends on this RPC
-- except its service-role caller, whose grant is reinstated immediately below.
drop function public.claim_notification_outbox(uuid, int);

create or replace function public.claim_notification_outbox(
  p_claim_id uuid,
  p_limit int default 20
)
returns table (
  id uuid,
  round_id uuid,
  invitation_id uuid,
  kind public.notif_kind,
  audience jsonb,
  attempts int,
  reveals_at timestamptz,
  scores_at timestamptz,
  invitation_expires_at timestamptz
)
language sql
volatile
strict
security invoker
set search_path = ''
as $$
  with settled_invitations as (
    update public.notification_outbox o
       set sent_at = statement_timestamp(),
           claimed_at = null,
           claim_id = null,
           last_error = 'invitation no longer pending'
     where o.sent_at is null
       and o.kind = 'invite'
       and not exists (
         select 1
           from public.invitations i
          where i.id = o.invitation_id
            and i.status = 'pending'
            and i.expires_at > statement_timestamp()
       )
  ), due as materialized (
    select o.id
      from public.notification_outbox o
     where o.sent_at is null
       and o.attempts < 5
       and (
         o.claimed_at is null
         or o.claimed_at <= statement_timestamp() - interval '55 seconds'
       )
       and (
         o.kind <> 'invite'
         or exists (
           select 1
             from public.invitations i
            where i.id = o.invitation_id
              and i.status = 'pending'
              and i.expires_at > statement_timestamp()
         )
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
    returning o.id, o.round_id, o.invitation_id, o.kind, o.audience, o.attempts
  )
  select c.id, c.round_id, c.invitation_id, c.kind, c.audience, c.attempts,
         r.reveals_at, r.scores_at, i.expires_at
    from claimed c
    left join public.rounds r on r.id = c.round_id
    left join public.invitations i on i.id = c.invitation_id
   order by c.id;
$$;

revoke all on function public.claim_notification_outbox(uuid, int) from public, anon, authenticated;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
