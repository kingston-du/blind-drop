-- E45-01 — member reports are server-only, self-free, and one per target per day.
begin;
set search_path = public, extensions, tests;
select plan(9);

insert into auth.users (id) values
  ('45000000-0000-4000-8000-000000000001'),
  ('45000000-0000-4000-8000-000000000002');
insert into public.profiles (id, display_name) values
  ('45000000-0000-4000-8000-000000000001', 'Reporter'),
  ('45000000-0000-4000-8000-000000000002', 'Reported');
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values ('45000000-0000-4000-8000-0000000000aa', 'Report Circle', 'America/Los_Angeles', 20,
        'RPT45X', '45000000-0000-4000-8000-000000000001');

select has_table('public', 'member_reports', 'the reports table exists');

-- Deny-by-default is the second lock behind the Edge Function's own authorization
-- (`CLAUDE.md` §4). Nobody reaches this table from a client, so a report can never be
-- enumerated by the person it is about.
select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.member_reports'::regclass),
  'row level security is enabled and forced'
);
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'member_reports' and grantee in ('anon', 'authenticated', 'public')),
  0,
  'no client role holds any grant on the table'
);

insert into public.member_reports (group_id, reporter_id, reported_id, reason)
values ('45000000-0000-4000-8000-0000000000aa',
        '45000000-0000-4000-8000-000000000001',
        '45000000-0000-4000-8000-000000000002', 'display_name');
select is((select count(*)::int from public.member_reports), 1, 'a report is stored');

-- The one-per-day index. Two taps racing each other must not both land; the handler reads the
-- resulting 23505 as success rather than surfacing a failure the reporter cannot act on.
select throws_ok(
  $$insert into public.member_reports (group_id, reporter_id, reported_id, reason)
    values ('45000000-0000-4000-8000-0000000000aa',
            '45000000-0000-4000-8000-000000000001',
            '45000000-0000-4000-8000-000000000002', 'harassment')$$,
  '23505',
  null,
  'the same reporter cannot raise the same member twice in a day'
);

-- A different target on the same day is a different report, and must still land.
insert into auth.users (id) values ('45000000-0000-4000-8000-000000000003');
insert into public.profiles (id, display_name)
values ('45000000-0000-4000-8000-000000000003', 'Another');
insert into public.member_reports (group_id, reporter_id, reported_id, reason)
values ('45000000-0000-4000-8000-0000000000aa',
        '45000000-0000-4000-8000-000000000001',
        '45000000-0000-4000-8000-000000000003', 'cue');
select is((select count(*)::int from public.member_reports), 2,
  'a different target on the same day is a separate report');

-- Yesterday's report of the same person is not the conflict, so the window really is a day.
insert into public.member_reports (group_id, reporter_id, reported_id, reason, created_at)
values ('45000000-0000-4000-8000-0000000000aa',
        '45000000-0000-4000-8000-000000000001',
        '45000000-0000-4000-8000-000000000002', 'other', now() - interval '1 day');
select is((select count(*)::int from public.member_reports), 3,
  'the same pair can be reported again on another day');

select throws_ok(
  $$insert into public.member_reports (group_id, reporter_id, reported_id, reason)
    values ('45000000-0000-4000-8000-0000000000aa',
            '45000000-0000-4000-8000-000000000001',
            '45000000-0000-4000-8000-000000000001', 'other')$$,
  '23514',
  null,
  'reporting yourself is refused by the table as well as by the route'
);

select throws_ok(
  $$insert into public.member_reports (group_id, reporter_id, reported_id, reason)
    values ('45000000-0000-4000-8000-0000000000aa',
            '45000000-0000-4000-8000-000000000001',
            '45000000-0000-4000-8000-000000000002', 'because-i-said-so')$$,
  '23514',
  null,
  'a reason outside the closed set is refused'
);

select * from finish();
rollback;
