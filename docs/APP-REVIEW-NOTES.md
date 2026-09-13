# App Review — the note, and how the demo account works

Two things live here: the block to paste into **App Store Connect → App Review Information →
Notes**, and the runbook behind it. Keep them together; the note is only true as long as the
runbook has been run.

---

## 1. Paste this into App Review Information → Notes

> Blind Drop is a daily song game for a small private group. One song each per day, everyone's
> submission stays hidden until an 8:00 PM reveal, then the group guesses who dropped what.
>
> **The demo account runs on an accelerated clock.** On a normal account the reveal happens
> once a day at 8:00 PM and the guessing window is two hours, so the full game would not be
> reachable during a single review session. The account below is on a review schedule instead:
> the round advances as soon as you act, at any hour of the day or night.
>
> 1. Sign in with the credentials above. You are "App Reviewer", in a group of six.
> 2. Tap **Drop a song**, search for anything, pick it, and tap **Seal it**.
> 3. The seal screen shows a countdown of about **12 seconds**. On a normal account this
>    counts down to 8:00 PM; here it is seconds. Wait for it.
> 4. The reveal appears: six songs, no names — yours among them. Tap each card and name who
>    you think dropped it, then tap **Lock in guesses**. Your own song is marked and needs no
>    guess, so there are five names to place.
> 5. A second countdown of about **20 seconds** runs, then the answers and scores appear.
> 6. Roughly two minutes later a fresh round opens and you can play again as many times as
>    you like. Past nights are under **The Record**, reachable from the top of the screen.
>
> The text on the seal screen still reads "Sealed until 8:00 PM" because that is the group's
> real reveal hour — only the countdown is accelerated for review.
>
> The other five members of the group — Kai, Mo, Nell, Rae and Sol — are fixtures with
> pre-filled songs so that the reveal has something in it; no real user's data is visible to
> this account.
>
> Sign in with Apple is the only sign-in method offered to the public. The email/password
> field is present for this review account.
>
> **What the app does, and for whom.** Blind Drop is a daily guessing game for one private
> group of friends who already know each other. It is not a music player, a playlist app or a
> social network: there is no feed, no discovery, no public profile, and no way to reach anyone
> you were not invited alongside. The problem it solves is that sending songs to friends is a
> firehose nobody reads; one song a day, hidden until a fixed hour, turns it into something the
> whole group actually shows up for.
>
> **User-generated content, reporting and blocking.** The content members create is a display
> name and, for admins, a one-line "cue" for the night. Songs themselves come from Apple's
> catalog and are never uploaded. **To report a member:** open the circle from the header menu
> (Group), tap the ⋯ on any member's row, choose *Report member*, and pick one of four reasons.
> Reports are available to every member, not only admins, and go to us rather than to the
> circle. **Blocking** works by leaving: a member can leave a circle at any time from the foot
> of the same screen, and an admin can remove any member from that same ⋯ menu. There is
> deliberately no per-user content hiding, because concealing one member's card while a round is
> still hidden would reveal to the viewer which card belongs to that person and break the
> blindness the game depends on.
>
> **Third-party material.** Blind Drop hosts no audio. Song metadata, artwork and the
> thirty-second previews are served by the Apple Music API under the Apple Developer Program
> License Agreement; Spotify links and playlist export use the Spotify Web API under Spotify's
> Developer Terms of Service, authorised by the member with PKCE. A member's "drop" is a
> reference to a catalog track (an ISRC), never an upload.
>
> **External services.** Supabase (hosted Postgres, authentication and Edge Functions), the
> Apple Music API (catalog search, artwork, previews), the Spotify Web API (track matching and
> playlist export), and Apple Push Notification service. There is no analytics SDK, no
> advertising SDK, no crash reporter, no AI service, and no third-party tracking of any kind.
>
> **Regions.** The app behaves identically in every country it is available in. There are no
> regional features, no regional content and no regional pricing; it is free everywhere. It is
> not offered in Vietnam.
>
> **Permission prompts you will see.** Notifications are requested only after you have played a
> round, never at launch. Apple Music access is requested only if you choose to export The
> Record to an Apple Music playlist. Photo library "add" access is requested only if you choose
> Save Image on a share card.
>
> **Account deletion** is in the app: the header menu → Settings → Delete account. It removes
> the account and its notification tokens; past songs and guesses remain in the circle's history
> as "Former member" so other members' scores stay correct.

**Demo account:** `demo@blinddrop.dev` — put the password in the App Store Connect password
field, not in the note.

### Devices and systems tested — fill this in before each submission

App Review asks for this explicitly. Name real devices and real OS versions; "latest iOS" is
not an answer, and an unanswered one is what triggered the 2.1 information request on the
owner's previous app.

| Device | iOS |
|---|---|
| iPhone 15 Pro (physical) | *fill in* |
| iPhone 17 (simulator) | 26.x |

### The screen recording

The same 2.1 letter asks for a recording made on a **physical device**, starting with launch.
One continuous take covers every item it lists:

1. **Delete the app and reinstall first.** Both the notification permission and Apple Music
   access are one-shot; without a fresh install neither prompt can be filmed again.
2. Launch → Sign in with Apple → the notification pre-prompt, then the system dialog.
3. Drop a song → Seal it → the reveal → guesses → answers. On the demo account the countdowns
   are seconds, so this takes about a minute.
4. The Record → export to Apple Music → the Apple Music permission prompt.
5. The circle → a member's ⋯ → **Report member** → a reason → the confirmation. This is the
   UGC reporting mechanism the letter asks to see.
6. Settings → **Delete account**.

Film step 6 on a throwaway account, or re-run `seed-app-review-demo.sql` afterwards — deleting
the review account is what the reviewer signs in with.

---

## 2. What is actually deployed

Project `blind-drop` (`ojzwgaffeegssfscoaiv`, `us-west-1`).

| | |
|---|---|
| Migrations | `20260815090000_demo_groups`, `20260815090500_demo_lifecycle`, `20260815120000_backfill_demo_groups` — pushed 2026-08-15; `20260910120000_demo_room_of_six` — pushed 2026-09-10 |
| Edge Function | `rounds` redeployed 2026-08-15 (the two `demo_arm` calls and the `demo_tick` before the round read) |
| Demo group | "App Review", `is_demo = true`. Members: **App Reviewer** (admin, `demo@blinddrop.dev`) plus fixtures Kai, Mo, Nell, Rae, Sol |
| State | Verified 2026-09-11: six members, seven finished nights in The Record, and one open round already holding the five fixtures' drops and not the reviewer's. The night count grows as the account is played; `seed-app-review-demo.sql` resets it to three. |

The real pilot group ("Family") is **not** a demo group and is untouched by any of this. The
exclusion is enforced in both directions — `ensure_rounds()` and all three `tick_rounds()`
loops skip demo groups, and `demo_arm()`/`demo_tick()` no-op on a group that is not one.
See `02-DOMAIN-RULES.md` §6 and `03-DATA-MODEL.md` §4.1.

---

## 3. Runbook

**Nothing decays.** The previous fixture script wrote a `revealed` round anchored to `now()`
that hosted cron swept into `scored` within the hour, so it had to be re-run shortly before
the reviewer opened the app. This one does not: the loop is driven by the reviewer's own
actions, so it is correct at any hour, indefinitely, and re-running is optional.

Re-run only if you want a clean slate — a fresh three-night archive and an unplayed round:

```bash
cd server && npx supabase db query --linked --file scripts/seed-app-review-demo.sql
```

It deletes every round in the App Review group and rebuilds them, so anything the reviewer
already played is discarded. It touches no other group. It is safe to run repeatedly.

To check the state without changing it:

```bash
cd server && npx supabase db query --linked --file scripts/status-app-review-demo.sql
```

### If the reviewer reports being stuck

- **"Nothing happens after I seal."** The reveal needs every member to have submitted. The
  three fixtures are seeded at roll, so this only happens if their submissions were removed —
  re-run the provisioning script.
- **"It says I joined after the reveal."** `demo_provision()` backdates the membership seven
  days for exactly this reason; re-running fixes it.
- **"The Record is empty."** Provisioning has not been run against this group. Run it.

### If the review account is ever recreated

`demo_provision()` needs the group to exist, and `assign_pilot_cohort()` only creates it on the
account's first `PUT /me`. Sign in once in the app, then run the script.

---

## 4. What was deliberately left out

An in-app "review mode" banner reconciling "Sealed until 8:00 PM" with a twelve-second
countdown. It would have cost a `GroupDTO` field, a `groups_current.json` golden, a copy-deck
entry, a strings entry and new goldens across the snapshot matrix — for a fact that belongs in
§1 above. That decision stands.

**What no longer stands is "server-only".** This section used to end by saying the demo
environment shipped with no iOS diff at all, and that turned out to be the reason it did not
work. The accelerated clock is the server moving `reveals_at` and `scores_at` out from under a
client that had already fetched them, and the client was keeping its copies: sealing armed a
twelve-second reveal that never reached the sealed screen's countdown, and the reveal's
countdown was pinned to the real two-hour window for the life of the screen. Only backgrounding
the app advanced a phase. Both are fixed in `bfd8a42` — the client now refetches the round after
a seal, and the reveal's answers instant follows the round across a refetch.

Neither fix is demo-specific, and neither one lets the client decide a phase (`CLAUDE.md` §2.2):
on a real circle they are one idempotent GET returning the value already on screen. But the demo
is what made a latent "the client trusts a timestamp it copied" bug into a visible one, and it is
why `E16-02`'s app walk is not an optional last step.
