// push-worker/worker.ts — claim, deliver, then mark the APNs outbox. tasks/E06-02.

import { apnsToken, notificationAlert, type NotificationKind } from "../_shared/apns.ts";
import { type Db, dbFailure } from "../_shared/db.ts";

export const PUSH_CONCURRENCY = 16;
const OUTBOX_BATCH = 20;
const APNS_TIMEOUT_MS = 18_000;
const RESULTS_LIFETIME_MS = 12 * 60 * 60 * 1_000;

export interface ClaimedNotification {
  id: string;
  round_id: string;
  kind: NotificationKind;
  audience: string[];
  attempts: number;
  reveals_at: string;
  scores_at: string;
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

export function notificationDeepLink(kind: NotificationKind): string {
  return kind === "results" ? "blinddrop://round/current/results" : "blinddrop://round/current";
}

/** The APNs expiration is the end of the phase the alert describes. */
export function notificationExpiration(row: ClaimedNotification): number {
  if (row.kind === "nudge") {
    return Math.floor(parseInstant(row.reveals_at, "reveals_at").getTime() / 1_000);
  }
  const scoresAt = parseInstant(row.scores_at, "scores_at").getTime();
  const expiresAt = row.kind === "results" ? scoresAt + RESULTS_LIFETIME_MS : scoresAt;
  return Math.floor(expiresAt / 1_000);
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
  const deepLink = notificationDeepLink(row.kind);

  return new Request(`${host}/3/device/${encodeURIComponent(device.apns_token)}`, {
    method: "POST",
    signal,
    headers: {
      authorization: `bearer ${providerToken}`,
      "content-type": "application/json",
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": `${row.round_id}:${row.kind}`,
      "apns-expiration": String(notificationExpiration(row)),
    },
    body: JSON.stringify({
      aps: {
        alert: notificationAlert(row.kind),
        sound: "default",
        "interruption-level": "active",
      },
      kind: row.kind,
      round_id: row.round_id,
      deep_link: deepLink,
    }),
  });
}

class ApnsSendError extends Error {
  constructor(readonly status: number, readonly reason: string) {
    super(`APNs rejected a notification (${status}${reason ? `: ${reason}` : ""})`);
    this.name = "ApnsSendError";
  }
}

async function sendNotification(
  row: ClaimedNotification,
  device: PushDevice,
  fetchApns: ApnsFetch,
): Promise<void> {
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
  if (response.ok) return;

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
    round_id: String(row.round_id),
    kind: row.kind as NotificationKind,
    audience: audience(row.audience),
    attempts: Number(row.attempts),
    reveals_at: String(row.reveals_at),
    scores_at: String(row.scores_at),
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

async function release(db: Db, outboxId: string, claimId: string): Promise<void> {
  const { error } = await db.rpc("release_notification_outbox", {
    p_id: outboxId,
    p_claim_id: claimId,
  });
  if (error) throw dbFailure("release_notification_outbox", error);
}

const productionFetch: ApnsFetch = async (request) => await fetch(request);
const fixtureFetch: ApnsFetch = async (_request) => ({
  ok: true,
  status: 200,
  text: async () => "",
});

function configuredFetch(): ApnsFetch {
  return Deno.env.get("APNS_FIXTURES") === "on" ? fixtureFetch : productionFetch;
}

/** Claims a bounded batch, sends every device at concurrency 16, then marks each row. */
export async function drainPushOutbox(
  db: Db,
  fetchApns: ApnsFetch = configuredFetch(),
): Promise<PushDrainResult> {
  const claimId = crypto.randomUUID();
  const rows = await claim(db, claimId);
  if (rows.length === 0) return { claimed: 0, sent: 0, failed: 0, devices: 0 };

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
  const failed = new Set<string>();

  await mapConcurrent(deliveries, PUSH_CONCURRENCY, async ({ row, device }) => {
    try {
      await sendNotification(row, device, fetchApns);
    } catch (error) {
      failed.add(row.id);
      const summary = error instanceof ApnsSendError
        ? `${error.status}${error.reason ? ` ${error.reason}` : ""}`
        : "network failure";
      console.error(`APNs send failed for outbox ${row.id}: ${summary}`);
    }
  });

  let sent = 0;
  for (const row of rows) {
    if (failed.has(row.id)) {
      await release(db, row.id, claimId);
      continue;
    }
    if (await finish(db, row.id, claimId)) sent += 1;
  }

  return { claimed: rows.length, sent, failed: failed.size, devices: deliveries.length };
}
