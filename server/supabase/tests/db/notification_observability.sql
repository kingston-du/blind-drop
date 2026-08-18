-- notification_observability.sql — tasks/E23-01, docs/05 §1, §6.
--
-- Two things, both from the E23-01 diagnosis:
--
--   1. A permanent, executable proof of suspect 1 — `app.functions_url` / `app.service_key`
--      are never set by any migration, `config.toml`, or `seed.sql`. If a later migration
--      quietly starts setting them (locally, which it must not — see 20260818140000's header),
--      this is the test that would need to change, on purpose, not by accident.
--   2. Behaviour of `public.stuck_notifications()`, the observability this slice adds: a row
--      unsent well past its enqueue time is surfaced; a fresh or already-sent row is not.
begin;
set search_path = public, extensions, tests;
select plan(8);

-- ─── suspect 1, reproduced ────────────────────────────────────────────────────
select throws_ok(
  $$ select current_setting('app.functions_url') $$,
  '42704', null,
  'app.functions_url has no value anywhere in this repo — the push/links cron jobs fail at '
  'this line before net.http_post is ever reached');
select throws_ok(
  $$ select current_setting('app.service_key') $$,
  '42704', null,
  'app.service_key is equally unset — same failure, same silence');

-- ─── stuck_notifications() exists and is locked down like its siblings ───────
select has_function('public', 'stuck_notifications', array['interval'],
                    'the outbox-health check exists');
select ok(not has_function_privilege('anon', 'public.stuck_notifications(interval)', 'execute'),
          'anon cannot query it — PostgREST is off-limits anyway, but deny-by-default twice');
select ok(not has_function_privilege('authenticated',
                 'public.stuck_notifications(interval)', 'execute'),
          'authenticated cannot query it either');
select ok(has_function_privilege('service_role',
                 'public.stuck_notifications(interval)', 'execute'),
          'the operational surface (service role, or an operator via the SQL editor) can');

-- ─── behaviour ─────────────────────────────────────────────────────────────
select tests.set_test_now('2026-08-10 12:00:00+00');

insert into public.notification_outbox (id, round_id, kind, audience, enqueued_at)
values
  ('e2301000-0000-4000-8000-000000000001', tests.round_on('2026-08-10'), 'reveal', '[]'::jsonb,
   '2026-08-10 11:00:00+00'),   -- an hour old, unsent: stuck
  ('e2301000-0000-4000-8000-000000000002', tests.round_on('2026-08-09'), 'reveal', '[]'::jsonb,
   '2026-08-10 11:59:00+00');   -- a minute old, unsent: not stuck yet

select set_eq(
  $$ select id from public.stuck_notifications('5 minutes'::interval) $$,
  $$ values ('e2301000-0000-4000-8000-000000000001'::uuid) $$,
  'only the hour-old unsent row is stuck at a 5-minute threshold');

-- Mark it sent: it must drop out immediately, same as a fresh row never appearing.
update public.notification_outbox set sent_at = public.now_()
 where id = 'e2301000-0000-4000-8000-000000000001'::uuid;
select is(
  (select count(*)::int from public.stuck_notifications('5 minutes'::interval)),
  0, 'a sent row is never reported as stuck, however old it is');

select * from finish();
rollback;
