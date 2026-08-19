---
description: Resolve, plan, implement, verify, review and close the next unfinished slice — or a safe batch of them in parallel worktrees.
---

Work the next slice, end to end, following `CLAUDE.md` §8 — including its batch path: if step A
finds more than one eligible slice whose `Parallel` fields don't exclude each other, work them
together in isolated worktrees and merge sequentially, rather than picking just the top one.

$ARGUMENTS

If arguments name one or more slices (e.g. `E19-02` or `E22-01 E26-01`), work those instead of
resolving the next — named slices skip the eligibility scan but not the parallel-safety check
before batching them.
If they say `plan only`, stop after step C and wait.
If they say `no parallel` or `single`, resolve and work only the top-most eligible slice even if
a batch was available.

Do not skip the review or the verification, for any slice in a batch. Do not mark a slice `done`
while any of its verification is unresolved — `blocked`, with the reason written under the task,
is the correct outcome when something will not pass. Do not merge a batch's worktrees all at
once — §8 step I is sequential on purpose.
