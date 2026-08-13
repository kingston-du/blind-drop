# 06 — Music integration

> **Owner amendment A2 applies here.** Apple Music remains the search and preview engine
> because it is better at both. But **every track must be linkable to Spotify, and the
> archive must export to Spotify.** Treat Spotify export as a first-class feature, not the
> nice-to-have the original PRD called it.

---

## 1. The shape of it

```
        search / previews                    identity bridge              export
   ┌──────────────────────────┐        ┌──────────────────────┐    ┌──────────────────┐
   │ Apple Music REST API     │        │ ISRC                 │    │ Spotify (PKCE,   │
   │ (server proxy, dev JWT)  │──ISRC─▶│ track_links cache    │───▶│  user's own auth)│
   └──────────────────────────┘        └──────────────────────┘    │ Apple Music      │
             │                                    ▲                 │  (MusicKit)      │
             ▼                                    │                 └──────────────────┘
     AVPlayer 30s preview            Spotify Web API (client creds)
```

Three separate concerns, deliberately not coupled:

| Concern | Who does it | Credential |
|---|---|---|
| Search, metadata, artwork, previews | **Server**, Apple Music REST API | our developer token |
| ISRC → Spotify id | **Server**, Spotify Web API | our client credentials |
| Creating a playlist in the user's account | **Client** | the *user's* OAuth token, never ours, never stored server-side |

---

## 2. The Track DTO

The single track shape used everywhere in `04-API-CONTRACT.md`. Also, verbatim, the shape of
`submissions.track_meta`.

```jsonc
{
  "track_key": "isrc:USUM71703861",
  "isrc": "USUM71703861",                 // nullable
  "title": "Ribs",
  "artist": "Lorde",
  "album": "Pure Heroine",
  "artwork_url": "https://is1-ssl.mzstatic.com/…/{w}x{h}bb.jpg",   // template, see §2.1
  "artwork_bg_color": "1d2b3a",           // hex, from Apple artwork.bgColor; nullable
  "duration_ms": 249000,
  "preview_url": "https://audio-ssl.itunes.apple.com/…m4a",        // nullable
  "apple_music_id": "1440857781",
  "apple_music_url": "https://music.apple.com/us/song/ribs/1440857781",
  "spotify_id": "2QjOHCTQ1JF3zJyfWY7EMU",  // nullable — may resolve later
  "spotify_url": "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"  // nullable
}
```

**`track_meta` is a denormalised snapshot, written at submission time and never rewritten**
— except for `spotify_id`/`spotify_url`, which may be backfilled by the resolver (§5). The
snapshot is what makes The Record survive catalog churn: a song pulled from Apple Music in
2027 still shows its title, artist, and artwork URL in the 2026 archive.

### 2.1 Artwork

Apple returns a URL template containing literal `{w}` and `{h}`. **Store the template.**
Substitute at render time:

| Use | Size |
|---|---|
| Search result row | `120x120` |
| Reveal card | `320x320` |
| Confirm / sealed card | `600x600` |
| Share card | `900x900` |

Request `@2x`/`@3x` equivalents by multiplying by the display scale, capped at 1200. Never
request a size larger than needed — this runs on cellular at 8pm.

`artwork_bg_color` is Apple's extracted dominant colour. **It is used for exactly one thing:**
the placeholder fill behind artwork while it loads, at 12% opacity over `surface`. It is never
used as a UI accent, never as a gradient, never tinting a card. Album artwork is the only
imagery in the app and nothing is layered on top of it (`07-DESIGN-SYSTEM.md`).

---

## 3. `track_key` — the identity rule

```
track_key = isrc ? ('isrc:' + isrc) : ('am:' + apple_music_id)
```

This is the dedupe identity used by the duplicate-track scoring rule
(`02-DOMAIN-RULES.md` §4.3) and the primary key of `track_links`.

- ISRC first, because the same recording has different Apple catalog IDs across storefronts
  and across single/album releases. Two members in different countries dropping the same song
  must produce the same `track_key`.
- **Never** compare on title/artist strings. "Ribs" by "Lorde" and "Ribs" by "Lorde " are
  not a matching problem worth having.
- ISRCs are uppercased and stripped of hyphens before use.
- Different recordings of the same song (live, remaster, radio edit) have different ISRCs and
  are correctly treated as different tracks. A player who drops the remaster while someone
  else drops the original does **not** get the duplicate rule. That is right.

---

## 4. Apple Music — server proxy

### Developer token

ES256 JWT signed with the `.p8` MusicKit private key.

```
header  { "alg": "ES256", "kid": APPLE_MUSIC_KEY_ID }
claims  { "iss": APPLE_MUSIC_TEAM_ID, "iat": now, "exp": now + 15552000 }   // 180d max
```

Generate with Web Crypto in Deno, cache in module scope, regenerate at 80% of lifetime. Store
the `.p8` as a Supabase function secret. **Never ship it in the app.**

### Search — `GET /tracks/search`

```
GET https://api.music.apple.com/v1/catalog/{storefront}/search
      ?term={q}&types=songs&limit={limit}
Authorization: Bearer <developer token>
```

- `storefront` from the client's `X-Storefront` header (derived from `Locale.current.region`,
  lowercased), defaulting to `us`. Validate against a known list; reject anything else to
  `us`.
- Map `data[].attributes` → Track DTO. `isrc` is present in song attributes; if it is
  missing, fall back to `am:` keying and log it — it should be rare.
- Cache 10 minutes on `(storefront, lower(trim(q)))`. Search is 30% of the 90-second budget
  (`00-PROJECT-BRIEF.md` §7); the cache is what keeps p95 under 400ms.
- Debounce client-side at 250ms, minimum 2 characters.

### Previews

`attributes.previews[0].url` is a plain HTTPS `.m4a`. Play it with `AVPlayer`. **No MusicKit
authorization, no Apple Music subscription, no permission prompt.** This is the whole reason
search is server-side (ADR-002).

Preview playback rules:
- One preview at a time. Starting a second stops the first.
- Preview does not autoplay, ever.
- Respect the silent switch: category `.playback` so it plays through silent mode *only* when
  the user explicitly taps play. Do not configure the audio session until first play.
- Deactivate the session when playback ends so the user's music resumes.

### Resolving a link — `POST /tracks/resolve`

| Input | Path |
|---|---|
| `https://open.spotify.com/track/{id}` or `spotify:track:{id}` | Spotify `GET /v1/tracks/{id}` → `external_ids.isrc` → Apple `GET /catalog/{sf}/songs?filter[isrc]={isrc}` |
| `https://music.apple.com/{sf}/song/{slug}/{id}` (or `?i={id}`) | Apple `GET /catalog/{sf}/songs/{id}` |
| bare ISRC | Apple `GET /catalog/{sf}/songs?filter[isrc]={isrc}` |

If the Spotify→Apple hop finds nothing (regional catalog gaps are real), return
`INVALID_INPUT` with the copy from `11-COPY-DECK.md`: *"That song isn't in the Apple catalog.
Search for it instead."* Do **not** store a Spotify-only track — the game needs a preview and
a stable artwork URL.

---

## 5. Spotify — the bridge

### Lookup (our credentials)

Client-credentials flow, server-side, token cached for its full hour.

```
GET https://api.spotify.com/v1/search?q=isrc:{ISRC}&type=track&limit=1
Authorization: Bearer <app token>
```

Take `tracks.items[0]`. Write `spotify_id` and `spotify_url` into `track_links` keyed by
`track_key`, and patch `submissions.track_meta` for existing rows with that `track_key`.

### When resolution happens

1. **At submission time**, inline, with a 700ms budget. If it resolves, great — the sealed
   card can show the Spotify link immediately.
2. **If it does not resolve in budget**, the submission succeeds anyway with
   `spotify_id: null` and a `track_links` row with `resolve_attempts` incremented. Sealing a
   song must never fail because Spotify was slow.
3. **A backfill pass** runs inside `tick_rounds()`'s minute: take up to 20 rows from
   `track_links_needs_resolve`, look them up, update. After 3 failed attempts set
   `unresolvable = true` and stop trying.

A track with no ISRC skips step 1 entirely and is marked `unresolvable` immediately — there
is no reliable way to match it, and title/artist search returns wrong recordings often enough
to be worse than nothing.

**Expected hit rate is high but not 100%.** Regional exclusives and very new releases miss.
The UI must handle `spotify_url == null` gracefully everywhere (§7).

### Linking

Every track surface that shows a song offers a Spotify link when `spotify_url` is present:

- Open `spotify:track:{id}` first (opens the app directly).
- If `UIApplication.canOpenURL` says no, open `https://open.spotify.com/track/{id}`.
- The affordance is a small text button reading **Open in Spotify**, in `ink-dim`, never an
  accent colour — it is a utility, not part of the game's phase language.

Apple Music gets the identical treatment (**Open in Apple Music**, `apple_music_url`). Both
appear where both exist. Neither is defaulted or emphasised.

---

## 6. Playlist export

Two buttons on The Record: **Export to Spotify**, **Export to Apple Music**. Both create a
playlist in the user's own account, from the client, with the user's own credentials.

### Spotify export — Authorization Code with PKCE

Nothing about this touches our server.

1. `ASWebAuthenticationSession` → `https://accounts.spotify.com/authorize` with
   `response_type=code`, `code_challenge_method=S256`,
   `redirect_uri=https://blinddrop.app/spotify-auth`,
   `scope=playlist-modify-private playlist-modify-public`.
2. Exchange the code at `/api/token` with the verifier. **No client secret** — PKCE public
   client. The secret stays server-side and is used only for the client-credentials lookup in
   §5.
3. Store `access_token` + `refresh_token` in the **Keychain**, accessibility
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Never in `UserDefaults`. Never sent to
   our server.
4. `POST /v1/me/playlists` → `POST /v1/playlists/{id}/items` in batches of 100 URIs. Spotify
   removed the older user-id and `/tracks` forms in February 2026.
5. On success, offer to open the playlist. On 401, refresh once, then re-auth.

The exact redirect URL must also be registered in the Spotify dashboard. `blinddrop.app` must
serve an `apple-app-site-association` file whose `webcredentials.apps` contains the production
`<TEAM_ID>.<BUNDLE_ID>`; the iOS target carries the matching `webcredentials:blinddrop.app`
entitlement. Without those two release-time registrations, iOS correctly refuses to hand the
HTTPS callback to the app.

**Pilot constraint (re-checked 2026-08-12).** A Spotify app registered today starts in
*development mode*: up to **5** authenticated users, each added by email in the Spotify
dashboard, and the app owner must have Premium. A 6–12 person pilot therefore needs extended
quota or must limit Spotify export testing to five allowlisted accounts. Document those tester
emails in `server/.env.example` comments. We do **not** use Spotify preview URLs at all, so
preview availability does not affect this build. Authorization Code with PKCE remains Spotify's
recommended mobile/public-client flow.

### Apple Music export — MusicKit

This is the **only** use of the MusicKit framework.

1. `MusicAuthorization.request()` — prompt here is fine, it is an explicit export action.
2. Requires an active Apple Music subscription. If `MusicSubscription.current` says no, show
   the copy in `11-COPY-DECK.md` and leave the Spotify button available.
3. `MusicLibraryRequest` / `MusicLibrary.shared.createPlaylist(name:items:)` with the
   `apple_music_id`s.

### Export UX rules

- Playlist name: `"{Group name} — Blind Drop"`. Existing playlist with that name is **not**
  reused; create a new one and let the user manage duplicates. Silently mutating a playlist
  the user may have edited is worse.
- Order: newest round first, matching The Record's on-screen order.
- Unresolved tracks are skipped and **stated**: *"3 songs aren't on Spotify. The rest are in."*
  Never silently drop them.
- Export is not gamified, not celebrated, not confetti'd. A quiet success row and a link.

---

## 7. Degradation matrix

| Condition | Behaviour |
|---|---|
| Apple Music API down | Search returns `UPSTREAM_UNAVAILABLE`. Copy: *"Search is down. Paste a Spotify or Apple Music link instead."* The paste path also fails — say so plainly; do not spin. |
| Track has no preview | Card renders with no play control. No placeholder, no disabled button, no explanation. |
| Track has no ISRC | `track_key` falls back to `am:`. No Spotify link. `unresolvable = true`. |
| Spotify lookup fails | Submission still succeeds. No Spotify link on that track until backfill lands. |
| `spotify_url == null` at render | The **Open in Spotify** button is absent, not disabled. |
| User denies MusicKit at export | Apple export unavailable; Spotify export unaffected. |
| User has no Apple Music subscription | Apple export unavailable; Spotify export unaffected. |
| Offline at search | Standard offline state. The last search's results are not cached — searching offline is not a supported flow. |

---

## 8. Secrets checklist

| Name | Where | Used by |
|---|---|---|
| `APPLE_MUSIC_KEY_ID`, `APPLE_MUSIC_TEAM_ID`, `APPLE_MUSIC_PRIVATE_KEY` | Supabase function secrets | `_shared/music/appleMusic.ts` |
| `SPOTIFY_CLIENT_ID` | Supabase secrets **and** iOS `Info.plist` (public, PKCE) | server lookup, client PKCE |
| `SPOTIFY_CLIENT_SECRET` | Supabase secrets **only** | server client-credentials lookup |

The Spotify client secret must never reach the app bundle. PKCE exists precisely so it does
not have to. If a task tempts you to put it there, the task is wrong.
