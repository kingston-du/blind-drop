-- 0010_service_role_grants.sql — docs/01 §2, docs/14 §4. tasks/E02-01.
--
-- The Edge Functions reach Postgres as `service_role`, and `service_role` starts with no
-- privilege at all on `public`: `config.toml` sets `auto_expose_new_tables = false`, so
-- nothing created by 0002/0006/0007 was granted to anybody. Without this file every handler
-- gets `42501 permission denied`.
--
-- Two things this file is NOT:
--
--   · It is not a loosening of 0003. `anon` and `authenticated` — the roles a client can
--     actually hold — are untouched and still hold nothing. PostgREST stays shut to the app
--     (docs/01 §2); the only key that unlocks anything here is the service key, which lives
--     in the function environment and never ships to a device (docs/14 §6).
--   · It is not a blanket grant. Each table gets the verbs its handlers use and no others,
--     so a bug cannot delete what the schema says is undeletable. In particular there is no
--     DELETE on profiles, memberships, rounds or submissions: leaving a group is
--     `left_at`, deleting an account is anonymisation (docs/03 §6), and a submission is
--     never removed (docs/04 §4, "there is no DELETE").

-- Identity and membership.
grant select, insert, update on public.profiles    to service_role;
grant select, insert, update on public.groups      to service_role;
grant select, insert, update on public.memberships to service_role;

-- The round and its contents. Rounds are created and transitioned by the tick job
-- (docs/03 §4), which runs as `postgres` under pg_cron — the API only ever reads them.
grant select                 on public.rounds      to service_role;
grant select, insert, update on public.submissions to service_role;
-- Guesses are the one place a client-driven DELETE is correct: the whole-sheet upsert in
-- docs/04 §4 clears a card by sending it explicitly as null, which removes the row.
grant select, insert, update, delete on public.guesses to service_role;

-- Push. The outbox is written only by the tick job — "notification abuse is impossible by
-- construction" (docs/14 §8) depends on the API never being able to insert into it.
grant select, insert, update on public.devices            to service_role;
grant select, update         on public.notification_outbox to service_role;

-- The cross-service identity cache (docs/06 §5).
grant select, insert, update on public.track_links to service_role;
