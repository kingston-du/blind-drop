# E34 — Marketing website (separate repo)

One slice, from `docs/17-NEXT-FEATURES.md` §9. Most of this epic's work happens **outside this
repository** and is not tracked here beyond the one obligation this repo carries.

---

### E34-01 — Coordinate this repo's half

**Status:** todo
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
      today.
- [ ] `web/README.md` gets a one-line pointer to the new repo, so the next person doesn't go
      looking for the marketing site in this one.
- [ ] Anything beyond the single page (more pages, a blog, a waitlist form, broader marketing copy)
      reopens `E27-03`'s "no" and needs a fresh owner decision — out of scope for this slice.
