# 0907 Hook-gated travel edges

- Status: Accepted
- Date: 2026-10-07

## Context

Travel edges crossed unconditionally: any portal stepped on traveled. A
toll bridge, a sealed formation, or an attunement gate had no representation,
and the evaluator must live outside the map system (realm, items, flags are
gameplay facts the map engine must not name).

## Decision

- An edge names an optional `hook` String. No hook passes; a hook asks
  `WorldmapGates`, whose evaluator table `app/` installs (same seam shape as
  the domain world observer). An edge whose hook has NOTHING installed
  refuses `unknown_gate` — an unwired lock reads as a wall, never as open.
- Verdicts are bool or `{ok, reason}`; anything else refuses `bad_verdict`.
- The scene asks the gate BEFORE moving state: a refusal leaves the player
  on the gate cell, same node, with the reason in the step answer.
- `WorldmapApi.can_traverse(edge, context)` is the one verb; `context` is
  caller-filled (slice 3 wires actor facts into it).

## Consequences

- New gates need no core change: install an evaluator under a hook id.
- What this ADR does NOT do: condition-data evaluation (a dict DSL over
  stats/items/flags stays a possible later layer atop the same hooks), or
  toll payment (evaluators observe context; spending happens in gameplay).
