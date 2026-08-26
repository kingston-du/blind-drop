# 17 — Next progression: feature spec

Nine improvements the owner named as the next progression for the app, written up in the format
the rest of `docs/` uses: current state, what changes, and the rules each change touches. This
document is a spec, not a task board — turning each section below into epics/slices on
`tasks/BOARD.md` (`E29` onward) is the natural next step, via the normal planning flow, once this
lands.

Two sections amend rules `CLAUDE.md` and `docs/16` currently treat as owner-only. Both amendments
were decided by the owner directly, in the conversation that produced this doc — see §5 and §9.

---

## 1. Results screen: "who guessed you" and tonight's top 3

**Current.** `ResultsScreen.swift` renders each card with its owner, an aggregate
`correct_guess_count` / `eligible_guesser_count`, and only the caller's own guess
(`ResultCardDTO.myGuess`). `ResultsDTO.people` — every submitter's per-round readability/ear rate
— is already fetched by `ResultsStore` but never rendered here; today it is consumed solely by the
share headline (`ShareHeadline.swift`). `StandingsView` ranks the group's all-time Best Ear only;
readability is deliberately never ranked (`docs/16` §5).

**New: who guessed you.** Once a round is `scored`, on the card the caller owns, show every
guesser and what they picked — name plus correct/incorrect. No green/red (`docs/16` §5); reuse the
neutral glyph/ink treatment `FlightCard` already uses for a `.resolved` card. This is scoped to the
caller's **own** card only — not a full who-guessed-whom grid for every card in the round.

Server: extend the `GET /rounds/:id/results` shaping (`server/supabase/functions/rounds/index.ts`)
with a field on the caller's own card —

```jsonc
"my_card": {
  // existing fields …
  "guesses": [
    { "guesser_name": "Ana", "picked_name": "Ben", "correct": false }
  ]
}
```

sourced from the `guess_results` view (`0005_scoring.sql`) filtered to `card = my card`. Leak-audit
addition (`server/scripts/audit-leak.mjs`): assert `guesses` is absent before `scored`, and absent
on every card the caller does not own.

**New: tonight's top 3.** A per-round Ear ranking — top 3, ties share a rank, same rank semantics
`standings` already uses — sourced from `round_scores` (`0005_scoring.sql`), for the current round
only. Shown as its own small module near, not merged into, the all-time `StandingsView`. Never
rank readability.

**iOS.** Add a "who guessed you" disclosure under the caller's own answer card, and a compact
"tonight" leaderboard module in `ResultsScreen`, visually distinct from the all-time Best Ear
section it sits beside.

---

## 2. Song preview playback on past results (The Record)

**Current.** `ResultsScreen` already accepts a `player` argument, used on the live results path.
`RecordResultsScreen` (`Features/Record/RecordScreen.swift`) instantiates
`ResultsScreen(state: store.viewState(resolve: nil))` with no `player` argument, which defaults it
to `nil` — so a past round's cards render with no preview playback, even though the same screen
supports it live.

**Change.** Confirm `player`'s exact type and behavior, then wire a real instance through
`RecordResultsScreen` so past-round cards get the same tap-to-preview playback as live results.
This is very likely a wiring gap rather than missing capability — no new player component expected.

Carries the same constraints the live path already respects (`docs/16` §3): preview only, 30
seconds, from the catalog, never autoplaying, never queued, never backgrounded. No server change.

---

## 3. Spotify / Apple Music open links — consistency pass

**Current.** Already built: `TrackLinkRouter` resolves an app-URL-first, web-URL-fallback open for
each service; `CardCornerLinks` surfaces it on the sealed/submitted card; `TrackUtilityMenu`
surfaces it on results answer cards and Record rows. Spotify is identity/export only and never a
preview source (`docs/16` §3 — "Spotify previews" is explicitly out of scope; previews are Apple
Music only).

**Gap to verify.** Whether cards during the revealed/guessing phase (after reveal, before
`scored`) expose the same open-in-Spotify/Apple-Music menu. If they don't, add `TrackUtilityMenu`
there too, for consistency across every card state a track can be viewed in.

**Non-goals.** No Spotify playback. No change to track-link resolution timing unless a measurement
(extend the existing `E27-01` coverage query rather than duplicating it) actually shows resolution
lagging past when it's useful.

---

## 4. Share card redesign

**Current** (`docs/10-SHARE-CARD-SPEC.md`, `Features/Results/Share/`). Header (group name + date),
up to 4 song rows (title, artist, artwork thumbnail, owner), one headline stat, the night's Best
Ear leader, wordmark. It reads as a compact data table — accurate, but not something built to want
to post.

**Direction.** Lead with one hero-scale visual moment — the headline — rather than a list of songs;
shrink or drop the row list; give album art a bigger, bolder treatment without laying any text over
the artwork itself (`docs/16` §5's explicit ban). This is a taste call, not a mechanical one — run
a short design-critique pass before committing to a layout.

**Constraints carried over, unchanged.** No QR code or install link, no avatars, no scores for
anyone but the headline person, no user IDs, no invite code, no group/join ID. Exists only once a
round is `scored`. Both render sizes (square-tall default, story) stay. `docs/10` needs a revision
pass alongside implementation — this doc doesn't replace it.

---

## 5. Conditional notifications, replacing the unconditional nudge

**Current** (`docs/05` §3). `nudge` fires at `reveals_at − 2h`, unconditionally, to every active
member regardless of submission status — one of exactly three deliveries/user/day
(`CLAUDE.md` §2.6, ADR-011).

> **Owner amendment, this doc.** The unconditional nudge is retired and replaced with three
> conditional reminders. The 3-deliveries/day cap (`CLAUDE.md` §2.6, ADR-011) is explicitly lifted
> to accommodate them — decided directly by the owner, the same way ADR-011 itself amended the
> original single-circle version of this rule.

| Kind | When | Audience | Replaces |
|---|---|---|---|
| `seal_reminder` (1st) | `reveals_at − 2h` | members who **haven't submitted** yet | today's `nudge`, same timing, now conditional |
| `seal_reminder` (2nd) | `reveals_at − 30m` | members who **haven't submitted** yet | new |
| `guess_reminder` | `scores_at − 30m` | submitters who **haven't finished guessing** yet | new |

`reveal`/`void` (at `reveals_at`) and `results` (at `scores_at`) are unchanged. `seal_reminder`
fires up to twice per round; `guess_reminder` once. Worst case for a fully disengaged member in one
circle is now up to **5 pushes in an evening** (both seal reminders, reveal, guess reminder,
results) — stated plainly here so it isn't discovered later.

**Rule updates required in the same change.** `CLAUDE.md` §2.6, `docs/05` §3's kind table and its
"closed set" language, and `docs/16` §5's "a fourth daily notification [is a spec violation]" line
all currently say the opposite of the table above. They must be edited together, with an ADR entry
recording that the owner made this change — not left to drift out of sync with the code.

**Architecture.** `tick_rounds()` gains new scan windows computing "members without a submission"
(for both `seal_reminder` firings) and "submitters without a complete guess sheet" (for
`guess_reminder`) at enqueue time — same mechanism `nudge`'s 2-hour scan already uses today, just
two more windows and a real condition instead of "everyone."

Round-kind notification audiences were previously documented as frozen forever at enqueue
(`docs/05` §3, "a later join or leave does not rewrite it") — because the old `nudge` didn't care
who had submitted. These new kinds do, and the condition can flip true between enqueue and actual
send (someone submits in the last 30 minutes). `claim_notification_outbox` needs a settle-check for
`seal_reminder`/`guess_reminder` mirroring the existing `settled_invitations` pattern used for
`invite` (`20260820110000_notification_delivery_budget.sql`): skip sending, mark `sent_at`, if the
recipient's condition already resolved by claim time. The multi-circle same-hour grouping rule
(§3, `E23-02`) still applies within each kind independently.

`push-worker/worker.ts`'s deep-link/expiration switch gets cases for the two new kinds, reusing the
existing `.round(groupID:)` deep link (`blinddrop://circle/<GROUP_ID>/round/current`) — no new iOS
routing needed; `App/DeepLink.swift` and `PushRouter.swift` already handle it.

**Tests.** Existing exactly-3/day budget tests (leak audit, notification tests) need explicit,
called-out revision to match the new cap — not incidental breakage discovered later.

---

## 6. Call-sheet drag snap-back

**Symptom.** The call sheet doesn't move up or down smoothly — a deliberate but moderate drag
sometimes snaps back to the original detent instead of committing to the new one. It should
decisively go up or down.

**Current.** `Features/Reveal/GuessSheet.swift`'s `headerGesture` (a single `DragGesture` recognized
on touch-down) resolves the end state through `CallSheetDetent.resolved(...)`, a
velocity/predicted-end-translation calculation. Its thresholds are the likely cause of premature
snap-back on a real, purposeful drag.

**Fix direction.** Retune `CallSheetDetent.resolved`'s distance/velocity thresholds so a deliberate
partial drag commits to the new detent, while a genuinely tiny movement still resolves as a tap
(`toggleDetent()`, gated by `abs(value.translation.height) < Space.sm` today). Reproduce first —
drag at a few different speeds and distances in the simulator — before changing constants, so the
fix targets the actual threshold that's wrong rather than guessing.

---

## 7. Record entry placement on the group screen — already in flight

The working tree already carries this change, uncommitted: `GroupScreen.swift`'s record entry
moved above the group/member list and restyled as a bordered pill (icon, title, trailing chevron,
`Palette.surface` fill, `Palette.edge` stroke) instead of a plain link, riding on `Palette.swift`'s
new `inkSubtle`/`ultramarineWashLight` tokens and `StatFigure.swift`'s generic
`SheetMeta<Trailing>` slot. Confirmed by the owner: this **is** the answer to "move the record up,
make it nicer" — not a placeholder for further redesign.

**Action.** Finish, verify, and commit this work as its own slice. No new design work.

---

## 8. Hamburger menu visible during pop-back transition (minor)

**Symptom.** Navigating back to the home screen — as the current screen slides right during the
pop — sometimes shows the hamburger `Menu` sliding in from the left, underneath the outgoing
screen.

**Current.** There is no custom drawer or slide animation anywhere in the app; "hamburger" is a
native SwiftUI `Menu` (`Features/Round/RoundScreen.swift`) that pushes `.group` / `.insights` /
`.settings` onto the app's single `NavigationStack`. No `.animation`/`.transition` code exists near
it — the glitch is most likely a compositing artifact of the stock pop transition, not app-owned
animation code.

**Owner note: low priority.** Confirm the repro in one simulator pass, try the cheapest fix first
(most likely: the menu staying attached/rendering behind the pop transition when it shouldn't be),
and stop there. Not worth a deep investigation.

---

## 9. Marketing website

**Current.** `blind-drop/web/` holds only `apple-app-site-association` and a README. `docs/16` §1
deferred "web presence" pending a spike; `tasks/E27-spikes.md`'s `E27-03` already ran it and
reported **"no, the beta needs nothing beyond the landing page"** — a single static page at
`https://blinddrop.app/j/<CODE>` (and reasonably the bare domain), showing the app name, one
screenshot, one line of copy, and an install link (TestFlight public link for now, swapped for the
App Store link at release), falling back to the raw code if the universal link doesn't resolve. No
login, no group data, no form.

> **Owner note.** The ask for "a basic website" in this conversation is read as executing
> `E27-03`'s already-decided scope, in a **new, separate repository** — not as reopening that
> spike's verdict for something larger. Anything beyond the single page above (additional pages, a
> blog, a waitlist form, broader marketing copy) would reopen `E27-03`'s "no" and needs a fresh
> owner decision; it is explicitly out of scope here.

**Recommendation.** Plain static HTML/CSS, no framework, matching the spike's own recommendation
("a static file and a host, not a framework"). `blind-drop/web/` stays exactly as it is — it exists
only to hold `apple-app-site-association`, and this new repo is separate from it.

**Coordination requirement.** Whatever host serves the new site must not disturb
`blinddrop.app/.well-known/apple-app-site-association` — either the new site also serves that file
unchanged, or DNS/reverse-proxy routing sends `.well-known/*` back to wherever it's served today.

---

## Rule changes this spec requires

One amendment, already recorded where it applies (§5), summarized here so it isn't missed:

- **`CLAUDE.md` §2.6 / `docs/05` §3 / `docs/16` §5** — the 3-deliveries/user/day cap is lifted to
  accommodate two new conditional notification kinds (`seal_reminder`, up to twice/round;
  `guess_reminder`, once/round), replacing the old unconditional `nudge`. Owner-decided, same
  pattern as ADR-011. All three documents need editing in the same change that ships the code —
  none of them may keep asserting the old cap once the new kinds exist.

No other section here requires a rule change; §9 documents a scope decision (executing an
already-approved spike result) rather than amending a rule.

## Suggested follow-up

Turning the nine sections above into epics/slices on `tasks/BOARD.md` (`E29` onward) is the natural
next step, through the normal planning flow — not part of this document.
