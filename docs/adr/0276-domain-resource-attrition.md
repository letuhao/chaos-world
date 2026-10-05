# 0276 Domain resource attrition

- Status: Proposed
- Date: 2026-10-06

## Context

The domain generates explorable maps with severe environments (heat, cold, toxic, void) but has **no consumable economy** — no food, water, torch, or carried inventory that depletes. This is the largest genre gap for a survival game. The domain already applies environment zones via `EnvironmentField.apply` on room entry (`DomainBoot._apply_zones`), and the items module already has a consumable category with `ItemUse` activation. What is missing is a system that makes carried resources **deplete over time** and **cost the player when they run out**.

## Decision

Introduce a **resource attrition** system: a consumable economy where food, water, and torch deplete per room entered, creating survival pressure inside a domain run.

### Resources

Three authored resources, each a `ResourcePool` on the actor:

| Resource | Pool id | Depletes per | Cost when empty |
|----------|---------|-------------|-----------------|
| Food | `food` | room entered | Health drain (starvation) |
| Water | `water` | room entered | Health drain (dehydration) |
| Torch | `torch` | room entered | Perception penalty (darkness) |

### Depletion model

- **Per room entered**, not per tick. The domain is a room-based traversal, not a real-time simulation. Each `DomainApi.visit_room` call triggers one depletion step.
- Depletion amount is authored per consumable item (e.g., rations restore 3 rooms worth of food).
- Resources are `ResourcePool` instances on the actor, sized from derived stats or authored constants.

### Cost when empty

- **Food/water at zero**: health drain per room (starvation/dehydration). Implemented as a `StatusEffect` (DOT) applied through `StatusApi`, never a direct health subtraction (ADR 0075).
- **Torch at zero**: perception penalty — a status that attenuates perception and may cause false exit reads (mirrors `SUBSTRATE_PERCEPTION_FAULT`).

### Integration

- **Items module**: Consumable item defs (`game/data/items/consumables/`) author the resource, depletion rate, and cost-when-empty as properties. `ItemsApi.use_item` already handles consumption; the attrition system reads these properties to apply effects.
- **Domain system**: `DomainBoot.visit_room` calls `ConsumablesApi.deplete(actor, room_id)` after `_apply_zones`. The domain module declares a dependency on `consumables` in `registry.json`.
- **Status module**: Costs-when-empty are applied as `StatusEffect` instances through `StatusApi.resolve`, obeying the same duration/stacking/cleanse rules as every other status.

### Module interface: `ConsumablesApi`

A new `consumables` module with facade `game/src/modules/consumables/api.gd`:

```
class_name ConsumablesApi

# Query: current resource levels as primitives
static func levels(actor: Actor) -> Dictionary
# => {"food": {"current": 5, "maximum": 10}, "water": {...}, "torch": {...}}

# Action: deplete resources on room entry. Returns what was depleted.
static func deplete(actor: Actor, room_id: StringName) -> Dictionary
# => {"food": -1, "water": -1, "torch": -1, "costs_applied": [...]}

# Action: restore resources (consuming an item from inventory)
static func restore(actor: Actor, resource_id: StringName, amount: int) -> Dictionary

# Query: what a resource costs when empty (for UI telegraphing)
static func empty_cost(resource_id: StringName) -> Dictionary
# => {"status_id": "starvation", "magnitude": 0.35, "tick_interval": 2.0}
```

The module depends on `core` (for `ResourcePool`, `Actor`) and `contracts` (for `StatusEffect`). It reaches `items` and `status` through their facades only.

### UI contract

Resource levels are published through `DomainApi.summary()["resources"]` as primitives:

```json
{
  "resources": {
    "food": {"current": 5, "maximum": 10, "empty_cost": "starvation"},
    "water": {"current": 3, "maximum": 10, "empty_cost": "dehydration"},
    "torch": {"current": 8, "maximum": 12, "empty_cost": "darkness"}
  }
}
```

## Consequences

- **Positive**: Creates survival pressure and a reason to carry consumables into a domain. Gives the consumable item category a gameplay purpose beyond one-shot restoration.
- **Negative**: Adds a module and a domain dependency. Must be balanced so attrition is pressure, not a death sentence.
- **Risk**: Health drain from starvation could conflict with environment zone damage. Mitigation: starvation/dehydration are CULTIVATION-scope DOTs, so they stack with but do not multiply environment hazards.
