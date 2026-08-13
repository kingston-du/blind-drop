-- Make the sliding-window limiter atomic per bucket and give every event an explicit expiry.
--
-- 0011 counted and inserted in separate statements. Concurrent requests could all observe the
-- same below-limit count and then all insert, admitting more than the configured limit. It also
-- only removed expired rows when that exact bucket was used again, so inactive hashed-IP buckets
-- lived indefinitely despite the documented one-hour retention bound.

alter table public.rate_limit_events
  add column expires_at timestamptz;

-- Existing windows are at most one hour. Keeping old rows for that full bound is conservative:
-- it may throttle briefly longer, but never weakens an existing limit during deployment.
update public.rate_limit_events
   set expires_at = at + interval '1 hour';

alter table public.rate_limit_events
  alter column expires_at set not null,
  alter column expires_at set default (public.now_() + interval '1 hour');

create index rate_limit_events_expires_at
  on public.rate_limit_events (expires_at);

create or replace function public.consume_rate_limit(
  p_bucket text,
  p_limit  int,
  p_window interval
) returns int
language plpgsql
as $$
declare
  v_now    timestamptz := public.now_();
  v_count  int;
  v_oldest timestamptz;
begin
  if p_bucket = '' or p_limit < 1 or p_window <= interval '0 seconds' then
    raise exception 'invalid rate-limit parameters' using errcode = '22023';
  end if;

  -- Serialize the count-and-insert transaction for this bucket. Hash collisions only serialize
  -- unrelated buckets; they cannot allow an extra request through.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bucket, 0));

  -- Explicit expiries let activity in any bucket enforce the retention bound for every bucket.
  delete from public.rate_limit_events where expires_at <= v_now;

  select count(*), min(at) into v_count, v_oldest
    from public.rate_limit_events where bucket = p_bucket;

  if v_count >= p_limit then
    return greatest(1, ceil(extract(epoch from (v_oldest + p_window - v_now)))::int);
  end if;

  insert into public.rate_limit_events (bucket, at, expires_at)
  values (p_bucket, v_now, v_now + p_window);
  return 0;
end $$;

comment on function public.consume_rate_limit(text, int, interval) is
  'Atomic sliding-window limiter. Returns 0 if allowed, else seconds to wait. Buckets are per '
  'user or per hashed IP, never per group (docs/04 §8).';

-- Retention must not depend on the same address ever returning. Keep the cleanup under the
-- existing scheduler toggle so local dated fixtures stay deterministic.
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
    'links', v_schedule,
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

select public.set_blind_drop_jobs_active(true);
