# 0033 Every cultivation path's gates are reachable through its own actions

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0028 ("Reachable gates"), ADR 0024

## Context

Writing the first qi full-traversal test exposed three gates that no sequence of
public qi actions could ever satisfy. Each had a passing test asserting the
*broken* behaviour, so the suite was green and the path was not playable.

1. **The dantian had no producer for its own quality floor.** `QiTraining.cultivate`
   capped quality at the *current* realm's `dantian_quality_required`, but every
   realm's floor rises above the one before it — 28 of 29 transitions demanded
   more quality than the realm below it could produce. Capping at the *next*
   realm's floor is the fix, mirroring the separate `quality_target` field ADR
   0028 gave Body.
2. **A full dantian stopped training, not just storing.** `cultivate` returned
   false when the reservoir was full, so progress could never catch up — yet the
   entry gate demands a full reservoir *and* a met progress floor. `fill` clamps,
   so a full dantian now simply keeps no surplus, exactly like
   `BodyTraining.cultivate`. `test_cultivate_stops_when_the_dantian_is_full`
   pinned the bug and was rewritten to assert the correct contract.
3. **The comprehension floor had no action at all.** Qi gates on
   `Stat.COMPREHENSION` up to 66, but `QiTraining` had no `meditate` and the realm
   rewards grant `spirit`. `QiTraining.meditate` now exists, mirroring
   `BodyTraining.meditate` (ADR 0024); comprehension cannot be bought with a pill.

Separately, `preview()` in both qi breakthrough files carried its own *inline
copy* of the tier gates, which drifted from the `Breakthrough` predicates the
transaction enforces. Both now delegate, so the preview cannot disagree with the
action it previews.

## Decision

- **Cultivation refines toward the next realm's floor, never the current one.**
  `QiTraining._quality_ceiling` resolves it, and `test_every_realm_quality_gate_
  is_reachable_by_circulating_qi` walks all 29 transitions to prove it.
- **A full reservoir clamps storage, not training.**
- **Meditation is the only route to comprehension on every path.**
- **Previews delegate to the shared gate predicates.** Duplicated inline gate
  logic is what let the transaction validate nothing while the preview looked
  correct.

## Consequences

- `qi_cultivation/test_full_traversal.gd` walks R1→R30 through cultivate, train a
  channel, meditate, recover, and breakthrough only, and asserts the high tier
  commits its own anchors rather than forging them.
- A deviation halves dantian quality and `recover` deliberately does not restore
  it, so preparation circulates again after every recovery — which is what the
  traversal helper's three-condition loop encodes.
- The same duplicated-preview pattern still exists between `QiBreakthrough
  Transaction` and `QiAdvancement`; they now agree, but consolidating the two is
  still open.
