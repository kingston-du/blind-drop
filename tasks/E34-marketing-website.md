# E34 — Marketing website (separate repo)

One slice, from `docs/17-NEXT-FEATURES.md` §9. Most of this epic's work happens **outside this
repository** and is not tracked here beyond the one obligation this repo carries.

---

### E34-01 — Coordinate this repo's half

**Status:** wip
**Deps:** —
**Parallel:** yes
**Reads:** `docs/17-NEXT-FEATURES.md` §9, `docs/16-OUT-OF-SCOPE.md` §3, `tasks/E27-spikes.md`
(`E27-03`'s already-decided requirement), `web/README.md`
**Touches:** `web/README.md` (a pointer to wherever the new site's repo lives, once it exists)
**Verify:** Manual: after the new site is deployed, confirm
`https://blinddrop.app/.well-known/apple-app-site-association` still resolves correctly from
whatever host now serves the domain.
**Proves:** —

`E27-03` already decided the requirement: a single static page at `https://blinddrop.app/j/<CODE>`
(and reasonably the bare domain) — app name, one screenshot, one line of copy, a TestFlight install
link (swap for the App Store link at release), falling back to the raw code if the universal link
doesn't resolve. No login, no group data, no form. Build it in a **new, separate repository**,
plain static HTML/CSS, no framework — per the spike's own recommendation. `blind-drop/web/` stays
exactly as it is; it exists only to hold `apple-app-site-association`.

- [ ] Confirm the new site's host does not disturb
      `blinddrop.app/.well-known/apple-app-site-association` — either it also serves that file
      unchanged, or DNS/reverse-proxy routing sends `.well-known/*` back to wherever it's served
      today. **Blocked on deployment**, which needs the owner's Vercel account and the domain.
- [x] `web/README.md` gets a one-line pointer to the new repo, so the next person doesn't go
      looking for the marketing site in this one.
- [ ] Anything beyond the single page (more pages, a blog, a waitlist form, broader marketing copy)
      reopens `E27-03`'s "no" and needs a fresh owner decision — out of scope for this slice.

> **Finding (E34-01), 2026-08-31.** The coordination requirement above assumes something serves
> `apple-app-site-association` today and the new host must avoid disturbing it. Nothing does:
> `dig @8.8.8.8 blinddrop.app NS` returns `NXDOMAIN`, so the domain is not registered and
> `web/.well-known/apple-app-site-association` has never been live. The requirement therefore
> inverts — the new site is the first thing on the domain and must **serve** that file, not
> route around it. It carries a byte-identical copy, and `verify.sh` in the site repo diffs the
> deployed file against it, since two copies of that file are the one thing in this arrangement
> that can drift silently. `web/`'s copy stays the source of truth.
>
> Two shipped features are waiting on the same registration, which is worth stating plainly
> because neither is obvious from this epic: `applinks:blinddrop.app` in
> `ios/BlindDrop/BlindDrop.entitlements` means universal links resolve on that domain and no
> other, so the association file is inert on a `*.vercel.app` address and `/j/<CODE>` can only
> offer the code for manual entry; and `SpotifyAuth.swift`'s callback
> `https://blinddrop.app/spotify-auth` has nowhere to land, which is the deferral already
> recorded in `docs/RELEASE-2026-08-12.md`.
>
> **Owner decision, recorded.** Host is **Vercel** on a free `*.vercel.app` address for now,
> with the domain deferred. `E27-03` recommended Cloudflare Pages, and the deciding factor it
> named — per-path control of the association file's `Content-Type` — turns out not to
> discriminate, since `vercel.json` does it too; the remaining argument was buying the domain at
> Cloudflare's registrar, which the deferral moots. `_headers` is kept alongside `vercel.json`
> so the swap stays a one-file decision.
>
> The site is built and pushed to <https://github.com/kingston-du/blinddrop-site>. This slice
> stays `wip` rather than `done` because its **Verify** line is a live-deployment check and the
> site is not deployed yet.
