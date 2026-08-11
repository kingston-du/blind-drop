-- deletion.sql — tasks/E02-05, docs/03 §6, docs/14 §9.
begin;
set search_path = public, extensions, tests;
select plan(26);

select has_function('public', 'delete_account', array['uuid'], 'delete_account(uuid) exists');
select is(
  (select p.prosecdef from pg_proc p
    where p.proname = 'delete_account' and p.pronamespace = 'public'::regnamespace),
  true, 'delete_account() is security definer');
select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p
    where p.proname = 'delete_account' and p.pronamespace = 'public'::regnamespace),
  'delete_account() pins an empty search_path');
select ok(not has_function_privilege('authenticated', 'public.delete_account(uuid)', 'execute'),
          'a client cannot invoke deletion for an arbitrary user');
select ok(has_function_privilege('service_role', 'public.delete_account(uuid)', 'execute'),
          'the authenticated Edge Function may invoke account deletion');

create temporary table before_counts as
select (select count(*)::int from public.submissions) as submissions,
       (select count(*)::int from public.guesses) as guesses,
       (select count(*)::int from public.guesses where guesser_id = tests.person('Ana')) as made_by_ana,
       (select count(*)::int from public.guesses where guessed_user_id = tests.person('Ana')) as naming_ana;

-- This is the standings input available before E05 creates the views: preserve every other
-- submitter's two numerators and guess count row-for-row.
create temporary table other_scores_before as
select p.id as user_id,
       tests.ear_correct(date '2026-08-08', p.display_name) as ear_correct,
       tests.read_correct(date '2026-08-08', p.display_name) as read_correct,
       tests.guesses_made(date '2026-08-08', p.display_name) as guesses_made
  from public.profiles p
 where p.id <> tests.person('Ana')
   and exists (select 1 from public.submissions s
                where s.round_id = tests.round_on(date '2026-08-08') and s.user_id = p.id);

insert into public.devices (user_id, apns_token, environment)
values (tests.person('Ana'), 'deletion-fixture-token', 'sandbox');
insert into public.rate_limit_events (bucket)
values ('route:DELETE /:u:' || tests.person('Ana')::text);
insert into public.notification_outbox (round_id, kind, audience)
values (tests.round_on(date '2026-08-10'), 'nudge',
        jsonb_build_array(tests.person('Ana'), tests.person('Ben')));

select tests.set_test_now('2026-08-10T19:00:00Z');
select lives_ok(
  format('select public.delete_account(%L)', tests.person('Ana')),
  'an established account can be deleted atomically');

select is((select display_name from public.profiles where id = 'a0000000-0000-4000-8000-000000000001'),
          'Former member', 'the stable profile is anonymised');
select is((select updated_at from public.profiles where id = 'a0000000-0000-4000-8000-000000000001'),
          '2026-08-10T19:00:00Z'::timestamptz, 'the tombstone timestamp uses public.now_()');
select is((select left_at from public.memberships
            where group_id = tests.the_group() and user_id = 'a0000000-0000-4000-8000-000000000001'),
          '2026-08-10T19:00:00Z'::timestamptz, 'the active membership is ended');
select is((select count(*)::int from auth.users
            where id = 'a0000000-0000-4000-8000-000000000001'),
          0, 'the authentication principal is gone');
select is((select count(*)::int from public.profiles
            where id = 'a0000000-0000-4000-8000-000000000001'),
          1, 'the historical profile principal survives auth deletion');

select is((select count(*)::int from public.submissions),
          (select submissions from before_counts), 'every submission survives');
select is((select count(*)::int from public.guesses),
          (select guesses from before_counts), 'every guess survives');
select is((select count(*)::int from public.guesses
            where guesser_id = 'a0000000-0000-4000-8000-000000000001'),
          (select made_by_ana from before_counts), 'guesses made by the deleted user survive');
select is((select count(*)::int from public.guesses
            where guessed_user_id = 'a0000000-0000-4000-8000-000000000001'),
          (select naming_ana from before_counts), 'guesses naming the deleted user survive');
select is((select count(*)::int from public.submissions
            where user_id = 'a0000000-0000-4000-8000-000000000001'),
          3, 'the Record keeps every song under the tombstone identity');

select set_eq(
  $$ select user_id, ear_correct, read_correct, guesses_made from other_scores_before $$,
  $$ select p.id,
            tests.ear_correct(date '2026-08-08', p.display_name),
            tests.read_correct(date '2026-08-08', p.display_name),
            tests.guesses_made(date '2026-08-08', p.display_name)
       from public.profiles p
      where p.id <> 'a0000000-0000-4000-8000-000000000001'
        and exists (select 1 from public.submissions s
                     where s.round_id = tests.round_on(date '2026-08-08') and s.user_id = p.id) $$,
  'every other member score input is unchanged');
select is((select count(*)::int from public.submissions
            where round_id = tests.round_on(date '2026-08-08')),
          8, 'the scoring denominator remains eight submitters');

select is((select count(*)::int from public.devices
            where user_id = 'a0000000-0000-4000-8000-000000000001'),
          0, 'APNs tokens are deleted rather than retained');
select is((select count(*)::int from public.rate_limit_events
            where bucket like '%:u:a0000000-0000-4000-8000-000000000001'),
          0, 'short-lived per-user rate-limit rows are removed');
select ok(not (select audience ? 'a0000000-0000-4000-8000-000000000001'
                 from public.notification_outbox
                where round_id = tests.round_on(date '2026-08-10') and kind = 'nudge'),
          'the deleted id is removed from frozen notification audiences');
select ok((select audience ? 'a0000000-0000-4000-8000-000000000002'
              from public.notification_outbox
             where round_id = tests.round_on(date '2026-08-10') and kind = 'nudge'),
          'other notification recipients are untouched');

select lives_ok(
  $$ select public.delete_account('a0000000-0000-4000-8000-000000000001') $$,
  'a retry is idempotent after the auth row is already gone');
select is((select count(*)::int from public.profiles
            where id = 'a0000000-0000-4000-8000-000000000001'),
          1, 'an idempotent retry does not remove the tombstone');

-- Deletion during onboarding: auth exists, profile does not. It must not require a profile
-- merely to remove the account.
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000','e2050000-0000-4000-8000-000000000001',
        'authenticated','authenticated','delete-before-profile@fixture.blinddrop.test',
        '2026-08-10T12:00:00Z','{}'::jsonb,'{}'::jsonb,'2026-08-10T12:00:00Z',
        '2026-08-10T12:00:00Z','','','','');
select lives_ok(
  $$ select public.delete_account('e2050000-0000-4000-8000-000000000001') $$,
  'an account with no profile yet can still be deleted');
select is((select count(*)::int from auth.users
            where id = 'e2050000-0000-4000-8000-000000000001'),
          0, 'onboarding deletion removes that auth principal too');

select * from finish();
rollback;
