-- 20260818090000_circle_cap.sql — ADR-011, docs/01 §4. tasks/E18-01.
--
-- Lifts ADR-005. A user may hold several active circles, capped at a number ADR-011 owns —
-- not this file, so raising it later is one edit there plus the constant this file reads.
--
-- `memberships_one_active_per_user` enforced "at most one" for free, by construction, with no
-- application code involved. Its replacement has to do the same job under concurrency without
-- an index shaped like "at most N per user", which Postgres has no native constraint for — so
-- this is a trigger, and the trigger takes an advisory lock before it counts. Two joins for
-- the same user arriving in the same instant both start by reading `count(*)`; without the
-- lock, both could read "2 of 3" and both insert, landing the user at 4. The lock serializes
-- them so the second one counts *after* the first one committed, not concurrently with it.

drop index public.memberships_one_active_per_user;

-- ─── the cap ───────────────────────────────────────────────────────────────────
-- The one statement of the number. Everywhere else — server or client — cites this function
-- rather than repeating the digit (ADR-011).
--
-- One place this cannot reach: the two copy strings that name "three" in prose —
-- `_shared/http.ts`'s `CIRCLE_LIMIT_REACHED` message and `docs/11-COPY-DECK.md`'s
-- `error.circlelimitreached` row. Raising the cap here does not raise them; that edit stays
-- manual and easy to forget, so it is flagged here rather than left implicit.
--
-- Granted to `service_role` even though no Edge Function calls it directly: `enforce_circle_cap`
-- below calls it *from inside the trigger body*, which is a genuine function call charged to
-- the DML role's own privileges — unlike the trigger's own dispatch, which fires regardless of
-- grants (`guesses_validate()`, 0002, has none and still runs). `tests/db/rls.sql`'s RPC
-- allowlist lists it too, with the same note, so the grant is asserted rather than assumed.
create or replace function public.active_circle_cap()
returns int
language sql
immutable
set search_path = ''
as $$
  select 3
$$;

revoke all on function public.active_circle_cap() from public, anon, authenticated;
grant execute on function public.active_circle_cap() to service_role;

-- ─── enforcement ─────────────────────────────────────────────────────────────
-- BD002, distinct from BD001 (`ALREADY_IN_GROUP`, still raised by the unique pair index below
-- when the caller rejoins a circle they are already in). The handler maps BD002 to
-- `CIRCLE_LIMIT_REACHED` — a named, cap-shaped answer, not a bare constraint violation.
create or replace function public.enforce_circle_cap()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_active_count int;
begin
  -- Rejoining a circle already held is a pair-uniqueness violation
  -- (`memberships_unique_active_pair`, 23505 → `ALREADY_IN_GROUP`), never a cap violation — it
  -- does not add a circle, so it must not be refused for holding too many. Checked first,
  -- because this trigger runs before the pair index would otherwise catch it, and a caller
  -- already sitting at the cap must still be able to hit "already in that one" rather than
  -- being told the cap first for a request that was never going to add a fourth circle.
  if exists (
    select 1 from public.memberships
     where user_id = new.user_id and group_id = new.group_id and left_at is null
  ) then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.user_id::text));

  select count(*) into v_active_count
  from public.memberships
  where user_id = new.user_id and left_at is null;

  if v_active_count >= public.active_circle_cap() then
    raise exception 'caller is at the active-circle cap' using errcode = 'BD002';
  end if;

  return new;
end $$;

comment on function public.enforce_circle_cap() is
  'Refuses a new active membership past active_circle_cap() (ADR-011). Raises BD002; the '
  'groups handler turns that into CIRCLE_LIMIT_REACHED. Takes an advisory lock on the user '
  'id first so two concurrent joins cannot both slip past the count. Rejoining a circle '
  'already held is exempted — that fails the pair index instead, not the cap.';

revoke all on function public.enforce_circle_cap() from public, anon, authenticated, service_role;

create trigger memberships_circle_cap
  before insert on public.memberships
  for each row
  when (new.left_at is null)
  execute function public.enforce_circle_cap();

-- ─── create_group() no longer refuses a second circle ───────────────────────
-- The pre-check for "caller already has an active membership" was ADR-005. Under ADR-011 a
-- second or third circle is allowed, and the cap above is what refuses a fourth — through the
-- same trigger `POST /groups/join` goes through, so the two routes fail identically at the
-- cap. The unique-violation catch goes too: the index it was guarding against no longer
-- exists, and `memberships_unique_active_pair` cannot fire here — this always inserts into a
-- group that was just created, so no prior row can collide with it.
create or replace function public.create_group(
  p_user        uuid,
  p_name        text,
  p_timezone    text,
  p_reveal_hour int,
  p_invite_code text
) returns public.groups
language plpgsql
set search_path = ''
as $$
declare
  v_group public.groups;
begin
  insert into public.groups (name, timezone, reveal_hour, invite_code, created_by)
  values (btrim(p_name), p_timezone, p_reveal_hour, p_invite_code, p_user)
  returning * into v_group;

  -- BD002 (circle cap) can raise here, through `memberships_circle_cap` above; the handler
  -- maps it to CIRCLE_LIMIT_REACHED the same way it does for `POST /groups/join`.
  insert into public.memberships (group_id, user_id, role)
  values (v_group.id, p_user, 'admin');

  return v_group;
end $$;

comment on function public.create_group(uuid, text, text, int, text) is
  'Creates a group and its creator''s admin membership in one transaction. Lets BD002 '
  '(ADR-011''s circle cap) and 23505 (invite-code collision, for retry) through unhandled.';

revoke all on function public.create_group(uuid, text, text, int, text) from public, anon, authenticated;
grant execute on function public.create_group(uuid, text, text, int, text) to service_role;
