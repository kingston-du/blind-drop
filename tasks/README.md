# Task board conventions

## Files

- `BOARD.md` — every task, its status, and its dependencies. The index.
- `E##-<name>.md` — one epic, containing its tasks in full.
- `ICEBOX.md` — good ideas that are out of scope (`docs/16-OUT-OF-SCOPE.md` §4).

## Tasks and slices

`E00`–`E17` were written at one-commit granularity: a task is a deliverable. That was right for
building the thing from nothing, and none of it is being renumbered.

**From `E18` onward a task is a *slice*** — the largest coherent unit that can be understood,
implemented, built, tested, exercised in the app, reviewed and closed as **one behaviour**. The
format below is unchanged; only the size is. Fewer, larger, each one a thing a person could use.

Split a slice when it spans unrelated systems, when its parts verify separately, when it drags
in context that has nothing to do with the rest of it, when regressions stop being reasonable to
think about as one change, or when no single flow demonstrates that it is finished. Do **not**
split it by file, layer, or component — a slice that ships a screen ships its store, its DTO and
its strings with it.

Slices carry two extra fields:

| Field | Meaning |
|---|---|
| **Parallel** | `yes` / `no`, and against what. `yes` means disjoint files and independent verification — safe to run in another worktree alongside its siblings. |
| **Verify** | As before, plus **what gets exercised in the simulator**. For a user-facing slice, "the tests pass" is not the whole answer. |

The full working loop for a slice is `CLAUDE.md` §8, not the six steps below.

## Task format

```markdown
### E03-02 — tick_rounds(): reveal and void

**Status:** todo
**Deps:** E03-01
**Reads:** docs/02 §2, docs/03 §4
**Touches:** server/supabase/migrations/0004_round_lifecycle.sql
**Verify:** npm run test:db -- lifecycle
**Proves:** AC-3, AC-4

One paragraph of what and why.

- [ ] concrete deliverable
- [ ] concrete deliverable
```

| Field | Meaning |
|---|---|
| **Status** | `todo` · `wip` · `blocked` · `done` |
| **Deps** | Task IDs that must be `done` first |
| **Reads** | The **only** docs to load. Section numbers are given — read those sections. |
| **Touches** | Files this task creates or modifies. Keeps two agents off the same file. |
| **Verify** | The command that must pass. If there isn't one, the task is underspecified. |
| **Proves** | Acceptance criteria from `docs/15` this task contributes to |

## Working a task

1. Pick the top-most `todo` in `BOARD.md` whose deps are all `done`.
2. Set `wip` in **both** `BOARD.md` and the epic file. Commit that alone.
3. Read only what **Reads** names.
4. Implement. Tick the checklist as you go.
5. Run **Verify**. It must pass.
6. Set `done` in both places. Commit.

Branch: `t/E03-02-tick-reveal`.

## Rules

- **Never mark `done` with failing verification.** Mark `blocked` and write why underneath
  the task.
- Ambiguity → add a `> **Open question:**` block under the task, choose the interpretation
  most protective of the blind window, note it in the commit message, keep going.
- A task that needs a doc not in **Reads** means either the task or the doc is wrong. Fix the
  **Reads** field in the same commit.
- Do not reorder or renumber tasks. Add `E03-07` rather than inserting.
- Tasks within an epic are ordered; tasks across independent epics can run in parallel. The
  dependency graph in `BOARD.md` is the authority on what is parallel.

## Parallelisation

Three lanes can run concurrently once `E00` and `E01` land:

```
Lane A (backend game)   E02 → E03 → E04 → E05 → E06
Lane B (backend music)  E07                      ┐
Lane C (iOS)            E08 → E09 → E10 → E11 → E12 → E13
                                                 └─ needs E04/E05/E07 endpoints
```

Lane C can start against the fixture server (`E00-05`) before Lane A finishes. That is the
point of building the fixture server first.
