// links-worker/index.ts — the Spotify backfill. docs/06 §5 step 3. tasks/E07-05.
//
//   POST /   drain up to twenty unresolved track_links rows
//
// Driven by pg_cron every minute through pg_net (0019), in the same minute as the scheduler.
// It exists because of one sentence in docs/06 §5: *sealing a song must never fail because
// Spotify was slow.* The submission path therefore gives Spotify 700ms and then gives up,
// leaving a `track_links` row with an incremented attempt count — and something has to come
// back for those rows later, or the promise that every song in The Record is exportable
// quietly becomes "most songs, depending on how Spotify felt that evening".
//
// Three things this worker is careful about:
//
//   1. **It is not a person.** No user, no group, no membership — `requireServiceRole` and
//      nothing else. A member who could POST here could make the server issue arbitrary
//      outbound lookups on a timer (docs/14 §8).
//   2. **It never gives up on a row it has not actually failed.** The three-attempt rule lives
//      in `trackLinks.ts`, shared with the inline path, because the invariant docs/15 §2
//      asserts — no track left in limbo — is only true while the two agree on what a failure
//      is.
//   3. **It cannot leak.** It touches `track_links` and `submissions.track_meta`, and its
//      response is four integers about its own work. Nothing here is keyed by a group, reads a
//      round, or knows what phase anything is in — a track is a track whether or not it is
//      sealed inside tonight's blind window, and the only field it writes into a submission is
//      the Spotify link, by a SQL function that can write nothing else (0017).

import { ok, serveFunction } from "../_shared/http.ts";
import { requireServiceRole } from "../_shared/auth.ts";
import { serviceClient } from "../_shared/db.ts";
import {
  BACKFILL_BATCH,
  backfillTrack,
  type DueLink,
  dueForBackfill,
} from "../_shared/music/trackLinks.ts";

/**
 * How many lookups are in flight at once.
 *
 * Twenty sequential lookups at up to 2.5s each is fifty seconds, which does not fit in the
 * minute this job owns; twenty at once is a burst Spotify has every right to rate-limit. Four
 * is the boring middle: a full batch of worst-case-slow rows finishes in about thirteen
 * seconds, and a healthy batch in well under one.
 */
const CONCURRENCY = 4;

serveFunction("links-worker", {
  "POST /": async (req) => {
    await requireServiceRole(req);
    const db = serviceClient();

    const due = await dueForBackfill(db, BACKFILL_BATCH);
    let resolved = 0;
    let gaveUp = 0;
    let patched = 0;

    for (let i = 0; i < due.length; i += CONCURRENCY) {
      const batch: DueLink[] = due.slice(i, i + CONCURRENCY);
      const outcomes = await Promise.all(batch.map((row) => backfillTrack(db, row)));
      for (const outcome of outcomes) {
        if (outcome.outcome === "resolved") resolved += 1;
        if (outcome.outcome === "gave_up") gaveUp += 1;
        patched += outcome.patched;
      }
    }

    // Counts of this worker's own work, for the logs and for the tests. `examined` is bounded
    // by the batch size, so a caller learns how much was waiting only up to twenty — and the
    // only caller is cron.
    return ok({ examined: due.length, resolved, gave_up: gaveUp, patched });
  },
});
