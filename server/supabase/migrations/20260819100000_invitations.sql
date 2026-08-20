-- 20260819100000_invitations.sql — E20-01, docs/02 §2 (join by an invite code, unchanged),
-- CLAUDE.md §2.6 (`invite` push kind reserved for E20-03, not this file).
--
-- Today joining inserts a membership directly — there is no invitation row anywhere. This adds
-- one: pending, distinct state with an inviter and an outcome, for the "someone I already know"
-- path (`docs/02`'s invite-code path — `_shared/invite.ts`, `POST /groups/join` — is untouched).
--
-- **A pending invitee is invisible to the game.** Every reader of `memberships` in this codebase
-- — the name pool, the minimum-of-three, `card_order`, standings, scoring, every push audience —
-- already filters to real, active membership rows. This table is never unioned into any of
-- them; `tests/db/invitations.sql` proves a pending user changes none of their answers.

-- ─── the table ─────────────────────────────────────────────────────────────────
create table public.invitations (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  invited_user  uuid not null references public.profiles(id) on delete cascade,
  invited_by    uuid not null references public.profiles(id),
  status        text not null default 'pending'
                  check (status in ('pending', 'accepted', 'declined', 'expired')),
  created_at    timestamptz not null default public.now_(),
  responded_at  timestamptz,
  -- Two weeks: long enough to reach someone who doesn't open the app daily, short enough that
  -- a stale invite doesn't sit around forever advertising a circle that moved on. Not an ADR;
  -- adjust freely if the owner wants a different number.
  expires_at    timestamptz not null default public.now_() + interval '14 days',
  constraint invitations_responded_iff_terminal check (
    (responded_at is not null) = (status <> 'pending')),
  -- Defense in depth. The handler checks this before ever calling create_invitation(); this is
  -- the backstop for a caller that reaches the RPC some other way.
  constraint invitations_not_self check (invited_user <> invited_by)
);

-- At most one *live* pending invitation per (circle, person) — freed the instant it goes
-- terminal (accepted, declined, or lazily expired by create_invitation() below), which is what
-- makes decline and expiry actually re-invitable rather than stuck behind their own ghost row.
create unique index invitations_unique_pending_pair
  on public.invitations (group_id, invited_user) where status = 'pending';

-- The two lookups the API does: "what's pending for me" (any circle) and "who in this circle
-- has an outstanding invite" (E20-02/E20-03).
create index invitations_invited_user_pending on public.invitations (invited_user)
  where status = 'pending';
create index invitations_group on public.invitations (group_id);

alter table public.invitations enable row level security;
alter table public.invitations force row level security;
revoke all on public.invitations from anon, authenticated;

grant select, insert, update on public.invitations to service_role;

-- ─── create_invitation() ──────────────────────────────────────────────────────
-- Lazily expires a stale pending row for the same pair before inserting a fresh one. Nothing
-- else in this slice flips a row to `expired` on its own — the state exists so a caller who
-- tries to act on an old invitation gets a terminal answer, and so the unique index above means
-- "one *live* pending invite", not "one invite ever".
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

  return v_invitation;
end $$;

comment on function public.create_invitation(uuid, uuid, uuid) is
  'Invites invited_user to group as pending, first lazily expiring a stale pending row for '
  'the same pair so a live invitation is always insertable after one goes terminal. Lets '
  '23505 (a live pending invite to this pair already exists) through unhandled — the handler '
  'maps it to ALREADY_INVITED.';

revoke all on function public.create_invitation(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.create_invitation(uuid, uuid, uuid) to service_role;

-- ─── accept_invitation() ──────────────────────────────────────────────────────
-- Atomically resolves the invitation and creates the membership through the same
-- `memberships_circle_cap` trigger every other join goes through (ADR-011, `20260818090000`) —
-- this is not a second, uncapped door into a circle.
create or replace function public.accept_invitation(
  p_invitation uuid,
  p_user       uuid
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_invitation public.invitations;
  v_membership public.memberships;
begin
  select * into v_invitation
  from public.invitations
  where id = p_invitation and invited_user = p_user
  for update;

  if not found then
    raise exception 'no such invitation for this caller' using errcode = 'BD004';
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'invitation is no longer pending' using errcode = 'BD004';
  end if;

  if v_invitation.expires_at <= public.now_() then
    update public.invitations set status = 'expired', responded_at = public.now_()
     where id = p_invitation;
    -- Returning this terminal outcome lets the update commit. Raising here would roll the
    -- expiry update back with the function call, leaving the invitation permanently pending.
    return jsonb_build_object('outcome', 'expired');
  end if;

  -- BD002 (ADR-011's circle cap) can raise here, through `memberships_circle_cap`; the
  -- handler maps it to CIRCLE_LIMIT_REACHED, the same as POST /groups and POST /groups/join.
  -- 23505 (already an active member of this circle — e.g. joined by invite code in the
  -- meantime) is also let through unhandled: the invitation stays pending, which is harmless,
  -- and the caller already has what they wanted.
  insert into public.memberships (group_id, user_id, role)
  values (v_invitation.group_id, p_user, 'member')
  returning * into v_membership;

  update public.invitations set status = 'accepted', responded_at = public.now_()
   where id = p_invitation;

  return jsonb_build_object('outcome', 'accepted', 'group_id', v_membership.group_id);
end $$;

comment on function public.accept_invitation(uuid, uuid) is
  'Accepts a pending, unexpired invitation and creates the membership in the same '
  'transaction, through memberships_circle_cap (ADR-011). Raises BD004 for a missing, '
  'foreign, or already-resolved invitation; returns outcome=expired after committing expiry. '
  'The handler maps both outcomes to the same non-oracle NOT_FOUND answer.';

revoke all on function public.accept_invitation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.accept_invitation(uuid, uuid) to service_role;

-- ─── decline_invitation() ─────────────────────────────────────────────────────
create or replace function public.decline_invitation(
  p_invitation uuid,
  p_user       uuid
) returns text
language plpgsql
set search_path = ''
as $$
declare
  v_invitation public.invitations;
begin
  select * into v_invitation
  from public.invitations
  where id = p_invitation and invited_user = p_user
  for update;

  if not found then
    raise exception 'no such invitation for this caller' using errcode = 'BD004';
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'invitation is no longer pending' using errcode = 'BD004';
  end if;

  if v_invitation.expires_at <= public.now_() then
    update public.invitations set status = 'expired', responded_at = public.now_()
     where id = p_invitation;
    -- As in accept_invitation, return after recording expiry so the terminal state commits.
    return 'expired';
  end if;

  update public.invitations set status = 'declined', responded_at = public.now_()
   where id = p_invitation;
  return 'declined';
end $$;

comment on function public.decline_invitation(uuid, uuid) is
  'Declines a pending, unexpired invitation. Returns expired after committing an expiry; '
  'raises BD004 (mapped to NOT_FOUND) on a second attempt.';

revoke all on function public.decline_invitation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.decline_invitation(uuid, uuid) to service_role;
