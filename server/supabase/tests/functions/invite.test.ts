// invite.test.ts — invite codes: the alphabet, the distribution, and the two limits that are
// what actually stop a brute force. tasks/E02-04, docs/03 §2, docs/04 §8, docs/14 §8.
//
// The space is 31^6 ≈ 8.9e8. That number is not the defence — 10 guesses per hour per user and
// 30 per hour per IP are. These tests assert the counters, because the counters are the control.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { call, newGroupOwner, newNamedUser, randomTestIp, type TestUser } from "./_harness.ts";
import {
  generateInviteCode,
  INVITE_ALPHABET,
  INVITE_LENGTH,
  normaliseInviteCode,
} from "../../functions/_shared/invite.ts";

const groups = (path: string, opts: Parameters<typeof call>[2] = {}) => call("groups", path, opts);

/** A join attempt, with the caller's apparent IP pinned so the test controls both buckets. */
function join(user: TestUser, code: string, ip: string) {
  return groups("/join", {
    method: "POST",
    token: user.token,
    body: { invite_code: code },
    headers: { "x-forwarded-for": ip },
  });
}

// ─── the alphabet and the distribution ───────────────────────────────────────

Deno.test("10k generated codes contain no excluded character and no duplicate", () => {
  const excluded = new Set(["I", "L", "O", "0", "1"]);
  const seen = new Set<string>();
  const frequency = new Map<string, number>();

  for (let i = 0; i < 10_000; i += 1) {
    const code = generateInviteCode();
    assertEquals(code.length, INVITE_LENGTH, `wrong length: ${code}`);
    for (const char of code) {
      assert(!excluded.has(char), `excluded character ${char} in ${code}`);
      assert(INVITE_ALPHABET.includes(char), `character ${char} is outside the alphabet: ${code}`);
      frequency.set(char, (frequency.get(char) ?? 0) + 1);
    }
    assert(!seen.has(code), `duplicate code ${code} at iteration ${i}`);
    seen.add(code);
  }
  assertEquals(seen.size, 10_000);

  // Every character actually occurs. The generator discards bytes >= 248 rather than folding
  // them with `% 31`, which would have made the first nine letters ~3% likelier; 60k samples
  // over 31 characters is ~1935 each, so a modulo bias would show up as a visible skew here.
  assertEquals(frequency.size, INVITE_ALPHABET.length, "some character never appeared");
  const counts = [...frequency.values()];
  const expected = (10_000 * INVITE_LENGTH) / INVITE_ALPHABET.length;
  for (const [char, count] of frequency) {
    assert(
      Math.abs(count - expected) < expected * 0.2,
      `${char} appeared ${count} times, expected about ${Math.round(expected)}`,
    );
  }
  assert(Math.max(...counts) - Math.min(...counts) < expected * 0.3, "distribution is skewed");
});

Deno.test("normalisation accepts what a person types and rejects what is not a code", () => {
  assertEquals(normaliseInviteCode("k7mq2x"), "K7MQ2X");
  assertEquals(normaliseInviteCode("  K7 MQ 2X "), "K7MQ2X");
  // Excluded characters are not silently mapped onto their look-alikes: `0` is not `O`.
  assertEquals(normaliseInviteCode("K7MQ2O"), null);
  assertEquals(normaliseInviteCode("K7MQ20"), null);
  assertEquals(normaliseInviteCode("ABC"), null);
  assertEquals(normaliseInviteCode(""), null);
});

Deno.test("every created group gets a distinct code from the alphabet", async () => {
  const pattern = new RegExp(`^[${INVITE_ALPHABET}]{${INVITE_LENGTH}}$`);
  const codes = new Set<string>();
  for (let i = 0; i < 12; i += 1) {
    const { group } = await newGroupOwner("Ana");
    const code = String(group.invite_code);
    assert(pattern.test(code), `${code} is not a well-formed invite code`);
    assert(!codes.has(code), `two groups were issued the same code: ${code}`);
    codes.add(code);
  }
  assertEquals(codes.size, 12);
});

// ─── the identical NOT_FOUND ─────────────────────────────────────────────────

Deno.test("a bad code and a valid-but-unusable code are byte-identical, and cost the same", async () => {
  // A real group exists; its code is never offered to the joiner below.
  await newGroupOwner("Ana");
  const joiner = await newNamedUser("Ben");
  const ip = randomTestIp();

  const malformed = await join(joiner, "I1LO0!", ip); // excluded characters
  const tooShort = await join(joiner, "ABC", ip);
  const wellFormedUnknown = await join(joiner, "K7MQ2Z", ip); // shaped right, does not exist

  for (const res of [malformed, tooShort, wellFormedUnknown]) {
    assertEquals(res.status, 404);
    assertEquals(JSON.stringify(res.body.error), JSON.stringify(wellFormedUnknown.body.error));
  }
  // No field anywhere in the envelope distinguishes them — not a `field`, not a hint.
  assertEquals(
    JSON.stringify(Object.keys(malformed.body.error).sort()),
    JSON.stringify(Object.keys(wellFormedUnknown.body.error).sort()),
  );

  // And the quota is charged identically. If a malformed code were rejected before the limiter,
  // an attacker could probe shape for free and learn which codes are worth spending a guess on.
  // Three attempts have been made above, so seven remain of the ten.
  for (let i = 0; i < 7; i += 1) {
    assertEquals(
      (await join(joiner, "K7MQ2Z", ip)).status,
      404,
      `attempt ${i + 4} should be a 404`,
    );
  }
  const eleventh = await join(joiner, "K7MQ2Z", ip);
  assertEquals(eleventh.status, 429, "the malformed attempts must have been charged too");
});

// ─── the limits ──────────────────────────────────────────────────────────────

Deno.test("POST /groups/join is limited to 10 an hour per user, with Retry-After", async () => {
  const joiner = await newNamedUser("Ben");

  // A distinct IP per call, so this test measures the per-user bucket alone.
  for (let attempt = 1; attempt <= 10; attempt += 1) {
    const res = await join(joiner, "K7MQ2Z", randomTestIp());
    assertEquals(res.status, 404, `attempt ${attempt} should still be admitted`);
  }

  const limited = await join(joiner, "K7MQ2Z", randomTestIp());
  assertEquals(limited.status, 429);
  assertEquals(limited.body.error.code, "RATE_LIMITED");

  const retryAfter = Number(limited.headers.get("retry-after"));
  assert(Number.isInteger(retryAfter) && retryAfter > 0, `Retry-After was ${retryAfter}`);
  assert(retryAfter <= 3600, `Retry-After ${retryAfter} exceeds the one-hour window`);

  // The limit is per user, not per group and not global: a different person is unaffected.
  const other = await newNamedUser("Cal");
  assertEquals((await join(other, "K7MQ2Z", randomTestIp())).status, 404);
});

Deno.test("POST /groups/join is additionally limited to 30 an hour per IP", async () => {
  const sharedIp = randomTestIp();

  // Four people behind one address, eight guesses each. Nobody reaches their own limit of ten,
  // so a 429 here can only be the per-IP counter — which is the point of it existing: an
  // attacker cannot buy more guesses by signing up more users.
  let admitted = 0;
  let limitedAt = 0;
  outer:
  for (let person = 0; person < 4; person += 1) {
    const user = await newNamedUser(`Attacker ${person}`);
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const res = await join(user, "K7MQ2Z", sharedIp);
      if (res.status === 429) {
        assertEquals(res.body.error.code, "RATE_LIMITED");
        limitedAt = admitted + 1;
        break outer;
      }
      assertEquals(res.status, 404);
      admitted += 1;
    }
  }

  assertEquals(admitted, 30, "the per-IP counter should admit exactly thirty");
  assertEquals(limitedAt, 31, "the thirty-first attempt from one address should be refused");

  // The bucket really is keyed by the address we sent, not by the machine's own: a fresh person
  // on a fresh address still gets through. If `x-forwarded-for` were being ignored, this call
  // would share the exhausted bucket and be refused.
  const elsewhere = await newNamedUser("Dee");
  assertEquals((await join(elsewhere, "K7MQ2Z", randomTestIp())).status, 404);
});

Deno.test("the per-IP counter is not keyed by group — one member cannot sense another", async () => {
  // docs/04 §8: "Rate-limit counters are per-user and never per-group." A group-scoped counter
  // would let one member detect another member's activity by watching for throttling, which is
  // a side channel on the blind window. Two members of the same group, each with their own
  // quota, both admitted.
  const { user: ana, group } = await newGroupOwner("Ana");
  const code = String(group.invite_code);
  const ben = await newNamedUser("Ben");

  // Ben's first join succeeds; the next nine are ALREADY_IN_GROUP. All ten are charged, because
  // the limiter runs before the membership insert — so a refused join costs a guess exactly as
  // an accepted one does.
  assertEquals((await join(ben, code, randomTestIp())).status, 200);
  for (let i = 0; i < 9; i += 1) {
    assertEquals((await join(ben, code, randomTestIp())).status, 409, `attempt ${i + 2}`);
  }
  const benLimited = await join(ben, code, randomTestIp());
  assertEquals(benLimited.status, 429, "Ben has spent his own ten");

  // Ana, in the same group, is untouched by Ben having exhausted his quota. If the bucket were
  // group-scoped, Ana would be throttled here and could infer that someone else had been busy.
  assertNotEquals(ana.token, ben.token);
  assertEquals((await join(ana, code, randomTestIp())).status, 409);
});
