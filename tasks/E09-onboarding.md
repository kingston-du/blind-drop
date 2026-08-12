# E09 — Onboarding

Four steps, no tutorial carousel, no permission asks. A user must reach today's round in under
30 seconds from a cold install with an invite code in hand.

---

### E09-01 — Sign in with Apple

**Status:** wip · **Deps:** E08-05 · **Reads:** `docs/08` §1.1, `docs/13` §1 (Core/Auth), `docs/14` §5
**Touches:** `Core/Auth/{SessionStore,AppleSignIn,Keychain}.swift`, `Features/Onboarding/SignInScreen.swift`
**Verify:** sign-in completes against the fixture server; `xcodebuild test -only-testing:BlindDropTests/AuthTests`

- [ ] `ASAuthorizationController` wrapped in an `async` API
- [ ] Session exchanged with Supabase Auth; refresh token in the **Keychain** with
      `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [ ] Never `UserDefaults`, never a file
- [ ] Sign out revokes server-side, not just locally
- [ ] 401 → refresh once → retry once → sign out
- [ ] Phone auth behind a build flag, **off** in v1
- [ ] Minimal `Keychain` wrapper, no dependency

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
