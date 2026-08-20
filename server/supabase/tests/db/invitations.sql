-- invitations.sql — tasks/E20-01, docs/02 §2, §3, ADR-011. `20260819100000_invitations.sql`.
--
-- Two things this proves: the invitation state machine itself (create, accept, decline,
-- expiry, re-invite, the circle cap on accept), and — the harder claim — that a person with a
-- pending invitation and no membership changes none of a round's answers: not the reveal
-- threshold, not `card_order`, not the notification audience, not the standings.
begin;
set search_path = public, extensions, tests;
select plan(27);

-- ─── a fresh three-member circle, and a pending invitee who never joins ──────
-- Ana, Ben and Cal are the seed's own people (docs/02 §4.4) — borrowed as actors for a new
-- circle of their own, the same way `circles.sql` borrows Ana for her second and third.
create temporary table itest as select gen_random_uuid() as group_id;
create temporary table itest_round as select gen_random_uuid() as round_id;

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
select group_id, 'E20-01 test circle', 'UTC', 20, 'E2NV8T', tests.person('Ana')
from itest;

insert into public.memberships (group_id, user_id, role)
select group_id, tests.person('Ana'), 'admin' from itest
union all
select group_id, tests.person('Ben'), 'member' from itest
union all
select group_id, tests.person('Cal'), 'member' from itest;

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
select r.round_id, i.group_id, date '2032-03-01', 'open',
       date '2032-03-01' + interval '10 hours',
       date '2032-03-01' + interval '20 hours',
       date '2032-03-01' + interval '22 hours'
from itest i, itest_round r;

insert into public.submissions (round_id, user_id, track_key, track_meta, created_at)
select r.round_id, p.user_id, 'isrc:E2NV8T' || p.suffix, '{}'::jsonb,
       date '2032-03-01' + interval '11 hours'
from itest_round r
cross join (values (tests.person('Ana'), 'A'), (tests.person('Ben'), 'B'),
                    (tests.person('Cal'), 'C')) p(user_id, suffix);

-- Fay is invited and never accepts — pending, and nothing but pending, for the rest of this
-- test's round scenario.
select lives_ok(
  format($$ select public.create_invitation(%L, %L, %L) $$,
         (select group_id from itest), tests.person('Ana'), tests.person('Fay')),
  'Ana invites Fay to the new circle — Fay holds no membership anywhere in it');

-- ─── reveal: the minimum-of-three, card_order, and the audience ──────────────
select tests.set_test_now(date '2032-03-01' + interval '20 hours');
select public.tick_rounds();

select is(
  (select state::text from public.rounds where id = (select round_id from itest_round)),
  'revealed',
  'three real submitters reveal the round — Fay''s pending invite does not count toward the '
  'minimum of three and does not void it');

select is(
  (select jsonb_array_length(card_order) from public.rounds
    where id = (select round_id from itest_round)),
  3,
  'card_order holds exactly the three real submissions — the pending invitee is not a card');

select ok(
  (select audience ? tests.person('Ana')::text from public.notification_outbox
    where round_id = (select round_id from itest_round) and kind = 'reveal'),
  'the reveal audience includes a real member');

select ok(
  not (select audience ? tests.person('Fay')::text from public.notification_outbox
    where round_id = (select round_id from itest_round) and kind = 'reveal'),
  'the reveal audience excludes the pending invitee — she has no membership row to draw from');

-- ─── guesses and scoring ──────────────────────────────────────────────────────
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select (select round_id from itest_round), tests.person('Ana'), s.id, tests.person('Ben')
  from public.submissions s
 where s.round_id = (select round_id from itest_round) and s.user_id = tests.person('Ben');
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select (select round_id from itest_round), tests.person('Ben'), s.id, tests.person('Cal')
  from public.submissions s
 where s.round_id = (select round_id from itest_round) and s.user_id = tests.person('Cal');
insert into public.guesses (round_id, guesser_id, submission_id, guessed_user_id)
select (select round_id from itest_round), tests.person('Cal'), s.id, tests.person('Ana')
  from public.submissions s
 where s.round_id = (select round_id from itest_round) and s.user_id = tests.person('Ana');

select tests.set_test_now(date '2032-03-01' + interval '22 hours');
select public.tick_rounds();

select is(
  (select state::text from public.rounds where id = (select round_id from itest_round)),
  'scored', 'the round scores on schedule');

select is(
  (select submitter_count from public.round_submitter_counts
    where round_id = (select round_id from itest_round)),
  3::bigint, 'round_submitter_counts sees exactly the three real submitters, never the invitee');

select ok(
  not exists (
    select 1 from public.standings
     where group_id = (select group_id from itest) and user_id = tests.person('Fay')
  ),
  'standings has no row at all for the pending invitee — she never submitted or guessed');

select ok(
  (select audience ? tests.person('Ana')::text from public.notification_outbox
    where round_id = (select round_id from itest_round) and kind = 'results'),
  'the results audience includes a real member');

select ok(
  not (select audience ? tests.person('Fay')::text from public.notification_outbox
    where round_id = (select round_id from itest_round) and kind = 'results'),
  'the results audience excludes the pending invitee');

-- ─── the invitation state machine itself ──────────────────────────────────────

-- The round exercise used a future clock. Invitation defaults are relative to `now_()`, so
-- return to real time before creating the state-machine fixtures; otherwise a newly-created
-- invitation looks expired immediately when the next create lazily checks it.
select tests.clear_test_now();

-- One live pending invite per pair — a second attempt while Fay's is still outstanding fails
-- the partial unique index, mapped by the handler to ALREADY_INVITED.
select throws_ok(
  format($$ select public.create_invitation(%L, %L, %L) $$,
         (select group_id from itest), tests.person('Ben'), tests.person('Fay')),
  '23505', null,
  'a second live pending invite to the same pair is refused');

-- Decline is terminal, and immediately re-invitable.
create temporary table itest_invite (id uuid);
insert into itest_invite (id)
select (public.create_invitation(
          (select group_id from itest), tests.person('Ana'), tests.person('Dee'))).id;

select lives_ok(
  format($$ select public.decline_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Dee')),
  'Dee declines her invitation');

select is(
  (select status from public.invitations where id = (select id from itest_invite)),
  'declined', 'the declined invitation is terminal');

select isnt(
  (select responded_at from public.invitations where id = (select id from itest_invite)),
  null, 'a terminal invitation always carries a responded_at');

select throws_ok(
  format($$ select public.decline_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Dee')),
  'BD004', null,
  'declining an already-declined invitation is refused — terminal means terminal');

select lives_ok(
  format($$ select public.create_invitation(%L, %L, %L) $$,
         (select group_id from itest), tests.person('Ana'), tests.person('Dee')),
  'Dee is re-invitable immediately after declining — the partial unique index freed on decline');

-- Expiry, forced by hand (create_invitation always mints a fresh 14-day expiry): terminal on
-- the next attempt to act on it, and — like decline — immediately re-invitable afterward.
truncate itest_invite;
insert into itest_invite (id)
select (public.create_invitation(
          (select group_id from itest), tests.person('Ana'), tests.person('Eli'))).id;
update public.invitations set expires_at = public.now_() - interval '1 minute'
 where id = (select id from itest_invite);

select is(
  (select public.accept_invitation((select id from itest_invite), tests.person('Eli'))->>'outcome'),
  'expired', 'accepting a past-expiry invitation records expiry before the handler refuses it');

select is(
  (select status from public.invitations where id = (select id from itest_invite)),
  'expired', 'the failed accept attempt lazily flips the row to expired');

select lives_ok(
  format($$ select public.create_invitation(%L, %L, %L) $$,
         (select group_id from itest), tests.person('Ana'), tests.person('Eli')),
  'Eli is re-invitable immediately after expiry');

-- `create_invitation` itself lazily expires a stale pending row nobody has ever tried to act
-- on — distinct from the two cases above, where `accept_invitation`/`decline_invitation` were
-- what flipped the status.
truncate itest_invite;
insert into itest_invite (id)
select (public.create_invitation(
          (select group_id from itest), tests.person('Ana'), tests.person('Ivy'))).id;
update public.invitations set expires_at = public.now_() - interval '1 minute'
 where id = (select id from itest_invite) and status = 'pending';

select lives_ok(
  format($$ select public.create_invitation(%L, %L, %L) $$,
         (select group_id from itest), tests.person('Ana'), tests.person('Ivy')),
  'create_invitation lazily expires a stale pending row nobody has touched yet, then inserts '
  'a fresh one, rather than colliding with its own ghost');

select is(
  (select status from public.invitations where id = (select id from itest_invite)),
  'expired',
  'the old, never-acted-on pending row is now expired — create_invitation did that itself, '
  'not accept_invitation or decline_invitation');

-- Accepting creates the membership atomically, and only for the invited caller.
truncate itest_invite;
insert into itest_invite (id)
select (public.create_invitation(
          (select group_id from itest), tests.person('Ana'), tests.person('Gus'))).id;

select throws_ok(
  format($$ select public.accept_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Hal')),
  'BD004', null,
  'a caller who was not invited gets the same BD004 as a nonexistent invitation — no oracle');

select lives_ok(
  format($$ select public.accept_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Gus')),
  'Gus accepts his own invitation');

select ok(
  exists (
    select 1 from public.memberships
     where group_id = (select group_id from itest) and user_id = tests.person('Gus')
       and left_at is null and role = 'member'
  ),
  'accepting created the membership, atomically, with the invitation');

select throws_ok(
  format($$ select public.accept_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Gus')),
  'BD004', null,
  'accepting an already-accepted invitation a second time is refused');

-- Accepting still goes through `memberships_circle_cap` (ADR-011) — this is not a second,
-- uncapped door into a circle. Hal is put at the cap first, the same way `circles.sql` does.
insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values
  ('e2001000-0000-4000-8000-0000000000c1', 'Hal''s second circle', 'UTC', 20, 'E2HA2X',
   tests.person('Hal')),
  ('e2001000-0000-4000-8000-0000000000c2', 'Hal''s third circle', 'UTC', 20, 'E2HA3X',
   tests.person('Hal'));
insert into public.memberships (group_id, user_id, role)
values
  ('e2001000-0000-4000-8000-0000000000c1', tests.person('Hal'), 'member'),
  ('e2001000-0000-4000-8000-0000000000c2', tests.person('Hal'), 'member');

truncate itest_invite;
insert into itest_invite (id)
select (public.create_invitation(
          (select group_id from itest), tests.person('Ana'), tests.person('Hal'))).id;

select throws_ok(
  format($$ select public.accept_invitation(%L, %L) $$,
         (select id from itest_invite), tests.person('Hal')),
  'BD002', null,
  'accepting at the circle cap is refused through the same trigger POST /groups/join uses');

select is(
  (select status from public.invitations where id = (select id from itest_invite)),
  'pending',
  'a cap refusal at accept leaves the invitation exactly as it was — nothing partially applied');

select * from finish();
rollback;
