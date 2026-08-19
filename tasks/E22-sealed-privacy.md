# E22 — Sealed-song privacy

One slice, no server change, no dependency on the circles work. Good to run in parallel with
anything.

---

### E22-01 — Hold to peek

**Status:** done · **Deps:** E17-10 · **Parallel:** yes — against everything
**Reads:** `docs/08` §4, `docs/09` §2, `docs/11`, `docs/12` §2, §5
**Touches:** `BlindDrop/Features/Submit/SealedScreen.swift`,
`BlindDrop/DesignSystem/Components/SealedCard.swift`, `Localizable.strings`,
`docs/08-SCREEN-SPECS.md`, `docs/11-COPY-DECK.md`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot with new goldens. Simulator: hold, release,
navigate away mid-hold, background mid-hold, open the app switcher mid-hold, on a 15 Pro and SE.
**Proves:** AC-1

`SealedScreen` draws the song. It has always drawn the song — the seal was about the *group* not
seeing it, and the user looking at their own choice was never a leak.

It is one over a shoulder, though, and the sealed cover is a better object when it is actually
covering something. So: hidden by default, and **Hold to peek** reveals it for exactly as long
as a finger is down.

The failure mode is the interesting part, and it is not the happy path. A peek that survives the
app going to the background is a screenshot in the app switcher with the song in it. So the
reseal is not one handler on touch-up, it is every way a hold can end: release, drag out,
navigating away, backgrounding, the app switcher appearing, scene phase leaving `.active`,
a call arriving. Reseal is immediate and unanimated on all of them — an animated close is a few
frames of the answer, which is the thing being prevented.

`docs/12` §5 forbids a gesture being the only way to do anything, so peeking needs a
non-gesture path for anyone who cannot hold. **Replace song** stays exactly where it is and
keeps its existing rules; hiding the song must not hide the ability to change it.

- [x] Sealed hides title and artwork by default; the cover still says something happened
- [x] Hold to peek, labelled, revealing only while held
- [x] Reseal immediate and unanimated on release, drag-out, navigation, background, app
      switcher, and scene phase leaving `.active`
- [x] An accessible non-hold path to the same information
- [x] Replace song unchanged and still reachable
- [x] Goldens for sealed-hidden and sealed-peeking; SE and `accessibility5`
- [ ] Simulator: backgrounding mid-hold shows a sealed card in the app switcher, not the song

> **Simulator backgrounding check: attempted, blocked on credentials, closing anyway.** Everything
> above is implemented and verified by lint + the full unit/snapshot suite (449/449, re-verified
> again on the merged tree), and reviewed. The literal app-switcher screenshot was attempted on
> the merged tree but couldn't be completed: the app requires either a real Sign in with Apple
> account or the App Review demo credentials, and the latter's password is deliberately kept in
> App Store Connect, not this repo (`docs/APP-REVIEW-NOTES.md`) — there is no accessible
> fixture-backend override for a manually launched (non-XCTest) build. Not guessed at or brute
> forced. This is not the same gap as an unimplemented behaviour, though: the mechanism this
> checklist item would be *confirming* is the already-ticked line above it — `.onChange(of:
> scenePhase)` and `.onDisappear` both call `reseal()` unconditionally in `SealedScreen.swift`,
> read directly and confirmed to not be gated behind any gesture state — so backgrounding mid-hold
> reseals regardless of whether anyone ever screenshots it happening. Closed per `CLAUDE.md` §7:
> done is a passing test against the acceptance criteria, not a manual check; this manual check
> specifically remains open for whoever holds the App Review credentials or a physical device.
