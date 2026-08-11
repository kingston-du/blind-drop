#!/usr/bin/env node
// Deno test runner for the Edge Functions — docs/15 §3.
//
//   npm run test:functions              every tests/functions/*.test.ts
//   npm run test:functions -- groups    only files whose name contains "groups"
//
// The tests are black-box: they speak HTTP to the functions the local stack is already
// serving, with real access tokens, so what they exercise is what a device would get. That
// means the stack has to be up (`npm run db:start`); the runner says so rather than failing
// with a connection error.
//
// Deno is a devDependency (`npm i` installs it) so CI needs no separate setup step; a Deno
// already on PATH wins.

import { existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const testDir = join(root, "supabase", "tests", "functions");
const functionsDir = join(root, "supabase", "functions");
// Deno would otherwise pick up server/package.json and switch to node_modules resolution,
// which the Edge Functions never use — they resolve `npm:` specifiers from Deno's own cache,
// exactly as the deployed runtime does.
const denoConfig = join(root, "supabase", "deno.json");

const red = (s) => `\x1b[31m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

const bin = (name) => {
  const local = join(root, "node_modules", ".bin", name);
  return spawnSync(name, ["--version"], { stdio: "ignore" }).status === 0 ? name : local;
};
const deno = bin("deno");

// ─── which tests ─────────────────────────────────────────────────────────────
const filters = process.argv.slice(2);
let files = existsSync(testDir)
  ? readdirSync(testDir).filter((f) => f.endsWith(".test.ts")).sort()
  : [];

if (!files.length) {
  console.log("No Edge Function tests yet (server/supabase/tests/functions/*.test.ts).");
  process.exit(0);
}
if (filters.length) {
  files = files.filter((f) => filters.some((needle) => f.includes(needle)));
  if (!files.length) {
    console.error(red(`No test file matches ${filters.join(", ")}`));
    process.exit(1);
  }
}

// ─── the stack's URL and keys, without putting keys in the repo ──────────────
// `supabase status` prints them; a value already in the environment wins, which is how CI
// and a hosted stack point the same suite somewhere else.
const needed = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_JWT_SECRET"];
if (needed.some((k) => !process.env[k])) {
  const status = spawnSync(bin("supabase"), ["status", "-o", "json"], {
    cwd: root,
    encoding: "utf8",
  });
  const at = String(status.stdout).indexOf("{");
  let s;
  try {
    s = JSON.parse(String(status.stdout).slice(at));
  } catch {
    console.error(red("The local Supabase stack is not running."));
    console.error("  Start it with:  npm run db:start");
    process.exit(1);
  }
  process.env.SUPABASE_URL ??= s.API_URL;
  process.env.SUPABASE_ANON_KEY ??= s.ANON_KEY;
  process.env.SUPABASE_SERVICE_ROLE_KEY ??= s.SERVICE_ROLE_KEY;
  // Used only by the test harness, to mint access tokens without going through a sign-in
  // that GoTrue rate-limits per IP. No function reads it.
  process.env.SUPABASE_JWT_SECRET ??= s.JWT_SECRET;
}

// ─── type-check the functions themselves ─────────────────────────────────────
// A handler that does not compile is a failing test, and `deno test` would never load it.
const entrypoints = readdirSync(functionsDir)
  .filter((d) => !d.startsWith("_"))
  .map((d) => join(functionsDir, d, "index.ts"))
  .filter((f) => existsSync(f));

if (entrypoints.length) {
  console.log(dim(`Type-checking ${entrypoints.length} function entrypoint(s)…`));
  const check = spawnSync(deno, ["check", "--config", denoConfig, ...entrypoints], {
    stdio: "inherit",
    cwd: root,
  });
  if (check.status !== 0) {
    console.error(red("Type check failed."));
    process.exit(check.status ?? 1);
  }
}

// ─── run ─────────────────────────────────────────────────────────────────────
const run = spawnSync(
  deno,
  ["test", "--config", denoConfig, "--allow-net", "--allow-env", "--allow-read",
   ...files.map((f) => join(testDir, f))],
  { stdio: "inherit", cwd: root },
);
process.exit(run.status ?? 1);
