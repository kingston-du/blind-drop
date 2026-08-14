// devices/index.ts — APNs registration. docs/04 §2, docs/05 §4. tasks/E06-03.
//
//   POST   /   register (or re-register) this device's APNs token
//   DELETE /   detach this device before signing out
//
// The client calls this once after the user grants notification permission — which happens
// after the first successful seal, never at launch — and again on every cold start, because
// APNs can hand out a new token at any time and a stale one is a silently undelivered push.
//
// Three things this endpoint deliberately does not have:
//
//   1. **No preferences.** No per-type toggles, no quiet hours, no `enabled` flag. Three
//      pushes a day is already quiet, and a settings field here would imply there is
//      something to manage (docs/05 §4, CLAUDE.md §2.6).
//   2. **No read side.** There is no `GET /devices`. A list of a user's registered devices is
//      of no use to the app and is a nice inventory for anyone holding a stolen token.
//   3. **No response body.** 204, whether the token was new, moved between users, or arrived
//      unchanged for the four hundredth time. A caller learns nothing about the row it just
//      wrote, including whether it already existed.

import { ApiError, noContent, parseBody, serveFunction, str } from "../_shared/http.ts";
import { requireProfile, requireUser } from "../_shared/auth.ts";
import { dbFailure } from "../_shared/db.ts";

/**
 * A device token as Apple formats it: hex, and today always 32 bytes of it.
 *
 * The upper bound is generous rather than exactly 64 because Apple has changed the length
 * before and has said it may again; the lower bound is what stops a one-character token from
 * being stored and then quietly never delivered to. Case is not significant in hex, so the
 * value is lowercased before it is stored — otherwise the same physical device could hold two
 * rows under two spellings of one token and take two copies of every push.
 */
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;

const ENVIRONMENTS = ["sandbox", "production"] as const;

serveFunction("devices", {
  "POST /": async (req, route) => {
    // `requireProfile`, not `requireUser`: `devices.user_id` references `profiles(id)`, so a
    // signed-in caller who has not finished onboarding gets `NO_PROFILE` here rather than a
    // foreign-key violation dressed up as `INTERNAL`.
    const ctx = await requireProfile(await requireUser(req, route));

    const body = await parseBody(req, {
      apns_token: str({ min: 64, max: 200, pattern: APNS_TOKEN }),
      environment: str({ min: 1, max: 16 }),
    });
    const environment = ENVIRONMENTS.find((value) => value === body.environment);
    if (!environment) throw new ApiError("INVALID_INPUT", { field: "environment" });

    // Upsert on the token, not on the user: one person may carry three devices, and one
    // device may be handed to somebody else. The conflict target is `apns_token` because the
    // token is what Apple will deliver to, so it is the thing that must have exactly one
    // owner — the second user to register a shared device takes it, and the first stops
    // receiving that device's pushes (docs/04 §2).
    //
    // `disabled_at` is cleared on every registration. A token is disabled only by a 410 from
    // Apple (E06-04), and a live app presenting the same token again is the direct evidence
    // that the 410 no longer holds.
    const { error } = await ctx.db
      .from("devices")
      .upsert({
        user_id: ctx.userId,
        apns_token: body.apns_token.toLowerCase(),
        environment,
        last_seen_at: new Date().toISOString(),
        disabled_at: null,
      }, { onConflict: "apns_token" });
    if (error) throw dbFailure("devices.register", error);

    return noContent();
  },

  "DELETE /": async (req, route) => {
    const ctx = await requireUser(req, route);
    const body = await parseBody(req, {
      apns_token: str({ min: 64, max: 200, pattern: APNS_TOKEN }),
    });
    const { error } = await ctx.db
      .from("devices")
      .delete()
      .eq("user_id", ctx.userId)
      .eq("apns_token", body.apns_token.toLowerCase());
    if (error) throw dbFailure("devices.unregister", error);
    return noContent();
  },
});
