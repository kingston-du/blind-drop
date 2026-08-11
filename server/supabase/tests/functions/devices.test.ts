// devices.test.ts — APNs registration. tasks/E06-03. docs/04 §2, docs/05 §4.
//
// Black box over HTTP, with one exception: the endpoint answers 204 and has no read side, so
// the only way to see what it stored is to look at the row as the service role does. That
// asymmetry is the point of the endpoint — see the header of `functions/devices/index.ts`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  API_URL,
  call,
  isRfc3339Z,
  keysOf,
  newNamedUser,
  newUser,
  SERVICE_KEY,
} from "./_harness.ts";

const devices = (opts: Parameters<typeof call>[2] = {}) => call("devices", "/", opts);

/** A fresh 64-character hex token, in the shape Apple hands the app. */
function newToken(): string {
  return Array.from(
    crypto.getRandomValues(new Uint8Array(32)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

interface DeviceRow {
  id: string;
  user_id: string;
  apns_token: string;
  environment: string;
  created_at: string;
  last_seen_at: string;
  disabled_at: string | null;
}

async function rowsFor(token: string): Promise<DeviceRow[]> {
  const columns = "id,user_id,apns_token,environment,created_at,last_seen_at,disabled_at";
  const response = await fetch(
    `${API_URL}/rest/v1/devices?select=${columns}&apns_token=eq.${token}`,
    { headers: { apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}` } },
  );
  const text = await response.text();
  if (!response.ok) throw new Error(`reading devices: ${response.status} ${text}`);
  return JSON.parse(text) as DeviceRow[];
}

async function disable(token: string): Promise<void> {
  const response = await fetch(`${API_URL}/rest/v1/devices?apns_token=eq.${token}`, {
    method: "PATCH",
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
      prefer: "return=minimal",
    },
    body: JSON.stringify({ disabled_at: new Date().toISOString() }),
  });
  if (!response.ok) throw new Error(`disabling a device: ${response.status}`);
  await response.body?.cancel();
}

Deno.test("POST /devices is 401 for an anonymous caller, in our envelope", async () => {
  const res = await devices({
    method: "POST",
    body: { apns_token: newToken(), environment: "sandbox" },
  });
  assertEquals(res.status, 401);
  assertEquals(keysOf(res.body), ["error", "server_now"]);
  assertEquals(res.body.error.code, "UNAUTHENTICATED");
  assert(isRfc3339Z(res.body.server_now));
});

Deno.test("POST /devices is 409 NO_PROFILE before onboarding finishes", async () => {
  const user = await newUser();
  const res = await devices({
    method: "POST",
    token: user.token,
    body: { apns_token: newToken(), environment: "sandbox" },
  });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_PROFILE");
});

Deno.test("POST /devices is 204 with no body, and stores the token lowercased", async () => {
  const user = await newNamedUser("Reg");
  const token = newToken();

  const res = await devices({
    method: "POST",
    token: user.token,
    body: { apns_token: token.toUpperCase(), environment: "sandbox" },
  });
  assertEquals(res.status, 204);
  assertEquals(res.body, null);

  // Hex is case-insensitive; two spellings of one token would be two rows and two copies of
  // every push to one phone.
  assertEquals((await rowsFor(token.toUpperCase())).length, 0);
  const rows = await rowsFor(token);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].user_id, user.id);
  assertEquals(rows[0].environment, "sandbox");
  assertEquals(rows[0].disabled_at, null);
});

Deno.test("re-registering is one row, a bumped last_seen_at, and a cleared disabled_at", async () => {
  const user = await newNamedUser("Relaunch");
  const token = newToken();
  const first = { method: "POST", token: user.token, body: { apns_token: token, environment: "sandbox" } };
  assertEquals((await devices(first)).status, 204);
  const before = (await rowsFor(token))[0];

  // Apple said this token is gone; the app then presents it again on the next launch, which
  // is the direct evidence that it is not (docs/05 §4).
  await disable(token);
  assert((await rowsFor(token))[0].disabled_at !== null);

  await new Promise((resolve) => setTimeout(resolve, 20));
  assertEquals((await devices(first)).status, 204);

  const after = (await rowsFor(token));
  assertEquals(after.length, 1, "the launch upsert must not add a second row");
  assertEquals(after[0].id, before.id);
  assertEquals(after[0].created_at, before.created_at, "created_at is not touched by an upsert");
  assertEquals(after[0].disabled_at, null);
  assert(
    Date.parse(after[0].last_seen_at) > Date.parse(before.last_seen_at),
    "last_seen_at is bumped on every registration",
  );
});

Deno.test("a token registered by a second user moves ownership — a shared device", async () => {
  const first = await newNamedUser("Lender");
  const second = await newNamedUser("Borrower");
  const token = newToken();

  assertEquals(
    (await devices({
      method: "POST",
      token: first.token,
      body: { apns_token: token, environment: "production" },
    })).status,
    204,
  );
  assertEquals(
    (await devices({
      method: "POST",
      token: second.token,
      body: { apns_token: token, environment: "sandbox" },
    })).status,
    204,
  );

  // One token, one owner: the phone in someone's hand is the phone the push goes to, and the
  // previous owner stops receiving that device's notifications.
  const rows = await rowsFor(token);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].user_id, second.id);
  assertEquals(rows[0].environment, "sandbox");
});

Deno.test("POST /devices validates the token, the environment, and the key set", async () => {
  const user = await newNamedUser("Picky");
  const token = newToken();

  const cases: [string, Record<string, unknown>][] = [
    ["apns_token", { apns_token: "abc123", environment: "sandbox" }],
    ["apns_token", { apns_token: `${token.slice(0, 63)}z`, environment: "sandbox" }],
    ["apns_token", { apns_token: `${token}${token}${token}${token}`, environment: "sandbox" }],
    ["apns_token", { environment: "sandbox" }],
    ["apns_token", { apns_token: 42, environment: "sandbox" }],
    ["environment", { apns_token: token, environment: "SANDBOX" }],
    ["environment", { apns_token: token, environment: "development" }],
    ["environment", { apns_token: token }],
    // docs/05 §4: there are no notification settings. A preference field is not ignored, it
    // is refused — an ignored key is how a setting arrives without anyone deciding to add one.
    ["quiet_hours", { apns_token: token, environment: "sandbox", quiet_hours: true }],
    ["enabled", { apns_token: token, environment: "sandbox", enabled: false }],
    ["user_id", { apns_token: token, environment: "sandbox", user_id: user.id }],
  ];

  for (const [field, body] of cases) {
    const res = await devices({ method: "POST", token: user.token, body });
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals(res.body.error.code, "INVALID_INPUT");
    assertEquals(res.body.error.details, { field }, JSON.stringify(body));
  }

  assertEquals((await rowsFor(token)).length, 0, "no rejected body may have stored a row");
});

Deno.test("/devices has no read side and no other route", async () => {
  const user = await newNamedUser("Nosy");
  for (
    const [method, path] of [
      ["GET", "/"],
      ["DELETE", "/"],
      ["PUT", "/"],
      ["POST", "/current"],
    ]
  ) {
    const res = await call("devices", path, { method, token: user.token });
    assertEquals(res.status, 404, `${method} ${path}`);
    assertEquals(res.body.error.code, "NOT_FOUND");
  }
});
