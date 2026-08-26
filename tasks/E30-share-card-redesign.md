# E30 — A share card worth sharing

One slice, from `docs/17-NEXT-FEATURES.md` §4. Everything the current share card gets right stays
right — this is a layout and hierarchy pass, not a rewrite of what it's allowed to say.

---

### E30-01 — Lead with the moment, not the table

**Status:** wip
**Deps:** —
**Parallel:** yes
**Reads:** `docs/17-NEXT-FEATURES.md` §4, `docs/10-SHARE-CARD-SPEC.md`, `docs/16-OUT-OF-SCOPE.md` §5,
`docs/07-DESIGN-SYSTEM.md`
**Touches:** `ios/BlindDrop/Features/Results/Share/ShareCardView.swift`,
`ios/BlindDrop/Features/Results/Share/ShareHeadline.swift`,
`ios/BlindDrop/Features/Results/Share/ShareRenderer.swift`, `docs/10-SHARE-CARD-SPEC.md`,
`ios/BlindDropTests/Snapshot/ShareCardSnapshotTests.swift`,
`ios/BlindDropTests/Unit/ShareRendererTests.swift`, `ios/BlindDropTests/Unit/ShareHeadlineTests.swift`
**Verify:** `-only-testing:BlindDropSnapshotTests/ShareCardSnapshotTests -only-testing:BlindDropUnitTests/ShareRendererTests -only-testing:BlindDropUnitTests/ShareHeadlineTests`;
`./ios/scripts/lint.sh`. Simulator: share sheet from scored rounds with 1 song, 4 songs, and 6+
songs (overflow), exercising as many of `ShareHeadline`'s five precedence branches as the fixture
data allows. Screenshot both render sizes (square-tall, story).
**Proves:** AC-9

Today's card reads as a compact data table: header, up to 4 song rows, one headline stat, the
night's Best Ear leader, wordmark. Redesign it to lead with one hero-scale visual moment — the
headline — instead of the song list.

- [ ] Run a short design-critique pass on layout options before committing to one; this is a
      taste call, not a mechanical one.
- [ ] The headline takes the dominant visual weight; the song list shrinks or is cut, at the
      designer's judgment from the critique pass.
- [ ] Bigger, bolder album-art treatment is fine. Text laid over the artwork is not — `docs/16` §5
      bans it explicitly, no exceptions for this redesign.
- [ ] Constraints carried over, unchanged: no QR code, no install link, no avatars, no scores for
      anyone but the headline person, no user IDs, no invite code, no group/join ID. The share
      entry point still exists only once a round is `scored`.
- [ ] Both render sizes (square-tall default, story) still work with the new layout.
- [ ] `docs/10-SHARE-CARD-SPEC.md` gets a revision pass in the same commit — it must describe what
      actually ships, not the layout it's replacing.
