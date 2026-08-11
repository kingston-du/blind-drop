-- 0004_round_lifecycle.sql — docs/03 §4, docs/02 §1. tasks/E03-01 (and E03-02..E03-04).
--
-- The two functions that make the game happen on time. Both are `security definer` owned by
-- `postgres` (docs/03 §4), and every clock reference in them is `public.now_()`, never
-- `now()` — that indirection is the whole reason the pgTAP suite can simulate a fortnight
-- without a single sleep (tasks/E01-05).
--
-- `security definer` and `set search_path = ''` are one decision, not two: a definer function
-- with a mutable search_path is a privilege-escalation hole, so every reference below is
-- schema-qualified and the path is empty. `pg_catalog` is still searched implicitly, which is
-- how `timezone`, `make_interval` and `unnest` resolve.
--
-- Note that 0003 turned on `force row level security` with zero policies, explicitly so that
-- "a future security definer function owned by postgres cannot become an accidental bypass".
-- These functions read and write `rounds` regardless, because the owner carries BYPASSRLS.
-- If that ever stops being true the scheduler becomes a silent no-op rather than an error,
-- which is why tests/db/ensure_rounds_timezones.sql asserts the owner's BYPASSRLS bit
-- directly instead of trusting it.

-- ─── ensure_rounds ───────────────────────────────────────────────────────────
-- Idempotently materialises today's and tomorrow's round for every group (docs/03 §4).
--
-- Two days and no more. A group's offset from UTC is only correct for a *specific local
-- date* (docs/02 §1, "DST"), so a round materialised a week out would be an hour wrong on
-- one side of a transition. Two days is the shortest horizon that still lets a round exist
-- before its own `opens_at`, and short enough that the offset used is the offset that will
-- apply on the day.
--
-- Failure is per group, not per tick. docs/05 §6 wants a group whose timezone has become
-- unusable skipped and logged while the loop continues: one group with a bad `timezone` must
-- not stop a thousand reveals. `public.timezone_is_valid()` (0012) keeps such a value out via
-- the API, but the column has no DB constraint and tzdata itself changes, so the handler is
-- the second lock here, not the only one.
create or replace function public.ensure_rounds()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now   timestamptz := public.now_();
  v_group record;
  v_today date;
begin
  for v_group in
    select g.id, g.timezone, g.reveal_hour
      from public.groups g
     order by g.id          -- deterministic, so a warning in the log names a stable order
  loop
    -- A subtransaction per group. That is the cost of isolating one broken timezone from
    -- every other group's evening, and it is the right price.
    begin
      -- docs/02 §1: the local date is resolved *through the zone*, never through a stored
      -- offset. timezone(text, timestamptz) -> timestamp is the only correct spelling; a
      -- fixed `at time zone '-05:00'` would be wrong for half the year.
      v_today := pg_catalog.timezone(v_group.timezone, v_now)::date;

      insert into public.rounds
             (group_id, local_date, state, opens_at, reveals_at, scores_at)
      select v_group.id,
             d.local_date,
             'open',                          -- spelled out: a round is born open (docs/02 §1)
             -- Computed on the *instant*, not on the wall clock. `rounds_window` (0002)
             -- compares timestamptz, and 10:00 local on a spring-forward date is not
             -- `reveals_at - 10h`. Materialise the reveal once, then subtract in UTC or the
             -- insert fails 23514 on exactly the dates this function exists to get right.
             d.reveals_at - interval '10 hours',
             d.reveals_at,
             d.reveals_at + interval '2 hours'
        from (
          select t.ld as local_date,
                 -- The UTC instant of reveal_hour:00 group-local ON that local date.
                 -- timezone(text, timestamp) -> timestamptz picks the offset in force for
                 -- that date, which is the entire point of doing it per date per day.
                 pg_catalog.timezone(
                   v_group.timezone,
                   t.ld + pg_catalog.make_interval(hours => v_group.reveal_hour)) as reveals_at
            from pg_catalog.unnest(array[v_today, v_today + 1]) as t(ld)
        ) d
       -- See the open question in tasks/E03: a round whose reveal is already behind us is
       -- never created. It suppresses creation only — it can neither re-time nor remove a
       -- round that already exists, so the cron-outage path in docs/05 §6 is untouched.
       where d.reveals_at > v_now
      -- An existing round is never re-timed. A `reveal_hour` change therefore lands on the
      -- first not-yet-created round (docs/02 §1, docs/03 §4) — that is the product rule,
      -- stated here as a conflict clause rather than enforced by one.
      on conflict (group_id, local_date) do nothing;

    exception when others then
      -- docs/05 §6: log it against the group and carry on. Swallowing the sqlstate would
      -- make an unusable timezone indistinguishable from a group with no rounds due.
      raise warning 'ensure_rounds: group % skipped (%): %',
                    v_group.id, sqlstate, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.ensure_rounds() is
  'Idempotently materialises today''s and tomorrow''s round for every group (docs/03 §4). '
  'Two days only, so the DST offset used is never stale; on conflict do nothing, so an '
  'existing round is never re-timed and a reveal_hour change lands on the first uncreated '
  'round. A group with an unusable timezone is skipped with a warning and the loop '
  'continues (docs/05 §6).';

-- ─── tick_rounds ─────────────────────────────────────────────────────────────
-- E03-02 (reveal/void), E03-03 (score/nudge) and E03-04 (the card_order shuffle) land here.
-- It calls ensure_rounds() at the top rather than running as a separate cron job (docs/03
-- §4), so a group created two minutes ago has a round before it has a transition.

-- ─── who may call these ──────────────────────────────────────────────────────
-- 0003 revoked execute from anon and authenticated by default privilege, but not from
-- `public`, and PUBLIC holds EXECUTE on every new function. Say it explicitly.
revoke all on function public.ensure_rounds() from public, anon, authenticated;

-- ensure_rounds() can only create rounds; it can never advance one, and it is idempotent, so
-- the worst a caller can do with it is nothing. The API legitimately wants it after a group
-- is created (docs/04 §3) rather than making the first member wait up to a minute.
grant execute on function public.ensure_rounds() to service_role;
