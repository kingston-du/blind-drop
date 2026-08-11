// me.test.ts — tasks/E02-02. docs/04 §2, docs/14 §7.
//
// Black box: every assertion here is made against the bytes a device would receive.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, isRfc3339Z, keysOf, newGroupOwner, newUser, newNamedUser } from "./_harness.ts";

const me = (path: string, opts: Parameters<typeof call>[2] = {}) => call("me", path, opts);

Deno.test("GET /me is 401 for an anonymous caller, in our envelope", async () => {
  const res = await me("/");
  assertEquals(res.status, 401);
  assertEquals(keysOf(res.body), ["error", "server_now"]);
  assertEquals(res.body.error.code, "UNAUTHENTICATED");
  assert(isRfc3339Z(res.body.server_now));
});

Deno.test("GET /me is 409 NO_PROFILE until a name is set", async () => {
  const user = await newUser();
  const res = await me("/", { token: user.token });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_PROFILE");
});

Deno.test("PUT then GET /me returns exactly {user_id, display_name, has_group}", async () => {
  const user = await newUser();

  const put = await me("/", { method: "PUT", token: user.token, body: { display_name: "Ana" } });
  assertEquals(put.status, 200);
  assertEquals(keysOf(put.body.data), ["display_name", "has_group", "user_id"]);
  assertEquals(put.body.data, { user_id: user.id, display_name: "Ana", has_group: false });

  const get = await me("/", { token: user.token });
  assertEquals(get.status, 200);
  assertEquals(get.body.data, { user_id: user.id, display_name: "Ana", has_group: false });
});

Deno.test("PUT /me trims, collapses whitespace, and enforces 1–24 characters", async () => {
  const user = await newUser();

  const trimmed = await me("/", {
    method: "PUT",
    token: user.token,
    body: { display_name: "  Ana   Lucia  " },
  });
  assertEquals(trimmed.body.data.display_name, "Ana Lucia");

  for (const bad of ["", "   ", "x".repeat(25), "🎧".repeat(25)]) {
    const res = await me("/", { method: "PUT", token: user.token, body: { display_name: bad } });
    assertEquals(res.status, 400, `expected 400 for ${JSON.stringify(bad)}`);
    assertEquals(res.body.error.code, "INVALID_INPUT");
    assertEquals(res.body.error.details, { field: "display_name" });
  }

  // Twenty-four characters is twenty-four characters, emoji included.
  const long = await me("/", { method: "PUT", token: user.token, body: { display_name: "🎧".repeat(24) } });
  assertEquals(long.status, 200);
  assertEquals(long.body.data.display_name, "🎧".repeat(24));
});

Deno.test("PUT /me strips control, zero-width and RTL-override characters — docs/14 §7", async () => {
  const user = await newUser();

  const cases: [string, string][] = [
    ["Ana\u202EBen", "AnaBen"],   // right-to-left override: would reorder the guess sheet
    ["Ana\u200BBen", "AnaBen"],   // zero width space: two visually identical names
    ["Ana\u200D\u2066Ben", "AnaBen"], // joiner and isolate
    ["An\u0000a", "Ana"],         // NUL
    // docs/14 §7 says newlines are *stripped*, not turned into spaces: the name is one
    // line by construction, and gluing the words is the honest result of pasting two.
    ["Ana\nBen", "AnaBen"],
    ["Ana\tBen", "AnaBen"],
    ["Ana\u00ADBen", "AnaBen"],   // soft hyphen
    ["\uFEFFAna", "Ana"],         // byte order mark
  ];

  for (const [sent, stored] of cases) {
    const res = await me("/", { method: "PUT", token: user.token, body: { display_name: sent } });
    assertEquals(res.status, 200, `${JSON.stringify(sent)} should be accepted once cleaned`);
    assertEquals(res.body.data.display_name, stored, JSON.stringify(sent));
  }

  // A name that is *only* invisible characters cleans down to nothing and is refused rather
  // than stored as an empty name.
  const empty = await me("/", {
    method: "PUT",
    token: user.token,
    body: { display_name: "\u200B\u200B\u202E" },
  });
  assertEquals(empty.status, 400);
  assertEquals(empty.body.error.code, "INVALID_INPUT");
});

Deno.test("PUT /me rejects an unknown key rather than ignoring it", async () => {
  const user = await newUser();
  const res = await me("/", {
    method: "PUT",
    token: user.token,
    body: { display_name: "Ana", is_admin: true },
  });
  assertEquals(res.status, 400);
  assertEquals(res.body.error.code, "INVALID_INPUT");
  assertEquals(res.body.error.details, { field: "is_admin" });
});

Deno.test("PUT /me is a change, not just a create", async () => {
  const user = await newNamedUser("Ana");
  const renamed = await me("/", { method: "PUT", token: user.token, body: { display_name: "Ana L" } });
  assertEquals(renamed.body.data.display_name, "Ana L");
  assertEquals((await me("/", { token: user.token })).body.data.display_name, "Ana L");
});

Deno.test("two people in one group may share a display name", async () => {
  // Two Sams is a real situation; the guess sheet disambiguates (docs/04 §2).
  const first = await newNamedUser("Sam");
  const second = await newNamedUser("Sam");
  assertEquals((await me("/", { token: first.token })).body.data.display_name, "Sam");
  assertEquals((await me("/", { token: second.token })).body.data.display_name, "Sam");
  assert(first.id !== second.id);
});

Deno.test("DELETE /me removes authentication and invalidates a live token", async () => {
  const { user } = await newGroupOwner("Delete Me");

  const deleted = await me("/", { method: "DELETE", token: user.token });
  assertEquals(deleted.status, 204);
  assertEquals(deleted.body, null);

  // requireUser verifies through GoTrue on every request. The same signed, unexpired token
  // is now useless because its auth.users principal no longer exists.
  const after = await me("/", { token: user.token });
  assertEquals(after.status, 401);
  assertEquals(after.body.error.code, "UNAUTHENTICATED");
});

Deno.test("DELETE /me is available before a profile exists and rejects options", async () => {
  const withProfile = await newNamedUser("Delete Strictly");
  const unknown = await me("/", {
    method: "DELETE",
    token: withProfile.token,
    body: { keep_history: false },
  });
  assertEquals(unknown.status, 400);
  assertEquals(unknown.body.error.details, { field: "keep_history" });

  const beforeProfile = await newUser();
  assertEquals((await me("/", { method: "DELETE", token: beforeProfile.token })).status, 204);
  assertEquals((await me("/", { token: beforeProfile.token })).status, 401);
});

Deno.test("an unrouted path or method on /me is a plain 404", async () => {
  const user = await newNamedUser("Ana");
  for (const [method, path] of [["GET", "/nope"], ["DELETE", "/nope"], ["POST", "/"]]) {
    const res = await me(path, { method, token: user.token });
    assertEquals(res.status, 404, `${method} ${path}`);
    assertEquals(res.body.error.code, "NOT_FOUND");
  }
});
