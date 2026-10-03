# Input & Skill System Design

## Overview

Input and skill systems for the action RPG slice. The input handler routes keyboard/mouse events through a combat/non-combat state machine. The skill system manages 9 equipable active slots with cooldowns and resource costs. The consumable system manages 6 quick-use slots.

## Input Mapping

### Keyboard

| Key | Non-Combat | Combat |
|-----|-----------|--------|
| W/A/S/D | Move 8-direction | Move 8-direction |
| E | Interact (talk/gather/enter) | Skill slot 2 |
| Q | — | Skill slot 1 |
| F | — | Skill slot 3 |
| Z | — | Skill slot 4 |
| X | — | Skill slot 5 |
| C | — | Skill slot 6 |
| R | — | Skill slot 7 |
| Space | — | Skill slot 8 |
| V | — | Skill slot 9 |
| 1-6 | Use consumable | Use consumable |
| Tab | Toggle combat | Toggle combat |

### Mouse

| Button | Non-Combat | Combat |
|--------|-----------|--------|
| Left click | Interact/attack | Basic attack |
| Right click | — | Block/defend |

## Combat State Machine

Two states: `NON_COMBAT` and `COMBAT`.

**Transitions:**
- `NON_COMBAT → COMBAT`: Tab press, enemy proximity (auto), left-click attack
- `COMBAT → NON_COMBAT`: Tab press, combat timeout (no damage dealt/received for 5s)

**Enforcement:**
- Action skills (slots 1-9) only fire in `COMBAT` state
- In `NON_COMBAT`, skill keys are no-ops (return `{"ok": false, "reason": "not_in_combat"}`)
- Consumables work in both states

## Skill System

### SkillDef (contracts/skill_def.gd)

Data-driven skill definition, authored as `.tres`:

```
id: StringName          # unique skill id
display_name: String
description: String
cooldown: float         # seconds
qi_cost: float          # qi consumed on use
stamina_cost: float     # stamina consumed on use
combat_only: bool       # always true for action skills
effect_type: StringName # damage, heal, buff, dash, aoe
effect_value: float     # magnitude
effect_radius: float    # 0 = single target
icon: StringName        # icon identifier for UI
```

### Skill Slots

9 fixed slots, each holding a SkillDef reference or null:

| Slot | Key | Index |
|------|-----|-------|
| 1 | Q | 0 |
| 2 | E | 1 |
| 3 | F | 2 |
| 4 | Z | 3 |
| 5 | X | 4 |
| 6 | C | 5 |
| 7 | R | 6 |
| 8 | Space | 7 |
| 9 | V | 8 |

### Cooldowns

- Each slot tracks `_cooldown_remaining: float`
- `tick(delta)` decrements all active cooldowns
- Cooldown reduction stat (`Stat.COOLDOWN_REDUCTION`) applies
- UI reads `cooldown_ratio()` for overlay rendering

### Costs

- Qi cost: deducted from actor's qi resource pool
- Stamina cost: deducted from actor's stamina resource pool
- Cost reduction stats apply (`Stat.QI_COST_REDUCTION`)
- Insufficient resources → use fails with reason

### Equip

- `equip_skill(slot_index, skill_def)` — assign a skill to a slot
- `unequip_skill(slot_index)` — clear a slot
- Equipped skills persist in actor's module_data

## Consumable System

### Consumable Slots

6 fixed slots for quick-use items:

| Slot | Key | Index |
|------|-----|-------|
| 1 | 1 | 0 |
| 2 | 2 | 1 |
| 3 | 3 | 2 |
| 4 | 4 | 3 |
| 5 | 5 | 4 |
| 6 | 6 | 5 |

### Behavior

- Each slot holds an item def_id + quantity
- `use_consumable(slot_index)` delegates to `ItemsApi.use_item()`
- Works in both combat and non-combat states
- UI shows item count per slot

## Input Buffering

Inputs are buffered for 150ms to enable combo chains:

```
buffer: Array[BufferedInput]
BufferedInput = { action: StringName, timestamp: float }
```

- `press_key(key)` adds to buffer and processes immediately
- `get_buffered_actions()` returns actions within the window
- `is_combo(actions)` checks if buffer matches a known combo pattern
- Buffer clears on successful combo or timeout

### Combo Patterns

Three combo chains, each with a 1.5x damage multiplier:

| Combo | Sequence | ID |
|-------|----------|-----|
| Flame Chain | Q → E → F | `flame_chain` |
| Shadow Chain | Z → X → C | `shadow_chain` |
| Arcane Chain | R → Space → V | `arcane_chain` |

Combos are only checked when a skill use succeeds, so failed skill uses don't consume the buffer.

## LLM-Drivable API

### InputHandler

```gdscript
func press_key(key: StringName) -> Dictionary    # simulate key press
func click(button: StringName) -> Dictionary     # simulate mouse click
func use_skill(slot_index: int) -> Dictionary    # trigger skill slot
func use_consumable(slot_index: int) -> Dictionary
func toggle_combat() -> Dictionary
func enter_combat() -> Dictionary
func exit_combat() -> Dictionary
func request_auto_combat() -> Dictionary
func reset() -> void                              # test isolation
func summary() -> Dictionary
```

### SkillSystem

```gdscript
func equip_skill(slot_index: int, skill_def: SkillDef) -> Dictionary
func unequip_skill(slot_index: int) -> Dictionary
func use_skill(slot_index: int) -> Dictionary
func tick(delta: float) -> void
func set_combat_state(in_combat: bool) -> void
func cooldown_ratio(slot_index: int) -> float
func slot_count() -> int
func skill_at(slot_index: int) -> SkillDef
func summary() -> Dictionary
```

### ConsumableSystem

```gdscript
func assign_consumable(slot_index: int, def_id: StringName, quantity: int) -> Dictionary
func unassign_consumable(slot_index: int) -> Dictionary
func use_consumable(slot_index: int) -> Dictionary
func slot_count() -> int
func def_id_at(slot_index: int) -> StringName
func reset() -> void                              # test isolation
func summary() -> Dictionary
```

## UI Layout

### Skill Bar (bottom center)

```
[Q] [E] [F] [Z] [X] [C] [R] [Spc] [V]
```

- 9 slots, each showing skill icon
- Cooldown overlay: radial or vertical fill (via `cooldown_ratio()`)
- Cost indicator: qi/stamina cost tint
- Empty slot: dimmed

### Consumable Bar (above skill bar)

```
[1] [2] [3] [4] [5] [6]
```

- 6 slots, each showing item icon + count
- Count badge bottom-right
- Empty slot: dimmed

## Architecture

- `contracts/skill_def.gd` — SkillDef data resource (no dependencies)
- `app/skill_system.gd` — slot management, cooldowns, costs (depends on core + contracts)
- `app/consumable_system.gd` — consumable slots (depends on core + contracts + items facade)
- `app/input_handler.gd` — input routing, state machine, buffering (depends on all above)

All systems expose `summary() -> Dictionary` for headless testing and UI consumption.

## Test Isolation

The test framework calls `setup()` before each test method. The input system test overrides `setup()` to call `_input_handler.reset()`, which:
- Exits combat state
- Clears the input buffer
- Resets `auto_combat_enabled` to true
- Clears all consumable slots
- Refills qi and stamina pools to maximum

This ensures each test starts with clean state regardless of execution order.
