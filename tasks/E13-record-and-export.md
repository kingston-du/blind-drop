# E13 — The Record and exports

The retention asset after the novelty of the game fades. It should feel like an archive, not
a feed.

Owner amendment A2 lands here: **every song must be linkable to Spotify, and the archive must
export to Spotify.** Treat the Spotify path as primary-grade, not as a fallback.

> **Before starting, confirm and note here:** Spotify apps in development mode still allow up
> to 25 manually-added users, and PKCE public-client auth still works for them. A 6–12 person
> pilot fits inside that cap. Record the date you checked and the tester emails in
> `server/.env.example`.

> **Policy check — 2026-08-12:** Spotify's current quota-mode documentation limits a
> development-mode app to **5 allowlisted authenticated users** and requires the app owner to
> have Premium. The earlier 25-user assumption is no longer true, so a 6–12 person pilot needs
> an approved extended-quota app or a pilot capped at five Spotify export testers. Authorization
> Code with PKCE remains Spotify's recommended mobile/public-client flow and still requires no
> client secret. Spotify's February 2026 migration also replaced
> `POST /users/{id}/playlists` with `POST /me/playlists` and
> `POST /playlists/{id}/tracks` with `POST /playlists/{id}/items`; E13 uses the live endpoints.
> Spotify now requires an HTTPS redirect URI, so the superseded `blinddrop://spotify-auth`
> design is implemented as `https://blinddrop.app/spotify-auth` using Apple's associated-domain
> callback matcher (iOS 17.4+).
> Blind Drop does not consume Spotify preview URLs, so preview availability does not affect the
> build.
>
> **Open question:** choose whether the pilot limits Spotify export to five allowlisted users or
> waits for extended quota. This does not change the client implementation; Apple Music export
> and per-track links remain available to the full group.

---

### E13-01 — `RecordScreen`, pagination, filter

**Status:** done · **Deps:** E08-04, E07-06 · **Reads:** `docs/08` §8, `docs/04` §5, `docs/11` (record)
**Touches:** `Features/Record/{RecordScreen,RecordStore}.swift`
**Verify:** snapshot matrix; pagination test against the fixture server

- [x] Newest first, grouped by `local_date`, **sticky date headers**
- [x] Cursor pagination at 50; prefetch at 10 rows from the end
- [x] Member filter as a menu — filtering to one person is the most-used view, it's how you
      learn someone's taste
- [x] Row overflow: **See that night's results** → `ResultsScreen` for that round
- [x] Preview playback reuses `PreviewPlayer`, one at a time
- [x] Empty states from `docs/11`, including the filtered variant
- [x] Reachable from the header menu in **every** phase
- [x] It reads as an archive: no engagement affordances, no counts, no "new" badges

---

### E13-02 — Per-track Spotify and Apple links

**Status:** done · **Deps:** E13-01 · **Reads:** `docs/06` §5 (linking), §7
**Touches:** `Features/Record/RecordScreen.swift`, `DesignSystem/Components/TrackRow.swift`
**Verify:** unit test on the URL fallback chain

- [x] `spotify:track:{id}` attempted first; falls back to
      `https://open.spotify.com/track/{id}` when `canOpenURL` says no
- [x] Same treatment for Apple Music
- [x] Both shown where both exist. Neither defaulted, neither emphasised.
- [x] Rendered in `ink-dim`, **never an accent colour** — this is a utility, not part of the
      game's phase language
- [x] `spotify_url == null` → the button is **absent**, not disabled (`docs/06` §7)
- [x] Also surfaced on the sealed card and on results rows, same rules

---

### E13-03 — Spotify PKCE auth

**Status:** done · **Deps:** E13-01 · **Reads:** `docs/06` §6, `docs/14` §6
**Touches:** `Core/Auth/SpotifyAuth.swift`
**Verify:** auth round-trip against a stub; `SpotifyAuthTests`

Nothing about this touches our server.

- [x] `ASWebAuthenticationSession`, `response_type=code`, `code_challenge_method=S256`,
      `redirect_uri=https://blinddrop.app/spotify-auth` (Spotify now requires HTTPS)
- [x] Scopes: `playlist-modify-private playlist-modify-public`
- [x] **No client secret in the app.** PKCE exists precisely so it never has to be there. If a
      step seems to need it, the step is wrong.
- [x] Tokens in the **Keychain**, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [x] Never sent to our server, never in `UserDefaults`
- [x] 401 → refresh once → re-auth
- [x] `SPOTIFY_CLIENT_ID` from `Info.plist` (public by design)
- [x] Test: `strings` on the built binary finds no client secret

---

### E13-04 — Spotify playlist export

**Status:** done · **Deps:** E13-03 · **Reads:** `docs/06` §6, `docs/11` (record.export)
**Touches:** `Features/Record/Export/SpotifyExporter.swift`
**Verify:** `SpotifyExporterTests` against a stub

- [x] `POST /v1/me/playlists` → `POST /v1/playlists/{id}/items` in batches of 100 URIs
      (the current replacements for Spotify's February 2026 removed endpoints)
- [x] Playlist name `"{Group name} — Blind Drop"`; an existing playlist with that name is
      **not** reused — silently mutating a playlist the user may have edited is worse
- [x] Order matches The Record's on-screen order, newest first
- [x] Unresolved tracks skipped and **stated**: *"3 songs aren't on Spotify. The rest are in."*
      Never silently dropped.
- [x] Success is a quiet row and a link. No celebration, no confetti.
- [x] Failure copy from `docs/11`; the operation is safely retryable
- [x] Test: batching at 100 with 250 tracks; order preserved across batches

---

### E13-05 — Apple Music playlist export

**Status:** done · **Deps:** E13-01 · **Reads:** `docs/06` §6, §7, `docs/11`
**Touches:** `Features/Record/Export/AppleMusicExporter.swift`
**Verify:** manual on a device with a subscription; unit test on the gating logic

The **only** use of the MusicKit framework in the app.

- [x] `MusicAuthorization.request()` — the prompt is fine here, it's an explicit export action
- [x] `MusicSubscription.current` checked; no subscription → the copy from `docs/11`, and the
      **Spotify button stays available**
- [x] Denied authorization → same, Spotify unaffected
- [x] `MusicLibrary.shared.createPlaylist(name:items:)` with the `apple_music_id`s
- [x] Same naming, ordering, and unresolved-count rules as Spotify
- [x] Test: the gating logic never disables the Spotify path for an Apple-side failure

> **Verification — 2026-08-12:** the exact full iOS scheme, Record snapshot matrix, iOS lint,
> pgTAP (544 assertions), Edge Functions (216 tests), and AC-1 leak audit all pass. Source and
> built-binary scans find no client secret. Production-account smoke tests for Spotify's
> dashboard/domain registration and Apple Music on a subscribed device remain explicit
> release checks in E14-05, where the signing and service credentials are configured.
