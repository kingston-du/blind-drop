-- 0006_notifications.sql — docs/03 §2, docs/05

create type notif_kind as enum ('nudge','reveal','results','void');

-- Outbox. The unique index IS the idempotency guarantee: a retried job cannot
-- double-send because the second insert conflicts.
create table public.notification_outbox (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references public.rounds(id) on delete cascade,
  kind        notif_kind not null,
  audience    jsonb not null,        -- uuid[] of user ids, resolved at enqueue time
  enqueued_at timestamptz not null default now(),
  sent_at     timestamptz,
  attempts    int not null default 0,
  last_error  text
);
create unique index notification_outbox_once on public.notification_outbox (round_id, kind);
create index notification_outbox_pending on public.notification_outbox (enqueued_at)
  where sent_at is null;

-- Same lockdown as every other table. See 0003_rls.sql — this table is created after it.
alter table public.notification_outbox enable row level security;
alter table public.notification_outbox force row level security;
revoke all on public.notification_outbox from anon, authenticated;
