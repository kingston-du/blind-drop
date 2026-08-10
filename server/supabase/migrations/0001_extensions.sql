-- 0001_extensions.sql — docs/03 §2
-- Forward-only. Never edited after merge (CLAUDE.md §4).

create extension if not exists pgcrypto with schema extensions;  -- gen_random_uuid
create extension if not exists pg_cron;                          -- the 1-minute tick (docs/05)
create extension if not exists pg_net with schema extensions;     -- outbound calls from the tick
