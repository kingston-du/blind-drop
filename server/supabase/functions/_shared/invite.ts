// _shared/invite.ts — invite codes. docs/03 §2, docs/14 §8.
//
// Six characters, read aloud across a lunch table and typed by a sixteen-year-old. The
// alphabet excludes I, L, O, 0 and 1 for that reason, which leaves 31 characters and
// 31^6 ≈ 8.9e8 codes, as approved in docs/03 §2 and docs/14 §8. Brute force is not stopped by
// the size of that space anyway — it is stopped by
// the 10/hour and 30/hour limits in docs/04 §8.

export const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const INVITE_LENGTH = 6;

const INVITE_PATTERN = new RegExp(`^[${INVITE_ALPHABET}]{${INVITE_LENGTH}}$`);

/**
 * A fresh code from `crypto.getRandomValues`, never `Math.random` (docs/14 §8;
 * `scripts/lint.mjs` fails the build on `Math.random` anywhere in a function).
 *
 * Bytes at or above `31 * 8 = 248` are discarded rather than folded, because `byte % 31`
 * would make the first nine letters of the alphabet slightly likelier than the rest. The
 * rejection rate is 8/256, so a six-character code costs seven bytes on average.
 */
export function generateInviteCode(): string {
  let code = "";
  const buffer = new Uint8Array(INVITE_LENGTH * 2);
  while (code.length < INVITE_LENGTH) {
    crypto.getRandomValues(buffer);
    for (const byte of buffer) {
      if (byte >= 248) continue;
      code += INVITE_ALPHABET[byte % INVITE_ALPHABET.length];
      if (code.length === INVITE_LENGTH) break;
    }
  }
  return code;
}

/**
 * A typed-in code, as the database stores it — uppercased, with every space removed, so
 * `"k7 mq 2x"` and `"K7MQ2X"` are the same code (docs/04 §3: case-insensitive, whitespace
 * stripped).
 *
 * Returns `null` when the result is not a code at all. The caller answers that with the same
 * `NOT_FOUND` a well-formed-but-unknown code gets: telling someone their code is *shaped*
 * right is the beginning of an enumeration oracle (docs/14 §8).
 */
export function normaliseInviteCode(raw: string): string | null {
  const candidate = raw.replace(/\s+/gu, "").toUpperCase();
  return INVITE_PATTERN.test(candidate) ? candidate : null;
}
