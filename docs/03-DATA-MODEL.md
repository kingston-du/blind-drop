# 03 — Data model

Postgres 17 on Supabase. Forward-only migrations in `server/supabase/migrations/`.

Read `02-DOMAIN-RULES.md` first — this file encodes those rules, it does not restate them.

---

## 1. Principles

- **RLS on every table, deny-by-default.** Edge Functions run as the service role and do
  their own authorization. RLS is the second lock, not the only one.
- **`REVOKE ALL … FROM anon, authenticated` on every table.** The client never touches
  PostgREST. See `01-ARCHITECTURE.md` §2.
- **No score columns.** Derived on read (ADR-004).
- **Timestamps are `timestamptz`, always UTC.** Group-local wall time exists only in
  `groups.timezone` + `rounds.local_date`.
- **Deletes are soft or forbidden.** Leaving a group sets `memberships.left_at`. Submissions
  and guesses are never deleted.

---

## 2. Schema

### `0001_extensions.sql`

```sql
create extension if not exists pgcrypto;   -- gen_random_uuid
create extension if not exists pg_cron;
create extension if not exists pg_net;
```

### `0002_core_tables.sql`

```sql
-- ─── profiles ────────────────────────────────────────────────────────────────
-- One row per auth.users row. display_name is what people guess with.
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null check (
                  char_length(btrim(display_name)) between 1 and 24),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ─── groups ──────────────────────────────────────────────────────────────────
create table public.groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(btrim(name)) between 1 and 40),
  timezone     text not null,                    -- IANA, validated on write
  reveal_hour  int  not null default 20 check (reveal_hour between 18 and 21),
  invite_code  text not null unique
                 check (invite_code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$'),
  created_by   uuid not null references public.profiles(id),
  created_at   timestamptz not null default now()
);
-- Invite alphabet excludes I, L, O, 0, 1 — this code gets read aloud and typed by
-- 16-year-olds. The alphabet has 31 symbols: 31^6 ≈ 8.9e8; collisions are handled by
-- retry on unique violation.

-- ─── memberships ─────────────────────────────────────────────────────────────
create table public.memberships (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('member','admin')),
  joined_at  timestamptz not null default now(),
  left_at    timestamptz
);

-- ADR-005 (one group per user) is superseded by ADR-011. `memberships_one_active_per_user`
-- — the index that enforced ADR-005 by construction — is dropped in
-- `20260818090000_circle_cap.sql` (E18-01). Its replacement cannot be an index: "at most N
-- active rows per user" has no index shape in Postgres, so it is a `before insert` trigger,
-- `memberships_circle_cap`, that takes an advisory lock on the user id and counts. See that
-- migration for the trigger and `public.active_circle_cap()`, the one statement of the number.
create unique index memberships_unique_active_pair
  on public.memberships (group_id, user_id) where left_at is null;
create index memberships_group_active on public.memberships (group_id)
  where left_at is null;

-- ─── rounds ──────────────────────────────────────────────────────────────────
create type round_state as enum ('open','revealed','scored','voided');

create table public.rounds (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  local_date  date not null,                    -- group-local calendar date
  state       round_state not null default 'open',
  opens_at    timestamptz not null,
  reveals_at  timestamptz not null,
  scores_at   timestamptz not null,
  card_order  jsonb,                            -- uuid[] of submission ids; null until reveal
  prompt      text,                             -- v1: always null, no UI. See docs/16.
  created_at  timestamptz not null default now(),
  constraint rounds_window check (
    scores_at = reveals_at + interval '2 hours' and
    opens_at  = reveals_at - interval '10 hours'),
  constraint rounds_card_order_iff_revealed check (
    (card_order is null) = (state in ('open','voided')))
);
create unique index rounds_group_date on public.rounds (group_id, local_date);
create index rounds_pending_tick on public.rounds (state, reveals_at)
  where state in ('open','revealed');

-- ─── submissions ─────────────────────────────────────────────────────────────
create table public.submissions (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references public.rounds(id) on delete cascade,
  user_id     uuid not null references public.profiles(id),
  track_key   text not null,        -- coalesce(isrc,'am:'||apple_id) — see docs/06 §3
  track_meta  jsonb not null,       -- denormalised snapshot; shape in docs/06 §2
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index submissions_one_per_user_per_round
  on public.submissions (round_id, user_id);
create index submissions_round on public.submissions (round_id);
create index submissions_user_created on public.submissions (user_id, created_at desc);
create index submissions_round_trackkey on public.submissions (round_id, track_key);
--                                        ^ the duplicate-track scoring join

-- ─── guesses ─────────────────────────────────────────────────────────────────
create table public.guesses (
  id               uuid primary key default gen_random_uuid(),
  round_id         uuid not null references public.rounds(id) on delete cascade,
  guesser_id       uuid not null references public.profiles(id),
  submission_id    uuid not null references public.submissions(id) on delete cascade,
  guessed_user_id  uuid not null references public.profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint guesses_not_self check (guesser_id <> guessed_user_id)
);
create unique index guesses_one_per_card
  on public.guesses (round_id, guesser_id, submission_id);
create index guesses_round on public.guesses (round_id);
create index guesses_guesser on public.guesses (guesser_id);

-- Invariants 4, 5, 7 from docs/02 §5 are enforced by trigger, since they need a join.
create or replace function public.guesses_validate() returns trigger
language plpgsql as $$
declare v_sub_round uuid; v_sub_owner uuid;
begin
  select round_id, user_id into v_sub_round, v_sub_owner
    from public.submissions where id = new.submission_id;
  if v_sub_round is distinct from new.round_id then
    raise exception 'guess round_id does not match submission round';
  end if;
  if v_sub_owner = new.guesser_id then
    raise exception 'cannot guess on own card';
  end if;
  if not exists (select 1 from public.submissions
                 where round_id = new.round_id and user_id = new.guesser_id) then
    raise exception 'guesser did not submit in this round';
  end if;
  return new;
end $$;
create trigger guesses_validate_trg before insert or update on public.guesses
  for each row execute function public.guesses_validate();

-- ─── devices ─────────────────────────────────────────────────────────────────
create table public.devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  apns_token   text not null,
  environment  text not null check (environment in ('sandbox','production')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  disabled_at  timestamptz                       -- set on APNs 410 Unregistered
);
create unique index devices_token on public.devices (apns_token);
create index devices_user_active on public.devices (user_id) where disabled_at is null;
```

### `0006_notifications.sql`

> This section shows the migration as originally written. `notif_kind` has since gained more
> values via later, forward-only migrations (`invite`, then `seal_reminder`/`guess_reminder` in
> `E31-01` — see `docs/05` §3 for the current, authoritative kind table and `nudge`'s retirement).
> The type below is not rewritten here to match; only the schema files themselves are the source
> of truth for the live column/type shape.

```sql
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
```

### `0007_track_links.sql`

```sql
-- Cross-service identity cache. Keyed by track_key so a lookup is done once per
-- distinct track for the lifetime of the app, not once per submission.
create table public.track_links (
  track_key        text primary key,
  isrc             text,
  apple_music_id   text,
  apple_music_url  text,
  spotify_id       text,
  spotify_url      text,
  resolved_at      timestamptz,        -- last successful spotify lookup
  resolve_attempts int not null default 0,
  unresolvable     boolean not null default false   -- give up after 3 misses
);
create index track_links_needs_resolve on public.track_links (resolve_attempts)
  where spotify_id is null and unresolvable = false;
```

### `0011_rate_limits.sql`

The tenth table, and the only one that holds no game data. The limits in
`04-API-CONTRACT.md` §8 need shared state, and an Edge Function has none of its own.

```sql
create table public.rate_limit_events (
  id      bigserial primary key,
  bucket  text        not null,     -- 'route:<key>:u:<user>' | 'join:ip:<sha256 prefix>'
  at      timestamptz not null default public.now_(),
  expires_at timestamptz not null
);
create index rate_limit_events_bucket_at on public.rate_limit_events (bucket, at desc);
create index rate_limit_events_expires_at on public.rate_limit_events (expires_at);
```

`consume_rate_limit(bucket, limit, window)` returns `0` when the request is allowed, else the
seconds to wait, which the handler returns as `Retry-After`.

- **A bucket key is a user id or a hashed IP. Never a group id.** A group-scoped counter would
  let one member detect another's activity by watching for throttling
  (`14-SECURITY-AND-THREAT-MODEL.md` §3).
- Rows carry their own expiry and the minute scheduler deletes expired rows across all buckets,
  so a hashed IP does not linger indefinitely when that address never returns. That is what keeps
  IP addresses off the
  collected-data list in `14-SECURITY-AND-THREAT-MODEL.md` §9.

---

### `20260912120000_member_reports.sql` — E45-01

The fifteenth table, and the second to hold no game data. App Review's guideline 1.2 asks an
app carrying user-generated content for a way to report it; Blind Drop's user-generated content
is a display name and a hand-written cue, so what gets reported is a **person in a circle**.

```sql
create table public.member_reports (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups(id) on delete cascade,
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  reported_id  uuid not null references public.profiles(id) on delete cascade,
  reason       text not null check (reason in ('display_name', 'cue', 'harassment', 'other')),
  created_at   timestamptz not null default now(),
  constraint member_reports_not_self check (reporter_id <> reported_id)
);
create unique index member_reports_daily_unique
  on public.member_reports (reporter_id, reported_id, ((created_at at time zone 'UTC')::date));
create index member_reports_group_recent on public.member_reports (group_id, created_at desc);
```

- **No reference to `rounds` or `submissions`, deliberately.** A report is about a person, never
  about a night, which is what keeps this table and its route entirely outside
  `CLAUDE.md` §2.1. The route answers the same `204` in every phase.
- **The day in the unique index is pinned to UTC.** A bare `created_at::date` reads the session's
  `TimeZone`, is therefore not immutable, and is refused at index creation.
- **`reason` is a closed set, and there is no free-text column.** A free-text reason would be a
  second piece of user-generated content, about a named person, moderated by nobody.
- Reads are the owner's, through the service role. No client role holds a grant, so a report
  can never be enumerated by the person it is about.

### `20260917120000_reactions.sql` — E46-01

The sixteenth table. One mark per member per card, from the reveal onward, and **no stored
tally anywhere** — `docs/19-REACTIONS.md` §6 and `CLAUDE.md` §2.8.

```sql
create type public.reaction_kind as enum ('loved', 'interesting', 'not_for_me');

create table public.reactions (
  id             uuid primary key default gen_random_uuid(),
  round_id       uuid not null references public.rounds(id) on delete cascade,
  reactor_id     uuid not null references public.profiles(id),
  submission_id  uuid not null references public.submissions(id) on delete cascade,
  kind           public.reaction_kind not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index reactions_one_per_card
  on public.reactions (round_id, reactor_id, submission_id);
create index reactions_round on public.reactions (round_id);
create index reactions_reactor on public.reactions (reactor_id);
```

- **This is the shape of `guesses`, on purpose.** `docs/19` §3's whole design is that a reaction
  behaves exactly like a guess: placed while the round is `revealed`, the reactor's own until it
  is `scored`, counted only after. A counter column on `submissions` would be a number that
  exists during the blind window, and something would eventually read it.
- **No `reactions_not_self`.** `guesses_not_self` exists because guessing your own card is
  cheating; marking your own drop is not, and `docs/19` §4 permits it. The reveal gives it no
  control — the quick pass skips your own card — so in practice it lands from the results screen.
- **`kind` is an enum**, not text with a check. The three are closed (`docs/19` §5) and a fourth
  should be a migration somebody writes on purpose.
- **`reactor_id` references `profiles` without a cascade**, like `guesses.guesser_id`: leaving a
  circle keeps the night's history intact, and only `delete_account` removes it (§6).
- Counts are a `group by kind` at read time, in the `scored` path of
  `functions/rounds/index.ts` and nowhere else.

---

## 3. RLS — `0003_rls.sql`

```sql
alter table public.profiles            enable row level security;
alter table public.groups              enable row level security;
alter table public.memberships         enable row level security;
alter table public.rounds              enable row level security;
alter table public.submissions         enable row level security;
alter table public.guesses             enable row level security;
alter table public.devices             enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.track_links         enable row level security;

-- Deny-by-default: no policies are created for anon/authenticated. Combined with
-- the revokes below, a direct PostgREST call fails with 42501 for every table.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
alter default privileges in schema public
  revoke all on tables from anon, authenticated;
```

> This is intentionally the whole of the RLS file. Do not add "convenience" policies. If a
> feature seems to need one, it needs an Edge Function instead. `E14` tests that every table
> rejects authenticated and anonymous PostgREST requests with `42501 permission denied`.

### `0010_service_role_grants.sql`

`config.toml` sets `auto_expose_new_tables = false`, so a new table is granted to **nobody** —
including `service_role`, which is what the Edge Functions hold. This file grants
`service_role` the verbs each table's handlers actually use, and nothing else: no `DELETE` on
`profiles`, `memberships`, `rounds` or `submissions` (leaving is `left_at`, deleting an
account is anonymisation, a submission is never removed), and no `INSERT` on
`notification_outbox`, because "notification abuse is impossible by construction"
(`14-SECURITY-AND-THREAT-MODEL.md` §8) depends on the API being unable to write to it.

`anon` and `authenticated` — the only roles a client can hold — are untouched and still hold
nothing.

---

## 4. Round lifecycle functions — `0004_round_lifecycle.sql`

Two functions. Both are `security definer`, owned by `postgres`, and callable only by the
service role. Both skip demo groups — see §4.1.

### `ensure_rounds()`

Idempotently materialises the next rounds for every group.

```
for each group g:
  for d in [today(g.timezone), today+1]:
    reveals_at := (d + g.reveal_hour hours) interpreted in g.timezone, cast to timestamptz
    if reveals_at > now_():
      insert into rounds (group_id, local_date, opens_at, reveals_at, scores_at, state)
        values (g.id, d, reveals_at - 10h, reveals_at, reveals_at + 2h, 'open')
        on conflict (group_id, local_date) do nothing
```

Notes:
- Only two days ahead, so the timezone offset used is never stale across a DST boundary.
- Today's round is created only while its reveal time is still in the future. A group created
  after reveal starts tomorrow instead of receiving an immediately expired, voided round.
  Existing rounds are never removed or re-timed, so outage recovery is unaffected.
- `on conflict do nothing` means **this function** never re-times a round. That is about
  outage recovery, not about settings: creation and re-timing are separate operations, so a
  late cron run cannot rewrite a round's clock.
- A `reveal_hour` change **does** re-time rounds, through `retime_unopened_rounds()`
  (20260909120000), and reaches every round whose `opens_at` is still ahead — which is the rule
  `02-DOMAIN-RULES.md` §1 always stated. Owner amendment, 2026-09-09: it used to take effect
  from the first not-yet-*created* round, and since this function materialises two days that
  meant an evening change waited two nights. The bound that matters is that a round somebody
  may already have sealed against never moves, and that is `opens_at`, not existence. Same set
  of rounds `rewrite_open_round_cues()` touches, for the same reason.
- The local-date arithmetic must use `timezone(g.timezone, ...)`, never `at time zone` with a
  fixed offset.

### `tick_rounds()`

Called every minute by `pg_cron`. One transaction per round. Pseudocode:

```
-- reveal or void
for r in (select * from rounds
          where state = 'open' and reveals_at <= now()
          for update skip locked):
    n := count(submissions where round_id = r.id)
    if n < 3:
        update rounds set state='voided'
          where id=r.id and state='open';            -- guard
        if found: insert into notification_outbox
                    (round_id, kind, audience)
                  values (r.id, 'void', <all active members>)
                  on conflict do nothing;
    else:
        order := fisher_yates(submission ids, seed := hashtext(r.id::text))
        update rounds set state='revealed', card_order=order
          where id=r.id and state='open';
        if found: insert into notification_outbox
                    (round_id,'reveal', <all active members>)
                  on conflict do nothing;

-- score
for r in (select * from rounds
          where state='revealed' and scores_at <= now()
          for update skip locked):
    update rounds set state='scored' where id=r.id and state='revealed';
    if found: insert into notification_outbox
                (round_id,'results', <members who submitted OR guessed>)
              on conflict do nothing;

-- seal_reminder, fired twice a round — reveals_at-2h, then reveals_at-30m — replacing the
-- old unconditional nudge as of E31-01 (docs/05 §3). Each firing recomputes the condition
-- fresh; the two are distinguished by scheduled_for, not by a second kind.
for window in ('2 hours', '30 minutes'):
    for r in (select * from rounds
              where state='open'
                and now() >= reveals_at - window
                and now() < reveals_at
                and not exists (outbox row for r, 'seal_reminder', reveals_at - window)):
        insert into notification_outbox (round_id,'seal_reminder',
            <active members with NO submission in r>, scheduled_for := reveals_at - window)
        on conflict (round_id, kind, scheduled_for) do nothing;

-- guess_reminder, fired once a round at scores_at-30m (expressed via reveals_at so this reuses
-- rounds_pending_tick(state, reveals_at) rather than an unindexed scores_at filter — scores_at
-- is always reveals_at + 2h, so reveals_at <= now() - 1h30m is the same instant).
for r in (select * from rounds
          where state='revealed'
            and reveals_at <= now() - interval '1 hour 30 minutes'
            and not exists (outbox row for r, 'guess_reminder')):
    insert into notification_outbox (round_id,'guess_reminder',
        <submitters in r with FEWER THAN S-1 distinct cards guessed>,
        scheduled_for := scores_at - interval '30 minutes')
    on conflict do nothing;                          -- fires exactly once per round
```

`claim_notification_outbox` re-checks `seal_reminder`/`guess_reminder` audiences at claim time
and drops any recipient whose condition has since resolved — the only round-kind audiences that
are not frozen forever at enqueue (docs/05 §3, E31-01).

The `where state = <expected>` guard plus `on conflict do nothing` gives full idempotency:
a job that runs twice, or a worker that crashes mid-transaction and retries, produces one
transition and one notification.

`ensure_rounds()` is called at the top of `tick_rounds()`.

---

## 5. Scoring views — `0005_scoring.sql`

```sql
-- Submitter count per scoreable round.
create view public.round_submitter_counts as
  select r.id as round_id, r.group_id, count(s.id)::int as s_count
  from public.rounds r
  join public.submissions s on s.round_id = r.id
  where r.state = 'scored'
  group by r.id, r.group_id;

-- Every guess, marked correct/incorrect under the duplicate-track rule (docs/02 §4.3).
create view public.guess_results as
  select g.id as guess_id,
         g.round_id,
         g.guesser_id,
         g.submission_id,
         g.guessed_user_id,
         exists (
           select 1
           from public.submissions s2
           where s2.round_id  = g.round_id
             and s2.user_id   = g.guessed_user_id
             and s2.track_key = (select s.track_key
                                 from public.submissions s
                                 where s.id = g.submission_id)
         ) as is_correct
  from public.guesses g;

-- Per-round, per-user readability and ear.
create view public.round_scores as
with c as (select * from public.round_submitter_counts),
     mine as (
       select s.round_id, s.user_id,
              count(*) filter (where gr.is_correct) ::int as read_correct
       from public.submissions s
       left join public.guess_results gr on gr.submission_id = s.id
       group by s.round_id, s.user_id
     ),
     theirs as (
       select gr.round_id, gr.guesser_id as user_id,
              count(*)::int                                as guesses_made,
              count(*) filter (where gr.is_correct)::int   as ear_correct
       from public.guess_results gr
       group by gr.round_id, gr.guesser_id
     )
select c.round_id,
       c.group_id,
       m.user_id,
       c.s_count,
       m.read_correct,
       m.read_correct::numeric / (c.s_count - 1)            as readability,
       coalesce(t.guesses_made, 0)                          as guesses_made,
       coalesce(t.ear_correct, 0)                           as ear_correct,
       case when coalesce(t.guesses_made,0) = 0 then null
            else t.ear_correct::numeric / (c.s_count - 1)
       end                                                  as ear
from c
join mine m on m.round_id = c.round_id
left join theirs t on t.round_id = c.round_id and t.user_id = m.user_id
where c.s_count >= 3;
--    ^ voided rounds never reach 'scored', but this is belt and braces

-- All-time standings. Ear is pooled; readability is a mean of per-round rates.
-- The asymmetry is deliberate — see docs/02 §4.2.
create view public.standings as
select group_id,
       user_id,
       sum(ear_correct)                                       as ear_correct_total,
       sum(case when ear is null then 0 else s_count - 1 end) as ear_possible_total,
       case when sum(case when ear is null then 0 else s_count - 1 end) = 0 then null
            else sum(ear_correct)::numeric
                 / sum(case when ear is null then 0 else s_count - 1 end)
       end                                                    as ear_all_time,
       avg(readability)                                       as readability_all_time,
       count(*)                                               as rounds_played
from public.round_scores
group by group_id, user_id;
```

> **Careful:** `sum(ear_correct)` in `ear_possible_total` must exclude rounds where the user
> made zero guesses, which is why the `case` keys off `ear is null`. A round the user sat out
> of contributes nothing to either side of the ear fraction. `E05` has a pgTAP test for
> exactly this using the §4.4 fixture.

---

## 6. Retention & deletion

| Event | Behaviour |
|---|---|
| User leaves group | `memberships.left_at = now()`. Submissions and guesses stay. Past attribution in The Record is preserved. |
| User deletes account | `delete_account()` replaces `display_name` with `'Former member'`, ends membership, removes device/rate-limit state, drops the auth link, and deletes the `auth.users` row. The stable profile, submissions, and guesses remain so historical scoring stays correct. |
| Group deleted | Cascades everything. Only reachable by direct DB access in v1 — no endpoint. |

`0014_delete_account.sql` resolves the apparent contradiction in the user-deletion row. A
live profile starts with `profiles.id = auth.users.id`, but the original cascading foreign
key is dropped before deletion support ships. The profile UUID then remains as a stable,
anonymised game principal while the matching `auth.users` row is deleted. The absence of that
auth row is the null auth link; there is no nullable second identifier to drift. Device tokens
and rate-limit rows are deleted, and the UUID is removed from notification audiences because
none of those are score history.

---

## 4.1 The demo lifecycle — `20260815090000`, `20260815090500`

The App Review environment (`02-DOMAIN-RULES.md` §6). Two columns, one table and five
functions, all of which no-op on a group that is not a demo group.

| Object | What it is |
|---|---|
| `groups.is_demo` | Set from `pilot_cohorts.is_demo` by `assign_pilot_cohort()`, and nowhere else. There is no API path to it. |
| `rounds.is_demo` | Mirrors the group's, by `before insert` trigger on `rounds` and `after update of is_demo` trigger on `groups`. Exists only so `rounds_window` can exempt a demo round from the fixed 10h/2h window. |
| `demo_companions` | The fixture players in a demo group. Server-only, deny-by-default, no grant to `service_role`. |
| `demo_arm(round, seconds)` | Brings the round's next transition `seconds` away — `reveals_at` while open, `scores_at` once revealed. Never moves `reveals_at` after the reveal: `cannotGuessReason()` reads it against `joined_at`, and moving it misreads as a late join. |
| `demo_tick(group)` | The state machine. Scores a revealed round whose window ran out, reveals an open one once every member has submitted, carries an unplayed round across local midnight, and rolls a fresh round two minutes after the last one scored. Never voids, never writes `notification_outbox`. |
| `shuffle_submissions(round)` | The Fisher–Yates from `0015`, extracted so `tick_rounds()` and `demo_tick()` share one implementation and `tests/db/shuffle.sql` proves both. |
| `demo_provision(group)` | Owner-run fixture setup: names the founding member *App Reviewer*, installs five companions, writes three finished nights, opens tonight's round. **Not granted to `service_role`** — no API path should manufacture players or backdated rounds. |

`ensure_rounds()` and all three `tick_rounds()` loops carry `not g.is_demo`, so the scheduler
and the demo lifecycle can never both own a round.

---

## 7. Seed data for local dev

`server/supabase/seed.sql` creates: one group (`America/New_York`, `reveal_hour = 20`), nine
profiles matching the `02-DOMAIN-RULES.md` §4.4 fixture names, and three rounds — one
`scored` with the full §4.4 data, one `revealed`, one `open`. Every test and every simulator
run starts from this. Keep the names and numbers in sync with §4.4.

It also does two things that exist only locally, both marked as such in the file: it installs
`tick_rounds_at`, `set_membership_joined_at` and `make_demo_group`, which let a test arrange
state no API route can reach; and it disables every pilot cohort, so that a `PUT /me` in the
Edge Function suite does not silently enrol a test user into a group they never asked for.
None of the three helpers exists on a deployed database, which is why there is no grant to
review.
