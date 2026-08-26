-- 20260826120100_conditional_reminders.sql — E31-01, docs/05 §3, docs/17 §5.
--
-- Owner amendment (docs/17-NEXT-FEATURES.md §5, same footing as ADR-011; CLAUDE.md §2.6,
-- docs/05 §3, docs/16 §5 edited alongside this file): the unconditional `nudge` — sent to every
-- active member at reveals_at − 2h regardless of submission status — is retired. Two
-- conditional reminders replace it:
--
--   seal_reminder   reveals_at − 2h  AND  reveals_at − 30m   members without a submission
--   guess_reminder  scores_at  − 30m                          submitters with an incomplete
--                                                              guess sheet (< S−1 distinct
--                                                              cards guessed)
--
-- This lifts the old 3-deliveries/24h cap that `notification_delivery_allowed` enforced: a
-- fully disengaged member (drops right before reveal, never opens the guess sheet) can now see
-- five pushes for one round — both seal_reminders, reveal, guess_reminder, results. The
-- cross-circle same-instant grouping that function also performs is unchanged and still applies
-- per kind (E23-02).

-- ─── outbox uniqueness widens to admit two seal_reminder firings per round ────────────────────
-- `seal_reminder` fires up to twice per round, at two different `scheduled_for` instants. The
-- old (round_id, kind) key would silently drop the second insert. `scheduled_for` was added by
-- 20260820110000 for exactly this kind of per-instant identity; every kind that fires once still
-- has exactly one (round_id, kind, scheduled_for) tuple; nothing about single-firing kinds
-- changes.
drop index public.notification_outbox_once;
create unique index notification_outbox_once
  on public.notification_outbox (round_id, kind, scheduled_for);

-- ─── enqueue_round_notification: same body, new conflict target ──────────────────────────────
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
  on conflict (round_id, kind, scheduled_for) do nothing
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
  'Writes one idempotent round event per (round, kind, scheduled instant), adding only '
  'recipients the central cross-circle coalesce check admits. Called only by tick_rounds() in '
  'its transition transaction.';

revoke all on function public.enqueue_round_notification(uuid, public.notif_kind, jsonb, timestamptz)
  from public, anon, authenticated, service_role;

-- ─── notification_delivery_allowed: the 3/24h cap is lifted, the coalesce check is not ────────
create or replace function public.notification_delivery_allowed(
  p_user uuid,
  p_kind public.notif_kind,
  p_scheduled_for timestamptz default null
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text, 2_003)
  );

  -- A scheduled window is a semantic instant, not the minute a delayed tick happened to run.
  -- The row may already be sent; it is still the user's one delivery for that coincident event.
  -- This is the part of this function E23-02 needs and E31-01 leaves untouched.
  if p_scheduled_for is not null and exists (
    select 1
      from public.notification_outbox o
     where o.kind = p_kind
       and o.scheduled_for = p_scheduled_for
       and o.audience ? p_user::text
  ) then
    return false;
  end if;

  -- E31-01 (docs/17 §5, owner amendment — CLAUDE.md §2.6): the rolling 3-deliveries/24h count
  -- this function used to enforce here is gone. `seal_reminder` (up to twice a round) and
  -- `guess_reminder` (once) push a fully disengaged member's evening past three deliveries by
  -- design, so a hard ceiling and these two kinds cannot coexist. The advisory lock above is
  -- kept because the coalesce check just above still needs to be race-free across concurrent
  -- circles.
  return true;
end $$;

comment on function public.notification_delivery_allowed(uuid, public.notif_kind, timestamptz) is
  'Coalesces same-kind scheduled windows across a user''s circles so a coincident event is one '
  'delivery, not one per circle (E23-02). Carries no daily delivery ceiling as of E31-01 — that '
  'cap was lifted by the owner (docs/17 §5) to accommodate seal_reminder/guess_reminder. '
  'Internal-only; scheduled and invitation enqueue paths call it.';

revoke all on function public.notification_delivery_allowed(uuid, public.notif_kind, timestamptz)
  from public, anon, authenticated, service_role;

-- ─── tick_rounds(): three conditional scan windows replace the unconditional nudge scan ───────
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

  -- reveal or void (unchanged by E31-01)
  for v_round in
    select r.id, r.group_id, r.reveals_at
      from public.rounds r
      join public.groups g on g.id = r.group_id
     where r.state = 'open'
       and not g.is_demo
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

  -- score (unchanged by E31-01)
  for v_round in
    select r.id, r.group_id, r.scores_at
      from public.rounds r
      join public.groups g on g.id = r.group_id
     where r.state = 'revealed'
       and not g.is_demo
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

  -- seal_reminder, first firing: reveals_at − 2h, members with no submission yet.
  -- Same scan mechanism the old unconditional nudge used — a not-yet-enqueued-for-this-instant
  -- guard ahead of the loop, then the real per-round idempotent enqueue — with a real audience
  -- condition instead of "everyone".
  for v_round in
    select r.id, r.group_id, r.reveals_at
      from public.rounds r
      join public.groups g on g.id = r.group_id
     where r.state = 'open'
       and not g.is_demo
       and r.reveals_at > v_now
       and r.reveals_at <= v_now + interval '2 hours'
       and not exists (
         select 1 from public.notification_outbox o
          where o.round_id = r.id and o.kind = 'seal_reminder'
            and o.scheduled_for = r.reveals_at - interval '2 hours'
       )
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb) into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id and m.left_at is null
         and not exists (
           select 1 from public.submissions s
            where s.round_id = v_round.id and s.user_id = m.user_id
         );
      perform public.enqueue_round_notification(
        v_round.id, 'seal_reminder', v_audience, v_round.reveals_at - interval '2 hours'
      );
    exception when others then
      raise warning 'tick_rounds seal_reminder(2h): round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  -- seal_reminder, second firing: reveals_at − 30m, same condition, re-evaluated fresh.
  -- Distinguished from the first firing only by `scheduled_for`; the widened
  -- notification_outbox_once index (round_id, kind, scheduled_for) is what lets both rows exist.
  for v_round in
    select r.id, r.group_id, r.reveals_at
      from public.rounds r
      join public.groups g on g.id = r.group_id
     where r.state = 'open'
       and not g.is_demo
       and r.reveals_at > v_now
       and r.reveals_at <= v_now + interval '30 minutes'
       and not exists (
         select 1 from public.notification_outbox o
          where o.round_id = r.id and o.kind = 'seal_reminder'
            and o.scheduled_for = r.reveals_at - interval '30 minutes'
       )
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select coalesce(jsonb_agg(m.user_id order by m.user_id), '[]'::jsonb) into v_audience
        from public.memberships m
       where m.group_id = v_round.group_id and m.left_at is null
         and not exists (
           select 1 from public.submissions s
            where s.round_id = v_round.id and s.user_id = m.user_id
         );
      perform public.enqueue_round_notification(
        v_round.id, 'seal_reminder', v_audience, v_round.reveals_at - interval '30 minutes'
      );
    exception when others then
      raise warning 'tick_rounds seal_reminder(30m): round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;

  -- guess_reminder: scores_at − 30m, submitters whose guess sheet is not yet complete
  -- (fewer than S−1 distinct cards guessed). Expressed via reveals_at (scores_at is always
  -- reveals_at + 2h, docs/03 §4) rather than scores_at directly, so this scan uses
  -- rounds_pending_tick(state, reveals_at) the same way the score loop above it does — the
  -- index has no scores_at column, and a filter on scores_at alone would fall back to scanning
  -- every revealed round. No upper bound is needed: the score loop above already moved any round
  -- whose scores_at has passed to 'scored' earlier in this same transaction, so `state =
  -- 'revealed'` here already means "not there yet".
  for v_round in
    select r.id, r.group_id, r.scores_at
      from public.rounds r
      join public.groups g on g.id = r.group_id
     where r.state = 'revealed'
       and not g.is_demo
       and r.reveals_at <= v_now - interval '1 hour 30 minutes'
       and not exists (
         select 1 from public.notification_outbox o
          where o.round_id = r.id and o.kind = 'guess_reminder'
       )
     order by r.reveals_at, r.id
     for update skip locked
  loop
    begin
      select count(*)::int into v_submitters
        from public.submissions s where s.round_id = v_round.id;

      select coalesce(jsonb_agg(s.user_id order by s.user_id), '[]'::jsonb) into v_audience
        from public.submissions s
       where s.round_id = v_round.id
         and exists (select 1 from auth.users u where u.id = s.user_id)
         and (
           select count(distinct g.submission_id)
             from public.guesses g
            where g.round_id = v_round.id and g.guesser_id = s.user_id
         ) < (v_submitters - 1);

      perform public.enqueue_round_notification(
        v_round.id, 'guess_reminder', v_audience, v_round.scores_at - interval '30 minutes'
      );
    exception when others then
      raise warning 'tick_rounds guess_reminder: round % skipped (%): %', v_round.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.tick_rounds() is
  'Ensures rounds, advances due rounds through reveal/void and score, and freezes each '
  'scheduled reminder''s conditional audience per open/revealed round (docs/02 §2, docs/05 §3). '
  'seal_reminder (reveals_at − 2h and − 30m) and guess_reminder (scores_at − 30m) replace the '
  'old unconditional nudge as of E31-01; every transition and enqueue is atomic, guarded, and '
  'idempotent (docs/05 §2).';

revoke all on function public.tick_rounds() from public, anon, authenticated;
grant execute on function public.tick_rounds() to service_role;

-- ─── claim_notification_outbox: settle-check for the two conditional kinds ────────────────────
-- Round-kind audiences were previously frozen forever at enqueue (docs/05 §3, "a later join or
-- leave does not rewrite it") because no existing kind's audience condition could change between
-- enqueue and send. seal_reminder/guess_reminder break that: their condition (no submission; an
-- incomplete guess sheet) can resolve true in the up-to-two-hour gap before the worker claims the
-- row. Unlike `settled_invitations` below — whose `invite` rows are always one recipient, so a
-- whole row can be marked fully sent when it settles, and whose settlement predicate is the exact
-- complement of `due`'s own pending-check (so the two updates provably never touch the same row)
-- — seal_reminder/guess_reminder rows commonly hold several recipients at once, only some of whom
-- may have resolved, and "resolved" is not the complement of anything `due` already tests. So
-- this settle-check cannot be a second, independent UPDATE the way `settled_invitations` is:
-- Postgres does not define what happens when two data-modifying CTEs in the same statement touch
-- the same row (it can outright error with "tuple to be updated was already modified"), and a row
-- that is both due to settle and due to claim is the common case here, not an edge case. Instead
-- the trim is folded into `claimed`'s own single UPDATE, in the same SET clause that advances
-- `attempts`/`claimed_at`: one statement per row, reading `o.audience`/`o.kind`/`o.round_id` at
-- their pre-update values, same as any ordinary UPDATE. A member who has since resolved their
-- condition is dropped from `audience` at the moment the row is (re)claimed — every attempt, not
-- just the first, since a retried send should be exactly as accurate as a first one. If every
-- recipient has resolved, the row is left with an empty audience; the ordinary claim → zero
-- devices → finish() path then marks it `sent_at` exactly as if it had been sent, which is the
-- same "skip sending, mark sent_at" outcome `settled_invitations` gives a fully-resolved invite
-- row, at recipient granularity instead of row granularity.
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
  scheduled_for timestamptz,
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
    -- The audience trim lives in this same UPDATE, not a separate CTE: two data-modifying CTEs
    -- touching one row in one statement is undefined in Postgres (and can raise "tuple to be
    -- updated was already modified"), and a row due to settle is usually also due to claim.
    update public.notification_outbox o
       set attempts = o.attempts + 1,
           claimed_at = statement_timestamp(),
           claim_id = p_claim_id,
           audience = case o.kind
             when 'seal_reminder' then coalesce((
               select jsonb_agg(elem.value order by elem.value)
                 from jsonb_array_elements_text(o.audience) as elem(value)
                where not exists (
                        select 1 from public.submissions s
                         where s.round_id = o.round_id and s.user_id = elem.value::uuid
                      )
             ), '[]'::jsonb)
             when 'guess_reminder' then coalesce((
               select jsonb_agg(elem.value order by elem.value)
                 from jsonb_array_elements_text(o.audience) as elem(value)
                where (
                        select count(distinct g.submission_id)
                          from public.guesses g
                         where g.round_id = o.round_id and g.guesser_id = elem.value::uuid
                      ) < greatest((
                        select count(*) from public.submissions s2 where s2.round_id = o.round_id
                      ) - 1, 0)
             ), '[]'::jsonb)
             else o.audience
           end
      from due
     where o.id = due.id
    returning o.id, o.round_id, o.invitation_id, o.kind, o.audience, o.attempts, o.scheduled_for
  )
  select c.id, c.round_id, r.group_id, c.invitation_id, c.kind, c.audience, c.attempts,
         r.reveals_at, r.scores_at, c.scheduled_for, i.expires_at
    from claimed c
    left join public.rounds r on r.id = c.round_id
    left join public.invitations i on i.id = c.invitation_id
   order by c.id;
$$;

revoke all on function public.claim_notification_outbox(uuid, int) from public, anon, authenticated;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
