# 0157 A drop pays the rung of its item's own realm, so a foreign-realm reagent belongs in a realm-declaring pool

- Status: Accepted
- Date: 2026-10-04

## Context

A `LootEntry` realizes at a realm the RESOLVER computes, never at the realm its item is
authored for. `LootResolver._plan` takes `context.realm` whenever it is set and only falls
back to `LootTableDef.realm`; the context is the band, and `LootResolver._child_context`
lets a nested table override the band only where that table declares a `realm` of its own.
So the rung a drop pays is *the band realm, overridden by each table's own realm from the
outside in*.

`item_magnitude_scale.json` is ONE per-realm table shared by all three ladders (ADR 0050:
item magnitudes are not actor stats and deliberately differ). The rung a reagent owes is
therefore the `realm` on its own `ItemDef` and nothing else.

Three places already said so, and nothing enforced any of them:

- `tools/acquisition/design.py`: "the band is a statement about difficulty, not about which
  realm a drop belongs to, so moving the realm between bands would mis-scale the loot",
  and a boss's loot is "grouped by the realm its items roll at, so one iron relic in a
  primordial trial still rolls at an iron magnitude".
- `tools/acquisition/chain.py:band_realm`: "a wrong-high fallback hands out loot scaled
  above its authored magnitude".
- `game/src/modules/loot/loot_rewards.gd`: "the drop rolls for the realm and rarity it fell
  from, not the ones its definition was authored at".

A **direct** entry has no table of its own to override the band, so it pays the band's rung.
BL-0645 measured the consequence on the Mind ladder: all 13 promoted Mind herbs paid a
body or qi rung, `mind_core_formation_mind_herb` paying `dao_ancestor` (3.8x) where it owes
`core_formation` (1.2x). Measured corpus-wide with `tools/cultivation/loot_magnitude.py`,
the same shape held on **53** guaranteed reagents — BL-0645's 13 plus 40 qi-ladder herbs
and cores its own audit never reached — and on 6,245 domain relics.

`loot_rewards.gd`'s line is the reason this is a PLACEMENT defect and not a scale defect.
The resolver's rule is right and `item_magnitude_scale.json` is right; retuning the table
would price 30 realms off a placement bug and leave the bug in place.

## Decision

- **The magnitude table is not touched.** A rung is authored per realm id; a drop that pays
  the wrong rung is a placement error, never a reason to move a number.
- **A reagent whose own realm is not the band's belongs in a nested pool that declares its
  realm**, which is the shape `tools/acquisition/seed.py` `_boss_entries` already emits for
  every foreign-realm catalyst and 1,039 shipped `_pool_*` tables already carry.
- **Only a guaranteed reagent may be moved.** A guaranteed entry inside a realm-correct pool
  yields exactly the units the direct entry did, so acquisition is unchanged. A rolled one
  would become one candidate among many on its parent, which is DEF-0187's permanent-miss
  class again; rolled reagents are measured and reported, never moved.
- **The nesting entry above a moved pool carries the moved entries' own `guaranteed` flag.**
  A guaranteed entry inside a pool is unconditional only if the step above it is too
  (`tools/acquisition/loot.py`). A realm whose moved entries disagree is refused rather than
  silently promoted or demoted.
- **The gate covers the guaranteed-reagent class** (`cultivation loot-magnitude check`), which
  is the part that can move. The 6,245-relic residual is BL-0704 and is measured by the same
  command under `--scope all`.

## Consequences

- The Mind ladder's 13 herbs and the qi ladder's 40 pay their own rung; the ladder ids are
  shared, so "Mind's own band" means the rung the Mind seed's realm id names, not a
  separate table.
- `cultivation loot-magnitude` reports and guards the class, so the next cross-ladder payment
  is caught rather than fixed once. It is **not yet wired into `tools check`**: that file was
  another agent's at the time of this change.
- The residual is a separate change of a different shape — one pool per owed realm per boss
  table, thousands of new `.tres` — and needs its own decision on whether a rolled relic may
  move at all.
- Text surgery, never a re-emit: `emit.Entry` writes no `chance` and no `quantity_max`, so
  regenerating a 24-entry boss table to move one entry would silently normalize the other
  twenty-three. `check` also asserts the `entries` array is loadable, because a fixer that
  can splice a ref has to be able to see the ref it broke.
