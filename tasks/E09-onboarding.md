# E09 — Onboarding

Four steps, no tutorial carousel, no permission asks. A user must reach today's round in under
30 seconds from a cold install with an invite code in hand.

---

### E09-01 — Sign in with Apple

**Status:** wip · **Deps:** E08-05 · **Reads:** `docs/08` §1.1, `docs/13` §1 (Core/Auth), `docs/14` §5
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

**Status:** todo · **Deps:** E09-01 · **Reads:** `docs/08` §1.2, `docs/11` (onboarding), `docs/14` §7
**Touches:** `Features/Onboarding/DisplayNameScreen.swift`, `OnboardingStore.swift`
**Verify:** snapshot at three type sizes; unit test on validation

- [ ] Copy from `docs/11` — the help line makes the stakes clear (this is what people guess
      with)
- [ ] 1–24 chars after trimming; **Continue** disabled until valid
- [ ] Inline error in `alert`, never a modal
- [ ] Client mirrors the server's control/zero-width/RTL strip so the user sees what will be
      saved
- [ ] Routed to on `NO_PROFILE` from any endpoint, not only during first launch

---

### E09-03 — Join or create

**Status:** todo · **Deps:** E09-02 · **Reads:** `docs/08` §1.3–1.4, `docs/11`, `docs/04` §3
**Touches:** `Features/Onboarding/{JoinOrCreateScreen,CreateGroupScreen}.swift`
**Verify:** both paths complete against the fixture server

Join first — most users arrive via a link.

- [ ] Code field: `monoM`, auto-uppercasing, auto-advancing, paste handled, 6 chars
- [ ] `NOT_FOUND` renders `onboarding.group.code.error`
- [ ] Create: name, timezone picker defaulting to the device timezone, reveal-hour picker
      (18–21, default 20, shown as "8:00 PM")
- [ ] Copy states the consequence: songs open ten hours before, answers land two hours after
- [ ] Timezone help line says it cannot be changed later
- [ ] `ALREADY_IN_GROUP` handled — route to the round, don't show an error the user can't act
      on

---

### E09-04 — Invite code screen and deep link

**Status:** todo · **Deps:** E09-03 · **Reads:** `docs/08` §1.4–1.5, `docs/05` §5
**Touches:** `Features/Onboarding/CreateGroupScreen.swift`, `App/DeepLink.swift`
**Verify:** `xcrun simctl openurl booted blinddrop://join/K7MQ2X` prefills the field

- [ ] Code in `displayL`, **Share invite** via the share sheet, **Go to today's round**
- [ ] Share sheet content is the `https://blinddrop.app/j/<CODE>` URL, not the bare code
- [ ] `blinddrop://join/<CODE>` prefills the join field and focuses the button
- [ ] Universal Link via `apple-app-site-association` for `blinddrop.app/j/*`
- [ ] Landing back on 1.3 when a user has a profile but no group (they left a group)
- [ ] Lands **straight** on today's round after joining — no confirmation, no welcome
