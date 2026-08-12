-- 0002_core_tables.sql — docs/03 §2, plus the test clock from docs/03 §? (tasks/E01-05)
-- Transcribed from docs/03 §2. Where this file and that section disagree, the doc wins.

-- ─── the clock ───────────────────────────────────────────────────────────────
-- Every lifecycle function calls public.now_(), never now() directly, so tests can move the
-- clock without sleeping. There is no pg_sleep anywhere in this repo (tasks/E01-05).
create or replace function public.now_() returns timestamptz
language sql stable as $$
  select coalesce(
    nullif(current_setting('app.test_now', true), '')::timestamptz,
    now())
$$;

comment on function public.now_() is
  'Server time, overridable in tests via `set_config(''app.test_now'', …)`. Lifecycle code '
  'must call this instead of now(). See tasks/E01-05.';

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
-- 16-year-olds. The 31-character alphabet gives 31^6 ≈ 8.88e8 codes; collisions are
-- handled by retry on unique violation.

-- ─── memberships ─────────────────────────────────────────────────────────────
create table public.memberships (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('member','admin')),
  joined_at  timestamptz not null default now(),
  left_at    timestamptz
);

-- ADR-005: one group per user. A user may have many historical memberships but
-- at most one active.
create unique index memberships_one_active_per_user
  on public.memberships (user_id) where left_at is null;
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

-- ─── rounds: the two invariants a check constraint cannot reach ───────────────
-- docs/02 §5 asks that every invariant be unviolatable by a direct SQL insert. Two of them
-- need a join or the previous row, so they are triggers rather than check constraints:
--   #1  state only ever moves forward along the machine in docs/02 §2.
--   #3  card_order is a permutation of the round's submission ids, of equal length.

create or replace function public.rounds_state_forward_only() returns trigger
language plpgsql as $$
begin
  if new.state = old.state then
    return new;
  end if;
  if not (
       (old.state = 'open'     and new.state in ('revealed','voided'))
    or (old.state = 'revealed' and new.state = 'scored')
  ) then
    raise exception 'round state cannot move % -> %', old.state, new.state;
  end if;
  return new;
end $$;
create trigger rounds_state_forward_only_trg before update of state on public.rounds
  for each row execute function public.rounds_state_forward_only();

create or replace function public.rounds_card_order_is_permutation() returns trigger
language plpgsql as $$
declare v_order uuid[]; v_subs uuid[];
begin
  if new.card_order is null then
    return null;
  end if;
  select array_agg(value::uuid order by ordinality)
    into v_order
    from jsonb_array_elements_text(new.card_order) with ordinality as t(value, ordinality);
  select array_agg(id order by id) into v_subs
    from public.submissions where round_id = new.id;

  if coalesce(array_length(v_order, 1), 0) <> coalesce(array_length(v_subs, 1), 0) then
    raise exception 'card_order length % <> submission count %',
      coalesce(array_length(v_order, 1), 0), coalesce(array_length(v_subs, 1), 0);
  end if;
  if (select array_agg(x order by x) from unnest(v_order) as x) is distinct from v_subs then
    raise exception 'card_order is not a permutation of this round''s submissions';
  end if;
  return null;
end $$;
-- Deferred to commit: a round and its submissions are written in one transaction, and the
-- seed writes the round row first.
create constraint trigger rounds_card_order_is_permutation_trg
  after insert or update of card_order on public.rounds
  deferrable initially deferred
  for each row execute function public.rounds_card_order_is_permutation();

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
