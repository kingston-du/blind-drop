-- 20260905110000_cue_promote_more_kingston_customs.sql — cue catalog retexture.
-- docs/18-CUES.md §6, tasks/E35-cues.md's dated note under E35-02.
--
-- Two more of "kingston's friends"' round-level customs promoted into the shared catalog
-- permanently, each replacing a weak/hard-to-answer entry — same bar and same in-place-retext
-- mechanism as every prior revision in this file's chain:
--
--   - `tied_to_someone` ("A song tied to a specific person") retexted to "A song that makes
--     you think of them" — same idea, sharper phrasing; the two were near-duplicates anyway,
--     the kind of redundancy the 2026-08-28 revision cut on sight.
--   - `unexpected_from_you` ("A song that would give the wrong impression of you") retexted to
--     "A song for your current mood" — the original asks the dropper to model a stranger's
--     misreading of their own music taste, a level of indirection nothing else in the catalog
--     asks for.
--
-- ("A song you hate" is not touched here — it is already the catalog's `song_you_hate` entry
-- verbatim, so the owner's third request that day just points a round at the existing key; see
-- the plain data update alongside this migration, not a catalog change.)
--
-- Both "kingston's friends" rounds carrying these texts had their `prompt_key` set to an
-- unrelated placeholder to satisfy `cueDTO()`'s not-null check (the same DTO-bug workaround
-- from 2026-09-01); both are repointed here to their real, now-matching keys.

update public.cue_catalog set text = 'A song that makes you think of them'
 where key = 'tied_to_someone';

update public.cue_catalog set text = 'A song for your current mood'
 where key = 'unexpected_from_you';

update public.rounds set prompt_key = 'tied_to_someone'
 where group_id = '9c35f3aa-71a7-40da-ab3d-6246f37b96fc'
   and local_date = date '2026-09-05'
   and prompt = 'A song that makes you think of them';

update public.rounds set prompt_key = 'unexpected_from_you'
 where group_id = '9c35f3aa-71a7-40da-ab3d-6246f37b96fc'
   and local_date = date '2026-09-07'
   and prompt = 'A song for your current mood';
