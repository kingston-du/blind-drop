-- 20260820110000_notification_delivery_budget.sql — E23-02, docs/05 §3–4.
--
-- An outbox row remains one circle event, with its original frozen audience.  The delivery
-- budget is per person, though: when the same recipient belongs to several circles whose same
--kind events share a scheduled instant, they stay on the first row only.  Later rows retain
--their other recipients, but not that person.  This preserves per-round idempotency and gives
--the one delivery a stable, circle-scoped target.

alter table public.notification_outbox
  add column scheduled_for timestamptz;

-- Existing rows were created before a delivery window was recorded. Backfill their semantic
-- trigger instant so an in-flight row continues to coalesce safely after this migration.
update public.notification_outbox o
   set scheduled_for = case o.kind
     when 'nudge' then r.reveals_at - interval '2 hours'
     when 'results' then r.scores_at
     else r.reveals_at
   end
  from public.rounds r
 where o.round_id = r.id
   and o.scheduled_for is null;

create index notification_outbox_delivery_window
  on public.notification_outbox (kind, scheduled_for)
  where scheduled_for is not null;

create index notification_outbox_audience
  on public.notification_outbox using gin (audience);

-- The only budget decision point. Its transaction advisory lock covers invitations and every
-- scheduled kind, so two concurrent senders cannot each observe an available final slot.
create or replace function public.notification_delivery_allowed(
  p_user uuid,
  p_kind public.notif_kind,
  p_scheduled_for timestamptz default null
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

  -- A scheduled window is a semantic instant, not the minute a delayed tick happened to run.
  -- The row may already be sent; it is still the user's one delivery for that coincident event.
  if p_scheduled_for is not null and exists (
    select 1
      from public.notification_outbox o
     where o.kind = p_kind
       and o.scheduled_for = p_scheduled_for
       and o.audience ? p_user::text
  ) then
    return false;
  end if;

  select count(*)::int
    into v_deliveries
    from public.notification_outbox o
   where o.audience ? p_user::text
     and o.enqueued_at > v_now - interval '24 hours'
     and o.enqueued_at <= v_now;

  return v_deliveries < 3;
end $$;

comment on function public.notification_delivery_allowed(uuid, public.notif_kind, timestamptz) is
  'The central per-user notification budget. Serializes every recipient decision, coalesces '
  'same-kind scheduled windows across circles, and refuses a fourth delivery in the preceding '
  'rolling 24 hours. Internal-only; scheduled and invitation enqueue paths call it.';

revoke all on function public.notification_delivery_allowed(uuid, public.notif_kind, timestamptz)
  from public, anon, authenticated, service_role;

-- One outbox row remains the idempotency marker for each round event. Its audience is filtered
-- per recipient through notification_delivery_allowed(), rather than treating a whole group as
-- one person's budget. An empty frozen audience is deliberate: it records that the event was
-- considered and prevents a later tick from trying again.
create or replace function public.enqueue_round_notification(
  p_round uuid,
  p_kind public.notif_kind,
  p_audience jsonb,
  p_scheduled_for timestamptz
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_outbox uuid;
  v_user uuid;
begin
  if p_kind = 'invite' or p_scheduled_for is null then
    raise exception 'round notification requires a scheduled round kind and window';
  end if;
  if pg_catalog.jsonb_typeof(p_audience) <> 'array' then
    raise exception 'round notification audience must be an array';
  end if;

  insert into public.notification_outbox (round_id, kind, audience, enqueued_at, scheduled_for)
  values (p_round, p_kind, '[]'::jsonb, public.now_(), p_scheduled_for)
  on conflict (round_id, kind) do nothing
  returning id into v_outbox;

  if v_outbox is null then
    return;
  end if;

  -- A stable lock order prevents two overlapping circle audiences from deadlocking while each
  -- recipient's decision is serialized by notification_delivery_allowed().
  for v_user in
    select value::uuid
      from pg_catalog.jsonb_array_elements_text(p_audience) t(value)
     group by value
     order by value
  loop
    if public.notification_delivery_allowed(v_user, p_kind, p_scheduled_for) then
      update public.notification_outbox
         set audience = audience || pg_catalog.jsonb_build_array(v_user)
       where id = v_outbox;
    end if;
  end loop;
end $$;

comment on function public.enqueue_round_notification(uuid, public.notif_kind, jsonb, timestamptz) is
  'Writes a single idempotent round event, adding only recipients allowed by the central '
  'cross-circle delivery budget. Called only by tick_rounds() in its transition transaction.';

revoke all on function public.enqueue_round_notification(uuid, public.notif_kind, jsonb, timestamptz)
  from public, anon, authenticated, service_role;

-- Invitations have a different coalescing window: any unsent invite prompt for this recipient
-- represents all pending invitations until the worker drains it. Their budget decision still
-- goes through the same central function as scheduled round events.
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
begin
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text, 2_003)
  );

  if exists (
    select 1
      from public.notification_outbox o
     where o.kind = 'invite'
       and o.sent_at is null
       and o.audience ? p_user::text
  ) then
    return false;
  end if;

  if not public.notification_delivery_allowed(p_user, 'invite', null) then
    return false;
  end if;

  insert into public.notification_outbox (invitation_id, kind, audience, enqueued_at)
  values (p_invitation, 'invite', pg_catalog.jsonb_build_array(p_user), v_now);
  return true;
end $$;

comment on function public.enqueue_invitation_notification(uuid, uuid) is
  'Queues one pending direct-invitation push when its recipient passes the central delivery '
  'budget. Concurrent unsent invitations coalesce into the first prompt.';

revoke all on function public.enqueue_invitation_notification(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_invitation_notification(uuid, uuid) to service_role;

-- Every scheduled enqueue now goes through the central delivery decision. The nudge is an
-- invitation to revise a choice, not a refusal for people who already made one, so its frozen
-- audience is the full active roster.
create or replace function public.tick_rounds()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now          timestamptz := public.now_();
  v_round        record;
  v_submitters   int;
  v_audience     jsonb;
  v_order        uuid[];
  v_swap         uuid;
  v_seed         bigint;
  v_digest       text;
  v_i            int;
  v_j            int;
  v_updated      int;
begin
  perform public.ensure_rounds();

  for v_round in
    select r.id, r.group_id, r.reveals_at
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at <= v_now
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select count(*)::int into v_submitters
        from public.submissions s where s.round_id = v_round.id;

      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb) into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id and m.left_at is null;

      if v_submitters < 3 then
        update public.rounds set state = 'voided'
         where id = v_round.id and state = 'open';
        get diagnostics v_updated = row_count;
        if v_updated = 1 then
          perform public.enqueue_round_notification(v_round.id, 'void', v_audience, v_round.reveals_at);
        end if;
      else
        select array_agg(s.id order by s.created_at, s.id) into v_order
          from public.submissions s where s.round_id = v_round.id;
        v_seed := pg_catalog.hashtext(v_round.id::text)::bigint;
        for v_i in reverse pg_catalog.array_length(v_order, 1)..2 loop
          v_digest := pg_catalog.md5(v_seed::text || ':' || v_i::text);
          v_j := ((('x' || pg_catalog.substr(v_digest, 1, 8))::bit(32)::bigint % v_i) + 1)::int;
          v_swap := v_order[v_i];
          v_order[v_i] := v_order[v_j];
          v_order[v_j] := v_swap;
        end loop;

        update public.rounds set state = 'revealed', card_order = pg_catalog.to_jsonb(v_order)
         where id = v_round.id and state = 'open';
        get diagnostics v_updated = row_count;
        if v_updated = 1 then
          perform public.enqueue_round_notification(v_round.id, 'reveal', v_audience, v_round.reveals_at);
        end if;
      end if;
    exception when others then
      raise warning 'tick_rounds reveal: round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  for v_round in
    select r.id, r.group_id, r.scores_at
      from public.rounds r
     where r.state = 'revealed'
       and r.reveals_at <= v_now - interval '2 hours'
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(participant.user_id order by participant.user_id), '[]'::jsonb)
        into v_audience
        from (
          select s.user_id from public.submissions s where s.round_id = v_round.id
          union
          select g.guesser_id from public.guesses g where g.round_id = v_round.id
        ) participant
       where exists (select 1 from auth.users u where u.id = participant.user_id);

      update public.rounds set state = 'scored'
       where id = v_round.id and state = 'revealed';
      get diagnostics v_updated = row_count;
      if v_updated = 1 then
        perform public.enqueue_round_notification(v_round.id, 'results', v_audience, v_round.scores_at);
      end if;
    exception when others then
      raise warning 'tick_rounds score: round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  for v_round in
    select r.id, r.group_id, r.reveals_at
      from public.rounds r
     where r.state = 'open'
       and r.reveals_at > v_now
       and r.reveals_at <= v_now + interval '2 hours'
       and not exists (
         select 1 from public.notification_outbox o
          where o.round_id = r.id and o.kind = 'nudge'
       )
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb) into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id and m.left_at is null;
      perform public.enqueue_round_notification(
        v_round.id, 'nudge', v_audience, v_round.reveals_at - interval '2 hours'
      );
    exception when others then
      raise warning 'tick_rounds nudge: round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.tick_rounds() is
  'Ensures rounds, advances due rounds through reveal/void and score, and freezes one nudge '
  'audience per open round. Every transition and central delivery decision is atomic, guarded, '
  'and idempotent (docs/02 §2, docs/05 §2–3).';

revoke all on function public.tick_rounds() from public, anon, authenticated;
grant execute on function public.tick_rounds() to service_role;

-- Group-aware deep links require the claim RPC to carry the group of the outbox row's stable,
-- representative round. Invitation rows remain intentionally groupless.
drop function public.claim_notification_outbox(uuid, int);

create function public.claim_notification_outbox(
  p_claim_id uuid,
  p_limit int default 20
)
returns table (
  id uuid,
  round_id uuid,
  group_id uuid,
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
       set sent_at = statement_timestamp(), claimed_at = null, claim_id = null,
           last_error = 'invitation no longer pending'
     where o.sent_at is null
       and o.kind = 'invite'
       and not exists (
         select 1 from public.invitations i
          where i.id = o.invitation_id and i.status = 'pending'
            and i.expires_at > statement_timestamp()
       )
  ), due as materialized (
    select o.id
      from public.notification_outbox o
     where o.sent_at is null
       and o.attempts < 5
       and (o.claimed_at is null or o.claimed_at <= statement_timestamp() - interval '55 seconds')
       and (o.kind <> 'invite' or exists (
         select 1 from public.invitations i
          where i.id = o.invitation_id and i.status = 'pending'
            and i.expires_at > statement_timestamp()
       ))
     order by o.enqueued_at, o.id
     limit least(greatest(p_limit, 1), 20)
     for update skip locked
  ), claimed as (
    update public.notification_outbox o
       set attempts = o.attempts + 1, claimed_at = statement_timestamp(), claim_id = p_claim_id
      from due
     where o.id = due.id
    returning o.id, o.round_id, o.invitation_id, o.kind, o.audience, o.attempts
  )
  select c.id, c.round_id, r.group_id, c.invitation_id, c.kind, c.audience, c.attempts,
         r.reveals_at, r.scores_at, i.expires_at
    from claimed c
    left join public.rounds r on r.id = c.round_id
    left join public.invitations i on i.id = c.invitation_id
   order by c.id;
$$;

revoke all on function public.claim_notification_outbox(uuid, int) from public, anon, authenticated;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
