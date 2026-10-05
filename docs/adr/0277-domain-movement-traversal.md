# 0277 Domain movement traversal

- Status: Proposed
- Date: 2026-10-06

## Context

The domain system generates explorable maps with rooms connected by corridors. Currently, moving between rooms is a UI dropdown — select a room, teleport there. There is no traversal under pressure: no walking, no movement feel, no sense of space. The genre gap is that the player never experiences the domain as a place you move through.

## Decision

**Traversal is room-to-room through exits.** The player moves from their current room to an adjacent room via a corridor connection. The map's exit graph (`RoomDef.exits`) defines legal moves. A move is valid when:

1. The actor is in a domain (has an active map)
2. The target room exists in the map
3. The target room is directly connected to the current room by a **mutual** exit (both rooms list each other in `exits` — `DomainPaths._connects_both_ways` already enforces this for corridors)

**The player's current room is tracked** in `DomainFight` as `_current_rooms` (keyed by actor instance id), lazily initialized from `map.entry_room` on first move. It is cleared when the actor leaves the domain.

**Movement triggers room entry.** A successful move calls `DomainBoot.visit_room`, which records discovery, applies environment zones, and publishes ward tags.

**Traps fire on presence.** After a move, the new room's fixtures are checked via `DomainBoot.presence_fixture`. The player's position within the room is the room's center tile (from `DomainPaths.layout`). This is the room-to-room simplification: the actor "appears" at the center, and traps whose footprint includes that tile fire.

**The UI contract is a single verb: `DomainFight.move(actor, target_room_id) -> Dictionary`.** The screen calls this through a new `move` callable on `DomainBridge`. Returns primitives only: `{ok, reason, room_id, newly_discovered, applied_zones, traps}`.

**Every refusal is named:**

| Reason | Meaning |
|---|---|
| `no_actor` | No hero bound |
| `no_map` | Not in a domain |
| `unknown_room` | Target room doesn't exist in this map |
| `same_room` | Already standing in that room |
| `no_exit` | Target room not connected to current room by a mutual exit |

## Consequences

- The domain becomes a place you move through, not a dropdown you pick from
- Traps fire on room entry, creating pressure during traversal
- `_current_rooms` is new state in `DomainFight` that must be cleared when the actor leaves a domain (handled by the `no_map` path in `move`)
- The `DomainBridge` gains a `move` callable (wired in a follow-up change)
- `DomainFight` owns the movement logic: validation + execution + trap check
- All loops are bounded: `_check_traps` iterates over authored fixtures; `_has_exit` is O(1); `_current_room` is O(1)
