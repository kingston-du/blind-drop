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
  sealReminderFiring,
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
  scheduled_for: "2026-08-11T20:00:00Z",
  invitation_expires_at: null,
  cue_text: null,
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

  // seal_reminder expires at reveal — a reminder to seal is pointless once the round revealed.
  const sealFirst = {
    ...row,
    kind: "seal_reminder" as const,
    scheduled_for: "2026-08-11T18:00:00Z", // reveals_at − 2h
  };
  assertEquals(notificationExpiration(sealFirst), Date.parse(row.reveals_at!) / 1_000);
  assertEquals(sealReminderFiring(sealFirst), "first");
  const sealFirstBody = await apnsRequest(sealFirst, device, "jwt", "topic").json();
  assertEquals(sealFirstBody.aps.alert, {
    title: "Blind Drop",
    body: "You haven't sealed a song yet. Two hours left.",
  });
  assertEquals(sealFirstBody.deep_link, `blinddrop://circle/${row.group_id}/round/current`);

  const sealSecond = {
    ...row,
    kind: "seal_reminder" as const,
    scheduled_for: "2026-08-11T19:30:00Z", // reveals_at − 30m
  };
  assertEquals(sealReminderFiring(sealSecond), "second");
  const sealSecondBody = await apnsRequest(sealSecond, device, "jwt", "topic").json();
  assertEquals(sealSecondBody.aps.alert, {
    title: "Blind Drop",
    body: "Half an hour left, and you haven't sealed a song.",
  });
  // Both firings collapse into one banner on the device — same round, same kind.
  assertEquals(
    apnsRequest(sealFirst, device, "jwt", "topic").headers.get("apns-collapse-id"),
    apnsRequest(sealSecond, device, "jwt", "topic").headers.get("apns-collapse-id"),
  );

  // E35-06 (docs/18-CUES.md §11.1): a single-circle seal_reminder relays the round's cue into
  // the body as a "Tonight: <cue>" suffix on whichever firing's base sentence applies.
  const sealFirstCued = { ...sealFirst, cue_text: "A song you hate" };
  const sealFirstCuedBody = await apnsRequest(sealFirstCued, device, "jwt", "topic").json();
  assertEquals(sealFirstCuedBody.aps.alert.body, "You haven't sealed a song yet. Two hours left. Tonight: A song you hate");

  const sealSecondCued = { ...sealSecond, cue_text: "A song you hate" };
  const sealSecondCuedBody = await apnsRequest(sealSecondCued, device, "jwt", "topic").json();
  assertEquals(sealSecondCuedBody.aps.alert.body, "Half an hour left, and you haven't sealed a song. Tonight: A song you hate");

  // guess_reminder expires at scoring — a reminder to guess is pointless once the round scored.
  const guessReminder = {
    ...row,
    kind: "guess_reminder" as const,
    scheduled_for: "2026-08-11T21:30:00Z", // scores_at − 30m
  };
  assertEquals(notificationExpiration(guessReminder), Date.parse(row.scores_at!) / 1_000);
  const guessReminderBody = await apnsRequest(guessReminder, device, "jwt", "topic").json();
  assertEquals(guessReminderBody.aps.alert, {
    title: "Blind Drop",
    body: "Half an hour left to guess who dropped what.",
  });
  assertEquals(guessReminderBody.deep_link, `blinddrop://circle/${row.group_id}/round/current`);

  const invitation: ClaimedNotification = {
    ...row,
    round_id: null,
    group_id: null,
    invitation_id: "00000000-0000-4000-8000-000000000005",
    kind: "invite",
    reveals_at: null,
    scores_at: null,
    scheduled_for: null,
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

Deno.test("invitations coalesce before sending, with no fixed daily delivery ceiling (E31-01)", async () => {
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

  // E31-01 lifted the fixed 3-deliveries/24h ceiling this used to be capped by. Send two more
  // direct-invitation deliveries against different circles (three total, settled as the fixture
  // APNs worker would), then prove a fourth is admitted too — nothing throttles it centrally
  // anymore; only the coalescing above (several *pending* invites, one row) still applies.
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
  assertEquals(fourthInvite.status, 200, "the invitation itself was never refused by push budget");
  assertEquals(
    (await invitationOutboxFor(recipient.id)).length,
    4,
    "the fourth invitation is now a real fourth delivery — E31-01 lifted the daily cap",
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

/** An `ApnsFetch` that records every request and always succeeds — for asserting on bodies. */
function captureApns() {
  const requests: Request[] = [];
  const fetchApns = async (request: Request) => {
    requests.push(request);
    return { ok: true, status: 200, text: async () => "" };
  };
  return { requests, fetchApns };
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

/**
 * Every seal_reminder row for a round, oldest `scheduled_for` first — E31-01 fires this kind
 * twice per round (`reveals_at − 2h`, then `− 30m`), so callers pick firing 1/2 by position.
 */
async function sealReminderRows(roundId: string): Promise<{ id: string; audience: string[] }[]> {
  return (await serviceRequest(
    `notification_outbox?select=id,audience&round_id=eq.${roundId}&kind=eq.seal_reminder` +
      `&order=scheduled_for.asc`,
  )).body as { id: string; audience: string[] }[];
}

Deno.test(
  "seal_reminder and guess_reminder audiences are conditional at enqueue, and trimmed at " +
    "claim — docs/05 §3, E31-01",
  async () => {
    await clearPending();
    // 17:00 local with a reveal at 20:00 (scores at 22:00), so the offsets below land inside
    // each window without crossing the group's local date.
    const { user: ana, group } = await newGroupOwner("Ana", {
      name: `Push Reminders ${crypto.randomUUID().slice(0, 8)}`,
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

    // Ben drops right away — he should never appear in either seal_reminder firing.
    assertEquals(
      (await call("rounds", "/current/submission", {
        method: "PUT",
        token: ben.token,
        body: { apple_music_id: "1440818664" },
      })).status,
      200,
    );

    // ── reveals_at − 2h (offset 1.5h → 18:30 local): Ben has submitted, Ana and Cal have not ──
    await tickRoundsAt(1.5);
    const afterFirstTick = await sealReminderRows(roundId);
    assertEquals(afterFirstTick.length, 1, "one seal_reminder row after the 2h window opens");
    assertEquals(
      [...afterFirstTick[0].audience].sort(),
      [ana.id, cal.id].sort(),
      "the 2h reminder reaches only members who haven't sealed a song yet",
    );

    // Cal seals between the two firings.
    assertEquals(
      (await call("rounds", "/current/submission", {
        method: "PUT",
        token: cal.token,
        body: { apple_music_id: "1440765580" },
      })).status,
      200,
    );

    // ── reveals_at − 30m (offset 2.6h → 19:36 local): only Ana is still unsealed ─────────────
    await tickRoundsAt(2.6);
    const afterSecondTick = await sealReminderRows(roundId);
    assertEquals(afterSecondTick.length, 2, "the 30m window adds a second, distinct row");
    const [firstFiring, secondFiring] = afterSecondTick;
    assertEquals(
      [...firstFiring.audience].sort(),
      [ana.id, cal.id].sort(),
      "the first firing's own row is not rewritten by Cal sealing later — frozen at enqueue",
    );
    assertEquals(
      [...secondFiring.audience],
      [ana.id],
      "the 30m reminder is computed fresh: Cal has since sealed and drops out",
    );

    // Ana seals just before reveal — after both seal_reminder rows were frozen, before either
    // is drained. This is the enqueue/claim gap docs/05 §3 now calls out explicitly.
    assertEquals(
      (await call("rounds", "/current/submission", {
        method: "PUT",
        token: ana.token,
        body: { apple_music_id: "1452874255" },
      })).status,
      200,
    );

    // Draining now must skip Ana on *both* rows — her condition resolved before claim — and
    // send nobody else, since the DB rows still list only her (Cal already excluded from the
    // second, and never in the first... Ben never appears in either).
    await clearPending(firstFiring.id);
    const sealDrain = stubApns(() => ({ status: 200 }));
    await drainPushOutbox(serviceClient(), sealDrain.fetchApns);
    assertEquals(sealDrain.tokens, [], "seal_reminder(2h): Ana sealed before claim, so no send");
    const firstFiringSentAt = (await serviceRequest(
      `notification_outbox?select=sent_at&id=eq.${firstFiring.id}`,
    )).body as { sent_at: string | null }[];
    assertEquals(
      firstFiringSentAt[0].sent_at !== null,
      true,
      "settled to an empty audience still marks the row sent_at",
    );

    await clearPending(secondFiring.id);
    const secondDrain = stubApns(() => ({ status: 200 }));
    await drainPushOutbox(serviceClient(), secondDrain.fetchApns);
    assertEquals(secondDrain.tokens, [], "seal_reminder(30m): Ana sealed before claim too");

    // ── reveal, at reveals_at (offset 3.0h → 20:00 local): unconditional, unaffected by E31-01 ─
    await clearPending();
    await tickRoundsAt(3.0);
    // Both seal_reminder rows are already sent (drained above); this adds exactly one more kind.
    assertEquals(await outboxKinds(roundId), ["reveal", "seal_reminder", "seal_reminder"]);

    // Ben completes his guess sheet; Cal makes one of two guesses (partial); Ana never opens
    // the sheet at all. `card_no` is shared round-wide, but "the other two cards" is relative
    // to each guesser's own card, so each fetches their own view.
    async function otherCardNosFor(token: string): Promise<number[]> {
      const view = (await call("rounds", "/current", { token })).body
        .data as { cards: { card_no: number }[]; my_card_no: number };
      const others = view.cards.map((c) => c.card_no).filter((n) => n !== view.my_card_no);
      assertEquals(others.length, 2, "three submitters means two cards to name");
      return others;
    }

    const bensOthers = await otherCardNosFor(ben.token);
    assertEquals(
      (await call("rounds", "/current/guesses", {
        method: "PUT",
        token: ben.token,
        body: {
          assignments: bensOthers.map((card_no) => ({ card_no, guessed_user_id: ana.id })),
        },
      })).status,
      200,
      "Ben completes his sheet",
    );

    const calsOthers = await otherCardNosFor(cal.token);
    assertEquals(
      (await call("rounds", "/current/guesses", {
        method: "PUT",
        token: cal.token,
        body: { assignments: [{ card_no: calsOthers[0], guessed_user_id: ana.id }] },
      })).status,
      200,
      "Cal guesses only one of two cards",
    );

    // ── guess_reminder, at scores_at − 30m (offset 4.6h → 21:36 local) ──────────────────────
    await tickRoundsAt(4.6);
    const guessReminderEnqueued = (await serviceRequest(
      `notification_outbox?select=id,audience&round_id=eq.${roundId}&kind=eq.guess_reminder`,
    )).body as { id: string; audience: string[] }[];
    assertEquals(guessReminderEnqueued.length, 1, "one guess_reminder, at scores_at − 30m");
    assertEquals(
      [...guessReminderEnqueued[0].audience].sort(),
      [ana.id, cal.id].sort(),
      "guess_reminder reaches submitters with an incomplete sheet — Ben is done, so excluded",
    );

    // Cal finishes their sheet after enqueue, before the worker claims the row.
    assertEquals(
      (await call("rounds", "/current/guesses", {
        method: "PUT",
        token: cal.token,
        body: {
          assignments: calsOthers.map((card_no) => ({ card_no, guessed_user_id: ana.id })),
        },
      })).status,
      200,
      "Cal completes their sheet before the reminder is drained",
    );

    await clearPending(guessReminderEnqueued[0].id);
    const guessDrain = stubApns(() => ({ status: 200 }));
    await drainPushOutbox(serviceClient(), guessDrain.fetchApns);
    assertEquals(
      guessDrain.tokens,
      [tokens.ana],
      "Cal is skipped (resolved before claim); Ana, still incomplete, is sent",
    );
  },
);

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
  // What each outbox row's audience should be — no fixed daily ceiling as of E31-01, but still
  // exactly the coalesced, conditional set a kind's own rule computes — is proven at the enqueue
  // layer by `tests/db/notification_budget.sql`. This is the other half: what the outbox holds
  // is what the phone gets, exactly once per registered device, no more and no less.
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

// ─── E35-06 · seal_reminder carries the cue when single-circle, never when grouped ──
// docs/18-CUES.md §11.1. `claim_notification_outbox` returns `cue_text` only for a
// single-circle seal_reminder claim; the worker relays it into the body verbatim. The four
// cases the checklist names are covered here end-to-end through the real claim + drain path.

Deno.test("a single-circle seal_reminder carries the round's cue on both firings — E35-06", async () => {
  await clearPending();
  const { user } = await newGroupOwner("Cue Solo", {
    name: `Cue Solo ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 20,
    cue_cadence: 1,
  });
  const current = await call("rounds", "/current", { token: user.token });
  const roundId = current.body.data.round_id as string;
  const cueText = current.body.data.cue.text as string;
  assert(typeof cueText === "string" && cueText.length > 0, "cadence 1 pins a cue on the round");
  const revealsAt = Date.parse(current.body.data.reveals_at as string);
  const deviceToken = await registerDevice(user.token);

  // Tick at fixed offsets from the round's own reveal, not from the wall clock: the two firing
  // windows are only 90 and 30 minutes wide, so an offset from `now` can drift past reveal when
  // the current minute-of-hour is high (the same time-of-minute boundary the pre-existing
  // E31-01 test can hit).
  await rpc("tick_rounds_at", { p_at: new Date(revealsAt - 1.5 * 3_600_000).toISOString() });
  const [firstFiring] = await sealReminderRows(roundId);
  assert(firstFiring?.id, "the 2h firing is enqueued");
  await clearPending(firstFiring.id);
  const first = captureApns();
  await drainPushOutbox(serviceClient(), first.fetchApns);
  assertEquals(first.requests.map(addressedToken), [deviceToken]);
  assertEquals(
    (await first.requests[0].json()).aps.alert.body,
    `You haven't sealed a song yet. Two hours left. Tonight: ${cueText}`,
  );

  await rpc("tick_rounds_at", { p_at: new Date(revealsAt - 60_000).toISOString() });
  const [, secondFiring] = await sealReminderRows(roundId);
  assert(secondFiring?.id, "the 30m firing is enqueued");
  await clearPending(secondFiring.id);
  const second = captureApns();
  await drainPushOutbox(serviceClient(), second.fetchApns);
  assertEquals(
    (await second.requests[0].json()).aps.alert.body,
    `Half an hour left, and you haven't sealed a song. Tonight: ${cueText}`,
  );
});

Deno.test("a single-circle seal_reminder with no cue keeps the generic body — E35-06", async () => {
  await clearPending();
  const { user } = await newGroupOwner("Cue Off Solo", {
    name: `Cue Off Solo ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 20,
    cue_cadence: 0,
  });
  const current = await call("rounds", "/current", { token: user.token });
  const roundId = current.body.data.round_id as string;
  assertEquals(current.body.data.cue, undefined, "cue_cadence 0 ships no cue key");
  const deviceToken = await registerDevice(user.token);

  await tickRoundsAt(1.5);
  const [firstFiring] = await sealReminderRows(roundId);
  assert(firstFiring?.id, "the firing is enqueued");
  await clearPending(firstFiring.id);
  const { requests, fetchApns } = captureApns();
  await drainPushOutbox(serviceClient(), fetchApns);
  assertEquals(requests.map(addressedToken), [deviceToken]);
  assertEquals(
    (await requests[0].json()).aps.alert.body,
    "You haven't sealed a song yet. Two hours left.",
  );
});

/** A member shared by two coincident circles, plus both rounds and the member's device. */
async function coincidentCirclesWithSharedMember(
  label: string,
  cadence: 0 | 1,
): Promise<{
  roundAId: string;
  roundBId: string;
  sam: { id: string; token: string };
  samDevice: string;
}> {
  const zone = zoneWhereLocalHourIs(17);
  const { user: ana, group: groupA } = await newGroupOwner(`${label} Ana`, {
    name: `${label} A ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zone,
    reveal_hour: 20,
    cue_cadence: cadence,
  });
  const { user: bob, group: groupB } = await newGroupOwner(`${label} Bob`, {
    name: `${label} B ${crypto.randomUUID().slice(0, 8)}`,
    timezone: zone,
    reveal_hour: 20,
    cue_cadence: cadence,
  });
  const sam = await newMember(groupA.invite_code as string, `${label} Sam`);
  assertEquals(
    (await call("groups", "/join", {
      method: "POST",
      token: sam.token,
      body: { invite_code: groupB.invite_code },
    })).status,
    200,
  );
  const roundAId =
    (await call("rounds", "/current", { token: ana.token })).body.data.round_id as string;
  const roundBId =
    (await call("rounds", "/current", { token: bob.token })).body.data.round_id as string;
  const samDevice = await registerDevice(sam.token);
  return { roundAId, roundBId, sam, samDevice };
}

Deno.test("a grouped seal_reminder never names one circle's cue — E35-06", async () => {
  await clearPending();
  const { roundAId, roundBId, sam, samDevice } = await coincidentCirclesWithSharedMember(
    "Cue Pair",
    1,
  );

  await tickRoundsAt(1.5);
  const rowsA = await sealReminderRows(roundAId);
  const rowsB = await sealReminderRows(roundBId);
  assertEquals([rowsA.length, rowsB.length], [1, 1], "each circle enqueues one firing");
  const samRow = [...rowsA, ...rowsB].find((r) => r.audience.includes(sam.id));
  assert(samRow, "Sam is coalesced into exactly one of the two circles' rows");
  const otherRow = [...rowsA, ...rowsB].find((r) => r.id !== samRow.id);
  assertEquals(
    otherRow!.audience.includes(sam.id),
    false,
    "the coalesce keeps Sam out of the other circle's row",
  );

  await clearPending(samRow.id);
  const { requests, fetchApns } = captureApns();
  await drainPushOutbox(serviceClient(), fetchApns);
  const samRequests = requests.filter((r) => addressedToken(r) === samDevice);
  assertEquals(samRequests.length, 1, "Sam gets exactly one reminder");
  assertEquals(
    (await samRequests[0].json()).aps.alert.body,
    "You haven't sealed a song yet. Two hours left.",
    "a grouped delivery never picks one circle's cue",
  );
});

Deno.test("a grouped seal_reminder with no cues keeps the generic body — E35-06", async () => {
  await clearPending();
  const { roundAId, roundBId, sam, samDevice } = await coincidentCirclesWithSharedMember(
    "NoCue Pair",
    0,
  );

  await tickRoundsAt(1.5);
  const rows = [...(await sealReminderRows(roundAId)), ...(await sealReminderRows(roundBId))];
  const samRow = rows.find((r) => r.audience.includes(sam.id));
  assert(samRow, "Sam is coalesced into one row");

  await clearPending(samRow.id);
  const { requests, fetchApns } = captureApns();
  await drainPushOutbox(serviceClient(), fetchApns);
  const samRequests = requests.filter((r) => addressedToken(r) === samDevice);
  assertEquals(samRequests.length, 1, "Sam gets exactly one reminder");
  assertEquals(
    (await samRequests[0].json()).aps.alert.body,
    "You haven't sealed a song yet. Two hours left.",
  );
});
