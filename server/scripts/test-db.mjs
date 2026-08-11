#!/usr/bin/env node
// pgTAP runner — docs/15 §3, tasks/E01-05.
//
//   npm run test:db              every tests/db/*.sql
//   npm run test:db -- schema    only files whose name contains "schema"
//
// Each test file is self-contained: begin; plan(n); …; select * from finish(); rollback;
// so the database is never left dirty and tests can run in any order.
//
// Time travel is `public.now_()` + `set_test_now()`. There is no pg_sleep anywhere in the
// suite and this script fails the run if one appears.

import { readdirSync, readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const testDir = join(root, "supabase", "tests", "db");
const helpers = join(testDir, "_helpers.sql");

const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54422/postgres";

const filters = process.argv.slice(2);
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

// ── psql, on the host or inside the local db container ───────────────────────
const container = "supabase_db_blind-drop";
function psqlRunner() {
  if (spawnSync("psql", ["--version"], { stdio: "ignore" }).status === 0) {
    return (sql) =>
      spawnSync("psql", ["-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=0", DB_URL], {
        input: sql,
        encoding: "utf8",
      });
  }
  if (spawnSync("docker", ["inspect", container], { stdio: "ignore" }).status === 0) {
    return (sql) =>
      spawnSync(
        "docker",
        ["exec", "-i", container, "psql", "-X", "-q", "-t", "-A",
         "-v", "ON_ERROR_STOP=0", "-U", "postgres", "-d", "postgres"],
        { input: sql, encoding: "utf8" },
      );
  }
  console.error(red("No psql on PATH and no local Supabase db container."));
  console.error("  Start the stack with:  npm run db:start");
  console.error(`  Or point SUPABASE_DB_URL at a database (currently ${DB_URL}).`);
  process.exit(1);
}
const psql = psqlRunner();

// ── preflight ────────────────────────────────────────────────────────────────
const ping = psql("select 1;");
if (ping.status !== 0 || !String(ping.stdout).includes("1")) {
  console.error(red("Cannot reach the database."));
  console.error(String(ping.stderr || ping.stdout).trim());
  console.error("\n  Start it with:  npm run db:start");
  process.exit(1);
}

// pgTAP lives in the test database only — never in a migration (tasks/E01-05).
const ext = psql("create extension if not exists pgtap with schema extensions;");
if (ext.status !== 0) {
  console.error(red("Could not install the pgtap extension."));
  console.error(String(ext.stderr).trim());
  process.exit(1);
}

if (!existsSync(testDir)) {
  console.log("No tests/db directory yet — nothing to run.");
  process.exit(0);
}

let files = readdirSync(testDir)
  .filter((f) => f.endsWith(".sql") && !f.startsWith("_"))
  .sort();

// ── the no-pg_sleep rule (tasks/E01-05) ──────────────────────────────────────
const stripComments = (sql) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/--[^\n]*/g, " ");
const sleepers = readdirSync(testDir)
  .filter((f) => f.endsWith(".sql"))
  .filter((f) => /\bpg_sleep\b/i.test(stripComments(readFileSync(join(testDir, f), "utf8"))));
if (sleepers.length) {
  console.error(red("pg_sleep found in the test suite. Move the clock with set_test_now()."));
  for (const f of sleepers) console.error(`  tests/db/${f}`);
  process.exit(1);
}

if (filters.length) {
  files = files.filter((f) => filters.some((needle) => f.includes(needle)));
  if (!files.length) {
    console.error(red(`No test file matches ${filters.join(", ")}`));
    process.exit(1);
  }
}
if (!files.length) {
  console.log("No pgTAP test files yet — nothing to run.");
  process.exit(0);
}

// ── helpers are applied once, outside any test transaction ───────────────────
if (existsSync(helpers)) {
  const r = psql(readFileSync(helpers, "utf8"));
  if (r.status !== 0 || /ERROR:/.test(String(r.stderr))) {
    console.error(red("tests/db/_helpers.sql failed to load."));
    console.error(String(r.stderr).trim());
    process.exit(1);
  }
}

// ── run ──────────────────────────────────────────────────────────────────────
let failed = 0;
let total = 0;

for (const file of files) {
  const label = basename(file);
  const r = psql(readFileSync(join(testDir, file), "utf8"));
  const out = String(r.stdout).split("\n").map((l) => l.trimEnd()).filter(Boolean);
  const err = String(r.stderr).trim();

  const bad = out.filter((l) => l.startsWith("not ok"));
  const good = out.filter((l) => /^ok \d+/.test(l));
  // pgTAP reports an invalid plan as a diagnostic while psql still exits zero. Treating
  // that as green would let an accidentally deleted assertion silently reduce coverage.
  const planProblems = out.filter((l) => l.startsWith("# Looks like you planned"));
  total += good.length + bad.length;

  console.log(`\n${dim("──")} ${label}`);
  for (const line of out) {
    if (line.startsWith("not ok")) console.log(red(line));
    else if (line.startsWith("#")) console.log(dim(line));
    else console.log(line);
  }
  if (err) {
    console.log(red(err));
    if (/ERROR:/.test(err)) failed += 1;
  }
  failed += bad.length;
  failed += planProblems.length;
}

console.log("");
if (failed) {
  console.log(red(`${failed} failing assertion${failed === 1 ? "" : "s"} of ${total}.`));
  process.exit(1);
}
console.log(green(`${total} assertions passed across ${files.length} file${files.length === 1 ? "" : "s"}.`));
