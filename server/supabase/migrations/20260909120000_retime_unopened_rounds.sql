-- 20260909120000_retime_unopened_rounds.sql — docs/02 §1, docs/03 §4.
--
-- **Owner amendment, 2026-09-09.** `docs/02` §1 has always said a `reveal_hour` change "takes
-- effect from the **next** round". `ensure_rounds()` materialises today's *and* tomorrow's, so
-- in practice "the next round" meant the round after next: an admin who moved the hour at
-- 21:00 was told to wait two nights. `docs/03` §4 wrote that down as acceptable. The owner's
-- reading is that it never was — it is a consequence of the two-day horizon, not a product
-- decision, and the copy it forced ("which can be two nights away") was a hedge covering an
-- implementation detail no member should have to know about.
--
-- So the rule narrows to what it was always trying to say: **a change never touches a round
-- that has already opened.** Everything ahead of `opens_at` is re-timed.
--
-- This is not new ground. `rewrite_open_round_cues()` (20260827120000) already rewrites the cue
-- on exactly this set of rounds, for exactly this reason — "a change never reaches a round
-- somebody may already have sealed against" — and `demo_tick()` already moves `reveals_at` on a
-- round that exists. What was missing was the reveal hour doing the same.
--
-- **Why there is no notification cleanup here.** Every round push is enqueued lazily by
-- `tick_rounds()` when its window arrives — `reveals_at <= now + 2h` for the first
-- `seal_reminder`, `<= now + 30m` for the second, `<= now` for the reveal
-- (20260826120100_conditional_reminders.sql). A round that has not opened is at least ten hours
-- from its reveal, so its outbox is empty by construction and moving it schedules nothing that
-- needs unscheduling. If a push is ever pre-enqueued at round creation, this function has to
-- move those rows too, and that is the line to read first.
--
-- **Moving the hour earlier can open a round immediately, and that is the intended answer.**
-- `rounds_window` (0002) requires `opens_at = reveals_at - 10h` exactly, so there is no clamp
-- available here even in principle: the window moves with the reveal or the row does not commit.
-- Concretely, an admin who drops 21:00 to 18:00 at 10:59 local turns a round that was going to
-- open at 11:00 into one that opened at 08:00 — so it is open the moment the PATCH returns, and
-- the drop window is eight hours rather than ten. That is what "the reveal moved earlier" means
-- for the day it moved. The alternative — holding the round shut until an opens_at that no
-- longer matches its own reveal — would be the strange one. Bounded by the 18…21 range: the
-- most a round can lose this way is the three hours between the ends of it.
--
-- `ensure_rounds()` is untouched: it still refuses to re-time on conflict. Creation and
-- re-timing stay separate operations, so a cron outage still cannot rewrite a round's clock
-- (docs/05 §6) — only an admin's explicit change can.

create or replace function public.retime_unopened_rounds(p_group_id uuid)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group     record;
  v_effective date;
begin
  select g.timezone, g.reveal_hour, g.is_demo into v_group
    from public.groups g
   where g.id = p_group_id;
  if not found then
    return null;
  end if;

  -- A demo circle's clock belongs to `demo_tick()`, which recomputes `reveals_at` from the
  -- reviewer's actions rather than from the wall clock (docs/02 §11). Its rounds are also
  -- always already open — `opens_at = least(reveals_at - 10h, now)` since 20260815130000 — so
  -- the gate below would exclude them anyway. Said out loud rather than left to that accident.
  if v_group.is_demo then
    return null;
  end if;

  -- Computed on the *instant*, per local date, for the same reason `ensure_rounds()` does it
  -- that way: 10:00 local on a spring-forward date is not `reveals_at - 10h`, and materialising
  -- the reveal first is what keeps the `rounds_window` check (0002) satisfied on exactly the
  -- dates this arithmetic exists to get right.
  update public.rounds r
     set reveals_at = d.reveals_at,
         opens_at   = d.reveals_at - interval '10 hours',
         scores_at  = d.reveals_at + interval '2 hours'
    from (
      select r2.id,
             pg_catalog.timezone(
               v_group.timezone,
               r2.local_date + pg_catalog.make_interval(hours => v_group.reveal_hour)
             ) as reveals_at
        from public.rounds r2
       where r2.group_id = p_group_id
         and r2.state = 'open'
         and r2.opens_at > public.now_()
    ) d
   where r.id = d.id;

  -- The earliest date now running on the current hour. Read *after* the update, so it names a
  -- round that has actually been re-timed rather than one that is about to be.
  select pg_catalog.min(r.local_date) into v_effective
    from public.rounds r
   where r.group_id = p_group_id
     and r.state = 'open'
     and r.reveals_at > public.now_()
     -- `date_part`, not `extract(hour from ...)`: the SQL-standard `EXTRACT` spelling cannot
     -- be schema-qualified, and this function pins an empty search_path.
     and pg_catalog.date_part(
           'hour', pg_catalog.timezone(v_group.timezone, r.reveals_at)
         )::int = v_group.reveal_hour;

  return v_effective;
end $$;

comment on function public.retime_unopened_rounds(uuid) is
  'Re-times every round of a group that has not yet opened to the group''s current reveal_hour, '
  'and returns the earliest date now running on it (null when none). Called by the reveal_hour '
  'PATCH path (docs/02 §1, owner amendment 2026-09-09): a change never reaches a round somebody '
  'may already have sealed against, and never waits longer than that. Demo circles are skipped; '
  'their clock belongs to demo_tick().';

revoke all on function public.retime_unopened_rounds(uuid)
  from public, anon, authenticated;
grant execute on function public.retime_unopened_rounds(uuid) to service_role;
