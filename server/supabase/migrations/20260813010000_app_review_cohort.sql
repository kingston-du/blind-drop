-- Keep App Review out of the real TestFlight group. The first cohort has one seat, claimed by
-- the durable demo account during release setup; pilot testers then fill the 12-seat cohort.
do $$
begin
  if not exists (select 1 from public.pilot_cohorts where name = 'App Review') then
    update public.pilot_cohorts set position = 100 where position = 1;
    insert into public.pilot_cohorts
      (name, timezone, reveal_hour, capacity, position, enabled)
    values ('App Review', 'America/Los_Angeles', 20, 1, 1, true);
    update public.pilot_cohorts set position = 2 where position = 100;
  end if;
end $$;
