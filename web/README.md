# web/ — the one web surface

`docs/16` §3: *"`https://blinddrop.app/j/<CODE>` — an invite landing page with an
`apple-app-site-association` file, falling back to showing the code for manual entry. It is a
static page. It has no login, no group data, and no content beyond the code and an App Store
link."*

This directory holds the part of that surface the **app** depends on. The landing page itself
is not built here and is not an E09 deliverable — E09-04 needs the association file, because
without it `applinks:blinddrop.app` in `ios/BlindDrop/BlindDrop.entitlements` claims a domain
that does not answer, and every invite link opens Safari instead of the app.

## `.well-known/apple-app-site-association`

Serving requirements, all of which Apple enforces and none of which are negotiable:

| Requirement | Value |
|---|---|
| URL | `https://blinddrop.app/.well-known/apple-app-site-association` |
| `Content-Type` | `application/json` |
| Extension | none — the file has no `.json` suffix |
| Redirects | none; Apple follows none |
| TLS | valid certificate, no client certificate |

`appIDs` is `<TEAM_ID>.com.blinddrop.app`. The prefix is written as `$APP_ID_PREFIX` because
the team identifier is not assigned yet — the same state `SUPABASE_ANON_KEY` and
`SPOTIFY_CLIENT_ID` are in, and **E14-05** is where all three are filled in. Substitute it at
deploy time; a literal `$APP_ID_PREFIX` in a served file matches no app and silently disables
every universal link.

The path claim is `/j/*` and nothing else. The entitlement can only claim a whole domain, so
this file is the only place the app's reach into `blinddrop.app` is actually narrowed —
`App/DeepLink.swift` narrows it a second time on the client, and refuses any URL on the domain
that is not `/j/<CODE>`.
