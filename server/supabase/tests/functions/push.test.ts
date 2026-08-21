// push.test.ts — APNs request shape, atomic claims, send-before-mark, and what happens when
// a send does not work. tasks/E06-02, E06-04.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { serviceClient } from "../../functions/_shared/db.ts";
import {
  apnsRequest,
  type ClaimedNotification,
  drainPushOutbox,
  mapConcurrent,
  notificationExpiration,
  PUSH_CONCURRENCY,
  PUSH_MAX_ATTEMPTS,
  type PushDevice,
} from "../../functions/push-worker/worker.ts";
import {
  ANON_KEY,
  API_URL,
  call,
  newGroupOwner,
  newMember,
  newNamedUser,
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
  group_id: "00000000-0000-4000-8000-000000000006",
  invitation_id: null,
  kind: "reveal",
  audience: ["00000000-0000-4000-8000-000000000003"],
  attempts: 1,
  reveals_at: "2026-08-11T20:00:00Z",
  scores_at: "2026-08-11T22:00:00Z",
  invitation_expires_at: null,
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
  assertEquals(notificationExpiration(row), Date.parse(row.scores_at!) / 1_000);

  assertEquals(await request.json(), {
    aps: {
      alert: { title: "Blind Drop", body: "Tonight's songs are out." },
      sound: "default",
      "interruption-level": "active",
    },
    kind: "reveal",
    round_id: row.round_id,
    deep_link: `blinddrop://circle/${row.group_id}/round/current`,
  });

  const results = { ...row, kind: "results" as const };
  assertEquals(
    notificationExpiration(results),
    (Date.parse(row.scores_at!) + 12 * 60 * 60 * 1_000) / 1_000,
  );
  const resultsBody = await apnsRequest(results, device, "jwt", "topic").json();
  assertEquals(resultsBody.deep_link, `blinddrop://circle/${row.group_id}/round/current/results`);

  const nudge = { ...row, kind: "nudge" as const };
  assertEquals(notificationExpiration(nudge), Date.parse(row.reveals_at!) / 1_000);

  const invitation: ClaimedNotification = {
    ...row,
    round_id: null,
    group_id: null,
    invitation_id: "00000000-0000-4000-8000-000000000005",
    kind: "invite",
    reveals_at: null,
    scores_at: null,
    invitation_expires_at: "2026-08-25T20:00:00Z",
  };
  const invitationRequest = apnsRequest(invitation, device, "jwt", "topic");
  assertEquals(invitationRequest.headers.get("apns-collapse-id"), `invite:${invitation.invitation_id}`);
  assertEquals(notificationExpiration(invitation), Date.parse(invitation.invitation_expires_at!) / 1_000);
  assertEquals(await invitationRequest.json(), {
    aps: {
      alert: { title: "Blind Drop", body: "You have a group invite." },
      sound: "default",
      "interruption-level": "active",
    },
    kind: "invite",
    deep_link: `blinddrop://invite/${invitation.invitation_id}`,
  });
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

interface InvitationOutboxRow {
  id: string;
  invitation_id: string;
  audience: string[];
  sent_at: string | null;
}

async function invitationOutboxFor(userID: string): Promise<InvitationOutboxRow[]> {
  const rows = (await serviceRequest(
    "notification_outbox?select=id,invitation_id,audience,sent_at&kind=eq.invite",
  )).body as InvitationOutboxRow[];
  return rows.filter((row) => row.audience.includes(userID));
}

// ─── E20-03 · direct-invitation deliveries ───────────────────────────────────

Deno.test("invitations enqueue one budgeted delivery and coalesce before it sends", async () => {
  await clearPending();
  const recipient = await newNamedUser("Invite Recipient");
  const first = await newGroupOwner("First Inviter");
  const second = await newGroupOwner("Second Inviter");

  const firstInvite = await call("groups", "/current/invitations", {
    method: "POST",
    token: first.user.token,
    body: { user_id: recipient.id },
  });
  assertEquals(firstInvite.status, 200);
  const secondInvite = await call("groups", "/current/invitations", {
    method: "POST",
    token: second.user.token,
    body: { user_id: recipient.id },
  });
  assertEquals(secondInvite.status, 200);

  const coalesced = await invitationOutboxFor(recipient.id);
  assertEquals(coalesced.length, 1, "several pending invitations become one delivery");
  assertEquals(
    coalesced[0].invitation_id,
    firstInvite.body.data.id,
    "the one prompt opens a real pending invitation; the switcher lists the other",
  );
  assertEquals(coalesced[0].sent_at, null);

  // A sent notification consumes one of the same rolling 24-hour slots as all round kinds.
  // Make three such events against different circles, settling each one as the fixture APNs
  // worker would, then prove a fourth direct invitation remains silent.
  await clearPending();
  for (const label of ["Budget Two", "Budget Three"]) {
    const inviter = await newGroupOwner(label);
    const invite = await call("groups", "/current/invitations", {
      method: "POST",
      token: inviter.user.token,
      body: { user_id: recipient.id },
    });
    assertEquals(invite.status, 200);
    await clearPending();
  }
  const fourth = await newGroupOwner("Budget Four");
  const fourthInvite = await call("groups", "/current/invitations", {
    method: "POST",
    token: fourth.user.token,
    body: { user_id: recipient.id },
  });
  assertEquals(fourthInvite.status, 200, "the invitation itself is never refused by push budget");
  assertEquals(
    (await invitationOutboxFor(recipient.id)).length,
    3,
    "the fourth invitation does not become a fourth delivery in the rolling day",
  );
});

Deno.test("an invite delivery points to its recipient-owned invitation", async () => {
  await clearPending();
  const recipient = await newNamedUser("Push Invitee");
  const { user: inviter } = await newGroupOwner("Push Inviter");
  const deviceToken = await registerDevice(recipient.token);
  const invitation = await call("groups", "/current/invitations", {
    method: "POST",
    token: inviter.token,
    body: { user_id: recipient.id },
  });
  assertEquals(invitation.status, 200);

  const observed: Request[] = [];
  const drained = await drainPushOutbox(serviceClient(), async (request) => {
    observed.push(request);
    return { ok: true, status: 200, text: async () => "" };
  });
  assertEquals(drained.claimed, 1);
  assertEquals(new URL(observed[0].url).pathname.endsWith(deviceToken), true);
  const payload = await observed[0].json();
  assertEquals(payload.kind, "invite");
  assertEquals(payload.deep_link, `blinddrop://invite/${invitation.body.data.id}`);
  assertEquals("round_id" in payload, false, "direct invitations do not pretend to have a round");
});

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
  assertEquals(
    Object.keys(scheduler.body.data).sort(),
    ["claimed", "devices", "disabled", "failed", "sent"],
  );
});

// ─── E06-04 · what happens when a send does not work ─────────────────────────
// docs/05 §6 gives three failures three different endings, and the difference between them is
// the whole of this section: a dead token is switched off, a busy Apple is retried, and a row
// that has failed five times stops rather than retrying until the heat death of the group.

/** A device registered the way the app registers one — through the real endpoint. */
async function registerDevice(token: string): Promise<string> {
  const apnsToken = Array.from(
    crypto.getRandomValues(new Uint8Array(32)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const res = await call("devices", "/", {
    method: "POST",
    token,
    body: { apns_token: apnsToken, environment: "sandbox" },
  });
  assertEquals(res.status, 204, "registering a test device");
  return apnsToken;
}

/** The device token an APNs request is addressed to — the last path segment. */
function addressedToken(request: Request): string {
  return new URL(request.url).pathname.split("/").pop() as string;
}

/** An `ApnsFetch` that records every request and answers per token. */
function stubApns(answer: (token: string) => { status: number; body?: string }) {
  const tokens: string[] = [];
  const fetchApns = async (request: Request) => {
    const token = addressedToken(request);
    tokens.push(token);
    const { status, body } = answer(token);
    return { ok: status >= 200 && status < 300, status, text: async () => body ?? "" };
  };
  return { tokens, fetchApns };
}

interface OutboxRow {
  id: string;
  attempts: number;
  sent_at: string | null;
  claim_id: string | null;
  claimed_at: string | null;
  last_error: string | null;
}

async function outboxRow(roundId: string, kind: string): Promise<OutboxRow> {
  const columns = "id,attempts,sent_at,claim_id,claimed_at,last_error";
  const rows = (await serviceRequest(
    `notification_outbox?select=${columns}&round_id=eq.${roundId}&kind=eq.${kind}`,
  )).body as OutboxRow[];
  assertEquals(rows.length, 1, `expected exactly one ${kind} row for ${roundId}`);
  return rows[0];
}

async function outboxKinds(roundId: string): Promise<string[]> {
  const rows = (await serviceRequest(
    `notification_outbox?select=kind&round_id=eq.${roundId}`,
  )).body as { kind: string }[];
  return rows.map((row) => row.kind).sort();
}

async function deviceDisabledAt(apnsToken: string): Promise<string | null> {
  const rows = (await serviceRequest(
    `devices?select=disabled_at&apns_token=eq.${apnsToken}`,
  )).body as { disabled_at: string | null }[];
  assertEquals(rows.length, 1, "expected exactly one device row");
  return rows[0].disabled_at;
}

/** A group whose round is about to void, with the owner's device registered. */
async function voidingRound(label: string): Promise<{ roundId: string; user_token: string }> {
  const { user } = await newGroupOwner(label, {
    name: `${label} ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const current = await call("rounds", "/current", { token: user.token });
  return { roundId: current.body.data.round_id as string, user_token: user.token };
}

Deno.test("410 Unregistered switches the token off and does not fail the row", async () => {
  await clearPending();
  const { roundId, user_token } = await voidingRound("Push Gone");
  const dead = await registerDevice(user_token);
  const alive = await registerDevice(user_token);
  await tickRoundsAt(9);
  const queued = await outboxRow(roundId, "void");
  await clearPending(queued.id);

  const { tokens, fetchApns } = stubApns((token) =>
    token === dead ? { status: 410, body: '{"reason":"Unregistered"}' } : { status: 200 }
  );
  const drained = await drainPushOutbox(serviceClient(), fetchApns);

  assertEquals(drained.devices, 2, "both of the user's devices were addressed");
  assertEquals(drained.disabled, 1);
  assertEquals(drained.failed, 0, "a dead token is not a failed notification");
  assertEquals(drained.sent, drained.claimed);

  assert(await deviceDisabledAt(dead) !== null, "a 410 disables the token");
  assertEquals(await deviceDisabledAt(alive), null, "the other device is untouched");

  const after = await outboxRow(roundId, "void");
  assert(after.sent_at !== null, "the row is done — retrying it would collect the same 410");
  assertEquals(after.last_error, null);

  // Never retried: the next pass has nothing to claim, and the dead token is not addressed
  // again even when it is.
  const second = await drainPushOutbox(serviceClient(), fetchApns);
  assertEquals(second.claimed, 0);
  assertEquals(tokens.filter((token) => token === dead).length, 1);

  // And a re-registration is how a device comes back (E06-03): `disabled_at` is cleared, not
  // permanent, because the app presenting the token again is evidence the 410 no longer holds.
  const res = await call("devices", "/", {
    method: "POST",
    token: user_token,
    body: { apns_token: dead, environment: "sandbox" },
  });
  assertEquals(res.status, 204);
  assertEquals(await deviceDisabledAt(dead), null);
});

Deno.test("429 and 5xx leave the row for the next minute, then stop at five attempts", async () => {
  await clearPending();
  const { roundId, user_token } = await voidingRound("Push Busy");
  await registerDevice(user_token);
  await tickRoundsAt(9);
  const queued = await outboxRow(roundId, "void");

  // Apple is busy, then broken, then busy again. Nothing here is permanent, so nothing here
  // may consume the row — until the ceiling does.
  const statuses = [429, 503, 500, 429, 503];
  for (const [index, status] of statuses.entries()) {
    await clearPending(queued.id);
    const { fetchApns } = stubApns(() => ({ status, body: '{"reason":"TooManyRequests"}' }));
    const drained = await drainPushOutbox(serviceClient(), fetchApns);
    assert(drained.claimed >= 1, `pass ${index + 1} claimed the row`);
    assertEquals(drained.failed, drained.claimed);
    assertEquals(drained.sent, 0);

    const row = await outboxRow(roundId, "void");
    assertEquals(row.attempts, index + 1, "each pass is exactly one attempt");
    assertEquals(row.sent_at, null, "a failed send never marks the row sent");
    assertEquals(row.claim_id, null, "the lease is released so the next minute can retry");
    assertEquals(row.claimed_at, null);
    assert(row.last_error?.startsWith(String(status)), `last_error records ${status}`);
  }

  // Five attempts and it stops. The row is not claimable, so no worker will try a sixth time,
  // and the reason it stopped is still on the row for whoever comes looking.
  await clearPending(queued.id);
  const nothingLeft = await drainPushOutbox(serviceClient(), stubApns(() => ({ status: 200 })).fetchApns);
  assertEquals(nothingLeft.claimed, 0, "a row at the attempt ceiling is never claimed again");

  const abandoned = await outboxRow(roundId, "void");
  assertEquals(abandoned.attempts, PUSH_MAX_ATTEMPTS);
  assertEquals(abandoned.sent_at, null);
  assert(abandoned.last_error?.startsWith("503"), "the last failure survives on the row");
});

Deno.test("the nudge audience is the active roster at enqueue — docs/05 §3", async () => {
  await clearPending();
  // 17:00 local with a reveal at 20:00, so a tick an hour and a half on lands inside the
  // two-hour nudge window without changing the group's local date.
  const { user: ana, group } = await newGroupOwner("Ana", {
    name: `Push Nudge ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 20,
  });
  const ben = await newMember(group.invite_code as string, "Ben");
  const cal = await newMember(group.invite_code as string, "Cal");
  const roundId =
    (await call("rounds", "/current", { token: ana.token })).body.data.round_id as string;

  const tokens = {
    ana: await registerDevice(ana.token),
    ben: await registerDevice(ben.token),
    cal: await registerDevice(cal.token),
  };

  // Ana seals before the nudge is enqueued. The nudge still invites her to revise that choice.
  assertEquals(
    (await call("rounds", "/current/submission", {
      method: "PUT",
      token: ana.token,
      body: { apple_music_id: "1440818664" },
    })).status,
    200,
  );

  await tickRoundsAt(1.5);
  const enqueued = (await serviceRequest(
    `notification_outbox?select=id,audience&round_id=eq.${roundId}&kind=eq.nudge`,
  )).body as { id: string; audience: string[] }[];
  assertEquals(enqueued.length, 1, "one nudge, at reveals_at − 2h");
  assertEquals(
    [...enqueued[0].audience].sort(),
    [ana.id, ben.id, cal.id].sort(),
    "the nudge reaches every active member, including people who already dropped",
  );

  // Cal seals at −1h55m, and a second tick runs before the worker does. The audience is not
  // revised: re-resolving at send time would mean the worker reads submission state.
  assertEquals(
    (await call("rounds", "/current/submission", {
      method: "PUT",
      token: cal.token,
      body: { apple_music_id: "1440765580" },
    })).status,
    200,
  );
  await tickRoundsAt(1.6);
  const afterCalSealed = (await serviceRequest(
    `notification_outbox?select=id,audience&round_id=eq.${roundId}&kind=eq.nudge`,
  )).body as { id: string; audience: string[] }[];
  assertEquals(afterCalSealed.length, 1, "a second tick does not enqueue a second nudge");
  assertEquals(
    [...afterCalSealed[0].audience].sort(),
    [ana.id, ben.id, cal.id].sort(),
    "someone who seals after the freeze still receives the nudge",
  );

  await clearPending(enqueued[0].id);
  const stub = stubApns(() => ({ status: 200 }));
  await drainPushOutbox(serviceClient(), stub.fetchApns);
  assertEquals(stub.tokens.sort(), [tokens.ana, tokens.ben, tokens.cal].sort());
});

Deno.test("reveal and void are mutually exclusive for a round", async () => {
  const zone = zoneWhereLocalHourIs(17);
  const { user: owner, group } = await newGroupOwner("Ana", {
    name: `Push Reveal ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zone,
    reveal_hour: 18,
  });
  const sealers = [
    owner,
    await newMember(group.invite_code as string, "Ben"),
    await newMember(group.invite_code as string, "Cal"),
  ];
  const revealing =
    (await call("rounds", "/current", { token: owner.token })).body.data.round_id as string;
  for (const [index, member] of sealers.entries()) {
    const res = await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: ["1440818664", "1440765580", "1452874255"][index] },
    });
    assertEquals(res.status, 200, `sealer ${index}`);
  }

  // A second group in the same hour with one submitter, which is two short of a round.
  const { user: lonely } = await newGroupOwner("Ivy", {
    name: `Push Void ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zone,
    reveal_hour: 18,
  });
  const voiding =
    (await call("rounds", "/current", { token: lonely.token })).body.data.round_id as string;
  assertEquals(
    (await call("rounds", "/current/submission", {
      method: "PUT",
      token: lonely.token,
      body: { apple_music_id: "1440830827" },
    })).status,
    200,
  );

  // Reveal, then score, in two ticks — the pair a real evening produces.
  await tickRoundsAt(1.5);
  await tickRoundsAt(3.5);

  assertEquals(await outboxKinds(revealing), ["results", "reveal"]);
  assertEquals(await outboxKinds(voiding), ["void"]);
  for (const roundId of [revealing, voiding]) {
    const exclusive = (await serviceRequest(
      `notification_outbox?select=kind&round_id=eq.${roundId}&kind=in.(reveal,void)`,
    )).body as { kind: string }[];
    assertEquals(exclusive.length, 1, `${roundId} announced its outcome exactly once`);
  }
});

Deno.test("a delivered row is one push per device and is never delivered twice", async () => {
  // The season budget — no more than three notifications to anyone in any 24 hours — is
  // proven at the enqueue layer over fourteen simulated days by
  // `tests/db/notification_budget.sql`. This is the other half: what the outbox holds is what
  // the phone gets, exactly once per registered device, so the enqueue budget *is* the
  // delivery budget.
  await clearPending();
  const { roundId, user_token } = await voidingRound("Push Once");
  const first = await registerDevice(user_token);
  const second = await registerDevice(user_token);
  await tickRoundsAt(9);
  const queued = await outboxRow(roundId, "void");
  await clearPending(queued.id);

  const stub = stubApns(() => ({ status: 200 }));
  const drained = await drainPushOutbox(serviceClient(), stub.fetchApns);
  assertEquals(drained.claimed, 1);
  assertEquals(stub.tokens.sort(), [first, second].sort(), "one push per device, and no more");

  const again = await drainPushOutbox(serviceClient(), stub.fetchApns);
  assertEquals(again.claimed, 0, "a sent row is not claimed a second time");
  assertEquals(stub.tokens.length, 2);
});
