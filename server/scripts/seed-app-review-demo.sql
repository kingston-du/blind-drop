-- seed-app-review-demo.sql — prepare the hosted App Review account. Owner-run, once.
--
-- All this does now is find the App Review cohort's group and call `demo_provision()`
-- (20260815090500). The fixture data, the companions, the archive and tonight's round all
-- live in that function, where the pgTAP suite can drive them; this file is the two lines of
-- glue that resolve "which group" on a hosted project.
--
-- **This replaces a script that had a deadline.** The previous version hand-wrote a `revealed`
-- round anchored to `now()`, which hosted cron swept into `scored` within the hour, so it had
-- to be re-run shortly before the reviewer was expected to open the app — something nobody can
-- schedule. A demo group's rounds now advance on the reviewer's own actions instead of on the
-- clock, so there is nothing left to decay and nothing to re-run. Drop a song, wait twelve
-- seconds, guess, wait twenty, read the answers, go again. At any hour.
--
-- Run it after the reviewer's account has signed in at least once: `assign_pilot_cohort()`
-- creates the group lazily on that first `PUT /me`, and `demo_provision()` raises a clear
-- exception if it has not happened yet.
--
--   npx supabase db query --linked --file server/scripts/seed-app-review-demo.sql
--
-- or, outside this repo's CLI setup:
--
--   psql "$HOSTED_DB_URL" -v ON_ERROR_STOP=1 -f server/scripts/seed-app-review-demo.sql
--
-- or paste the body into the hosted project's SQL editor with the postgres role.
--
-- Idempotent. Re-running is safe and mostly a no-op: the display name and companions are
-- upserted, and an archive night is only written for a date that has none.

set local role postgres;

do $$
declare
  v_group_id uuid;
begin
  select c.group_id into v_group_id
    from public.pilot_cohorts c
   where c.name = 'App Review';

  if v_group_id is null then
    raise exception
      'The App Review cohort has no group yet. Sign in as the review account once first — '
      'that call to assign_pilot_cohort() creates the group — then re-run this script.';
  end if;

  perform public.demo_provision(v_group_id);

  raise notice
    'App Review ready. group=% — the reviewer is "App Reviewer", three companions are in the '
    'room, three nights are in The Record, and tonight''s round is open at any hour.',
    v_group_id;
end $$;
