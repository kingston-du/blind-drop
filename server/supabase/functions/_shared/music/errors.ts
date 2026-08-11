// _shared/music/errors.ts — what an upstream failure is, in its own module so that
// `upstream.ts` and `fixtures.ts` can both raise one without importing each other.

export type UpstreamReason =
  /** The budget expired. The caller decides whether that is fatal (search) or not (Spotify). */
  | "timeout"
  /** A non-2xx answer. `status` carries it, for the log only — never for the client. */
  | "status"
  /** Connection refused, DNS, TLS, or a body that was not JSON. */
  | "network"
  /** The URL was not on the allowlist. A bug or an attack; never a transient condition. */
  | "blocked";

/**
 * An upstream that did not answer usefully.
 *
 * Callers decide what it means, and they decide differently: `GET /tracks/search` turns it
 * into `UPSTREAM_UNAVAILABLE`, while the Spotify ISRC lookup swallows it and returns `null`,
 * because sealing a song must never fail because Spotify was slow (docs/06 §5).
 */
export class UpstreamError extends Error {
  constructor(readonly reason: UpstreamReason, readonly status?: number) {
    super(`upstream ${reason}${status === undefined ? "" : ` ${status}`}`);
    this.name = "UpstreamError";
  }
}
