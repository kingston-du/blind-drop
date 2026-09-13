// leak.test.ts — the golden files. tasks/E04-03, docs/15 AC-1, docs/14 §3.
//
// Every response reachable during a round's `open` phase is captured as a golden file of its
// **key set**, and diffed on every run. Values are not asserted: fixture churn would make this
// noisy and nobody would trust it. Keys are the whole point — a leak is a key that should not
// be there.
//
// **The friction is the control.** Adding a field to an `open`-phase response means editing
// `dto.ts`, editing the handler, and then coming here and updating a checked-in file with a
// commit message explaining why. Three deliberate acts. That is a very different thing from a
// `select *` picking up a new column, which is how this class of bug actually ships.
//
// The last test in this file is the one that keeps the set honest: it enumerates every route
// in `functions/` and fails when one has no golden entry. A new endpoint cannot be added
// without a human deciding what it is allowed to return.
//
//   Regenerate deliberately, never reflexively:
//     GOLDEN=update npm run test:functions -- leak

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  mintToken,
  newGroupOwner,
  newMember,
  newNamedUser,
  newUser,
  serviceRpc,
  type TestUser,
  tickRounds,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

const GOLDEN_DIR = new URL("../golden/", import.meta.url);
const UPDATING = Deno.env.get("GOLDEN") === "update";

interface Golden {
  /** What this capture is, in one line, for whoever reads the diff. */
  about: string;
  /** The envelope's own keys — `["data", "server_now"]` for every success. */
  envelope: string[];
  /** `data`'s key set, sorted. The assertion that matters. */
  data: string[];
  /** Key sets of nested objects, by dotted path. Absent when the field is null. */
  nested?: Record<string, string[]>;
}

function shapeOf(body: Record<string, unknown>, about: string): Golden {
  const data = body.data as Record<string, unknown>;
  const nested: Record<string, string[]> = {};

  const walk = (value: unknown, path: string) => {
    if (value === null || typeof value !== "object") return;
    if (Array.isArray(value)) {
      // One entry stands for the array: every element of a list must have one shape, and
      // recording per-index key sets would make the golden vary with the fixture's length.
      if (value.length > 0) walk(value[0], `${path}[]`);
      return;
    }
    nested[path] = keysOf(value);
    for (const [key, child] of Object.entries(value)) walk(child, `${path}.${key}`);
  };
  for (const [key, child] of Object.entries(data)) walk(child, key);

  return {
    about,
    envelope: keysOf(body),
    data: keysOf(data),
    ...(Object.keys(nested).length ? { nested } : {}),
  };
}

async function assertGolden(name: string, body: Record<string, unknown>, about: string) {
  const actual = shapeOf(body, about);
  const path = new URL(`${name}.json`, GOLDEN_DIR);
  const serialised = `${JSON.stringify(actual, null, 2)}\n`;

  if (UPDATING) {
    await Deno.writeTextFile(path, serialised);
    return;
  }

  let expected: Golden;
  try {
    expected = JSON.parse(await Deno.readTextFile(path));
  } catch {
    throw new Error(
      `No golden file for "${name}". A response with no golden file is a response nobody has ` +
        `reviewed (docs/14 §3). Capture it with:\n\n    GOLDEN=update npm run test:functions -- leak\n\n` +
        `and read the diff before committing it. What it would have been:\n${serialised}`,
    );
  }

  assertEquals(
    actual,
    expected,
    `The shape of "${name}" changed. If that is intended, say why in the commit message and ` +
      `regenerate with GOLDEN=update. If it is not, you have just widened an open-phase payload.`,
  );
}

// ─── the captures ────────────────────────────────────────────────────────────

function openGroup(name: string) {
  // Cue off: the round goldens below assert the exact minimal `open` key set, so a cued round
  // would be a non-deterministic extra key (the hash-derived cadence parity is coin-flip). The
  // cued shape gets its own golden and its own assertion further down.
  return newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 0,
  });
}

Deno.test("golden: GET /rounds/current, open, caller has sealed a song", async () => {
  const { user } = await openGroup("Golden Open");
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });
  const res = await call("rounds", "/current", { token: user.token });
  assertEquals(res.status, 200);
  await assertGolden(
    "round_open",
    res.body,
    "GET /rounds/current during `open`, for a member who has submitted. docs/04 §4: the key " +
      "set is exactly {round_id, local_date, state, opens_at, reveals_at, scores_at, " +
      "my_submission} and there is no other key.",
  );
});

Deno.test("golden: GET /rounds/current, open, caller has not submitted", async () => {
  const { user, group } = await openGroup("Golden Open Nosub");
  const ben = await newMember(group.invite_code as string, "Ben");
  // Ana submits; Ben must still see a payload with nothing of hers in it.
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });
  const res = await call("rounds", "/current", { token: ben.token });
  await assertGolden(
    "round_open_nosub",
    res.body,
    "GET /rounds/current during `open`, for a member who has not submitted — while another " +
      "member has. `my_submission` is null and no nested track shape appears at all.",
  );
});

Deno.test("golden: GET /rounds/current, open, cued", async () => {
  // cadence 1 → every night is cued, so the `cue` key is deterministically present. This is
  // the widened `open` payload `docs/18-CUES.md` §8 adds: the base key set plus one top-level
  // `cue: {key, text}`, and nothing else.
  const { user } = await newGroupOwner("Ana", {
    name: "Golden Open Cued",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 1,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });
  const res = await call("rounds", "/current", { token: user.token });
  assertEquals(res.status, 200);
  await assertGolden(
    "round_open_cued",
    res.body,
    "GET /rounds/current during `open` for a cued round. One top-level `cue: {key, text}` " +
      "beside the base keys — identical for every member, independent of who has submitted.",
  );
});

Deno.test("golden: GET /rounds/current, the dark hours", async () => {
  // The one payload on this route whose key set depends on the clock: an `open` round that has
  // not opened yet, with a finished round behind it, carries `previous_cue` as well as `cue`
  // (`docs/18-CUES.md` §7, §8). 03:00 local, opening at 10:00 — real time, real timezone.
  const { user, group } = await newGroupOwner("Ana", {
    name: "Golden Dark Hours",
    timezone: zoneWhereLocalHourIs(3),
    reveal_hour: 20,
    cue_cadence: 1,
  });
  // `GET /current` first: it is what materialises the round (`ensure_rounds()` on a miss), and
  // the seed helper dates its row relative to the group's earliest existing one.
  await call("rounds", "/current", { token: user.token });
  // Seeded `scored`, which is the *maximal* dark-hours payload: a voided night behind these
  // hours yields `previous_cue` alone, so pinning that one would leave `previous_round_id`
  // outside the golden and outside the leak audit's reach.
  await serviceRpc("seed_previous_round", {
    p_group_id: group.id,
    p_prompt_key: "aux_song",
    p_prompt: "Your go-to aux song",
    p_state: "scored",
  });
  const res = await call("rounds", "/current", { token: user.token });
  assertEquals(res.status, 200);
  await assertGolden(
    "round_darkhours",
    res.body,
    "GET /rounds/current between local midnight and `opens_at`. The round is the coming " +
      "night's, so alongside its own `cue` it carries `previous_cue` and `previous_round_id` " +
      "— the cue of the round that just ended and the way through to its results, which is " +
      "the night the screen over it is talking about. Still nothing about anybody's " +
      "participation.",
  );
});

Deno.test("a cue is byte-identical for every member and independent of participation", async () => {
  // docs/18-CUES.md §2, §11.5. A cue is assigned before the round opens and never touches
  // submission or guess state, so it must be byte-identical whether or not the caller has
  // submitted, and its presence must not vary by participation either.
  const { user: ana, group } = await newGroupOwner("Ana", {
    name: "Cue Identity",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 1,
  });
  const ben = await newMember(group.invite_code as string, "Ben");
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: ana.token,
    body: { apple_music_id: "1440818664" },
  });

  const forAna = (await call("rounds", "/current", { token: ana.token })).body.data;
  const forBen = (await call("rounds", "/current", { token: ben.token })).body.data;

  // Both see the cue, and it is the same object.
  assertEquals(typeof forAna.cue, "object");
  assertEquals(forAna.cue, forBen.cue);

  // The whole body differs only in `my_submission` — the cue does not budge.
  const strip = (d: Record<string, unknown>) => ({ ...d, my_submission: null });
  assertEquals(strip(forAna), strip(forBen));

  // And a round with the cue off has no `cue` key at all — absent, not null.
  const off = await newGroupOwner("Cal", {
    name: "Cue Off",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 0,
  });
  const offRound = (await call("rounds", "/current", { token: off.user.token })).body.data;
  assertEquals("cue" in offRound, false);
});

Deno.test("golden: GET /rounds/current, voided", async () => {
  const { user } = await newGroupOwner("Ana", {
    name: "Golden Voided",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
    cue_cadence: 0,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });
  await tickRoundsAt(2);
  const res = await call("rounds", "/current", { token: user.token });
  assertEquals((res.body.data as Record<string, unknown>).state, "voided");
  await assertGolden(
    "round_voided",
    res.body,
    "GET /rounds/current for a `voided` round. Identical key set to `open`: the caller's own " +
      "song comes back and there is no count of how many did submit (docs/08 §5).",
  );
});

Deno.test("golden: PUT /rounds/current/submission", async () => {
  const { user } = await openGroup("Golden Submit");
  const res = await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });
  await assertGolden(
    "submission",
    res.body,
    "PUT /rounds/current/submission — the caller's own sealed track.",
  );
});

Deno.test("golden: GET /groups/current", async () => {
  const { user, group } = await openGroup("Golden Group");
  await newMember(group.invite_code as string, "Ben");
  const res = await call("groups", "/current", { token: user.token });
  await assertGolden(
    "groups_current",
    res.body,
    "GET /groups/current. The roster is who is in the group, not who has done anything — and " +
      "`joined_at` must never appear on a member (docs/04 §3, docs/14 §3).",
  );
});

Deno.test("golden: GET /groups/{group_id}/members/{user_id}/profile during open", async () => {
  const { user: ana, group } = await openGroup("Golden Member Profile");
  const ben = await newMember(group.invite_code as string, "Ben");
  // Ben does submit tonight. The profile response must remain a finished-history lens: no song,
  // no round, no participation bit, and no count can move until the night is scored.
  const seal = await call("rounds", "/current/submission", {
    method: "PUT",
    token: ben.token,
    body: { apple_music_id: "1440818664" },
  });
  assertEquals(seal.status, 200);

  const res = await call("groups", `/${group.id}/members/${ben.id}/profile`, { token: ana.token });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  assertEquals(res.body.data.drop_count, 0);
  assertEquals(res.body.data.recent_tracks, []);
  await assertGolden(
    "groups_member_profile",
    res.body,
    "GET /groups/{group_id}/members/{user_id}/profile during `open`, after that member has " +
      "submitted. Every profile field remains a function of scored rounds only; the reviewed " +
      "shape deliberately contains no current-round, submission, or other-member field.",
  );
});

Deno.test("golden: GET /groups/{group_id}/insights during open", async () => {
  const { user: ana, group } = await openGroup("Golden Insights");
  const ben = await newMember(group.invite_code as string, "Ben");
  // Ben seals tonight, but the new endpoint may name nobody until a whole round has scored.
  // This proves Insights is a finished-history lens rather than a participation signal.
  const seal = await call("rounds", "/current/submission", {
    method: "PUT",
    token: ben.token,
    body: { apple_music_id: "1440818664" },
  });
  assertEquals(seal.status, 200);

  const res = await call("groups", `/${group.id}/insights`, { token: ana.token });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  assertEquals(res.body.data, {
    your_reads: [],
    reads_you: [],
    mutual_recognition: [],
    mutual_misses: [],
    confusion: { scored_rounds: 0, minimum_rounds: 4, pairs: [] },
  });
  await assertGolden(
    "groups_insights",
    res.body,
    "GET /groups/{group_id}/insights during `open`, after another member has submitted. Every " +
      "field remains a function of scored rounds only, so the response names nobody and carries " +
      "no current-round, submission, or participation field.",
  );
});

Deno.test("golden: GET /groups (the switcher)", async () => {
  const { user, group } = await openGroup("Golden Circles");
  await newMember(group.invite_code as string, "Ben");
  // A second circle for the same caller, so the capture is genuinely a list and not one entry
  // that happens to be an array — `E18-01`'s cap is three, well clear of two here.
  await call("groups", "/", {
    method: "POST",
    token: user.token,
    body: { name: "Golden Circles Two", timezone: zoneWhereLocalHourIs(12) },
  });
  const res = await call("groups", "/", { token: user.token });
  assertEquals(res.status, 200);
  await assertGolden(
    "groups_circles",
    res.body,
    "GET /groups, `E18-02`. One row per circle the caller holds: `{id, name, my_state, " +
      "needs_action}` and nothing else — no member count, no submission count, no timestamp " +
      "that belongs to anyone but the caller.",
  );
});

Deno.test("golden: GET /groups/people-you-played-with", async () => {
  const { user, group } = await openGroup("Golden People");
  await newMember(group.invite_code as string, "Ben");
  const res = await call("groups", "/people-you-played-with", { token: user.token });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  await assertGolden(
    "groups_people_you_played_with",
    res.body,
    "GET /groups/people-you-played-with. Shared-circle identities only: no group id, membership " +
      "date, role, round, or social-graph metadata.",
  );
});

Deno.test("golden: POST /groups/current/invitations", async () => {
  // E20-01. The invitee is a real account with no membership anywhere — this route's whole
  // point is that a pending invitation is not a roster entry.
  const { user } = await openGroup("Golden Invite");
  const invitee = await newNamedUser("Invitee");
  const res = await call("groups", "/current/invitations", {
    method: "POST",
    token: user.token,
    body: { user_id: invitee.id },
  });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  await assertGolden(
    "invitation",
    res.body,
    "POST /groups/current/invitations. `{id, group:{id,name}, invited_by:{user_id," +
      "display_name}, created_at, expires_at}` — no roster, no round, nothing about the " +
      "circle beyond its own name (E20-01).",
  );
});

Deno.test("golden: GET /groups/invitations", async () => {
  const { user } = await openGroup("Golden Invite Mine");
  const invitee = await newNamedUser("Invitee");
  await call("groups", "/current/invitations", {
    method: "POST",
    token: user.token,
    body: { user_id: invitee.id },
  });
  const res = await call("groups", "/invitations", { token: invitee.token });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  await assertGolden(
    "invitations_mine",
    res.body,
    "GET /groups/invitations — the caller's own pending invitations, across every circle. " +
      "One entry per invitation, same shape as the create response (E20-01).",
  );
});

Deno.test("golden: GET /groups/:group_id/invitations", async () => {
  const { user, group } = await openGroup("Golden Invite Sent");
  const invitee = await newNamedUser("Sent Invitee");
  await call("groups", "/current/invitations", {
    method: "POST",
    token: user.token,
    body: { user_id: invitee.id },
  });
  const res = await call("groups", `/${group.id}/invitations`, { token: user.token });
  assertEquals(res.status, 200, JSON.stringify(res.body));
  await assertGolden(
    "invitations_sent",
    res.body,
    "GET /groups/:group_id/invitations — the pending invitations this circle has sent. " +
      "`{id, invited_user, expires_at}` and nothing else: not the circle (the caller named " +
      "it), not the inviter, and nothing about the invitee beyond the id used to invite them.",
  );
});

Deno.test("golden: GET /me", async () => {
  const { user } = await openGroup("Golden Me");
  const res = await call("me", "/", { token: user.token });
  await assertGolden("me", res.body, "GET /me.");
});

Deno.test("golden: GET /tracks/search", async () => {
  const { user } = await openGroup("Golden Search");
  const res = await call("tracks", "/search?q=Lorde", { token: user.token });
  await assertGolden(
    "tracks_search",
    res.body,
    "GET /tracks/search. A catalog proxy: reachable in every phase and carrying nothing about " +
      "any group (docs/04 §6).",
  );
});

Deno.test("golden: POST /tracks/resolve", async () => {
  const { user } = await openGroup("Golden Resolve");
  const res = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { isrc: "USUM71311296" },
  });
  await assertGolden("tracks_resolve", res.body, "POST /tracks/resolve.");
});

Deno.test("golden: GET /rounds/current, revealed", async () => {
  const { user, group } = await newGroupOwner("Ana", {
    name: "Golden Revealed",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
    cue_cadence: 0,
  });
  const others = [
    await newMember(group.invite_code as string, "Ben"),
    await newMember(group.invite_code as string, "Cal"),
  ];
  for (const [i, member] of [user, ...others].entries()) {
    await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: ["1440818664", "1440765580", "1452874255"][i] },
    });
  }
  await tickRoundsAt(2);

  const view = await call("rounds", "/current", { token: user.token });
  assertEquals((view.body.data as Record<string, unknown>).state, "revealed");
  await assertGolden(
    "round_revealed",
    view.body,
    "GET /rounds/current for a `revealed` round. Wider than `open` by design — docs/02 §3 " +
      "accepts that the name pool discloses who participated, because the game is unsolvable " +
      "otherwise. A card carries a number, a track, and the four user ids it offers as " +
      "candidates (`_shared/shortlist.ts`) — which narrows who owns it, deliberately, and only " +
      "ever after the reveal. What it still never carries is `submission_id`, which does not " +
      "cross the wire before `scored` (ADR-003): the shortlist is a hint that expires with the " +
      "round, a submission id is a durable handle to the answer.",
  );

  const anaCard = (view.body.data as Record<string, unknown>).my_card_no as number;
  const target = ((view.body.data as Record<string, unknown>).cards as { card_no: number }[])
    .find((c) => c.card_no !== anaCard)!;
  const sheet = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: user.token,
    body: { assignments: [{ card_no: target.card_no, guessed_user_id: others[0].id }] },
  });
  assertEquals(sheet.status, 200);
  await assertGolden(
    "guess_sheet",
    sheet.body,
    "PUT /rounds/current/guesses — the caller's own sheet, and two counts that are both about " +
      "the caller. Neither says whether anybody else has guessed, and there is no field here " +
      "that could.",
  );
});

Deno.test("golden: GET /groups/current/standings", async () => {
  // Reachable in every phase, including `open`, which is why it gets a golden rather than an
  // exemption. It is safe there for a reason worth writing down: every number on it comes from
  // `scored` rounds only, so nothing on this payload moves while tonight's round is in flight.
  // A member refreshing it all evening watching for a change learns nothing (docs/14 §3).
  //
  // Captured from a group that has actually played, not from a fresh one. A golden of two
  // empty arrays would pin nothing at all, and the row shapes are the entire point here: the
  // key that must never appear on this payload lives *inside* `readability[]`, so a capture
  // that never produced a readability row could not notice it arriving.
  const { user, group } = await newGroupOwner("Ana", {
    name: "Golden Standings",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const others: TestUser[] = [];
  for (const name of ["Ben", "Cal"]) {
    others.push(await newMember(group.invite_code as string, name));
  }
  for (const [i, member] of [user, ...others].entries()) {
    await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: ["1440818664", "1440765580", "1452874255"][i] },
    });
  }
  await tickRoundsAt(2);

  // One guess, so somebody has an ear and Best Ear is not empty either.
  const revealed = await call("rounds", "/current", { token: user.token });
  const mine = (revealed.body.data as Record<string, unknown>).my_card_no as number;
  const other = ((revealed.body.data as Record<string, unknown>).cards as { card_no: number }[])
    .find((c) => c.card_no !== mine)!;
  await call("rounds", "/current/guesses", {
    method: "PUT",
    token: user.token,
    body: { assignments: [{ card_no: other.card_no, guessed_user_id: others[0].id }] },
  });
  await tickRoundsAt(4);

  const res = await call("groups", "/current/standings", { token: user.token });
  assertEquals(res.status, 200);
  assert((res.body.data.readability as unknown[]).length > 0, "the capture needs a populated list");
  await assertGolden(
    "groups_standings",
    res.body,
    "GET /groups/current/standings. Best Ear is ranked; readability is not and carries no " +
      "`rank` field — docs/02 §4.5 makes that a product rule, and a client that receives a " +
      "rank will render it.",
  );
});

Deno.test("golden: GET /rounds/{id}/results", async () => {
  // Captured against the seed's §4.4 round rather than a freshly built one, because a golden
  // wants a payload with every optional branch populated at once: a caller with both rates, a
  // guessed card and an unguessed one, and a `people` array that is not a single row. Round
  // 2026-08-08 is `scored`, and `scored` is terminal, so the capture is stable.
  //
  // This is the widest payload in the API and the only one that names who dropped what. That
  // is not a leak here — the blind window closed hours ago and docs/02 §2 says the answers are
  // the point of the phase — but it is precisely why the shape gets a checked-in file: the
  // difference between this payload and `round_open` is the entire product, and it must never
  // be one careless edit away from being reachable an hour earlier.
  const ana = await mintToken("a0000000-0000-4000-8000-000000000001");
  const res = await call("rounds", "/c0000000-0000-4000-8000-000000000001/results", { token: ana });
  assertEquals(res.status, 200);
  await assertGolden(
    "round_results",
    res.body,
    "GET /rounds/{round_id}/results for a `scored` round. Owners, per-card correct counts and " +
      "everyone's rates — all of it allowed only because the round is over (docs/04 §4). " +
      "`my_guess` is the caller's own; there is still no route to anyone else's sheet.",
  );
});

Deno.test("golden: GET /groups/current/record", async () => {
  // Reachable during `open`, and safe there for the same reason the standings are: it is a
  // function of `scored` rounds only. Tonight's sealed songs are not in it, and neither is a
  // `voided` night — ever (docs/04 §5). The golden is what makes that a shape somebody has
  // reviewed rather than a sentence in a handler comment: the day this payload grows a
  // `submission_count`, a `submitted` flag, or an entry for a round that has not scored, this
  // file fails before it ships.
  //
  // Captured against the seed group, which is the only fixture with more than one night in it.
  // Its two unfinished rounds are moved on by the scheduler first, so the capture holds a
  // populated `entries[]` with a whole Track in it — a golden of an empty array pins nothing.
  await tickRounds();
  await tickRounds();
  const ana = await mintToken("a0000000-0000-4000-8000-000000000001");
  const res = await call("groups", "/current/record", { token: ana });
  assertEquals(res.status, 200);
  assert(
    (res.body.data.days as { entries: unknown[] }[]).some((day) => day.entries.length > 0),
    "the capture needs a night with songs in it",
  );
  await assertGolden(
    "groups_record",
    res.body,
    "GET /groups/current/record. The archive: `scored` nights only, newest first, each entry " +
      "naming who dropped what. Nothing about tonight is in it, in any phase — an `open` " +
      "round has no row here and a `voided` one never gets one.",
  );
});

Deno.test("golden: GET /groups/current/record/export", async () => {
  // The list the client turns into a playlist with its own credentials (docs/06 §6). Its shape
  // is deliberately not a Track: five fields, all of them identifiers or the words to show
  // beside a failed add. The golden is here to keep it that way — an export payload that grew
  // artwork and preview URLs would be The Record's payload wearing a different name.
  const ana = await mintToken("a0000000-0000-4000-8000-000000000001");
  const res = await call("groups", "/current/record/export?service=spotify", { token: ana });
  assertEquals(res.status, 200);
  assert((res.body.data.tracks as unknown[]).length > 0, "the capture needs a track in it");
  await assertGolden(
    "groups_record_export",
    res.body,
    "GET /groups/current/record/export?service=spotify. Identifiers and a count, and no " +
      "credential in either direction: the server never creates the playlist.",
  );
});

// ─── the errors ──────────────────────────────────────────────────────────────

Deno.test("a WRONG_PHASE body contains the state and nothing else", async () => {
  const { user, group } = await newGroupOwner("Ana", {
    name: "Golden Wrong Phase",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const others: TestUser[] = [];
  for (const name of ["Ben", "Cal"]) {
    others.push(await newMember(group.invite_code as string, name));
  }
  for (const [i, member] of [user, ...others].entries()) {
    await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: ["1440818664", "1440765580", "1452874255"][i] },
    });
  }
  await tickRoundsAt(2);

  const res = await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440765580" },
  });
  assertEquals(res.status, 409);
  // docs/14 §3 closes this channel by construction — `fail()` assembles the body field by
  // field per code, so there is no path by which a count could be attached. This asserts the
  // outcome anyway, because the channel is the one this whole product is about.
  assertEquals(keysOf(res.body.error), ["code", "message", "state"]);
  assertEquals(res.body.error.state, "revealed");
  assertEquals(keysOf(res.body), ["error", "server_now"]);
});

Deno.test("every error envelope is code, message, and at most state", async () => {
  const stranger = await newUser();
  for (
    const [label, res] of [
      ["anonymous", await call("rounds", "/current")],
      ["no profile", await call("rounds", "/current", { token: stranger.token })],
      ["unknown route", await call("rounds", "/nope", { token: stranger.token })],
    ] as const
  ) {
    assertEquals(keysOf(res.body), ["error", "server_now"], label);
    const keys = keysOf(res.body.error);
    assert(
      keys.every((k) => ["code", "message", "state", "details"].includes(k)),
      `${label}: error carried ${keys.join(", ")}`,
    );
  }
});

// ─── the backstop ────────────────────────────────────────────────────────────

Deno.test("every route reachable during `open` has a golden file", async () => {
  // Parsed out of the handlers themselves rather than listed here, so the check cannot go
  // stale: a route added to `serveFunction` with no golden entry fails this test on the next
  // run, before anyone has to remember.
  const functionsDir = new URL("../../functions/", import.meta.url);
  const routes: string[] = [];
  for await (const entry of Deno.readDir(functionsDir)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;
    let source: string;
    try {
      source = await Deno.readTextFile(new URL(`${entry.name}/index.ts`, functionsDir));
    } catch {
      continue; // a group with no handler yet
    }
    for (const match of source.matchAll(/^\s*"((?:GET|PUT|POST|PATCH|DELETE) [^"]*)":/gm)) {
      routes.push(`${entry.name} ${match[1]}`);
    }
  }
  assert(routes.length > 0, "no routes found — the parser has drifted from the handlers");

  // Every route that answers with a body during `open`, and the golden that covers it. A
  // route is listed as `null` only when it has no body to leak: a 204, or a route no client
  // can reach while a round is open.
  const COVERED: Record<string, string | null> = {
    "me GET /": "me",
    "me PUT /": "me",
    "me DELETE /": null, // 204
    "groups POST /": "groups_current",
    "groups POST /join": "groups_current",
    "groups GET /": "groups_circles",
    "groups GET /people-you-played-with": "groups_people_you_played_with",
    "groups GET /current": "groups_current",
    "groups PATCH /current": "groups_current",
    "groups GET /current/standings": "groups_standings",
    // The archive and its export. Both are reachable during `open` and both are a function of
    // `scored` rounds alone, which is the whole reason they are safe there — and the reason
    // their shapes are checked in: an archive that could see one phase earlier than it does
    // would publish tonight's songs (docs/04 §5, CLAUDE.md §2.1).
    "groups GET /current/record": "groups_record",
    "groups GET /current/record/export": "groups_record_export",
    "groups POST /current/leave": null, // 204
    // ADR-011 (E18-01): every `current`-shaped route above also exists named by group id, one
    // shared handler apiece. Same DTO, same golden — the shape a member of *a* circle sees
    // does not change depending on how the circle was addressed.
    "groups GET /:group_id": "groups_current",
    "groups PATCH /:group_id": "groups_current",
    "groups GET /:group_id/standings": "groups_standings",
    // E24-02. This is safe during `open` only because every field is filtered to scored rounds;
    // its dedicated capture runs after the target has sealed tonight, proving the shape still
    // cannot name or carry that submission.
    "groups GET /:group_id/members/:user_id/profile": "groups_member_profile",
    "groups GET /:group_id/insights": "groups_insights",
    "groups GET /:group_id/record": "groups_record",
    "groups GET /:group_id/record/export": "groups_record_export",
    "groups POST /:group_id/leave": null, // 204
    // E21-02. A role update returns the same reviewed roster DTO as the group settings route;
    // removal is a bodiless 204 and therefore cannot widen an open-phase response.
    // E43-02. Writing or clearing the next round's cue answers with the same reviewed group
    // DTO the settings routes above already return — the one new key on it, `next_cue`, is
    // admin-only and describes a round that has not opened, so it is a fact about the coming
    // brief and never about anyone's participation in tonight's (docs/18-CUES.md §11.6).
    "groups PUT /current/cue": "groups_current",
    "groups DELETE /current/cue": "groups_current",
    "groups PUT /:group_id/cue": "groups_current",
    "groups DELETE /:group_id/cue": "groups_current",
    "groups PATCH /:group_id/members/:user_id": "groups_current",
    "groups DELETE /:group_id/members/:user_id": null,
    // E45-01. A bodiless 204, like removal above, so there is no payload to widen. It is also
    // the only write on this function that reads no round state whatsoever — it never loads a
    // round, a submission or a guess — so the response cannot vary with anybody's participation
    // and is byte-identical whether the target has sealed tonight or not.
    "groups POST /:group_id/members/:user_id/report": null,
    // E20-01. Pending invitations, distinct from membership — see the two captures above.
    "groups POST /current/invitations": "invitation",
    "groups POST /:group_id/invitations": "invitation",
    "groups GET /invitations": "invitations_mine",
    // `E38-03` fix. The circle's own *sent* invitations, so a member can finish sending a link
    // for somebody already asked. Two facts per row — the invitee and the invitation id — and
    // nothing about tonight: it reads `invitations` alone, never a round, submission or guess.
    "groups GET /current/invitations": "invitations_sent",
    "groups GET /:group_id/invitations": "invitations_sent",
    // Same DTO shape `POST /groups/join` already answers with — accepting is a second door
    // into the same "you're in" response, not a new shape.
    "groups POST /invitations/:invitation_id/accept": "groups_current",
    "groups POST /invitations/:invitation_id/decline": null, // 204
    "rounds GET /current": "round_open",
    "rounds PUT /current/submission": "submission",
    // Reachable only once the round is `revealed`, which is to say only once the blind window
    // is over — but it is captured all the same, because "this route cannot be called during
    // `open`" is a claim that needs a golden file behind it as much as any other.
    "rounds PUT /current/guesses": "guess_sheet",
    // Refuses anything but `scored` (`requirePhase`), so it is not reachable during `open` at
    // all — and captured anyway, on the same principle as the guess sheet above: "this cannot
    // be called during `open`" is a claim that needs a golden file behind it.
    "rounds GET /:round_id/results": "round_results",
    // ADR-011 (E18-01): the `current`-shaped round routes, named by group id.
    "rounds GET /:group_id/current": "round_open",
    "rounds PUT /:group_id/current/submission": "submission",
    "rounds PUT /:group_id/current/guesses": "guess_sheet",
    // The scheduler's, not a client's: `requireServiceRole` and nothing else, so there is no
    // phase in which a device can reach it (tasks/E07-05). Its body is four integers about the
    // worker's own pass — no group, no round, no member — and `examined` is capped at the batch
    // size, so it cannot become a count of anything but its own work.
    "links-worker POST /": null,
    // Also scheduler-only. Its five counters describe the bounded batch it just handled;
    // none is keyed by a group, round, member, or participation state, and no device token
    // can pass requireServiceRole to observe them.
    "push-worker POST /": null,
    // 204, always, whether the token was new, moved between users, or unchanged. There is no
    // read side and no body to shape, so a caller learns nothing from registering — including
    // whether the row already existed (tasks/E06-03).
    "devices POST /": null,
    // 204, same as registration: whether the token existed, belonged to this user, or matched
    // nothing at all, the caller learns nothing about the row it just asked to be gone
    // (tasks/E14, "add group and account settings").
    "devices DELETE /": null,
    "tracks GET /search": "tracks_search",
    "tracks POST /resolve": "tracks_resolve",
  };

  const uncovered = routes.filter((r) => !(r in COVERED));
  assertEquals(
    uncovered,
    [],
    `These routes have no golden file. A response nobody has reviewed is how a leak ships ` +
      `(docs/14 §3). Add a capture in this file and an entry to COVERED.`,
  );

  // And the reverse: a golden named here must exist on disk.
  for (const golden of new Set(Object.values(COVERED))) {
    if (golden === null) continue;
    await Deno.stat(new URL(`${golden}.json`, GOLDEN_DIR));
  }
});
