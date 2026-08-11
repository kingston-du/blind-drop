# E07 — Music services

Apple Music is the search and preview engine (ADR-002). Spotify is the identity bridge and an
export target (owner amendment A2). This epic can run in parallel with E03–E06 once `E02-01`
lands.

> **Before starting, verify and record in this file:** (a) Apple Music song attributes still
> include `isrc` and `previews[].url`; (b) Spotify's `GET /v1/search?q=isrc:` still works for
> a development-mode app. We do not use Spotify preview URLs at all, so the 2024 restriction
> on those should be irrelevant — confirm it and note the date you checked.

**Checked 2026-08-11, against the vendors' own reference docs:**

| Assumption | Verdict |
|---|---|
| Apple `Songs.Attributes` still carries `isrc` | **holds** — documented, and `GET /v1/catalog/{sf}/songs?filter[isrc]=` is a first-class route ("Get Multiple Catalog Songs by ISRC") |
| Apple still carries `previews[].url`, `artwork.url` as a `{w}x{h}` template, `artwork.bgColor`, `durationInMillis` | **holds** — all four documented on `Songs.Attributes` / `Artwork` |
| Spotify `GET /v1/search?q=isrc:{ISRC}&type=track` | **holds** — `isrc` is a documented track filter, alongside `track`, `artist`, `album`, `year`, `genre` |
| The 2024 `preview_url` restriction is irrelevant to us | **holds, by construction** — no code path in this repo reads a Spotify `preview_url`; previews come from Apple only (`_shared/music/appleMusic.ts`). Nothing to break. |
| Development mode caps a new Spotify app at 25 users | unchanged; the quota-mode page is unversioned so this is re-checked before `E13`, not here — the pilot is under 25 either way |

---

### E07-01 — Apple Music developer token

**Status:** wip · **Deps:** E02-01 · **Reads:** `docs/06` §4, §8
**Touches:** `functions/_shared/music/appleMusic.ts`
**Verify:** `npm run test:functions -- applemusic`

ES256 JWT from the MusicKit `.p8`, via Web Crypto. Shares the signing helper with `E06-01`.

- [ ] Claims `iss = TEAM_ID`, `kid = KEY_ID`, `exp` ≤ 180 days
- [ ] Cached in module scope, regenerated at 80% of lifetime
- [ ] `.p8` from a Supabase secret only; never in the app bundle
- [ ] Storefront resolution from `X-Storefront`, validated against a known list, default `us`
- [ ] Test: token verifies; an unknown storefront falls back to `us` rather than erroring

---

### E07-02 — `GET /tracks/search`

**Status:** wip · **Deps:** E07-01 · **Reads:** `docs/06` §2, §4, `docs/04` §6
**Touches:** `functions/tracks/index.ts`
**Verify:** `npm run test:functions -- search`

- [ ] Maps Apple song attributes → the Track DTO in `docs/06` §2, field by field
- [ ] **Artwork URL stored as the `{w}x{h}` template**, not a resolved size
- [ ] `preview_url` from `previews[0].url`; absent is normal and must not error
- [ ] `artwork_bg_color` captured (used only as a load placeholder — `docs/06` §2.1)
- [ ] Edge cache 10 min on `(storefront, lower(trim(q)))`
- [ ] Rate limit 30/min per user
- [ ] p95 under 400ms with a warm cache (this is 30% of the 90-second budget)
- [ ] Test: a song with no ISRC still returns a valid DTO with an `am:` `track_key`

---

### E07-03 — `POST /tracks/resolve` and `track_key`

**Status:** wip · **Deps:** E07-02 · **Reads:** `docs/06` §3–4, `docs/14` §7
**Touches:** `functions/_shared/music/resolve.ts`
**Verify:** `npm run test:functions -- resolve`

```
track_key = isrc ? 'isrc:' + isrc : 'am:' + apple_music_id
```

- [ ] ISRCs uppercased and de-hyphenated before use
- [ ] Three input paths: Spotify URL/URI → ISRC → Apple; Apple URL/id → Apple; bare ISRC →
      Apple
- [ ] **URL allowlist** — only Spotify and Apple Music host patterns. No arbitrary URL is
      ever fetched server-side (SSRF, `docs/14` §7)
- [ ] ISRC validated against `^[A-Z]{2}[A-Z0-9]{3}\d{7}$`
- [ ] Spotify→Apple miss returns `INVALID_INPUT` with the `resolve.error.notfound` copy. A
      Spotify-only track is **never** stored — the game needs a preview and stable artwork
- [ ] Never match on title/artist strings
- [ ] Test: two Apple catalog ids sharing one ISRC produce the same `track_key`
- [ ] Test: a live recording and its studio original produce different keys

---

### E07-04 — Spotify ISRC lookup

**Status:** wip · **Deps:** E07-03 · **Reads:** `docs/06` §5, §8
**Touches:** `functions/_shared/music/spotify.ts`
**Verify:** `npm run test:functions -- spotify`

Client-credentials flow, our credentials, server-side only.

- [ ] Token cached for its full hour
- [ ] `GET /v1/search?q=isrc:{ISRC}&type=track&limit=1`
- [ ] Writes `spotify_id` / `spotify_url` into `track_links` keyed by `track_key`, and patches
      `track_meta` on existing submissions with that key
- [ ] Inline at submission with a **700ms budget**; a timeout never fails the submission
- [ ] A track with no ISRC is marked `unresolvable` immediately — title/artist search returns
      wrong recordings often enough to be worse than nothing
- [ ] `SPOTIFY_CLIENT_SECRET` used here and **nowhere near the app bundle**
- [ ] Test: submission succeeds with `spotify_id: null` when Spotify times out

---

### E07-05 — `track_links` backfill

**Status:** todo · **Deps:** E07-04, E03-05 · **Reads:** `docs/06` §5
**Touches:** `functions/push-worker/index.ts` or a sibling, `migrations/0007_track_links.sql`
**Verify:** `npm run test:db -- links`

- [ ] Up to 20 unresolved rows per minute, ordered by `resolve_attempts`
- [ ] After 3 failures set `unresolvable = true` and stop
- [ ] Backfill patches every existing `submissions.track_meta` sharing the `track_key`
- [ ] Test: for every `scored` submission, either `spotify_url` is present or
      `track_links.unresolvable` is true — **no track is left in limbo** (`docs/15` §2)

---

### E07-06 — Record and export endpoints

**Status:** todo · **Deps:** E07-04, E05-03 · **Reads:** `docs/04` §5, `docs/06` §6
**Touches:** `functions/groups/index.ts`
**Verify:** `npm run test:functions -- record`

- [ ] `GET /groups/current/record` — newest first, grouped by `local_date`, cursor-paginated
      at 50 (max 100), optional `member` filter
- [ ] **Only `scored` rounds appear.** A `voided` round never enters the archive — publishing
      those submissions later would retroactively break the blind window
- [ ] Every entry carries both `apple_music_url` and `spotify_url` (either may be null)
- [ ] `GET …/record/export?service=` returns the ordered track list plus `unresolved_count`
- [ ] The server **never** creates the playlist and never holds a user's third-party
      credentials — the client does it with the user's own token (`docs/06` §6)
- [ ] Test: a `revealed` round's submissions are absent from the record
- [ ] Test: `unresolved_count` matches the number of null ids for the requested service
