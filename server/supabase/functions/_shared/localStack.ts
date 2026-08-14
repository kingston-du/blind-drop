// _shared/localStack.ts — the one question every fixture switch has to ask first.
//
// Two flags in this project replace a real upstream with an in-process stand-in: `MUSIC_FIXTURES`
// (`music/fixtures.ts`) and `APNS_FIXTURES` (`push-worker/worker.ts`). Both are for the local
// stack, both are set in `supabase/config.toml`, and both were documented as "never set in a
// deployed environment" — which is a comment, not a control. A deploy that carries the local
// `.env` up with `supabase secrets set --env-file` sets them anyway, and then nothing fails:
// search quietly answers from an eight-song catalogue and pushes are quietly swallowed, which
// is far worse than an outage because it looks like the product working badly.
//
// So the flags are now honoured only where the stand-in makes sense, and the deployed runtime
// refuses them however they arrive.

/** Hostnames a locally-running Supabase stack answers on. `kong` is the edge runtime container's
 *  own view of the gateway; `127.0.0.1` is what `supabase status` prints for the test process. */
const LOCAL_HOSTS: ReadonlySet<string> = new Set([
  "kong",
  "localhost",
  "127.0.0.1",
  "0.0.0.0",
  "host.docker.internal",
]);

/** Whether this function is running against a local stack rather than a Supabase project.
 *
 *  `SUPABASE_URL` is injected by the platform in both worlds and cannot be spoofed by a request,
 *  which is what makes it the right thing to key on: deployed it is `https://<ref>.supabase.co`,
 *  local it is one of `LOCAL_HOSTS`. Unparseable or absent counts as deployed — the safe default
 *  for a switch whose failure mode is serving fake data to real users. */
export function isLocalStack(): boolean {
  const raw = Deno.env.get("SUPABASE_URL");
  if (!raw) return false;
  try {
    return LOCAL_HOSTS.has(new URL(raw).hostname);
  } catch {
    return false;
  }
}

/** Whether a fixture flag is both set and allowed to take effect.
 *
 *  Read per call, never cached: a test may set the variable after this module is first imported,
 *  and a Supabase secret must be removable without a redeploy. A flag that is on but ignored is
 *  logged every time rather than once, because the condition it describes is a misconfigured
 *  production project and should be impossible to miss in the logs. */
export function fixtureFlagEnabled(name: string): boolean {
  if ((Deno.env.get(name) ?? "").toLowerCase() !== "on") return false;
  if (isLocalStack()) return true;
  console.error(
    `${name} is set on a deployed stack and is being ignored. ` +
      `Fixtures are for the local stack only — run \`supabase secrets unset ${name}\`.`,
  );
  return false;
}
