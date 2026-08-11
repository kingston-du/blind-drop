// _shared/music/resolve.ts — a user's input → one canonical Track. docs/06 §3–4, docs/14 §7.
// tasks/E07-03.
//
// Three input paths, and all three end at Apple:
//
//   Spotify URL/URI  → Spotify `GET /v1/tracks/{id}` → ISRC → Apple `filter[isrc]`
//   Apple URL or id  → Apple `GET /songs/{id}`
//   bare ISRC        → Apple `filter[isrc]`
//
// **A Spotify-only track is never stored.** If the Spotify → Apple hop finds nothing — and
// regional catalogue gaps are real — the answer is `INVALID_INPUT` with the
// `resolve.error.notfound` copy. The game needs a 30-second preview and a stable artwork URL
// on every card, and a track Apple does not have has neither. Storing it would produce a card
// that cannot be played and an archive entry that cannot be rendered.

import { ApiError } from "../http.ts";
import { UpstreamError } from "./errors.ts";
import { songById, songsByIsrc } from "./appleMusic.ts";
import { isrcForTrack } from "./spotify.ts";
import { isAppleMusicId, type LinkTarget, normaliseIsrc, parseSongLink } from "./identity.ts";
import type { TrackDTO } from "../dto.ts";

/** The three ways a client may name a track (docs/04 §4, §6). Exactly one must be present. */
export interface TrackInput {
  apple_music_id?: string;
  spotify_url?: string;
  isrc?: string;
}

/**
 * Which of the three fields was supplied, as the thing to look up.
 *
 * Zero or more than one is `INVALID_INPUT` naming `track`: the request is ambiguous and
 * guessing which field the client meant is how a client ships a bug that only appears when
 * two fields disagree.
 */
export function targetFromInput(input: TrackInput): LinkTarget {
  const present = (["apple_music_id", "spotify_url", "isrc"] as const).filter(
    (k) => input[k] !== undefined && input[k] !== "",
  );
  if (present.length !== 1) throw new ApiError("INVALID_INPUT", { field: "track" });

  switch (present[0]) {
    case "apple_music_id": {
      const id = (input.apple_music_id as string).trim();
      if (!isAppleMusicId(id)) throw new ApiError("INVALID_INPUT", { field: "apple_music_id" });
      return { kind: "apple", appleMusicId: id };
    }
    case "isrc": {
      const isrc = normaliseIsrc(input.isrc);
      if (!isrc) throw new ApiError("INVALID_INPUT", { field: "isrc" });
      return { kind: "isrc", isrc };
    }
    case "spotify_url": {
      // Deliberately `parseSongLink` and not a Spotify-only parser: the field is where people
      // paste *a link*, and half of them will paste an Apple one. Accepting it costs nothing
      // and refusing it would be pedantry the user reads as a bug.
      const target = parseSongLink(input.spotify_url as string);
      if (!target) throw new ApiError("INVALID_INPUT", { field: "spotify_url" });
      return target;
    }
  }
}

/**
 * A target → the canonical Track, or an `ApiError` a client can act on.
 *
 * `NOT_FOUND` is never used here. A song the catalogue does not carry is `INVALID_INPUT`,
 * because from the user's side it is their input that was wrong, and `resolve.error.notfound`
 * is the copy that says so ("That song isn't in the Apple catalog. Search for it instead.").
 * A 404 would send the client down the "that resource is gone" path instead.
 */
export async function resolveTarget(storefront: string, target: LinkTarget): Promise<TrackDTO> {
  try {
    switch (target.kind) {
      case "apple": {
        const track = await songById(storefront, target.appleMusicId);
        if (!track) throw new ApiError("INVALID_INPUT", { field: "apple_music_id" });
        return track;
      }
      case "isrc":
        return firstOrNotFound(await songsByIsrc(storefront, target.isrc), "isrc");
      case "spotify": {
        const isrc = await isrcForTrack(target.spotifyId);
        // No ISRC on the Spotify side means there is nothing to match on — and we never match
        // on title and artist (docs/06 §3), so this is the end of the road.
        if (!isrc) throw new ApiError("INVALID_INPUT", { field: "spotify_url" });
        return firstOrNotFound(await songsByIsrc(storefront, isrc), "spotify_url");
      }
    }
  } catch (err) {
    if (err instanceof ApiError) throw err;
    if (err instanceof UpstreamError) throw new ApiError("UPSTREAM_UNAVAILABLE");
    throw err;
  }
}

/** Apple returns every catalogue id carrying an ISRC — the single and the album release are
 *  separate ids for one recording. They all produce the same `track_key`, so which one is
 *  stored is arbitrary and cannot affect scoring (docs/06 §3). */
function firstOrNotFound(tracks: TrackDTO[], field: string): TrackDTO {
  const track = tracks[0];
  if (!track) throw new ApiError("INVALID_INPUT", { field });
  return track;
}

/** The whole path, for the two handlers that need it. */
export async function resolveTrack(storefront: string, input: TrackInput): Promise<TrackDTO> {
  return await resolveTarget(storefront, targetFromInput(input));
}
