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

**Never invoke the Godot binary directly.** Go through `tools/godot.py` (`tools test`, `tools run`, `tools ui`, `tools export`). It passes `--log-file build/godot.log` and enforces a 900 s ceiling. Bypassing it opts you into the hazard below.

**Do not rely on bare `python`.** System Python here is inconsistent (3.13 on `PATH`, a broken `py` launcher, 3.10 as `python3`). Always use `uv run`, which honors `.python-version`/`uv.lock`.

## Logs, memory, and runaway loops: hard disk- and machine-safety rules
Three ceilings exist because three different runaway shapes exist. `tools/godot.py` enforces all of them; none is optional and none may be raised to stop a failure firing.

**1. Log (disk).** Godot's own log defaults to `%APPDATA%/Godot/app_userdata/<project>/logs/`, rotating at **2 GB per file with no total ceiling** (`max_log_files=5`) — ~10 GB per incident, re-created every run, on the user's **C:** drive. A mind_cultivation test once entered an unbounded retry loop, `push_error` fired every iteration, and ~10 GB was written before anyone noticed.
- **A loop that spams is a bug to fix, never output to preserve.** Do not "let it log" a failure you have not read.
- `debug/file_logging/enable_file_logging` in `project.godot` **does not disable it** — the engine reads the `.pc` variant, which stays `true`. Only `--log-file` redirects the sink, which is why `tools/godot.py` owns it. Do not "fix" this by editing `project.godot`. A persisted log goes in `build/` (gitignored) — never the user profile.

**2. Memory (RAM).** A `tests/ui` run once reached **67 GB resident / 105 GB commit at ~0.3 GB/s** and the machine had to be power-cycled. The clock and disk ceilings both measure *output*, so an allocating loop that prints nothing passes both — that is the gap `RAM_CEILING_BYTES` closes.
- **A loop that allocates without releasing is the same defect as a loop that spams.** Leaking a `Node`, `Resource` or `String` per iteration exhausts RAM exactly as fast as logging fills the SSD, and is just as invisible.
- **Anything mounted under `root` in a test must be freed.** `add_child` without a matching `free()`/`queue_free()` is a leak, not a fixture. `SeamHarness.teardown()` is idempotent and safe after an abort — call it.
- **`queue_free()` in `res://src` is banned: use `free()`.** The headless runner drives every test from `SceneTree._initialize()`, which returns before the first frame, so a deferred free *never runs* under `tools test`. Detach the node (`remove_child`) first, then `free()`. Enforced by `tests/arch_rules/test_no_deferred_free.gd`. This one deferral leaked a screen subtree per navigation and a map graph per refresh — the 67 GB.
- **A loop that tests a size it is itself growing is infinite.** `while count < board.size() + 4` where the body inserts one key per pass never terminates: `size` rises in lockstep with `count`. Snapshot the bound **before** the loop. This is the loop that reached 67 GB.

**3. Infinite loop (time).** A feature that cannot work must fail out loud, not spin. If an exit condition cannot be met, never leave it running and never bound it by a huge iteration count — that just burns disk or RAM more slowly. Make it fail.
- **Every loop gets a real guard.** A `while` on game state needs a bounded, *small* cap that names the condition which failed to converge. Never a bare unbounded `while`.
- **That rule is enforced, not just written.** `tests/arch_rules/test_no_unbounded_wait.gd` fails the build on any `while` in `res://src` **or `res://tests`** it cannot show terminating: it moves a counter it reads, is the `DirAccess` terminator, drains a container it tests, fills one toward a fixed count with an *unconditional* append, or breaks/returns. Tests are scanned because the loop that filled the disk was a test's. Do not add an exception because a loop "looks fine" — that judgement shipped the 1 GB/s loop.
- **Recursion needs a depth cap** for the same reason: a cycle in a traversal (A holds B, B holds A) is an unbounded loop that `while` scanning cannot see.
- **Never re-run a loop body that asserts.** `TestCase` (`game/tests/framework.gd`) kills the process via `OS.crash` past `MAX_FAILURES` / `MAX_ASSERTIONS`; that is the intended backstop, not a number to raise until it stops firing.

**Never reproduce a runaway to diagnose it.** A timeout, a `=== FATAL ===` crash, or a ceiling breach already names the cause in its message and points at the log; a manual repro spends the user's disk, RAM and time to re-learn what the ceiling just reported, and has twice forced a power-cycle. Read the log, read the code, fix the loop. Fix first, verify by the guard not firing — that is the whole test, and it is not an A/B experiment. If a repro is genuinely unavoidable, say so and get the user's go-ahead first.

## Agent workflow
Optimize for small verifiable steps. The repo is the source of truth; chat history is not.
1. **Orient cheaply.** Read this file, then only the target module's `api.gd` and the files you will touch. Do not read the whole repo — take evidence from `tools arch` / `tools test` output instead.
2. **State the goal in one sentence** in your reply. If it needs a design doc to explain, split it.
3. **Ship one vertical slice**, then run `uv run python -m tools check`. Fix failures before continuing.
4. **Test what you changed, not everything.** Use `tools test --suite <substring>` while building. Run the full suite only to release a finished module, or when a critical bug makes the game fail to build or load and you need the whole picture. A full run mid-build wastes minutes and reports other agents' in-flight breakage as if it were yours.
5. **Record durable decisions only.** An architectural choice future agents could get wrong goes in a one-page `docs/adr/NNNN-<slug>.md`. Everything else is written nowhere.
6. **Touch this file only when a rule changes.** Never add changelogs, status, or plan sections.
7. **Commit your own work; committing is part of the task, not a favour.** An uncommitted change is only safe while you are still alive. This tree is shared with live agents: a bulk revert, a stray `git checkout .`, or one agent's session ending can wipe uncommitted work, and uncommitted work is **unrecoverable** — there is no reflog entry for a file that was never staged. Commit at the end of each vertical slice, before you start the next one.
   - Stage **only your own paths**: `git add <path> <path>`, never `git add -A`, `git add .`, or `git commit -a`. A blanket stage swallows a concurrent agent's in-flight edits into your commit and makes them unrecoverable too.
   - `git commit -am`/`git add -u` are equally unsafe here — they sweep every modified tracked path, including other agents'.
   - Before committing, `git status --short` and confirm every staged path is one you edited. If something foreign appears, unstage it (`git restore --staged <path>`) rather than committing it.
8. **The working tree is shared with live agents.** Never `git checkout`, `git restore`, `git revert`, or `git stash` a path you do not own — a concurrent agent's edits and this file itself are not yours to roll back. Bulk-reverting "my" files has twice destroyed another agent's finished work. Undo your own mistake by hand, path by path.
   - `git checkout .` / `git restore .` / `git stash` with no pathspec are **forbidden outright**: they are not "reverting my files", they are reverting everyone's.
   - Never `git push --force` or `git reset --hard` on a shared branch. There is no undo for either once another agent has pulled.
   - To undo your own edit, fix it forward with `edit_file`/`write_file`, or revert one specific commit you authored by hash (`git revert <your-sha>`), never a path-wide sweep.

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
- **Rates** are ONE shared curve in `core/realm_rate.gd` (`RealmRate`): `factor(realm_id) = RATE_STEP^ordinal`, where `ordinal` is `RealmDef.index`. Bounded by construction — `RATE_STEP^29` is under 2x, a gain and never a magnitude. `RATE_STEP` is authored there once and shared by all three paths (ADR 0066): it is not triplicated, because `core` is a layer, not a module, so the cross-module facade rule never applied to it. Retuning it is a one-line edit and cannot desynchronise a copy — but `tools realm_power check` does not cover it.
- **`RATE_STEP` must stay at or below the smallest per-realm step in the authored work budget**, or the rate outruns the price and the deep realms get cheap.
- **Guard:** `uv run python -m tools realm_power check` runs in `tools check`. It asserts the table's shape — one entry per realm, R1 at 1.0, strictly rising, finite, inside a readable range — not the recipe that filled it, so the numbers stay hand-editable. `realm_power emit --force` rewrites the file.
- **Two more per-realm tables are deliberate, not drift.** `game/data/item_options/item_magnitude_scale.json` is item magnitudes (1.0 → 3.9x) and technique magnitudes are ~1.0 → ~2.8x geometric (ADR 0055) — an item is not an actor, and a technique bonus rides on top of both, so it stays an order of magnitude below `realm_power_table.tres` (1.0 → 551x). Never derive any of the three from another, and never let any of them compute from a realm index. Reconciling the item table with the actor table is an open decision needing its own ADR (ADR 0050).
- **Adding a scale is a reviewed change**, not a convenience. A new power-shaped number needs an ADR, not a second curve.

## Institutions: clan, sect, nation
Three tiers, one vocabulary, and each answers a question no other answers (ADR 0083).
- **clan is born to** (ADR 0064) — a lineage across generations. **sect is sworn to** — the institution you join; it teaches and holds a roster. **nation is lived under** — a polity whose offices may be vacant. They are **not** nested: a clan exists without a sect, and `nation → sect` exists because offices are filled from sects, not because a nation contains them.
- **One claim shape in `core/institution_claim.gd`**: `position` (discrete, authored), `standing` (continuous, earned, can fall), `obligation` (open terms). The three tiers must never grow a second copy — that is the ADR 0066 failure mode. It is in `core/` rather than `contracts/` because it must be an `@export` field on `.tres` Resources, and `core` is a layer, so the facade rule never applied to it.
- **Position and standing never derive from each other** (ADR 0064's split, carried forward). `SectApi.promote` writes one, `SectApi.move_standing` writes the other, and neither reads the other. That gap is the politics layer.
- **An institution grants recognition and access, never power** (ADR 0084). The only stat surface is `InstitutionClaim.standing_percent()`, a bounded PERCENT capped by `STANDING_PERCENT_CAP`. Never a FLAT, never `set_base`, never a second stat composer, never a new `StatProvider`. `tools arch` cannot see a method that does not exist, so `tests/modules/sect/test_sect_no_power.gd` pins it structurally.
- **Reputation is not standing.** `social` (ADR 0091) already owns `regard` per institution and a `trust` axis that gates teaching. Sect membership *moves* `regard` through `SocialApi.apply_cause`; it never keeps a second copy.
- **A conflict is a declaration of sides and a prize, never a formula** (ADR 0085). `nation` owns no damage arithmetic, no `rng`, and no `army_strength`. Verdicts arrive from combat; the political layer counts them and pays the prize declared at declaration.
- **The three-state vocabulary is load-bearing for every screen** (ADR 0083): `{}` = does not exist; `"vacant": true` = exists and its value is absent; `{"ok": false, "reason": R}` = refused. A vacancy is never `0` and never a hidden row.
- **The `nation → sect` edge is enforced by review, not by the gate.** `BARE_REF_UNITS` excludes `modules/*`, so a bare `SectApi` reference from `modules/nation/` reports zero violations and a code-only cycle is invisible to `_find_cycle`. Reach `sect` only through a `preload` of its facade and spell every other identifier as a plain id.
- **No institution owns a clock.** Nothing in `sect/` or `nation/` may read `Time.get_ticks*`, declare `_process`, or call `get_tree()`; every accrual takes an explicit `periods` from a caller that owns time (DEF-0111).

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
2. UI builds only against that contract, never module internals, and both stay green independently.

Where a panel needs something the facade does not expose, add it to the facade — do not widen `ui/` to reach internals.

## SOLID workflow
Contract-first; the composition root is the only place that knows concrete types.
1. **D — invert dependencies.** Define or extend the interface in `contracts/` before behavior. Modules depend on that interface, never on a sibling's concrete script.
2. **I — keep interfaces small.** `api.gd` exposes only what other modules need; split rather than grow a god-facade.
3. **S — one responsibility.** A module answers one "why change". If a script needs "and", split a component out.
4. **O — extend, do not edit.** Add a module or component and wire it in `app/`; never put feature logic in `core/`. Changing a `contracts/` interface or `core/` behavior requires an ADR in the same change.
5. **L — substitutable implementations.** Any script implementing a `contracts/` interface must pass the same contract tests.

Loop: contract -> implementation -> app wiring -> contract test -> `tools check`. It is enforced by: `tools arch` for DIP/ISP (facade-only cross-module edges, no upward layer deps, a cap on the public surface of `api.gd`) and SRP (a warning past the line budget); an ADR in the same change for OCP (`core/`/`contracts/`); and contract tests under `game/tests/contracts/` for LSP.

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
- **Allowed docs** — `AGENTS.md`, `docs/adr/NNNN-*.md`, `docs/art-direction.md`, and the machine-readable `docs/deferred.jsonl` only. Do not add READMEs, design docs, status files, or notes; ask before creating any other Markdown.
- **Deferred work** — tracked in `docs/deferred.jsonl`, one JSON object per line with `id`, `area`, `title`, `status`, `source`, `reason`, `next`, `created`. Record deferrals there instead of prose TODOs. Use `uv run python -m tools deferred` (`report`/`search`/`add`/`done`/`validate`); `tools check` validates the file. When solved, set `status` to `done` and add a `resolved` date; keep the entry as the trace. Add `priority`/`depends_on` when useful. Never delete entries.
- **Caps** — `AGENTS.md` ≤ 200 lines; an ADR ≤ 1 page. Over budget means split or delete.
- **ADRs are immutable** once accepted: supersede with a new ADR, do not rewrite history.
- **Docs ship with code** in the same change; delete stale text rather than appending "updated" notes.

## Repo hygiene
- `.pi/` and `.remember/` are local agent state, not game code: leave them alone and keep them gitignored. `.agents/` and `skills-lock.json` are the opposite — committed shared skills (see Skill index).
- `.gitignore` at minimum: `game/.godot/`, `build/`, `.venv/`, `.ruff_cache/`, `.remember/`, `.pi/`, and any local `GODOT_BIN` config.
- CI (`.github/workflows/ci.yml`) is YAML and may only shell out to `uv sync` and `uv run python -m tools check` — no inline logic, no bat/ps1.
