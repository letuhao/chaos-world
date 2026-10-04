# 0156 a probe in the git index is one commit from history, and the worktree cannot see it

- Status: Accepted
- Date: 2026-10-04

## Context

`test_no_stranded_mutation.gd` reads the **working tree**, so it is blind to a marker
that exists only in the git index, and equally blind to one already committed (INC-0007).

On 2026-10-04 that gap was one commit wide. An agent applied `MUTATION-LOOTWORLDFULL`
to `game/src/modules/loot/loot_state.gd` to prove a refusal-label fix load-bearing, and
while that marker was still live a second agent ran `git add` on the same file. The index
then held a state that existed neither in `HEAD` nor in the worktree. It was caught by
reading `git diff --cached` after the file showed `MM` where its author's own edit
predicted `M`.

The ordering trap is the durable part. A fix-forward revert repairs the **worktree only**
and leaves the **index** wrong: `git diff` shows the fix in place, the tree reads clean,
and the probe is still one `git commit` from history. Reading the worktree harder cannot
close that window.

## Decision

`mutation_history.staged()` reads the **index** with `git grep --cached`, which reads staged
blobs rather than disk, and classifies each hit with the **same `_live_marker`** the ref
half uses. A second marker grammar would be a second opinion, and the two layers would then
disagree about what a probe is — the one failure this module exists to prevent.

The findings fold into `carried()` rather than becoming a new gate, because `tools check`
reaches this module only through `carried()`. An unwired guard is a function, not a guard.
Index findings sort **first**: they are the ones about to become history, and a truncated
report must not drop them.

Proved in both directions by `selftest_cases.py` — a staged probe is found while the
working tree is clean *and* the fixture really is in the `MM` state *and* no tip carries
it; and restaging the repair clears both `staged()` and `carried()`. A guard that can never
pass is a guard people learn to ignore.

## Consequences

- A staged probe is red **before** it can be committed, not after.
- Reading the worktree is no longer sufficient after any mutation window: run
  `git diff --cached -- <path>` as well as `git diff -- <path>`.
- The GDScript tree guard stays worktree-only by design; this closes the index layer, not
  the whole class. A probe that writes no marker still leaves nothing to find.
- Index findings cost one extra `git grep` per `check`, a hoisted guard already documented
  as ~150 ms.
