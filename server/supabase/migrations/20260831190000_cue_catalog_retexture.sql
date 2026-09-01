-- 20260831190000_cue_catalog_retexture.sql — cue catalog retexture. docs/18-CUES.md §3, §6,
-- tasks/E35-cues.md's dated note under E35-02.
--
-- Owner retired one entry and retexted another:
--   1. `active = false` on `workout` ("A song that makes you walk faster") — never deleted,
--      since `rounds.prompt_key` may already reference it, and a round's `prompt` is the
--      frozen text anyway (§3's whole point: the catalog can change under a round without
--      touching what already shipped).
--   2. `text` updated in place on `getting_hyped`, from "A song for getting hyped up" to
--      "A song that excites you" — same key, same reasoning as the 20260828 revision's
--      in-place re-texts.
--
-- This drops the active count from 41 to 40. 41 was prime; 40 is not. `cue_for_round()`
-- (`20260828150000`) hardcoded the modulus at 41 and relied on that primality so any
-- hash-derived odd `stride` below it was automatically coprime — a composite modulus breaks
-- that for free: a `stride` sharing a factor with `N` shortens the cycle, and can leave some
-- `(n + offset)` slots mapping past the end of the active set entirely (no cue on a round that
-- should have one). Rather than force the count back to a prime by retiring cues nobody asked
-- to retire, `cue_for_round()` is recreated here to read `N` live (`count(*) from cue_catalog
-- where active`) and search forward from its hash-derived candidate `stride` until it lands on
-- one coprime with that live `N`, using Postgres's built-in `gcd()`. Coprimality — not
-- primality — is what the full-period property in docs/18-CUES.md §3 actually needs, so this
-- also means the catalog can shrink or grow by any amount in the future without a matching
-- constant edit.
--
-- No key is renamed or deleted, so no existing `rounds.prompt_key` reference breaks.

-- ─── retire one row ───────────────────────────────────────────────────────────

update public.cue_catalog set active = false where key = 'workout';

-- ─── retext one row in place ─────────────────────────────────────────────────

update public.cue_catalog set text = 'A song that excites you' where key = 'getting_hyped';

-- ─── cue_for_round: live active count, coprime-stride search ────────────────
-- Forward-only replacement of the 20260828150000 definition. `language sql` becomes
-- `language plpgsql` because finding a coprime stride needs a small bounded loop; the
-- function's signature, determinism, and revoked grants are unchanged.

create or replace function public.cue_for_round(
  p_group_id uuid,
  p_n        int,
  p_cadence  smallint
) returns table (prompt_key text, prompt text)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_cnt    int;
  v_h      bigint;
  v_seed   int;
  v_stride int;
  v_off    int;
  v_idx    int;
begin
  select pg_catalog.count(*)::int into v_cnt from public.cue_catalog where active;

  -- offset/stride/seed derive once from the group id's hash, so two circles on the same
  -- cadence draw different cues and a circle does not always start its cycle on cue #0.
  v_h := (pg_catalog.hashtext(p_group_id::text)::bigint & 4294967295::bigint);

  v_seed   := (v_h % v_cnt)::int;
  v_off    := ((v_h / 4096) % v_cnt)::int;
  v_stride := (1 + (v_h / 64) % greatest(v_cnt - 1, 1))::int;

  -- hunt forward for a stride coprime with the live active count, so
  -- i -> catalog[(i*stride + seed) mod v_cnt] is a full bijection on Z/v_cnt regardless of
  -- whether v_cnt is prime.
  while pg_catalog.gcd(v_stride, v_cnt) <> 1 loop
    v_stride := (v_stride % v_cnt) + 1;
  end loop;

  if p_cadence > 0 and (p_n + v_off) % p_cadence = 0 then
    v_idx := (((p_n + v_off) / p_cadence) * v_stride + v_seed) % v_cnt;
  else
    v_idx := null;
  end if;

  -- Always exactly one row, both columns null when the round is not cued — callers (e.g.
  -- ensure_rounds()'s `cross join lateral`) rely on that to insert/rewrite an uncued round
  -- too, not just cued ones.
  return query
    select c.key, c.text
      from (select v_idx as idx) p
      left join lateral (
        select c2.key, c2.text
          from public.cue_catalog c2
         where c2.active
         order by c2.key
         offset coalesce(p.idx, 0)
         limit 1
      ) c on p.idx is not null;
end;
$$;

comment on function public.cue_for_round(uuid, int, smallint) is
  'The cue for a circle''s n-th round under a cadence, or null when the round is not cued '
  '(docs/18-CUES.md §3). Deterministic: offset/stride/seed derive from the group id, and the '
  'active cue count is read live with a coprime stride searched at call time, so the full-cycle '
  'guarantee holds regardless of whether that count is prime. Revised 2026-08-31 when the '
  'active count dropped from 41 (prime) to 40; see this migration''s header comment.';

revoke all on function public.cue_for_round(uuid, int, smallint)
  from public, anon, authenticated;
