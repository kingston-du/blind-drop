# Fixture server

Canned responses for every endpoint in `docs/04-API-CONTRACT.md`. This exists so the iOS lane
(`E08` onward) can be built and tested without the backend, and so phase testing is instant
and deterministic instead of requiring a real 8 PM.

**A fixture that drifts from the contract is worse than no fixture.** `payloads/*.json` are
the contract verbatim — `server.ts` only wraps them in the envelope, stamps `server_now`, and
routes. When `docs/04` changes, change the payload file in the same commit.

## Running it

```bash
cd ios/Fixtures
PHASE=open ../../server/node_modules/.bin/deno run --allow-net --allow-read --allow-env server.ts
```

Deno comes from `server/node_modules` (`cd server && npm install`), so there is nothing to
install globally. A `deno` already on `PATH` works too.

| env | default | effect |
|---|---|---|
| `PHASE` | `open` | which `/rounds/current` payload to serve |
| `PORT` | `8787` | |
| `LATENCY_MS` | `0` | delay on every response — this is how the 400ms search budget in AC-10 gets exercised |
| `ANCHOR` | `now` | `now` re-times the round around `server_now` so countdowns are live; `fixed` serves the literal timestamps in the payload files |

### Phases

| `PHASE` | Serves | Exists to cover |
|---|---|---|
| `open` | `round_open.json` | sealed card + countdown |
| `open_nosub` | `round_open_nosub.json` | the submit invitation, `my_submission: null` |
| `open_darkhours` | `round_darkhours.json` | "Tonight's round is done." — an `open` round that has **not** opened yet, carrying `previous_cue` beside its own `cue` so the screen can show last night's and not the coming one, plus `previous_round_id` so **See last night's results** is there and lands on that night's answers (docs/18 §7) |
| `voided` | `round_voided.json` | AC-4 — your song comes back, no count of anyone else |
| `revealed` | `round_revealed.json` | the guess sheet, 8 cards, `my_card_no: 4` |
| `revealed_nosub` | `round_revealed_nosub.json` | AC-6 — `can_guess: false`, `not_a_submitter` |
| `revealed_joinedlate` | `round_revealed_joinedlate.json` | AC-6 — `joined_late` |
| `scored` | `round_scored.json` | base keys only; the client then calls `/rounds/{id}/results` |

`GET /__fixture` reports the running configuration.

## Supabase Auth (E09-01)

Sign in with Apple exchanges Apple's identity token for a Supabase session, and Supabase Auth
is a **sibling** of the functions service rather than a route inside it. So the fixture also
answers two GoTrue routes, in GoTrue's own shapes — no `docs/04` §1 envelope, no `server_now`:

| Route | Behaviour |
|---|---|
| `POST /auth/v1/token?grant_type=id_token` | 400 unless `provider: "apple"`, `id_token` and `nonce` are all present; otherwise a session |
| `POST /auth/v1/token?grant_type=refresh_token` | Rotates. Spending a token twice is a 400 `invalid_grant`, exactly as Supabase behaves — which is what makes a client that refreshes twice on one 401 fail visibly |
| `POST /auth/v1/logout?scope=local` | 204, or 401 without a bearer |

The client derives the auth address from `-apiBaseURL` (`…/functions/v1` → `…/auth/v1`, or
`/auth/v1` appended), so one launch argument still points a whole run here.

**These routes are not an auth gate.** Everything else in this file answers anyone; the fixture
is the contract, canned, not a copy of the server's authorization pipeline. `docs/14` §10's
"every anonymous call returns 401" is audited against the real functions, not against this.

`ios/scripts/verify-signin.sh` starts this server and runs
`BlindDropUnitTests/FixtureSignInTests` against it — the real `SupabaseAuthService`, the real
`Keychain` and the real `APIClient`, with only Apple's sheet stubbed.

## What the payloads contain

One group ("The Cove", `America/New_York`, reveal hour 20, invite code `K7MQ2X`), nine
people (Ana…Ivy), and the `docs/02` §4.4 round: 8 submitters, Ivy sat out, Ana and Ben both
dropped *Ribs*. The caller is **Ana**.

`results.json` carries the §4.4 numbers, so the results screen can be built against
hand-checked values. Two of them differ from §4.4 as printed, for the reason recorded in
`server/supabase/seed.sql`'s header: §4.4 as printed is unsatisfiable, and the repair is
Gus's readability 0 → 1 and Hal's 5 → 4. `results.json` and `seed.sql` must agree.

Note the two cases that are easy to get wrong and are therefore in the fixture:

- **Eli's `ear` is `null`, not `0`.** Eli submitted and guessed nothing. `null` means *not
  applicable*. Rendering it as "0%" turns "you sat out" into "you scored nothing", which is
  the one judgement the product refuses to make (`docs/04` §4).
- **`standings.readability` has no `rank` field.** Only `best_ear` is ranked. A client that
  receives a rank will render one (`docs/04` §4, `docs/02` §4.5).

ISRCs and Apple/Spotify ids are plausible-shaped fixtures, not live catalog ids. Artwork URLs
are `{w}x{h}` templates so `ArtworkView`'s sizing logic gets exercised; they do not resolve to
real images, which is what makes the placeholder path testable.

## Wiring it to the app

The test harness launches this server before the scheme; the UI target passes
`-apiBaseURL http://127.0.0.1:8787`, which `AppEnvironment` honours (`E08-01`). Nothing else
in the app knows the fixture exists.
