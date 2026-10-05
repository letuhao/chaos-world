# 0121 The milestone commit reached core only; the paths keep their hand-written call

- **Status**: accepted
- **Supersedes**: ADR 0112 (its Decision's second sentence only; the rest stands)

## Context

ADR 0112 decided two things: that `Breakthrough.try_advance` commits, and "the per-path
hand-written calls are removed" (0112:27-29). The first shipped at
`core/breakthrough.gd:56`. **The second did not ship at all**, and ADR 0112 contradicted
itself — its own Consequences say "Body and qi each still commit by hand" (0112:48-50).

Three call sites survive:

| Site | Call | Shared or own |
|---|---|---|
| `core/breakthrough.gd:56` | `WorldAnchor.commit` | shared schedule |
| `body_cultivation/advancement.gd:269` | `WorldAnchor.commit` | **shared — duplicate** |
| `qi_cultivation/breakthrough_transaction.gd:151` | `WorldAnchor.commit` | **shared — duplicate** |
| `mind_cultivation/advancement.gd:413` | `MindAnchor.commit` | mind's own anchor clause |

Evidence: `Select-String -Path game/src/core/breakthrough.gd,game/src/modules/*/… -Pattern
'WorldAnchor\.commit|MindAnchor\.commit'`.

Body and qi are now **provably redundant**, not merely duplicated. Both call
`Breakthrough.try_advance_gated` on the way in — `advancement.gd:254`,
`breakthrough_transaction.gd:132` — which reaches `try_advance`'s commit, and then hand
commit the same `target.index` twenty lines later. `commit` is idempotent, so this is
dead work, not a double award.

Mind is **not** a duplicate: `MindAnchor` is the anchor clause ADR 0118 kept as mind's
own additional `and`, paid by that attempt's own outcome. Removing it would be a
regression.

## Decision

- **The milestone commit has two owners today: `core` plus the two paths that still
  remember.** ADR 0112's claim of one owner is superseded.
- **The two body/qi calls stay until an owner of `modules/**` removes them.** They are
  redundant, and deleting them is right, but the truthfulness cost of an ADR claiming a
  deletion that has not happened is higher than the cost of a redundant idempotent call.
  This slice does not touch `modules/`.
- **Mind's call is not part of this question.** It is a different artifact (ADR 0118).

Rejected: *delete the two calls now.* They are in files this slice does not own, on a
tree shared with live agents. Rejected: *rewrite 0112 to say "still there"* — 0112 is
accepted, and the claim it needed was never true.

## Consequences

- `tests/core/test_commit_on_advance.gd` is the load-bearing evidence for the **core**
  commit only, exactly as ADR 0112:54-57 already warned. `test_full_traversal` must not
  be cited for it.
- A future owner of `modules/**` should delete `advancement.gd:269` and
  `breakthrough_transaction.gd:151` and leave mind alone. Nothing forces them: both
  paths reach core's commit, so removing them is behaviour-preserving, and
  `test_commit_on_advance.gd` is the suite that would catch getting it wrong.