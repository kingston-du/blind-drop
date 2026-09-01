# 05 — Jobs and notifications

---

## 1. The scheduler

Two `pg_cron` entries. That is the whole scheduler.

```sql
-- Advance round states and enqueue notifications. Also calls ensure_rounds().
select cron.schedule('tick', '* * * * *',
  $$ select public.tick_rounds(); $$);

-- Drain the outbox to APNs via the push-worker Edge Function.
select cron.schedule('push', '* * * * *',
  $$ select net.http_post(
       url     := (select decrypted_secret from vault.decrypted_secrets
                    where name = 'blind_drop_functions_url') || '/push-worker',
       headers := jsonb_build_object(
                    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets
                                                     where name = 'blind_drop_service_key'),
                    'Content-Type',  'application/json'),
       body    := '{}'::jsonb) $$);
```

Why a single global tick rather than one job per timezone: with one group per user and a
pilot-scale deployment, a per-minute scan of
`rounds where state in ('open','revealed') and reveals_at <= now()` is a single index hit
against `rounds_pending_tick`. Per-timezone jobs would multiply cron entries by ~30 for no
benefit and would need re-registration whenever a group is created. Revisit only if the
`rounds` table exceeds ~10⁵ live rows.

**Accuracy target:** a transition fires within 60 seconds of its target minute. A push that
arrives at 20:00:41 is fine; one that arrives at 20:04 is not, because the group experiences
the reveal together.

`tick_rounds()` is specified in `03-DATA-MODEL.md` §4. Read it there; it is the transactional
core and is not duplicated here.

### Deployment: two Vault secrets

> **E23-01, amended 2026-08-18.** `app.functions_url`/`app.service_key` database GUCs were the
> original design here and are what `0016_cron.sql`'s tests first shipped against — but they do
> not work on a hosted project. Verified live: the `postgres` role on hosted Supabase is not a
> real superuser (`select rolsuper from pg_roles where rolname = current_user` returns `false`),
> and `alter database postgres set app.functions_url = …` fails with
> `42501 permission denied to set parameter "app.functions_url"`. No connection method changes
> that — it is a role-privilege restriction, not a client quirk. The GUC design in earlier
> revisions of this doc was never actually exercised against a hosted project before being
> written down; this section corrects that.
>
> The `push` and `links` jobs above instead read two **Vault secrets** at call time —
> `blind_drop_functions_url` and `blind_drop_service_key` — via `vault.decrypted_secrets`. Same
> property the GUC design was after: neither value is ever a literal in `cron.job.command`,
> where anyone with `select` on the catalog could read it (`0016_cron.sql`'s tests still assert
> this, now against the Vault pattern). On a project where these secrets have never been set,
> both jobs fail on their first line, every minute, silently — the subquery returns no row, so
> `url`/`Authorization` become `null`, `net.http_post` sends a request to nowhere. The failure
> lands in `cron.job_run_details`, which nothing in this app queries. See
> `tasks/E23-notifications.md` for how the original (GUC) failure mode was diagnosed.
>
> **The one-time step, per environment**, run by whoever has admin access to that Supabase
> project (SQL editor, or `supabase db query --linked --file …` with an uncommitted file — never
> a migration):
>
> ```sql
> select vault.create_secret('https://<project-ref>.supabase.co/functions/v1', 'blind_drop_functions_url');
> select vault.create_secret('<the project''s current sb_secret_… key>', 'blind_drop_service_key');
> ```
>
> **The key must be the project's current `sb_secret_…` secret API key, not the legacy
> `service_role` JWT.** `push-worker`'s `requireServiceRole` check (`_shared/auth.ts`) is a plain
> equality against the deployed function's `SUPABASE_SERVICE_ROLE_KEY` — once a project has
> migrated to the new API-key system, the platform binds that env var to the `sb_secret_…` key,
> and the legacy JWT is rejected with a 401 even though it is still listed as a valid, unrevoked
> key in the dashboard. Verified by direct `curl` against the deployed function: legacy JWT → 401,
> `sb_secret_…` → 200. Rotation is `vault.update_secret`, never a migration or a rescheduled job.
> Verify with `select decrypted_secret from vault.decrypted_secrets where name = 'blind_drop_functions_url';`.
>
> Locally, `seed.sql` parks all four named jobs (`set_blind_drop_jobs_active(false)`) precisely
> so `test:db`/`test:functions` never race a live scheduler — the Vault secrets are never set
> locally either, on purpose, since nothing local depends on them being set.

---

## 2. Idempotency

Three layers, all required:

1. **Guarded transition.** Every state change is
   `update rounds set state = <new> where id = $1 and state = <expected>` and the code
   branches on the affected row count. A second run affects zero rows and does nothing.
2. **Outbox unique key.** Scheduled alerts use `unique (round_id, kind)` on
   `notification_outbox`; a direct invitation is keyed by its invitation id. Enqueue is
   idempotent, and concurrent pending invitations for one recipient share the one unsent invite
   delivery. A retried transaction cannot create a second notification.
3. **Send marker.** The worker claims rows with
   `update … set attempts = attempts + 1 where sent_at is null … returning *` inside a
   transaction using `for update skip locked`, sends, then sets `sent_at`. A crash between
   send and marking can duplicate **at most one** batch; APNs `apns-collapse-id` (§4) makes
   that invisible to the user.

Transition and enqueue happen in **one transaction**. Never enqueue first.

---

## 3. The round notifications and invitations

> **Amended by the owner — `docs/17-NEXT-FEATURES.md` §5, on the same footing as ADR-011,
> `CLAUDE.md` §2.6.** The unconditional `nudge` is retired for two conditional reminders,
> `seal_reminder` (up to twice a round) and `guess_reminder` (once a round), and the old
> 3-deliveries/24h cap is lifted to admit them: a fully disengaged member in one circle can now
> see up to five pushes in an evening. What the cap protected — a quiet app, and one grouped push
> per coincident same-kind event across circles — is unchanged; only the fixed ceiling is gone.
> `E23-02`'s cross-circle grouping still applies, per kind.

This app earns trust by being quiet, not by a fixed daily number. Round transitions make the
five kinds below; `invite` is the one prompt kind, created with a direct invitation rather than
by `tick_rounds()`. `E23-02` applies cross-circle grouping to coincident scheduled deliveries of
the same kind — a person in three circles that reveal at the same hour gets **one** `reveal`
push, not three, and a person invited to several circles together gets **one** `invite`. A
grouped scheduled delivery uses the first deterministic round as its deep-link target; the
switcher exposes the other circles that changed at the same instant.

| # | When | Audience | Title / body | Deep link |
|---|---|---|---|---|
| 1 | `reveals_at` | all active members | *Tonight's songs are out.* | `blinddrop://circle/<GROUP_ID>/round/current` |
| 2 | `scores_at` | members who **submitted or guessed** | *Tonight's answers are in.* | `blinddrop://circle/<GROUP_ID>/round/current/results` |
| 3 | `reveals_at − 2h` | members who **haven't submitted yet** | *You haven't sealed a song yet. Two hours left.* | `blinddrop://circle/<GROUP_ID>/round/current` |
| 4 | `reveals_at − 30m` | members who **haven't submitted yet** | *Half an hour left, and you haven't sealed a song.* | `blinddrop://circle/<GROUP_ID>/round/current` |
| 5 | `scores_at − 30m` | submitters who **haven't finished guessing yet** | *Half an hour left to guess who dropped what.* | `blinddrop://circle/<GROUP_ID>/round/current` |

Rows 3 and 4 are both `seal_reminder` — the same kind, firing at most twice a round, at two
different scheduled instants. Row 5 is `guess_reminder`, firing at most once. Worst case for a
fully disengaged member in one circle, in one evening — drops right before reveal, never opens
the guess sheet: both `seal_reminder`s, `reveal`, `guess_reminder`, `results`. Five pushes,
stated here plainly rather than left for someone to discover later.

Plus one conditional, replacing #1:

| — | `reveals_at`, when `S < 3` | all active members | *Not enough drops tonight. Nothing revealed.* | `blinddrop://circle/<GROUP_ID>/round/current` |

| Kind | When | Audience | Title / body | Deep link |
|---|---|---|---|---|
| `invite` | direct invitation created | that invitation's recipient | *You have a group invite.* | `blinddrop://invite/<INVITATION_ID>` |

That is the complete closed set — six kinds. **No** streak reminders, **no** "your friend just
posted", **no** re-engagement nags, **no** "someone dropped a song". Adding a seventh
notification is a product change requiring the owner, not an agent.

### The reminders are personal, not a headcount

`seal_reminder` and `guess_reminder` are each addressed to the recipient about their **own**
status — unlike the old `nudge`, which went to every active member including people who'd
already dropped, these two only ever reach someone whose own condition (no submission; an
incomplete guess sheet) is still true when the reminder is enqueued. That is why the copy may say
"you haven't sealed a song yet" — it is never a claim about anyone else, and never a count.
`CLAUDE.md` §2.1's no-leak rule still applies in full: no mention of another member's status, no
number that moves with participation.

### Audiences can change between enqueue and send — a deliberate, scoped break

Every notification kind before this slice had its audience **frozen forever** at enqueue: "a
later join or leave does not rewrite it" held without exception, because `reveal`/`void`/`results`
are decided by the same transaction that freezes their audience, and the old `nudge` didn't care
who had submitted. `seal_reminder` and `guess_reminder` are enqueued up to two hours (or thirty
minutes) before the condition they describe is checked again, and that condition can turn true in
between — someone drops a song, or finishes their guess sheet, before the worker actually sends.
Re-sending "you haven't sealed a song yet" to someone who sealed ten minutes ago would be wrong,
not merely stale, so `claim_notification_outbox` re-checks each of these two kinds' recipients at
claim time and drops anyone whose condition has since resolved before the push goes out —
mirroring the `settled_invitations` pattern that already retires a pending-invitation row whose
invitation is no longer pending, but at the granularity of one recipient inside a shared audience
rather than a whole row, since a `seal_reminder`/`guess_reminder` row commonly holds several
recipients at once and only some may have resolved
(`20260826120100_conditional_reminders.sql`). `reveal`, `void`, `results`, and `invite` keep the
old frozen-forever guarantee, unchanged.

---

## 4. APNs

Token-based auth (`.p8` key, ES256 JWT), HTTP/2, from `functions/push-worker/`.

```
POST https://api.push.apple.com/3/device/<token>          (production)
POST https://api.sandbox.push.apple.com/3/device/<token>  (sandbox)

authorization:      bearer <ES256 JWT, iss=TEAM_ID, kid=KEY_ID, iat=now>
apns-topic:         <bundle id>
apns-push-type:     alert
apns-priority:      10
apns-collapse-id:   <round_id>:<kind>
apns-expiration:    <unix seconds>
```

```jsonc
{
  "aps": {
    "alert": { "title": "Blind Drop", "body": "Tonight's songs are out." },
    "sound": "default",
    "interruption-level": "active"
  },
  "kind": "reveal",
  "round_id": "r_…",
  "deep_link": "blinddrop://circle/<GROUP_ID>/round/current"
}
```

- **JWT cache:** Apple rejects tokens regenerated more than once per 20 minutes and expires
  them at 60. Generate once, cache in module scope, refresh at 50 minutes.
- **`apns-collapse-id`** makes a duplicated batch collapse into one visible notification.
  This is why the at-most-once-extra-batch behaviour in §2 is acceptable.
- **`apns-expiration`** = the end of the phase the push refers to. A reveal push that could
  not be delivered before 22:00 must not arrive at midnight; set expiration to `scores_at`.
  The results push expires 12 hours out.
- **410 Unregistered** → set `devices.disabled_at = now()`. Never retry that token.
- **429 / 5xx** → leave `sent_at` null, let the next minute retry. After `attempts >= 5`,
  record `last_error` and stop; a human looks at it. Do not retry forever.
- **Batching:** send per device with bounded concurrency (16). Target: all devices in a group
  within 20 seconds of each other (`01-ARCHITECTURE.md` §6).

### Registration

The client calls `POST /devices` after the user grants notification permission, and again on
every launch (cheap upsert, refreshes `last_seen_at`). Permission is requested **after** the
first successful seal, never at launch — the ask lands when the user has just learned that
something happens at 8:00 PM and has a reason to want to be told.

### There are no notification settings

> **ADR-011, `CLAUDE.md` §2.6; amended by `E31-01`.** Deliveries are grouped where the kind and
> scheduled instant coincide across **all** a user's circles — that part of ADR-011 stands. The
> fixed daily delivery ceiling it also introduced does not: `E31-01` lifted it to admit
> `seal_reminder`/`guess_reminder` (§3).

No per-type toggles, no quiet hours, no in-app preference screen. A handful of pushes a day,
every one of them about something that actually happened or is about to, is already quiet; a
settings screen implies there is something to manage. Users who want silence use iOS
notification settings.

> **Amended by the owner, 2026-08-27.** That last sentence assumes the app is registered with
> iOS — but `PushRegistrar.skip()` (the pre-prompt's **Not now**) never calls
> `requestAuthorization()`, so a person who declines the pre-prompt is never asked at the system
> level either, and never appears in Settings → Notifications at all. Combined with "no second
> ask, ever," that person had zero way back in, forever, from a single soft tap. `Settings` now
> shows one narrow, self-erasing row — **only** while `hasDeclinedNotifications` is true and
> `authorizationStatus` is still `.notDetermined`, i.e. only in that exact dead end. It calls the
> same `allow()` the pre-prompt does; once the real dialog answers, the row is gone for the life
> of the install, same as everything else in this section. It is not a preference to manage and
> is not per-type — it is the one place this rule's own "use iOS Settings" escape hatch was
> unreachable. See `PushRegistrar.canRecoverNotifications` and `SettingsStore.swift`.
>
> **Further amended by the owner, 2026-08-27, same day.** This app's users are a known, small
> circle, several of whom were already stuck in that dead end before the fix above landed.
> Rather than leave them to discover the `Settings` row on their own, the pre-prompt is shown
> again automatically — the same sheet, not a new one — the first time this build launches for
> a stuck install. This is a bounded, one-time catch-up (`LocalFlags
> .hasOfferedNotificationRecoveryOnLaunch`), not a standing "ask again" policy: it fires at most
> once, ever, per install, and after that the `Settings` row is the only way back, exactly as
> above. See `PushRegistrar.offerNotificationRecoveryOnLaunchIfNeeded`, called once per launch
> from `BlindDropApp`.

---

## 5. Deep links

URL scheme `blinddrop://`. Universal Links are out of scope except the invite landing page.

| URL | Destination |
|---|---|
| `blinddrop://round/current` | The active circle's round, phase-appropriate screen |
| `blinddrop://round/current/results` | The active circle's results |
| `blinddrop://circle/<GROUP_ID>/round/current` | That circle's round, phase-appropriate screen |
| `blinddrop://circle/<GROUP_ID>/round/current/results` | That circle's results |
| `blinddrop://record` | The Record |
| `blinddrop://join/<CODE>` | Join flow, code prefilled |

**A circle prefix, since `E19-01`** (`docs/01` ADR-011): `blinddrop://circle/<GROUP_ID>/round/current`,
`…/circle/<GROUP_ID>/round/current/results`, and `…/circle/<GROUP_ID>/record` name which
circle the link belongs to. The bare forms above are unchanged and still mean "the active
circle" — every link this table already promised keeps resolving exactly as it did before a
second circle existed. `blinddrop://join/<CODE>` is never circle-prefixed: joining is how a
circle is acquired, not a thing that already has one. Parsing a circle-prefixed link is
`E19-01`; switching to the named circle before landing on it is `E19-03`.

A deep link **never** shortcuts a phase gate. `blinddrop://round/current/results` opened at
21:30 lands on the guess screen with no error — the client asks the server what phase it is
and renders that. A deep link is a navigation hint, not an authorization.

**A join link works whether or not the caller already has a circle** (`E38-02`). `Router` used
to discard `blinddrop://join/<CODE>` outright for a signed-in caller who was already in a group,
on the reasoning that the server would answer `ALREADY_IN_GROUP` and that tapping your own
invite is not worth a toast. Under ADR-011 that is wrong: a person may hold three circles, and
a code arriving at a `ready` session almost always names one they are **not** in.
`ALREADY_IN_GROUP` is raised only for the circle they are actually in. The link now prefills a
sheet in both states — `JoinOrCreateScreen` with no circle, `JoinCircleSheet` with one — and, as
above, **prefills only**: it never joins, because a forwarded message must not put somebody in a
circle they did not choose.

Invite links are `https://blinddrop.app/j/<CODE>` with an `apple-app-site-association` file,
falling back to a static landing page with the code shown for manual entry. The landing page
is the only web surface in v1 (`16-OUT-OF-SCOPE.md`).

---

## 6. Failure modes and what they must not do

| Failure | Behaviour | Must not |
|---|---|---|
| Cron down for 3 hours, comes back at 23:00 | Round transitions `open → revealed → scored` on the next tick. Both pushes fire, once each. | Skip a state. Fire twice. Void a round that had ≥3 submissions. |
| APNs unreachable at 20:00 | Outbox row stays unsent, retries each minute until `apns-expiration`. | Block the state transition. |
| `push-worker` times out mid-batch | Unsent rows retried next minute; collapse-id hides the overlap. | Mark `sent_at` before the send completes. |
| A group's timezone is deleted from tzdata | `ensure_rounds()` raises for that group only, logs, continues to the next. | Abort the whole tick. |
| Clock skew on the DB host | Irrelevant within a minute; the tick is minute-granular. | — |
| Two `push-worker` invocations overlap | `for update skip locked` means they claim disjoint rows. | Send the same row twice. |
| `blind_drop_functions_url`/`blind_drop_service_key` Vault secrets unset or wrong (§1) | `push`/`links` fail before any request is built, or `push-worker` returns 401. | Look like an idle worker. See below. |

`E03` and `E06` each carry a test for the first row of this table — it is the one that
actually happens.

**E23-01.** Every failure mode above except clock skew ends the same way from the outbox's
point of view: a row that stays unsent. Before this slice, nothing surfaced that — a worker
that has never once run looked identical to a worker with nothing to send. `select
public.stuck_notifications();` (service role only, same lockdown as `claim_notification_outbox`)
returns any row unsent more than five minutes after `enqueued_at`, well past the 60-second
accuracy target in `01-ARCHITECTURE.md` §6. An empty result is the only "the push path is
healthy" a person should trust; a non-empty one names the stuck round, its `kind`, `attempts`,
and `last_error` (once it has one — see §2's send marker).
