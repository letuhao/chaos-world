# 0030 ui-is-a-separate-top-level-program

- Status: Accepted
- Date: 2026-10-02

## Context
The game had no UI. The two early panels lived in `src/app/`, which `tools/arch`
exempts from every boundary rule, so a UI agent could call module internals
(`BodyTraining`, `BodyAdvancement`) with no error. That makes gameplay and UI work
collide silently: both agents edit the same files and neither `tools check` nor
`tools arch` reports it.

## Decision
`src/ui/` is a top-level program, separate from gameplay and from `app/`.
- Depends on `core` + `contracts`, and on modules **only** through `api.gd`.
- Declared deps live in `rules.UI_MODULES` — not `registry.json`, which
  `save_registry` rewrites with only `modules` and would silently drop a `ui` entry.
- May never reference `app/`. Boot and wiring stay in `app/`, which instantiates
  screens and injects the actor.
- Screens are `.tscn` composed in `src/ui/screens/`, styled by one `Theme` in
  `src/ui/theme/`, each exposing `summary() -> Dictionary` as its headless test contract.

## Consequences
- `tools arch` fails when `ui/` reaches past a facade or into `app/`. It detects
  bare class references in `ui/`, not just `res://`/`extends`, so panels call the
  facade by name with no `preload` ceremony.
- Gameplay and UI can proceed in parallel behind a `preview()` contract.
- The pre-existing `src/app/*_cultivation_ui.gd` panels are now outside the standard.
  They stay until the UI program replaces them; remove rather than migrate.
- The standard deliberately excludes a screen stack, a no-polling rule, and theme
  ownership: none is enforced and none is needed before the first real screen.
  Re-add a rule only when a screen proves the need.