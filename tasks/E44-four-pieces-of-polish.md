# E44 — Five pieces of polish

Five owner-reported defects from an app walk, 2026-09-11. All client-only: no migration, no
endpoint, no DTO, no push-worker change. Ordered cheapest-and-most-certain first, deliberately —
the last one touches the arrangement `E37`/`E43` fought for and is the only one carrying real
risk.

**The owner's constraint on `E44-04`, and it is the binding one.** *"Nothing should really change
the cued night layout. If it's too risky don't do it, just leave it."* So the keyboard-ownership
rewrite considered in planning — `.ignoresSafeArea(.keyboard)` plus an observed keyboard frame
applied as our own padding — is **off the table for this epic**. It is the fix that would centre
the uncued column exactly and give the chrome's descent something to animate, and it would also
re-open the arrangement that four separate owner notes in `SubmitScreen` and `SongSearch` were
written to settle. What `E44-04` does instead is bounded: it changes the value passed on the
**uncued** path only, so the cued night is not merely "probably fine", it is running the same
code it ran before this epic.

> **Open question — is the header's snap-down fixable without owning the keyboard?**
> Interpretation taken: **try the cheap transactions, and if they do not take, say so and stop.**
> The lift is applied by the hosting controller after layout, outside any SwiftUI transaction, so
> whether an implicit animation reaches it is an empirical question about UIKit and not a design
> decision. `E44-04` tries it; if the answer is no, the slice closes with the uncued centring
> fixed, the snap named as unfixed, and the reason written here rather than a risky rewrite
> smuggled in under a polish epic.

---

### E44-01 — Sheets put the keyboard away when they close

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/12` §5, `ios/BlindDrop/Features/Circles/JoinCircleSheet.swift`,
`ios/BlindDrop/Features/Settings/GroupScreen.swift` (`GroupNameSheet`, `NextCueSheet`),
`ios/BlindDrop/Features/Submit/SearchSheet.swift`,
`ios/BlindDrop/Features/Onboarding/StartGroupSheet.swift`
**Touches:** new `DesignSystem/Components/KeyboardFocus.swift`, the four files above

Every sheet with a field spent real effort getting its keyboard **up** — `NextCueSheet` carries
three separate focus requests and a paragraph explaining each. None of them wrote the way down.
Closing by the button, by `dismiss()` or by drag leaves the field first responder, and the
keyboard rides out over the screen behind.

One shared modifier, the mirror of the `defaultFocus` chain: resign focus as the sheet leaves,
and resign it explicitly before any programmatic dismissal so the keyboard travels with the sheet
rather than after it.

- [x] `resigningFocus(_:)` in `DesignSystem`, documented as the counterpart to `defaultFocus`
- [x] `JoinCircleSheet` resigns before `close()` and on the way out
- [x] `GroupNameSheet` and `NextCueSheet` resign before `dismiss()` and on the way out
- [x] `SearchSheet` and `StartGroupForm` likewise
- [x] `./ios/scripts/lint.sh` clean

**Verify:** `./ios/scripts/lint.sh`; unit + snapshot suite; simulator — each sheet closed three
ways (button, drag, save).

---

### E44-02 — A circle you have already seen does not show a skeleton

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/13` §5 rule 3/§7, `ios/BlindDrop/Features/Round/RoundStore.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift` (`switchCircle`),
`ios/BlindDrop/Features/RouteStoreCache.swift`, `ios/BlindDrop/Core/Networking/LoadState.swift`
**Touches:** `Features/Round/RoundStore.swift`, `Features/Round/RoundScreen.swift`,
`ios/BlindDropTests/Unit/RoundStoreTests.swift`

`RouteStoreCache` already does this for Group, Insights, Record and Profile — a store per circle
id, so a revisit refreshes in place instead of flashing. The round is the one screen it does not
cover: a single `RoundStore`, and `switchCircle` calls `invalidate()`, which hard-sets
`.loading`.

`RoundStore` gains a per-circle memo of the last successful `RoundContext`.
`invalidate(switchingTo:)` serves it when there is one and clears to `.loading` when there is not.

**Why this does not re-open what `invalidate()` exists for.** That method's note names the
hazard: the *previous* circle's round on screen while `SubmitStore`/`SealStore` resolve
`resolveActiveID()` fresh, so a tap lands on the new circle against the old circle's card.
Serving the **new** circle's remembered round inverts that — card and action now name the same
circle. The swap must stay synchronous with `circles.select(id)`.

**The residual risk is a stale phase**, and it is guarded rather than argued away: the memo is
served only when the cached context's own deadline has not passed. A round whose reveal has since
fired gets the skeleton, exactly as today.

No `CLAUDE.md` §2.1 exposure. The memo holds a payload this caller was already served for a
circle they hold; nothing about anybody else is in `RoundContext`, and there is no field on it
where a count could be put.

- [x] `RoundStore` memoises the last loaded `RoundContext` per circle id
- [x] `invalidate(switchingTo:)` serves a live memo, `.loading` otherwise
- [x] The memo is refused when `deadline` has passed, and when the clock has no anchor
- [x] `reset()` on sign-out clears it — the one case keys cannot see
- [x] Tests: a revisit renders without `.loading`; an expired memo does not

**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropUnitTests`; simulator — switch
A → B → A and watch for the skeleton.

---

### E44-03 — Past results keeps its store too

**Status:** done
**Deps:** E44-02
**Parallel:** no
**Reads:** `ios/BlindDrop/Features/RouteStoreCache.swift`,
`ios/BlindDrop/Features/Results/PastResultsScreen.swift`
**Touches:** `Features/RouteStoreCache.swift`, `Features/Results/PastResultsScreen.swift`

The remaining skeleton-flash the walk did not reach: `PastResultsScreen` builds its own
`ResultsStore` per push, so the same night opened twice loads twice. Keyed by round id, not
circle id — a night is the thing being looked at.

- [x] `RouteStoreCache.resultsStore(for:)`, keyed by round id
- [x] `PastResultsScreen` takes it from the cache
- [x] `reset()` clears it

**Verify:** `./ios/scripts/lint.sh`; unit suite; simulator — open a night from The Record, back,
open it again.

---

### E44-04 — The uncued drop screen is centred, not resting on the keyboard

**Status:** done
**Deps:** —
**Parallel:** no
**Reads:** `docs/08` §2, `docs/07` §4, `ios/BlindDrop/Features/Submit/SubmitScreen.swift`,
`ios/BlindDrop/Features/Submit/SongSearch.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift:207`
**Touches:** `Features/Submit/SubmitScreen.swift` (the uncued path only)

**The defect.** On a night with no cue the headline, field and footer sit at the very bottom of
the screen, resting on the keyboard.

**Why.** `SubmitScreen` passes `topGapCap: cue == nil ? nil : Space.x5`. `nil` leaves both of
`SongSearch`'s flexible gaps uncapped, and the note there says capping neither is what centres
the block. It does split the leftover evenly — of a container that extends *underneath the
keyboard*, which is the fact `SongSearch`'s own body note records as the reason nothing on this
screen can be pinned to its bottom edge. So the midpoint being aimed at is the midpoint of the
full device height, which is below the keyboard line; the block lands under the keyboard, and
UIKit's avoidance then lifts the whole hosting view to keep the field visible and parks it on top
of the keyboard. That lift is also what drags the chrome up.

**The fix, and its bound.** The uncued path gets a **cap**, chosen by looking at the rendered
screen, instead of `nil`. A cap is a resting position measured from the chrome, which is a number
that does not care where the keyboard is — so it cannot be centred *into* the keyboard the way an
even split of an over-tall container can. `Space.x5` is what the cued night already uses and is
too small here, because an uncued column is shorter by the whole cue card; the uncued night needs
a larger one, and the value is settled against screenshots rather than arithmetic.

The cued night's argument is untouched: same expression, same `Space.x5`, same code path.

**And the snap.** With the uncued column no longer overflowing, the lift on that path stops
happening at all, which removes the snap there for free. On a cued night at large type the column
can still overflow, and the chrome's descent when results arrive is still a jump. Two cheap
attempts, in order: drive the `isBrowsing` flip through an explicit transaction, and failing
that, hoist a narrowly-keyed `.animation(value:)` above `RoundScreen`'s `safeAreaInset` so the
chrome's own frame change is inside the animated scope. If neither takes, the slice closes with
it named as unfixed — see this epic's open question.

- [x] The uncued night gets a cap — `Layout.dropColumnTopGapUncued`
- [x] The cued night's expression and value are unchanged
- [x] Snapshot goldens: **none moved**, and that is a finding, not a pass (see below)
- [x] The chrome's descent: **not attempted** (see below)

**Verify:** `./ios/scripts/lint.sh` clean; unit + snapshot suite green.

> **Closed with two things unverified, both named rather than papered over.**
>
> **The number was derived, not seen.** `dropColumnTopGapUncued` is 104 because that is half the
> band an uncued column leaves over on an iPhone 17 by arithmetic — chrome to keyboard, less the
> block. The owner took the simulator passes for this epic, so nobody has looked at it yet. If the
> block sits high or low, that constant is the only thing to move and nothing moves with it.
>
> **The snapshot suite cannot see this change at all.** Not one `Cue-Submit` or `Cue-Closed`
> golden moved, which looked like a clean pass and is not one: `SnapshotRenderer` fits the
> column's own height, so a flexible `Spacer` capped at anything resolves to zero and the cap
> never renders. The automated suite is therefore *silent* here rather than agreeing — it proves
> only that nothing else broke. A golden that could see it would need a fixed device-height
> canvas with a keyboard inset, which this harness does not have and which is not worth building
> for one number. It is a device check, and it is the owner's.
>
> **The chrome's snap-down was not attempted.** The two cheap transactions in the plan — driving
> `isBrowsing` through an explicit `withAnimation`, or hoisting a keyed `.animation(value:)` above
> `RoundScreen`'s `safeAreaInset` — were not tried, because neither reaches the offset in
> question: UIKit's keyboard avoidance applies it after layout and outside SwiftUI's transaction
> system, and dressing the screen in an animation scope that cannot contain it would have been a
> change that looks like a fix and is not. The honest fix is owning the keyboard, which the owner
> put out of scope for good reason. What this slice does buy is narrower and real: an uncued
> column that no longer overflows never gets lifted, so on that night there is nothing left to
> snap. A cued night at large type can still overflow, and there the chrome still jumps. Unfixed,
> on purpose, and recorded here rather than left for somebody to rediscover.

---

### E44-05 — The shortlist draws like the pool it came from

**Status:** todo
**Deps:** —
**Parallel:** vs E44-02, E44-03
**Reads:** `docs/07` §5, `docs/08` §6, `docs/12` §3,
`ios/BlindDrop/Features/Reveal/GuessSheet.swift` (`pool`, `equalWidthRow`, `chipRow`,
`snapshotPool`), `ios/BlindDrop/DesignSystem/Components/NameChip.swift`
**Touches:** `Features/Reveal/GuessSheet.swift`, `DesignSystem/Components/NameChip.swift`

**Owner call, 2026-09-11.** The four-name shortlist stays. How it is *drawn* is reverted: the
narrowed row goes back to the full pool's rendering exactly — each pill hugging its own name with
`Layout.nameChipMinimumWidth` as the floor, one line and no wrapping, inside the same horizontal
`ScrollView` with the same trailing fade. Asked which of "ragged like the pool" or "equal widths
sized to the longest name" was meant, the owner said *"just like the full pool"*: ragged.

**What this reverses, and the argument it overrides.** `equalWidthRow` exists on the reasoning
that four equal shares read as one set of choices and always fit down to an SE. The cost, which
is what the owner is reporting, is that a quarter of the sheet is narrow enough to force long
names onto two lines — and a wrapped pill is visibly a different object from the pool's pills, so
focusing a card changed what the names *were*, not just which ones were offered. Drawing them the
pool's way is what makes narrowing a filter rather than a mode.

The fade returning over a row that may not overflow is accepted: it is what the full pool already
does at every length, and one rule drawn consistently beats two rules each locally optimal.

- [ ] The narrowed row uses the pool's `ScrollView` + `chipRow` path
- [ ] `equalWidthRow` is gone, not left unused
- [ ] `NameChip.fillsWidth` removed if `Size.large` is its only remaining caller
- [ ] The narrowed golden re-recorded after looking at the diff
- [ ] `.accessibility5` still gets `gridChips`, untouched

**Verify:** `./ios/scripts/lint.sh`; unit + snapshot suite; simulator — focus a card in a circle
with a long name and a short one, default and `accessibility5`.
