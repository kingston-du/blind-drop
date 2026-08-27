// record.test.ts — the archive and the export. tasks/E07-06, docs/04 §5, docs/06 §6.
//
// The Record is the one screen that publishes what everybody dropped, so the question this
// file exists to answer is *which nights it is allowed to publish*. The answer is one word —
// `scored` — and it has two halves that fail differently:
//
//   · a `revealed` round is not in the archive **yet**. Its sheets are still being edited.
//   · a `voided` round is never in the archive **at all**. Its songs went back to their owners
//     unseen, and putting them on a page the next morning would retroactively break the blind
//     window they were sealed inside (CLAUDE.md §2.1). This is the one that cannot be fixed by
//     waiting, and the test below builds a voided round specifically to watch it stay out.
//
// The exclusion tests build their own group and walk it through the phases, because a state
// this file arranged is a state no other test can move. The paging and filtering tests read
// the seed's group instead: it is the only fixture with more than one night in it, and its
// three rounds hold 8, 6 and 3 songs, which is what makes "how many nights fit in a page of
// eight songs" a question with an exact answer rather than an approximate one.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  mintToken,
  newGroupOwner,
  newMember,
  type TestUser,
  tickRounds,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";
import { trackFields } from "../../functions/_shared/dto.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

const RECORD_KEYS = ["days", "next_cursor"];
const DAY_KEYS = ["entries", "local_date", "round_id"];
const ENTRY_KEYS = ["display_name", "track", "user_id"];
const EXPORT_KEYS = ["playlist_name", "tracks", "unresolved_count"];
const EXPORT_TRACK_KEYS = ["apple_music_id", "artist", "isrc", "spotify_uri", "title"];

/** Five distinct recordings from the fixture catalogue. */
const TRACKS = ["1440818664", "1440765580", "1452874255", "1440830827", "1442571948"];

/** The regional exclusive Spotify does not carry: it seals with `spotify_id: null` and stays
 *  that way, which is the only way to get an archive with something in it to be unresolved
 *  about (docs/06 §7, links.test.ts). */
const NO_SPOTIFY = "9000000002";

function record(token: string, query = ""): Promise<Json> {
  return call("groups", `/current/record${query}`, { token });
}

/** A group whose round is `open`, with everybody's song sealed inside it. */
async function sealed(
  name: string,
  appleMusicIds: string[],
): Promise<{ people: TestUser[]; group: Json }> {
  const { user, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
    cue_cadence: 0,
  });
  const people = [user];
  for (const person of ["Ben", "Cal", "Dee"].slice(0, appleMusicIds.length - 1)) {
    people.push(await newMember(group.invite_code as string, person));
  }
  for (const [i, person] of people.entries()) {
    const res = await call("rounds", "/current/submission", {
      method: "PUT",
      token: person.token,
      body: { apple_music_id: appleMusicIds[i] },
    });
    assertEquals(res.status, 200, `could not seal a song: ${JSON.stringify(res.body)}`);
  }
  return { people, group };
}

// ─── which nights are in it ──────────────────────────────────────────────────

Deno.test("a night enters the record when it scores, and not one phase earlier", async () => {
  const { people } = await sealed("Record Phases", TRACKS.slice(0, 3));
  const ana = people[0].token;

  const whileOpen = await record(ana);
  assertEquals(whileOpen.status, 200);
  assertEquals(keysOf(whileOpen.body.data), RECORD_KEYS);
  assertEquals(whileOpen.body.data.days, [], "tonight's sealed songs are not an archive entry");
  assertEquals(whileOpen.body.data.next_cursor, null);

  // Revealed: the cards are on everybody's screen and the name pool is public, so nothing here
  // is secret any more — and the night still stays out, because the sheets are open and the
  // results do not exist yet. The Record is an archive of finished nights (docs/04 §5).
  await tickRoundsAt(2);
  const revealed = await record(ana);
  assertEquals(revealed.status, 200);
  assertEquals(revealed.body.data.days, [], "a revealed round is not in the archive yet");

  await tickRoundsAt(4);
  const scored = await record(ana);
  assertEquals(scored.status, 200);
  assertEquals(scored.body.data.days.length, 1, "and it is, once the night is scored");

  const day = scored.body.data.days[0];
  assertEquals(keysOf(day), DAY_KEYS);
  assertEquals(day.entries.length, 3);
  assertEquals(keysOf(day.entries[0]), ENTRY_KEYS);
  assertEquals(
    day.entries.map((entry: Json) => entry.display_name),
    ["Ana", "Ben", "Cal"],
    "a night is ordered by name, never by who sealed first",
  );

  // Every entry carries a whole Track, both service links included, so every song in the
  // archive is linkable without a second call (docs/04 §5, docs/06 §2).
  assertEquals(keysOf(day.entries[0].track), [...trackFields()].sort());
  for (const entry of day.entries) {
    assert("apple_music_url" in entry.track, "an archive entry needs its Apple link");
    assert("spotify_url" in entry.track, "and its Spotify link, even when it is null");
  }
});

Deno.test("a voided night never enters the record", async () => {
  // Two submitters, one short of the three a round needs (docs/02 §2). The songs go back to
  // their owners unseen — and stay unseen. A voided round is the one archive exclusion that
  // waiting cannot fix: publishing it tomorrow would break the window it was sealed inside.
  const { people } = await sealed("Record Voided", TRACKS.slice(0, 2));
  await tickRoundsAt(2);

  const mine = await call("rounds", "/current", { token: people[0].token });
  assertEquals(mine.body.data.state, "voided", "the fixture must actually have voided");

  await tickRoundsAt(4);
  for (const person of people) {
    const res = await record(person.token);
    assertEquals(res.status, 200);
    assertEquals(res.body.data.days, [], "a voided night is not in the archive, ever");
  }
});

// ─── the seed's three nights ─────────────────────────────────────────────────
// 2026-08-08 (8 songs), 2026-08-09 (6) and 2026-08-10 (3). The seed leaves the last two
// mid-flight; one run of the real scheduler finishes them, and `scored` is terminal, so from
// here the group's archive is exactly those three nights however many times this file runs.

const ANA = "a0000000-0000-4000-8000-000000000001";
const DEE = "a0000000-0000-4000-8000-000000000004";
const NIGHTS = ["2026-08-10", "2026-08-09", "2026-08-08"];

async function seedArchive(): Promise<string> {
  // Twice: the first pass reveals 08-10, the second scores it. Idempotent either way.
  await tickRounds();
  await tickRounds();
  return mintToken(ANA);
}

function cursorFor(localDate: string): string {
  return btoa(JSON.stringify({ d: localDate })).replace(/=+$/, "");
}

Deno.test("the archive is newest night first, grouped by local date", async () => {
  const token = await seedArchive();
  const res = await record(token);

  assertEquals(res.status, 200);
  assertEquals(res.body.data.days.map((day: Json) => day.local_date), NIGHTS);
  assertEquals(res.body.data.days.map((day: Json) => day.entries.length), [3, 6, 8]);
  assertEquals(res.body.data.next_cursor, null, "seventeen songs fit in a page of fifty");

  // Ana left the group in no test, but the entry names come from `profiles` rather than the
  // roster on purpose (docs/02 §3): the night happened, and an archive that dropped a departed
  // member's songs would be an archive of a game nobody played.
  const names = res.body.data.days[2].entries.map((entry: Json) => entry.display_name);
  assertEquals(names, ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal"]);
});

Deno.test("a page holds whole nights, and the cursor walks them oldest-ward", async () => {
  const token = await seedArchive();

  // Eight songs of budget against nights of 3, 6 and 8. The first page takes 08-10 and stops
  // rather than splitting 08-09 across a boundary the cursor could not name; the last page
  // takes a night bigger than the whole budget, because a page that fit nothing would be a
  // page nobody could turn.
  const first = await record(token, "?limit=8");
  assertEquals(first.status, 200);
  assertEquals(first.body.data.days.map((day: Json) => day.local_date), ["2026-08-10"]);
  assertEquals(first.body.data.next_cursor, cursorFor("2026-08-10"));

  const second = await record(token, `?limit=8&cursor=${first.body.data.next_cursor}`);
  assertEquals(second.body.data.days.map((day: Json) => day.local_date), ["2026-08-09"]);
  assertEquals(second.body.data.next_cursor, cursorFor("2026-08-09"));

  const third = await record(token, `?limit=8&cursor=${second.body.data.next_cursor}`);
  assertEquals(third.body.data.days.map((day: Json) => day.local_date), ["2026-08-08"]);
  assertEquals(third.body.data.days[0].entries.length, 8, "a night is never split");
  assertEquals(third.body.data.next_cursor, null, "and the end of the archive says so");

  const past = await record(token, `?cursor=${cursorFor("2026-08-08")}`);
  assertEquals(past.body.data.days, []);
  assertEquals(past.body.data.next_cursor, null);
});

Deno.test("?member= narrows the archive to one person", async () => {
  const token = await seedArchive();

  const dee = await record(token, `?member=${DEE}`);
  assertEquals(dee.status, 200);
  // Dee dropped on 08-08 and 08-09 and sat out 08-10 — and that night is simply absent rather
  // than present-and-empty, because "played and dropped nothing" is not a state that exists.
  assertEquals(dee.body.data.days.map((day: Json) => day.local_date), NIGHTS.slice(1));
  for (const day of dee.body.data.days) {
    assertEquals(day.entries.length, 1);
    assertEquals(day.entries[0].user_id, DEE);
  }

  // A stranger's id selects nothing. It never reaches anything but this group's scored rounds,
  // so it cannot be used to ask whether somebody exists (docs/14 §4).
  const nobody = await record(token, "?member=00000000-0000-4000-8000-0000000000ff");
  assertEquals(nobody.status, 200);
  assertEquals(nobody.body.data.days, []);
});

Deno.test("paging parameters are validated, not clamped", async () => {
  const token = await seedArchive();

  for (const [query, field] of [
    ["?limit=0", "limit"],
    ["?limit=101", "limit"],
    ["?limit=ten", "limit"],
    ["?limit=2.5", "limit"],
    ["?cursor=not-a-cursor", "cursor"],
    [`?cursor=${btoa(JSON.stringify({ d: "yesterday" })).replace(/=+$/, "")}`, "cursor"],
    ["?member=ana", "member"],
  ] as const) {
    const res = await record(token, query);
    assertEquals(res.status, 400, query);
    assertEquals(res.body.error.code, "INVALID_INPUT", query);
    assertEquals(res.body.error.details.field, field, query);
  }

  // An empty value is an absent one — `?member=` is what a client sends when it clears the
  // filter, and it means "everyone" (docs/11 `record.filter.all`).
  const cleared = await record(token, "?member=&cursor=&limit=");
  assertEquals(cleared.status, 200);
  assertEquals(cleared.body.data.days.length, 3);
});

// ─── the export ──────────────────────────────────────────────────────────────

Deno.test("the export names the playlist, orders it like the archive, and counts what is missing", async () => {
  // Three songs, one of which Spotify does not carry. The Apple export therefore has all three
  // and the Spotify export has two and says so — the count is the whole point (docs/06 §6:
  // unresolved tracks are skipped and **stated**, never silently dropped).
  const { people, group } = await sealed("Record Export", [TRACKS[0], NO_SPOTIFY, TRACKS[1]]);
  await tickRoundsAt(2);
  await tickRoundsAt(4);
  const token = people[0].token;

  const spotify = await call("groups", "/current/record/export?service=spotify", { token });
  assertEquals(spotify.status, 200);
  assertEquals(keysOf(spotify.body.data), EXPORT_KEYS);
  assertEquals(spotify.body.data.playlist_name, `${group.name} — Blind Drop`);
  assertEquals(spotify.body.data.unresolved_count, 1, "Ben's song is not on Spotify");
  assertEquals(spotify.body.data.tracks.length, 2, "and it is left out of the list, not faked");
  assertEquals(keysOf(spotify.body.data.tracks[0]), EXPORT_TRACK_KEYS);
  for (const track of spotify.body.data.tracks) {
    assert(
      typeof track.spotify_uri === "string" && track.spotify_uri.startsWith("spotify:track:"),
      "a Spotify export carries URIs the client can post as-is",
    );
  }

  const apple = await call("groups", "/current/record/export?service=apple", { token });
  assertEquals(apple.status, 200);
  assertEquals(apple.body.data.unresolved_count, 0, "every song in the archive came from Apple");
  assertEquals(apple.body.data.tracks.length, 3);
  assertEquals(
    apple.body.data.tracks.map((track: Json) => track.apple_music_id),
    [TRACKS[0], NO_SPOTIFY, TRACKS[1]],
    "newest night first, and within a night the order the archive shows",
  );

  // The archive's order, verbatim: the list is the page, flattened.
  const archive = await record(token);
  assertEquals(
    archive.body.data.days.flatMap((day: Json) =>
      day.entries.map((entry: Json) => entry.track.apple_music_id)
    ),
    apple.body.data.tracks.map((track: Json) => track.apple_music_id),
  );
});

Deno.test("the export refuses a service it does not have", async () => {
  const { people } = await sealed("Record Export Service", TRACKS.slice(0, 3));
  const token = people[0].token;

  for (const query of ["", "?service=", "?service=tidal", "?service=SPOTIFY"]) {
    const res = await call("groups", `/current/record/export${query}`, { token });
    assertEquals(res.status, 400, query);
    assertEquals(res.body.error.code, "INVALID_INPUT", query);
    assertEquals(res.body.error.details.field, "service", query);
  }
});

Deno.test("the export is empty, not an error, before a group has finished a night", async () => {
  const { people, group } = await sealed("Record Export Empty", TRACKS.slice(0, 3));
  const res = await call("groups", "/current/record/export?service=spotify", {
    token: people[0].token,
  });

  assertEquals(res.status, 200);
  assertEquals(res.body.data.playlist_name, `${group.name} — Blind Drop`);
  assertEquals(res.body.data.tracks, []);
  assertEquals(res.body.data.unresolved_count, 0);
});

// ─── the doors ───────────────────────────────────────────────────────────────

Deno.test("both routes need a member of a group", async () => {
  for (const path of ["/current/record", "/current/record/export?service=spotify"]) {
    const anonymous = await call("groups", path, { token: null });
    assertEquals(anonymous.status, 401, path);
    assertEquals(anonymous.body.error.code, "UNAUTHENTICATED", path);
  }
});
