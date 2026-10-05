# 0112 The milestone commit belongs to the breakthrough, not to a path

- **Status**: accepted
- **Supersedes**: none

## Context

`WorldAnchor.commit` was called by hand from the resolve path of each cultivation
path that uses the shared high-tier schedule — `body_cultivation/advancement.gd`
and `qi_cultivation/breakthrough_transaction.gd` — and from no other caller. Every
other consumer reached past it to a constant or a test helper.

Two rules in `AGENTS.md` make that shape a defect, not a style preference:

- "One module = one reason to change." A shared mechanic with one owner *per
  caller* has as many reasons to change as it has callers.
- ADR 0066 exists because this repo already grew a second copy of a three-tier
  concept, and the duplication outlived the feature.

The stranding is also silent. `Breakthrough.ascension_ok` demands
`actor.ascension != null`, and nothing reports an actor whose ascent was never
begun — the gate simply reads as permanently unsatisfiable, which is a state no
test assertion distinguishes from a legitimately unmet gate.

## Decision

`Breakthrough.try_advance` calls `WorldAnchor.commit(actor, index_of(next_realm.id))`
on the resolve of a successful advance, and the per-path hand-written calls are
removed.

`try_advance` is the one call every path already makes when a breakthrough
succeeds, so the milestone acquires exactly one owner and a new path becomes
incapable of forgetting it. `commit` is idempotent and a no-op off-schedule, so
the change is behaviour-preserving for every path that already worked.

The commit runs **after** `can_advance`, not before, and this ordering is load
bearing. `ascension_ok` opens with `if next_index <= COMMIT_MICRO: return true`,
so the advance *into* index 27 owes no ascent; that advance commits 27 and begins
the ritual; the gate that consumes it is `ascension_ok(actor, 28)` on the next
advance. The commit for index N serves the gate for index N+1. Committing first
would demand state the gate-checking call must itself create — the same
circularity `inside_world_ok`'s docstring records being fixed once already, for
R19's inside world.

## Consequences

- A fourth path cannot strand the milestone, because it never had to remember.
- **This fixes no currently-reachable bug, and that is recorded deliberately.**
  Body and qi each still commit by hand, and `mind_cultivation/advancement.gd`
  advances through the ungated `Breakthrough.try_advance`, so it never consults
  the shared schedule at all. That is why the duplication survived this long, and
  it is the reason a mutation deleting this commit leaves the full traversal
  suite green. The coverage gap is tracked as BL-0351, not papered over here.
- The ownership claim is therefore partly unproven by the tests that exist. The
  load-bearing evidence is `game/tests/core/test_commit_on_advance.gd`; deleting
  the commit turns it red. `test_full_traversal` does not, and must not be cited
  as if it did.