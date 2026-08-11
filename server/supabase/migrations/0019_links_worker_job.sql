-- 0019_links_worker_job.sql — tasks/E07-05, docs/06 §5, docs/05 §1.
--
-- docs/06 §5 puts the Spotify backfill "inside `tick_rounds()`'s minute". It cannot literally
-- be inside `tick_rounds()`: that function is plpgsql running under pg_cron, and the backfill
-- needs an OAuth token, an HTTPS call to Spotify and a JSON response parsed — none of which
-- belong in a database function, and all of which would put a network round trip inside the
-- transaction that moves rounds between phases. A scheduler that could be held up by Spotify
-- being slow is a scheduler that can miss a reveal.
--
-- So it is a sibling job on the same every-minute schedule, draining `links-worker` through
-- pg_net exactly as `push` drains `push-worker`. Same shape, same secrets handling, same
-- reasoning: the host and the service key come from database settings, never from a literal in
-- `cron.job` where anyone with `select` on the catalog could read them.
--
-- This replaces `set_blind_drop_jobs_active` (0016) rather than adding a second toggle, because
-- `seed.sql` calls it with `false` to park the schedule for local test runs and a job it did not
-- know about would keep running against the dated fixture — advancing rounds under a suite that
-- assumes they stand still.

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

  perform cron.schedule(
    'links',
    v_schedule,
    $job$
      select net.http_post(
        url := current_setting('app.functions_url') || '/links-worker',
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

-- Live on a hosted database; `seed.sql` parks all three locally, as it already did for two.
select public.set_blind_drop_jobs_active(true);
