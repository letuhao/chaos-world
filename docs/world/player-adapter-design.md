# Player Adapter Design

## Overview

`PlayerAdapter` is a `CharacterBody2D` that wraps an `Actor` and bridges the engine-agnostic game logic to the Godot 2D scene tree. It owns movement, camera, interaction, and combat/non-combat state — all callable headlessly for LLM-driven play.

## CharacterBody2D Structure

```
PlayerAdapter (CharacterBody2D)
  ├── Camera2D          — follows player, clamped to map bounds
  ├── Sprite2D          — visual representation (optional)
  ├── CollisionShape2D  — physics body
  └── InteractionArea (Area2D)  — detects nearby interactables
```

- Extends `CharacterBody2D`, uses `move_and_slide()` for physics-based movement
- Nodes resolved in `_bind_nodes()` via `get_node_or_null()` — no `@onready`
- Works headlessly: all nodes optional, adapter functions without them

## Actor Wrapping

- Owns an `Actor` reference (RefCounted, engine-agnostic)
- Exposed via `actor() -> Actor`
- Actor created externally (by `ActorFactory`) and injected via `_init(actor)`
- Move speed derived from `actor.stats.derived(Stat.MOVE_SPEED)` — falls back to `DEFAULT_MOVE_SPEED` (200.0) when actor is null

## Camera2D Setup

- `Camera2D` child node, enabled in `_setup_camera()`
- Clamped to map bounds via `limit_left/right/top/bottom`
- Map bounds set via `set_map_bounds(bounds: Rect2)` — defaults to 1024x1024
- Camera follows player automatically (built-in Camera2D behavior)

## Movement System

- **WASD / Arrow keys** — 8-direction movement via `Input.is_action_pressed()`
- **Normalized diagonal** — `direction.normalized()` prevents faster diagonal movement
- **Speed** — derived from actor's `MOVE_SPEED` stat, fallback 200.0 px/s
- **Physics** — `move_and_slide()` in `_physics_process(delta)`
- **Target movement** — `move_to(position)` sets a target; adapter moves toward it until within 4px

### Input Actions

| Action | Keys |
|---|---|
| `move_up` | W, Up |
| `move_down` | S, Down |
| `move_left` | A, Left |
| `move_right` | D, Right |
| `interact` | E |
| `attack` | Space |

Actions registered programmatically via `_ensure_input_actions()` — idempotent, safe to call repeatedly.

## Interaction System

- **E key** — `interact()` finds nearest interactable within `INTERACTION_RANGE` (64px)
- **InteractionArea** — Area2D with collision shape detects nearby bodies via `body_entered`/`body_exited` signals
- **Manual tracking** — `add_interactable(node)` / `remove_interactable(node)` for programmatic control
- **Signal** — `interacted(target_name: String)` emitted on successful interaction
- **LLM-drivable** — `interact()` callable headlessly, finds nearest valid target

## Combat/Non-Combat States

```
EXPLORATION  ←──→  COMBAT
  │                    │
  │ Full speed         │ Half speed (COMBAT_SPEED_MULTIPLIER = 0.5)
  │ WASD + interact    │ WASD + attack
  │ move_to()          │ attack()
```

- `State` enum: `EXPLORATION`, `COMBAT`
- `set_state(new_state)` — transitions emit `state_changed`, `combat_started`, `combat_ended`
- Combat state: movement slowed, attack input active
- Exploration state: full speed, interaction input active

## LLM-Drivable API

All methods callable headlessly — no display required:

| Method | Purpose |
|---|---|
| `move_to(position: Vector2)` | Move toward target position |
| `interact()` | Interact with nearest interactable |
| `attack(target: Node2D = null)` | Attack target (combat state only) |
| `set_state(new_state: int)` | Switch exploration/combat |
| `add_interactable(node: Node2D)` | Register interactable |
| `remove_interactable(node: Node2D)` | Unregister interactable |
| `actor() -> Actor` | Access wrapped actor |
| `state() -> int` | Current state |
| `summary() -> Dictionary` | Testable state snapshot |

## Save/Load

- `to_dict() -> Dictionary` — serializes position, state, map bounds, and full actor state
- `from_dict(data) -> PlayerAdapter` — static factory, restores adapter with actor
- Actor state persisted via `Actor.to_dict()` / `Actor.from_dict()` (schema version 4)
- Save format versioned (`SAVE_VERSION = 1`)

### Save Payload

```json
{
  "version": 1,
  "position": [100.0, 200.0],
  "state": 0,
  "map_bounds": [0, 0, 1024, 1024],
  "actor": { ... }
}
```

## Integration Points

| System | Integration |
|---|---|
| `Actor` | Wrapped reference, stats drive movement speed |
| `WorldApi` | World module facade for resources, locations, inhabitants |
| `CombatApi` | Combat module facade for attack resolution |
| `WorldEntry` | Base scene providing spawn points, NPCs, resources |
| `ScreenStack` | UI program reads adapter state via `summary()` |
| `ActorFactory` | Creates actor with cultivation paths attached |

## Architecture Compliance

- Lives in `app/` — composition root layer, may depend on anything
- No direct module references — uses facades only
- No `@onready` — nodes resolved in `_bind_nodes()`
- `summary()` for headless testing
- Lean: ~230 lines, under 400-line budget
