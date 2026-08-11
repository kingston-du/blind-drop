# 04 — API contract

Base URL: `https://<project>.supabase.co/functions/v1`

All requests carry `Authorization: Bearer <supabase access token>` unless marked *public*.
All bodies are JSON. All timestamps are RFC 3339 UTC with a `Z`.

> **The rule this document exists to enforce:** during a round's `open` phase the response
> body must not contain another user's submission, a count of submissions, any member's
> submitted/not-submitted status, or anything from which one can be derived. Golden-file
> tests in `server/supabase/tests/golden/` assert the exact key sets below.

---

## 1. Envelope

Success — the resource, bare, plus a server clock:

```jsonc
{
  "server_now": "2026-08-10T18:42:07Z",
  "data": { /* endpoint-specific */ }
}
```

`server_now` is on **every** response. The client uses it to establish its clock offset
(`13-IOS-APP-ARCHITECTURE.md` §5). Countdowns are rendered from it, never from `Date()`.

Failure:

```jsonc
{
  "server_now": "2026-08-10T18:42:07Z",
  "error": { "code": "NOT_A_SUBMITTER", "message": "You didn't drop a song tonight." }
}
```

`message` is user-presentable and comes from `11-COPY-DECK.md`. `code` is stable and the
client switches on it. Never put a raw DB error in `message`.

### Error codes

| Code | HTTP | Meaning |
|---|---|---|
| `UNAUTHENTICATED` | 401 | Missing/invalid token |
| `NO_PROFILE` | 409 | Authenticated but display name not set |
| `NO_GROUP` | 409 | Not in a group yet |
| `NOT_FOUND` | 404 | Invite code, round, or resource does not exist |
| `WRONG_PHASE` | 409 | Action not allowed in the round's current state |
| `NOT_A_SUBMITTER` | 403 | Guessing without having submitted |
| `JOINED_LATE` | 403 | Joined after `reveals_at`; excluded from this round |
| `ROUND_VOIDED` | 409 | Round had fewer than 3 submissions |
| `INVALID_INPUT` | 400 | Validation failure; `details` may name the field |
| `ALREADY_IN_GROUP` | 409 | ADR-005 — one group per user |
| `NOT_ADMIN` | 403 | Group settings change by a non-admin |
| `RATE_LIMITED` | 429 | See §8 |
| `UPSTREAM_UNAVAILABLE` | 502 | Apple Music / Spotify failure |
| `INTERNAL` | 500 | Anything unhandled. Carries no detail — the detail is in the server log |

**Phase errors must not leak.** `WRONG_PHASE` returns the round's `state` and nothing else —
never "3 of 8 submitted, wait for reveal".

---

## 2. Identity

### `GET /me`

```jsonc
{ "data": {
  "user_id": "u_…",
  "display_name": "Ana",
  "has_group": true
}}
```

Returns `NO_PROFILE` if `display_name` has never been set — the client routes to onboarding
step 2 on that code.

### `PUT /me`

```jsonc
// request
{ "display_name": "Ana" }
```

Trimmed, 1–24 chars, no leading/trailing whitespace, no newlines. Duplicate display names
within a group are **allowed** (two Sams is a real situation) — the guess sheet disambiguates
by showing an initial suffix, see `08-SCREEN-SPECS.md` §4.

### `DELETE /me`

No request body. Returns `204`. Deletes the authentication principal and device tokens,
ends the active membership, and anonymises the stable historical profile to `Former member`.
Submissions and guesses remain because other members' scores and The Record depend on them.
The caller's current token is rejected on its next request.

### `POST /devices`

```jsonc
{ "apns_token": "…", "environment": "sandbox" }
```

Upsert on `apns_token`, re-points to the current user, clears `disabled_at`, bumps
`last_seen_at`. Returns `204`.

---

## 3. Groups

### `POST /groups` — create

```jsonc
// request
{ "name": "The Cove", "timezone": "America/New_York", "reveal_hour": 20 }
```

`timezone` must be a valid IANA name (validate against `pg_timezone_names`). `reveal_hour`
optional, default `20`, range `18..21`. Creator becomes `admin`. Returns the group DTO. Fails
`ALREADY_IN_GROUP` if the user has an active membership.

### `POST /groups/join`

```jsonc
// request
{ "invite_code": "K7MQ2X" }
```

Case-insensitive, whitespace stripped. Returns the group DTO. Fails `NOT_FOUND` or
`ALREADY_IN_GROUP`.

### `GET /groups/current`

```jsonc
{ "data": {
  "id": "g_…",
  "name": "The Cove",
  "timezone": "America/New_York",
  "reveal_hour": 20,
  "invite_code": "K7MQ2X",
  "is_admin": true,
  "members": [
    { "user_id": "u_…", "display_name": "Ana" },
    { "user_id": "u_…", "display_name": "Ben" }
  ]
}}
```

`members` is the active-membership roster and is **safe in every phase** — it is who is in
the group, not who has submitted. It carries no timestamps beyond nothing at all: do **not**
add `joined_at` to this DTO. During `open`, a `joined_at` that changed today plus a missing
name in tonight's pool is an inference channel.

### `PATCH /groups/current` — admin only

```jsonc
{ "name": "The Cove", "reveal_hour": 19 }
```

`timezone` is **immutable** after creation. `reveal_hour` changes apply to the first round
not yet created (`03-DATA-MODEL.md` §4) — the response echoes
`"effective_from": "2026-08-12"` so the UI can say so precisely.

### `POST /groups/current/leave`

Sets `left_at`. Returns `204`. The client returns to the join/create screen.

---

## 4. The round

### `GET /rounds/current` — the workhorse

Returns today's round for the caller's group, shaped by phase. The client calls this on
launch, on foreground, and when a countdown reaches zero.

**Phase `open` — the entire payload:**

```jsonc
{ "server_now": "2026-08-10T18:42:07Z",
  "data": {
    "round_id": "r_…",
    "local_date": "2026-08-10",
    "state": "open",
    "opens_at":   "2026-08-10T14:00:00Z",
    "reveals_at": "2026-08-11T00:00:00Z",
    "scores_at":  "2026-08-11T02:00:00Z",
    "my_submission": {
      "track": { /* Track DTO, docs/06 §2 */ },
      "sealed_at": "2026-08-10T16:11:02Z"
    }
  }}
```

- `my_submission` is `null` if the caller has not submitted.
- **There is no other key.** No `submission_count`, no `members_submitted`, no
  `participants`, no `pool`, no `card_count`. The golden test asserts the key set is exactly
  `{round_id, local_date, state, opens_at, reveals_at, scores_at, my_submission}`.
- `sealed_at` is the caller's own `updated_at`. Safe — it is their own data.
- Response size must not vary with participation. It does not, because nothing in it depends
  on anyone else.

**Phase `voided`:**

```jsonc
{ "data": {
  "round_id": "r_…", "local_date": "2026-08-10", "state": "voided",
  "opens_at": "…", "reveals_at": "…", "scores_at": "…",
  "my_submission": { "track": {…}, "sealed_at": "…" }
}}
```

Same shape. The user's own song comes back to them, unseen and unscored. **No count of how
many did submit** — "only 2 dropped" tells you something about specific people in a group of
eight. The copy is `"Not enough drops tonight. Nothing revealed."` and that is all.

**Phase `revealed`:**

```jsonc
{ "data": {
  "round_id": "r_…", "local_date": "2026-08-10", "state": "revealed",
  "opens_at": "…", "reveals_at": "…", "scores_at": "…",
  "my_submission": { "track": {…}, "sealed_at": "…" },
  "my_card_no": 4,                       // null if you didn't submit
  "can_guess": true,                     // false ⟹ reason is set
  "cannot_guess_reason": null,           // "not_a_submitter" | "joined_late" | null
  "cards": [
    { "card_no": 1, "track": { /* Track DTO */ } },
    { "card_no": 2, "track": { /* Track DTO */ } }
  ],
  "name_pool": [
    { "user_id": "u_…", "display_name": "Ana" },
    { "user_id": "u_…", "display_name": "Ben" }
  ],
  "my_guesses": [ { "card_no": 1, "guessed_user_id": "u_…" } ]
}}
```

- `cards` includes **every** card, including the caller's own. The client removes the
  caller's card from the *guessing* sheet using `my_card_no`, but the card is still listed —
  the numbering is the game's spine and must not have a hole in it.
- `name_pool` is exactly the submitters, **including** the caller. The client removes itself.
  Returning it whole keeps the client's arithmetic honest and makes `S` derivable for the
  progress copy ("6 of 7 assigned").
- `my_guesses` is the caller's own saved sheet. Nobody else's guesses are obtainable at any
  URL in this phase. There is no endpoint that returns another user's guesses before
  `scored`.
- Card ordering in `cards` is ascending `card_no` and identical for every member.

**Phase `scored`:** returns `{…, "state": "scored"}` with the same base keys plus nothing
else — the client then calls `GET /rounds/{id}/results`. Keeping results on their own route
means the launch call stays small and the results screen can be deep-linked from the push.

### `PUT /rounds/current/submission`

```jsonc
// request — one of:
{ "apple_music_id": "1440857781" }
{ "spotify_url": "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU" }
{ "isrc": "USUM71703861" }
```

Server resolves to a canonical Track (`06-MUSIC-INTEGRATION.md` §4), upserts on
`(round_id, user_id)`, returns the resolved submission:

```jsonc
{ "data": { "track": { /* Track DTO */ }, "sealed_at": "2026-08-10T16:11:02Z" } }
```

- Allowed only while `state = 'open'`; otherwise `WRONG_PHASE`.
- Replacement is a plain upsert. `created_at` is preserved, `updated_at` moves. Never
  announced, never counted, no separate "replace" route.
- Duplicate tracks across users are **never rejected** — the rejection itself would leak.
- There is no `DELETE`.
- Idempotent: the same body twice produces one row and the same response.

### `GET /rounds/current/reveal`

Deprecated alias — do not build it. Everything is on `GET /rounds/current`. Listed here only
so nobody re-invents it.

### `PUT /rounds/current/guesses`

Whole-sheet upsert. The client sends the complete current sheet; the server diffs.

```jsonc
// request
{ "assignments": [
    { "card_no": 1, "guessed_user_id": "u_ben" },
    { "card_no": 2, "guessed_user_id": null },     // explicit clear
    { "card_no": 3, "guessed_user_id": "u_cal" }
]}
```

```jsonc
// response
{ "data": { "assignments": [ { "card_no": 1, "guessed_user_id": "u_ben" } ],
            "assigned_count": 6, "assignable_count": 7 }}
```

Server-side validation, each failing with `INVALID_INPUT` unless noted:

1. `state` must be `revealed` → else `WRONG_PHASE`.
2. Caller must have a submission in the round → else `NOT_A_SUBMITTER` (403).
3. Caller's membership `joined_at` must be `< reveals_at` → else `JOINED_LATE` (403).
4. `card_no` must be in `1..N` and must not be the caller's own card.
5. `guessed_user_id` must be in the round's name pool and must not be the caller.
6. Duplicate `guessed_user_id` across two cards in one request → **allowed**. Players
   double-assign while thinking. The UI discourages it (`08-SCREEN-SPECS.md` §4) but the API
   permits it and scoring handles it naturally.
7. Missing `card_no` entries are left untouched — this is a partial-update-safe upsert. To
   clear a card, send it explicitly with `null`.

Guesses may be changed freely until `scores_at`. Partial sheets are valid; unassigned cards
score as wrong (`02-DOMAIN-RULES.md` §4.1).

### `GET /rounds/{round_id}/results`

Requires `state = 'scored'` → else `WRONG_PHASE`. Requires membership. Available for any past
round, which is how the Record links back into results.

```jsonc
{ "data": {
  "round_id": "r_…",
  "local_date": "2026-08-10",
  "submitter_count": 8,
  "cards": [
    {
      "card_no": 1,
      "track": { /* Track DTO */ },
      "owner": { "user_id": "u_dee", "display_name": "Dee" },
      "correct_guess_count": 4,
      "eligible_guesser_count": 7,
      "my_guess": { "guessed_user_id": "u_cal", "display_name": "Cal",
                    "is_correct": false }      // null if you didn't guess / couldn't
    }
  ],
  "me": {
    "readability": 0.857,          // null if you didn't submit
    "readability_correct": 6,
    "readability_possible": 7,
    "ear": 0.714,                  // null if you made zero guesses
    "ear_correct": 5,
    "ear_possible": 7
  },
  "people": [
    { "user_id": "u_ana", "display_name": "Ana",
      "readability": 0.857, "ear": 0.714 }
  ]
}}
```

- Rates are decimals `0..1`, not percentages. The client formats.
- `null` means *not applicable*, never *zero*. The client must render `null` ear as "—", not
  "0%". Getting this wrong turns "you sat out" into "you scored nothing", which is the one
  judgement the product refuses to make.
- `people` is every submitter, so the results screen can show the room at a glance.

### `GET /groups/current/standings`

```jsonc
{ "data": {
  "rounds_played": 14,
  "best_ear": [
    { "rank": 1, "user_id": "u_cal", "display_name": "Cal",
      "ear_all_time": 0.79, "ear_correct_total": 61 }
  ],
  "readability": [
    { "user_id": "u_ana", "display_name": "Ana",
      "readability_all_time": 0.83, "band": "open_book" }
  ]
}}
```

- `best_ear` **is** ranked; ties share a rank and the next rank skips.
- `readability` is **not** ranked and carries **no `rank` field**. It is sorted descending
  purely so the list is stable. `band` is one of `open_book | legible | mixed_signals |
  hard_to_place | unreadable` (`02-DOMAIN-RULES.md` §4.5). Do not add a rank to this array —
  a client that receives one will render it.

---

## 5. The Record

### `GET /groups/current/record`

Query: `?member=<user_id>` (optional filter) · `?cursor=<opaque>` · `?limit=` (default 50,
max 100).

```jsonc
{ "data": {
  "days": [
    { "local_date": "2026-08-10",
      "round_id": "r_…",
      "entries": [
        { "user_id": "u_ana", "display_name": "Ana",
          "track": { /* Track DTO */ } }
      ]}
  ],
  "next_cursor": "eyJkIjoiMjAyNi0wOC0wMSJ9"
}}
```

- Newest first, grouped by `local_date`.
- **Only rounds in state `scored`** appear. A `revealed` round is not in the archive yet, and
  a `voided` round never enters it — its submissions were returned unseen and publishing them
  later would retroactively break the blind window.
- Every entry's `track` carries both `apple_music_url` and `spotify_url` (either may be
  `null`), so every song in the archive is linkable to Spotify (`06-MUSIC-INTEGRATION.md`).

### `GET /groups/current/record/export?service=spotify|apple`

Returns the ordered track list for playlist creation. The playlist is created **by the
client** with the user's own OAuth token — the server never holds a user's Spotify or Apple
Music credentials.

```jsonc
{ "data": {
  "playlist_name": "The Cove — Blind Drop",
  "tracks": [
    { "spotify_uri": "spotify:track:2QjO…", "apple_music_id": "1440857781",
      "isrc": "USUM71703861", "title": "Ribs", "artist": "Lorde" }
  ],
  "unresolved_count": 2
}}
```

`unresolved_count` is the number of archive tracks with no id for the requested service. The
UI states it plainly (`11-COPY-DECK.md`) rather than silently dropping them.

---

## 6. Tracks

### `GET /tracks/search?q=<query>&limit=20`

Proxies Apple Music catalog search. Storefront from the caller's device region header,
default `us`.

```jsonc
{ "data": { "results": [ { /* Track DTO */ } ] } }
```

Cached edge-side for 10 minutes on `(storefront, normalised q)`. **This endpoint is available
in every phase and reveals nothing about the group** — it is a catalog proxy, not group data.

### `POST /tracks/resolve`

```jsonc
{ "spotify_url": "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU" }
```

Accepts a Spotify track URL/URI, an Apple Music song URL, or a bare ISRC. Returns a Track
DTO. Used by the "paste a link" path for people who search in Spotify by habit.

---

## 7. What is deliberately absent

There is no endpoint for any of these, and adding one is a spec violation:

- Submission counts, per-member submission status, or "who's still out" — in any phase.
- Another user's guesses before `scored`.
- Another user's submission before `revealed`.
- Round history for a group you are not a member of.
- Anything keyed by a `group_id` supplied by the client (ADR-005 — the group comes from the
  caller's membership, never from the request).
- Push-notification preferences. Three pushes, no settings (`05-JOBS-AND-NOTIFICATIONS.md`).

---

## 8. Rate limits

Per user, sliding window, returned as `429 RATE_LIMITED` with `Retry-After`:

| Route | Limit |
|---|---|
| `GET /tracks/search` | 30 / minute |
| `PUT /rounds/current/submission` | 20 / minute |
| `PUT /rounds/current/guesses` | 60 / minute |
| `POST /groups/join` | 10 / hour (invite-code brute force) |
| everything else | 120 / minute |

`POST /groups/join` additionally rate-limits per IP at 30/hour. `32^6` codes make brute force
impractical, but the limit makes it pointless.

**Rate-limit counters are per-user and never per-group** — a shared group counter would let
one member detect another member's activity by watching for throttling. That is a genuine
side channel; do not build a group-scoped limiter.
