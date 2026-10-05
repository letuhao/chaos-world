# 0248 A claim floor counts the ground a holder already holds, never a standing

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0083 (three tiers, one vocabulary), ADR 0084 (recognition and access,
  never power), ADR 0097 (a resource node is an authored holding with one typed owner ref)
- Resolves: DEF-0305

## Context

`HoldingsApi._meets_floor` compared a node's authored `claim_floor` against
`owner.get("standing", 0)` — a field the OWNER REF does not carry. `OwnerRef` is
`{kind, id}` (`contracts/owner_ref.gd`), and the two production producers both build
exactly that: `ForageScreen._owner()` and `ForageAction.owner_ref()`. So the read was
always `0`, and every node authored with `claim_floor > 0` refused `claim_below_floor`
forever. **7 of the 16 authored nodes** carry a non-zero floor, so 44% of the resource
corpus was permanently unclaimable.

It survived four audit cycles because `tests/modules/holdings/test_holdings_claim.gd`'s
`_owner()` helper *did* inject a `standing` key while every fixture node it claimed was
floor-0 — the suite could afford a ref shape no producer ships, because the branch under
test never ran. The test fixture and the production ref had quietly diverged, and the
divergence was invisible from both ends.

ADR 0097 wrote the node's `claim_floor` as *"the standing a claim requires"* with no
measurement behind it. The question is what a floor may be read against.

### What `standing` is in this repo, measured

Every `standing` in `game/src` is scoped to ONE institution's ledger: `ClanState.standing`,
`SectState.standing(ledger)`, `NationState`'s `ledger["standing"]`, and `social`'s
`bond.standing`. There is no actor-global standing anywhere. An actor's standing exists
only *relative to* an institution, and each institution keeps its own capped number
(ADR 0084's `STANDING_PERCENT_CAP`). So "the holder's standing" is not one number — it is
a set of numbers, one per institution the holder belongs to, and a resource node would
have to name which one it means.

## Decision

**`claim_floor` is the number of resource nodes the holder must ALREADY hold. It is a
concentration gate, not a recognition gate — and `OwnerRef` does not change shape.**

- `_meets_floor` answers `_held_by(state, owner) >= def.claim_floor`, counting the
  ledger's own rows for that holder. The gate is now answered by the module that owns the
  only data which could answer it: no new seam, no new edge, no `contracts/` change, and
  no invented number.
- **The floor is kind-agnostic.** The old rule refused any non-`actor` holder on a floored
  node outright, so an institution could never take one. A count of holdings is a ledger
  fact for all four `KINDS` equally.
- **Seven floors are re-authored** as a ladder over the 16-node corpus (2, 3, 5, 6, 7, 9,
  11 — ascending with realm depth), because the old magnitudes (20…80) meant a count and
  would have been unmeetable by anyone: the corpus holds sixteen nodes, so a floor of 20
  is the same UNBUILT bug wearing different numbers.
- `CLAIM_BELOW_FLOOR` keeps its name. The rule did not change kind, only what it counts.
- `ForageApi.view` publishes `meets_floor`, so a row can say whether a claim is open
  before the button is pressed rather than only after.

### Why this keeps the gate NON-TRIVIAL

**The gate is non-trivial because the corpus itself cannot satisfy it at the start, and
reaches every node only by first consolidating shallow ground** — nine floor-0 nodes seed
the ladder, and the seven floored ones are then reachable in ascending-floor order to a
holder holding all sixteen. That order is asserted over the real `.tres` files, not over
fixtures: a cold hero is refused `claim_below_floor` on every floored node, and the same
hero is accepted on every one of them after the consolidation a reviewer can replay.

## Rejected

- **(a) `OwnerRef` gains a `standing` field the resolver fills.** Killed by measurement:
  no actor-global standing exists to put in it — every `standing` in the tree is one
  institution's capped ledger, so the field would have to be a per-institution map, which
  is a second ref. Worse, the resolver (`OwnerResolver.resolve`) answers `{ok, reason}`
  with no numbers by contract; filling a political number through it would make the
  holdings gate depend on which institutions the holder happens to join, from a module
  with no edge to any of them (ADR 0084's coupling by another route). It would also have
  had every producer of a ref decide whether to populate a political number it does not
  own.
- **(b) Drop `claim_floor` entirely.** Cheaper, and defensible on ADR 0084's grounds — but
  it deletes a designed rule and seven authored values rather than repairing a gate, and
  `ResourceNodeDef`'s own note ("a claim without one would let anyone take a vein") states
  the rule was deliberate. The coupling ADR 0084 warns about is reading a *political
  number* as a resource gate; a count of ground already held is not one.

## Consequences

- **`OwnerRef` is untouched.** `to_dict`, `from_dict`, `vacant`, `storage_key`, `KINDS`
  and the three-state vocabulary are exactly as ADR 0097 wrote them; no producer has to
  decide anything.
- **The fixture that hid the bug is gone.** `test_holdings_claim.gd`'s `_owner()` builds a
  bare `{kind, id}` ref — the production shape — so a suite can no longer pass on a field
  no player path supplies.
- **`HoldingsApi` stays at its twelve public methods.** `_meets_floor` and the new
  `_held_by` are private; the cap is untouched.
- **A new suite sweeps the real corpus**: all sixteen authored `.tres` nodes, claimed by a
  cold hero in a legal order, plus the both-directions gate on real floored content. The
  class of bug — a gate that no holder can satisfy — can no longer return unnoticed,
  because a floor above the corpus size fails that sweep.
