-- status-app-review-demo.sql — what state is the App Review group in? Read-only.
--
-- The companion to seed-app-review-demo.sql, for answering "is the demo account ready?"
-- without changing anything. Safe to run at any time, against any environment.
--
--   npx supabase db query --linked --file server/scripts/status-app-review-demo.sql
--
-- A ready group looks like: is_demo true, six members one of whom is App Reviewer, five
-- companions, three or more scored rounds, and exactly one open round holding the companions'
-- submissions and not the reviewer's.

select
  g.name,
  g.is_demo,
  g.timezone,
  g.reveal_hour,
  (select count(*) from public.memberships m
    where m.group_id = g.id and m.left_at is null)                  as members,
  (select count(*) from public.demo_companions d
    where d.group_id = g.id)                                        as companions,
  (select p.display_name from public.memberships m
     join public.profiles p on p.id = m.user_id
    where m.group_id = g.id and m.role = 'admin' and m.left_at is null
    order by m.joined_at limit 1)                                   as reviewer,
  (select count(*) from public.rounds r
    where r.group_id = g.id and r.state = 'scored')                 as nights_in_the_record,
  (select count(*) from public.rounds r
    where r.group_id = g.id and r.state = 'open')                   as live_rounds,
  (select count(*) from public.submissions s
     join public.rounds r on r.id = s.round_id
    where r.group_id = g.id and r.state = 'open')                   as drops_in_the_live_round
from public.groups g
join public.pilot_cohorts c on c.group_id = g.id
where c.name = 'App Review';
