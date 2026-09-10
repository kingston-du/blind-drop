-- 20260909140000_leaderboard_window.sql — Best Ear becomes a count over a moving window.
--
-- Owner change to docs/02 §4.2. Best Ear used to rank on `ear_all_time`, a pooled rate, and a
-- rate cannot express the thing the leaderboard was always meant to say. Two failures, both
-- visible in a real circle:
--
--   1. **A thin record wins.** One round guessed perfectly is 100% and tops a veteran's 62%.
--   2. **Absence is free.** §4.1 drops a zero-guess round from *both* sums, so a member is only
--      ever measured on the nights they chose to be measured. Someone who plays five nights a
--      month outranks someone who plays thirty, and no amount of arithmetic on a rate fixes
--      that, because the missing nights are missing by choice.
--
-- 0005's own header says ear pools "because Best Ear is a leaderboard and should reward
-- volume". That reasoning never held: pooling reweights by *round size*, not by *number of
-- rounds*, so it is still a rate and still says nothing about turning up. `ear_reads` is what
-- that sentence was reaching for.
--
--   ear_reads = correct guesses over the group's last 14 scored rounds
--
-- The window is **the group's** last 14 rounds, not the member's. That is the whole mechanism:
-- a night you skipped is inside everyone's window and you scored nothing for it. Scoped to the
-- member instead, selective participation walks straight back in.
--
-- `coalesce(ear_correct, 0)` rather than 0005's `filter (where ear is not null)` is the other
-- half. The NULL-not-zero rule exists because a *rate* has no way to say "wasn't there"; a
-- count does, and it is zero. NULL still means what it always meant everywhere else — every
-- other column here is untouched, and `ear_all_time` keeps the exception intact for the
-- per-round and profile surfaces that still show a rate.
--
-- Readability stays all-time and unwindowed on purpose. It is a spectrum, not a ranking
-- (docs/02 §4.5), and a band that flickered between "Legible" and "Elusive" with a fortnight's
-- weather would read as a score going up and down.

-- Appended, never reordered: `create or replace view` requires the existing columns to keep
-- their names, types and positions, and every consumer selects by name anyway.
create or replace view public.standings as
  with recent as (
    -- Built on `round_submitter_counts`, not `rounds`, so the window inherits exactly the
    -- universe every other number on the page is computed over: scored rounds only, voided and
    -- revealed ones absent by construction (0005 §"S, and S − 1"). `round_id` breaks a tie on
    -- `local_date` so the ordering is total and the 14th round is never ambiguous.
    select rsc.round_id,
           row_number() over (
             partition by rsc.group_id
             order by rsc.local_date desc, rsc.round_id desc
           ) as recency
      from public.round_submitter_counts rsc
  )
  select rs.group_id,
         rs.user_id,
         count(*)                                             as rounds_played,

         sum(rs.ear_correct) filter (where rs.ear is not null) as ear_correct_total,
         sum(rs.possible)    filter (where rs.ear is not null) as ear_possible_total,
         case when sum(rs.possible) filter (where rs.ear is not null) > 0
              then sum(rs.ear_correct) filter (where rs.ear is not null)::numeric
                   / sum(rs.possible)  filter (where rs.ear is not null)
         end                                                  as ear_all_time,
         count(*) filter (where rs.ear is not null)           as ear_rounds,

         avg(rs.readability)                                  as readability_all_time,

         case
           when avg(rs.readability) >= 0.80 then 'open_book'
           when avg(rs.readability) >= 0.60 then 'legible'
           when avg(rs.readability) >= 0.40 then 'mixed_signals'
           when avg(rs.readability) >= 0.20 then 'hard_to_place'
           else 'unreadable'
         end                                                  as band,

         -- The ranked figure. Zero, not NULL, for a member who was in the window and named
         -- nobody: on a count that is the honest number, and it is the one the board sorts on.
         coalesce(
           sum(coalesce(rs.ear_correct, 0)) filter (where w.recency <= 14),
           0
         )::bigint                                            as ear_reads
    from public.round_scores rs
    left join recent w on w.round_id = rs.round_id
   group by rs.group_id, rs.user_id;

comment on view public.standings is
  'Per group. ear_reads is the ranked figure: correct guesses over the group''s last 14 scored '
  'rounds, counting a skipped night as zero (docs/02 §4.2). ear_all_time stays a pooled rate '
  'over rounds the member guessed in, for the profile and per-round surfaces. readability is a '
  'mean of per-round rates, all-time and deliberately unwindowed — it is a spectrum, not a rank.';
