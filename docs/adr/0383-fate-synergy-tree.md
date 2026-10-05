# 0383 Fate Synergy Tree

- Status: Proposed
- Date: 2026-10-06
- Amends: ADR 0065 (earn-only invariant; synergy is a prerequisite, not a grant)
- Consistent with: ADR 0113 (data-driven content), ADR 0134 (facade surface)

## Context

Fates are earned consequences of deeds (ADR 0065). Today each fate is independent:
earning one has no effect on any other. But cultivation is a web of consequences —
an oath broken after it was sworn under witness is a different story than one broken
in secret. The content tree needs a way to express "this fate becomes reachable once
that fate is held" without auto-granting anything or violating the earn-only invariant.

## Decision

- **A synergy is a prerequisite edge, not a grant.** `FateDef.unlocks` lists fates that
  become *available* when this fate is held; `FateDef.requires` lists fates that must
  be held before this one can be earned. The two fields are two views of the same edge
  and must be consistent: `A.unlocks` contains `B` iff `B.requires` contains `A`.
- **Earning a fate never auto-grants another.** The synergy tree gates *when* a fate
  can be earned, not *whether* it is granted. A player still earns each fate through
  its own deed path; the tree only adds a prerequisite constraint. This preserves the
  earn-only invariant (ADR 0065): nothing is chosen, nothing is revoked.
- **The graph must be acyclic.** A unlocks B and B unlocks A means neither can ever be
  earned — a deadlock the player cannot resolve. `FateSynergyTree.is_acyclic()` is
  validated at load and asserted by test. A cycle is a content bug, refused loudly.
- **Dangling references are refused.** An unlock or require naming a fate the catalog
  does not ship is a content bug, not a silent no-op. Validation names the missing id.
- **The tree is data, never code.** Synergy edges are authored in `.tres` files as
  `Array[StringName]` on `FateDef`. No GDScript is authored per synergy.
- **The UI reads the tree through the facade.** `DestinyApi.summary()` publishes each
  fate's `unlocks` and `requires` lists. The tree panel renders nodes and edges from
  that data; it holds no graph logic of its own.

## Consequences

- `FateDef` grows two fields: `unlocks: Array[StringName]` and `requires:
  Array[StringName]`. Both default to empty — a fate with no synergies is legal.
- `FateSynergyTree` (new file in `modules/destiny/`) validates the graph: acyclic,
  all references resolve, the two views are consistent. Called by `FateCatalog` at
  load and by tests.
- `DestinyGate.earnable()` gains a synergy check: a fate with unmet `requires` is not
  earnable. This is a prerequisite check, not a grant — the fate must still be earned
  through its own path.
- The fate tree UI (Gap 1) renders the synergy graph: nodes are fates, edges are
  unlock/requires relationships, color-coded by earned/unearned. Data-driven from
  `summary()`.
- Existing fates ship with empty `unlocks`/`requires`, so no current content changes
  behavior. New synergies are authored in `.tres` files.
