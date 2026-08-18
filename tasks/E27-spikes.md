# E27 — Spikes

Investigations, not implementations. Each produces a written recommendation in this file and a
decision the owner makes; none of them writes product code. A spike that ends "we should not
build this" has succeeded.

Keep them short. A spike that takes longer than the thing it is investigating has failed
differently.

---

### E27-01 — Opening a song in Spotify

**Status:** todo · **Deps:** — · **Parallel:** yes
**Reads:** `docs/06` §2, §4, §6
**Touches:** this file
**Verify:** a recommendation, and a task written or a decline recorded

Songs are identified by `track_key`, resolved from Apple, with Spotify already reached by
client-credentials ISRC lookup and `track_links` backfilled in the tick (`E07-04`, `E07-05`).
`TrackLinks` and `TrackUtilityMenu` already exist, so a chunk of the work may already be done.

Establish: what fraction of real catalogue actually resolves by ISRC; what happens on the misses;
whether opening needs the app installed and what a person without it should see; whether the
existing backfill covers the cases the UI would need. `docs/06` §6's note about Spotify
development mode being capped at five users applies to *authenticated* calls — check whether it
constrains this at all, since opening a link may not need auth.

- [ ] Coverage measured against real tracks, not assumed
- [ ] Miss behaviour decided
- [ ] Recommendation: build now, build later, or do not build — with the reason
- [ ] If build: a slice written into the right epic

---

### E27-02 — Pick for me

**Status:** todo · **Deps:** — · **Parallel:** yes
**Reads:** `docs/06` §1, §3, `docs/16` §3
**Touches:** this file
**Verify:** a recommendation

Offering a few songs from the user's own library when they are stuck. **Never automatic** — the
user chooses deliberately before sealing, or the game stops being about taste.

Establish: whether the user's library is reachable at all under `docs/16` §3's ban on client
MusicKit and ADR-002's server-side proxy — which may make this infeasible without a decision the
architecture deliberately avoided. If it needs client MusicKit, that is the finding, and it is a
bigger question than a helper feature justifies.

Also worth asking whether the problem is real: does anyone in the beta actually fail to drop
because they cannot think of a song, or do they just drop late? Recently Played and Forgotten
Favourites are variations to note, not to design yet.

- [ ] Feasibility under ADR-002 and `docs/16` §3, stated plainly
- [ ] Whether the beta shows evidence the problem exists
- [ ] Recommendation, with the architectural cost if it is not free

---

### E27-03 — A web page

**Status:** todo · **Deps:** — · **Parallel:** yes
**Reads:** `docs/16` §3 *The one web surface*, `web/README.md`
**Touches:** this file
**Verify:** a recommendation naming stack, repository and host, or a decline

`web/` today holds a README and an `apple-app-site-association` file — the invite landing page
`docs/16` §3 allows, and nothing else.

Decide first **whether the beta needs anything more**, because it may not: TestFlight has its
own install path and the landing page already handles invite links. If the answer is a
single-page site with a name, a screenshot and a TestFlight link, then that is the requirement,
and it wants a static file and a host, not a framework.

Only after the requirement is written should the stack be chosen — from what the page actually
does, the maintenance it adds to a repository that currently has zero third-party dependencies,
and cost. Vercel and Heroku were both mentioned; a static page needs neither of them
particularly. Same repo or separate is part of the recommendation: `web/` already exists here,
and the AASA file must stay in sync with the app's associated domains, which argues for one repo.

Do not pick a framework because it is what people use.

- [ ] The requirement written before any stack is named
- [ ] Same-repo vs separate decided, with the AASA coupling weighed
- [ ] Host and stack justified by the requirement, cost and maintenance
- [ ] Recommendation, or a recorded decline with the reason

---

### E27-04 — Themed prompts

**Status:** todo · **Deps:** — · **Parallel:** yes
**Reads:** `docs/16` §1, §2, `tasks/ICEBOX.md`
**Touches:** this file
**Verify:** a recommendation

*"A song that reminds you of summer."* The nullable `Round.prompt` column exists and is the
entire allowance — no DTO field, no UI, and `docs/16` §2 says to stop if you find yourself
adding one.

This is product experimentation, not a feature to expand into. A prompt changes the game from
taste-reading to prompt-answering, which is a different game and might be a better one — but
that is a thing to test with a few rounds and a few people, not to build a system for.

Establish whether the beta gives any evidence that the unprompted round goes stale, what the
smallest honest test looks like, and what it would cost to reverse. Broader anonymous content
types are out of scope for this beta and stay out.

- [ ] Evidence from the beta, or the absence of it, stated
- [ ] The smallest test that would answer the question
- [ ] Recommendation — test, defer, or drop
