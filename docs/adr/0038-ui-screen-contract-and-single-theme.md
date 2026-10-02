# 0038 ui-screen-contract-and-single-theme

- Status: Accepted
- Date: 2026-10-02

## Context
The UI grew from two panels into a program (item workbench, inventory/detail/action
panels, `ScreenStack`). Four defects made future screens non-uniform:
- **Two themes.** `cultivation_theme.tres` (no `Button/disabled`, no type variations)
  and `chaos_world_theme.tres` (has both, plus `SectionTitle`/`MetaLabel`/`WarnLabel`/`OkLabel`).
  `cultivation_theme` has no disabled style, so a disabled button looks enabled.
- **Key drift.** body emits `target`/`ready`/`unmet`; qi emits `target_realm`/`can_attempt`/`unmet_conditions`.
- **`@onready` in `ui/`** (14 uses) breaks headless tests, which drive panels before a scene tree exists.
- **Number formatting in screens** (`"%d/%d | progress: %d"`), so the same value formats
  differently on each screen.

## Decision
- **One theme**: `src/ui/theme/chaos_world_theme.tres`. `cultivation_theme.tres` is deleted.
- **One screen contract**: a screen implements `summary()`, `refresh()`, and the four
  `ScreenStack` hooks; `summary()` returns primitives only, `{}` when no actor, child
  summaries nested under the child's key.
- **No `@onready` in `ui/`**: nodes resolve in `_bind_nodes()` via `get_node_or_null("%X")`.
- **No number formatting in a screen**: a screen passes raw values to a panel; the panel
  owns formatting. Step amounts live in the facade.
- **One `summary()` vocabulary**: `realm, target, progress, resource, channels, can_act,
  chance, unmet, costs`. A path-specific block nests under its own key.
- Cultivation screens are **one generic screen** over a normalized read contract, with
  per-path action adapters. The acupoint map stays its own screen.

## Consequences
- `items` and `body_cultivation` facades are at the 12-method cap, so a new UI need there
  means splitting the facade, not growing it.
- Existing screens migrate: remove `@onready`, rename qi keys, collapse themes (BL-0084..0087).
- `main.gd`/`mind_cultivation_ui.gd` are outside the standard and are removed, not migrated
  (ADR 0030).