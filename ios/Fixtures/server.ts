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
  if (ANCHOR !== "now") return round;
  const [o, r, s] = OFFSETS[activePhase];
  const at = (m: number) => rfc3339(new Date(now.getTime() + m * 60_000));
  return { ...round, opens_at: at(o), reveals_at: at(r), scores_at: at(s) };
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

  if (m === "GET" && p === "/me") return ok(await payload("me"));
  if (m === "PUT" && p === "/me") {
    const body = await req.json().catch(() => ({}));
    const name = String(body.display_name ?? "").trim();
    if (!name) return fail(400, "INVALID_INPUT", "Enter a name to continue.", { field: "display_name" });
    if (name.length > 24) return fail(400, "INVALID_INPUT", "Keep it to 24 characters.", { field: "display_name" });
    return ok({ ...(await payload("me") as object), display_name: name });
  }
  if (m === "DELETE" && p === "/me") return noContent();
  if (m === "POST" && p === "/devices") return noContent();

  if (m === "GET" && p === "/groups/current") return ok(await payload("group_current"));
  if (m === "POST" && p === "/groups") return ok(await payload("group_current"));
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
    const g = await payload("group_current") as Record<string, unknown>;
    // reveal_hour changes land on the first round not yet created (docs/04 §3).
    return ok({ ...g, ...body, effective_from: "2026-08-12" });
  }
  if (m === "POST" && p === "/groups/current/leave") return noContent();
  if (m === "GET" && p === "/groups/current/standings") return ok(await payload("standings"));
  if (m === "GET" && p === "/groups/current/record") return ok(await payload("record"));
  if (m === "GET" && p === "/groups/current/record/export") {
    const svc = url.searchParams.get("service") === "apple" ? "apple" : "spotify";
    return ok(await payload(`record_export_${svc}`));
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
    if (activePhase !== "scored") {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    return ok(await payload("results"));
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
