# 0031 Body cultivation recovery is the third per-realm consumable

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0028 ("Recoverable failure")

## Context

ADR 0028 called a deviation recoverable but shipped no way to act on it. A deviation blocks one
open acupoint and damages one required channel, and nothing in the action layer could undo either:
`BodyTraining.strengthen` only works on the meridian it is handed and only when that channel still
has training headroom, so a blocked huyệt on an arbitrary channel had no public repair. Worse,
`BodyTraining.cultivate` skips blocked points, so a blocked huyệt's quality could never rise again.
Because the gate demands every unlocked huyệt meet the next realm's `quality_required`, a deviation
that blocked a point *not* listed in `required_meridians` made the next realm permanently
unreachable. `test_full_traversal.gd` hung on it at R4 rather than failing.

`cultivate` had a second defect: it wrote `quality = minf(quality_target, quality + gain)`, which
*lowers* quality for any huyệt already above the current realm's ceiling. A fresh huyệt starts at
0.5, so the first cultivation in `qi_refining` (ceiling 0.4) silently undid it.

## Decision

- **Every realm authors three consumable roles**, not two: `breakthrough_item`,
  `strengthening_item`, and `recovery_item`. All 30 body seeds carry a `recovery_item`, and each
  names an existing `ItemDef` craftable from that realm's materials.
- **`BodyTraining.recover(actor, meridian_id)` is the only action that clears a blockage.** It
  repairs the channel and unblocks its linked huyệt, consuming the realm's `recovery_item`. It is
  all-or-nothing: the item is consumed only after the meridian is found to actually need repair, so
  a no-op never burns a charge.
- **Cultivation only ever raises quality.** The realm's `quality_target` is a ceiling, not a reset;
  a huyệt trained above it keeps its value. This keeps the ADR 0028 invariant
  (`quality_required(R) == quality_target(R−1)`) intact in the reachable direction.
- **Recovery is exposed, not implied.** `BodyCultivationApi.recover_next` picks the wound to close
  (a blocked huyệt first, since it names its own channel), and the panel calls it. Without this the
  objective's "recovery" surface would be undiscoverable from the UI.

## Consequences

- `test_full_traversal.gd` walks R1→R30 using only public actions and now completes, recovering
  through `BodyTraining.recover` after each deviation rather than deadlocking.
- A deviation costs the player an extra consumable, so a failed attempt is a real setback that the
  realm's content can pay for.
- The seed's third role is now load-bearing: a realm missing `recovery_item` is unreachable after a
  deviation, which `test_every_realm_authors_all_three_consumables` asserts for all 30.
- Qi and Mind reach the same dead end through channel damage alone and are covered separately by
  their own seeded contracts (ADR 0024); only Body had the acupoint-quality coupling.
