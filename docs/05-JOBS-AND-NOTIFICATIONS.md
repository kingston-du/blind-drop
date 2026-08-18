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
       url     := current_setting('app.functions_url') || '/push-worker',
       headers := jsonb_build_object(
                    'Authorization', 'Bearer ' || current_setting('app.service_key'),
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

---

## 2. Idempotency

Three layers, all required:

1. **Guarded transition.** Every state change is
   `update rounds set state = <new> where id = $1 and state = <expected>` and the code
   branches on the affected row count. A second run affects zero rows and does nothing.
2. **Outbox unique key.** `unique (round_id, kind)` on `notification_outbox`. Enqueue is
   `on conflict do nothing`. A retried transaction cannot create a second notification.
3. **Send marker.** The worker claims rows with
   `update … set attempts = attempts + 1 where sent_at is null … returning *` inside a
   transaction using `for update skip locked`, sends, then sets `sent_at`. A crash between
   send and marking can duplicate **at most one** batch; APNs `apns-collapse-id` (§4) makes
   that invisible to the user.

Transition and enqueue happen in **one transaction**. Never enqueue first.

---

## 3. The three notifications

> **Amended by the owner — ADR-011, `CLAUDE.md` §2.6.** The budget is now three *deliveries*
> per user per day across **all** their circles, grouped where they coincide; it did not grow
> with the circle count. The kinds below are unchanged and `invite` joins them in `E20-03`.
> `E23-02` brings this section in line. Until it lands, what follows is what the code does.

Exactly three per day, maximum. This app earns trust by being quiet.

| # | When | Audience | Title / body | Deep link |
|---|---|---|---|---|
| 1 | `reveals_at` | all active members | *Tonight's drop is open.* | `blinddrop://round/current` |
| 2 | `scores_at` | members who **submitted or guessed** | *Answers are in.* | `blinddrop://round/current/results` |
| 3 | `reveals_at − 2h` | active members with **no submission** in this round | *Two hours to drop.* | `blinddrop://round/current` |

Plus one conditional, replacing #1:

| — | `reveals_at`, when `S < 3` | all active members | *Not enough drops tonight. Nothing revealed.* | `blinddrop://round/current` |

That is the complete list. **No** streak reminders, **no** "your friend just posted", **no**
re-engagement nags, **no** "someone dropped a song". Adding a fourth notification is a
product change requiring the owner, not an agent.

### The nudge is the only targeted one

Notification #3 goes only to non-submitters. This is the single behaviourally-targeted push
and it must never reach someone who has already submitted. Two consequences:

- The audience is resolved **at enqueue time** (`reveals_at − 2h`) and frozen into
  `notification_outbox.audience`. Someone who submits at `−1h55m` still receives it. That is
  accepted: re-resolving at send time would mean the worker reads submission state, and a
  worker that reads submission state is one refactor away from an endpoint that does.
- The push body must not imply anything about others. *"Two hours to drop."* — not "you're
  the last one", not "3 people have dropped".

### The nudge is not a leak

A user who receives the nudge learns only that *they* have not submitted, which they already
knew. Verify the inverse too: a user who has submitted receives nothing at `−2h`, and silence
carries no information about others.

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
    "alert": { "title": "Blind Drop", "body": "Tonight's drop is open." },
    "sound": "default",
    "interruption-level": "active"
  },
  "kind": "reveal",
  "round_id": "r_…",
  "deep_link": "blinddrop://round/current"
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

> **Amended by the owner (ADR-011, `CLAUDE.md` §2.6).** Three *deliveries* per user per day
> across **all** their circles, grouped where they coincide — the budget did not grow with the
> circle count. `E23-02` brings this section and §3 in line; until then §3's per-round table is
> still what the code does.

No per-type toggles, no quiet hours, no in-app preference screen. Three pushes a day is
already quiet; a settings screen implies there is something to manage. Users who want silence
use iOS notification settings.

---

## 5. Deep links

URL scheme `blinddrop://`. Universal Links are out of scope except the invite landing page.

| URL | Destination |
|---|---|
| `blinddrop://round/current` | Today's round, phase-appropriate screen |
| `blinddrop://round/current/results` | Results for today's round |
| `blinddrop://record` | The Record |
| `blinddrop://join/<CODE>` | Join flow, code prefilled |

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

`E03` and `E06` each carry a test for the first row of this table — it is the one that
actually happens.
