// push-worker/index.ts — the APNs notification outbox worker. docs/05 §2, §4. tasks/E06-02.

import { requireServiceRole } from "../_shared/auth.ts";
import { serviceClient } from "../_shared/db.ts";
import { ok, serveFunction } from "../_shared/http.ts";
import { drainPushOutbox } from "./worker.ts";

serveFunction("push-worker", {
  "POST /": async (req) => {
    await requireServiceRole(req);
    return ok(await drainPushOutbox(serviceClient()));
  },
});
