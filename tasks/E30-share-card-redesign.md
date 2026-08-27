# E30 — A share card worth sharing

One slice, from `docs/17-NEXT-FEATURES.md` §4. Everything the current share card gets right stays
right — this is a layout and hierarchy pass, not a rewrite of what it's allowed to say.

---

### E30-01 — Lead with the moment, not the table

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/17-NEXT-FEATURES.md` §4, `docs/10-SHARE-CARD-SPEC.md`, `docs/16-OUT-OF-SCOPE.md` §5,
`docs/07-DESIGN-SYSTEM.md`
**Touches:** `ios/BlindDrop/Features/Results/Share/ShareCardView.swift`,
`ios/BlindDrop/Features/Results/Share/ShareHeadline.swift`,
`ios/BlindDrop/Features/Results/Share/ShareRenderer.swift`, `docs/10-SHARE-CARD-SPEC.md`,
`ios/BlindDropTests/Snapshot/ShareCardSnapshotTests.swift`,
`ios/BlindDropTests/Unit/ShareRendererTests.swift`, `ios/BlindDropTests/Unit/ShareHeadlineTests.swift`
**Verify:** `-only-testing:BlindDropSnapshotTests/ShareCardSnapshots -only-testing:BlindDropUnitTests/ShareRendererTests -only-testing:BlindDropUnitTests/ShareHeadlineTests`
(the suite is `ShareCardSnapshots`, not `ShareCardSnapshotTests` — the filename `ShareCardSnapshotTests.swift`
matches the old name but the `-only-testing:` filter needs the actual `struct`/`class` name; the
stale name silently matches zero tests and reports a false "0 tests, passed" rather than an error);
`./ios/scripts/lint.sh`. Simulator: share sheet from scored rounds with 1 song, 4 songs, and 6+
songs (overflow), exercising as many of `ShareHeadline`'s five precedence branches as the fixture
data allows. Screenshot both render sizes (square-tall, story).
**Proves:** AC-9

Today's card reads as a compact data table: header, up to 4 song rows, one headline stat, the
night's Best Ear leader, wordmark. Redesign it to lead with one hero-scale visual moment — the
headline — instead of the song list.

- [x] Run a short design-critique pass on layout options before committing to one; this is a
      taste call, not a mechanical one.
- [x] The headline takes the dominant visual weight; the song list shrinks or is cut, at the
      designer's judgment from the critique pass.
- [x] Bigger, bolder album-art treatment is fine. Text laid over the artwork is not — `docs/16` §5
      bans it explicitly, no exceptions for this redesign.
- [x] Constraints carried over, unchanged: no QR code, no install link, no avatars, no scores for
      anyone but the headline person, no user IDs, no invite code, no group/join ID. The share
      entry point still exists only once a round is `scored`.
- [x] Both render sizes (square-tall default, story) still work with the new layout.
- [x] `docs/10-SHARE-CARD-SPEC.md` gets a revision pass in the same commit — it must describe what
      actually ships, not the layout it's replacing.

**Closing notes.** Redesigned around one hero-scale headline (`TypeStyle.displayXL`, 56pt — the
largest the display face gets), with the old 4-row song table replaced by a filmstrip of bare
180pt artwork tiles (no title, no owner, no card number — up from the pre-redesign 96px
thumbnail). `docs/10-SHARE-CARD-SPEC.md` carries the full revision and rationale.

A design-critique pass was run against the rendered goldens (both variants, base case and the
`DisplayName.maximumLength`-name/100%-rate worst case): hierarchy reads correctly (headline
dominant, filmstrip demoted to texture), no text over artwork, tokens only, ultramarine-only
accent. One real bug caught and fixed in that pass: the headline's `minimumScaleFactor` was
initially too high (0.45) and let the worst-case headline truncate with an ellipsis despite the
spec's "shrinks, never truncates" promise; same problem, independently, on the Best Ear name in
the narrower story variant. Both fixed and re-verified pixel-by-pixel against the rendered
goldens. A follow-up `reviewer` pass caught that the fix's replacement value (0.34) could in
principle let a future, longer headline render under `docs/07`'s "never below 20pt" display-face
floor even though nothing reachable today triggers it — tightened to 0.4, which stays above that
floor with margin while still comfortably below the ~0.445 scale the current worst case needs.
The reviewer also flagged that `displayXL`'s doc-comment didn't yet list a results-card headline
as a sanctioned use (docs/07 already allowed it in prose, but the per-case gloss didn't) —
added to both `Typography.swift` and `docs/07-DESIGN-SYSTEM.md`.

**Known, separately-tracked gap — not part of this slice.** `ResultsViewState.share` is never
populated by `ResultsStore.viewState(resolve:)` (pre-existing on `main`, unrelated to this diff),
so the "Share tonight" button does not currently render live even on a `scored` round. This
blocked the simulator pass for 1-song and 4-song counts (only the fixture's fixed 8-card scored
round is reachable end-to-end today) — verified those two cases instead via the same
`ShareCardFixture` rendering path the snapshot tests use, visually confirmed correct (no overflow
caption, correct tile count, no truncation), then discarded the throwaway test scaffolding
before commit. Flagged as a separate follow-up task; not blocking here since it touches
`ResultsScreen.swift`/`ResultsStore.swift`, outside this slice's `Touches` list.

**Closed by a follow-up commit.** The gap was narrower than the note above states — the live
round's own `ResultsHost` did build a `ShareEntry` and pass it to `ResultsScreen`, but The
Record's history path (`RecordResultsScreen`) never did, and the two call sites were free to
drift apart. The fix moves construction into `ResultsStore` alone: `viewState(resolve:)` now
populates `ResultsViewState.share` from a best-effort `GroupDTO` fetch and a store-owned
`ShareRenderer`, and both `RoundScreen` and `RecordScreen` read it from the store instead of
building their own. `ResultsTests` proves the entry appears once the answers and the group land
(and is absent without the group); `ShareRendererTests` now asserts nothing outside
`Features/Results/` reaches the share card at all.
