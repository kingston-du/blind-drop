// links.test.ts — the backfill worker. tasks/E07-05, docs/06 §5, docs/15 §2.
//
// `tests/db/links.sql` covers the data: which rows are due, in what order, and the invariant
// that no scored track is left in limbo. This file covers the worker itself — who may call it,
// and whether three failed passes actually end in a row that says "never", rather than a row
// that gets picked up again every minute for the rest of the product's life.
//
// The fixture catalogue makes both failure modes available (`_shared/music/fixtures.ts`):
// `9000000002` is a regional exclusive Spotify's catalogue does not carry, and `9000000003`
// answers so slowly that no budget in this app survives it. A submission of either succeeds
// with `spotify_id: null` — that is E07-04's rule, sealing never fails because Spotify was
// slow — and leaves exactly the row this worker exists to come back for.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  ANON_KEY,
  API_URL,
  call,
  newGroupOwner,
  SERVICE_KEY,
  type TestUser,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

/** One pass of the backfill, as cron would run it. */
function drain(token: string | null = SERVICE_KEY) {
  return call("links-worker", "/", { method: "POST", token, body: {} });
}

/** A member who has sealed a song Spotify will never answer for. */
async function droppedUnresolvable(name: string, appleMusicId: string): Promise<TestUser> {
  const { user } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const res = await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: appleMusicId },
  });
  assertEquals(res.status, 200, "sealing must succeed even when Spotify does not answer");
  assertEquals(res.body.data.track.spotify_id, null, "and it must succeed without a link");
  return user;
}

// ─── who may call it ─────────────────────────────────────────────────────────

Deno.test("the backfill worker is closed to everybody but the scheduler", async () => {
  // It has no user and no group, so none of the usual pipeline applies to it — which means the
  // only thing standing between a member and an endpoint that makes the server issue outbound
  // lookups on demand is this guard (docs/14 §8). The same guard `push-worker` will use, which
  // is a rather more serious door: a member who could drain the outbox could send the group
  // notifications.
  const { user } = await newGroupOwner("Ana", {
    name: "Worker Door",
    timezone: zoneWhereLocalHourIs(12),
  });

  for (
    const [label, res] of [
      ["anonymous", await drain(null)],
      ["a member's own token", await drain(user.token)],
      // The anon key is the interesting one: a genuinely valid, platform-accepted JWT that
      // simply is not the service key. It is the case our own comparison has to catch, where
      // the two above would also be caught by any guard at all.
      ["the anon key", await drain(ANON_KEY)],
    ] as const
  ) {
    assertEquals(res.status, 401, label);
    assertEquals(res.body.error.code, "UNAUTHENTICATED", label);
  }

  // A malformed bearer is refused by the platform gateway before our handler ever runs, so the
  // body is its envelope rather than ours. Asserted as a status only, and noted here so that a
  // future reader does not "fix" the missing `error.code` by loosening the guard.
  assertEquals((await drain(`${SERVICE_KEY}x`)).status, 401, "a malformed key never reaches us");

  assertEquals((await drain()).status, 200, "and open to the service key");
});

Deno.test("the worker reports only its own work", async () => {
  const res = await drain();

  assertEquals(res.status, 200);
  assertEquals(Object.keys(res.body.data).sort(), ["examined", "gave_up", "patched", "resolved"]);
  // Four integers about the worker's own pass. Nothing keyed by a group, nothing about a round,
  // and `examined` is bounded by the batch size — so even the one caller who can reach this
  // learns "up to twenty were waiting" and not how many people sealed what.
  for (const value of Object.values(res.body.data)) assert(typeof value === "number");
});

// ─── three strikes ───────────────────────────────────────────────────────────

Deno.test("a track Spotify does not carry is given up on after three attempts, and only then", async () => {
  // The regional exclusive. The submission spent attempt one, so two passes of the worker take
  // it to three — and the third is the one that writes `unresolvable`. The assertion that
  // matters is the *second* pass: a worker that gave up early would strand a track that a
  // retry would have found, which is the failure the retry budget exists to prevent.
  await droppedUnresolvable("Backfill Exclusive", "9000000002");

  const first = await drain();
  assertEquals(first.status, 200);
  assertEquals(first.body.data.resolved, 0, "there is nothing for Spotify to find");

  const second = await drain();
  assertEquals(second.status, 200);

  // By now the row has had three attempts and left the due set, so a fourth pass finds nothing
  // to do with it. That is the difference between a queue and a treadmill.
  const third = await drain();
  assertEquals(third.status, 200);
  assertEquals(third.body.data.gave_up, 0, "nothing left to give up on — it already did");

  const rows = await trackLinkRow("isrc:GBXXX0000001");
  assertEquals(rows.unresolvable, true, "flagged, in writing, so nobody looks again");
  assertEquals(rows.resolve_attempts, 3, "after exactly three attempts, not two and not four");
  assertEquals(rows.spotify_id, null);
});

Deno.test("a timeout is a failure like any other, and the sealed song is untouched", async () => {
  // `9000000003` answers slower than any budget this app allows. docs/06 §5 is explicit that
  // this must not fail the submission, and E07-04 asserts that; what this adds is that the
  // backfill treats a timeout as an attempt rather than as a reason to keep trying forever.
  const user = await droppedUnresolvable("Backfill Slow", "9000000003");

  await drain();
  await drain();

  const row = await trackLinkRow("isrc:GBXXX0000002");
  assertEquals(row.resolve_attempts, 3);
  assertEquals(row.unresolvable, true);

  // The member's own card is exactly as they left it: same song, no Spotify link, and nothing
  // about it says the server spent the evening failing to look it up.
  const mine = await call("rounds", "/current", { token: user.token });
  assertEquals(mine.body.data.my_submission.track.title, "Slow Lookup");
  assertEquals(mine.body.data.my_submission.track.spotify_id, null);
  assertEquals(mine.body.data.my_submission.track.spotify_url, null);
});

// ─── the promise ─────────────────────────────────────────────────────────────

Deno.test("no track anywhere is left in limbo", async () => {
  // docs/15 §2, checked against whatever the whole suite has managed to create in this database
  // — every group, every submission, resolved and unresolved alike. It is a stronger statement
  // than the pgTAP version of the same assertion, which sees only the seed plus its own rows.
  await drain();
  await drain();
  await drain();

  const limbo = await serviceQuery(
    "track_links?select=track_key,resolve_attempts&spotify_id=is.null" +
      "&unresolvable=is.false&resolve_attempts=gte.3",
  );
  assertEquals(limbo, [], "every row with three attempts spent and no link is flagged");
});

// ─── reading the cache back ──────────────────────────────────────────────────
// The tests above assert on `track_links`, which no client can read (0003, 0010) and no
// endpoint returns. These go through PostgREST with the service key, the way the worker does.

async function serviceQuery(path: string): Promise<Json[]> {
  const res = await fetch(`${API_URL}/rest/v1/${path}`, {
    headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) throw new Error(`rest ${path}: ${res.status} ${await res.text()}`);
  return await res.json();
}

async function trackLinkRow(trackKey: string): Promise<Json> {
  const rows = await serviceQuery(
    `track_links?select=track_key,spotify_id,resolve_attempts,unresolvable&track_key=eq.${
      encodeURIComponent(trackKey)
    }`,
  );
  assertEquals(rows.length, 1, `expected one track_links row for ${trackKey}`);
  return rows[0];
}
