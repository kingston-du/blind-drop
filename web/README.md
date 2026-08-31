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

`appIDs` is `<APP_ID_PREFIX>.com.blinddrop.app`. This repository uses the current Kingston Du
App ID Prefix, `NNQ4DT9Z7Q`; verify it against the production provisioning profile if the Apple
account changes. A mismatched prefix silently disables every universal link.

The path claim is `/j/*` and nothing else. The entitlement can only claim a whole domain, so
this file is the only place the app's reach into `blinddrop.app` is actually narrowed —
`App/DeepLink.swift` narrows it a second time on the client, and refuses any URL on the domain
that is not `/j/<CODE>`.

## Where the landing page lives

Not here. The page served at `blinddrop.app/j/<CODE>` and at the bare domain is
**<https://github.com/kingston-du/blinddrop-site>** (`E34-01`, `docs/17` §9). This directory
still exists only to hold the association file above.

That repository carries its own copy of `apple-app-site-association`, because it is what will
serve the domain. **This file is the source of truth**: the App ID prefix here has to match the
production provisioning profile and the `applinks:blinddrop.app` entitlement, and the copy has
to match this file. `verify.sh` in the site repo diffs the deployed file against its copy,
which is the check that catches drift.
