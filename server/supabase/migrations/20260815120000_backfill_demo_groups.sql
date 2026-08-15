-- 20260815120000_backfill_demo_groups.sql — reach the group that already exists.
--
-- `assign_pilot_cohort()` carries `pilot_cohorts.is_demo` onto the group it creates
-- (20260815090000), which is right for every cohort whose group is still to be made and wrong
-- for the one that matters: the App Review cohort's group was created on 2026-08-13, when the
-- review account first signed in, and a cohort flag set afterwards never reaches it. Deployed
-- as written, the demo environment would have been switched on for a group that does not
-- exist yet and left off for the one App Review actually uses.
--
-- Backfill, not a rewrite of 20260815090000: that migration is merged and forward-only
-- migrations are never edited (CLAUDE.md §4).
--
-- The `groups_propagate_is_demo_trg` from 20260815090000 fires on this update and carries
-- `is_demo` down to the group's existing rounds, so no separate statement is needed for them.
-- Those rounds all satisfy the strict ten-hour/two-hour window, which also satisfies the demo
-- branch of `rounds_window`, so the propagation cannot fail on them.

update public.groups g
   set is_demo = true
  from public.pilot_cohorts c
 where c.group_id = g.id
   and c.is_demo
   and not g.is_demo;
