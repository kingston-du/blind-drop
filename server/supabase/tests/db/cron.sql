-- cron.sql — tasks/E03-05, docs/05 §1.
begin;
set search_path = public, extensions, tests;
select plan(20);

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
            where jobname in ('tick', 'push') and schedule = '0 0 31 2 *'),
          2, 'the local seed parks both jobs on an impossible date');
select lives_ok('select public.set_blind_drop_jobs_active(true)',
                'an administrator can enable both named jobs atomically');

select set_eq(
  $$ select jobname from cron.job where jobname in ('tick', 'push') $$,
  $$ values ('tick'::text), ('push'::text) $$,
  'exactly the two named Blind Drop jobs are registered');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push') and schedule = '* * * * *'),
          2, 'both jobs run every minute');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push') and active),
          2, 'both registered job rows remain active after restoring the minute schedule');
select is((select count(*)::int from cron.job
            where jobname in ('tick', 'push')
              and database = current_database() and username = current_user),
          2, 'both jobs run in this database as the migration owner');

select ok((select command like '%select public.tick_rounds();%'
             from cron.job where jobname = 'tick'),
          'tick invokes the one scheduler entrypoint');
select ok((select command not like '%ensure_rounds%'
             from cron.job where jobname = 'tick'),
          'ensure_rounds is not a third job or a second cron call');

select ok((select command like '%net.http_post(%'
             from cron.job where jobname = 'push'), 'push drains through pg_net');
select ok((select command like '%current_setting(''app.functions_url'')%'
             from cron.job where jobname = 'push'),
          'the function host comes from a database setting');
select ok((select command like '%|| ''/push-worker''%'
             from cron.job where jobname = 'push'), 'push targets the push-worker function');
select ok((select command like '%current_setting(''app.service_key'')%'
             from cron.job where jobname = 'push'),
          'authorization comes from a database setting');
select ok((select command like '%''Authorization''%''Bearer ''%'
             from cron.job where jobname = 'push'), 'push sends service-role bearer auth');
select ok((select command like '%''Content-Type''%''application/json''%'
             from cron.job where jobname = 'push'), 'push sends a JSON request');
select ok((select command not like '%http%://%'
             from cron.job where jobname = 'push'), 'no environment URL is embedded in cron.job');
select ok((select command not like '%eyJ%'
             from cron.job where jobname = 'push'), 'no JWT-shaped service key is embedded in cron.job');

select * from finish();
rollback;
