# 0231 A domain is driven headlessly by a JSONL transcript over the facade, seeded and echoed

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0473 (the driver is unbuilt), BL-0220 (no headless way to see a domain)
- Implements the driver ADR 0072 promised at `:28` and never built.

## Context

ADR 0072 requires "a `tools` driver that enters a domain, prints map and encounter state
as JSON, accepts `--cmd` verbs, and writes a screenshot per step". Nothing registers such a
subcommand; `tools/__main__.py:32-71` has no `domain` module, and the two shipped harness
scripts are `game/tools/ui_driver.gd` (screens) and `boot_probe.gd` (the shell).

Everything the driver would read already exists and is already primitives-only:
`DomainApi.summary` (`api.gd:194-206`) folds the whole map in under `map_data`,
`DomainApi.templates` (`api.gd:66`) is the catalogue, `DomainMinimap.render`
(`domain_minimap.gd:59-73`) is the floor plan, `DomainBoot.bridge()`
(`domain_boot.gd:539-551`) already publishes the ten verbs a screen drives, and
`DomainBoot.read_model` (`:237-242`) is `{has_actor, templates, active}`.

So the missing thing is a **transport**, not plumbing. `tools ui drive` is the precedent
and its shape is right: a `SceneTree` script in the `harness` arch unit
(`enforce.py:63,153-161` — may reach module internals, may not reach `app/`), wrapped by a
Python task that parses `PREFIX` lines out of captured output (`tools/ui.py:105-118`).

## Decision

**`uv run python -m tools domain <sub>` over a JSONL transcript, with `--cmd` verbs, one
JSON document per step and a final state — plus `--seed` echoed into every document.**

- **Subcommands:** `templates` (the catalogue, no engine), `drive` (enter and play),
  `audit` (content shape over the `game/src/data/domains` tree).
- **Events:** one JSON object per line, prefixed `DOMAINJSON `, every one carrying
  `event`, `seed` and `template_id`. First is always `{"event":"ready", ...}`; last is
  always `{"event":"final","summary":{...}}`.
- **Verbs** are the ten the bridge already publishes, plus the drive-only ones: `enter`,
  `visit`, `arm`, `attempt`, `claim`, `leave`, `map`, `rooms`, `minimap`, `summary`,
  `grant:<item_id>`, `realm:<rank_id>`.
- **It reads the facade and the bridge, never a node.** `DomainBoot.bridge()` is the same
  seam `domain_explore.gd` drives, so anything the driver can play a player can play, and
  the driver cannot measure wiring the screen never reaches.
- **No screenshot.** See ADR 0232's last bullet.

## Consequences

- `templates` and the argument validation are engine-free; only `drive` and `audit` spawn
  the engine, and both go through `godot.run_godot`, so `TIMEOUT_SECONDS`,
  `RAM_CEILING_BYTES`, `LOG_BYTE_CEILING`, `SILENCE_GRACE_SECONDS` and `PROJECT_LOCK`
  apply (INC-0004/0005). There is **no** `game/tools/domain_driver.gd` invocation by path,
  ever.
- Seed supplied as `--seed N` (int, default `DomainBridge.DEFAULT_SEED` 20260904) and
  echoed on every event; a defect report is `--seed N --cmd ...` and nothing else.
- BL-0220 closes when `drive` lands. `audit` closes BL-0475 under ADR 0233.
