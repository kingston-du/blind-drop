# E13 — The Record and exports

The retention asset after the novelty of the game fades. It should feel like an archive, not
a feed.

Owner amendment A2 lands here: **every song must be linkable to Spotify, and the archive must
export to Spotify.** Treat the Spotify path as primary-grade, not as a fallback.

> **Before starting, confirm and note here:** Spotify apps in development mode still allow up
> to 25 manually-added users, and PKCE public-client auth still works for them. A 6–12 person
> pilot fits inside that cap. Record the date you checked and the tester emails in
> `server/.env.example`.

---

### E13-01 — `RecordScreen`, pagination, filter

**Status:** todo · **Deps:** E08-04, E07-06 · **Reads:** `docs/08` §8, `docs/04` §5, `docs/11` (record)
**Touches:** `Features/Record/{RecordScreen,RecordStore}.swift`
**Verify:** snapshot matrix; pagination test against the fixture server

- [ ] Newest first, grouped by `local_date`, **sticky date headers**
- [ ] Cursor pagination at 50; prefetch at 10 rows from the end
- [ ] Member filter as a menu — filtering to one person is the most-used view, it's how you
      learn someone's taste
- [ ] Row overflow: **See that night's results** → `ResultsScreen` for that round
- [ ] Preview playback reuses `PreviewPlayer`, one at a time
- [ ] Empty states from `docs/11`, including the filtered variant
- [ ] Reachable from the header menu in **every** phase
- [ ] It reads as an archive: no engagement affordances, no counts, no "new" badges

---

### E13-02 — Per-track Spotify and Apple links

**Status:** todo · **Deps:** E13-01 · **Reads:** `docs/06` §5 (linking), §7
**Touches:** `Features/Record/RecordScreen.swift`, `DesignSystem/Components/TrackRow.swift`
**Verify:** unit test on the URL fallback chain

- [ ] `spotify:track:{id}` attempted first; falls back to
      `https://open.spotify.com/track/{id}` when `canOpenURL` says no
- [ ] Same treatment for Apple Music
- [ ] Both shown where both exist. Neither defaulted, neither emphasised.
- [ ] Rendered in `ink-dim`, **never an accent colour** — this is a utility, not part of the
      game's phase language
- [ ] `spotify_url == null` → the button is **absent**, not disabled (`docs/06` §7)
- [ ] Also surfaced on the sealed card and on results rows, same rules

---

### E13-03 — Spotify PKCE auth

**Status:** todo · **Deps:** E13-01 · **Reads:** `docs/06` §6, `docs/14` §6
**Touches:** `Core/Auth/SpotifyAuth.swift`
**Verify:** auth round-trip against a stub; `SpotifyAuthTests`

Nothing about this touches our server.

- [ ] `ASWebAuthenticationSession`, `response_type=code`, `code_challenge_method=S256`,
      `redirect_uri=blinddrop://spotify-auth`
- [ ] Scopes: `playlist-modify-private playlist-modify-public`
- [ ] **No client secret in the app.** PKCE exists precisely so it never has to be there. If a
      step seems to need it, the step is wrong.
- [ ] Tokens in the **Keychain**, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [ ] Never sent to our server, never in `UserDefaults`
- [ ] 401 → refresh once → re-auth
- [ ] `SPOTIFY_CLIENT_ID` from `Info.plist` (public by design)
- [ ] Test: `strings` on the built binary finds no client secret

---

### E13-04 — Spotify playlist export

**Status:** todo · **Deps:** E13-03 · **Reads:** `docs/06` §6, `docs/11` (record.export)
**Touches:** `Features/Record/Export/SpotifyExporter.swift`
**Verify:** `SpotifyExporterTests` against a stub

- [ ] `GET /v1/me` → `POST /v1/users/{id}/playlists` → `POST /v1/playlists/{id}/tracks` in
      batches of 100 URIs
- [ ] Playlist name `"{Group name} — Blind Drop"`; an existing playlist with that name is
      **not** reused — silently mutating a playlist the user may have edited is worse
- [ ] Order matches The Record's on-screen order, newest first
- [ ] Unresolved tracks skipped and **stated**: *"3 songs aren't on Spotify. The rest are in."*
      Never silently dropped.
- [ ] Success is a quiet row and a link. No celebration, no confetti.
- [ ] Failure copy from `docs/11`; the operation is safely retryable
- [ ] Test: batching at 100 with 250 tracks; order preserved across batches

---

### E13-05 — Apple Music playlist export

**Status:** todo · **Deps:** E13-01 · **Reads:** `docs/06` §6, §7, `docs/11`
**Touches:** `Features/Record/Export/AppleMusicExporter.swift`
**Verify:** manual on a device with a subscription; unit test on the gating logic

The **only** use of the MusicKit framework in the app.

- [ ] `MusicAuthorization.request()` — the prompt is fine here, it's an explicit export action
- [ ] `MusicSubscription.current` checked; no subscription → the copy from `docs/11`, and the
      **Spotify button stays available**
- [ ] Denied authorization → same, Spotify unaffected
- [ ] `MusicLibrary.shared.createPlaylist(name:items:)` with the `apple_music_id`s
- [ ] Same naming, ordering, and unresolved-count rules as Spotify
- [ ] Test: the gating logic never disables the Spotify path for an Apple-side failure
