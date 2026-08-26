# E31 — Conditional reminders, not a universal nudge

One slice, from `docs/17-NEXT-FEATURES.md` §5.

> **Owner amendment — lifts `CLAUDE.md` §2.6's 3-deliveries/user/day cap.** Decided directly by the
> owner while `docs/17-NEXT-FEATURES.md` was being written, the same way ADR-011 amended the
> original single-circle version of this rule. `CLAUDE.md` §2.6, `docs/05-JOBS-AND-NOTIFICATIONS.md`
> §3's kind table and "closed set" language, and `docs/16-OUT-OF-SCOPE.md` §5's "a fourth daily
> notification [is a spec violation]" line all currently say the opposite of what this epic ships.
> **All three must be edited in the same commit as the code** — this is not a silent rewrite, and
> the epic is not done while any of the three still asserts the old cap.

---

### E31-01 — Two conditions replace one universal nudge

**Status:** wip
**Deps:** —
**Parallel:** yes
**Reads:** `docs/17-NEXT-FEATURES.md` §5, `docs/05-JOBS-AND-NOTIFICATIONS.md` (all), `docs/03-DATA-MODEL.md` §4
(`tick_rounds()`), `CLAUDE.md` §2.6, `docs/16-OUT-OF-SCOPE.md` §5, `docs/11-COPY-DECK.md`
**Touches:** `CLAUDE.md`, `docs/05-JOBS-AND-NOTIFICATIONS.md`, `docs/16-OUT-OF-SCOPE.md`,
`docs/11-COPY-DECK.md`, a new `server/supabase/migrations/NNNN_conditional_reminders.sql`,
`server/supabase/functions/push-worker/worker.ts`, `server/supabase/tests/functions/push.test.ts`,
`server/supabase/tests/functions/apns.test.ts`, `server/scripts/audit-leak.mjs`, `server/supabase/tests/db`
(new pgTAP for the `tick_rounds()` scan windows)
**Verify:** `cd server && npm run test:db && npm run test:functions && npm run audit:leak`.
Manually against the local stack: advance the fixture clock through `reveals_at − 2h`,
`reveals_at − 30m`, and `scores_at − 30m` with a mix of submitted/unsubmitted/guessed fixture
members, and confirm each outbox row's audience matches the condition exactly at enqueue time, and
that a member who completes the action between enqueue and claim is skipped, not sent.
**Proves:** AC-3

Retires the unconditional `nudge` (`reveals_at − 2h`, sent to every active member regardless of
submission status) and replaces it with:

| Kind | When | Audience |
|---|---|---|
| `seal_reminder` (1st) | `reveals_at − 2h` | members who **haven't submitted** yet |
| `seal_reminder` (2nd) | `reveals_at − 30m` | members who **haven't submitted** yet |
| `guess_reminder` | `scores_at − 30m` | submitters who **haven't finished guessing** yet |

`reveal`/`void` (`reveals_at`) and `results` (`scores_at`) are unchanged. `seal_reminder` fires up
to twice per round; `guess_reminder` once. Worst case for a fully disengaged member in one circle
is now **up to 5 pushes in an evening** — the doc updates below must say this plainly, not leave it
implicit.

- [ ] `tick_rounds()` gains three new scan windows, computing "members without a submission" (for
      both `seal_reminder` firings) and "submitters without a complete guess sheet" (for
      `guess_reminder`) at enqueue time — same mechanism the old 2-hour nudge scan already used,
      just a real condition instead of "everyone."
- [ ] `claim_notification_outbox` gets a settle-check for `seal_reminder`/`guess_reminder`
      mirroring the existing `settled_invitations` pattern used for `invite`
      (`20260820110000_notification_delivery_budget.sql`): skip sending, mark `sent_at`, if the
      recipient's condition already resolved by claim time. This is a deliberate break from
      `docs/05`'s prior guarantee that round-kind audiences are frozen forever at enqueue — say so
      in the doc, not just in the migration comment.
- [ ] The multi-circle same-hour grouping rule (`E23-02`) still applies within each kind
      independently.
- [ ] `worker.ts`'s deep-link/expiration switch gets cases for `seal_reminder`/`guess_reminder`,
      reusing the existing `.round(groupID:)` deep link
      (`blinddrop://circle/<GROUP_ID>/round/current`) — no iOS routing change is expected;
      `App/DeepLink.swift` and `PushRouter.swift` already handle this link shape generically.
- [ ] New push copy added to `docs/11-COPY-DECK.md` in this commit (`CLAUDE.md` §6 — don't invent
      strings elsewhere). These are addressed to the recipient about their own status, so — unlike
      the old nudge's deliberately neutral body — they may say "you haven't sealed a song yet" or
      similar; they still must never mention anyone else's status or a count.
- [ ] `CLAUDE.md` §2.6, `docs/05` §3, `docs/16` §5 all edited to match the table above, in this
      commit.
- [ ] Existing exactly-3/day assertions (`push.test.ts`, `apns.test.ts`, `audit:leak`) found and
      explicitly revised to the new model — not left to fail and get silently loosened.
