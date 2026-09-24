# 14 — Security and threat model

> *"Assume a technically curious 18-year-old will proxy the traffic; several of them will."*

That line from the PRD is the whole threat model. The adversary is not a criminal — it is a
smart, bored member of the group who wants to win, and who has physical access to a device
inside the trust boundary. Everything below follows from taking that seriously.

---

## 1. Assets, ranked

| # | Asset | Why it matters | Loss if breached |
|---|---|---|---|
| 1 | Other users' submissions during `open` | The blind window **is** the product | Game is over. Not degraded — over. |
| 2 | Submission counts / who has submitted during `open` | Lets you infer ownership at guess time, and lets a late submitter game their pick against the field | Game is significantly degraded |
| 3 | Other users' guesses before `scored` | Copying guesses; also social fallout | Scores meaningless |
| 4 | `card_order` before reveal | Card N ↔ submission mapping | Full break of #1 |
| 5 | Group membership, display names, archive | Ordinary private data | Privacy incident |
| 6 | Our Apple Music / Spotify / APNs keys | Abuse, cost, impersonation | Operational |

Everything above #4 is a **correctness** problem before it is a security problem, which is
why the leak rules are in the API contract and not only here.

---

## 2. Attacker model

| Attacker | Capability | In scope |
|---|---|---|
| **Curious member** | Proxies their own app's traffic (Charles / mitmproxy with a trusted root on their own device), reads every response, replays requests, edits request bodies | **Yes — primary** |
| Curious member with a jailbroken device | Also reads the Keychain and the binary | Yes |
| Ex-member | Retains an old access token | Yes |
| Random internet | No group credentials; may brute-force invite codes | Yes |
| Nation-state / targeted attacker | — | No |
| Malicious server operator | — | No (we are the operator) |

**Certificate pinning is not a control here.** The primary attacker owns the device and can
trust their own root, and pinning would only add ops fragility. We do not pin. We instead
assume every response is fully visible to a member and make sure the responses do not contain
anything a member should not have. That assumption is what makes the design safe rather than
obscure.

---

## 3. The leak rules

Stated once, normatively. `04-API-CONTRACT.md` implements them; `15-TESTING-AND-ACCEPTANCE.md`
tests them.

**During a round in state `open`, no response to any authenticated request may contain, or
allow derivation of:**

1. Any submission belonging to another user — no track, no id, no timestamp, no partial.
2. The number of submissions in the round.
3. Whether any specific member has or has not submitted.
4. The round's name pool (it is derived from submissions).
5. `card_order` (it does not exist yet — enforce with the DB constraint in
   `03-DATA-MODEL.md`).
6. Any value whose **presence, length, or ordering** varies with the above.

**During `revealed`, additionally:** no response may contain another user's guesses, or the
mapping from `card_no` to `user_id`.

### Derivation channels we have actually closed

Being precise here, because "don't leak it" is easy and "don't leak it through a side channel"
is the part that gets missed.

| Channel | Closed by |
|---|---|
| A `submission_count` field | Golden-file test asserts the exact key set of the `open` payload |
| Response body **length** varying with participation | The `open` payload contains nothing derived from other users, so length varies only with the caller's own track metadata |
| `Content-Range` / row counts from PostgREST | PostgREST is not client-reachable; `REVOKE ALL` + deny-by-default RLS (`03-DATA-MODEL.md` §3) |
| `joined_at` on the member roster | Removed from `GET /groups/current` (`04-API-CONTRACT.md` §3) — a new `joined_at` plus a missing name in tonight's pool is an inference |
| `WRONG_PHASE` error bodies containing counts | Error bodies carry `state` and nothing else |
| A group-scoped rate limiter revealing others' activity | Rate limits are per-user only, never per-group (`04-API-CONTRACT.md` §8) |
| The 6:00 PM nudge push implying who else got one | Audience frozen at enqueue; body says nothing about others; a submitter receives silence, which carries no information |
| `submission_id` correlation across rounds | Cards addressed by `card_no` only (ADR-003) |
| Timing: a slower response when more people have submitted | The `open` handler's query cost does not depend on other users' rows. Do not add a `count(*)` "for logging". |
| Accessibility labels exposing counts | Covered in `12-ACCESSIBILITY.md` §2 and in the leak audit |
| Analytics / crash logs | There is no analytics SDK in v1. Do not add one. |

### The rule for future work

**Any new field on an `open`-phase response is a spec change.** Adding one requires updating
the golden file, which requires a human to look at it. That friction is the control.

---

## 4. Authorization

Edge Functions run with the service role, so **every handler does its own authorization.**
The base guards are fixed in `_shared/auth.ts`; the rounds handler's shared guess-eligibility
helper enforces steps 5–6 in both its read and write paths:

```
1. requireUser(req)              → user_id, or 401 UNAUTHENTICATED
2. requireProfile(user_id)       → or 409 NO_PROFILE
3. requireMembership(user_id)    → group_id, role, joined_at, or 409 NO_GROUP
4. requirePhase(round, [...])    → or 409 WRONG_PHASE
5. requireJoinedBefore(reveals)  → or 403 JOINED_LATE      (guessing only)
6. requireSubmitter(...)         → or 403 NOT_A_SUBMITTER  (guessing only)
```

- **The group is never taken from the request.** It comes from the caller's active
  membership (ADR-005). There is no `group_id` parameter anywhere in the client-facing API,
  <!-- ADR-011: from E18-01 there is one, and this section's guarantee is re-established by an
       explicit membership check on every group-scoped route, plus the non-member tests it names. -->
  so there is no IDOR surface for group data.
- `round_id` in a path is validated to belong to the caller's group before anything is read.
- RLS is deny-by-default on every table as a second lock. It is not the primary control and
  must not be relied on as one — a service-role client bypasses it. Its job is to make a
  mistake (a leaked anon key, a stray PostgREST call) fail closed.

---

## 5. Authentication

- Sign in with Apple via Supabase Auth. The client never sees a password because there isn't
  one.
- **The authorization asks for `.fullName` and nothing else.** App Review's guideline 4
  requires that a name the Authentication Services framework already supplied is not asked for
  again (rejection of 2026-09-21), so the first authorization's name becomes the display name
  and onboarding step 1.2 is skipped. The email scope is still never requested: the app sends
  no mail and stores no address. Apple supplies the name on the **first** authorization of an
  Apple ID only; every later one carries nothing, and the client only ever writes it when the
  server has said `NO_PROFILE`, so an existing name cannot be overwritten by signing in.
- Supabase's platform JWT gate is disabled for these functions so authentication failures can
  use the API's documented error envelope. This does not make a route public: every handler's
  first operation is `requireUser()`, and the release audit asserts every anonymous call
  returns 401 `UNAUTHENTICATED`.
- Access tokens are short-lived; refresh tokens live in the **Keychain** with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Never `UserDefaults`, never a file.
- Sign out unregisters the current APNs token, clears delivered notifications and local
  Spotify credentials, then revokes the Supabase refresh token server-side.
- Deleting an Apple-authenticated account requires a fresh Sign in with Apple code. The server
  verifies its subject against the current Supabase Apple identity, revokes Apple's resulting
  refresh token, and only then deletes the account. The code and token are never persisted.
- **Ex-member with a live token:** every handler resolves membership per request. A user
  whose `left_at` is set gets `NO_GROUP` on the next call, within the access-token lifetime
  at worst. Do not cache membership in the JWT.
- Phone OTP is behind a build flag and off in v1 (needs an SMS provider). If enabled later it
  needs its own rate limiting — SMS is a cost-amplification target.

---

## 6. Secrets

| Secret | Where it lives | Never |
|---|---|---|
| Apple Music `.p8` private key | Supabase function secret | In the app bundle, in the repo |
| APNs `.p8` private key | Supabase function secret | In the app bundle, in the repo |
| Sign in with Apple `.p8` private key | Supabase function secret | In the app bundle, in the repo |
| Supabase service role key | Function environment only | In the app, in any client response |
| `SPOTIFY_CLIENT_SECRET` | Supabase function secret | In the app bundle — PKCE exists so it never has to be |
| `SPOTIFY_CLIENT_ID` | `Info.plist` (public by design) | — |
| User's Spotify tokens | Device Keychain | On our server. We never store a user's third-party credentials. |
| User's Apple Music token | MusicKit-managed | Our server |

Rotation: Apple Music developer token regenerates from the `.p8` every 180 days maximum,
in-process. APNs JWT regenerates every 50 minutes. If a `.p8` leaks, revoke in the Apple
developer portal and issue a new key — no app update required, because neither key ships in
the binary.

---

## 7. Input handling

- Every body validated against an explicit schema. Unknown keys are **rejected**, not ignored
  — a silently-ignored key is how a future field becomes a vulnerability.
- `display_name`: trimmed, 1–24 chars, control characters and newlines stripped. Rendered as
  text, never as markup. Zero-width and RTL-override characters stripped (a display name that
  reorders the guess sheet is a real prank vector).
- `invite_code`: matched against `^[A-Z2-9]{6}$` after uppercasing, against the restricted
  alphabet in `03-DATA-MODEL.md`.
- `timezone`: validated against `pg_timezone_names`. Never interpolated into SQL.
- Track input: only `apple_music_id` (digits), `isrc` (`^[A-Z]{2}[A-Z0-9]{3}\d{7}$`), or a URL
  matching an allowlist of Spotify/Apple Music host patterns. No arbitrary URL is ever
  fetched server-side — that is an SSRF hole.
- All SQL through parameterised queries. No string interpolation, ever, including in the
  plpgsql functions.

---

## 8. Abuse

| Vector | Control |
|---|---|
| Invite-code brute force | 31⁶ ≈ 8.9e8 codes; 10/hour per user, 30/hour per IP |
| Search-endpoint abuse (our Apple quota) | 30/min per user, 10-minute edge cache |
| Submission spam / replacement churn | 20/min; replacement is a no-op upsert, costs one row write |
| Guess-sheet spam | 60/min; debounced client-side at 600ms |
| Notification abuse | Impossible by construction — the outbox is written only by the tick job, never by a request handler |
| Account enumeration | Join by code returns the same `NOT_FOUND` for a bad code and a valid code the user can't use |
| Display-name impersonation | Duplicate names allowed and disambiguated in the UI (`08-SCREEN-SPECS.md` §6). Not a security control — this is a 10-person group, social enforcement is the control. |

---

## 8a. Export compliance

`ITSAppUsesNonExemptEncryption` is **`NO`**, declared in the build settings rather than answered
by hand on every upload. Without the key, App Store Connect parks each build in *Missing
Compliance* until somebody answers the question in the web UI — which is a submission that
silently does not happen, on the day it matters.

`NO` is the correct answer and not a convenient one. The app's only cryptography is HTTPS/TLS to
Supabase and Apple's own frameworks: the Keychain, and `CryptoKit`'s SHA-256 over the Sign in
with Apple nonce (`AppleSignIn.digest(of:)`), which is a hash rather than encryption. All of that
falls under the standard exemption. **Adding any encryption of our own — a bundled cipher, an
encrypted local store, anything that is not the platform's — makes this answer wrong**, and the
key has to change with it.

---

## 9. Privacy

- Data collected: Apple sub or phone, display name, group membership, song choices, guesses,
  APNs token. That is the complete list. The display name is either typed by the user or the
  given name Apple supplied at the first authorization; it is editable in settings either way,
  and no other field of Apple's name — no family name, no email — is requested or kept.
- **No analytics, no telemetry, no crash reporter with PII, no ad SDK, no device fingerprint.**
- The share card is generated only on explicit action, contains no IDs or join links, and its
  temp file is deleted after sharing (`10-SHARE-CARD-SPEC.md` §5).
- Account deletion is implemented as a real function (`03-DATA-MODEL.md` §6): the profile is
  anonymised to "Former member", auth is unlinked, and historical rows survive so other
  members' scores stay correct. Say this plainly in the settings copy before confirming.
- The public policy lives at `https://kingston-du.github.io/blind-drop-pages/privacy/`; Settings
  links to it and the same URL is supplied to App Store Connect.
- App Privacy nutrition label: *Data Linked to You* — Contact Info (name), User Content
  (songs), Identifiers. No tracking.

---

## 10. Audit checklist — run before every release

- [ ] `npm run audit:leak` passes: `open`-phase payloads match golden files byte for byte
- [ ] Authenticated and anonymous PostgREST calls to every table fail with `42501 permission denied`
- [ ] Anonymous call to every Edge Function returns 401
- [ ] A member of group A cannot read any resource of group B (path-fuzzed with real UUIDs)
- [ ] An ex-member's live token is rejected with `NO_GROUP`
- [ ] `GET /rounds/current` during `open` is byte-identical for a user who has submitted and
      one who has not, apart from `my_submission` and `server_now`
- [ ] Response time for `GET /rounds/current` during `open` shows no correlation with the
      number of submissions (100 samples across 0–12 submitters)
- [ ] No secret in the built `.ipa` (`strings` grep for key prefixes and for
      `SPOTIFY_CLIENT_SECRET`)
- [ ] No `Date()` outside `ServerClock`
- [ ] No new field on any `open`-phase DTO since the last release
