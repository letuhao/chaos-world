# Input & Skill System Audit Report

## Criteria Coverage

### Input System

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Keyboard + mouse support | MET | `InputHandler.press_key()` handles WASD/Q/E/F/Z/X/C/R/Space/V/1-6/Tab; `click()` handles left/right |
| 2 | Combat/non-combat states | MET | `_in_combat` flag with `enter_combat()`/`exit_combat()`/`toggle_combat()`; skill keys only fire in combat |
| 3 | LLM-drivable | MET | `press_key()`, `click()`, `use_skill()`, `use_consumable()`, `toggle_combat()` all callable headlessly |
| 4 | 9 active skill slots | MET | `SKILL_KEYS` array with 9 entries: Q, E, F, Z, X, C, R, Space, V |
| 5 | 6 consumable slots | MET | `CONSUMABLE_KEYS` array with 6 entries: 1, 2, 3, 4, 5, 6 |
| 6 | Skills equipable | MET | `equip_skill(slot_index, skill_def)` / `unequip_skill(slot_index)` |
| 7 | Action skills combat-only | MET | `use_skill()` checks `_in_combat` and returns `not_in_combat` reason |
| 8 | Facade-only architecture | MET | `app/` layer references `core/` and `contracts/` only; consumables delegate to `ItemsApi` facade |
| 9 | Testable (summary) | MET | `InputHandler.summary()`, `SkillSystem.summary()`, `ConsumableSystem.summary()` |
| 10 | Input buffering | MET | `_buffer` array with 150ms window; `get_buffered_actions()`, `is_combo()` |

### Skill System

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | 9 active skill slots | MET | `SkillSystem.SLOT_COUNT = 9`, data-driven `SkillDef` resources |
| 2 | Cooldowns | MET | `_cooldowns` array, `tick(delta)`, `cooldown_ratio()` for UI overlay |
| 3 | Costs (qi/stamina) | MET | `SkillDef.qi_cost`, `stamina_cost`; `_can_afford()`/`_pay_cost()` |
| 4 | Action-oriented | MET | `effect_type` (damage/heal/buff/dash/aoe), `effect_value`, `effect_radius` |
| 5 | Combat-only enforcement | MET | `combat_only` flag + `_in_combat` check in `use_skill()` |
| 6 | Skill bar UI data | MET | `summary()` returns per-slot cooldown_ratio, costs, effect info |
| 7 | Consumable bar UI data | MET | `ConsumableSystem.summary()` returns per-slot def_id + quantity |
| 8 | LLM-drivable | MET | `equip_skill()`, `unequip_skill()`, `use_skill()`, `summary()` |

## Architecture Compliance

- `contracts/skill_def.gd` — no dependencies (pure data)
- `app/skill_system.gd` — depends on `core/` (Actor, Stat) + `contracts/` (SkillDef)
- `app/consumable_system.gd` — depends on `core/` + `contracts/` + `ItemsApi` facade
- `app/input_handler.gd` — depends on all above
- No upward layer violations
- No direct module-to-module references (consumables go through `ItemsApi`)

## Integration Points

| System | Integration | Status |
|--------|-------------|--------|
| Actor resources | Skill costs deduct from qi/stamina pools | WIRED |
| Stats | COOLDOWN_REDUCTION, QI_COST_REDUCTION applied | WIRED |
| Items module | Consumable use delegates to ItemsApi.use_item() | WIRED |
| Combat module | Shield/block can read input handler state | PENDING |
| UI program | summary() provides skill bar + consumable bar data | PENDING |
| Save system | Skill slots + consumable slots persist in module_data | WIRED |

## Test Coverage

74 tests covering:
- Slot initialization (9 skill, 6 consumable)
- Equip/unequip
- Combat-only enforcement
- Cooldowns
- Resource costs
- Combat toggle + timeout
- Key press routing
- Mouse click routing
- Input buffering + combo detection
- Consumable assign/use
- Summary contracts
- Persistence (module_data)
- Key mapping uniqueness
- Auto-combat request/disable/already-in-combat
- Test isolation (setup/reset)

## Bugs Fixed During Implementation

1. **Type error in `check_combo()`** — `pattern["sequence"]` returns `Array` but was assigned to `Array[StringName]`. Fixed by explicit element-wise conversion.

2. **Test isolation** — Shared `_input_handler` state leaked between tests (combat state, buffer, qi pool, consumable slots, auto_combat flag). Fixed by adding `reset()` method to `InputHandler` and `ConsumableSystem`, plus a `setup()` hook in the test framework.

3. **Consumable test** — `ItemDef` lacked `fixed_modifiers` with a resource restoration effect, causing `ItemUse.apply()` to return `no_applicable_effect`. Fixed by adding `fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]`.

4. **Combo detection** — `_check_combos()` cleared the buffer even when skill use failed, making combo assertions unreliable. Fixed by only checking combos when `use_skill()` succeeds.

## Gaps & Future Work

1. **UI scenes not built** — Skill bar and consumable bar scenes need to be created in `src/ui/panels/`. The data layer (summary()) is ready for UI consumption. The `summary()` output provides all data needed: per-slot `cooldown_ratio` for overlay rendering, `qi_cost`/`stamina_cost` for cost tinting, `effect_type`/`effect_value` for icon selection, and per-slot `quantity` for count badges.

2. **Skill effects not resolved** — `use_skill()` returns effect metadata but does not apply damage/heal to targets. A combat resolution system (DEF-0007) is needed. The `effect_type` and `effect_value` fields on `SkillDef` provide the data contract for a future damage pipeline.

3. **Mouse position for targeting** — `click()` accepts button name but not position. The 2D world adapter will pass mouse position when calling `click()` for skill targeting.

4. **SkillDef content** — No `.tres` skill definitions exist yet. Content authoring needed. The `SkillDef` resource class is ready for `.tres` authoring with all fields exported.

5. **Input map registration** — `project.godot` should declare all input actions: `move_up`/`move_down`/`move_left`/`move_right` (WASD), `interact` (E), `skill_1` through `skill_9` (Q/E/F/Z/X/C/R/Space/V), `consumable_1` through `consumable_6` (1-6), `combat_toggle` (Tab), `attack` (left click), `block` (right click).
