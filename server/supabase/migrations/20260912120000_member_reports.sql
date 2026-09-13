-- E45-01 — a member can report a member.
--
-- App Review's guideline 1.2 asks an app carrying user-generated content for a way to report it.
-- Blind Drop's user-generated content is a display name and a hand-written cue, so what gets
-- reported is a *person in a circle*, not a song and never a round. Nothing here references
-- `rounds` or `submissions`, which is what keeps `CLAUDE.md` §2.1 out of this feature entirely:
-- a report can be raised, stored and read without any part of it knowing what phase it is.
--
-- Rows are server-only, like `pilot_cohorts`. The Edge Function writes with the service role and
-- the owner reads with it; nobody reaches this table from a client, so a report can never be
-- enumerated by the person it is about.
create table public.member_reports (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  reported_id  uuid not null references public.profiles(id) on delete cascade,
  reason       text not null check (reason in ('display_name', 'cue', 'harassment', 'other')),
  created_at   timestamptz not null default now(),
  -- Reporting yourself is meaningless, and the route refuses it first. The constraint is the
  -- second lock, in the same spirit as RLS behind the function's own authorization.
  constraint member_reports_not_self check (reporter_id <> reported_id)
);

-- One report per reporter, per target, per day. A unique index rather than a read-then-write,
-- so two taps racing each other cannot both land — the handler treats the conflict as success.
--
-- The day is pinned to UTC explicitly. A bare `created_at::date` reads the session's `TimeZone`,
-- which makes the expression non-immutable and is rejected outright at index creation; naming the
-- zone also means the window cannot quietly move under a connection with a different setting.
create unique index member_reports_daily_unique
  on public.member_reports (reporter_id, reported_id, ((created_at at time zone 'UTC')::date));

-- What the owner actually reads: newest first, scoped to a circle.
create index member_reports_group_recent
  on public.member_reports (group_id, created_at desc);

alter table public.member_reports enable row level security;
alter table public.member_reports force row level security;

comment on table public.member_reports is
  'Server-only UGC reports raised by one member against another (E45-01). No round state.';

revoke all on table public.member_reports from public, anon, authenticated;
grant select, insert, delete on table public.member_reports to service_role;
