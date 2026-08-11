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
  const [o, r, s] = OFFSETS[PHASE];
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

// ─── routes ──────────────────────────────────────────────────────────────────
async function route(req: Request, url: URL): Promise<Response> {
  const p = url.pathname.replace(/^\/functions\/v1/, "").replace(/\/$/, "") || "/";
  const m = req.method;

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
    const round = await payload(PHASES[PHASE]) as Record<string, unknown>;
    return ok(reTime(round, new Date()));
  }
  if (m === "PUT" && p === "/rounds/current/submission") {
    if (PHASE !== "open" && PHASE !== "open_nosub") {
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
    if (!PHASE.startsWith("revealed")) {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    if (PHASE === "revealed_nosub") {
      return fail(403, "NOT_A_SUBMITTER", "You didn't drop a song tonight.");
    }
    if (PHASE === "revealed_joinedlate") {
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
    if (PHASE !== "scored") {
      return fail(409, "WRONG_PHASE", "That's not available right now.", { state: currentState() });
    }
    return ok(await payload("results"));
  }

  if (m === "GET" && p === "/__fixture") {
    return ok({ phase: PHASE, latency_ms: LATENCY_MS, anchor: ANCHOR,
                phases: Object.keys(PHASES) });
  }

  return fail(404, "NOT_FOUND", "That's not available right now.");
}

function currentState(): string {
  if (PHASE.startsWith("open")) return "open";
  if (PHASE.startsWith("revealed")) return "revealed";
  return PHASE;
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
