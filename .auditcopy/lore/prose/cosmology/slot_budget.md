# Slot Budget

## The problem it solves

The authored tiers carry `law_slots` 3 / 6 / 10 / 15. There are six authored laws. A
mortal-tier world holding "three of six laws" and a transcendent-tier world holding
"fifteen" are the same sentence, and it cannot mean fifteen laws. Either the number is
wrong or "law" means something narrower than `WorldLawDef`.

## What a slot actually is

A slot is **one law group written at one value into one layer**. The authored code already
has the container for this: `WorldLayerState` carries its own `laws: Array[StringName]`
and its own `size_ratio`. Layers divide a world into regions with their own law sets.

So the budget is not "how many laws does this world have". It is "how many imprints can
this world hold at once, spread across its layers". A group may be imprinted at more than
one value in different layers of the same world; the budget counts imprints, and that is
the only reason 15 can exceed 6.

Consequences that follow arithmetically:

| tier | slots | groups | minimum layers |
|---|---|---|---|
| mortal_world | 3 | 6 | 1 |
| spirit_world | 6 | 6 | 1 |
| immortal_world | 10 | 6 | 2 |
| transcendent_world | 15 | 6 | 3 |

At the immortal tier the surplus is forced. Ten imprints over six groups leaves four
duplicates, and a duplicate only has somewhere to sit if a second layer exists. That is
why a layered immortal world is not a stylistic choice — it is the remainder.

## Every law is a dial, not a switch

Each authored `WorldLawDef` carries `value_min` and `value_max`:

- physical 0.1 – 10.0
- spatial 0.1 – 10.0
- qi 0.1 – 100.0
- temporal 0.1 – 100.0
- elemental 0.0 – 1.0
- life 0.0 – 1.0

So presence is a magnitude. A world that spends a slot on `qi_law` has not "got qi"; it
has got one reading of a dial that runs from 0.1 to 100. That reading is what a person
grows a body to tolerate, and it is why a mortal world's qi is present and still useless.

## Not yet enforced in the engine

`WorldState.add_law` (`game/src/core/world_creation.gd`) appends with no cap, and
`WorldApi.add_law` (`game/src/modules/world/api.gd`) never reads `law_slots`. `WorldApi`
also carries its own tier vocabulary — `micro` / `small` / `great` — which has no
`WorldTierDef` data at all, and `evolve_world` computes `new_law_slots = (idx + 2) * 3`
for 3 / 6 / 9, which matches the authored mortal and spirit budgets and diverges from the
authored immortal (10) and transcendent (15).

The budget is therefore authored data the engine does not yet enforce. This record
describes the setting the data already implies, not behaviour the engine has.