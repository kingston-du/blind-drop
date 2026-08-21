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

> **Amended by the owner — ADR-011, `CLAUDE.md` §2.6.** Three *deliveries* per user in a rolling
> 24-hour window, across **all** their circles, grouped by kind where their scheduled instants
> coincide. The budget did not grow with the circle count; `E23-02` enforces it centrally.

Three deliveries per user in a rolling 24-hour window, maximum, across every circle. This app
earns trust by being quiet. Round transitions make the four kinds below; `invite` is the one
prompt kind, created with a direct invitation rather than by `tick_rounds()`. Its enqueue path
counts every existing delivery for the recipient and coalesces invitations waiting to send, so a
person invited to several circles together receives one notification. `E23-02` finishes the
same cross-circle grouping for coincident scheduled round deliveries. A grouped scheduled
delivery uses the first deterministic round as its deep-link target; the switcher exposes the
other circles that changed at the same instant.

| # | When | Audience | Title / body | Deep link |
|---|---|---|---|---|
| 1 | `reveals_at` | all active members | *Tonight's songs are out.* | `blinddrop://circle/<GROUP_ID>/round/current` |
| 2 | `scores_at` | members who **submitted or guessed** | *Tonight's answers are in.* | `blinddrop://circle/<GROUP_ID>/round/current/results` |
| 3 | `reveals_at − 2h` | all active members | *Two hours left to drop a song.* | `blinddrop://circle/<GROUP_ID>/round/current` |

Plus one conditional, replacing #1:

| — | `reveals_at`, when `S < 3` | all active members | *Not enough drops tonight. Nothing revealed.* | `blinddrop://circle/<GROUP_ID>/round/current` |

| Kind | When | Audience | Title / body | Deep link |
|---|---|---|---|---|
| `invite` | direct invitation created | that invitation's recipient | *You have a group invite.* | `blinddrop://invite/<INVITATION_ID>` |

That is the complete closed set. **No** streak reminders, **no** "your friend just posted", **no**
re-engagement nags, **no** "someone dropped a song". Adding a sixth notification is a product
change requiring the owner, not an agent.

### The nudge leaves a choice open

Notification #3 goes to every active member, including someone who has already dropped. It is a
quiet invitation to open the round and replace their song before reveal, not a signal about who
else has or has not submitted. Its audience is resolved and frozen at `reveals_at − 2h`; a later
join or leave does not rewrite it. The body stays personal and neutral: *"Two hours left to drop
a song."* — never "you're the last one" or "3 people have dropped".

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

> **ADR-011, `CLAUDE.md` §2.6.** Three *deliveries* per user in a rolling 24-hour window across
> **all** their circles, grouped where the kind and scheduled instant coincide. The budget does
> not grow with the circle count.

No per-type toggles, no quiet hours, no in-app preference screen. Three pushes a day is
already quiet; a settings screen implies there is something to manage. Users who want silence
use iOS notification settings.

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
