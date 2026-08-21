-- notification_coalescing.sql — E23-02, docs/05 §3–4.
begin;
set search_path = public, extensions, tests;
select plan(5);

-- A fresh principal can hold three circles. Their three void events share one scheduled instant
-- and kind; calling the same central path tick_rounds() uses proves they become one delivery.
insert into public.profiles (id, display_name)
values ('e2302000-0000-4000-8000-000000000001', 'Budget Listener');

insert into public.groups (id, name, timezone, reveal_hour, invite_code, created_by)
values
  ('e2302000-0000-4000-8000-000000000011', 'Budget One', 'UTC', 20, 'E23ABC', 'e2302000-0000-4000-8000-000000000001'),
  ('e2302000-0000-4000-8000-000000000012', 'Budget Two', 'UTC', 20, 'E23DEF', 'e2302000-0000-4000-8000-000000000001'),
  ('e2302000-0000-4000-8000-000000000013', 'Budget Three', 'UTC', 20, 'E23GHJ', 'e2302000-0000-4000-8000-000000000001');

insert into public.memberships (group_id, user_id, role)
values
  ('e2302000-0000-4000-8000-000000000011', 'e2302000-0000-4000-8000-000000000001', 'admin'),
  ('e2302000-0000-4000-8000-000000000012', 'e2302000-0000-4000-8000-000000000001', 'admin'),
  ('e2302000-0000-4000-8000-000000000013', 'e2302000-0000-4000-8000-000000000001', 'admin');

insert into public.rounds (id, group_id, local_date, state, opens_at, reveals_at, scores_at)
values
  ('e2302000-0000-4000-8000-000000000021', 'e2302000-0000-4000-8000-000000000011', '2032-03-01', 'open', '2032-03-01T10:00:00Z', '2032-03-01T20:00:00Z', '2032-03-01T22:00:00Z'),
  ('e2302000-0000-4000-8000-000000000022', 'e2302000-0000-4000-8000-000000000012', '2032-03-01', 'open', '2032-03-01T10:00:00Z', '2032-03-01T20:00:00Z', '2032-03-01T22:00:00Z'),
  ('e2302000-0000-4000-8000-000000000023', 'e2302000-0000-4000-8000-000000000013', '2032-03-01', 'open', '2032-03-01T10:00:00Z', '2032-03-01T20:00:00Z', '2032-03-01T22:00:00Z');

select tests.set_test_now('2032-03-01T20:00:00Z');
select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000021', 'void', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-01T20:00:00Z');
select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000022', 'void', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-01T20:00:00Z');
select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000023', 'void', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-01T20:00:00Z');

select is((select count(*)::int from public.notification_outbox
            where kind = 'void' and scheduled_for = '2032-03-01T20:00:00Z'
              and round_id in ('e2302000-0000-4000-8000-000000000021', 'e2302000-0000-4000-8000-000000000022', 'e2302000-0000-4000-8000-000000000023')),
          3, 'each circle records its own idempotent void event');
select is((select count(*)::int from public.notification_outbox
            where kind = 'void' and scheduled_for = '2032-03-01T20:00:00Z'
              and audience ? 'e2302000-0000-4000-8000-000000000001'),
          1, 'three coincident circles produce one delivery for their shared member');
select is((select round_id from public.notification_outbox
            where kind = 'void' and scheduled_for = '2032-03-01T20:00:00Z'
              and audience ? 'e2302000-0000-4000-8000-000000000001'),
          'e2302000-0000-4000-8000-000000000021'::uuid,
          'the earliest deterministic round is the grouped delivery target');

select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000021', 'nudge', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-01T18:00:00Z');
select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000021', 'results', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-01T22:00:00Z');
select public.enqueue_round_notification('e2302000-0000-4000-8000-000000000022', 'reveal', jsonb_build_array('e2302000-0000-4000-8000-000000000001'::uuid), '2032-03-02T17:59:00Z');

select is((select count(*)::int from public.notification_outbox
            where audience ? 'e2302000-0000-4000-8000-000000000001'
              and enqueued_at = '2032-03-01T20:00:00Z'),
          3, 'the shared member has exactly three deliveries in the rolling window');
select ok(not (select audience ? 'e2302000-0000-4000-8000-000000000001'
                 from public.notification_outbox
                where round_id = 'e2302000-0000-4000-8000-000000000022' and kind = 'reveal'),
          'a fourth delivery is refused centrally while its source event remains idempotent');

select * from finish();
rollback;
