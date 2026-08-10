#!/usr/bin/env node
// audit:leak — the AC-1 group. docs/15 §1 calls this "the single most important command in
// this repo": it asserts, against raw API responses, that nothing about anyone else's
// participation is obtainable during a round's `open` phase.
//
// It is built out across E04-03 / E04-04 (golden files + the diff) and E14-01 (full pass).
// Until those land this script has nothing to compare, and it says so rather than printing
// a green tick it has not earned.

import { existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const goldenDir = join(root, "supabase", "tests", "functions");

const leakTests = existsSync(goldenDir)
  ? readdirSync(goldenDir).filter((f) => /^leak.*\.test\.ts$/.test(f))
  : [];

if (!leakTests.length) {
  console.log("\x1b[33mLEAK AUDIT NOT YET ARMED\x1b[0m");
  console.log("");
  console.log("  No leak tests exist yet. This command currently proves nothing.");
  console.log("  It becomes real in E04-03 (golden files) and E04-04 (the diff), and");
  console.log("  gates release in E14-01. See docs/15 §1 AC-1.");
  console.log("");
  console.log("  What it will assert:");
  console.log("    · GET /rounds/current during `open` has exactly the key set");
  console.log("      {round_id, local_date, state, opens_at, reveals_at, scores_at, my_submission}");
  console.log("    · the same for a non-submitter, and for `voided`");
  console.log("    · response byte-length invariant across 0/1/5/11 other submitters");
  console.log("    · response latency uncorrelated (|r| < 0.2) with submitter count");
  console.log("    · an authenticated PostgREST select on each of the 9 tables returns no row");
  process.exit(0);
}

const deno =
  spawnSync("deno", ["--version"], { stdio: "ignore" }).status === 0
    ? "deno"
    : join(root, "node_modules", ".bin", "deno");

const r = spawnSync(
  deno,
  ["test", "--allow-net", "--allow-env", "--allow-read",
   ...leakTests.map((f) => join(goldenDir, f))],
  { stdio: "inherit", cwd: root },
);
process.exit(r.status ?? 1);
