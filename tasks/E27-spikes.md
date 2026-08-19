# E27 — Spikes

Investigations, not implementations. Each produces a written recommendation in this file and a
decision the owner makes; none of them writes product code. A spike that ends "we should not
build this" has succeeded.

Keep them short. A spike that takes longer than the thing it is investigating has failed
differently.

---

### E27-01 — Opening a song in Spotify

**Status:** done · **Deps:** — · **Parallel:** yes
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

- [ ] Coverage measured against real tracks, not assumed — **not satisfiable by this
      documentation-only spike as scoped**; findings name the one query that would answer it
      and hand it to the follow-up audit slice as its first step
- [x] Miss behaviour decided
- [x] Recommendation: build now, build later, or do not build — with the reason
- [ ] If build: a slice written into the right epic — **deliberately not written here**; the
      findings recommend a short audit slice but leave writing it into an epic for the owner's
      go-ahead, same as `E27-03`

> **Findings (E27-01).**
>
> **Coverage.** No real number came out of this spike — it is documentation-only and there is
> no route from here to a live `track_links` table. `docs/06` §5 (adjacent to the read sections,
> already implemented per `E07-04`/`E07-05`) only commits to a qualitative claim: *"Expected hit
> rate is high but not 100%. Regional exclusives and very new releases miss."* That is a
> design-time estimate, not a measurement, and "coverage measured against real tracks, not
> assumed" cannot be satisfied by this spike as scoped — it needs one query
> (`select count(*) filter (where spotify_id is not null), count(*) filter (where unresolvable),
> count(*) from track_links`) against real data, which is cheap and should be step one of the
> build slice below, not a separate spike.
>
> **Miss behaviour is already decided, in the doc.** `docs/06` §7's degradation matrix: when
> `spotify_url == null` at render, *"the Open in Spotify button is absent, not disabled."* No
> new decision needed — the existing rule already covers a track that never resolves.
>
> **App-not-installed is already decided too.** §6/§5's linking rule: try `spotify:track:{id}`
> first (opens the app directly); if `UIApplication.canOpenURL` says no, fall back to
> `https://open.spotify.com/track/{id}`. A person without the app lands on Spotify's own web
> player, which is Spotify's problem to present, not ours to build a fallback screen for.
>
> **The five-user development-mode cap does not apply.** It sits under §6's *Spotify export*
> subsection and is scoped explicitly to *authenticated* PKCE calls that write to a user's own
> account (creating a playlist). Opening `spotify:track:{id}` or `open.spotify.com/track/{id}`
> is an unauthenticated deep link / universal link the OS resolves — no OAuth, no dashboard
> allowlist, no Premium requirement. It does not constrain this feature at all, and the epic's
> own instinct to double-check was correct: it isn't a shared budget with export.
>
> **Whether the backfill covers what the UI needs.** Per §5 (again adjacent, already built):
> resolution is attempted inline at submission (700ms budget) and then retried in the
> `tick_rounds()` minute, up to 20 rows per tick, up to 3 attempts before `unresolvable = true`.
> Between a submission during `open` and that round's `reveal`, there are multiple tick cycles —
> so by the time a card is visible to guess against, most resolvable tracks should already carry
> a `spotify_id`. This is a data-layer fit for the use case, not a gap.
>
> **Recommendation: build now — likely already mostly built.** Every piece of infrastructure this
> needs (`track_key`, `track_links`, the inline + backfill resolver, the null-safe
> `spotify_url` field on the Track DTO, the documented miss/no-app behaviour) is already in
> place per `E07-04`/`E07-05`, and the epic text names `TrackLinks` and `TrackUtilityMenu` as
> existing iOS components. This spike did not open that Swift code (out of scope per its `Reads`
> field), so the honest next step is **not** a from-scratch build — it is a short audit slice:
> confirm `TrackUtilityMenu`/`TrackLinks` already render **Open in Spotify** per §5's rule
> (`spotify:` first, HTTPS fallback, absent not disabled when null) on every screen that shows a
> track (reveal card, results, The Record), pull the real `track_links` coverage number as a
> byproduct, and close any gap found. If it turns out already fully wired, the slice closes
> as a verification with no code change. Either way this is small, additive, and needs no
> architecture decision — but per this task's constraints, the slice itself is not written into
> another epic here; that addition needs the owner's go-ahead (same pattern as the amendments
> recorded in `E17-05`/`E17-07`, just without a rule change attached this time).

---

### E27-02 — Pick for me

**Status:** done · **Deps:** — · **Parallel:** yes
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

- [x] Feasibility under ADR-002 and `docs/16` §3, stated plainly
- [x] Whether the beta shows evidence the problem exists
- [x] Recommendation, with the architectural cost if it is not free

> **Findings (E27-02).**
>
> **Feasibility.** Checked `docs/01-ARCHITECTURE.md` ADR-002 directly (it is the actual source
> of the rule the epic text calls "`docs/16` §3's ban on client MusicKit" — `docs/16` §3 doesn't
> spell that ban out itself; ADR-002 does, and it's what actually governs this). ADR-002's
> decision: Apple Music search/metadata/previews come from **our server**, with our developer
> token, catalog-only. The client uses MusicKit for exactly one thing — Apple Music playlist
> export — and ADR-002 explicitly **rejected** client-side MusicKit for search because of "a
> denied prompt at second 10 of a 90-second loop." A developer-token JWT has no access to any
> user's personal library; there is no server-side path to "songs this user has saved." The
> only route to a user's Apple Music library is client MusicKit with
> `MusicAuthorization.request()` — the exact mechanism, and the exact permission-prompt risk,
> ADR-002 rejected, and "Pick for me" would trigger it during the same submission window ADR-002
> was protecting.
>
> The Spotify side doesn't offer a free path either. `docs/06` §6's existing PKCE flow only
> requests `playlist-modify-private playlist-modify-public`, is opt-in, and only runs when a
> user chooses to export — most users may never have connected Spotify at drop time, and Apple
> Music is the app's default engine (ADR-002). Reading a user's saved tracks needs a broader
> scope (`user-library-read`) and an OAuth round trip on the sealing path for every user who'd
> use the feature, not just exporters. That also drags in `docs/06` §6's five-authenticated-user
> Spotify development-mode cap for real, unlike `E27-01`'s plain link-opening — a "Pick for me"
> powered by Spotify would need every beta tester to be an allowlisted authenticated account
> before the feature works for them at all.
>
> Either path — client MusicKit prompting mid-drop, or mandatory early Spotify auth — reopens a
> decision ADR-002 deliberately closed. This is not a free feature; it is an architecture
> amendment wearing a helper feature's clothes, exactly as the epic text predicted.
>
> **Evidence from the beta.** None available to this spike. `docs/16` §3 explicitly bans
> analytics, telemetry, and any crash reporter with PII in v1 — there is no instrumented signal
> for "opened Submit, sat there, gave up" versus "dropped late," and this investigation has no
> channel to the owner's or testers' anecdotal impressions either (it is a documentation-only
> read, per its `Reads` field). So the honest statement is: **absence of evidence, not evidence
> of absence** — nothing here confirms or denies that anyone actually struggles to think of a
> song, because nothing in the product is instrumented to say.
>
> **Recommendation: do not build.** The architectural cost is not free — it requires either
> reopening ADR-002 (client MusicKit on the critical submission path, the specific prompt-timing
> risk it was written to avoid) or making Spotify OAuth a near-mandatory step for a helper
> feature, which the five-user pilot cap makes actively worse during the beta. Paying that cost
> needs stronger justification than "seems plausible," and no evidence exists — because none can
> exist under the current no-analytics rule — that the problem is real enough to justify it.
> Recently Played and Forgotten Favourites are downstream variations of the same infeasible base
> and don't change the answer. If the owner has independent anecdotal signal from the pilot that
> people are actually failing to drop (not just dropping late), that would be the trigger to
> revisit — but reopening ADR-002 is an owner call, not this spike's to make, consistent with how
> `E17-05`/`E17-07` recorded owner-level amendments rather than performing them.

---

### E27-03 — A web page

**Status:** done · **Deps:** — · **Parallel:** yes
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

- [x] The requirement written before any stack is named
- [x] Same-repo vs separate decided, with the AASA coupling weighed
- [x] Host and stack justified by the requirement, cost and maintenance
- [x] Recommendation, or a recorded decline with the reason

> **Findings (E27-03).**
>
> **Does the beta need anything more than the landing page? No.** `docs/16` §3 gives the entire
> allowance already: a static page at the invite path, no login, no group data, nothing beyond
> the code and an install link. TestFlight has its own install/accept flow independent of any
> web page, so this page's only job is the moment before that: someone taps a `/j/<CODE>` link,
> the app isn't installed yet, and they land somewhere that isn't a dead Safari error. Nothing
> in the beta calls for more than that.
>
> **The requirement, written before any stack:** a single static page, served at
> `https://blinddrop.app/j/<CODE>` (and reasonably at the bare domain too), showing the app
> name, one screenshot, one line of copy, and an install link — a **TestFlight** public link for
> now, since there is no App Store listing yet; swap it for the App Store link at release. If the
> app isn't installed (universal link fails through to the browser) the page also shows the raw
> code as `web/README.md` already promises ("falling back to showing the code for manual entry").
> No account, no group data, no form, no submission of anything. That is the whole page.
>
> **Same repo.** `web/` already exists here and already holds the `apple-app-site-association`
> file the app's `applinks:blinddrop.app` entitlement depends on (`web/README.md`; wired for
> `E09-04`). A landing page hosted elsewhere would split the one thing that must never drift —
> the AASA's `appIDs`/path claim and the app's actual entitlements/Team ID — across two
> repositories with no shared review. One repo means one PR changes both when either changes,
> and the App ID prefix note in `web/README.md` ("verify it against the production provisioning
> profile if the Apple account changes") stays a single place to check. Separate repo has no
> offsetting benefit for a page this small.
>
> **Stack: no framework.** One HTML file and a stylesheet. The requirement above has no state,
> no routing beyond "read the code out of the path," and no interactivity beyond an install
> link — at most a few lines of vanilla JS to read `window.location.pathname` and drop the code
> into the fallback text. Reaching for a framework (Next.js, or anything with a build step) adds
> a dependency and a build pipeline to a repository whose entire Swift and TypeScript layers
> currently run on zero third-party dependencies (`CLAUDE.md` §4) — pure scope creep for one
> page. "Do not pick a framework because it is what people use" is the epic's own instruction,
> and it applies directly here.
>
> **Host: decline both named options.** Neither Vercel nor Heroku is a good fit, and the epic
> text's own hedge — "a static page needs neither of them particularly" — holds up:
> - **Heroku** is a dyno-based platform for apps with server processes. It has had no meaningful
>   free tier since November 2022, and there is no server-side logic here to run. Wrong shape
>   entirely; decline.
> - **Vercel** can serve a static page, but it's a framework-forward platform (its own default
>   is Next.js) — more surface and more temptation toward "just add a build step" than one
>   static page justifies, with no advantage over a plainer static host for a page this size.
> - **Recommended instead: Cloudflare Pages.** Free for a project this size, git-connected
>   (deploys straight from `web/` on push), automatic TLS on the custom domain, and — the
>   deciding factor — a `_headers` file gives explicit, versioned control over the response
>   headers for one path. That matters because `web/README.md` lists `Content-Type:
>   application/json` and "no redirects" as non-negotiable for the AASA file, and that is
>   exactly the kind of per-path header control some static hosts (GitHub Pages among them)
>   don't expose without extra machinery. Cloudflare Pages sets it in one file, checked into the
>   same repo as the requirement it's satisfying.
>
> **Recommendation: build — the single static page described above, in `web/`, deployed to
> Cloudflare Pages, no framework.** This is small enough that it does not need a slice written
> elsewhere by this spike; per this task's constraints, the concrete build is left for the owner
> to schedule (it is not a rule amendment, so unlike `E27-05` it doesn't need a `CLAUDE.md`
> change — just a go-ahead to add the page and wire up the host).

---

### E27-04 — Themed prompts

**Status:** done · **Deps:** — · **Parallel:** yes
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

- [x] Evidence from the beta, or the absence of it, stated
- [x] The smallest test that would answer the question
- [x] Recommendation — test, defer, or drop

> **Findings (E27-04).**
>
> **Evidence.** None available to this spike, and for the same structural reason as `E27-02`:
> `docs/16` §3 bans analytics and telemetry in v1, so there is no instrumented signal for
> "unprompted rounds feel stale" versus "people are fine" — only what the owner or testers might
> say directly, which this documentation-only investigation has no channel to. `tasks/ICEBOX.md`
> already carries a "Themed prompts" entry noting this and marking it "frozen until that spike
> says otherwise" — so the absence of evidence isn't new here, it was already the recorded state
> going in.
>
> **The smallest honest test needs no app change at all.** The entire allowance in the app today
> is the nullable `Round.prompt` column (`docs/16` §2) — no DTO field, no UI, and the doc's own
> instruction is to stop if either gets added. But the question — does a themed round change
> anything about how a round plays — doesn't need the column, the DTO, or any UI to answer. The
> group already has a chat (the same one `docs/16` §1 points to for the declined "reactions"
> idea): an admin or the owner can simply post *"tonight's round: a song that reminds you of
> summer"* into that chat before a round opens, entirely out-of-band, with zero lines of code
> changed. Run it for one or two rounds in one or two willing circles and watch, informally,
> whether it changes anything — more submissions, earlier submissions, different chat energy
> after reveal, or someone asking "wait, are we doing themes now?" That is a strictly smaller
> test than building even the `RoundDTO` field this doc forbids, and it directly answers the
> product question (taste-reading vs. prompt-answering) without touching the codebase.
>
> **Cost to reverse: none.** A chat message is not a migration, a DTO field, or a UI string —
> there is nothing to revert. This is the cheapest possible way to learn whether the idea has
> legs before any engineering is spent, which is exactly what `docs/16` §2's "entire allowance"
> line is protecting against being outrun.
>
> **Recommendation: test — out-of-band, not a build.** Have the owner (or a willing circle) run
> the group-chat version of a themed round for a round or two and see what happens. If it
> produces a real signal that unprompted rounds go stale — not a guess, an actual observation
> from those rounds — that becomes the evidence to bring back before spending a slice on the
> `RoundDTO` field and UI `docs/16` currently forbids. Until then this stays exactly where
> `tasks/ICEBOX.md` already has it: frozen. This spike doesn't change that entry itself (out of
> this task's scope — `ICEBOX.md` is touched only if `E27-05` is declined), but the entry's own
> language ("decide whether to test it, on evidence from the beta, before anyone builds a prompt
> UI") is now answered: test it out-of-band first, evidence still absent otherwise.

---

### E27-05 — Streaks

**Status:** done · **Deps:** — · **Parallel:** yes
**Reads:** `CLAUDE.md` §2.7, `docs/16` §3, `docs/02` §4
**Touches:** this file
**Verify:** a recommendation, or an owner amendment recorded if the answer is yes

**This is a question, not a green light.** `CLAUDE.md` §2.7 is explicit: *"No gamification. No
streaks, badges, XP, levels, or cosmetics."* `docs/16` §3 repeats it. Neither is an agent's call
to override, and this slice does not implement anything — it is the investigation the owner
asked for, so that a yes or a no is a recorded decision rather than a drift.

Two shapes get asked about separately, because they fail differently. A **player streak**
("dropped N days running") is the closer of the two to what §2.7 already names and rejects by
design — it is a personal counter that goes up, which is the template the rule exists to block,
and turns a missed evening into a loss rather than a non-event. A **circle streak** ("the circle
has completed N rounds running") is a fact about the group's participation rather than a score
on a person, which is a different question — closer to the minimum-submitters mechanic that
already exists than to a badge.

Ask, for each shape: what does it change about why someone opens the app — is it still "there's
a song from my circle" or does it become "don't break the chain"? What does a broken streak look
like on screen, and does that screen become the thing a lapsed player dreads seeing, which is
the actual mechanism `docs/16`'s progression-system ban is defending against? Does either
survive multi-circle — a streak per circle, or one across all of them, and does the second
quietly punish having several?

- [x] Player streaks and circle streaks assessed separately, not as one feature
- [x] What each does to the reason someone opens the app on a day they would rather skip
- [x] Recommendation: build, and get the owner's explicit `CLAUDE.md` §2.7 amendment first
      (naming what changed, the way E17-05/07 did), or decline and say why
- [x] If declined, a line added to `tasks/ICEBOX.md` so the question does not get re-asked cold

> **Findings (E27-05).**
>
> **Player streaks — decline, not close.** `CLAUDE.md` §2.7 names "streaks" first in an
> unqualified list; `docs/16` §3 repeats it and adds the reasoning: *"The two numbers are
> readability and ear. That is the entire progression system."* A player streak is the literal
> shape the rule was written about — a personal counter that only goes up until it doesn't. What
> it changes about why someone opens the app is exactly the failure mode the epic names: on an
> evening someone would rather skip, "there's a song from my circle" (an invitation) becomes
> "don't break the chain" (an obligation) — and `docs/02` §4.1 shows the game already made the
> opposite choice on purpose. A member who opens the app and makes **zero guesses** gets `ear`
> excluded from that round entirely — *"It is not a zero"* — a deliberate refusal to let a lapse
> read as a negative data point. A player streak's whole premise is a screen where a lapse *is*
> the negative data point, on purpose, in the biggest font on the page. That's a direct reversal
> of a design decision already made and documented. Multi-circle makes it worse either way it's
> built: a streak per circle multiplies the number of chains a person can feel they're dragging
> (three circles, three ways to fail an evening), and a single streak across all circles
> "quietly punishes having several" exactly as the epic predicted — the more circles someone
> joins, the more ways there are to miss at least one and break the combined count, which
> punishes the exact multi-circle behaviour `E18`–`E21` were just built to support. There is no
> framing of a player streak that survives contact with either §2.7 or the existing scoring
> philosophy. Not worth proposing an amendment for.
>
> **Circle streaks — also decline, but for a different, weaker reason.** "The circle completed N
> rounds running" is a fact about the group's participation, not a score on a person — closer in
> shape to the minimum-submitters mechanic (`docs/02` §4.2: *"Voided rounds (S < 3) are excluded
> from everything"*) than to a badge, and it could in principle be **derived**, never stored,
> the same way `CLAUDE.md` §2.8 already requires scores to be. That makes it the more defensible
> of the two shapes, and worth being honest about rather than dismissing on reflex. But it still
> fails on the same question the epic asks: what does a broken circle streak look like on
> screen? Either it's silent (in which case it isn't really a feature — nothing changes from
> today's plain "round voided" state), or it's visible, and a visible reset is still the dreaded
> screen `docs/16`'s ban defends against — just retargeted from an individual to a group, in a
> genre of app whose one shared social space *is* the group chat (`docs/16` §1's "reactions"
> entry). A visible group streak-break risks pinning blame on whichever member didn't submit in
> a small circle right at the `S ≥ 3` margin — arguably a worse dynamic than an individual streak,
> because now it's peer pressure instead of self-directed guilt. Multi-circle is at least clean
> here: circles are already independent and never aggregate (`docs/16` §1, the promoted
> multi-circle note: *"nothing aggregates across circles"*, and the same section's
> *"Head-to-head or cross-group play: No. No cross-group anything"*), so a circle streak, if it
> existed, could only ever be per-circle — that part needs no new decision. But
> per-circle-and-not-punishing-multi-circle
> is a "less bad," not a "clean." And `CLAUDE.md` §2.7's text is unqualified — it says
> "streaks," not "personal streaks" — so nothing here reads it as already carving out a
> group-level exception.
>
> **Recommendation: decline both shapes for this beta.** Player streaks fail decisively and
> aren't worth bringing back. Circle streaks are the more defensible of the two — a derived,
> group-level fact rather than a personal progression counter — but still need an explicit
> `CLAUDE.md` §2.7 amendment before anyone could build them, exactly the way `E17-05`/`E17-07`
> recorded owner-level rule changes rather than an agent making the call; that amendment is not
> made here. If the owner wants to revisit, the circle-streak shape displayed as a plain,
> spectrum-style fact (no reset animation, no "you broke it" moment — closer to how `docs/02`
> §4.5 already renders readability as a position, never a judgement) is the version worth
> discussing first, not the player-facing one.