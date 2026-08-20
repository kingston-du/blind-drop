// push-worker/worker.ts — claim, deliver, then mark the APNs outbox. tasks/E06-02, E06-04.
//
// The three outcomes of a send, from docs/05 §6, are not three shades of the same thing:
//
//   410 Unregistered  the token is gone. Disable it, never retry it, and do not fail the row.
//   429 / 5xx         Apple is busy or broken. Leave `sent_at` null and let the next minute try.
//   attempts = 5      it is not going to work. Record `last_error` and stop; a human looks.

import { apnsToken, notificationAlert, type NotificationKind } from "../_shared/apns.ts";
import { type Db, dbFailure } from "../_shared/db.ts";
import { fixtureFlagEnabled } from "../_shared/localStack.ts";

export const PUSH_CONCURRENCY = 16;
const OUTBOX_BATCH = 20;
const APNS_TIMEOUT_MS = 18_000;
const RESULTS_LIFETIME_MS = 12 * 60 * 60 * 1_000;

/**
 * How many times a row is attempted before it stops (docs/05 §6).
 *
 * The guard that actually enforces this is `attempts < 5` inside `claim_notification_outbox`
 * (20260811201246), because a ceiling that lives only in the worker is a ceiling a second
 * worker does not have. This constant exists so the last attempt can be logged as the last
 * one, and so the test that proves the ceiling names the same number the SQL does.
 */
export const PUSH_MAX_ATTEMPTS = 5;

export interface ClaimedNotification {
  id: string;
  /** Present for scheduled round notifications; direct invitations have no round. */
  round_id: string | null;
  /** Present only for the recipient-specific `invite` kind. */
  invitation_id: string | null;
  kind: NotificationKind;
  audience: string[];
  attempts: number;
  reveals_at: string | null;
  scores_at: string | null;
  invitation_expires_at: string | null;
}

export interface PushDevice {
  id: string;
  user_id: string;
  apns_token: string;
  environment: "sandbox" | "production";
}

interface ApnsResponse {
  readonly ok: boolean;
  readonly status: number;
  text(): Promise<string>;
}

export type ApnsFetch = (request: Request) => Promise<ApnsResponse>;

export interface PushDrainResult {
  claimed: number;
  sent: number;
  failed: number;
  devices: number;
  /** Tokens Apple answered `410 Unregistered` for, now switched off (docs/05 §6). */
  disabled: number;
}

function requiredSecret(name: "APNS_TOPIC"): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set; APNs notifications cannot be sent`);
  return value;
}

function parseInstant(value: string, field: string): Date {
  const instant = new Date(value);
  if (!Number.isFinite(instant.getTime())) {
    throw new Error(`invalid ${field} on claimed outbox row`);
  }
  return instant;
}

export function notificationDeepLink(row: ClaimedNotification): string {
  if (row.kind === "invite") {
    if (!row.invitation_id) throw new Error("invite outbox row has no invitation id");
    return `blinddrop://invite/${row.invitation_id}`;
  }
  return row.kind === "results" ? "blinddrop://round/current/results" : "blinddrop://round/current";
}

/** The APNs expiration is the end of the phase the alert describes. */
export function notificationExpiration(row: ClaimedNotification): number {
  if (row.kind === "invite") {
    return Math.floor(parseInstant(row.invitation_expires_at ?? "", "invitation_expires_at").getTime() / 1_000);
  }
  if (row.kind === "nudge") {
    return Math.floor(parseInstant(row.reveals_at ?? "", "reveals_at").getTime() / 1_000);
  }
  const scoresAt = parseInstant(row.scores_at ?? "", "scores_at").getTime();
  const expiresAt = row.kind === "results" ? scoresAt + RESULTS_LIFETIME_MS : scoresAt;
  return Math.floor(expiresAt / 1_000);
}

function notificationCollapseID(row: ClaimedNotification): string {
  if (row.kind === "invite") {
    if (!row.invitation_id) throw new Error("invite outbox row has no invitation id");
    return `invite:${row.invitation_id}`;
  }
  if (!row.round_id) throw new Error("round notification outbox row has no round id");
  return `${row.round_id}:${row.kind}`;
}

/** Builds the exact request sent to Apple. Kept pure so headers and payload are testable. */
export function apnsRequest(
  row: ClaimedNotification,
  device: PushDevice,
  providerToken: string,
  topic: string,
  signal?: AbortSignal,
): Request {
  const host = device.environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const deepLink = notificationDeepLink(row);

  return new Request(`${host}/3/device/${encodeURIComponent(device.apns_token)}`, {
    method: "POST",
    signal,
    headers: {
      authorization: `bearer ${providerToken}`,
      "content-type": "application/json",
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": notificationCollapseID(row),
      "apns-expiration": String(notificationExpiration(row)),
    },
    body: JSON.stringify({
      aps: {
        alert: notificationAlert(row.kind),
        sound: "default",
        "interruption-level": "active",
      },
      kind: row.kind,
      ...(row.round_id === null ? {} : { round_id: row.round_id }),
      deep_link: deepLink,
    }),
  });
}

class ApnsSendError extends Error {
  constructor(readonly status: number, readonly reason: string) {
    super(`APNs rejected a notification (${status}${reason ? `: ${reason}` : ""})`);
    this.name = "ApnsSendError";
  }

  /** A short, token-free summary for `notification_outbox.last_error`. */
  get summary(): string {
    return `${this.status}${this.reason ? ` ${this.reason}` : ""}`;
  }
}

/**
 * `410 Unregistered`: the app is off this device for good — deleted, or restored onto another
 * phone. It is the one APNs failure that is not a failure of the *notification*, so it neither
 * fails the row nor is ever retried; the token is switched off instead (docs/05 §6). A device
 * that comes back registers again, and `POST /devices` clears `disabled_at` (E06-03).
 */
const UNREGISTERED = 410;

type SendOutcome = "sent" | "unregistered";

async function sendNotification(
  row: ClaimedNotification,
  device: PushDevice,
  fetchApns: ApnsFetch,
): Promise<SendOutcome> {
  const [providerToken, topic] = await Promise.all([apnsToken(), requiredSecret("APNS_TOPIC")]);
  const request = apnsRequest(
    row,
    device,
    providerToken,
    topic,
    AbortSignal.timeout(APNS_TIMEOUT_MS),
  );

  let response: ApnsResponse;
  try {
    response = await fetchApns(request);
  } catch {
    // Fetch exceptions can include the URL, and the APNs URL contains the device token.
    throw new Error("APNs network request failed");
  }
  if (response.ok) return "sent";
  if (response.status === UNREGISTERED) {
    await response.text().catch(() => "");
    return "unregistered";
  }

  let reason = "";
  try {
    const body = JSON.parse(await response.text()) as { reason?: unknown };
    if (typeof body.reason === "string") reason = body.reason;
  } catch {
    // Apple normally returns `{ reason }`; an unreadable error body is still a failed send.
  }
  throw new ApnsSendError(response.status, reason);
}

/** A small worker pool. The callback is never in flight more than `limit` times. */
export async function mapConcurrent<T>(
  values: readonly T[],
  limit: number,
  operation: (value: T) => Promise<void>,
): Promise<void> {
  if (!Number.isInteger(limit) || limit < 1) throw new Error("concurrency must be positive");
  let next = 0;
  const worker = async () => {
    while (next < values.length) {
      const index = next;
      next += 1;
      await operation(values[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, values.length) }, worker));
}

function audience(value: unknown): string[] {
  if (!Array.isArray(value) || !value.every((item) => typeof item === "string")) {
    throw new Error("invalid audience on claimed outbox row");
  }
  return [...new Set(value)];
}

async function claim(db: Db, claimId: string): Promise<ClaimedNotification[]> {
  const { data, error } = await db.rpc("claim_notification_outbox", {
    p_claim_id: claimId,
    p_limit: OUTBOX_BATCH,
  });
  if (error) throw dbFailure("claim_notification_outbox", error);
  return (data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id),
    round_id: typeof row.round_id === "string" ? row.round_id : null,
    invitation_id: typeof row.invitation_id === "string" ? row.invitation_id : null,
    kind: row.kind as NotificationKind,
    audience: audience(row.audience),
    attempts: Number(row.attempts),
    reveals_at: typeof row.reveals_at === "string" ? row.reveals_at : null,
    scores_at: typeof row.scores_at === "string" ? row.scores_at : null,
    invitation_expires_at: typeof row.invitation_expires_at === "string"
      ? row.invitation_expires_at
      : null,
  }));
}

async function activeDevices(db: Db, rows: ClaimedNotification[]): Promise<PushDevice[]> {
  const userIds = [...new Set(rows.flatMap((row) => row.audience))];
  if (userIds.length === 0) return [];
  const { data, error } = await db
    .from("devices")
    .select("id, user_id, apns_token, environment")
    .in("user_id", userIds)
    .is("disabled_at", null);
  if (error) throw dbFailure("push active devices", error);
  return (data ?? []) as PushDevice[];
}

async function finish(db: Db, outboxId: string, claimId: string): Promise<boolean> {
  const { data, error } = await db.rpc("finish_notification_outbox", {
    p_id: outboxId,
    p_claim_id: claimId,
  });
  if (error) throw dbFailure("finish_notification_outbox", error);
  return data === true;
}

async function release(
  db: Db,
  outboxId: string,
  claimId: string,
  lastError: string,
): Promise<void> {
  const { error } = await db.rpc("release_notification_outbox", {
    p_id: outboxId,
    p_claim_id: claimId,
    p_error: lastError,
  });
  if (error) throw dbFailure("release_notification_outbox", error);
}

/** Switches off tokens Apple has told us are gone. One statement, whatever the batch size. */
async function disableDevices(db: Db, deviceIds: readonly string[]): Promise<void> {
  if (deviceIds.length === 0) return;
  const { error } = await db
    .from("devices")
    .update({ disabled_at: new Date().toISOString() })
    .in("id", [...deviceIds]);
  if (error) throw dbFailure("push disable devices", error);
}

const productionFetch: ApnsFetch = async (request) => await fetch(request);
const fixtureFetch: ApnsFetch = async (_request) => ({
  ok: true,
  status: 200,
  text: async () => "",
});

/** The fixture is the local stack's APNs. On a deployed project the flag is ignored however it
 *  got there (`_shared/localStack.ts`) — a swallowed push looks exactly like a delivered one, so
 *  this switch failing open would be silent and permanent. */
function configuredFetch(): ApnsFetch {
  return fixtureFlagEnabled("APNS_FIXTURES") ? fixtureFetch : productionFetch;
}

/** Claims a bounded batch, sends every device at concurrency 16, then marks each row. */
export async function drainPushOutbox(
  db: Db,
  fetchApns: ApnsFetch = configuredFetch(),
): Promise<PushDrainResult> {
  const claimId = crypto.randomUUID();
  const rows = await claim(db, claimId);
  if (rows.length === 0) return { claimed: 0, sent: 0, failed: 0, devices: 0, disabled: 0 };

  const devices = await activeDevices(db, rows);
  const byUser = new Map<string, PushDevice[]>();
  for (const device of devices) {
    const list = byUser.get(device.user_id) ?? [];
    list.push(device);
    byUser.set(device.user_id, list);
  }

  const deliveries = rows.flatMap((row) =>
    row.audience.flatMap((userId) => (byUser.get(userId) ?? []).map((device) => ({ row, device })))
  );
  // The *first* error per row, not the last: with sixteen sends in flight the last one to
  // land is whichever happened to be slowest, and the first failure is the one that describes
  // what went wrong. Devices Apple has disowned are collected here and switched off once,
  // after the fan-out, so a 410 storm is one statement rather than one per device.
  const failures = new Map<string, string>();
  const unregistered = new Set<string>();

  await mapConcurrent(deliveries, PUSH_CONCURRENCY, async ({ row, device }) => {
    try {
      if (await sendNotification(row, device, fetchApns) === "unregistered") {
        unregistered.add(device.id);
      }
    } catch (error) {
      const summary = error instanceof ApnsSendError ? error.summary : "network failure";
      if (!failures.has(row.id)) failures.set(row.id, summary);
      console.error(`APNs send failed for outbox ${row.id}: ${summary}`);
    }
  });

  await disableDevices(db, [...unregistered]);

  let sent = 0;
  for (const row of rows) {
    const failure = failures.get(row.id);
    if (failure !== undefined) {
      // Left unsent with `sent_at` still null, so the next minute picks it up — until the
      // fifth attempt, after which `claim_notification_outbox` stops offering it and this
      // `last_error` is what a human finds (docs/05 §6).
      if (row.attempts >= PUSH_MAX_ATTEMPTS) {
        console.error(
          `outbox ${row.id} has failed ${row.attempts} times and will not be retried: ${failure}`,
        );
      }
      await release(db, row.id, claimId, failure);
      continue;
    }
    // A row every one of whose devices answered 410 has nothing left to deliver to and is
    // done, not failed: retrying it would produce the same 410 four more times.
    if (await finish(db, row.id, claimId)) sent += 1;
  }

  return {
    claimed: rows.length,
    sent,
    failed: failures.size,
    devices: deliveries.length,
    disabled: unregistered.size,
  };
}
