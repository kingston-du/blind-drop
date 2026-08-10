#!/usr/bin/env node
// Deno test runner for the Edge Functions — docs/15 §3.
//
// Deno is a devDependency (`npm i` installs it) so CI needs no separate setup step; a Deno
// already on PATH wins.

import { existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const testDir = join(root, "supabase", "tests", "functions");

const found = existsSync(testDir)
  ? readdirSync(testDir).filter((f) => f.endsWith(".test.ts"))
  : [];

if (!found.length) {
  console.log("No Edge Function tests yet (server/supabase/tests/functions/*.test.ts).");
  console.log("These arrive with E02. Nothing to run.");
  process.exit(0);
}

const deno =
  spawnSync("deno", ["--version"], { stdio: "ignore" }).status === 0
    ? "deno"
    : join(root, "node_modules", ".bin", "deno");

const r = spawnSync(
  deno,
  ["test", "--allow-net", "--allow-env", "--allow-read", testDir],
  { stdio: "inherit", cwd: root },
);
process.exit(r.status ?? 1);
