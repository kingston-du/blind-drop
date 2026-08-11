// push.test.ts — APNs request shape, atomic claims, and send-before-mark. tasks/E06-02.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { serviceClient } from "../../functions/_shared/db.ts";
import {
  apnsRequest,
  type ClaimedNotification,
  drainPushOutbox,
  mapConcurrent,
  notificationExpiration,
  PUSH_CONCURRENCY,
  type PushDevice,
} from "../../functions/push-worker/worker.ts";
import {
  ANON_KEY,
  API_URL,
  call,
  newGroupOwner,
  SERVICE_KEY,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

// The worker still signs a real provider JWT when its HTTP hop is injected. This throwaway
// key matches local config and grants access to nothing outside this test stack.
Deno.env.set("APNS_KEY_ID", "FIXTUREKEY");
Deno.env.set("APNS_TEAM_ID", "FIXTURETEAM");
Deno.env.set(
  "APNS_PRIVATE_KEY",
  "-----BEGIN PRIVATE KEY-----\\n" +
    "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg+++sB8fDqPStKEYe\\n" +
    "+irO12iVTZL1ZfUO1Rix2vN/nTWhRANCAARtlFyvyNwGc+BTmoit5hxyjLrDMrNJ\\n" +
    "9DSpTPAag1J2STE165f2EBZGV/hrGwOr3wJBeVW0gp34EJ+PEkxfrqAc\\n" +
    "-----END PRIVATE KEY-----",
);
Deno.env.set("APNS_TOPIC", "com.blinddrop.fixture");

const row: ClaimedNotification = {
  id: "00000000-0000-4000-8000-000000000001",
  round_id: "00000000-0000-4000-8000-000000000002",
  kind: "reveal",
  audience: ["00000000-0000-4000-8000-000000000003"],
  attempts: 1,
  reveals_at: "2026-08-11T20:00:00Z",
  scores_at: "2026-08-11T22:00:00Z",
};
const device: PushDevice = {
  id: "00000000-0000-4000-8000-000000000004",
  user_id: row.audience[0],
  apns_token: "fixture-device-token",
  environment: "sandbox",
};

Deno.test("APNs headers, expiration, and custom payload are exact", async () => {
  const request = apnsRequest(row, device, "provider.jwt", "com.blinddrop.test");
  assertEquals(request.url, "https://api.sandbox.push.apple.com/3/device/fixture-device-token");
  assertEquals(request.method, "POST");
  assertEquals(request.headers.get("authorization"), "bearer provider.jwt");
  assertEquals(request.headers.get("apns-topic"), "com.blinddrop.test");
  assertEquals(request.headers.get("apns-push-type"), "alert");
  assertEquals(request.headers.get("apns-priority"), "10");
  assertEquals(request.headers.get("apns-collapse-id"), `${row.round_id}:reveal`);
  assertEquals(request.headers.get("apns-expiration"), String(notificationExpiration(row)));
  assertEquals(notificationExpiration(row), Date.parse(row.scores_at) / 1_000);

  assertEquals(await request.json(), {
    aps: {
      alert: { title: "Blind Drop", body: "Tonight's drop is open." },
      sound: "default",
      "interruption-level": "active",
    },
    kind: "reveal",
    round_id: row.round_id,
    deep_link: "blinddrop://round/current",
  });

  const results = { ...row, kind: "results" as const };
  assertEquals(
    notificationExpiration(results),
    (Date.parse(row.scores_at) + 12 * 60 * 60 * 1_000) / 1_000,
  );
  const resultsBody = await apnsRequest(results, device, "jwt", "topic").json();
  assertEquals(resultsBody.deep_link, "blinddrop://round/current/results");

  const nudge = { ...row, kind: "nudge" as const };
  assertEquals(notificationExpiration(nudge), Date.parse(row.reveals_at) / 1_000);
});

Deno.test("device sends are bounded at sixteen", async () => {
  let active = 0;
  let peak = 0;
  await mapConcurrent(
    Array.from({ length: 48 }, (_, index) => index),
    PUSH_CONCURRENCY,
    async () => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
    },
  );
  assertEquals(peak, PUSH_CONCURRENCY);
});

interface ServiceResponse {
  status: number;
  // deno-lint-ignore no-explicit-any
  body: any;
}

async function serviceRequest(
  path: string,
  opts: { method?: string; body?: unknown; prefer?: string } = {},
): Promise<ServiceResponse> {
  const response = await fetch(`${API_URL}/rest/v1/${path}`, {
    method: opts.method ?? "GET",
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
      ...(opts.prefer ? { prefer: opts.prefer } : {}),
    },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`service REST ${path}: ${response.status} ${text}`);
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

async function rpc(name: string, args: Record<string, unknown>) {
  return (await serviceRequest(`rpc/${name}`, { method: "POST", body: args })).body;
}

async function clearPending(exceptId?: string): Promise<void> {
  const exclude = exceptId ? `&id=neq.${exceptId}` : "";
  await serviceRequest(`notification_outbox?sent_at=is.null${exclude}`, {
    method: "PATCH",
    body: { sent_at: new Date().toISOString(), claimed_at: null, claim_id: null },
  });
}

Deno.test("claim leases are disjoint, crash-safe, and sent_at follows APNs", async () => {
  await clearPending();

  // First prove the real worker's ordering with an APNs hop held open by the test.
  const { user } = await newGroupOwner("Push Order", {
    name: `Push Order ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const current = await call("rounds", "/current", { token: user.token });
  const roundId = current.body.data.round_id as string;
  await serviceRequest("devices", {
    method: "POST",
    prefer: "return=minimal",
    body: {
      user_id: user.id,
      apns_token: crypto.randomUUID().replaceAll("-", ""),
      environment: "sandbox",
    },
  });
  await tickRoundsAt(9);
  const ownQueued = (await serviceRequest(
    `notification_outbox?select=id&round_id=eq.${roundId}&kind=eq.void`,
  )).body[0];
  assert(ownQueued?.id, "the tick enqueued the test group's void notification");
  await clearPending(ownQueued.id);

  let allowApns!: () => void;
  let sawApns!: () => void;
  const apnsStarted = new Promise<void>((resolve) => sawApns = resolve);
  const apnsMayFinish = new Promise<void>((resolve) => allowApns = resolve);
  const draining = drainPushOutbox(serviceClient(), async () => {
    sawApns();
    await apnsMayFinish;
    return { ok: true, status: 200, text: async () => "" };
  });
  await apnsStarted;

  const whileSending = (await serviceRequest(
    `notification_outbox?select=id,attempts,claimed_at,sent_at&round_id=eq.${roundId}&kind=eq.void`,
  )).body[0];
  assertEquals(whileSending.attempts, 1, "claim increments before the network hop");
  assert(whileSending.claimed_at !== null, "the active claim has a lease");
  assertEquals(whileSending.sent_at, null, "a row is not sent while APNs is still in flight");

  allowApns();
  const drained = await draining;
  assert(drained.claimed >= 1, "the pass includes the test row");
  assertEquals(drained.sent, drained.claimed, "every claimed fixture send completed");
  assertEquals(drained.failed, 0);
  assertEquals(drained.devices, 1, "only the test row has an active device");
  const afterSend = (await serviceRequest(
    `notification_outbox?select=claim_id,claimed_at,sent_at&round_id=eq.${roundId}&kind=eq.void`,
  )).body[0];
  assert(afterSend.sent_at !== null, "sent_at is written after APNs completes");
  assertEquals(afterSend.claim_id, null);
  assertEquals(afterSend.claimed_at, null);

  // Then arrange two fresh rows and race the atomic SQL claim itself. Persisted leases make
  // this deterministic even if PostgREST happens to serialize the two HTTP requests.
  await clearPending();
  const [pushA, pushB] = await Promise.all([
    newGroupOwner("Push A", {
      name: `Push A ${crypto.randomUUID().slice(0, 8)}`,
      timezone: zoneWhereLocalHourIs(12),
      reveal_hour: 20,
    }),
    newGroupOwner("Push B", {
      name: `Push B ${crypto.randomUUID().slice(0, 8)}`,
      timezone: zoneWhereLocalHourIs(12),
      reveal_hour: 20,
    }),
  ]);
  // Creating a group and creating its first round are separate API calls. Materialise both
  // while their real reveal is still ahead; the time-travelled tick then advances them.
  await Promise.all([
    call("rounds", "/current", { token: pushA.user.token }),
    call("rounds", "/current", { token: pushB.user.token }),
  ]);
  await tickRoundsAt(9);

  const firstClaim = crypto.randomUUID();
  const secondClaim = crypto.randomUUID();
  const [firstRows, secondRows] = await Promise.all([
    rpc("claim_notification_outbox", { p_claim_id: firstClaim, p_limit: 1 }),
    rpc("claim_notification_outbox", { p_claim_id: secondClaim, p_limit: 1 }),
  ]);
  assertEquals(firstRows.length, 1);
  assertEquals(secondRows.length, 1);
  assert(firstRows[0].id !== secondRows[0].id, "overlapping claims must be disjoint");
  assertEquals(firstRows[0].attempts, 1);
  assertEquals(secondRows[0].attempts, 1);

  // One claim completes. The other "crashes" before marking: age its lease past the next
  // minute, remove every other pending row, and claim again. The APNs collapse id is derived
  // only from round + kind, so the retry is visibly identical to the original send.
  await rpc("finish_notification_outbox", {
    p_id: secondRows[0].id,
    p_claim_id: secondClaim,
  });
  await clearPending(firstRows[0].id);
  await serviceRequest(`notification_outbox?id=eq.${firstRows[0].id}`, {
    method: "PATCH",
    body: { claimed_at: "2000-01-01T00:00:00Z" },
  });

  const retryClaim = crypto.randomUUID();
  const retried = await rpc("claim_notification_outbox", {
    p_claim_id: retryClaim,
    p_limit: 1,
  });
  assertEquals(retried.length, 1);
  assertEquals(retried[0].id, firstRows[0].id);
  assertEquals(retried[0].attempts, 2);

  const firstRequest = apnsRequest(firstRows[0], device, "jwt", "topic");
  const retryRequest = apnsRequest(retried[0], device, "jwt", "topic");
  assertEquals(
    retryRequest.headers.get("apns-collapse-id"),
    firstRequest.headers.get("apns-collapse-id"),
    "a post-crash retry must collapse onto the original visible notification",
  );
  await rpc("finish_notification_outbox", { p_id: retried[0].id, p_claim_id: retryClaim });
});

Deno.test("the push worker is closed to everybody but the scheduler", async () => {
  const { user } = await newGroupOwner("Push Door", {
    name: `Push Door ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(12),
  });
  for (
    const [label, response] of [
      ["anonymous", await call("push-worker", "/", { method: "POST", token: null, body: {} })],
      ["member", await call("push-worker", "/", { method: "POST", token: user.token, body: {} })],
      ["anon key", await call("push-worker", "/", { method: "POST", token: ANON_KEY, body: {} })],
    ] as const
  ) {
    assertEquals(response.status, 401, label);
    assertEquals(response.body.error.code, "UNAUTHENTICATED", label);
  }

  const scheduler = await call("push-worker", "/", {
    method: "POST",
    token: SERVICE_KEY,
    body: {},
  });
  assertEquals(scheduler.status, 200);
  assertEquals(Object.keys(scheduler.body.data).sort(), ["claimed", "devices", "failed", "sent"]);
});
