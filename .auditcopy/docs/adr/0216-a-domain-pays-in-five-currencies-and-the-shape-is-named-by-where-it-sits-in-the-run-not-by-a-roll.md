# 0216 A domain pays in five currencies and the shape is named by where it sits in the run, not by a roll

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0839 (the shape of a domain's payment)
- Related: ADR 0166 (a drop pays its item's own rung), ADR 0053 (a technique is a codex entry)

## Context

A domain pays through two unrelated machinery. A **boss** pays through `LootApi.strike`
→ `LootState._defeat` → `LootResolver.resolve` (weighted/chance/guaranteed tables). A
**fixture** pays through `DomainFixtures._grant` → `DomainBoot.grant_item` → one
`reward_item_id` × `reward_count`, with **no table, no roll and no realization**.

Those are not two shapes of one thing; they are two things. A boss drop is a *sample*
from a distribution. A fixture reward is a *specific object at a specific place*. Nothing
in the repo says which is which, so an author reaches for whichever is convenient and the
player gets whatever came out.

`DomainFixtures._grant` pays `count` of one **definition** — it never realizes
(`domain_fixtures.gd:565-579`). Every `reward_item_id` in the corpus is
equipment- or key-shaped, so a hoard hands over the archetype and the player sees a
non-instanced row. `LootRewards._drop` by contrast realizes at defeat time and stores
the instance (`loot_rewards.gd:71-102`) so a save/load between defeat and pickup
restores the exact rolls. The fixture path has no such moment.

## Decision

**A domain pays in exactly five currencies, and which one a thing pays is decided by
WHERE IT SITS in the run — never by a roll.**

| Sits at | Pays | Carried as |
|---|---|---|
| a defeated boss | **materials** | a realized `ItemInstance` |
| a defeated boss's tier, once | **one manual or pill** | a realized instance |
| a fixture a player must earn past | **one equipment piece** | a realized instance |
| a fixture that is a formation or a hazard | **lore / insight** | a ledger row |
| the run's completion | **the run's own claim** | the loot state |

1. **Boss kills pay materials.** This is the load-bearing choice and it is what makes a
   domain one-shot-per-band coherent (ADR 0219): a material is a fungible input to a
   recipe, so a repeatable supply is not a problem and a non-repeatable one is not a
   famine. Materials are the currency a *system* consumes.

2. **A fixture pays the specific object the room is about**, and nothing else. A hoard
   contains a relic; it does not contain "3 of whatever the table rolls". This is the
   genre convention stated plainly: a **placed** reward is legible from the moment the
   player sees the container, which is the entire reason placed rewards are tension
   devices rather than slot machines. The player knows what is behind the door *before*
   paying the price of the door, and that knowledge is what makes the gate a decision.

3. **A fixture pays ONE unit, never a count.** `reward_count` is removed from the
   vocabulary. A hoard holds a relic, not a stack of relics; if the content wants volume
   it authors several fixtures or a material drop.

4. **A fixture reward MUST realize through the one realization path the game already
   owns** (`ItemsApi.generate`, seeded from fixture id), never through a bare
   `inventory.add(def, count)`. This is the direct answer to BL-0839: a fixture whose
   reward does not resolve is not a small defect, it is a fixture that answers
   `inventory_full` forever and reads as "still sealed".

5. **Scale is the TIER's, never the fixture's.** A fixture's item is authored at its own
   realm and pays its own magnitude (ADR 0166). A deeper band gets a **deeper authored
   fixture**, in a deeper room, not a bigger number on the same fixture.

6. **A reward is EARNED, not dropped, when three things are all true** and this is the
   test every authored reward must pass: (a) the player could see it was there before
   they could have it; (b) something they had to spend or risk stands between them and
   it; (c) the thing they spend or risk is still spent afterwards. A boss material drop
   fails (a) — it was never visible — which is why it is the *load*, not the reward, and
   why a domain whose only output is boss materials has given the player a grind rather
   than a prize.

## Consequences

- **BL-0839 closes with a rule, not five content files.** The defect is a missing
  content audit, but the *rule* that catches the next one is: a fixture `reward_item_id`
  that `Crafting.resolve` cannot resolve is a hard `data audit` failure, exactly as an
  `EnvironmentZoneDef` with empty `mitigation_tags` already is (ADR 0075).
- `reward_count` removal is a `RoomDef`/data change and belongs with the owner; this ADR
  fixes the direction, not the migration.
- A fixture must reach `items` for realization. `domain` declares no `items` dependency,
  so realization rides the **existing injected granter seam**
  (`DomainFixtures.set_minter`, `domain_fixtures.gd:152`) — the seam is already there and
  already legal. No new edge, no new module.
- The five currencies are **not** five new item categories. Materials/equipment/pills are
  `ItemCategory` values that already exist (ADR 0007); a manual is a `technique`-category
  item routed to the codex (ADR 0053); lore/insight is the only genuinely new shape and it
  is deliberately the **thinnest** — one ledger row, no new persistence.

## Rejected

- **One loot table for fixtures too.** Rejected: a placed reward's value is that the
  player knows what it is. Rolling it destroys the only property the container had and
  turns a hoard into a vending machine.
- **A `treasure_chance` field.** Rejected: it is a second probability next to the gate,
  and a gate you can roll through is not a gate.
- **Scaling fixtures by band multiplier.** Rejected on ADR 0166's own reasoning — the
  item is the magnitude authority, and a multiplier is the band paying magnitude again.