-- 20260901130000_cue_promote_kingston_customs.sql — cue catalog retexture. docs/18-CUES.md
-- §6, tasks/E35-cues.md's dated note under E35-02.
--
-- The two hand-set, keyless cues on "kingston's friends" (2026-09-01: "Your lock tf in song",
-- 2026-09-02: "A tiktok song you actually listen to") were a one-off round-level override, not
-- a catalog change (see the 2026-09-01 dated notes in tasks/E35-cues.md). Owner now wants both
-- promoted into the shared catalog permanently, replacing two more weak/hard-to-answer/boring
-- entries — same bar as the `nobody_has_heard` retexture two migrations ago:
--
--   - `worst_by_favorite_artist` ("The worst song by an artist you love") needs a working
--     knowledge of an artist's whole discography to rank against, and overlaps thematically with
--     the catalog's other negative-framing lines (`song_you_hate`, `loved_by_all_not_you`).
--   - `should_be_more_famous` ("A song that should be more famous") is a generic taste-judgment
--     with no clear right answer and doesn't say anything about the person answering it, unlike
--     the rest of the catalog.
--
-- Retexted in place, same keys, same reasoning as every other in-place retext this feature has
-- done. Both keys already exist and are referenced nowhere yet by a frozen round, so no past
-- round's cue changes under this.
--
-- The two "kingston's friends" rounds that were carrying these texts with a placeholder
-- prompt_key (20260901's DTO-bug fix pointed them at getting_hyped/falling_asleep purely to
-- satisfy cueDTO()'s not-null check) are repointed here to their real, now-matching keys —
-- prompt_key finally means what it says for those two rows.

update public.cue_catalog set text = 'Your lock tf in song'
 where key = 'worst_by_favorite_artist';

update public.cue_catalog set text = 'A tiktok song you actually listen to'
 where key = 'should_be_more_famous';

update public.rounds set prompt_key = 'worst_by_favorite_artist'
 where group_id = '9c35f3aa-71a7-40da-ab3d-6246f37b96fc'
   and local_date = date '2026-09-01'
   and prompt = 'Your lock tf in song';

update public.rounds set prompt_key = 'should_be_more_famous'
 where group_id = '9c35f3aa-71a7-40da-ab3d-6246f37b96fc'
   and local_date = date '2026-09-02'
   and prompt = 'A tiktok song you actually listen to';
