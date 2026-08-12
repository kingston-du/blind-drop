#!/usr/bin/env node
// audit:leak — the AC-1 group. tasks/E04-04, docs/15 §1, docs/14 §10.
//
// docs/15 §1 calls this "the single most important command in this repo": it asserts, against
// raw API responses, that nothing about anyone else's participation is obtainable during a
// round's `open` phase. It gates release (E14-05), and the summary it prints at the end is
// meant to be pasted straight into the release checklist.
//
// Four suites, each answering a different question, and all four have to pass:
//
//   leak              Does any open-phase response carry a key nobody reviewed?
//   leak_timing       Does response *time* carry the count the payload does not?
//   postgrest_locked  Can a real member's token read the tables directly, or reach
//                     another group's data by any path?
//   rounds            Does the payload's *length* move when other people submit?
//
// The last one lives in the behaviour suite rather than here because it is also an ordinary
// correctness property; `audit:leak` runs it anyway, because AC-1 is not satisfied without it
// and a release gate that trusts another command to have been run is not a gate.
//
//   npm run audit:leak            run the gate
//   GOLDEN=update npm run test:functions -- leak     re-capture the golden files, deliberately

import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ensureFreshEdgeRuntime, waitForEdgeRuntime } from "./edge-runtime.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const testDir = join(root, "supabase", "tests", "functions");
const goldenDir = join(root, "supabase", "tests", "golden");
const denoConfig = join(root, "supabase", "deno.json");

const red = (s) => `\x1b[31m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

/** Each suite, with the AC-1 clause it is here to discharge. The wording is what gets printed,
 *  so it says what was proved rather than which file ran. */
const SUITES = [
  {
    file: "leak.test.ts",
    claims: [
      "`GET /rounds/current` during `open` has exactly {round_id, local_date, state, opens_at, reveals_at, scores_at, my_submission}",
      "the same key set for a non-submitter, and for `voided`",
      "every route in functions/ has a reviewed golden file",
      "`WRONG_PHASE` bodies carry the state and nothing else",
    ],
  },
  {
    file: "rounds.test.ts",
    claims: [
      "response byte-length invariant across 0/1/5/11 other submitters",
      "a submitter's and a non-submitter's payloads differ only in `my_submission`",
      "a duplicate track is never rejected and the response gives no hint of one",
    ],
  },
  {
    file: "leak_timing.test.ts",
    claims: ["response latency uncorrelated (|r| < 0.2) with submitter count, over 100+ samples"],
  },
  {
    file: "postgrest_locked.test.ts",
    claims: [
      "authenticated and anonymous PostgREST selects on every audited table fail with 42501",
      "no lifecycle RPC is callable by anon or by a member",
      "every Edge Function returns 401 in our envelope to an anonymous caller",
      "no route takes a client-supplied resource id; a cross-group probe 404s",
      "an ex-member's still-valid token gets NO_GROUP",
    ],
  },
];

// ─── preconditions ───────────────────────────────────────────────────────────

const missing = SUITES.map((s) => s.file).filter((f) => !existsSync(join(testDir, f)));
if (missing.length) {
  console.log(red(bold("LEAK AUDIT CANNOT RUN")));
  console.log(`\n  Missing suite(s): ${missing.join(", ")}`);
  console.log("  This command proves nothing without them. See tasks/E04-03, E04-04.\n");
  process.exit(1);
}

if (!existsSync(goldenDir) || !existsSync(join(goldenDir, "round_open.json"))) {
  console.log(red(bold("LEAK AUDIT CANNOT RUN")));
  console.log("\n  No golden files. Capture them, read the diff, and commit them:");
  console.log("      GOLDEN=update npm run test:functions -- leak\n");
  process.exit(1);
}

if (process.env.GOLDEN === "update") {
  // Otherwise the gate would rewrite the very files it is supposed to be checking against and
  // pass unconditionally. This is the one environment variable that must not reach it.
  console.log(red(bold("REFUSING TO RUN WITH GOLDEN=update")));
  console.log("\n  The audit compares against the golden files; it never writes them.\n");
  process.exit(1);
}

const bin = (name) => {
  const local = join(root, "node_modules", ".bin", name);
  return spawnSync(name, ["--version"], { stdio: "ignore" }).status === 0 ? name : local;
};

// The same resolution `test-functions.mjs` does: an environment value wins, so CI and a
// hosted stack can point the audit somewhere other than the local one. That matters here more
// than anywhere else — E14-05 runs this against the release candidate, not against a laptop.
const needed = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_JWT_SECRET"];
if (needed.some((k) => !process.env[k])) {
  const status = spawnSync(bin("supabase"), ["status", "-o", "json"], { cwd: root, encoding: "utf8" });
  const at = String(status.stdout).indexOf("{");
  let s;
  try {
    s = JSON.parse(String(status.stdout).slice(at));
  } catch {
    console.log(red(bold("LEAK AUDIT CANNOT RUN")));
    console.log("\n  The Supabase stack is not running, and none of");
    console.log(`  ${needed.join(", ")} is set.`);
    console.log("  Start it with:  npm run db:start\n");
    process.exit(1);
  }
  process.env.SUPABASE_URL ??= s.API_URL;
  process.env.SUPABASE_ANON_KEY ??= s.ANON_KEY;
  process.env.SUPABASE_SERVICE_ROLE_KEY ??= s.SERVICE_ROLE_KEY;
  process.env.SUPABASE_JWT_SECRET ??= s.JWT_SECRET;
}

// ─── run ─────────────────────────────────────────────────────────────────────

// The gate must judge the code on disk, not whatever modules the runtime happens to still
// hold. This is not a convenience here the way it is in `test-functions.mjs` — a release gate
// that can pass against a stale worker is worse than no gate, because it is believed.
if (ensureFreshEdgeRuntime(root)) {
  await waitForEdgeRuntime(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
}

console.log(bold("\nLEAK AUDIT — AC-1\n"));
console.log(dim("  docs/15 §1: no endpoint may reveal another user's participation during `open`.\n"));

const results = [];
for (const suite of SUITES) {
  process.stdout.write(dim(`  running ${suite.file}…\n`));
  const run = spawnSync(
    bin("deno"),
    ["test", "--config", denoConfig, "--allow-net", "--allow-env", "--allow-read",
     join(testDir, suite.file)],
    { cwd: root, encoding: "utf8" },
  );
  const passed = run.status === 0;
  results.push({ ...suite, passed, output: `${run.stdout ?? ""}${run.stderr ?? ""}` });
  if (!passed) {
    console.log(run.stdout ?? "");
    console.log(run.stderr ?? "");
  }
}

// ─── the one-page summary ────────────────────────────────────────────────────

const failed = results.filter((r) => !r.passed);

console.log(`\n${bold("─".repeat(78))}`);
console.log(bold("  BLIND DROP · LEAK AUDIT · AC-1"));
console.log(`  ${dim(new Date().toISOString())}`);
console.log(bold("─".repeat(78)));

for (const result of results) {
  const mark = result.passed ? green("PASS") : red("FAIL");
  console.log(`\n  ${mark}  ${bold(result.file)}`);
  for (const claim of result.claims) {
    console.log(`        ${result.passed ? green("·") : red("·")} ${claim}`);
  }
}

// The timing suite prints its own measurement; surface it in the summary rather than making
// somebody scroll for the number that matters.
const timing = results.find((r) => r.file === "leak_timing.test.ts");
const correlation = timing?.output.match(/Pearson r = (-?[\d.]+) over (\d+) samples/);
if (correlation) {
  console.log(`\n  ${dim(`timing channel: r = ${correlation[1]} over ${correlation[2]} samples`)}`);
}

console.log(`\n${bold("─".repeat(78))}`);
if (failed.length === 0) {
  console.log(`  ${green(bold("AC-1 SATISFIED"))} — ${results.length} suites, all green.`);
  console.log(bold("─".repeat(78)));
  console.log("");
  process.exit(0);
}

console.log(`  ${red(bold("AC-1 NOT SATISFIED"))} — ${failed.length} of ${results.length} suites failed.`);
console.log(`  ${red("Do not release.")} Failing: ${failed.map((f) => f.file).join(", ")}`);
console.log(bold("─".repeat(78)));
console.log("");
process.exit(1);
