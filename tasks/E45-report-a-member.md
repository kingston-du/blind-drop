# E45 — Report a member

App Review's UGC rule (guideline 1.2) asks four things of an app that carries user-generated
content. Blind Drop carries two pieces of it — a **display name** and a **hand-written cue**
(`E43`) — and today answers three of the four:

| 1.2 asks for | Blind Drop's answer |
|---|---|
| A filter for objectionable content | Songs come from Apple's catalog, already rated and labelled at the source. Names and cues are the only free text, and they are read by one closed, invite-only circle. No word list ships: the false-positive cost is real and the benefit at this scale is not. |
| **A way to report content** | **Missing. This epic.** |
| A way to block an abusive user | **Leaving the circle is the block**, and an admin can remove. Per-user content blocking is not merely unnecessary here, it is *unsafe*: hiding one member's card during `open` would tell the viewer which card is theirs, which is a direct `CLAUDE.md` §2.1 leak. |
| Published contact information | Live at `https://kingston-du.github.io/blind-drop-pages/support/`, and in the App Store listing. |

So the whole epic is the second row: one action, in a menu that already exists, on a screen that
already exists.

**The shape of it, and the reason for each bound:**

- **The group page's `⋯` menu, and nowhere else.** Not the round screens, not a card, not the
  Record. A report is about a *person*, and the group page is the only screen that lists people.
  Keeping it off the round screens is also what keeps §2.1 intact — nothing in this epic reads
  or writes round state.
- **Every member, not just admins.** Reporting is the one member action that is not an admin
  power; an abusive name is exactly the thing the people without the remove button need to raise.
- **A fixed reason list, never free text.** A free-text report field would be new user-generated
  content, moderated by nobody, which is the problem this epic exists to answer rather than a
  solution to it.
- **No push, no email, no inbox.** Reports land in a table the owner reads. "Timely response"
  is a promise about the owner, not a feature.

---

### E45-01 — A member can report a member

**Status:** wip · **Deps:** — · **Parallel:** no
**Reads:** `docs/02` §2, `docs/04` §3, `CLAUDE.md` §2, this file
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/groups/`,
`server/supabase/tests/`, `ios/BlindDrop/Core/Networking/Endpoint.swift`,
`ios/BlindDrop/Features/Settings/`, `Localizable.strings`, `docs/11-COPY-DECK.md`
**Verify:** `cd server && npm run test:db -- reports`; `npm run test:functions`;
`node server/scripts/lint.mjs`; `./ios/scripts/lint.sh`; iOS unit + snapshot; `npm run audit:leak`
**Proves:** AC-11 (nothing new on an `open`-phase payload)

- [x] `member_reports` table: reporter, group, reported member, reason, `created_at`. RLS on and
      forced, `revoke all` from `public`/`anon`/`authenticated`, service role only.
- [x] One report per reporter, per target, per day — a unique index, not a read-then-write.
- [x] `POST /groups/:group_id/members/:user_id/report` — proves membership of that circle,
      refuses a self-report, refuses a reason outside the closed set, and is idempotent within
      the day.
- [x] The `⋯` menu on the group page offers **Report** to every member, on every row but their
      own. Admin rows keep promote/demote/remove exactly as they were, self-demote included.
- [x] A fixed four-item reason list. No free-text field anywhere in the flow.
- [x] The reporter is told the report landed.
- [x] No round state is read or written anywhere in this slice; `audit:leak` still passes.

> **Open question:** whether a report should also be reachable from a member's profile screen.
> Left out deliberately — one entry point is easier to describe to App Review and easier to
> keep correct. Revisit only if a real report arrives that the group page could not have raised.
