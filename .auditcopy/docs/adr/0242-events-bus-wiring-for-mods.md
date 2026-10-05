# 0242 Events bus wiring for mods

- Status: Proposed
- Date: 2026-10-05
- Extends: ADR 0184 (mods are first-class content)

## Context

Mods need to react to game events — npc bonds, world creation, sect promotions — without the event-owning module naming the mod. The `events` manifest field declares these subscriptions, but the wiring from a manifest entry to a live signal connection had no defined mechanism.

Seven event bus types exist in `contracts/`: `NpcEvents`, `AuctionEvents`, `WorldEvents`, `DestinyEvents`, `NationEvents`, `SectEvents`, `HoldingsEvents`. Each is a `RefCounted` with typed signals. Two (`NpcEvents`, `AuctionEvents`) expose a `shared()` accessor returning a process-wide singleton; the rest are instantiated fresh.

## Decision

1. **Subscription shape:** each `events` manifest entry is a Dictionary `{event_bus: String, event_name: String, callable: Callable}`. The bus is named by class name, not by a node path or autoload.
2. **Factory resolution:** `_resolve_events_bus(bus_name)` maps the class name to a factory lambda. Buses with `shared()` return the singleton; others return a fresh instance. Unknown names return `null`.
3. **Guarded connection:** `_wire_subscriptions` connects each callable only when `bus.is_connected(event_name, callable)` is false, so a repeated boot never double-connects.
4. **Skip silently:** an unknown bus name, empty event name, or invalid callable is skipped without crashing — the mod's other subscriptions still load.

## Consequences

- A mod can subscribe to any of the 7 known bus types by class name.
- Unknown bus names are skipped without crashing the boot.
- The `is_connected` guard prevents double-connect on repeated boots (AGENTS.md loop-safety rule).
- The factory pattern keeps the bus list in one place; adding an eighth bus means one new entry in `_resolve_events_bus`.
