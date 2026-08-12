# E09 — Onboarding

Four steps, no tutorial carousel, no permission asks. A user must reach today's round in under
30 seconds from a cold install with an invite code in hand.

---

### E09-01 — Sign in with Apple

**Status:** done · **Deps:** E08-05 · **Reads:** `docs/08` §1.1, `docs/13` §1 (Core/Auth), `docs/14` §5
**Touches:** `Core/Auth/{SessionStore,AppleSignIn,Keychain}.swift`, `Features/Onboarding/SignInScreen.swift`
**Verify:** sign-in completes against the fixture server; `xcodebuild test -only-testing:BlindDropUnitTests/AuthTests`

- [x] `ASAuthorizationController` wrapped in an `async` API
- [x] Session exchanged with Supabase Auth; refresh token in the **Keychain** with
      `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [x] Never `UserDefaults`, never a file
- [x] Sign out revokes server-side, not just locally
- [x] 401 → refresh once → retry once → sign out
- [x] Phone auth behind a build flag, **off** in v1
- [x] Minimal `Keychain` wrapper, no dependency

> **Open question:** *Where does the client get the Supabase Auth address and the anon key?*
> `docs/04` gives the functions base (`https://<project>.supabase.co/functions/v1`) and
> `docs/14` §5 says the session comes from Supabase Auth, but nothing names `/auth/v1` or says
> where the publishable key lives. Chosen: `AppConfiguration` **derives** the auth base from
> the API base (`…/functions/v1` → `…/auth/v1`, otherwise `/auth/v1` appended), overridable
> with `-authBaseURL`; the anon key comes from `Info.plist`'s `SUPABASE_ANON_KEY`, injected at
> build time and public by design like `SPOTIFY_CLIENT_ID` (`docs/14` §6). One launch argument
> therefore points a whole run at the fixture server. Both are empty until the project ref is
> assigned in E14-05, which is the same state `SPOTIFY_CLIENT_ID` is already in.

> **Open question:** *Which Apple scopes does the request ask for?* `docs/08` §1.1 does not
> say. Chosen: **none.** `docs/14` §9 lists the complete set of data the app collects — "Apple
> sub or phone, display name, group membership, song choices, guesses, APNs token" — and the
> display name is the one the user types in §1.2, not the one on their Apple ID. Requesting
> `.email` or `.fullName` would collect a field nothing reads, and a field we do not hold is a
> field we cannot leak. The consequence to note: there is no email on file, so account recovery
> is Apple's problem and not ours, which is the correct division.

> **Note, not a question:** the simulator returns `errSecMissingEntitlement` (-34018) for every
> Keychain call when the app is built with `CODE_SIGNING_ALLOWED = NO`, which is what E00-03
> set so CI needs no team. All eight build configurations now ad-hoc sign **on the simulator
> only** (`CODE_SIGN_IDENTITY[sdk=iphonesimulator*] = "-"`); device builds are unchanged and
> still need no signing identity. Without this no keychain code can be run or tested at all.

---

### E09-02 — Display name

**Status:** done · **Deps:** E09-01 · **Reads:** `docs/08` §1.2, `docs/11` (onboarding), `docs/14` §7
**Touches:** `Features/Onboarding/{OnboardingFlow,OnboardingStore,DisplayNameScreen}.swift`,
`Core/Text/DisplayName.swift`, `Core/Auth/SessionStore.swift`, `Core/Networking/APIClient.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropSnapshotTests/OnboardingSnapshots` (2 devices ×
3 type sizes); `-only-testing:BlindDropUnitTests/DisplayNameTests` and
`/OnboardingStoreTests`

- [x] Copy from `docs/11` — the help line makes the stakes clear (this is what people guess
      with)
- [x] 1–24 chars after trimming; **Continue** disabled until valid
- [x] Inline error in `alert`, never a modal
- [x] Client mirrors the server's control/zero-width/RTL strip so the user sees what will be
      saved — `DisplayNameTests` runs **the server's own cases**, lifted from
      `server/supabase/tests/functions/me.test.ts`
- [x] Routed to on `NO_PROFILE` from any endpoint, not only during first launch —
      `SessionStore.noteServerSaid(_:)`, called by `APIClient` on every failure

---

### E09-03 — Join or create

**Status:** done · **Deps:** E09-02 · **Reads:** `docs/08` §1.3–1.4, `docs/11`, `docs/04` §3
**Touches:** `Features/Onboarding/{JoinOrCreateScreen,CreateGroupScreen}.swift`,
`Core/Text/InviteCode.swift`, `Core/Time/RevealHour.swift`,
`DesignSystem/Components/InsetField.swift`
**Verify:** `./ios/scripts/verify-fixture.sh BlindDropUnitTests/FixtureOnboardingTests Onboarding`
— four tests, both paths, against `ios/Fixtures/server.ts`

Join first — most users arrive via a link.

- [x] Code field: `monoM`, auto-uppercasing, auto-advancing, paste handled, 6 chars —
      `InviteCode.normalise` runs on every keystroke, and a pasted **link** yields its code
      rather than six characters mined out of the URL
- [x] `NOT_FOUND` renders `onboarding.group.code.error`
- [x] Create: name, timezone picker defaulting to the device timezone, reveal-hour picker
      (18–21, default 20, shown as "8:00 PM")
- [x] Copy states the consequence: songs open ten hours before, answers land two hours after
- [x] Timezone help line says it cannot be changed later
- [x] `ALREADY_IN_GROUP` handled — route to the round, don't show an error the user can't act
      on. Handled on **both** the join and the create path, because a second device is how it
      actually happens

---

### E09-04 — Invite code screen and deep link

**Status:** done · **Deps:** E09-03 · **Reads:** `docs/08` §1.4–1.5, `docs/05` §5
**Touches:** `Features/Onboarding/CreateGroupScreen.swift`, `App/{DeepLink,BlindDropApp}.swift`,
`BlindDrop.entitlements`, `web/.well-known/apple-app-site-association`
**Verify:** `xcrun simctl openurl booted blinddrop://join/K7MQ2X` — see the note below on what
that command can and cannot reach today; `-only-testing:BlindDropUnitTests/DeepLinkTests` and
`OnboardingStoreTests/aLinkTravelsAllTheWayToTheField`

- [x] Code in `displayL`, **Share invite** via the share sheet, **Go to today's round**
- [x] Share sheet content is the `https://blinddrop.app/j/<CODE>` URL, not the bare code
- [x] `blinddrop://join/<CODE>` prefills the join field and focuses the button
- [x] Universal Link via `apple-app-site-association` for `blinddrop.app/j/*`
- [x] Landing back on 1.3 when a user has a profile but no group (they left a group) —
      the same `noteServerSaid(_:)` path as E09-02's last box, on `NO_GROUP`
- [x] Lands **straight** on today's round after joining — no confirmation, no welcome

> **Open question:** *What accent does a screen with no phase wear?* `CLAUDE.md` §2.5 allows
> two accents and forbids both decoratively; `docs/07` §5 says `PrimaryButton` takes *"accent
> from the current phase"*; `docs/07` §6's phase table has four rows and every one of them is a
> round state. Onboarding is in none of them — nothing is sealed and nothing is revealed —
> so borrowing amber would be the decorative use §2.5 rules out. Chosen: `PrimaryButton` gains
> a `Fill.neutral` case, `ink` filled with a `paper` label, and every onboarding button uses
> it. That is not a third accent and not a new colour pair: it is row one of `docs/07` §2's
> contrast table (*ink on paper*, 16.5:1) read the other way round, and `PaletteContrastTests`
> computes the ratio order-independently, so it is already asserted. `SignInScreen` had
> already made the same call for its own screen in E09-01.
>
> The one thing this loses: `docs/07` §5's press rule is *"fill darkens to the `Deep`
> variant"*, and the neutral has no `Deep` variant — the palette's neutrals run from `ink`
> upward, so `inkDim` would make a press read as a release. The neutral press is carried by
> the 0.985 scale alone, which is the other half of the same 120ms gesture. Inventing an
> `inkDeep` token is a design change and belongs to the owner, not to this task.

> **Open question:** *Which team identifier goes in the `apple-app-site-association` file?*
> `docs/05` §5 and `docs/16` §3 both name `https://blinddrop.app/j/<CODE>`, and the
> entitlement E00-03 shipped claimed a placeholder domain (`applinks:blinddrop.example`) with
> a note that the real one lands when the host is chosen. It is chosen — both docs name it —
> so the entitlement now claims `applinks:blinddrop.app`. The **team** identifier is a
> different matter: it is not assigned yet, so `web/.well-known/apple-app-site-association`
> carries `$APP_ID_PREFIX.com.blinddrop.app` and `web/README.md` says to substitute it at
> deploy time. That is the same state `SUPABASE_ANON_KEY` and `SPOTIFY_CLIENT_ID` are already
> in, and **E14-05** is where all three are filled in. A served file with a literal
> `$APP_ID_PREFIX` in it matches no app and silently disables every universal link, which is
> why it is written down here rather than left as a `TODO` in a JSON file.

> **Note, not a question:** *what `xcrun simctl openurl booted blinddrop://join/K7MQ2X`
> actually proves today.* Run against an installed build it returns cleanly and the app handles
> it without crashing, which is the real content of "the scheme is claimed and the link is
> delivered" — an unclaimed scheme fails the command outright. What it cannot do yet is show
> the prefilled field, because reaching step 1.3 live needs a signed-in session and signing in
> needs Apple's sheet, which cannot be driven from a simulator (E09-01 made the same point
> about `StubApple`). The claim is therefore split, with nothing left on trust:
> `DeepLinkTests` proves the parse for both doors, `aLinkTravelsAllTheWayToTheField` walks
> URL → `DeepLink` → `Router` → `OnboardingStore` and ends on a complete code and a live
> button, and the golden `JoinOrCreate-prefilled` is the picture of that field. The
> whole-loop walk against a live app is **E14-04**, which is where the board already puts it.

> **Note, not a question:** `ImageRenderer` draws `TextField` and `Menu` as a yellow
> "unsupported view" placeholder — they are UIKit-backed and the renderer has no host window to
> build them in. This is the fifth trap in that harness, after the four in `E11`'s notes. The
> placeholder occupies the control's **real frame**, so the onboarding goldens still carry what
> they are for: the rhythm, the reflow, the wrapping of every label and help line, and a row
> growing rather than clipping at `.accessibility5`. What they cannot show is the glyphs inside
> those two controls. The alternative — branching the components on a test-only flag so they
> draw a `Text` instead — would make the goldens pictures of something the app never renders.
>
> Two things were found by *looking at* the goldens rather than by a failing assertion, which
> is the argument for looking at them. The reveal-hour control was a segmented `Picker` whose
> placeholder was the wrong width, revealing that it sized to its content and would truncate at
> large type sizes; it is a `Menu` in the timezone row's chrome now, which is both renderable at
> the right frame and the control that cannot truncate. And `JoinOrCreateScreen`'s primary
> button was **absent** from its first golden: `@AccessibilityFocusState` may only be read from
> `body`, and a view that reads it outside `body` silently fails to draw. The screen now splits
> `snapshotContent` off the way `RevealScreen` splits its `@Namespace` rotor entries.
