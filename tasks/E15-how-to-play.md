# E15 — How to play

The explainer nowhere in the app named until now. Reachable from a `[?]` beside every phase's
menu and from sign-in, opening as a sheet — never a fourth `Route` (`docs/13` §4: three pushed
destinations, and adding a fourth is a product change).

---

### E15-01 — Copy deck: How to play

**Status:** done · **Deps:** — · **Reads:** `docs/11` §Voice, `CLAUDE.md` §6
**Touches:** `docs/11-COPY-DECK.md`, `BlindDrop/Resources/Localizable.strings`
**Verify:** `./ios/scripts/lint.sh`

Twenty-three rows: the four steps, the two scoring terms, the four "Good to know" facts, and
the page's own title and intro. No step names its phase (`sealed` / `live` / `scored`) beside
its clock time — the time alone says when, and the word beside it would repeat what the
countdown already carries.

- [x] `## How to play` section added to `docs/11-COPY-DECK.md`
- [x] Every row transcribed verbatim into `Localizable.strings`
- [x] `lint.sh` — no exclamation marks, no banned words

---

### E15-02 — `HowToSheet`

**Status:** done · **Deps:** E15-01, E08-04 · **Reads:** `docs/07`, `docs/12` §1
**Touches:** `BlindDrop/Features/HowTo/HowToSheet.swift`, `BlindDrop/Features/Round/RoundStore.swift`
**Verify:** `xcodebuild test -scheme BlindDrop -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' -only-testing:BlindDropUnitTests/HowToTests -only-testing:BlindDropSnapshotTests/HowToSnapshotTests`

No accent (`CLAUDE.md` §2.5) — the page is true on every phase and before any round exists, so
neither amber nor ultramarine belongs on it. Three neutral `cardSurface()` blocks: the four
steps, the two scoring terms, the four notes.

The three clock times a step needs — when songs seal, when the reveal lands, when scores
land — are never written down as strings. They come off `RevealHour`, against the **group's**
`reveal_hour`, so a group with a non-default schedule reads its own hours. `RoundContext` gained
`scoresTime` for the one caller that needed it. The sheet defaults to `RevealHour.default` for
the one entry point reached before there is a group — sign-in.

- [x] `HowToSheet` renders the intro, the four steps, scoring, and the notes
- [x] `RoundContext.scoresTime` added, derived the same way `revealTime`/`opensTime` are
- [x] `HowToTests` — the default group's three times match the copy deck's; a group on a
      different `reveal_hour` reads its own
- [x] `HowToSnapshotTests` — full page, `{SE, 15 Pro Max} × {large, accessibility1, accessibility5}`

---

### E15-03 — `HelpButton` and its three entry points

**Status:** done · **Deps:** E15-02 · **Reads:** `docs/08` §1.1, §2, §8, `docs/12` §5
**Touches:** `BlindDrop/DesignSystem/Components/HelpButton.swift`,
`BlindDrop/Features/Round/RoundScreen.swift`, `BlindDrop/Features/Onboarding/SignInScreen.swift`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropUnitTests/RoutingTests -only-testing:BlindDropUnitTests/RoundInsetTests`

`questionmark.circle`, drawn like `CloseButton` — a bare glyph in `inkDim`, 44pt touch target,
no accent. In `RoundHeader`, beside `[≡]`, which puts it on all five phase screens through one
file. On `SignInScreen`, alone in the top-right corner — the one screen with no header to share
it with.

- [x] `HelpButton` component, matching `CloseButton`'s chrome
- [x] `RoundHeader` takes a `showHowTo` closure and renders it before the menu
- [x] `RoundScreen` presents `HowToSheet(revealHour:)` from the group's own `reveal_hour`
- [x] `SignInScreen` gets its own row and presents `HowToSheet()` at the default hours
- [x] `RoutingTests` still holds three destinations; `RoundInsetTests`' whitelist is unaffected —
      a sheet is not a phase screen
