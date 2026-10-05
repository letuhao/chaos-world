# 0007 Item system

- Status: Accepted
- Date: 2026-10-01

## Context

Items span crafting, equipment, consumables, quests, and cultivation. Breakthrough conditions (DEF-0018/0019) and many future systems need items. Items must be data-driven and extensible, and must not bloat `core`.

## Decision

- Module `items` owns the item system; it depends only on core/contracts.
- Categories: `material`, `consumable`, `equipment`, `technique`, `quest`, `key`, `currency`, `misc`. Subtypes: material (herb/ore/beast_core/essence), consumable (pill/elixir/talisman/food), equipment (weapon/armor/accessory/artifact), technique (manual/scroll/jade_slip).
- Grades: mortal/spirit/earth/heaven/immortal/divine, each mapped to a required realm tier for gating.
- `ItemDef` (Resource): id, category, subcategory, grade, stackable, max_stack, value, tags, description; authored as `.tres`.
- Runtime: `ItemStack` (def_id + quantity) for stackables; `ItemInstance` (def_id + instance_id + durability + refinement + affixes + bound_to) for equipment and unique items.
- `Inventory`: slot capacity, stacking/merge, add/remove/find/has; observable (`changed`) so stat caches invalidate.
- `Equipment`: slot map (weapon/armor/accessory_a/accessory_b/artifact); equipping applies source-tagged stat modifiers, like `TraitDef`.
- Core gains one generic extension point: `Actor.components` (`set_component`/`component`), so modules attach components (inventory, equipment) without core knowing item types.
- Tradable currency is `currency` items; abstract points (e.g. contribution) are resource pools.

## Consequences

- Adding an item = authoring an `ItemDef` `.tres`; no code.
- Breakthrough conditions read `Inventory` through the `items` facade.
- Equipment stats flow through the existing modifier system; equip/unequip invalidates stat caches automatically.
- `Actor.components` is the only core change; further item features stay in the module.
