# 0043 headless-ui-cli-drives-screens-for-llm-and-player

- Status: Accepted
- Date: 2026-10-02

## Context
Screens were only reachable by opening the game and clicking. An agent — or a
human without a display — could not inspect what the UI shows or drive an action,
so the UI could not be verified except by the headless test suite.

## Decision
- `game/tools/ui_driver.gd` runs one screen headlessly, applies a script of
  commands, and emits one JSON document per step plus a final state.
- `uv run python -m tools ui drive --screen <scene> --path body|qi|mind --cmd <verb>`
  wraps it and prints one JSON object per line. `tools ui screens` lists what ships.
- The driver calls the screen's public `setup` / `act_*` / `summary` methods only.
  It never reaches into widgets, so anything it can drive a player can drive, and
  anything it reports is what the player sees.
- `game/tools/` is a new arch unit, `harness`: it may reach module internals (it
  builds an Actor directly) but never `app/`, so the harness cannot test wiring no
  player drives.
- `UiScreen` is the screen base: lazy `_bind_nodes()`, the four `ScreenStack` hooks,
  and a `summary()` that is `{}` with no actor and nests child summaries.
- `StatRow` owns every `%d/%d`; `ActionSet` owns the action row and result line, so
  no screen formats a number or invents a tone.

## Consequences
- Every screen is verifiable by an agent without a display or a click.
- A screen that adds an `act_<verb>` is immediately drivable from the CLI and needs
  no CLI change — that is the extension point.
- Screens normalize their facade's key names on the way in, so `can_attempt` and
  `can_act` cannot drift apart across screens.
- `run_godot` gained an opt-in `capture`; existing callers are unaffected.

### Amended after the completeness audit
The first driver could only *inspect*: one screen per process, a fresh actor every
run, zero-argument verbs. An LLM could look at the game but not play it.

- **The session is persistent.** The actor is saved to `user://ui_cli_session.json`
  and resumed on the next invocation, so progress is observable across commands.
  `--fresh` discards it.
- **The actor is seeded** with the realm items every gate needs, read from the realm
  seeds, so a caller is not permanently stuck at R1.
- **`grant:<item_id>`, `realm:<rank_id>`, `call:<method>[=arg]`** seed and drive
  directly. `call:` reaches non-`act_*` helpers such as `select_key`, which the
  item workbench needs to target anything but row 0.
- **`ScreenStack.on_stack_input` now honours the screen's return value.** It used to
  `return` unconditionally, so `ui_cancel` was dead on every screen implementing the
  hook — that is every screen on `UiScreen`. `on_stack_input` must return `bool`.
- **The 12-method facade cap was not enforced at all.** `FUNC_RE` matched `^func`,
  which never matches `static func`, so every facade reported zero public methods.
  Four facades are exactly at the cap; the guard is now real.