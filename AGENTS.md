# AGENTS.md

Chaos World is a Godot 4 **action RPG with cultivation**. Core loop: **combat → hunting → cultivate → breakthrough**; every other feature is added later. The repo is a git repository with a Python tool bundle (`tools/`), a Godot project (`game/`), content under `game/data/`, and a headless GDScript test suite. Everything below is the intended standard. Follow it when scaffolding, and update this file whenever a decision changes.

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
  src/ui/   UI program: theme, screens, widgets. Facade-only consumer of modules.
  scenes/   app-owned scene composition; UI scenes live in src/ui/screens/
  assets/   imported art / audio / fonts
  tests/    GDScript tests, mirroring the src/ layout
  data/     content resources (.tres): items/<category>/, recipes/, bosses/, domains/, ...
tools/      Python-only automation (uv package, outside res://)
docs/       architecture notes and ADRs
```
Item art uses reusable PNG and SVG families indexed by `game/assets/asset-index.jsonl`; style rules live in `docs/art-direction.md`.
Because the project is rooted at `game/`, Godot never scans `tools/` or `docs/` — do not add `.gdignore` for them.

## Commands
Prereqs: `uv` (https://docs.astral.sh/uv/) and a Godot 4.7.x binary.
- `uv sync` — create/refresh `.venv` from `pyproject.toml` + `uv.lock`.
- `uv run python -m tools fmt` — format GDScript + Python (`--check` to verify only).
- `uv run python -m tools lint` — static lint.
- `uv run python -m tools arch` — enforce module boundaries + SOLID structure (facade surface, line budget).
- `uv run python -m tools test` — run the Godot test suite headless.
- `uv run python -m tools test --suite <substring>` — run only the suites whose path matches. **Use this while iterating.**
- `uv run python -m tools check` — full gate, in order: `fmt --check -> lint -> arch -> deferred validate -> backlog validate -> data audit -> test`. Run before every commit; CI runs exactly this.
- `uv run python -m tools run` — launch the game.
- `uv run python -m tools ui screens|drive` — drive a screen headlessly and print its state as JSON; `--drive --screen <scene> --path body|qi|mind --cmd <verb>` (repeat `--cmd`). An agent inspects and plays the UI without a display.
- `uv run python -m tools export <preset>` — export a build.
- `uv run python -m tools new_module <name>` — scaffold a module and register it in `tools/arch/registry.json`.
- `uv run python -m tools new_adr "<title>"` — create the next numbered ADR in `docs/adr/`.
- `uv run python -m tools deferred report|search|add|done|validate` — inspect and maintain `docs/deferred.jsonl`.
- `uv run python -m tools data report|audit` — inspect and audit content under `game/data/` (acquisition gaps).
- `uv run python -m tools data distribution` — audit item characteristic distribution/diversity (category, subtype, grade, source, modifier coverage). Read-only, non-gating by default; `--fail-on warn|error` to gate. Run before planning a generation wave.
- `uv run python -m tools cultivation seed|seed-systems|validate|report` — write missing realm-seed content (never overwrites authored files), audit the generation contract, or print the deterministic body-ladder balance report.

**Godot binary is not on `PATH`.** `tools/godot.py` resolves it from `GODOT_BIN`, else the gitignored `.godot-bin` file, else `PATH`, and fails loudly if none resolve. Do not hardcode machine paths anywhere else.

**Do not rely on bare `python`.** System Python here is inconsistent (3.13 on `PATH`, a broken `py` launcher, 3.10 as `python3`). Always use `uv run`, which honors `.python-version`/`uv.lock`.

## Agent workflow
Optimize for small verifiable steps. The repo is the source of truth; chat history is not.
1. **Orient cheaply.** Read this file, then only the target module's `api.gd` and the files you will touch. Do not read the whole repo — take evidence from `tools arch` / `tools test` output instead.
2. **State the goal in one sentence** in your reply. If it needs a design doc to explain, split it.
3. **Ship one vertical slice**, then run `uv run python -m tools check`. Fix failures before continuing.
4. **Test what you changed, not everything.** Use `tools test --suite <substring>` while building. Run the full suite only to release a finished module, or when a critical bug makes the game fail to build or load and you need the whole picture. A full run mid-build wastes minutes and reports other agents' in-flight breakage as if it were yours.
5. **Record durable decisions only.** An architectural choice future agents could get wrong goes in a one-page `docs/adr/NNNN-<slug>.md`. Everything else is written nowhere.
6. **Touch this file only when a rule changes.** Never add changelogs, status, or plan sections.

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
ui/           UI program. Depends on core + contracts, and on modules only via their facade.
modules/<x>/  feature modules. Depend on core + contracts, and on other modules only via their facade.
core/         foundation primitives (math, events, utils). Depends on contracts only.
contracts/    dependency-free interfaces, value objects, event/signal contracts. Depends on nothing.
```
Rules enforced by `tools/arch` (defined in `tools/arch/rules.py`):
- `contracts` and `core` must never reference `modules/` or `app/`.
- Nothing may reference `app/` except `app/`.
- A module may reference another module **only** through its facade `game/src/modules/<x>/api.gd`; touching any other file in that module is a violation.
- `ui/` is a **pure consumer**: same facade-only rule, but only for the modules listed in `rules.UI_MODULES`, and it may never reference `app/`.
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

## Realm scale: a magnitude and a rate, never one number
There is no shared power curve. A realm's strength is authored data and lives in `core/realm_power_table.tres`, one multiplier per realm **keyed by realm id**, R1 at 1.0. Keyed by id, never by position: an inserted realm would silently shift every realm below it.
- **A magnitude and a rate are different kinds of number.** A magnitude answers "how strong is a thing from this realm"; a rate answers "what is one unit of this realm's training worth". A rate must never track a magnitude — reading a shared exponential as a gain is what once made a single breakthrough worth more than everything else combined.
- **Magnitudes** are owned where they belong. `RealmScaling` (core) scales the shared combat stats by `realm.power`; each path's own magnitude is authored on its own seed (`integrity_maximum`, `sea_capacity`, …) and applied once. Do not scale the same realm twice.
- **Rates** live in each path's `realm_profile.gd` as `factor(realm_id) = RATE_STEP^ordinal`, where `ordinal` is `RealmDef.index`. Bounded by construction: `RATE_STEP^29` is under 2x. A rate needs no justification for being modest, but it does need to stay a gain.
- **`RATE_STEP` is deliberately triplicated** — one per path — because a module may only reach another module through its `api.gd` facade, and the alternative is a shared curve. Retune all three together; nothing enforces that for you.
- **`RATE_STEP` must stay at or below the smallest per-realm step in the authored work budget**, or the rate outruns the price and the deep realms get cheap.
- **Guard:** `uv run python -m tools realm_power check` runs in `tools check`. It asserts the table's shape — one entry per realm, R1 at 1.0, strictly rising, finite, inside a readable range — not the recipe that filled it, so the numbers stay hand-editable. `realm_power emit --force` rewrites the file.
- **Two per-realm tables is deliberate, not drift.** `core/realm_power_table.tres` is actor stat strength (1.0 → 551x); `game/data/item_options/item_magnitude_scale.json` is item magnitudes (1.0 → 3.9x). They measure different things — an item is not an actor — and their ranges differ because an item is a relative upgrade inside a realm/rarity band, not an absolute power claim. Never derive one from the other, and never let either compute from a realm index. Reconciling them is a new decision needing its own ADR (ADR 0050).
- **Adding a scale is a reviewed change**, not a convenience. A new power-shaped number needs an ADR, not a second curve.

## UI standard
`ui/` is a separate program from gameplay. It renders state and calls public actions; it never owns game rules.
- **Layout** — anchors + `Container` nodes only. Never absolute positions, never child anchors inside a container.
- **Composition** — a screen is `.tscn` + script in `src/ui/screens/`; reusable rows live in `src/ui/panels/`. Never build widgets in `_ready()`.
- **Theme** — one theme, `src/ui/theme/chaos_world_theme.tres`. Style by `theme_type_variation`; `theme_override_*` is banned.
- **No `@onready` in `ui/`** — resolve nodes in `_bind_nodes()` via `get_node_or_null("%X")`; headless tests drive panels with no scene tree.
- **No number formatting in a screen** — screens pass raw values to a panel; the panel owns `%d/%d`, decimals and widths. Step amounts live in the facade.
- **Focus** — implement the `ScreenStack` hooks (`focus_initial`, `on_screen_shown`, `on_screen_hidden`, `on_stack_input`), never `grab_focus()` in `_ready()`.
- **Testable contract** — every screen/panel exposes `summary() -> Dictionary`: primitives only, `{}` when no actor, child summaries nested under the child's key. Tests assert that, not pixels.
- **No autoload** holds feature UI.

`tools arch` enforces the facade rule for `ui/` by scanning bare class references, so panels call the facade by name with no `preload` ceremony. Note `items` and `body_cultivation` are at the 12-method facade cap — a new UI need there means splitting the facade, not growing it.

**Split dev cycle** — gameplay and UI can be built in parallel:
1. Gameplay publishes a facade method or `preview() -> Dictionary` answering "what is true now?".
2. UI builds only against that contract, never module internals.
3. Both stay green independently.

Where a panel needs something the facade does not expose, add it to the facade — do not widen `ui/` to reach internals.

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
