// _shared/music/upstream.ts — the only place this project makes an outbound request.
// docs/06 §4–5, docs/14 §7.
//
// Two jobs, and it exists so that neither is done twice anywhere else:
//
//   1. **The host allowlist.** `POST /tracks/resolve` takes a URL from a user. If a handler
//      could hand any URL to `fetch`, the function's service-role network position becomes an
//      SSRF pivot (docs/14 §7: "No arbitrary URL is ever fetched server-side"). The allowlist
//      lives here rather than in the parser, so a caller that forgets to parse still cannot
//      reach anything but these three hosts.
//   2. **The budget.** Every upstream call has a deadline and there is no default one, because
//      the deadlines differ by an order of magnitude: search is 30% of a 90-second budget
//      (docs/00 §7), the inline Spotify lookup gets 700ms and no more (docs/06 §5). Making
//      `budgetMs` required means every call site has had to think about it.
//
// In fixture mode it substitutes the *hop*, not the code — see `fixtures.ts`.

import { UpstreamError } from "./errors.ts";
import { fixturesEnabled, fixtureUpstream } from "./fixtures.ts";

/** The complete set of hosts this server may talk to. Not a prefix or suffix match:
 *  `new URL(u).hostname` must equal one of these, so `api.spotify.com.evil.test`,
 *  `evil.test/?x=api.spotify.com` and `evil.test#api.spotify.com` are all refused. */
const ALLOWED_HOSTS: ReadonlySet<string> = new Set([
  "api.music.apple.com",
  "api.spotify.com",
  "accounts.spotify.com",
]);

export function isAllowedUpstream(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  return parsed.protocol === "https:" && ALLOWED_HOSTS.has(parsed.hostname);
}

export interface UpstreamOptions {
  /** Hard deadline in milliseconds. Required, deliberately — see the header. */
  budgetMs: number;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}

/**
 * One outbound request, allowlisted and time-boxed, returning the parsed JSON body.
 *
 * A non-2xx raises rather than resolving: an upstream 404 and an upstream 500 mean very
 * different things to a caller, and both would otherwise arrive as an indistinguishable
 * `undefined` somewhere further down.
 */
export async function upstreamJson<T>(url: string, opts: UpstreamOptions): Promise<T> {
  if (!isAllowedUpstream(url)) throw new UpstreamError("blocked");
  if (fixturesEnabled()) return await fixtureUpstream<T>(url, opts);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.budgetMs);
  let res: Response;
  try {
    res = await fetch(url, {
      method: opts.method ?? "GET",
      headers: opts.headers,
      body: opts.body,
      signal: controller.signal,
      // An allowlisted host that 302s to somewhere else is not a way around the allowlist.
      redirect: "error",
    });
  } catch {
    throw new UpstreamError(controller.signal.aborted ? "timeout" : "network");
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    // Cancel, or the response body keeps a connection open for the life of the isolate.
    await res.body?.cancel();
    throw new UpstreamError("status", res.status);
  }
  try {
    return await res.json() as T;
  } catch {
    throw new UpstreamError("network");
  }
}
