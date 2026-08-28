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

// E31-01, docs/05 §3: `nudge` is retired — replaced by two conditional reminders,
// `seal_reminder` (up to twice a round) and `guess_reminder` (once). The enum label `nudge`
// stays in the database (Postgres has no `ALTER TYPE ... DROP VALUE`) but no code path produces
// it anymore, so it is deliberately absent from this type and from `BODIES` below.
export type NotificationKind =
  | "invite"
  | "seal_reminder"
  | "guess_reminder"
  | "reveal"
  | "results"
  | "void";

const BODIES: Readonly<Record<Exclude<NotificationKind, "seal_reminder">, string>> = {
  invite: "You have a group invite.",
  guess_reminder: "Half an hour left to guess who dropped what.",
  reveal: "Tonight's songs are out.",
  results: "Tonight's answers are in.",
  void: "Not enough drops tonight. Nothing revealed.",
};

/**
 * `seal_reminder` fires twice a round (`reveals_at − 2h`, then `reveals_at − 30m`) and each
 * firing gets its own body — `firing` distinguishes them. Every other kind ignores `firing`.
 */
const SEAL_REMINDER_BODIES = {
  first: "You haven't sealed a song yet. Two hours left.",
  second: "Half an hour left, and you haven't sealed a song.",
} as const;

export type SealReminderFiring = keyof typeof SEAL_REMINDER_BODIES;

/**
 * The only six notification alerts the product permits (docs/11 §"Notifications").
 *
 * `cueText` is the round's frozen cue (E35-06, docs/18-CUES.md §11.1). When a single-circle
 * `seal_reminder` fires for a round that has one, the cue rides as a `" Tonight: <cue>"` suffix
 * on whichever firing's base sentence applies. A grouped (multi-circle) delivery, and any round
 * with no cue, passes no cue text and keeps the base body unchanged — the same body as before.
 */
export function notificationAlert(
  kind: NotificationKind,
  sealReminderFiring: SealReminderFiring = "first",
  cueText?: string,
): { title: "Blind Drop"; body: string } {
  if (kind === "seal_reminder") {
    const base = SEAL_REMINDER_BODIES[sealReminderFiring];
    const body = cueText && cueText.trim().length > 0 ? `${base} Tonight: ${cueText}` : base;
    return { title: "Blind Drop", body };
  }
  return { title: "Blind Drop", body: BODIES[kind] };
}
