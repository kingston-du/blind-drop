// apns.test.ts — provider authentication and approved notification copy. tasks/E06-01.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { apnsToken, notificationAlert, resetApnsToken } from "../../functions/_shared/apns.ts";

const encoder = new TextEncoder();

function base64urlBytes(segment: string): Uint8Array<ArrayBuffer> {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - padded.length % 4) % 4));
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeSegment(segment: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(base64urlBytes(segment)));
}

function privateKeyPem(pkcs8: ArrayBuffer): string {
  const bytes = new Uint8Array(pkcs8);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const lines = btoa(binary).match(/.{1,64}/g) ?? [];
  // Exercise the exact Supabase-secret representation: escaped, not literal, newlines.
  return ["-----BEGIN PRIVATE KEY-----", ...lines, "-----END PRIVATE KEY-----"].join("\\n");
}

const pair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
Deno.env.set("APNS_KEY_ID", "TESTKEY123");
Deno.env.set("APNS_TEAM_ID", "TESTTEAM12");
Deno.env.set(
  "APNS_PRIVATE_KEY",
  privateKeyPem(await crypto.subtle.exportKey("pkcs8", pair.privateKey)),
);

Deno.test("the APNs JWT is ES256 and verifies against its .p8 public key", async () => {
  resetApnsToken();
  const at = new Date("2026-08-11T18:00:00Z");
  const token = await apnsToken(at);
  const [header, claims, signature] = token.split(".");

  assertEquals(decodeSegment(header), { alg: "ES256", kid: "TESTKEY123" });
  assertEquals(decodeSegment(claims), {
    iss: "TESTTEAM12",
    iat: Math.floor(at.getTime() / 1000),
  });
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      base64urlBytes(signature),
      encoder.encode(`${header}.${claims}`),
    ),
    "the provider token signature does not verify against the generated public key",
  );
});

Deno.test("the APNs JWT is reused until the fifty-minute refresh boundary", async () => {
  resetApnsToken();
  const at = new Date("2026-08-11T18:00:00Z");
  const first = await apnsToken(at);
  assertEquals(await apnsToken(new Date(at.getTime() + 49 * 60_000 + 59_000)), first);

  const refreshed = await apnsToken(new Date(at.getTime() + 50 * 60_000));
  assert(refreshed !== first, "the token was still cached at its refresh boundary");
});

Deno.test("a cold concurrent batch signs one APNs JWT", async () => {
  resetApnsToken();
  const at = new Date("2026-08-11T18:00:00Z");
  const tokens = await Promise.all(Array.from({ length: 16 }, () => apnsToken(at)));
  assertEquals(new Set(tokens).size, 1);
});

Deno.test("the four APNs alerts are the approved copy, verbatim", () => {
  assertEquals(notificationAlert("nudge"), { title: "Blind Drop", body: "Two hours to drop." });
  assertEquals(notificationAlert("reveal"), {
    title: "Blind Drop",
    body: "Tonight's drop is open.",
  });
  assertEquals(notificationAlert("results"), { title: "Blind Drop", body: "Answers are in." });
  assertEquals(notificationAlert("void"), {
    title: "Blind Drop",
    body: "Not enough drops tonight. Nothing revealed.",
  });
});
