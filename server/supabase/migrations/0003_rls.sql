-- 0003_rls.sql — docs/03 §3, docs/01 §2, docs/14 §4
--
-- Deny-by-default on every table, and NO policies. The client never touches PostgREST; the
-- Edge Functions use the service role and do their own authorization. RLS is the second
-- lock, not the only one.
--
-- Resist adding a "read your own profile" policy (tasks/E01-02). The app reads its profile
-- through an Edge Function. Every policy added here is a surface that has to be re-reasoned
-- about in every phase of every round.
--
-- Two of the nine tables — notification_outbox and track_links — do not exist yet at this
-- point in the migration order (docs/01 §3 puts them in 0006 and 0007). They repeat these
-- same two statements at the end of their own file, and tests/db/rls.sql asserts all nine.

alter table public.profiles    enable row level security;
alter table public.groups      enable row level security;
alter table public.memberships enable row level security;
alter table public.rounds      enable row level security;
alter table public.submissions enable row level security;
alter table public.guesses     enable row level security;
alter table public.devices     enable row level security;

-- Force RLS for the table owner too, so a future `security definer` function owned by
-- postgres cannot become an accidental bypass.
alter table public.profiles    force row level security;
alter table public.groups      force row level security;
alter table public.memberships force row level security;
alter table public.rounds      force row level security;
alter table public.submissions force row level security;
alter table public.guesses     force row level security;
alter table public.devices     force row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges in schema public
  revoke all on functions from anon, authenticated;

-- `public.now_()` is a helper for lifecycle code and tests. Nothing outside the service role
-- has any business calling it.
revoke all on function public.now_() from anon, authenticated;
