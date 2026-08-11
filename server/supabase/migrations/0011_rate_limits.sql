-- 0011_rate_limits.sql — docs/04 §8, docs/14 §8. tasks/E02-01, E02-04.
--
-- Sliding-window rate limiting, in the database because the Edge Functions are stateless and
-- a per-worker counter would reset on every cold start.
--
-- **Buckets are keyed by user id or by hashed IP. Never by group.** A group-scoped counter
-- would let one member detect another member's activity by watching for throttling, which is
-- a real side channel on the blind window (docs/14 §3). The bucket string is built in
-- `_shared/auth.ts` and nothing in it is derived from group membership.
--
-- Retention: rows live for one window and are deleted by the next call on the same bucket.
-- The hashed IP is therefore held for at most an hour, which is what keeps IP addresses off
-- the collected-data list in docs/14 §9.

create table public.rate_limit_events (
  id      bigserial primary key,
  bucket  text        not null,
  at      timestamptz not null default public.now_()
);
create index rate_limit_events_bucket_at on public.rate_limit_events (bucket, at desc);

-- The same lockdown as every other table (0003_rls.sql).
alter table public.rate_limit_events enable row level security;
alter table public.rate_limit_events force row level security;
revoke all on public.rate_limit_events from anon, authenticated;
revoke all on sequence public.rate_limit_events_id_seq from anon, authenticated;

grant select, insert, delete on public.rate_limit_events to service_role;
grant usage on sequence public.rate_limit_events_id_seq to service_role;

-- ─── consume_rate_limit ──────────────────────────────────────────────────────
-- Returns 0 when the request is allowed (and records it), or the number of seconds until the
-- oldest event in the window ages out, which the handler returns as `Retry-After`.
--
-- Deliberately *not* `security definer`: it runs as its caller, which is `service_role`, and
-- `service_role` has BYPASSRLS. A definer function owned by `postgres` would be a second way
-- to reach these tables, which is exactly what `force row level security` in 0003 is trying
-- to prevent from existing.
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
  -- Only this bucket's expired rows: cheap, and it keeps the table's size proportional to
  -- current activity rather than to history.
  delete from public.rate_limit_events
   where bucket = p_bucket and at <= v_now - p_window;

  select count(*), min(at) into v_count, v_oldest
    from public.rate_limit_events where bucket = p_bucket;

  if v_count >= p_limit then
    return greatest(1, ceil(extract(epoch from (v_oldest + p_window - v_now)))::int);
  end if;

  insert into public.rate_limit_events (bucket, at) values (p_bucket, v_now);
  return 0;
end $$;

comment on function public.consume_rate_limit(text, int, interval) is
  'Sliding-window limiter. Returns 0 if allowed, else seconds to wait. Buckets are per user '
  'or per hashed IP, never per group (docs/04 §8).';

revoke all on function public.consume_rate_limit(text, int, interval) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(text, int, interval) to service_role;
