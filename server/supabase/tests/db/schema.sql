-- schema.sql — tasks/E01-01. Every table, column type, and index in docs/03 §2 exists.
begin;
set search_path = public, extensions, tests;
select plan(132);

-- ─── extensions (docs/03 §2, 0001) ───────────────────────────────────────────
select has_extension('pgcrypto', 'pgcrypto is installed (gen_random_uuid)');
select has_extension('pg_cron',  'pg_cron is installed (the 1-minute tick)');
select has_extension('pg_net',   'pg_net is installed');

-- ─── enums ───────────────────────────────────────────────────────────────────
select has_enum('public', 'round_state', 'round_state enum exists');
select enum_has_labels('public', 'round_state',
       array['open','revealed','scored','voided'], 'round_state has the docs/02 §2 states');
select has_enum('public', 'notif_kind', 'notif_kind enum exists');
select enum_has_labels('public', 'notif_kind',
       array['nudge','reveal','results','void'], 'notif_kind has the docs/11 kinds');

-- ─── the nine tables ─────────────────────────────────────────────────────────
select has_table('public', t, format('table %I exists', t))
from unnest(array['profiles','groups','memberships','rounds','submissions','guesses',
                  'devices','notification_outbox','track_links']) as t;

-- ─── profiles ────────────────────────────────────────────────────────────────
select has_column('public','profiles', c, format('profiles.%I', c))
from unnest(array['id','display_name','created_at','updated_at']) as c;
select col_type_is('public','profiles','id','uuid', 'profiles id uuid');
select col_type_is('public','profiles','display_name','text', 'profiles display_name text');
select col_is_pk('public','profiles','id','profiles.id is the pk');
select is_empty($$
  select 1 from pg_constraint
   where conrelid = 'public.profiles'::regclass
     and confrelid = 'auth.users'::regclass
$$, 'profile tombstones survive auth.users deletion (E02-05)');

-- ─── groups ──────────────────────────────────────────────────────────────────
select has_column('public','groups', c, format('groups.%I', c))
from unnest(array['id','name','timezone','reveal_hour','invite_code','created_by',
                  'created_at']) as c;
select col_type_is('public','groups','reveal_hour','integer', 'groups reveal_hour integer');
select col_type_is('public','groups','timezone','text', 'groups timezone text');
select col_has_default('public','groups','reveal_hour','reveal_hour defaults to 20');
select ok((select count(*) = 1 from pg_indexes
           where schemaname='public' and tablename='groups' and indexdef ilike '%UNIQUE%invite_code%'),
          'invite_code is unique');

-- ─── memberships — ADR-005 lives in these indexes ────────────────────────────
select has_column('public','memberships', c, format('memberships.%I', c))
from unnest(array['id','group_id','user_id','role','joined_at','left_at']) as c;
select has_index('public','memberships','memberships_one_active_per_user',
                 'ADR-005: at most one active membership per user');
select index_is_unique('public','memberships','memberships_one_active_per_user', 'memberships memberships_one_active_per_user');
select has_index('public','memberships','memberships_unique_active_pair', 'memberships memberships_unique_active_pair');
select index_is_unique('public','memberships','memberships_unique_active_pair', 'memberships memberships_unique_active_pair');
select has_index('public','memberships','memberships_group_active', 'memberships memberships_group_active');
select ok((select indexdef ilike '%where (left_at is null)%' from pg_indexes
           where indexname='memberships_one_active_per_user'),
          'memberships_one_active_per_user is partial on left_at is null');

-- ─── rounds ──────────────────────────────────────────────────────────────────
select has_column('public','rounds', c, format('rounds.%I', c))
from unnest(array['id','group_id','local_date','state','opens_at','reveals_at','scores_at',
                  'card_order','prompt','created_at']) as c;
select col_type_is('public','rounds','local_date','date', 'rounds local_date date');
select col_type_is('public','rounds','state','round_state', 'rounds state round_state');
select col_type_is('public','rounds','opens_at','timestamp with time zone', 'rounds opens_at timestamp with time zone');
select col_type_is('public','rounds','card_order','jsonb', 'rounds card_order jsonb');
select has_index('public','rounds','rounds_group_date', 'rounds rounds_group_date');
select index_is_unique('public','rounds','rounds_group_date', 'rounds rounds_group_date');
select has_index('public','rounds','rounds_pending_tick', 'rounds rounds_pending_tick');
select has_check('public','rounds','rounds has check constraints');
select ok((select count(*) = 1 from pg_constraint
           where conrelid='public.rounds'::regclass and conname='rounds_window'),
          'rounds_window check constraint exists');
select ok((select count(*) = 1 from pg_constraint
           where conrelid='public.rounds'::regclass
             and conname='rounds_card_order_iff_revealed'),
          'rounds_card_order_iff_revealed check constraint exists');

-- ─── submissions ─────────────────────────────────────────────────────────────
select has_column('public','submissions', c, format('submissions.%I', c))
from unnest(array['id','round_id','user_id','track_key','track_meta','created_at',
                  'updated_at']) as c;
select col_type_is('public','submissions','track_key','text', 'submissions track_key text');
select col_type_is('public','submissions','track_meta','jsonb', 'submissions track_meta jsonb');
select has_index('public','submissions','submissions_one_per_user_per_round', 'submissions submissions_one_per_user_per_round');
select index_is_unique('public','submissions','submissions_one_per_user_per_round', 'submissions submissions_one_per_user_per_round');
select has_index('public','submissions','submissions_round', 'submissions submissions_round');
select has_index('public','submissions','submissions_user_created', 'submissions submissions_user_created');
select has_index('public','submissions','submissions_round_trackkey', 'submissions submissions_round_trackkey');

-- ─── guesses ─────────────────────────────────────────────────────────────────
select has_column('public','guesses', c, format('guesses.%I', c))
from unnest(array['id','round_id','guesser_id','submission_id','guessed_user_id',
                  'created_at','updated_at']) as c;
select has_index('public','guesses','guesses_one_per_card', 'guesses guesses_one_per_card');
select index_is_unique('public','guesses','guesses_one_per_card', 'guesses guesses_one_per_card');
select has_index('public','guesses','guesses_round', 'guesses guesses_round');
select has_index('public','guesses','guesses_guesser', 'guesses guesses_guesser');
select has_function('public','guesses_validate', 'guesses_validate() exists');
select has_trigger('public','guesses','guesses_validate_trg', 'guesses guesses_validate_trg');

-- ─── the two invariants that needed a trigger rather than a check ────────────
select has_function('public','rounds_state_forward_only', 'rounds_state_forward_only');
select has_trigger('public','rounds','rounds_state_forward_only_trg', 'rounds rounds_state_forward_only_trg');
select has_function('public','rounds_card_order_is_permutation', 'rounds_card_order_is_permutation');
select has_trigger('public','rounds','rounds_card_order_is_permutation_trg', 'rounds rounds_card_order_is_permutation_trg');

-- ─── devices ─────────────────────────────────────────────────────────────────
select has_column('public','devices', c, format('devices.%I', c))
from unnest(array['id','user_id','apns_token','environment','created_at','last_seen_at',
                  'disabled_at']) as c;
select has_index('public','devices','devices_token', 'devices devices_token');
select index_is_unique('public','devices','devices_token', 'devices devices_token');
select has_index('public','devices','devices_user_active', 'devices devices_user_active');

-- ─── notification outbox — the unique index IS the idempotency guarantee ─────
select has_column('public','notification_outbox', c, format('notification_outbox.%I', c))
from unnest(array['id','round_id','kind','audience','enqueued_at','sent_at','attempts',
                  'last_error']) as c;
select has_index('public','notification_outbox','notification_outbox_once', 'notification_outbox notification_outbox_once');
select index_is_unique('public','notification_outbox','notification_outbox_once', 'notification_outbox notification_outbox_once');
select has_index('public','notification_outbox','notification_outbox_pending', 'notification_outbox notification_outbox_pending');

-- ─── track_links ─────────────────────────────────────────────────────────────
select has_column('public','track_links', c, format('track_links.%I', c))
from unnest(array['track_key','isrc','apple_music_id','apple_music_url','spotify_id',
                  'spotify_url','resolved_at','resolve_attempts','unresolvable']) as c;
select col_is_pk('public','track_links','track_key','track_key is the pk (docs/06 §3)');
select has_index('public','track_links','track_links_needs_resolve', 'track_links track_links_needs_resolve');

-- ─── ADR-004: no score columns on any table ──────────────────────────────────
-- Scores are derived, never stored (CLAUDE.md §2.8). Since E05-03 the words do appear in the
-- schema — on the `round_scores` and `standings` *views*, which is the whole point of them —
-- so this is scoped to base tables. A view computes on read and cannot disagree with the rows
-- underneath it; a column can, and that is the failure ADR-004 exists to prevent.
select is_empty($$
  select c.table_name || '.' || c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
   where c.table_schema = 'public'
     and t.table_type = 'BASE TABLE'
     and c.column_name ~ '(readability|ear|score)'
     and c.table_name <> 'rounds'
$$, 'ADR-004: no stored score columns on any table — scores are derived on read');

-- And the corollary, which is what makes the narrowing above safe: the four scoring views
-- exist, so "no score columns" cannot be satisfied by having deleted them.
select is_empty($$
  select v
    from unnest(array['round_submitter_counts','guess_results','round_scores','standings']) v
   where to_regclass('public.' || v) is null
$$, 'the four E05-03 scoring views exist');

select * from finish();
rollback;
