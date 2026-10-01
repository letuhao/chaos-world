# AGENTS.md

Chaos World is a Godot 4 **action RPG with cultivation**. Core loop: **combat → hunting → cultivate → breakthrough**; every other feature is added later. This repo is **greenfield**: nothing exists yet except the agent-tooling dirs `.pi/`, `.remember/`, and `.agents/`, and it is not a git repository. Everything below is the intended standard. Follow it when scaffolding, and update this file whenever a decision changes.

> `tools/` does not exist yet. Creating its entrypoints (below) is the first task; until then the `uv run python -m tools ...` commands will fail.

## Non-negotiable rules
- **Python-only tooling.** Every script, task, and automation entrypoint is a Python module run through `uv`. Do **not** add `.bat`, `.ps1`, `.cmd`, or `.sh` files, and never document a shell one-liner as the supported path.
- **Godot 4.7.x, standard (GDScript) build.** Not the .NET/C# build. GDScript for game code, Python for tooling. Do not introduce C#.
- **All commands go through `uv run python -m tools <task>`.** Never invoke Godot, `gdformat`, `gdlint`, or the test addon directly from docs or CI.
- **Boundary truth is code, not prose:** `tools/arch/rules.py` (policy) and `tools/arch/registry.json` (machine-managed state). The checker is authoritative.
- **English, lean docs.** Every document is in English and as short as it can be — see Documentation rules.
- **No sexual content.** Succubus, dual-cultivation, and fertility are pure gameplay mechanics: never write sexual, explicit, or suggestive prose, descriptions, names, or assets. Keep everything clinical and mechanical.

## Layout
```
game/       Godot project root (project.godot lives here). res:// is relative to game/.
  addons/   pinned editor plugins (test framework, etc.)
  src/      all GDScript, organized by layer/module (see below)
  scenes/   app-owned scene composition; modules own their own scenes
  assets/   imported art / audio / fonts
  tests/    GDScript tests, mirroring the src/ layout
tools/      Python-only automation (uv package, outside res://)
docs/       architecture notes and ADRs
```
Because the project is rooted at `game/`, Godot never scans `tools/` or `docs/` — do not add `.gdignore` for them.

## Commands
Prereqs: `uv` (https://docs.astral.sh/uv/) and a Godot 4.7.x binary.
- `uv sync` — create/refresh `.venv` from `pyproject.toml` + `uv.lock`.
- `uv run python -m tools fmt` — format GDScript + Python (`--check` to verify only).
- `uv run python -m tools lint` — static lint.
- `uv run python -m tools arch` — enforce module boundaries + SOLID structure (facade surface, line budget).
- `uv run python -m tools test` — run the Godot test suite headless.
- `uv run python -m tools check` — full gate, in order: `fmt --check -> lint -> arch -> test`. Run before every commit; CI runs exactly this.
- `uv run python -m tools run` — launch the game.
- `uv run python -m tools export <preset>` — export a build.
- `uv run python -m tools new_module <name>` — scaffold a module and register it in `tools/arch/registry.json`.
- `uv run python -m tools new_adr "<title>"` — create the next numbered ADR in `docs/adr/`.
- `uv run python -m tools deferred report|search|add|done|validate` — inspect and maintain `docs/deferred.jsonl`.

**Godot binary is not on `PATH`.** `tools/godot.py` resolves it from `GODOT_BIN`, else the gitignored `.godot-bin` file, else `PATH`, and fails loudly if none resolve. Do not hardcode machine paths anywhere else.

**Do not rely on bare `python`.** System Python here is inconsistent (3.13 on `PATH`, a broken `py` launcher, 3.10 as `python3`). Always use `uv run`, which honors `.python-version`/`uv.lock`.

## Agent workflow
Optimize for small verifiable steps. The repo is the source of truth; chat history is not.
1. **Orient cheaply.** Read this file, then only the target module's `api.gd` and the files you will touch. Do not read the whole repo — take evidence from `tools arch` / `tools test` output instead.
2. **State the goal in one sentence** in your reply. If it needs a design doc to explain, split it.
3. **Ship one vertical slice**, then run `uv run python -m tools check`. Fix failures before continuing.
4. **Record durable decisions only.** An architectural choice future agents could get wrong goes in a one-page `docs/adr/NNNN-<slug>.md`. Everything else is written nowhere.
5. **Touch this file only when a rule changes.** Never add changelogs, status, or plan sections.

Handoff: commit messages carry the what/why; the active goal carries the now. Do not create notes, plans, or status files.

Definition of done: `tools check` passes; behavior changes have tests under `game/tests/`; new `contracts/` interfaces have contract tests; module-graph changes update `tools/arch/registry.json` (plus an ADR if a boundary moved); no new Markdown beyond the allowed set.

## Skill index
Skills live at `.agents/skills/<id>/SKILL.md`; `.agents/` and `skills-lock.json` are **committed** repo assets (do not gitignore). Load only the skills a task needs (`router` when unsure) — never bulk-load.
| Need | Skills |
|---|---|
| Entry / unsure | `router` |
| Godot foundation | `godot-gdscript`, `godot-nodes-scenes`, `godot-resources`, `godot-signals-groups`, `godot-physics`, `godot-animation`, `godot-ui-control`, `godot-audio`, `godot-shaders` |
| Movement / world | `godot-2d-movement`, `godot-tilemap` (2D — decided, ADR 0001) |
| Genre anchor | `rpg` — stats, leveling, inventory, combat, quests, saves |
| Combat | `game-ai`, `ai-behavior-trees-utility-ai`, `game-feel`, `camera-systems`, `input-systems`, `physics-tuning` |
| Hunting | `game-ai`, `level-design`, `procedural-gen`, plus the movement/world skill |
| Cultivate | `rpg`, `godot-resources`, `save-systems` |
| Breakthrough | `rpg`, `save-systems`, `game-ui-ux`, `godot-ui-control`, `game-feel` |
| Cross-cutting | `game-ui-ux`, `audio-design`, `performance-optimization`, `create-game-assets` |
| Prototyping | `prototype-fast` |
| Build / ship | `godot-gdscript-headless-testing`, `godot-export`; add `itch-publish` / `steam-publish` when releasing |

**Decided:** 2D (ADR 0001). **Out of scope unless a task names it:** `godot-csharp` (GDScript-only repo), all non-Godot engine skills (`unity-*`, `unreal-*`, `bevy-*`, `phaser-*`, `pixijs-*`, `threejs-*`, `love2d-*`, `pygame-*`, `roblox-*`), and off-genre genres (`platformer`, `roguelike`, `fps-shooter`, `card-game`, `puzzle`, `tower-defense`, `visual-novel`, `survival-crafting`). `dialogue-systems` and `godot-multiplayer` are deferred until a feature needs them.

## Architecture: layers and module boundaries
`game/src/` is layered. Dependencies point **downward only**, and cross-module dependencies only through a public facade.
```
app/          composition root: boot, autoloads, wiring. May depend on anything.
modules/<x>/  feature modules. Depend on core + contracts, and on other modules only via their facade.
core/         foundation primitives (math, events, utils). Depends on contracts only.
contracts/    dependency-free interfaces, value objects, event/signal contracts. Depends on nothing.
```
Rules enforced by `tools/arch` (defined in `tools/arch/rules.py`):
- `contracts` and `core` must never reference `modules/` or `app/`.
- Nothing may reference `app/` except `app/`.
- A module may reference another module **only** through its facade `game/src/modules/<x>/api.gd`; touching any other file in that module is a violation.
- Module dependency cycles are forbidden.
- `res://` scene/resource references follow the same rules as script references.
- GDScript must never import from `tools/`.
- The shared actor base (`core/actor.gd` + `core/actor_stats.gd`) is the single source of stats for all actors — see ADR 0001.

Design principles to apply:
- **Composition over inheritance.** Prefer child nodes/scenes as components over deep `extends` chains.
- **Dependency inversion.** Modules depend on `contracts` interfaces, not concrete siblings; `app/` injects implementations.
- **Event-driven decoupling.** Cross-module communication uses typed signals/events defined in `contracts`, not direct node lookups.
- **Minimal autoloads.** Autoloads are global singletons — keep them to documented infrastructure declared in `game/project.godot`, never feature logic. No cross-module `get_node("/root/...")`.
- One module = one reason to change. If two modules need each other's internals, the boundary is wrong: move the shared part to `contracts`/`core`.

## SOLID workflow
Contract-first; the composition root is the only place that knows concrete types.
1. **D — invert dependencies.** Define or extend the interface in `contracts/` before behavior. Modules depend on that interface, never on a sibling's concrete script.
2. **I — keep interfaces small.** `api.gd` exposes only what other modules need; split rather than grow a god-facade.
3. **S — one responsibility.** A module answers one "why change". If a script needs "and", split a component out.
4. **O — extend, do not edit.** Add a module or component and wire it in `app/`; never put feature logic in `core/`. Changing a `contracts/` interface or `core/` behavior requires an ADR in the same change.
5. **L — substitutable implementations.** Any script implementing a `contracts/` interface must pass the same contract tests.

Loop: contract -> implementation -> app wiring -> contract test -> `tools check`.

Where it is enforced:
- DIP/ISP: `tools arch` — facade-only cross-module edges, no upward layer deps.
- ISP: `tools arch` caps the public surface of `api.gd`.
- SRP: `tools arch` warns when a script exceeds the line budget.
- OCP: an ADR is required for `core/`/`contracts/` changes.
- LSP: each `contracts/` interface ships contract tests under `game/tests/contracts/`.

## Adding or changing a module
1. Run `uv run python -m tools new_module <name>` (or create `game/src/modules/<name>/` with an `api.gd` facade).
2. Set its allowed dependencies in `tools/arch/registry.json` (written by `new_module`; never edit Python for this); run `tools arch`.
3. Add tests under `game/tests/modules/<name>/`.
4. Record the decision with `uv run python -m tools new_adr "<title>"`.
Changing a boundary rule is an architecture change: update the rule, the ADR, and this file together — never weaken a rule just to make code pass.

## Godot conventions
- Follow the official GDScript style guide. Files/folders `snake_case`; `class_name` and node names `PascalCase`; signals `snake_case` past tense (`health_depleted`); constants `CONSTANT_CASE`; private members `_leading_underscore`.
- A script file is `snake_case` and matches its scene's root node name; scenes are `PascalCase.tscn`.
- `class_name` is a global namespace — keep names unique and prefix with the module when ambiguous.
- `game/.godot/` is a generated import cache: never commit, edit, or read it for truth. Commit `*.import` and `*.uid` files.
- `.tscn`/`.tres` are text but editor-owned and order-sensitive: make minimal diffs, never regenerate whole scenes by hand, keep logic in scripts.
- Use `res://` paths (relative to `game/`) in code and resources, never OS-absolute paths.

## Python tooling conventions
- `tools/` is a real `uv` package. Add dependencies to `pyproject.toml` and commit `uv.lock`; no ad-hoc `pip install`.
- One module per task exposing `register(subparsers)` + `run(args)`; `tools/__main__.py` dispatches subcommands.
- Machine-managed state (module registry, ADR numbering) lives in structured files written by tools — never hand-edit it into docs or Python.
- Tools must be deterministic, non-interactive, and return non-zero on failure (CI depends on exit codes).
- Build output goes to a gitignored `build/`; never write generated artifacts into `game/src/`.

## Documentation rules
- **English only** — docs, code comments, commit messages, ADRs, issues, PR text.
- **Lean by default** — bullets, one fact per line, no tutorials, no restating code or config. If a line would not surprise a competent agent, delete it.
- **One source of truth** — precedence: code/config > `AGENTS.md` > ADRs. When docs disagree with code, code wins; fix the doc in the same change. Link, never duplicate.
- **Allowed docs** — `AGENTS.md`, `docs/adr/NNNN-*.md`, and the machine-readable `docs/deferred.jsonl` only. Do not add READMEs, design docs, status files, or notes; ask before creating any other Markdown.
- **Deferred work** — tracked in `docs/deferred.jsonl`, one JSON object per line with `id`, `area`, `title`, `status`, `source`, `reason`, `next`, `created`. Record deferrals there instead of prose TODOs. Use `uv run python -m tools deferred` (`report`/`search`/`add`/`done`/`validate`); `tools check` validates the file. When solved, set `status` to `done` and add a `resolved` date; keep the entry as the trace. Add `priority`/`depends_on` when useful. Never delete entries.
- **Caps** — `AGENTS.md` ≤ 200 lines; an ADR ≤ 1 page. Over budget means split or delete.
- **ADRs are immutable** once accepted: supersede with a new ADR, do not rewrite history.
- **Docs ship with code** in the same change; delete stale text rather than appending "updated" notes.

## Repo hygiene
- `.pi/` and `.remember/` are local agent state, not game code: leave them alone and keep them gitignored. `.agents/` and `skills-lock.json` are the opposite — committed shared skills (see Skill index).
- `.gitignore` at minimum: `game/.godot/`, `build/`, `.venv/`, `.ruff_cache/`, `.remember/`, `.pi/`, and any local `GODOT_BIN` config.
- CI (`.github/workflows/ci.yml`) is YAML and may only shell out to `uv sync` and `uv run python -m tools check` — no inline logic, no bat/ps1.
