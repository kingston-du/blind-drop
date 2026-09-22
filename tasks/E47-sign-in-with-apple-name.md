# E47 — Sign in with Apple, as Apple requires it

App Review rejected build **1.0 (2)** on 2026-09-21 under **guideline 4 — Design**, reviewed on
an iPad Air 11-inch (M3):

> The app offers Sign in with Apple as a login option but does not follow the design and user
> experience requirements for Sign in with Apple. Specifically, users are required to provide
> their name and/or email address after using Sign in with Apple even though that information is
> already provided by the Authentication Services framework.

They are right, and the cause is one line. `AppleSignIn` set `request.requestedScopes = []` on
purpose — *"a field we do not need is a field we cannot leak"* — and `docs/08` §1.2 then made
every new user type a name before it would let them past. Apple was never asked for the name it
was holding, and the user was asked for it instead. That is the rejection, exactly.

**What the fix must not do.** The display name is not an account field the app happens to need:
it is *"the name people guess with"* (`docs/11`, `onboarding.name.help`), and a name nobody
chose and nobody has seen is discovered in front of the circle at the next reveal. So adopting
Apple's name silently trades one bad outcome for another. The slice below does both halves —
never ask, always show.

**The shape of it, and the bound on each part:**

- **`.fullName`, never `.email`.** The app sends no mail and stores no address (`docs/14` §9).
  The rejection is about not re-asking for what was provided; it is not a licence to collect
  more.
- **Given name, not the full name.** `Ana`, not `Ana Beltrán`. The field it replaces is
  placeheld *"First name"*, and a guess sheet reads like a room of people rather than a contact
  list. The full name is the fallback for an Apple ID that carries no given name.
- **Adopted only when the server says `NO_PROFILE`.** Apple sends a name on the first
  authorization of an Apple ID and never again, so an existing name cannot be overwritten — but
  the guard is written rather than inferred from Apple's behaviour.
- **A failed save is not a failed sign-in.** The state stays `.noProfile` and `docs/08` §1.2
  appears, which is the same screen the returning Apple ID gets and is allowed: nothing was
  provided to re-ask for.
- **One row, not one step.** *Playing as Ana · Change* under the title on 1.3, opening a sheet.
  A second screen — even a pre-filled one — is the thing the rejection forbids.

---

### E47-01 — The name comes from Apple

**Status:** wip · **Deps:** — · **Parallel:** no
**Reads:** `docs/08` §1.1–§1.3, `docs/13` §4, `docs/14` §5 and §9, `CLAUDE.md` §2, this file
**Touches:** `ios/BlindDrop/Core/Auth/`, `ios/BlindDrop/Features/Onboarding/`,
`ios/BlindDrop/Features/Settings/SettingsScreen.swift`, `Localizable.strings`,
`docs/08`, `docs/11`, `docs/14`, `docs/APP-REVIEW-NOTES.md`
**Verify:** `./ios/scripts/lint.sh`; iOS unit + snapshot; simulator pass over sign-in → 1.3 →
the rename sheet
**Proves:** guideline 4's requirement, and no change to any round payload (AC-1 untouched —
nothing in this slice reads or writes round state)

- [x] The authorization requests `.fullName`; the account-deletion re-auth still requests
      nothing (`AppleSignIn(requestsName:)`).
- [x] `AppleSignIn.displayName(from:)` reduces Apple's components to one name: given name
      first, full name as a fallback, cleaned and length-checked by `DisplayName`, `nil` when
      there is nothing usable.
- [x] `SessionStore.adoptAppleName(_:)` saves it only when the state is `.noProfile`, and a
      failure leaves the session signed in on `.noProfile`.
- [x] A first-time user never sees `docs/08` §1.2. A returning Apple ID with no profile still
      does, unchanged.
- [x] 1.3 shows *Playing as <name>* with **Change**, opening `DisplayNameSheet` — no accent, no
      new blocking step, 44pt target, one VoiceOver button.
- [x] New copy in `docs/11` and `Localizable.strings`: `onboarding.group.identity`,
      `onboarding.group.identity.change`, `onboarding.name.save`.
- [x] `AuthTests` covers all four outcomes (adopted, not overwritten, absent, refused) and the
      name reduction; a `JoinOrCreate-playingas` golden covers the row across the matrix.
- [x] `docs/08` §1.2, `docs/14` §5 and §9, and the App Review note say what changed and why.

> **Open question:** whether to show the row on 1.4 and 1.5 as well. Left off deliberately —
> 1.3 is the screen every signed-in user without a circle passes through, and repeating an
> identity line on the create form would start to read as a header the app does not otherwise
> have. Settings is where a name is changed after onboarding, and already was.
