-- Configurable, code-free TestFlight enrollment.
--
-- Rows are deliberately server-only. The first profile assigned to a cohort creates its
-- backing group and becomes admin; later profiles join it as members. An advisory transaction
-- lock makes capacity checks and first-user creation safe under concurrent signups.
create table public.pilot_cohorts (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(btrim(name)) between 1 and 40),
  timezone     text not null,
  reveal_hour  int not null default 20 check (reveal_hour between 18 and 21),
  capacity     int not null default 12 check (capacity between 1 and 12),
  position     int not null unique check (position > 0),
  enabled      boolean not null default false,
  group_id     uuid unique references public.groups(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.pilot_cohorts enable row level security;
alter table public.pilot_cohorts force row level security;

comment on table public.pilot_cohorts is
  'Server-only TestFlight cohorts. Enabled rows are filled in position order, up to capacity.';

revoke all on table public.pilot_cohorts from public, anon, authenticated;
grant select, insert, update, delete on table public.pilot_cohorts to service_role;

create or replace function public.assign_pilot_cohort(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cohort public.pilot_cohorts;
  v_group_id uuid;
  v_code text;
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  -- A single lock is intentional: pilot signup volume is tiny, while serialising selection
  -- prevents two signups from both taking the final seat or creating two backing groups.
  perform pg_advisory_xact_lock(hashtextextended('blind-drop-pilot-cohort-assignment', 0));

  select m.group_id into v_group_id
  from public.memberships m
  where m.user_id = p_user and m.left_at is null;
  if v_group_id is not null then
    return v_group_id;
  end if;

  select c.* into v_cohort
  from public.pilot_cohorts c
  where c.enabled
    and (
      c.group_id is null
      or (select count(*) from public.memberships m
          where m.group_id = c.group_id and m.left_at is null) < c.capacity
    )
  order by c.position
  limit 1
  for update;

  if not found then
    return null;
  end if;

  if v_cohort.group_id is null then
    loop
      select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1), '')
      into v_code
      from generate_series(1, 6);
      begin
        insert into public.groups (name, timezone, reveal_hour, invite_code, created_by)
        values (btrim(v_cohort.name), v_cohort.timezone, v_cohort.reveal_hour, v_code, p_user)
        returning id into v_group_id;
        exit;
      exception when unique_violation then
        -- Only an invite-code collision is possible while the advisory lock is held.
      end;
    end loop;

    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'admin');

    update public.pilot_cohorts
    set group_id = v_group_id, updated_at = now()
    where id = v_cohort.id;
  else
    v_group_id := v_cohort.group_id;
    insert into public.memberships (group_id, user_id, role)
    values (v_group_id, p_user, 'member');
  end if;

  return v_group_id;
end $$;

revoke all on function public.assign_pilot_cohort(uuid) from public, anon, authenticated;
grant execute on function public.assign_pilot_cohort(uuid) to service_role;

insert into public.pilot_cohorts (name, timezone, reveal_hour, capacity, position, enabled)
values ('Initial TestFlight', 'America/Los_Angeles', 20, 12, 1, false);
