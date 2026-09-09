// ios/Fixtures/server.ts — E00-05.
//
// A canned server for every endpoint in docs/04, so the whole iOS lane can be built and
// tested before the backend exists. The UI test scheme launches it and points the app at it
// with `-apiBaseURL http://127.0.0.1:8787` (E08-01).
//
//   PHASE=open deno run --allow-net --allow-read --allow-env server.ts
//
// | env         | default | what it does                                                  |
// |-------------|---------|---------------------------------------------------------------|
// | PHASE       | open    | which /rounds/current payload to serve (see PHASES below)      |
// | PORT        | 8787    |                                                               |
// | LATENCY_MS  | 0       | delay on every response — exercise the 400ms search budget     |
// | ANCHOR      | now     | `now` re-times the round around server_now; `fixed` serves the |
// |             |         | literal timestamps in the payload files                        |
//
// A fixture that drifts from docs/04 is worse than no fixture. The payload files in
// payloads/ are the contract, verbatim; this file only wraps them in the envelope, stamps
// server_now, and routes.

const PORT = Number(Deno.env.get("PORT") ?? 8787);
const LATENCY_MS = Number(Deno.env.get("LATENCY_MS") ?? 0);
const ANCHOR = Deno.env.get("ANCHOR") ?? "now";

const PHASES = {
  open: "round_open",
  open_nosub: "round_open_nosub",
  // The dark hours: an `open` round that has not opened yet, carrying the *previous* night's
  // cue alongside its own (`docs/18-CUES.md` §7). The one phase where two cues are on the wire
  // at once and only one of them may reach the screen.
  open_darkhours: "round_darkhours",
  revealed: "round_revealed",
  revealed_nosub: "round_revealed_nosub",
  revealed_joinedlate: "round_revealed_joinedlate",
  scored: "round_scored",
  voided: "round_voided",
} as const;
type Phase = keyof typeof PHASES;

const PHASE = (Deno.env.get("PHASE") ?? "open") as Phase;
if (!(PHASE in PHASES)) {
  console.error(`PHASE must be one of: ${Object.keys(PHASES).join(" | ")}`);
  Deno.exit(2);
}
const FIXTURE_CONTROL = Deno.env.get("FIXTURE_CONTROL") === "1";
let activePhase: Phase = PHASE;

// How far each phase sits from "now", so countdowns on screen are always live and sane.
// [opens_at, reveals_at, scores_at] as minutes relative to server_now.
const OFFSETS: Record<Phase, [number, number, number]> = {
  open: [-330, 270, 390],
  open_nosub: [-330, 270, 390],
  // Opens in four and a half hours: 05:30 in a circle that opens at 10:00.
  open_darkhours: [270, 870, 990],
  voided: [-600, 0, 120],
  revealed: [-615, -15, 105],
  revealed_nosub: [-615, -15, 105],
  revealed_joinedlate: [-615, -15, 105],
  scored: [-720, -120, 0],
};

const here = new URL(".", import.meta.url);
const cache = new Map<string, unknown>();
async function payload(name: string): Promise<unknown> {
  if (!cache.has(name)) {
    cache.set(name, JSON.parse(await Deno.readTextFile(new URL(`payloads/${name}.json`, here))));
  }
  return structuredClone(cache.get(name));
}

const rfc3339 = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, "Z");

function reTime(round: Record<string, unknown>, now: Date): Record<string, unknown> {
  return reTimeWith(round, OFFSETS[activePhase], now);
}

function reTimeWith(
  round: Record<string, unknown>,
  offsets: [number, number, number],
  now: Date,
): Record<string, unknown> {
  if (ANCHOR !== "now") return round;
  const [o, r, s] = offsets;
  const at = (m: number) => rfc3339(new Date(now.getTime() + m * 60_000));
  return { ...round, opens_at: at(o), reveals_at: at(r), scores_at: at(s) };
}

// ─── circles — E19-01 ────────────────────────────────────────────────────────
//
// `PRIMARY_GROUP_ID` is `payloads/group_current.json`'s own id: every `current`-shaped route
// above already resolves to this circle, so keying the `:group_id` siblings off it is what
// makes "nothing changes" true for a test written before this slice. `SECONDARY_GROUP_ID` is
// `GET /groups`'s static second row (`switcherStateFor`) — a real circle a `:group_id` route
// can be asked for, distinct from the scripted one `PHASE` moves.
const PRIMARY_GROUP_ID = "b0000000-0000-4000-8000-000000000001";
const SECONDARY_GROUP_ID = "b0000000-0000-4000-8000-000000000099";

// Circles created during this run, by `POST /groups` (`E38-03`).
//
// `POST /groups` used to answer with `group_current.json` — the nine-member circle the fixture
// has always shipped — which made the creation flow untestable in the one way that matters:
// a circle you have just made has exactly **one** member, you, and every screen that follows
// (the invite shortlist, the roster, the standings) is about that fact. Returning somebody
// else's nine-person circle hid it. These are held in memory only: nothing is written to
// `payloads/`, and a restart forgets them, so no existing test's expectations move.
const createdGroups = new Map<string, Record<string, unknown>>();

/** Settings patched onto the **primary** circle, which comes from a payload file rather than
 *  from `createdGroups` and so had nowhere to remember a change. Held for the life of the
 *  process, like everything else here. It is what lets a driver — a UI test, or somebody
 *  tapping through the app — change the reveal hour, leave the settings screen and come back to
 *  a circle that still knows: `reveal_effective_from` is *about* outliving the reply it arrived
 *  in (`docs/04` §3), and a fixture that forgot on the next GET could not show that. */
const patchedPrimary: Record<string, unknown> = {};

/// The name `PUT /me` was last given, so `GET /me` answers with it (`E38`). `null` until
/// somebody has actually set one, which keeps `payloads/me.json` the source of truth for every
/// test that never touches the name.
let savedDisplayName: string | null = null;

async function groupPayloadFor(groupId: string): Promise<Record<string, unknown> | null> {
  const created = createdGroups.get(groupId);
  if (created) return created;
  if (groupId === PRIMARY_GROUP_ID) return await primaryGroup();
  if (groupId === SECONDARY_GROUP_ID) {
    const primary = await payload("group_current") as Record<string, unknown>;
    return {
      id: SECONDARY_GROUP_ID,
      name: "Late Night Radio",
      timezone: "America/New_York",
      reveal_hour: 21,
      invite_code: "LN8RADIO",
      is_admin: false,
      members: primary.members,
    };
  }
  return null;
}

/** The secondary circle's round is always the shape `switcherStateFor` claims — `sealed`,
 *  never moving with `PHASE` — so a `:group_id` route asked for it stays honest about what
 *  `GET /groups` already said. */
async function roundPayloadFor(groupId: string): Promise<Record<string, unknown> | null> {
  // A circle created a moment ago plays tonight like any other; it gets the `open` round so
  // "Go to the group" lands on a real screen rather than a NOT_FOUND.
  if (createdGroups.has(groupId)) {
    const round = await payload("round_open") as Record<string, unknown>;
    return reTimeWith(round, OFFSETS.open, new Date());
  }
  if (groupId === PRIMARY_GROUP_ID) {
    const round = await payload(PHASES[activePhase]) as Record<string, unknown>;
    return reTime(round, new Date());
  }
  if (groupId === SECONDARY_GROUP_ID) {
    const round = await payload("round_open") as Record<string, unknown>;
    return reTimeWith(round, OFFSETS.open, new Date());
  }
  return null;
}

// ─── invitations — E20-01 ─────────────────────────────────────────────────────
// Pending, distinct from membership, exactly as the server's `invitations` table is: nothing
// here ever writes to `group_current.json`'s `members`, so a UI test that accepts or declines
// still sees the same roster it always did.

interface FixtureInvitation {
  id: string;
  group: { id: string; name: string };
  /// Who it is for. Never in the recipient-facing `InvitationDTO` — they know who they are —
  /// but it is the whole point of the circle's own *sent* list, which is keyed by it.
  invited_user: string;
  invited_by: { user_id: string; display_name: string };
  created_at: string;
  expires_at: string;
}

/** The circle's own list, shaped as `SentInvitationDTO` — the invitee and the id, and neither
 *  the circle (the caller named it) nor the inviter (nobody is choosing between them). */
function sentInvitationsFor(groupId: string) {
  return fixtureInvitations
    .filter((i) => i.group.id === groupId)
    .map((i) => ({ id: i.id, invited_user: i.invited_user, expires_at: i.expires_at }));
}

const fixtureInvitations: FixtureInvitation[] = [];
let invitationSeq = 0;

async function createInvitation(groupId: string, body: Record<string, unknown>): Promise<Response> {
  const group = await groupPayloadFor(groupId);
  if (!group) return fail(404, "NOT_FOUND", "That's not available right now.");
  const userId = typeof body.user_id === "string" ? body.user_id.trim() : "";
  if (!userId) return fail(400, "INVALID_INPUT", "Check that and try again.", { field: "user_id" });

  const me = (await payload("me")) as Record<string, unknown>;
  const now = new Date();
  const expires = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
  invitationSeq += 1;
  const invitation: FixtureInvitation = {
    id: `c0000000-0000-4000-8000-${String(invitationSeq).padStart(12, "0")}`,
    group: { id: group.id as string, name: group.name as string },
    invited_user: userId,
    invited_by: { user_id: me.user_id as string, display_name: me.display_name as string },
    created_at: rfc3339(now),
    expires_at: rfc3339(expires),
  };
  fixtureInvitations.push(invitation);
  return ok(invitation);
}

// docs/04 §1 — the resource, bare, plus a server clock. On every response.
function ok(data: unknown, status = 200): Response {
  return new Response(
    JSON.stringify({ server_now: rfc3339(new Date()), data }, null, 2),
    { status, headers: { "content-type": "application/json; charset=utf-8" } },
  );
}
function fail(status: number, code: string, message: string, details?: unknown): Response {
  return new Response(
    JSON.stringify({ server_now: rfc3339(new Date()), error: { code, message, ...(details ? { details } : {}) } }, null, 2),
    { status, headers: { "content-type": "application/json; charset=utf-8" } },
  );
}
const noContent = () => new Response(null, { status: 204 });

// ─── Supabase Auth (docs/14 §5) ──────────────────────────────────────────────
//
// GoTrue is a sibling service, not one of our functions: it lives under /auth/v1, it does not
// use the docs/04 §1 envelope, and it carries no server_now. So it gets its own two shapes.
// The refresh token rotates on every issue, which is what the client's "one 401 buys one
// refresh" path has to survive — a fixture that returned a fixed token would make a
// double-spend look like a success.

const FIXTURE_ACCESS_TOKEN = "fixture-access-token";
let refreshCounter = 0;
const issuedRefreshTokens = new Set<string>(["fixture-refresh-token-0"]);

function issueSession(): Response {
  const refresh = `fixture-refresh-token-${++refreshCounter}`;
  issuedRefreshTokens.add(refresh);
  return new Response(
    JSON.stringify({
      access_token: `${FIXTURE_ACCESS_TOKEN}-${refreshCounter}`,
      token_type: "bearer",
      expires_in: 3600,
      refresh_token: refresh,
      user: { id: "u_ana", aud: "authenticated", role: "authenticated" },
    }, null, 2),
    { status: 200, headers: { "content-type": "application/json; charset=utf-8" } },
  );
}

function authFail(status: number, code: string, message: string): Response {
  return new Response(
    JSON.stringify({ code: status, error_code: code, msg: message }, null, 2),
    { status, headers: { "content-type": "application/json; charset=utf-8" } },
  );
}

async function authRoute(req: Request, url: URL, p: string): Promise<Response | null> {
  if (req.method !== "POST") return null;

  if (p === "/auth/v1/token") {
    const grant = url.searchParams.get("grant_type");
    const body = await req.json().catch(() => ({}));

    if (grant === "id_token") {
      // The nonce is the whole point of the exchange (see Core/Auth/AppleSignIn.swift): a
      // request without one is one the real GoTrue would refuse, so this one does too.
      if (body.provider !== "apple" || !body.id_token || !body.nonce) {
        return authFail(400, "validation_failed", "Missing provider, id_token or nonce.");
      }
      return issueSession();
    }
    if (grant === "refresh_token") {
      // Rotation, enforced: spending a token twice fails, which is how a client that
      // refreshes twice on one 401 shows up as a broken test rather than as a working app.
      if (!body.refresh_token || !issuedRefreshTokens.delete(body.refresh_token)) {
        return authFail(400, "invalid_grant", "Invalid Refresh Token.");
      }
      return issueSession();
    }
    return authFail(400, "validation_failed", `Unsupported grant_type: ${grant}`);
  }

  if (p === "/auth/v1/logout") {
    if (!req.headers.get("authorization")) return authFail(401, "no_authorization", "No bearer.");
    return noContent();
  }

  return null;
}

// ─── routes ──────────────────────────────────────────────────────────────────
async function route(req: Request, url: URL): Promise<Response> {
  // /auth/v1 is matched before the functions prefix is stripped — it is a sibling of
  // /functions/v1, not a route inside it.
  const auth = await authRoute(req, url, url.pathname.replace(/\/$/, ""));
  if (auth) return auth;

  const p = url.pathname.replace(/^\/functions\/v1/, "").replace(/\/$/, "") || "/";
  const m = req.method;

  // E14's UI loop advances the scripted server instead of waiting four real hours. This route
  // exists only when explicitly enabled by the fixture process and is not an app endpoint.
  if (m === "PUT" && p === "/__fixture/phase" && FIXTURE_CONTROL) {
    const body = await req.json().catch(() => ({}));
    const requested = String(body.phase ?? "") as Phase;
    if (!(requested in PHASES)) {
      return fail(400, "INVALID_INPUT", `phase must be one of ${Object.keys(PHASES).join(", ")}`);
    }
    activePhase = requested;
    return ok({ phase: activePhase });
  }

  // The catalog proxy is group-blind and available in every phase (docs/04 §6).
  if (m === "GET" && p === "/tracks/search") {
    const q = (url.searchParams.get("q") ?? "").trim();
    if (q.length < 2) return ok({ results: [] });
    const all = (await payload("tracks_search")) as { results: { title: string; artist: string }[] };
    const needle = q.toLowerCase();
    const hits = all.results.filter(
      (t) => t.title.toLowerCase().includes(needle) || t.artist.toLowerCase().includes(needle),
    );
    // An unmatched query still returns the full set, so a UI test can type anything and
    // still get eight rows to drive the loop with.
    return ok({ results: hits.length ? hits : all.results });
  }
  if (m === "POST" && p === "/tracks/resolve") {
    const body = await req.json().catch(() => ({}));
    if (!body.spotify_url && !body.apple_music_url && !body.isrc && !body.apple_music_id) {
      return fail(400, "INVALID_INPUT", "That's not a song link.");
    }
    return ok(await payload("track_resolved"));
  }

  if (m === "GET" && p === "/me") {
    const me = await payload("me") as Record<string, unknown>;
    return ok(savedDisplayName === null ? me : { ...me, display_name: savedDisplayName });
  }
  if (m === "PUT" && p === "/me") {
    const body = await req.json().catch(() => ({}));
    const name = String(body.display_name ?? "").trim();
    if (!name) return fail(400, "INVALID_INPUT", "Enter a name to continue.", { field: "display_name" });
    if (name.length > 24) return fail(400, "INVALID_INPUT", "Keep it to 24 characters.", { field: "display_name" });
    // Remembered, so the `GET /me` that follows agrees with it. `OnboardingStore.saveName()`
    // sends this and then re-reads the session — *"the server decides what comes next"* — and a
    // fixture that echoed the new name here while `GET /me` kept answering `Ana` made
    // `namingCompletesAgainstTheFixtureServer` red for exactly as long as it has existed. In
    // memory only: a restart forgets it, the same as the created circles above.
    savedDisplayName = name;
    return ok({ ...(await payload("me") as object), display_name: name });
  }
  if (m === "DELETE" && p === "/me") return noContent();
  if (m === "POST" && p === "/devices") return noContent();

  if (m === "GET" && p === "/groups") {
    const group = await payload("group_current") as Record<string, unknown>;
    const primary = {
      id: group.id as string,
      name: group.name as string,
      ...switcherStateFor(activePhase),
    };
    // A second, static circle so `E19`'s switcher has more than one row to build against
    // without needing a second phase control. It never moves with `PHASE`/`FIXTURE_CONTROL`,
    // and `:group_id` routes answer for it too (`roundPayloadFor`, `groupPayloadFor`).
    const secondary = {
      id: SECONDARY_GROUP_ID,
      name: "Late Night Radio",
      my_state: "sealed",
      needs_action: false,
    };
    // Circles made during this run sit after the two static ones, in creation order, so the
    // switcher a `POST /groups` just changed actually shows what changed (`E38-03`).
    const created = [...createdGroups.values()].map((group) => ({
      id: group.id as string,
      name: group.name as string,
      my_state: "drop",
      needs_action: true,
    }));
    return ok({ circles: [primary, secondary, ...created] });
  }
  if (m === "GET" && p === "/groups/current") return ok(await primaryGroup());
  if (m === "GET" && p === "/groups/people-you-played-with") {
    const group = await payload("group_current") as Record<string, unknown>;
    const members = (group.members as Array<Record<string, unknown>>) ?? [];
    const me = (await payload("me")) as Record<string, unknown>;
    return ok({
      people: members
        .filter((member) => member.user_id !== me.user_id)
        .map((member) => ({ user_id: member.user_id, display_name: member.display_name })),
    });
  }
  if (m === "POST" && p === "/groups") {
    const body = await req.json().catch(() => ({}));
    const me = (await payload("me")) as Record<string, unknown>;
    // A block of its own, well clear of `PRIMARY_GROUP_ID`/`SECONDARY_GROUP_ID` — the first
    // draft of this generated `…0001` and shadowed the primary circle in `groupPayloadFor`.
    const id = `b0000000-0000-4000-8000-${String(500 + createdGroups.size).padStart(12, "0")}`;
    const group = {
      id,
      name: String(body.name ?? "New group"),
      timezone: String(body.timezone ?? "America/New_York"),
      reveal_hour: Number(body.reveal_hour ?? 20),
      // `docs/03` §2's alphabet: no `I`, `L`, `O`, `0` or `1`.
      invite_code: `N${createdGroups.size + 2}WCRD`.slice(0, 6),
      is_admin: true,
      // One member: the creator. That is the whole point of this route answering for itself.
      members: [{ user_id: me.user_id, display_name: me.display_name }],
      cue_cadence: 2,
    };
    createdGroups.set(id, group);
    return ok(group);
  }
  if (m === "POST" && p === "/groups/join") {
    const body = await req.json().catch(() => ({}));
    const code = String(body.invite_code ?? "").trim().toUpperCase();
    if (code !== "K7MQ2X") {
      return fail(404, "NOT_FOUND", "No group with that code. Check it and try again.");
    }
    return ok(await payload("group_current"));
  }
  if (m === "PATCH" && p === "/groups/current") {
    const body = await req.json().catch(() => ({}));
    return ok(await patchPrimary(body));
  }
  if (m === "POST" && p === "/groups/current/leave") return noContent();
  if (m === "GET" && p === "/groups/current/standings") return ok(await payload("standings"));
  if (m === "GET" && p === "/groups/current/record") return ok(await payload("record"));
  if (m === "GET" && p === "/groups/current/record/export") {
    const svc = url.searchParams.get("service") === "apple" ? "apple" : "spotify";
    return ok(await payload(`record_export_${svc}`));
  }

  // ─── invitations — E20-01 ────────────────────────────────────────────────────
  // In-memory, not scripted by `PHASE`: a pending invitation is new state a fixture-backed
  // test creates and resolves itself, the same way `refreshCounter` tracks its own thing.
  if (m === "POST" && p === "/groups/current/invitations") {
    const body = await req.json().catch(() => ({}));
    return createInvitation(PRIMARY_GROUP_ID, body);
  }
  if (m === "GET" && p === "/groups/invitations") {
    return ok({ invitations: fixtureInvitations });
  }
  // The circle's *sent* invitations, two segments — never reachable from the one-segment route
  // just above, which is the caller's *received* ones.
  if (m === "GET" && p === "/groups/current/invitations") {
    return ok({ invitations: sentInvitationsFor(PRIMARY_GROUP_ID) });
  }
  const invitationAccept = p.match(/^\/groups\/invitations\/([^/]+)\/accept$/);
  if (m === "POST" && invitationAccept) {
    const idx = fixtureInvitations.findIndex((i) => i.id === invitationAccept[1]);
    if (idx === -1) return fail(404, "NOT_FOUND", "That's not available right now.");
    const [invitation] = fixtureInvitations.splice(idx, 1);
    const group = (await groupPayloadFor(invitation.group.id)) ?? (await payload("group_current"));
    return ok(group);
  }
  const invitationDecline = p.match(/^\/groups\/invitations\/([^/]+)\/decline$/);
  if (m === "POST" && invitationDecline) {
    const idx = fixtureInvitations.findIndex((i) => i.id === invitationDecline[1]);
    if (idx === -1) return fail(404, "NOT_FOUND", "That's not available right now.");
    fixtureInvitations.splice(idx, 1);
    return noContent();
  }

  if (m === "GET" && p === "/rounds/current") {
    const round = await payload(PHASES[activePhase]) as Record<string, unknown>;
    return ok(reTime(round, new Date()));
  }
  if (m === "PUT" && p === "/rounds/current/submission") {
    if (activePhase !== "open" && activePhase !== "open_nosub") {
      // A phase error returns the state and nothing else (docs/04 §1).
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    const body = await req.json().catch(() => ({}));
    if (!body.apple_music_id && !body.spotify_url && !body.isrc) {
      return fail(400, "INVALID_INPUT", "That's not a song link.");
    }
    const t = await payload("track_resolved");
    return ok({ track: t, sealed_at: rfc3339(new Date()) });
  }
  if (m === "PUT" && p === "/rounds/current/guesses") {
    if (!activePhase.startsWith("revealed")) {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    if (activePhase === "revealed_nosub") {
      return fail(403, "NOT_A_SUBMITTER", "You didn't drop a song tonight.");
    }
    if (activePhase === "revealed_joinedlate") {
      return fail(403, "JOINED_LATE", "You joined after the reveal. You're in from tomorrow.");
    }
    const body = await req.json().catch(() => ({}));
    const assignments = (body.assignments ?? []).filter(
      (a: { guessed_user_id: string | null }) => a.guessed_user_id !== null,
    );
    return ok({ assignments, assigned_count: assignments.length, assignable_count: 7 });
  }

  const results = p.match(/^\/rounds\/([^/]+)\/results$/);
  if (m === "GET" && results) {
    // **The phase guard is about *tonight's* round, not about this route.** A past night's
    // answers are readable whatever the live round is doing — that is the whole premise of The
    // Record's date headers and of the dark hours' "See last night's results". Guarding every id
    // by `activePhase` made both of those 409 in the fixtures while working against the real
    // server, which is a fixture bug that only showed up once something linked to a past night
    // from a screen that was not itself scored.
    const current = (await payload(PHASES[activePhase])) as { round_id: string };
    if (results[1] === current.round_id && activePhase !== "scored") {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    return ok(await payload("results"));
  }

  // ─── `:group_id` — E19-01 ──────────────────────────────────────────────────
  //
  // The client no longer calls the `current`-shaped routes above; they are left in place
  // because nothing forces a fixture to shed compatibility the day the app does. Every route a
  // named circle needs has a sibling here, keyed by `PRIMARY_GROUP_ID` (the same circle the
  // `current` routes always resolved to — so a test written before this slice still gets the
  // same answers) or `SECONDARY_GROUP_ID` (`GET /groups`'s static second row). An id that is
  // neither is a stranger to both, and gets the same `NOT_FOUND` a real non-member would.
  const groupOnly = p.match(/^\/groups\/([^/]+)$/);
  if ((m === "GET" || m === "PATCH") && groupOnly && groupOnly[1] !== "current") {
    const group = await groupPayloadFor(groupOnly[1]);
    if (!group) return fail(404, "NOT_FOUND", "That's not available right now.");
    if (m === "GET") return ok(group);
    const body = await req.json().catch(() => ({}));
    if (groupOnly[1] === PRIMARY_GROUP_ID) return ok(await patchPrimary(body));
    return ok({ ...group, ...body, reveal_effective_from: revealEffectiveFrom(group, body) });
  }
  const groupLeave = p.match(/^\/groups\/([^/]+)\/leave$/);
  if (m === "POST" && groupLeave && groupLeave[1] !== "current") {
    return (await groupPayloadFor(groupLeave[1])) ? noContent() : fail(404, "NOT_FOUND", "That's not available right now.");
  }
  const groupStandings = p.match(/^\/groups\/([^/]+)\/standings$/);
  if (m === "GET" && groupStandings && groupStandings[1] !== "current") {
    if (!(await groupPayloadFor(groupStandings[1]))) return fail(404, "NOT_FOUND", "That's not available right now.");
    return ok(await payload("standings"));
  }
  const memberProfile = p.match(/^\/groups\/([^/]+)\/members\/([^/]+)\/profile$/);
  if (m === "GET" && memberProfile) {
    const group = await groupPayloadFor(memberProfile[1]) as Record<string, unknown> | null;
    const member = (group?.members as Array<Record<string, unknown>> | undefined)
      ?.find((entry) => entry.user_id === memberProfile[2]);
    if (!member) return fail(404, "NOT_FOUND", "That's not available right now.");
    return ok({
      member,
      ear: { value: 0.71, samples: 14 },
      readability: { value: 0.43, samples: 14 },
      drop_count: 14,
      recent_tracks: [],
      you_read_them: { correct: 8, possible: 14 },
      they_read_you: { correct: 5, possible: 14 },
    });
  }
  const groupInsights = p.match(/^\/groups\/([^/]+)\/insights$/);
  if (m === "GET" && groupInsights && groupInsights[1] !== "current") {
    if (!(await groupPayloadFor(groupInsights[1]))) return fail(404, "NOT_FOUND", "That's not available right now.");
    return ok(await payload("insights"));
  }
  const groupRecord = p.match(/^\/groups\/([^/]+)\/record$/);
  if (m === "GET" && groupRecord && groupRecord[1] !== "current") {
    if (!(await groupPayloadFor(groupRecord[1]))) return fail(404, "NOT_FOUND", "That's not available right now.");
    return ok(await payload("record"));
  }
  const groupExport = p.match(/^\/groups\/([^/]+)\/record\/export$/);
  if (m === "GET" && groupExport && groupExport[1] !== "current") {
    if (!(await groupPayloadFor(groupExport[1]))) return fail(404, "NOT_FOUND", "That's not available right now.");
    const svc = url.searchParams.get("service") === "apple" ? "apple" : "spotify";
    return ok(await payload(`record_export_${svc}`));
  }
  const groupInvite = p.match(/^\/groups\/([^/]+)\/invitations$/);
  if (m === "POST" && groupInvite && groupInvite[1] !== "current") {
    const body = await req.json().catch(() => ({}));
    return createInvitation(groupInvite[1], body);
  }
  if (m === "GET" && groupInvite && groupInvite[1] !== "current") {
    if (!(await groupPayloadFor(groupInvite[1]))) {
      return fail(404, "NOT_FOUND", "That's not available right now.");
    }
    return ok({ invitations: sentInvitationsFor(groupInvite[1]) });
  }

  const roundCurrent = p.match(/^\/rounds\/([^/]+)\/current$/);
  if (m === "GET" && roundCurrent && roundCurrent[1] !== "current") {
    const round = await roundPayloadFor(roundCurrent[1]);
    if (!round) return fail(404, "NOT_FOUND", "That's not available right now.");
    return ok(round);
  }
  const roundSubmission = p.match(/^\/rounds\/([^/]+)\/current\/submission$/);
  if (m === "PUT" && roundSubmission && roundSubmission[1] !== "current") {
    const groupId = roundSubmission[1];
    if (!(await groupPayloadFor(groupId))) return fail(404, "NOT_FOUND", "That's not available right now.");
    // The secondary circle's row is always `sealed` (`switcherStateFor`) — it never has an
    // open submission to accept, and there is no scripted test that needs it to.
    if (groupId !== PRIMARY_GROUP_ID || (activePhase !== "open" && activePhase !== "open_nosub")) {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    const body = await req.json().catch(() => ({}));
    if (!body.apple_music_id && !body.spotify_url && !body.isrc) {
      return fail(400, "INVALID_INPUT", "That's not a song link.");
    }
    const t = await payload("track_resolved");
    return ok({ track: t, sealed_at: rfc3339(new Date()) });
  }
  const roundGuesses = p.match(/^\/rounds\/([^/]+)\/current\/guesses$/);
  if (m === "PUT" && roundGuesses && roundGuesses[1] !== "current") {
    const groupId = roundGuesses[1];
    if (!(await groupPayloadFor(groupId))) return fail(404, "NOT_FOUND", "That's not available right now.");
    if (groupId !== PRIMARY_GROUP_ID || !activePhase.startsWith("revealed")) {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    if (activePhase === "revealed_nosub") {
      return fail(403, "NOT_A_SUBMITTER", "You didn't drop a song tonight.");
    }
    if (activePhase === "revealed_joinedlate") {
      return fail(403, "JOINED_LATE", "You joined after the reveal. You're in from tomorrow.");
    }
    const body = await req.json().catch(() => ({}));
    const assignments = (body.assignments ?? []).filter(
      (a: { guessed_user_id: string | null }) => a.guessed_user_id !== null,
    );
    return ok({ assignments, assigned_count: assignments.length, assignable_count: 7 });
  }

  if (m === "GET" && p === "/__fixture") {
    return ok({ phase: activePhase, latency_ms: LATENCY_MS, anchor: ANCHOR,
                control: FIXTURE_CONTROL, phases: Object.keys(PHASES) });
  }

  return fail(404, "NOT_FOUND", "That's not available right now.");
}

function currentState(): string {
  if (activePhase.startsWith("open")) return "open";
  if (activePhase.startsWith("revealed")) return "revealed";
  return activePhase;
}

/** `GET /groups`'s per-circle state (`E18-02`), mapped off the same `PHASE` the round fixtures
 *  already key off — so switching phase through `__fixture/phase` moves this row too, the way
 *  a real reveal or score would. */
/** The fixture's stand-in for the server's round-table comparison.
 *
 *  A change re-times every round that has not yet opened (docs/02 §1), so the only round that
 *  can still be on the old hour is the one that is *open* — and the fixture's primary circle
 *  always has one. So a moved hour reports the next day, and an unmoved one reports nothing.
 *  The date is fixed rather than derived: the goldens assert it, and the payload file's round
 *  is dated 2026-08-11 whatever day it is read on. */
function revealEffectiveFrom(
  group: Record<string, unknown>,
  body: Record<string, unknown>,
): string | null {
  const hour = body.reveal_hour ?? group.reveal_hour;
  return hour === group.reveal_hour ? null : "2026-08-12";
}

/** The primary circle as it currently stands: the payload file, plus anything patched onto it. */
async function primaryGroup(): Promise<Record<string, unknown>> {
  return { ...(await payload("group_current")) as Record<string, unknown>, ...patchedPrimary };
}

/** Apply a patch to the primary circle and remember it. The effective date is computed against
 *  the **payload file's** hour, not the patched one — that file is what the circle's already
 *  materialised rounds were built from, so it is the thing the current column is compared to. */
async function patchPrimary(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const original = await payload("group_current") as Record<string, unknown>;
  Object.assign(patchedPrimary, body, {
    reveal_effective_from: revealEffectiveFrom(original, {
      ...patchedPrimary,
      ...body,
    }),
  });
  return await primaryGroup();
}

function switcherStateFor(phase: Phase): { my_state: string; needs_action: boolean } {
  switch (phase) {
    case "open":
      return { my_state: "sealed", needs_action: false };
    case "open_nosub":
      return { my_state: "drop", needs_action: true };
    // Nothing to do yet: the round has not opened, so the switcher row is `drop` without the
    // dot. `currentState()` reads it as `open` off the `open_` prefix, which is what the round
    // itself is — the dark hours are not a state (docs/02 §1).
    case "open_darkhours":
      return { my_state: "drop", needs_action: false };
    case "revealed":
      return { my_state: "guess", needs_action: true };
    case "revealed_nosub":
    case "revealed_joinedlate":
      return { my_state: "guess", needs_action: false };
    case "scored":
      return { my_state: "answers", needs_action: false };
    case "voided":
      return { my_state: "voided", needs_action: false };
  }
}

Deno.serve({ port: PORT, onListen: ({ port }) => {
  console.log(`Blind Drop fixture server — phase=${PHASE} anchor=${ANCHOR} latency=${LATENCY_MS}ms`);
  console.log(`  http://127.0.0.1:${port}`);
} }, async (req) => {
  const url = new URL(req.url);
  if (LATENCY_MS > 0) await new Promise((r) => setTimeout(r, LATENCY_MS));
  try {
    return await route(req, url);
  } catch (e) {
    return fail(500, "INVALID_INPUT", "That didn't work. Try again.", { detail: String(e) });
  }
});
