-- marketing-score.sql — flip the marketing round to `scored`, so the answers are on screen.
--
-- Run between takes: shoot the flight and your guesses at `revealed`, run this, shoot the
-- answers. `marketing-reset.sql` puts it back.
--
--   npx supabase db query --linked --file server/scripts/marketing-score.sql
--
-- A state change and nothing else. Scores are derived from `guesses` × `submissions` on read
-- (CLAUDE.md §2.8), so there is no total to compute and nothing to store — the results screen,
-- the standings and the share card all build themselves off this one column. `tick_rounds()`
-- skips demo groups, so no scheduler competes for this transition.

set local role postgres;

do $$
declare
  v_group constant uuid := 'fa000000-0000-4000-8000-00000000e001';
  v_round constant uuid := 'fa000000-0000-4000-8000-00000000e002';
  v_mine  int;
begin
  select pg_catalog.count(*)::int into v_mine
    from public.guesses g
    join public.memberships m
      on m.group_id = v_group and m.user_id = g.guesser_id and m.role = 'admin'
   where g.round_id = v_round;

  if v_mine = 0 then
    raise warning
      'You have not guessed yet — the results will show your sheet empty. Guess in the app '
      'first if that frame is going in the video.';
  end if;

  update public.rounds
     set state = 'scored'
   where id = v_round and group_id = v_group and state = 'revealed';

  if not found then
    raise notice
      'Nothing to do — the round is not in `revealed`. Re-run seed-marketing-demo.sql to '
      'rebuild the round for another take.';
  else
    raise notice 'Scored. The answers are live; No. 2 is Seo.';
  end if;
end $$;
