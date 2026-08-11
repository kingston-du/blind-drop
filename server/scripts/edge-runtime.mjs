// scripts/edge-runtime.mjs — make the local edge runtime serve the code that is on disk.
//
// The Supabase edge runtime caches modules per worker. A change to a *function's* entrypoint
// is picked up; a change to anything under `_shared/` frequently is not, and a new function
// directory never is — the runtime is handed its function list when its container is created.
//
// That is a nuisance in development and a genuine hazard for `audit:leak`, which is a release
// gate (docs/15 §1). A gate that can pass against yesterday's modules is not a gate: this was
// found by injecting a `submission_count` field into an `open`-phase payload and watching the
// golden-file suite go green against a stale worker.
//
// So: hash the tree, compare against the hash the runtime was last restarted for, and restart
// the container when they differ. A no-op on the common path, about eight seconds when it
// fires, and it removes the failure mode entirely.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const CONTAINER = "supabase_edge_runtime_blind-drop";
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

/** Content hash of every `.ts` under `functions/`, path included so a rename counts. */
function treeHash(functionsDir) {
  const hash = createHash("sha256");
  const walk = (dir) => {
    for (const entry of readdirSync(dir).sort()) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) walk(full);
      else if (entry.endsWith(".ts")) {
        hash.update(full.slice(functionsDir.length));
        hash.update(readFileSync(full));
      }
    }
  };
  walk(functionsDir);
  return hash.digest("hex");
}

/**
 * Restarts the edge runtime if `functions/` has changed since it last did.
 *
 * Returns `true` when it restarted. Silent and instant when nothing has changed, which is
 * every run where you are only editing tests.
 */
export function ensureFreshEdgeRuntime(root, { log = console.log } = {}) {
  const functionsDir = join(root, "supabase", "functions");
  if (!existsSync(functionsDir)) return false;

  const stampDir = join(root, "supabase", ".temp");
  const stampPath = join(stampDir, "edge-runtime-tree-hash");
  const current = treeHash(functionsDir);
  const previous = existsSync(stampPath) ? readFileSync(stampPath, "utf8").trim() : null;
  if (previous === current) return false;

  // No docker means a hosted stack, where deploys handle this and there is nothing to restart.
  if (spawnSync("docker", ["inspect", CONTAINER], { stdio: "ignore" }).status !== 0) return false;

  log(dim("  functions/ changed since the edge runtime started — restarting it…"));
  const restart = spawnSync("docker", ["restart", CONTAINER], { stdio: "ignore" });
  if (restart.status !== 0) {
    log(dim("  could not restart the edge runtime; run `npm run db:restart` if results look stale."));
    return false;
  }

  mkdirSync(stampDir, { recursive: true });
  writeFileSync(stampPath, current);
  return true;
}

/** Blocks until the runtime answers, so the first test does not race the restart. */
export async function waitForEdgeRuntime(url, anonKey, { timeoutMs = 60_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const res = await fetch(`${url}/functions/v1/me`, { headers: { apikey: anonKey } }).catch(() => null);
    // Any envelope at all means the runtime is up. 401 is the expected one — `me` refuses an
    // anonymous caller — and is proof the handler itself ran, not just the gateway.
    if (res) {
      await res.body?.cancel();
      if (res.status !== 503 && res.status !== 502) return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return false;
}
