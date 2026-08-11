-- 0005_scoring.sql — docs/02 §4, docs/03 §5, ADR-004. tasks/E05-03.
--
-- **Scores are derived, never stored** (CLAUDE.md §2.8, ADR-004). Everything below is a view
-- over `guesses` × `submissions`, computed on read. There is no score column anywhere in the
-- schema and adding one is a product decision, not an optimisation: a stored score is a score
-- that can disagree with the rows it came from, and this game is small enough that it never
-- needs to.
--
-- Four views, each the input to the next:
--
--   round_submitter_counts   S per round, and the S−1 that every denominator uses
--   guess_results            one row per guess, with the duplicate rule applied
--   round_scores             readability and ear per user per round
--   standings                all-time, per group
--
-- The two subtleties, both of which a plausible-looking rewrite gets wrong:
--
--   1. **`ear` is NULL, not 0, when a user made no guesses** (docs/02 §4.1). Zero means "you
--      guessed and got none right"; NULL means "you sat this one out". The product refuses to
--      turn the second into the first, and every consumer must render NULL as "—".
--   2. **Ear pools; readability averages** (docs/02 §4.2). All-time ear is Σcorrect / Σpossible
--      across rounds; all-time readability is the mean of the per-round *rates*. That
--      asymmetry is deliberate — Best Ear is a leaderboard and should reward volume, while
--      readability is a character trait and should not be dominated by whichever round had the
--      most people in it. A single `avg()` in the wrong place silently conflates them, which
--      is why E05-06 asserts across rounds of three different sizes.

-- ─── S, and S − 1 ────────────────────────────────────────────────────────────
-- Only `scored` rounds. A `voided` round contributes to nothing, anywhere (docs/02 §4.2), and
-- a `revealed` round is not finished — its sheets are still being edited. Excluding them here
-- rather than in each consumer means no consumer can forget.

create view public.round_submitter_counts as
  select r.id            as round_id,
         r.group_id,
         r.local_date,
         count(s.id)     as submitter_count,
         -- The denominator for both rates: every *other* submitter. Guarded, because a
         -- division by zero here would take out the whole standings query for one odd round.
         nullif(count(s.id) - 1, 0) as denominator
    from public.rounds r
    join public.submissions s on s.round_id = r.id
   where r.state = 'scored'
   group by r.id, r.group_id, r.local_date;

comment on view public.round_submitter_counts is
  'S and S-1 per scored round. Voided and revealed rounds are absent by construction — '
  'docs/02 §4.2, "voided rounds are excluded from everything".';

-- ─── the duplicate rule ──────────────────────────────────────────────────────
-- docs/02 §4.3: a guess is correct iff **the guessed person did in fact submit that track this
-- round** — not iff they own the card. If Ana and Ben both dropped *Ribs*, naming either of
-- them on either card is correct, and that correct guess counts toward the guesser's ear *and*
-- toward the readability of the card's actual owner.
--
-- So correctness is an existence test against `(round_id, track_key)`, never an equality test
-- against the card's owner. The `submissions_round_trackkey` index (0002) is exactly this
-- join, which is what E05-03's `explain` check is about.

create view public.guess_results as
  select g.id                as guess_id,
         g.round_id,
         g.guesser_id,
         g.submission_id,
         g.guessed_user_id,
         card.user_id        as card_owner_id,
         card.track_key,
         exists (
           select 1
             from public.submissions dup
            where dup.round_id  = g.round_id
              and dup.user_id   = g.guessed_user_id
              and dup.track_key = card.track_key
         ) as is_correct
    from public.guesses g
    join public.submissions card on card.id = g.submission_id
    join public.round_submitter_counts rsc on rsc.round_id = g.round_id;

comment on view public.guess_results is
  'One row per guess in a scored round, with docs/02 §4.3 applied: correct iff the guessed '
  'person submitted that track_key this round, which is why duplicates are correct on either '
  'card. Never an equality test against the card owner.';

-- ─── per round, per user ─────────────────────────────────────────────────────
-- One row per submitter per scored round. A non-submitter has neither value for the round and
-- does not appear (docs/02 §4.1) — they have no card, so no readability, and they were not
-- allowed to guess, so no ear.

create view public.round_scores as
  with submitters as (
    select s.round_id, s.user_id, s.id as submission_id, rsc.group_id,
           rsc.local_date, rsc.submitter_count, rsc.denominator
      from public.submissions s
      join public.round_submitter_counts rsc on rsc.round_id = s.round_id
  ),
  -- Correct guesses landed *on* each submitter's card. The denominator is S−1 regardless of
  -- who actually guessed: docs/02 §4.1 is explicit that a submitter who never opened the sheet
  -- counts as a miss against everyone's readability, because "a room that didn't look is a
  -- room that didn't read you".
  read_by as (
    select gr.submission_id, count(*) filter (where gr.is_correct) as correct
      from public.guess_results gr
     group by gr.submission_id
  ),
  -- Guesses each submitter *made*. `made` is what separates a null ear from a zero one.
  made as (
    select gr.round_id, gr.guesser_id,
           count(*)                                  as made,
           count(*) filter (where gr.is_correct)     as correct
      from public.guess_results gr
     group by gr.round_id, gr.guesser_id
  )
  select sub.round_id,
         sub.group_id,
         sub.local_date,
         sub.user_id,
         sub.submitter_count,
         sub.denominator                                as possible,

         coalesce(rb.correct, 0)                        as readability_correct,
         -- Always a number for a submitter, including 0/7. Gus scoring zero is a real result
         -- and the product says so plainly (docs/02 §4.5, "low readability is its own win").
         (coalesce(rb.correct, 0)::numeric / sub.denominator) as readability,

         md.made                                        as guesses_made,
         case when md.made is null then null else md.correct end as ear_correct,
         -- NULL, not 0, when they made no guesses at all. docs/02 §4.1: that round is dropped
         -- from their ear average rather than counted as a failure.
         case when md.made is null
              then null
              else md.correct::numeric / sub.denominator
         end                                            as ear
    from submitters sub
    left join read_by rb on rb.submission_id = sub.submission_id
    left join made    md on md.round_id = sub.round_id and md.guesser_id = sub.user_id;

comment on view public.round_scores is
  'readability and ear per submitter per scored round (docs/02 §4.1). ear is NULL when the '
  'user made zero guesses — never 0. Non-submitters do not appear at all.';

-- ─── all-time, per group ─────────────────────────────────────────────────────
-- The asymmetry in docs/02 §4.2, spelled out so it cannot be collapsed by accident:
--
--   ear_all_time         = Σ correct / Σ possible      over rounds where they guessed
--   readability_all_time = mean( readability per round )
--
-- Both are per *group*, because a user's history belongs to the group it happened in and
-- membership is one-at-a-time (ADR-005). Someone who left and rejoined a different group does
-- not carry their numbers across.

create view public.standings as
  select rs.group_id,
         rs.user_id,
         count(*)                                             as rounds_played,

         -- Pooled. Rounds with no guesses contribute to neither sum, which is what the
         -- `filter` does — a plain sum() would treat NULL as 0 in the numerator and still
         -- count the denominator, quietly punishing people for sitting one out.
         sum(rs.ear_correct) filter (where rs.ear is not null) as ear_correct_total,
         sum(rs.possible)    filter (where rs.ear is not null) as ear_possible_total,
         case when sum(rs.possible) filter (where rs.ear is not null) > 0
              then sum(rs.ear_correct) filter (where rs.ear is not null)::numeric
                   / sum(rs.possible)  filter (where rs.ear is not null)
         end                                                  as ear_all_time,
         count(*) filter (where rs.ear is not null)           as ear_rounds,

         -- A mean of rates, not a pooled ratio. Every scored round they submitted in counts,
         -- including the ones where they guessed nothing: readability does not depend on
         -- whether *they* looked.
         avg(rs.readability)                                  as readability_all_time,

         -- docs/02 §4.5. A band, never a rank — readability is presented as a position on a
         -- spectrum and the API deliberately carries no rank field for it (docs/04 §4).
         case
           when avg(rs.readability) >= 0.80 then 'open_book'
           when avg(rs.readability) >= 0.60 then 'legible'
           when avg(rs.readability) >= 0.40 then 'mixed_signals'
           when avg(rs.readability) >= 0.20 then 'hard_to_place'
           else 'unreadable'
         end                                                  as band
    from public.round_scores rs
   group by rs.group_id, rs.user_id;

comment on view public.standings is
  'All-time per group. ear pools (Σcorrect/Σpossible, zero-guess rounds excluded from both '
  'sums); readability is a mean of per-round rates. The asymmetry is deliberate — docs/02 '
  '§4.2. `band` is docs/02 §4.5 and there is no rank column, by design.';

-- ─── access ──────────────────────────────────────────────────────────────────
-- Views run with the privileges of their owner unless told otherwise, so a view over locked
-- tables would be a way around 0003. `security_invoker` makes each of these evaluate as the
-- caller, which means `anon` and `authenticated` still hit the same wall they hit on the
-- tables underneath — the views inherit the lockdown instead of tunnelling under it.
alter view public.round_submitter_counts set (security_invoker = on);
alter view public.guess_results          set (security_invoker = on);
alter view public.round_scores           set (security_invoker = on);
alter view public.standings              set (security_invoker = on);

revoke all on public.round_submitter_counts, public.guess_results,
              public.round_scores, public.standings
  from public, anon, authenticated;

-- The Edge Functions shape these into `GET /rounds/{id}/results` and
-- `GET /groups/current/standings` (E05-04, E05-05), after doing their own authorization.
grant select on public.round_submitter_counts, public.guess_results,
                public.round_scores, public.standings
  to service_role;
