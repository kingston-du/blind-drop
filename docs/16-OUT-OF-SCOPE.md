# 16 — Out of scope for v1

Do not build these. **Do not add scaffolding for them**, with the single exception noted in
§2. A `// TODO: multi-group` and an unused `groupId` parameter are both violations — they
invite the next agent to fill them in.

---

## 1. Designed for, but not built

| Feature | Why it's deferred | What you may **not** do now |
|---|---|---|
| **Themed prompts** ("a song that reminds you of summer") | Changes the game's texture; needs its own design pass | No UI, no prompt selection, no admin field. The nullable column in §2 is the entire allowance. |
| ~~**Multiple groups per user**~~ | **Promoted to scope 2026-08-17 by the owner — ADR-011 supersedes ADR-005.** Built in `E18`–`E21`, capped per ADR-011. | The ban is lifted. What replaces it: every group-scoped route proves membership of *that* group explicitly, and nothing aggregates across circles. |
| **Reactions or comments on songs** | The group already has a group chat. Do not compete with it. | No reaction model, no comment table, no "hold to react" |
| **Head-to-head or cross-group play** | No | No cross-group anything |
| **Web presence** | Still deferred; `E27-03` is a spike that decides whether the beta needs more than the landing page, and where it would live | Nothing beyond the invite-link landing page (§3) until that spike reports |

---

## 2. The one allowed piece of scaffolding

```sql
Round.prompt text   -- nullable, always NULL in v1, no UI
```

That is the complete allowance, quoted from the PRD. It exists so that adding themed prompts
later is a migration-free change on the storage side.

There is **no** corresponding field in any API response, no field in any DTO, and no UI. If
you find yourself adding `prompt` to `RoundDTO`, stop.

---

## 3. Not built, and not planned

- **Android.** iOS only.
- **iPad layouts.** iPhone only, portrait only.
- **Dark mode.** Owner amendment A1 — light mode is v1's realized theme
  (`07-DESIGN-SYSTEM.md`).
- **In-app audio hosting or a real player.** Previews only, 30 seconds, from the catalog,
  never autoplaying, never queued, never backgrounded.
- **Public discovery or feeds.** There is no surface where a non-member sees anything.
- **Streaks, badges, XP, levels, cosmetics, avatars, profile customisation.** The two numbers
  are readability and ear. That is the entire progression system. The profiles of `E24` show
  those two numbers and a history; they are a lens on existing data, not a new one, and they
  carry no bio, no followers, and no editable surface.
- **Notification settings.** Three deliveries a day, grouped across circles, is already quiet
  (`05-JOBS-AND-NOTIFICATIONS.md` §4, `CLAUDE.md` §2.6).
- **Analytics, telemetry, or a crash reporter with PII.** None in v1.
- **Offline mutation queueing.** A submission that lands at 20:01 is worse than a submission
  that fails at 19:59 (`13-IOS-APP-ARCHITECTURE.md` §7).
- **A local database.** The game is server-authoritative; a cache of game state is a
  correctness hazard.
- **A tab bar.** One primary action per screen. Insights (`E25`) is reached from a profile or
  the menu, and does not get one either.
- **Un-submitting.** Replace, yes. Withdraw, no.
- **Configurable submission open/close hours.** Only `reveal_hour`, 18–21
  (`02-DOMAIN-RULES.md` §1).
- **Group deletion from the app.** Leaving is supported; deleting is a DB operation.
- **Spotify previews.** Previews come from Apple. Spotify is for identity and export
  (`06-MUSIC-INTEGRATION.md`).

### The one web surface

`https://blinddrop.app/j/<CODE>` — an invite landing page with an
`apple-app-site-association` file, falling back to showing the code for manual entry. It is a
static page. It has no login, no group data, and no content beyond the code and an App Store
link.

---

## 4. How to handle a good idea

You will have one. The pilot will produce several. The process:

1. Do not build it.
2. Add it to `tasks/ICEBOX.md` with one paragraph: what it is, what it would change, and what
   it would cost the blind window.
3. Continue with your task.

The instinct to add "just a small thing" is the specific failure mode this document exists to
prevent. Most small things here are not small: a submission count is one integer and it ends
the game.

---

## 5. Requests that are actually spec violations

If a task, an issue, or a well-meaning person asks for one of these, it is not a feature
request — it is a break, and it needs the owner:

- Any display of who has or hasn't submitted, in any phase
- Any submission count before the reveal
- Letting non-submitters guess
- A fourth daily notification
- Making the reveal or the score time client-decided
- Removing the two-hour guess window, or moving anything past 22:00
- Ranking readability
- Green/red for correct/incorrect
- Anything layered on top of album artwork
