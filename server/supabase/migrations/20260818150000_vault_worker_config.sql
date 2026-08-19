-- Hosted Supabase does not permit arbitrary `app.*` GUCs at the role or database
-- level. Keep the Edge worker endpoint and authorization key in Vault instead;
-- they never appear in this migration or in cron.job's command text.
--
-- Operator setup (once per hosted project):
--   select vault.create_secret('<service-role key>', 'blind_drop_service_key');
--   select vault.create_secret('<functions base URL>', 'blind_drop_functions_url');
-- The names are intentionally stable so rotation is `vault.update_secret`, without
-- rescheduling jobs or writing a key to source control.

create or replace function public.set_blind_drop_jobs_active(p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule text := case when p_active then '* * * * *' else '0 0 31 2 *' end;
begin
  perform cron.schedule('tick', v_schedule, $job$ select public.tick_rounds(); $job$);

  perform cron.schedule(
    'push', v_schedule,
    $job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets
                 where name = 'blind_drop_functions_url') || '/push-worker',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                           where name = 'blind_drop_service_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      );
    $job$
  );

  perform cron.schedule(
    'links', v_schedule,
    $job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets
                 where name = 'blind_drop_functions_url') || '/links-worker',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                           where name = 'blind_drop_service_key'),
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb
      );
    $job$
  );

  perform cron.schedule(
    'rate-limit-retention', v_schedule,
    $job$
      delete from public.rate_limit_events
       where expires_at <= public.now_();
    $job$
  );
end;
$$;

alter function public.set_blind_drop_jobs_active(boolean) owner to postgres;
revoke all on function public.set_blind_drop_jobs_active(boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_blind_drop_jobs_active(boolean) to supabase_admin;

-- Rewrites existing named jobs in place.
select public.set_blind_drop_jobs_active(true);
