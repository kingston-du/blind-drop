-- 0016_cron.sql — tasks/E03-05, docs/05 §1.
--
-- Named schedules are idempotent: cron.schedule(name, ...) updates the existing row when a
-- migration is replayed against a development database. Secrets and environment-specific
-- hosts are database settings, never migration literals or arguments visible in cron.job.

-- The local dated seed must pause these jobs without receiving UPDATE on cron.job. pg_cron
-- does not expose an active toggle, so false parks both named jobs on an impossible February
-- 31 schedule while retaining their commands; true restores the production every-minute
-- schedule. Calling cron.schedule(name, ...) updates rather than duplicates a named job.
create or replace function public.set_blind_drop_jobs_active(p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule text := case when p_active then '* * * * *' else '0 0 31 2 *' end;
begin
  perform cron.schedule(
    'tick',
    v_schedule,
    $job$ select public.tick_rounds(); $job$
  );

  perform cron.schedule(
    'push',
    v_schedule,
    $job$
      select net.http_post(
        url := current_setting('app.functions_url') || '/push-worker',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || current_setting('app.service_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      );
    $job$
  );
end;
$$;

alter function public.set_blind_drop_jobs_active(boolean) owner to postgres;
revoke all on function public.set_blind_drop_jobs_active(boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_blind_drop_jobs_active(boolean) to supabase_admin;

-- Hosted migrations stop here with live schedules. `seed.sql`, which is local-only, calls
-- the same scoped function with false after loading its dated fixture.
select public.set_blind_drop_jobs_active(true);
