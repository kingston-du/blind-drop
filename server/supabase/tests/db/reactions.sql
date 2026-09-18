-- E46-01 — one mark per member per card, changeable, clearable, and never a stored tally.
-- docs/19-REACTIONS.md §6, docs/15 AC-12.
begin;
set search_path = public, extensions, tests;
select plan(11);

select has_table('public', 'reactions', 'the reactions table exists');

-- The set of three is closed (docs/19 §5). An enum rather than a text check, so a fourth kind
-- is a migration somebody writes on purpose.
select set_eq(
  $$ select unnest(enum_range(null::public.reaction_kind))::text $$,
  $$ values ('loved'), ('interesting'), ('not_for_me') $$,
  'reaction_kind is exactly the three closed kinds'
);

select ok(
  (select relrowsecurity and relforcerowsecurity
     from pg_class where oid = 'public.reactions'::regclass),
  'row level security is enabled and forced'
);
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'reactions' and grantee in ('anon', 'authenticated', 'public')),
  0,
  'no client role holds any grant on the table'
);

-- **No stored count anywhere.** CLAUDE.md §2.8 and docs/19 §6: the counts on the results screen
-- are a `group by` at read time, so there must be no column here or on `submissions` that a
-- future reader could mistake for an authoritative tally — and none that exists during the
-- blind window at all.
select is_empty(
  $$ select table_name || '.' || column_name
       from information_schema.columns
      where table_schema = 'public'
        and table_name in ('reactions', 'submissions', 'rounds')
        and (column_name like '%reaction%count%' or column_name like '%loved%'
             or column_name like '%_tally' or column_name like 'reaction_%s') $$,
  'no reaction tally column exists on reactions, submissions or rounds'
);

-- ─── the fixture: the §4.4 round, which seed.sql already leaves `scored` ─────
-- Ana reacts to Dee's card (no. 1) and to her own (no. 4). Her own is the case docs/19 §4
-- permits and `guesses_not_self` forbids for the other table — there is deliberately no
-- `reactions_not_self` constraint to trip over here.
insert into public.reactions (round_id, reactor_id, submission_id, kind)
values (tests.round_on('2026-08-08'), tests.person('Ana'),
        tests.card_of('2026-08-08', 'Dee'), 'loved'),
       (tests.round_on('2026-08-08'), tests.person('Ana'),
        tests.card_of('2026-08-08', 'Ana'), 'interesting');
select is((select count(*)::int from public.reactions), 2, 'two marks are stored');

select is(
  (select kind::text from public.reactions
    where reactor_id = tests.person('Ana')
      and submission_id = tests.card_of('2026-08-08', 'Ana')),
  'interesting',
  'a member may mark their own card — there is no not-self constraint (docs/19 §4)'
);

-- One mark per person per card. A second row for the same pair must be impossible: changing
-- your mind is an upsert on this index, never a second row that would double the count.
select throws_ok(
  format(
    $$insert into public.reactions (round_id, reactor_id, submission_id, kind)
      values ('%s', '%s', '%s', 'not_for_me')$$,
    tests.round_on('2026-08-08'), tests.person('Ana'), tests.card_of('2026-08-08', 'Dee')),
  '23505',
  null,
  'the same member cannot hold two marks on one card'
);

-- Changing your mind replaces.
update public.reactions set kind = 'not_for_me'
 where reactor_id = tests.person('Ana')
   and submission_id = tests.card_of('2026-08-08', 'Dee');
select is(
  (select count(*)::int from public.reactions where reactor_id = tests.person('Ana')),
  2,
  'changing a mark replaces it rather than adding one'
);

-- Clearing deletes. There is no tombstone, no `kind = null`, and nothing left behind that a
-- count could pick up.
delete from public.reactions
 where reactor_id = tests.person('Ana')
   and submission_id = tests.card_of('2026-08-08', 'Dee');
select is(
  (select count(*)::int from public.reactions where reactor_id = tests.person('Ana')),
  1,
  'clearing a mark deletes the row'
);

-- A different member on the same card is a different mark, and must land.
insert into public.reactions (round_id, reactor_id, submission_id, kind)
values (tests.round_on('2026-08-08'), tests.person('Ben'),
        tests.card_of('2026-08-08', 'Ana'), 'loved');
select is(
  (select count(*)::int from public.reactions
    where submission_id = tests.card_of('2026-08-08', 'Ana')),
  2,
  'two members may mark the same card'
);

select * from finish();
rollback;
