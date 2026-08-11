// me/index.ts — identity. docs/04 §2, docs/14 §7, §9.
//
// Three routes, and the whole of what the app knows about a person:
//
//   GET /me   who am I, and am I in a group yet
//   PUT /me   set or change my display name
//   DELETE /me anonymise game history and delete authentication

import { ApiError, noContent, ok, parseBody, serveFunction, str } from "../_shared/http.ts";
import { requireProfile, requireUser, type UserCtx } from "../_shared/auth.ts";
import { dbFailure } from "../_shared/db.ts";
import { meDTO } from "../_shared/dto.ts";
import { charLength, cleanDisplayName } from "../_shared/text.ts";

/** Whether the caller has an active membership. Not *which* group — that is `/groups/current`
 *  — and never anything about who else is in it. */
async function hasGroup(ctx: UserCtx): Promise<boolean> {
  const { data, error } = await ctx.db
    .from("memberships")
    .select("id")
    .eq("user_id", ctx.userId)
    .is("left_at", null)
    .maybeSingle();
  if (error) throw dbFailure("me.hasGroup", error);
  return data !== null;
}

serveFunction("me", {
  "GET /": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return ok(meDTO({ id: ctx.userId, display_name: ctx.displayName }, await hasGroup(ctx)));
  },

  "PUT /": async (req, route) => {
    const ctx = await requireUser(req, route);

    // Validate the raw length first so a 200-character paste is refused rather than silently
    // cleaned down to something that fits, then clean, then validate what will actually be
    // stored. An all-invisible name cleans to "" and is rejected here (docs/14 §7).
    const { display_name } = await parseBody(req, { display_name: str({ min: 1, max: 96 }) });
    const cleaned = cleanDisplayName(display_name);
    if (charLength(cleaned) < 1 || charLength(cleaned) > 24) {
      throw new ApiError("INVALID_INPUT", { field: "display_name" });
    }

    // Upsert: onboarding step 2 creates the row, Settings later changes it. Duplicate names
    // within a group are deliberately allowed — two Sams is a real situation, and the guess
    // sheet disambiguates (docs/04 §2).
    const { data, error } = await ctx.db
      .from("profiles")
      .upsert(
        { id: ctx.userId, display_name: cleaned, updated_at: new Date().toISOString() },
        { onConflict: "id" },
      )
      .select("id, display_name")
      .single();
    if (error) throw dbFailure("me.put", error);

    return ok(meDTO(data, await hasGroup(ctx)));
  },

  "DELETE /": async (req, route) => {
    const ctx = await requireUser(req, route);
    // There are no deletion options. Rejecting keys keeps this route from acquiring a
    // half-supported mode through a client typo or a future refactor.
    await parseBody(req, {});

    const { error } = await ctx.db.rpc("delete_account", { p_user: ctx.userId });
    if (error) throw dbFailure("me.delete", error);
    return noContent();
  },
});
