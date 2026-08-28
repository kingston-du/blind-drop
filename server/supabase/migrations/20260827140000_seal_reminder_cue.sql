-- 20260827140000_seal_reminder_cue.sql — E35-06, docs/18-CUES.md §11.1.
--
-- A single-circle `seal_reminder` may carry the round's cue in its body ("… Tonight: A song you
-- hate."). This is a body change on the existing `seal_reminder` kind, not a seventh kind —
-- CLAUDE.md §6's closed set is unchanged. The cue text is `rounds.prompt` (the frozen text;
-- `prompt_key` only references the catalog).
--
-- The subtle part is the "grouped" decision, and it is resolved here so the worker stays dumb.
-- Cross-circle grouping is done at *enqueue* time by `notification_delivery_allowed`: a user in
-- several circles whose rounds all share a `scheduled_for` is added to only one circle's outbox
-- row. So a "grouped" notification is one whose `audience` contains a member who *also* belongs
-- to another circle that has a coincident `seal_reminder` row at the same `scheduled_for` — that
-- delivery stands in for several circles for that member, and must never name one circle's cue
-- arbitrarily. The claim function therefore returns `cue_text` only when the row is NOT grouped;
-- the worker just relays `cue_text`, with no grouping logic of its own.
--
-- "Grouped" is defined concretely: there exists another `notification_outbox` row of kind
-- `seal_reminder` at the same `scheduled_for` for a *different* round (so a different circle),
-- whose circle has an active membership overlapping this row's `audience`. The check reads the
-- audience *after* the settle-trim below — a member who resolved before claim receives nothing,
-- so they cannot make the delivery "stand in for" anything. It runs against the existing
-- `notification_outbox_delivery_window (kind, scheduled_for)` index.

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
  invitation_expires_at timestamptz,
  cue_text text
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
         r.reveals_at, r.scores_at, c.scheduled_for, i.expires_at,
         case
           when c.kind = 'seal_reminder'
            and not exists (
                  -- Another circle's coincident seal_reminder row whose circle shares an active
                  -- member with this row's (post-trim) audience: the delivery stands in for more
                  -- than one circle, so it must not name this circle's cue.
                  select 1
                    from public.notification_outbox o2
                    join public.rounds r2 on r2.id = o2.round_id
                   where o2.kind = 'seal_reminder'
                     and o2.scheduled_for = c.scheduled_for
                     and o2.id <> c.id
                     and exists (
                           select 1
                             from public.memberships m
                            where m.group_id = r2.group_id
                              and m.left_at is null
                              and c.audience ? m.user_id::text
                         )
                )
           then r.prompt
           else null
         end as cue_text
    from claimed c
    left join public.rounds r on r.id = c.round_id
    left join public.invitations i on i.id = c.invitation_id
   order by c.id;
$$;

revoke all on function public.claim_notification_outbox(uuid, int) from public, anon, authenticated;
grant execute on function public.claim_notification_outbox(uuid, int) to service_role;
