# 0027 Instance persistence and migration: boundary-correct item state in actor payload

- Status: Accepted
- Date: 2026-10-02

## Context

`Actor` (core) serializes identity, stats, resources, paths, meridians, dantian, sea,
acupoints, and `module_data`, but attached `Inventory`/`Equipment` components are not in the
payload. The item module owns instance state (stacks, distinct non-stackable instances,
equipment slots). Core must not serialize concrete item-module types.

## Decision

- The item module provides `ItemsApi.serialize(actor) -> Dictionary` and
  `ItemsApi.deserialize(actor, data)`. These own all item-state serialization.
- `Actor` exposes a generic item-state hook: `set_item_state_serializer(serializer,
  deserializer)`. `to_dict()` includes `item_state` when a serializer is registered;
  `from_dict()` calls the deserializer. Core never references item types.
- `ItemsApi.attach` registers the hook, so any actor with items persists item state.
- The payload is versioned (`version: 1`) with stable ids and realized values. Loading
  restores instances and re-applies equipment definition modifiers; it never rerolls.
- Legacy definition/quantity stacks and affix-id-only instances migrate deterministically.

## Consequences

- Item state round-trips through the actor payload without core knowing item types.
- Loading is non-destructive: invalid or missing item state is diagnosed, not partially
- applied. Schema version gates future migrations.
