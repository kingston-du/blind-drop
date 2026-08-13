-- rls.sql — tasks/E01-02, AC-1. docs/03 §3, docs/01 §2, docs/14 §4.
--
-- Deny-by-default on every table and *no policies*. The HTTP half of this (an
-- authenticated PostgREST call to each table returning no row) is
-- tests/functions/postgrest_locked.test.ts; what is provable in SQL is proved here.
begin;
set search_path = public, extensions, tests;
select plan(52);

-- ─── RLS is on, and forced, everywhere ───────────────────────────────────────
select ok(c.relrowsecurity, format('%I has row level security enabled', c.relname))
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

select ok(c.relforcerowsecurity, format('%I forces RLS for the owner too', c.relname))
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'),
  11,
  'exactly eleven tables in public — nothing has been added without a doc change');

-- ─── zero policies. Not "the right policies". Zero. ──────────────────────────
select is_empty($$
  select schemaname || '.' || tablename || ' :: ' || policyname
  from pg_policies where schemaname = 'public'
$$, 'no RLS policies exist in public (docs/03 §3 — do not add convenience policies)');

-- ─── the revokes ─────────────────────────────────────────────────────────────
-- No privilege of any kind, on any table, for either client-facing role.
select is_empty($$
  select grantee || ' has ' || privilege_type || ' on ' || table_name
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon','authenticated')
$$, 'anon and authenticated hold no table privilege in public');

select is_empty($$
  select grantee || ' has ' || privilege_type || ' on sequence ' || object_name
  from information_schema.role_usage_grants
  where object_schema = 'public' and grantee in ('anon','authenticated')
$$, 'anon and authenticated hold no sequence privilege in public');

select is_empty($$
  select grantee || ' can execute ' || routine_name
  from information_schema.role_routine_grants
  where routine_schema = 'public' and grantee in ('anon','authenticated')
$$, 'anon and authenticated can execute nothing in public — including now_()');

-- Default privileges: a table added by a later migration inherits the lockdown.
--
-- Scoped to grantor `postgres`, which is the role migrations run as and therefore the only
-- one whose defaults this repo can set. Supabase's platform role `supabase_admin` also holds
-- default grants to anon/authenticated in `public`, and `postgres` is refused when it tries
-- to revoke them ("permission denied to change default privileges"). Nothing here creates an
-- object as supabase_admin, config.toml sets `auto_expose_new_tables = false`, and the
-- authenticated-PostgREST sweep in E14-01 is the backstop that would catch it if that ever
-- stopped being true.
select is_empty($$
  select defaclobjtype::text || ' -> ' || defaclacl::text
  from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
  where n.nspname = 'public'
    and d.defaclrole = 'postgres'::regrole
    and array_to_string(d.defaclacl, ',') ~ '\m(anon|authenticated)='
$$, 'default privileges set by postgres grant nothing to anon or authenticated');

-- ─── and the lock actually holds ─────────────────────────────────────────────
-- Read each table as `authenticated`. Every one must fail closed.
select throws_ok(
         format('select 1 from public.%I limit 1', t),
         '42501',
         format('permission denied for table %s', t),
         format('authenticated cannot read %I', t))
from unnest(array['profiles','groups','memberships','rounds','submissions','guesses',
                  'devices','notification_outbox','track_links','rate_limit_events',
                  'pilot_cohorts']) as t,
     lateral (select set_config('role', 'authenticated', true)) as _;
reset role;

select throws_ok(
         format('select 1 from public.%I limit 1', t),
         '42501',
         format('permission denied for table %s', t),
         format('anon cannot read %I', t))
from unnest(array['profiles','groups','memberships','rounds','submissions','guesses',
                  'devices','notification_outbox','track_links','rate_limit_events',
                  'pilot_cohorts']) as t,
     lateral (select set_config('role', 'anon', true)) as _;
reset role;

-- Writes too — a leak is not only a read.
set local role authenticated;
select throws_ok(
  $$ insert into public.submissions (round_id, user_id, track_key, track_meta)
     values (gen_random_uuid(), gen_random_uuid(), 'isrc:X', '{}'::jsonb) $$,
  '42501', null, 'authenticated cannot insert a submission');
select throws_ok(
  $$ update public.rounds set state = 'revealed' $$,
  '42501', null, 'authenticated cannot move a round to revealed');
reset role;

select * from finish();
rollback;
