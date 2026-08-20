// _shared/apns.ts — APNs authentication and the five permitted alerts. docs/05 §2, §4.
// tasks/E06-01.
//
// This module signs only the provider JWT and owns the product-approved alert copy. Sending,
// collapse ids, expiry, retry policy, and device retirement belong to push-worker (E06-02/04).

import { jwtSegment, signEs256 } from "./es256.ts";

const TOKEN_REFRESH_SECONDS = 50 * 60;

interface CachedToken {
  jwt: string;
  issuedAt: number;
  staleAt: number;
}

let cached: CachedToken | null = null;
let signing: Promise<string> | null = null;

function secret(name: "APNS_KEY_ID" | "APNS_TEAM_ID" | "APNS_PRIVATE_KEY"): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set; APNs authentication cannot be signed`);
  return value;
}

/**
 * Apple's short-lived provider JWT, cached for fifty minutes in the worker module.
 *
 * Apple expires a token at sixty minutes and rejects deliberately regenerating one more often
 * than every twenty. Fifty minutes leaves ten minutes of safety. `signing` also coalesces a
 * cold worker's concurrent callers: a sixteen-device batch must not manufacture sixteen keys
 * before the first promise has had time to fill the cache.
 */
export async function apnsToken(now: Date = new Date()): Promise<string> {
  const issuedAt = Math.floor(now.getTime() / 1000);
  if (cached && issuedAt >= cached.issuedAt && issuedAt < cached.staleAt) return cached.jwt;
  if (signing) return await signing;

  signing = (async () => {
    const header = jwtSegment({ alg: "ES256", kid: secret("APNS_KEY_ID") });
    const claims = jwtSegment({ iss: secret("APNS_TEAM_ID"), iat: issuedAt });
    const input = `${header}.${claims}`;
    const signature = await signEs256(input, secret("APNS_PRIVATE_KEY"));
    const jwt = `${input}.${signature}`;
    cached = { jwt, issuedAt, staleAt: issuedAt + TOKEN_REFRESH_SECONDS };
    return jwt;
  })();

  try {
    return await signing;
  } finally {
    signing = null;
  }
}

/** Tests only: simulate a fresh worker module. */
export function resetApnsToken(): void {
  cached = null;
  signing = null;
}

export type NotificationKind = "invite" | "nudge" | "reveal" | "results" | "void";

const BODIES: Readonly<Record<NotificationKind, string>> = {
  invite: "You have a group invite.",
  nudge: "Two hours to drop.",
  reveal: "Tonight's drop is open.",
  results: "Answers are in.",
  void: "Not enough drops tonight. Nothing revealed.",
};

/** The only five notification alerts the product permits. */
export function notificationAlert(kind: NotificationKind): { title: "Blind Drop"; body: string } {
  return { title: "Blind Drop", body: BODIES[kind] };
}
