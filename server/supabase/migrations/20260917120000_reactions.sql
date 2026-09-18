-- E46-01 — reactions. docs/19-REACTIONS.md.
--
-- `docs/16` §1 banned reactions outright until 2026-09-17, when the owner promoted them on the
-- terms `docs/19` sets out. The one that shapes this table is §3: **a reaction behaves exactly
-- like a guess.** It is placed while the round is `revealed`, it is the reactor's own until the
-- round is `scored`, and no count of it exists anywhere before then.
--
-- That is why this is the shape of `guesses` (0002) rather than a counter column on
-- `submissions`. A stored tally is a number that exists during the blind window, and something
-- would eventually read it. Counts are a `group by` at read time in the `scored` path and
-- nowhere else (`CLAUDE.md` §2.8, and the same reasoning that keeps scores derived).
--
-- Two differences from `guesses`, both deliberate:
--
--   · **No not-self constraint.** `guesses_not_self` exists because guessing your own card is
--     cheating. Marking your own drop is a person saying what they think of their own song,
--     which is the same thing they did by dropping it, and `docs/19` §4 permits it. The reveal
--     gives it no control — the quick pass still skips your own card — so in practice this lands
--     from the results screen.
--   · **`kind` is an enum, not text with a check.** The set of three is closed and a fourth is a
--     product change (`docs/19` §5); an enum makes adding one a migration somebody has to write
--     on purpose, which is the same friction the golden files apply on the other side.
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

-- One mark per person per card. Changing your mind is an upsert on this index, not a second
-- row; clearing is a delete. The same three columns `guesses_one_per_card` uses, in the same
-- order, so the two tables are read the same way by anyone who has read one of them.
--
-- `reactor_id` references `profiles` without a cascade, like `guesses.guesser_id`: a member who
-- leaves a circle keeps their history there — the night happened — and only `delete_account`
-- removes it (docs/03 §6).
create unique index reactions_one_per_card
  on public.reactions (round_id, reactor_id, submission_id);

-- The `scored` read: every reaction in one round, grouped by card and kind. The only aggregate
-- this feature has, and it is reachable from exactly one code path.
create index reactions_round on public.reactions (round_id);
create index reactions_reactor on public.reactions (reactor_id);

alter table public.reactions enable row level security;
alter table public.reactions force row level security;

comment on table public.reactions is
  'One mark per member per card (E46-01, docs/19). Sealed until the round is scored: no count '
  'of these rows exists in any response before then, and no tally is stored here.';

revoke all on table public.reactions from public, anon, authenticated;
grant select, insert, update, delete on table public.reactions to service_role;
