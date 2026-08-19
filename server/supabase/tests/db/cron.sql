-- cron.sql — tasks/E03-05, docs/05 §1.
begin;
set search_path = public, extensions, tests;
select plan(26);

select has_function('public', 'set_blind_drop_jobs_active', array['boolean'],
                    'the scoped scheduler toggle exists');
select is(
  (select p.prosecdef from pg_proc p
    where p.proname = 'set_blind_drop_jobs_active' and p.pronamespace = 'public'::regnamespace),
  true, 'the toggle can update cron.job without granting table access');
select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p
    where p.proname = 'set_blind_drop_jobs_active' and p.pronamespace = 'public'::regnamespace),
  'the security-definer toggle pins an empty search_path');
select ok(not has_function_privilege('service_role',
                 'public.set_blind_drop_jobs_active(boolean)', 'execute'),
          'the Edge Function service role cannot toggle scheduling');

select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push', 'links', 'rate-limit-retention')
              and schedule = '0 0 31 2 *'),
          4, 'the local seed parks every job on an impossible date');
select lives_ok('select public.set_blind_drop_jobs_active(true)',
                'an administrator can enable all four named jobs atomically');

select set_eq(
  $$ select jobname from cron.job
      where jobname in ('tick', 'push', 'links', 'rate-limit-retention') $$,
  $$ values ('tick'::text), ('push'::text), ('links'::text), ('rate-limit-retention'::text) $$,
  'exactly the four named Blind Drop jobs are registered');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push', 'links', 'rate-limit-retention')
              and schedule = '* * * * *'),
          4, 'all four jobs run every minute');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push', 'links', 'rate-limit-retention') and active),
          4, 'every registered job row remains active after restoring the minute schedule');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push', 'links', 'rate-limit-retention')
              and database = current_database() and username = current_user),
          4, 'all four jobs run in this database as the migration owner');

select ok((select command like '%select public.tick_rounds();%'
             from cron.job where jobname = 'tick'),
          'tick invokes the one scheduler entrypoint');
select ok((select command not like '%ensure_rounds%'
             from cron.job where jobname = 'tick'),
          'ensure_rounds is not a third job or a second cron call');

select ok((select command like '%net.http_post(%'
             from cron.job where jobname = 'push'), 'push drains through pg_net');
select ok((select command like '%vault.decrypted_secrets%blind_drop_functions_url%'
             from cron.job where jobname = 'push'),
          'the function host comes from a Vault secret, never a literal');
select ok((select command like '%|| ''/push-worker''%'
             from cron.job where jobname = 'push'), 'push targets the push-worker function');
select ok((select command like '%vault.decrypted_secrets%blind_drop_service_key%'
             from cron.job where jobname = 'push'),
          'authorization comes from a Vault secret, never a literal');
select ok((select command like '%''Authorization''%''Bearer ''%'
             from cron.job where jobname = 'push'), 'push sends service-role bearer auth');
select ok((select command like '%''Content-Type''%''application/json''%'
             from cron.job where jobname = 'push'), 'push sends a JSON request');
select ok((select command not like '%http%://%'
             from cron.job where jobname = 'push'), 'no environment URL is embedded in cron.job');
select ok((select command not like '%eyJ%'
             from cron.job where jobname = 'push'), 'no JWT-shaped service key is embedded in cron.job');

-- ─── the Spotify backfill — tasks/E07-05, docs/06 §5 ─────────────────────────
-- Same shape as `push`, deliberately: it is the same mechanism doing the same job for a
-- different worker, and a second way of writing it would be a second way of getting the
-- secrets handling wrong.

select ok((select command like '%net.http_post(%'
             from cron.job where jobname = 'links'), 'the backfill drains through pg_net');
select ok((select command like '%|| ''/links-worker''%'
             from cron.job where jobname = 'links'), 'links targets the links-worker function');
select ok((select command like '%vault.decrypted_secrets%blind_drop_functions_url%'
             and command like '%vault.decrypted_secrets%blind_drop_service_key%'
             from cron.job where jobname = 'links'),
          'its host and key come from Vault secrets, like push''s');
select ok((select command not like '%http%://%' and command not like '%eyJ%'
             from cron.job where jobname = 'links'),
          'and neither is embedded in cron.job');
select ok((select command not like '%tick_rounds%'
             from cron.job where jobname = 'links'),
          'the backfill cannot advance a round — a slow Spotify must never delay a reveal');

select ok((select command like '%delete from public.rate_limit_events%expires_at <= public.now_()%'
             from cron.job where jobname = 'rate-limit-retention'),
          'expired limiter rows are deleted even when their address never returns');

select * from finish();
rollback;
