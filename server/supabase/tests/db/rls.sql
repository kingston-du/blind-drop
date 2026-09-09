-- rls.sql — tasks/E01-02, AC-1. docs/03 §3, docs/01 §2, docs/14 §4.
--
-- Deny-by-default on every table and *no policies*. The HTTP half of this (an
-- authenticated PostgREST call to each table returning no row) is
-- tests/functions/postgrest_locked.test.ts; what is provable in SQL is proved here.
begin;
set search_path = public, extensions, tests;
-- Table count and every `unnest(array[...])` table list below grows by one whenever a table
-- lands: `invitations` (E20-01), `cue_catalog` (E35-02, `20260827120000_cues.sql`) — four new
-- assertions per table: one more row apiece in the two `pg_class`-driven RLS-enabled/forced
-- checks (automatic, no array to edit) and one more row apiece in the two hand-enumerated
-- read-denial checks below.
select plan(69);

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
  14,
  'exactly fourteen tables in public — nothing has been added without a doc change');

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

-- The service role is powerful, but not a database owner. Hosted projects must preserve the
-- verb-by-verb allowlist from 0010 instead of inheriting legacy blanket auto-grants.
select set_eq(
  $$ select table_name, privilege_type
       from information_schema.role_table_grants
      where table_schema = 'public' and grantee = 'service_role' $$,
  $$ values
       ('profiles', 'SELECT'), ('profiles', 'INSERT'), ('profiles', 'UPDATE'),
       ('groups', 'SELECT'), ('groups', 'INSERT'), ('groups', 'UPDATE'),
       ('memberships', 'SELECT'), ('memberships', 'INSERT'), ('memberships', 'UPDATE'),
       ('rounds', 'SELECT'),
       ('submissions', 'SELECT'), ('submissions', 'INSERT'), ('submissions', 'UPDATE'),
       ('guesses', 'SELECT'), ('guesses', 'INSERT'), ('guesses', 'UPDATE'),
       ('guesses', 'DELETE'),
       ('devices', 'SELECT'), ('devices', 'INSERT'), ('devices', 'UPDATE'),
       -- DELETE arrived with sign-out detaching its APNs token (20260814201956).
       ('devices', 'DELETE'),
       ('notification_outbox', 'SELECT'), ('notification_outbox', 'UPDATE'),
       ('track_links', 'SELECT'), ('track_links', 'INSERT'), ('track_links', 'UPDATE'),
       ('rate_limit_events', 'SELECT'), ('rate_limit_events', 'INSERT'),
       ('rate_limit_events', 'DELETE'),
       ('pilot_cohorts', 'SELECT'), ('pilot_cohorts', 'INSERT'),
       ('pilot_cohorts', 'UPDATE'), ('pilot_cohorts', 'DELETE'),
       ('round_submitter_counts', 'SELECT'), ('guess_results', 'SELECT'),
       ('round_scores', 'SELECT'), ('standings', 'SELECT'),
       -- E20-01 (20260819100000). No DELETE: an invitation only ever moves forward to a
       -- terminal status; nothing removes the row.
       ('invitations', 'SELECT'), ('invitations', 'INSERT'), ('invitations', 'UPDATE') $$,
  'service_role has exactly the table and view verbs used by Edge Functions');

select set_eq(
  $$ select object_name, privilege_type
       from information_schema.role_usage_grants
      where object_schema = 'public' and grantee = 'service_role' $$,
  $$ values ('rate_limit_events_id_seq'::information_schema.sql_identifier,
             'USAGE'::information_schema.character_data) $$,
  'service_role can use only the rate-limit sequence');

select set_eq(
  $$ select routine_name
       from information_schema.role_routine_grants
      where routine_schema = 'public' and grantee = 'service_role'
        -- These helpers are created by seed.sql after every migration. They never exist on a
        -- hosted database and are covered by the fixture tests that use them.
        and routine_name not in
            ('tick_rounds_at', 'set_membership_joined_at', 'make_demo_group',
             'seed_previous_round') $$,
  $$ values
       ('now_'::information_schema.sql_identifier),
       ('ensure_rounds'::information_schema.sql_identifier),
       ('tick_rounds'::information_schema.sql_identifier),
       ('timezone_is_valid'::information_schema.sql_identifier),
       ('create_group'::information_schema.sql_identifier),
       ('consume_rate_limit'::information_schema.sql_identifier),
       ('delete_account'::information_schema.sql_identifier),
       ('patch_track_meta_spotify'::information_schema.sql_identifier),
       ('upsert_submission'::information_schema.sql_identifier),
       ('claim_notification_outbox'::information_schema.sql_identifier),
       ('finish_notification_outbox'::information_schema.sql_identifier),
       ('release_notification_outbox'::information_schema.sql_identifier),
       -- E23-01: the outbox-health check (20260818140000), same posture as the three above.
       ('stuck_notifications'::information_schema.sql_identifier),
       ('assign_pilot_cohort'::information_schema.sql_identifier),
       -- The demo lifecycle (20260815090500). `demo_provision` is deliberately absent: it
       -- manufactures players and backdated rounds, and is owner-run only.
       ('demo_arm'::information_schema.sql_identifier),
       ('demo_tick'::information_schema.sql_identifier),
       -- ADR-011 (20260818090000). No Edge Function calls this directly — it is granted
       -- because `enforce_circle_cap`'s trigger body calls it, which is a real function call
       -- charged to the DML role's own privileges, unlike the trigger's own dispatch.
       ('active_circle_cap'::information_schema.sql_identifier),
       -- E20-01 (20260819100000). Pending invitations: create, accept (atomic with the
       -- membership insert, through the same circle-cap trigger above), decline.
       ('create_invitation'::information_schema.sql_identifier),
       -- E20-03. Called from create_invitation() to make the invitation and its budgeted
       -- notification one transaction; it is not exposed to either client-facing role.
       ('enqueue_invitation_notification'::information_schema.sql_identifier),
       ('accept_invitation'::information_schema.sql_identifier),
       ('decline_invitation'::information_schema.sql_identifier),
       -- E35-02 (20260827120000_cues.sql). Called by the cadence PATCH path after updating
       -- groups.cue_cadence; `cue_for_round` is deliberately absent — it is an internal
       -- helper reached only through the definer functions, never by a client RPC.
       ('rewrite_open_round_cues'::information_schema.sql_identifier),
       -- Owner amendment, 2026-09-09 (20260909120000). Called by the reveal_hour PATCH path
       -- after updating groups.reveal_hour, exactly as the cadence path calls the cue rewrite
       -- above. Admin-only is enforced in the Edge Function, which is why `authenticated` is
       -- absent here and asserted absent in retime_unopened_rounds.sql.
       ('retime_unopened_rounds'::information_schema.sql_identifier) $$,
  'service_role can execute exactly the RPC allowlist');

select is_empty($$
  select defaclobjtype::text || ' -> ' || defaclacl::text
  from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
  where n.nspname = 'public'
    and d.defaclrole = 'postgres'::regrole
    and array_to_string(d.defaclacl, ',') ~ '\mservice_role='
$$, 'future public objects are not auto-granted to service_role');

select is_empty($$
  select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and not coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
$$, 'every public function pins an empty search_path');

-- ─── and the lock actually holds ─────────────────────────────────────────────
-- Read each table as `authenticated`. Every one must fail closed.
select throws_ok(
         format('select 1 from public.%I limit 1', t),
         '42501',
         format('permission denied for table %s', t),
         format('authenticated cannot read %I', t))
from unnest(array['profiles','groups','memberships','rounds','submissions','guesses',
                  'devices','notification_outbox','track_links','rate_limit_events',
                  'pilot_cohorts','demo_companions','invitations','cue_catalog']) as t,
     lateral (select set_config('role', 'authenticated', true)) as _;
reset role;

select throws_ok(
         format('select 1 from public.%I limit 1', t),
         '42501',
         format('permission denied for table %s', t),
         format('anon cannot read %I', t))
from unnest(array['profiles','groups','memberships','rounds','submissions','guesses',
                  'devices','notification_outbox','track_links','rate_limit_events',
                  'pilot_cohorts','demo_companions','invitations','cue_catalog']) as t,
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
