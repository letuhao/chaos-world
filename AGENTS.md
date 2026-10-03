# AGENTS.md

Chaos World is a Godot 4 **action RPG with cultivation**. Core loop: **combat → hunting → cultivate → breakthrough**; every other feature is added later. The repo is a git repository with a Python tool bundle (`tools/`), a Godot project (`game/`), content under `game/data/`, and a headless GDScript test suite. Everything below is the intended standard. Follow it when scaffolding, and update this file whenever a decision changes.

## Non-negotiable rules
- **Python-only tooling.** Every script, task, and automation entrypoint is a Python module run through `uv`. Do **not** add `.bat`, `.ps1`, `.cmd`, or `.sh` files, and never document a shell one-liner as the supported path. **Godot 4.7.x, standard (GDScript) build** — not the .NET/C# build; do not introduce C#. **All commands go through `uv run python -m tools <task>`:** never invoke Godot, `gdformat`, `gdlint`, or the test addon directly from docs or CI.
- **Boundary truth is code, not prose:** `tools/arch/rules.py` (policy) and `tools/arch/registry.json` (machine-managed state). The checker is authoritative.
- **English, lean docs.** Every document is in English and as short as it can be — see Documentation rules. **No sexual content:** succubus, dual-cultivation, and fertility are pure gameplay mechanics — never write sexual, explicit, or suggestive prose, descriptions, names, or assets. Keep everything clinical and mechanical.

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
Item art uses reusable PNG and SVG families indexed by `game/assets/asset-index.jsonl`; style rules live in `docs/art-direction.md`. Because the project is rooted at `game/`, Godot never scans `tools/` or `docs/` — do not add `.gdignore` for them.

## Commands
Prereqs: `uv` (https://docs.astral.sh/uv/) and a Godot 4.7.x binary. All of these are `uv run python -m tools <task>`.
- `uv sync` — create/refresh `.venv` from `pyproject.toml` + `uv.lock`. `fmt` — format GDScript + Python (`--check` to verify only). `lint` — static lint. `arch` — enforce module boundaries + SOLID structure (facade surface, line budget).
- `test` — run the Godot test suite headless; `test --suite <substring>` runs only matching suites. **Use this while iterating.**
- `check` — full gate: `fmt --check -> lint -> arch -> deferred validate -> backlog validate -> data audit -> test`. Run before every commit; CI runs exactly this.
- `run` — launch the game. `export <preset>` — export a build.
- `ui screens|drive` — drive a screen headlessly and print its state as JSON (`--drive --screen <scene> --path body|qi|mind --cmd <verb>`, repeatable). An agent inspects and plays the UI without a display.
- `new_module <name>` — scaffold a module and register it in `tools/arch/registry.json`. `new_adr "<title>"` — create the next numbered ADR in `docs/adr/`.
- `deferred report|search|add|update|done|validate` — maintain `docs/deferred.jsonl`.
- `incident report|add|close|search|validate` — maintain `docs/incidents.jsonl` (what went wrong, and the guard that now stops it).
- `data report|audit` — inspect and audit content under `game/data/` (acquisition gaps). `data distribution` — audit item characteristic distribution/diversity; read-only, non-gating by default, `--fail-on warn|error` to gate. Run before planning a generation wave.
- `cultivation seed|seed-systems|validate|report` — write missing realm-seed content (never overwrites authored files), audit the generation contract, or print the deterministic body-ladder balance report.

**Godot binary is not on `PATH`.** `tools/godot.py` resolves it from `GODOT_BIN`, else the gitignored `.godot-bin` file, else `PATH`, and fails loudly if none resolve. Do not hardcode machine paths anywhere else. **Never invoke the Godot binary directly:** go through `tools/godot.py` (`tools test`, `run`, `ui`, `export`), which passes `--log-file build/godot.log` and enforces a 900 s ceiling — bypassing it opts you into the hazard below. **Do not rely on bare `python`:** system Python here is inconsistent (3.13 on `PATH`, a broken `py` launcher, 3.10 as `python3`). Always use `uv run`, which honors `.python-version`/`uv.lock`.

## Logs, memory, and runaway loops: hard disk- and machine-safety rules
Three ceilings exist because three different runaway shapes exist. `tools/godot.py` enforces all of them; none is optional and none may be raised to stop a failure firing.

**1. Log (disk).** Godot's own log defaults to `%APPDATA%/Godot/app_userdata/<project>/logs/`, rotating at **2 GB per file with no total ceiling** (`max_log_files=5`) — ~10 GB per incident, re-created every run, on the user's **C:** drive. A mind_cultivation test once entered an unbounded retry loop, `push_error` fired every iteration, and ~10 GB was written before anyone noticed.
- **A loop that spams is a bug to fix, never output to preserve.** Do not "let it log" a failure you have not read.
- `debug/file_logging/enable_file_logging` in `project.godot` **does not disable it** — the engine reads the `.pc` variant, which stays `true`. Only `--log-file` redirects the sink, which is why `tools/godot.py` owns it. Do not "fix" this by editing `project.godot`. A persisted log goes in `build/` (gitignored) — never the user profile.

**2. Memory (RAM).** A `tests/ui` run once reached **67 GB resident / 105 GB commit at ~0.3 GB/s** and the machine had to be power-cycled. The clock and disk ceilings both measure *output*, so an allocating loop that prints nothing passes both — that is the gap `RAM_CEILING_BYTES` closes.
- **A loop that allocates without releasing is the same defect as a loop that spams.** Leaking a `Node`, `Resource` or `String` per iteration exhausts RAM exactly as fast as logging fills the SSD, and is just as invisible.
- **Anything instantiated in a test must be freed.** `add_child`/`instantiate()` without a matching `free()` is a leak, not a fixture, and the runner shares one process across every suite. Track what a helper mints in a `_born` array and free it from `teardown()` — call sites are interleaved, so freeing at each one is skipped by any test that returns early. `SeamHarness.teardown()` is idempotent and safe after an abort — call it.
- **`queue_free()` in `res://src` is banned: use `free()`.** The headless runner drives every test from `SceneTree._initialize()`, which returns before the first frame, so a deferred free *never runs* under `tools test`. Detach the node (`remove_child`) first, then `free()`. Enforced by `tests/arch_rules/test_no_deferred_free.gd`; this one deferral leaked a screen subtree per navigation and a map graph per refresh — the 67 GB.
- **A loop that tests a size it is itself growing is infinite.** `while count < board.size() + 4` where the body inserts one key per pass never terminates: `size` rises in lockstep with `count`. Snapshot the bound **before** the loop. This is the loop that reached 67 GB. A data-derived row count is not a fixed count either: `while rows.size() < needed` passes the arch rule only because `needed` looks fixed to a scan, but when it comes from a snapshot (`keys.size()`, `views.size()`, an office board) it is bounded by nothing, and each row is a live `Control` parented into the tree. Clamp through `RowBudget.cap()` — one shared number, because six independently-chosen caps would drift and the one that matters is the smallest.
- **Every `.connect()` is guarded by `is_connected()`.** An unguarded one is one handler per call, so a reused or cached screen accumulates connections and every press fires N times. Safe *only* by accident of fresh instantiation is not safe.
- **A recursive walk needs a depth cap, and `while` scanning cannot see it.** A recursive call is not a `while`, so `test_no_unbounded_wait.gd` passes a `_scan` that recurses without limit; a junction pointing at an ancestor never returns. All content loading goes through `core/ContentScan`, which caps depth at `MAX_DEPTH`. Do not grow a local `_scan`.

**3. Infinite loop (time).** A feature that cannot work must fail out loud, not spin. If an exit condition cannot be met, never leave it running and never bound it by a huge iteration count — that just burns disk or RAM more slowly. Make it fail.
- **Every loop gets a real guard.** A `while` on game state needs a bounded, *small* cap that names the condition which failed to converge. Never a bare unbounded `while`.
- **That rule is enforced, not just written.** `tests/arch_rules/test_no_unbounded_wait.gd` fails the build on any `while` in `res://src` **or `res://tests`** it cannot show terminating: it moves a counter it reads, is the `DirAccess` terminator, drains a container it tests, fills one toward a fixed count with an *unconditional* append, or breaks/returns. Tests are scanned because the loop that filled the disk was a test's. Recursion is the same hazard a `while` scan cannot see (A holds B, B holds A), so it needs its own depth cap. Do not add an exception because a loop "looks fine" — that judgement shipped the 1 GB/s loop.
- **Never re-run a loop body that asserts.** `TestCase` (`game/tests/framework.gd`) kills the process via `OS.crash` past `MAX_FAILURES` / `MAX_ASSERTIONS`; that is the intended backstop, not a number to raise until it stops firing.
- **Mark a mutation with a token the stranded-mutation guard actually fires on.** `test_no_stranded_mutation.gd` matches only shapes rooted at `MUTATION` (`MUTATION-x`, `MUTATION PROBE`, `# MUTATION`, `// MUTATION`, `XXX MUTAT`), and it is deliberately case-sensitive so the tree's 172 lines of prose about mutation survive. `MUTANT-B1` matches **none** of them, so a reasonable marker leaves the guard blind. Write `MUTATION-<id>`. A mutation window is also only safe while nobody commits: another agent's commit captures the probe into history, which the working-tree guard cannot see (INC-0007). Prefer mutating a throwaway copy.
- **`tools/godot.py` is the ONLY way to start the engine (INC-0004, INC-0005).** The RAM, log and clock ceilings live in that launcher, so invoking the Godot binary by path — a hand-typed command, a probe script, anything that resolves `GODOT_BIN` itself — gets **no ceiling at all**. That is not a faster way to run a test, it is an unguarded one: a silent allocating loop produces no measurable output, so it passes every ceiling not measured in the process. Both the 73 GB run and the PC reset came from exactly this shape. Never reach for the binary to "see the error the tool swallowed" — read `build/logs/`, or raise it as a `DEF`/`INC` entry.

**Never reproduce a runaway to diagnose it.** A timeout, a `=== FATAL ===` crash, or a ceiling breach already names the cause and points at the log; a manual repro spends the user's disk, RAM and time to re-learn what the ceiling just reported, and has twice forced a power-cycle. Read the log, read the code, fix the loop. Fix first, verify by the guard not firing — that is the whole test, not an A/B experiment. If a repro is genuinely unavoidable, say so and get the user's go-ahead first.

**Record what happened, not just what to do.** `docs/incidents.jsonl` holds every hazard that actually occurred — `disk` (filled C:), `memory` (67 GB, two power-cycles), `loop` (never terminated), `git` (a bulk revert destroyed an agent's uncommitted work). `uv run python -m tools incident report|add|close|search|validate`. A rule here that traces to an incident is durable; a rule with no incident behind it is somebody's guess. **Never delete an entry** — set `status` and record the `guard`, because the trace is the value. `tools incident validate` runs in `tools check` and **fails** any entry that claims to be handled without naming what handles it, because a hazard we hit and did not guard is a hazard waiting to repeat.

## Agent workflow
Optimize for small verifiable steps. The repo is the source of truth; chat history is not.
1. **Orient cheaply.** Read this file, then only the target module's `api.gd` and the files you will touch. Do not read the whole repo — take evidence from `tools arch` / `tools test` output instead.
2. **State the goal in one sentence** in your reply. If it needs a design doc to explain, split it.
3. **Ship one vertical slice**, then run `uv run python -m tools check`. Fix failures before continuing.
4. **Test what you changed, not everything.** Use `tools test --suite <substring>` while building; run the full suite only to release a finished module or when a critical bug makes the game fail to build or load. A full run mid-build wastes minutes and reports other agents' in-flight breakage as if it were yours.
   - **Re-measure a tracked finding before dispatching against it** (BL-0619). Nothing fails when a tracked finding becomes untrue, so a list carried across turns decays silently — 14+ of the 2026-10-03 audit's 17 entries were already fixed, and each would have rebuilt working code. Verify with `rg`/a suite run, never from the entry's own text.
   - **A green guard is not a tested guard** (INC-0016). Every validator in `tools/` is unreachable from the GDScript suite, so `tools selftest run` asserts each still goes **RED**. Adding a validator there means adding its red path; "it passes on today's tree" is what `check` already does and proves nothing.
5. **Record durable decisions only.** An architectural choice future agents could get wrong goes in a one-page `docs/adr/NNNN-<slug>.md`. Everything else is written nowhere.
6. **Touch this file only when a rule changes.** Never add changelogs, status, or plan sections.
7. **Commit your own work; committing is part of the task, not a favour.** Uncommitted work is **unrecoverable** — there is no reflog entry for a file that was never staged. Commit at the end of each vertical slice, before starting the next.
   - Stage **only your own paths**: `git add <path> <path>`, never `git add -A`, `git add .`, `git commit -a`, `git commit -am` or `git add -u`. A blanket stage sweeps every modified tracked path, swallows a concurrent agent's in-flight edits, and makes them unrecoverable too. Before committing, `git status --short` and confirm every staged path is one you edited; if something foreign appears, unstage it (`git restore --staged <path>`) rather than committing it.
   - **A narrow pathspec is necessary and NOT sufficient** (INC-0011). `git commit --only <path>` commits that path's **entire working-tree state**, not a hunk — so editing 2 lines of a file another agent left dirty commits their ~157 too. Before committing a path, `git diff --stat -- <path>`: a count far larger than your edit means someone else's uncommitted work rode in.
   - **Never remove `.git/index.lock`** (BL-0424). With ~20 concurrent agents a lock that reappears within a minute belongs to a live process; deleting it lets two git processes write one index. Check for live git processes and whether HEAD is moving, then wait and retry. Leave the work uncommitted rather than force it: the next committer recovers it, a corrupted index does not.
8. **The working tree is shared with live agents.** Never `git checkout`, `git restore`, `git revert`, or `git stash` a path you do not own — a concurrent agent's edits and this file itself are not yours to roll back. Bulk-reverting "my" files has twice destroyed another agent's finished work. Undo your own mistake by hand, path by path.
   - `git checkout .` / `git restore .` / `git stash` with no pathspec are **forbidden outright**: they are not "reverting my files", they are reverting everyone's. Same for `git push --force` and `git reset --hard` on a shared branch — there is no undo once another agent has pulled.
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
| Genre anchor | `rpg` — stats, leveling, inventory, combat, quests, saves. Cultivate/breakthrough build on it |
| Combat | `game-ai`, `ai-behavior-trees-utility-ai`, `game-feel`, `camera-systems`, `input-systems`, `physics-tuning`. Hunting adds `level-design`, `procedural-gen` + the movement/world skill |
| Breakthrough UI | `game-ui-ux`, `godot-ui-control` |
| Cross-cutting | `game-ui-ux`, `audio-design`, `performance-optimization`, `create-game-assets`; `save-systems` when state persists |
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
Rules enforced by `tools/arch` (`tools/arch/rules.py`):
- `contracts` and `core` must never reference `modules/` or `app/`; nothing may reference `app/` except `app/`.
- A module may reference another module **only** through its facade `game/src/modules/<x>/api.gd`; touching any other file in that module is a violation.
- `ui/` is a **pure consumer**: same facade-only rule, but only for the modules in `rules.UI_MODULES`, and it may never reference `app/`.
- Module dependency cycles are forbidden; `res://` scene/resource references follow the same rules as script references. GDScript must never import from `tools/`.
- The shared actor base (`core/actor.gd` + `core/actor_stats.gd`) is the single source of stats for all actors — ADR 0001.

Design principles to apply:
- **Composition over inheritance.** Prefer child nodes/scenes as components over deep `extends` chains.
- **Dependency inversion.** Modules depend on `contracts` interfaces, not concrete siblings; `app/` injects implementations.
- **Event-driven decoupling.** Cross-module communication uses typed signals/events defined in `contracts`, not direct node lookups.
- **Minimal autoloads.** Keep them to documented infrastructure declared in `game/project.godot`, never feature logic. No cross-module `get_node("/root/...")`.
- One module = one reason to change. If two modules need each other's internals, the boundary is wrong: move the shared part to `contracts`/`core`.

## Realm scale: a magnitude and a rate, never one number
There is no shared power curve. A realm's strength is authored data and lives in `core/realm_power_table.tres`, one multiplier per realm **keyed by realm id**, R1 at 1.0. Keyed by id, never by position: an inserted realm would silently shift every realm below it.
- **A magnitude and a rate are different kinds of number.** A magnitude answers "how strong is a thing from this realm"; a rate answers "what is one unit of this realm's training worth". A rate must never track a magnitude — reading a shared exponential as a gain is what once made a single breakthrough worth more than everything else combined.
- **Magnitudes** are owned where they belong. `RealmScaling` (core) scales the shared combat stats by `realm.power`; each path's own magnitude is authored on its own seed (`integrity_maximum`, `sea_capacity`, …) and applied once. Do not scale the same realm twice.
- **Rates** are ONE shared curve in `core/realm_rate.gd` (`RealmRate`): `factor(realm_id) = RATE_STEP^ordinal`, bounded by construction — `RATE_STEP^29` is under 2x, a gain and never a magnitude. `RATE_STEP` is authored in exactly one place, that file, and all three paths call `RealmRate.factor` directly; the `*RealmProfile` copies are deleted, not aliased (ADR 0116). Retuning it is a one-line edit that cannot desynchronise a copy, because there is no second number. `tools arch` cannot see this (`BARE_REF_UNITS` excludes `modules/*`), so `tests/core/test_realm_rate.gd` reads source and fails if any cultivation module declares `const RATE_STEP`/`const NEUTRAL`, calls `pow(`, or names a `*RealmProfile` — a numerically-identical private copy stays green under every value assertion.
- **`RATE_STEP` is bounded by the AUTHORED work budget, not a typed-in constant.** It must stay at or below the smallest per-realm step in the three authored `progress_required` ladders, skipping the first transition (qi and mind author R1 and R2 equal, so the entry price has no predecessor). That ceiling is qi's `dao_ancestor → primordial_origin` at `2900/2800` ≈ 1.0357, and the test computes it from the seeds. The old `<= 1.05` was looser than the data and permitted a retune that inverted qi's deepest breakthrough.
- **Guard:** `uv run python -m tools realm_power check` runs in `tools check`. It asserts the table's shape — one entry per realm, R1 at 1.0, strictly rising, finite, readable — not the recipe that filled it, so the numbers stay hand-editable. `realm_power emit --force` rewrites the file.
- **Two more per-realm tables are deliberate, not drift.** `game/data/item_options/item_magnitude_scale.json` is item magnitudes (1.0 → 3.9x) and technique magnitudes are ~1.0 → ~2.77x geometric (ADR 0055) — an item is not an actor, and a technique bonus rides on top of both, so it stays two orders of magnitude below `realm_power_table.tres` (1.0 → 551x). Never derive any of the three from another, and never let any of them compute from a realm index. Reconciling the item table with the actor table is an open decision needing its own ADR (ADR 0050). Adding a scale at all is a reviewed change: a new power-shaped number needs an ADR, not a second curve.

## Institutions: clan, sect, nation
Three tiers, one vocabulary, and each answers a question no other answers (ADR 0083).
- **clan is born to** (ADR 0064) — a lineage across generations. **sect is sworn to** — the institution you join; it teaches and holds a roster. **nation is lived under** — a polity whose offices may be vacant. They are **not** nested: a clan exists without a sect, and `nation → sect` exists because offices are filled from sects, not because a nation contains them.
- **One claim shape in `core/institution_claim.gd`**: `position` (discrete, authored), `standing` (continuous, earned, can fall), `obligation` (open terms). The three tiers must never grow a second copy — that is the ADR 0066 failure mode. It is in `core/` rather than `contracts/` because it must be an `@export` field on `.tres` Resources, and `core` is a layer, so the facade rule never applied to it. **Position and standing never derive from each other** (ADR 0064's split, carried forward): `SectApi.promote` writes one, `SectApi.move_standing` writes the other, and neither reads the other. That gap is the politics layer.
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
- **No `@onready` in `ui/`** — resolve nodes in `_bind_nodes()` via `get_node_or_null("%X")`; headless tests drive panels with no scene tree. No autoload holds feature UI.
- **No number formatting in a screen** — screens pass raw values to a panel; the panel owns `%d/%d`, decimals and widths. Step amounts live in the facade.
- **Focus** — implement the `ScreenStack` hooks (`focus_initial`, `on_screen_shown`, `on_screen_hidden`, `on_stack_input`), never `grab_focus()` in `_ready()`.
- **Testable contract** — every screen/panel exposes `summary() -> Dictionary`: primitives only, `{}` when no actor, child summaries nested under the child's key. Tests assert that, not pixels.

`tools arch` enforces the facade rule for `ui/` by scanning bare class references, so panels call the facade by name with no `preload` ceremony. Note `items` and `body_cultivation` are at the 12-method facade cap (`rules.MAX_FACADE_PUBLIC_METHODS`) — a new UI need there means splitting the facade, not growing it.

**Split dev cycle** — gameplay and UI can be built in parallel: (1) gameplay publishes a facade method or `preview() -> Dictionary` answering "what is true now?"; (2) UI builds only against that contract, never module internals, and both stay green independently. Where a panel needs something the facade does not expose, add it to the facade — do not widen `ui/` to reach internals.

## SOLID workflow
Contract-first; the composition root is the only place that knows concrete types.
- **D — invert dependencies.** Define or extend the interface in `contracts/` before behavior. Modules depend on that interface, never on a sibling's concrete script. **I — keep interfaces small:** `api.gd` exposes only what other modules need; split rather than grow a god-facade.
- **S — one responsibility.** A module answers one "why change". If a script needs "and", split a component out.
- **O — extend, do not edit.** Add a module or component and wire it in `app/`; never put feature logic in `core/`. Changing a `contracts/` interface or `core/` behavior requires an ADR in the same change.
- **L — substitutable implementations.** Any script implementing a `contracts/` interface must pass the same contract tests.

Loop: contract -> implementation -> app wiring -> contract test -> `tools check`. Enforced by: `tools arch` for DIP/ISP (facade-only cross-module edges, no upward layer deps, `MAX_FACADE_PUBLIC_METHODS` on `api.gd`) and SRP (a warning past `LINE_BUDGET`); an ADR in the same change for OCP (`core/`/`contracts/`); contract tests under `game/tests/contracts/` for LSP.

## Adding or changing a module
1. Run `uv run python -m tools new_module <name>` (or create `game/src/modules/<name>/` with an `api.gd` facade), then set its allowed dependencies in `tools/arch/registry.json` (written by `new_module`; never edit Python for this) and run `tools arch`.
2. Add tests under `game/tests/modules/<name>/`, then record the decision with `uv run python -m tools new_adr "<title>"`.
Changing a boundary rule is an architecture change: update the rule, the ADR, and this file together — never weaken a rule just to make code pass.

## Godot conventions
- Follow the official GDScript style guide. Files/folders `snake_case`; `class_name` and node names `PascalCase`; signals `snake_case` past tense (`health_depleted`); constants `CONSTANT_CASE`; private members `_leading_underscore`.
- A script file is `snake_case` and matches its scene's root node name; scenes are `PascalCase.tscn`. `class_name` is a global namespace — keep names unique and prefix with the module when ambiguous.
- `game/.godot/` is a generated import cache: never commit, edit, or read it for truth. Commit `*.import` and `*.uid` files.
- `.tscn`/`.tres` are text but editor-owned and order-sensitive: make minimal diffs, never regenerate whole scenes by hand, keep logic in scripts.
- Use `res://` paths (relative to `game/`) in code and resources, never OS-absolute paths.

## Python tooling conventions
- `tools/` is a real `uv` package. Add dependencies to `pyproject.toml` and commit `uv.lock`; no ad-hoc `pip install`.
- One module per task exposing `register(subparsers)` + `run(args)`; `tools/__main__.py` dispatches subcommands.
- Machine-managed state (module registry, ADR numbering) lives in structured files written by tools — never hand-edit it into docs or Python.
- Tools must be deterministic, non-interactive, and return non-zero on failure (CI depends on exit codes). Build output goes to a gitignored `build/`; never write generated artifacts into `game/src/`.

## Documentation rules
- **English only** — docs, code comments, commit messages, ADRs, issues, PR text.
- **Lean by default** — bullets, one fact per line, no tutorials, no restating code or config. If a line would not surprise a competent agent, delete it.
- **One source of truth** — precedence: code/config > `AGENTS.md` > ADRs. When docs disagree with code, code wins; fix the doc in the same change. Link, never duplicate.
- **Allowed docs** — `AGENTS.md`, `docs/adr/NNNN-*.md`, `docs/art-direction.md`, and the machine-readable `docs/deferred.jsonl` only. Do not add READMEs, design docs, status files, or notes; ask before creating any other Markdown.
- **Deferred work** — tracked in `docs/deferred.jsonl`, one JSON object per line with `id`, `area`, `title`, `status`, `source`, `reason`, `next`, `created`. Record deferrals there instead of prose TODOs. Use `uv run python -m tools deferred` (`report`/`search`/`add`/`update`/`done`/`validate`); `tools check` validates the file. When solved, set `status` to `done` and add a `resolved` date; keep the entry as the trace. Add `priority`/`depends_on` when useful. Never delete entries.
- **Caps** — `AGENTS.md` ≤ 200 lines; an ADR ≤ 1 page. Over budget means split or delete.
- **ADRs are immutable** once accepted: supersede with a new ADR, do not rewrite history. Docs ship with code in the same change; delete stale text rather than appending "updated" notes.

## Repo hygiene
- `.pi/` and `.remember/` are local agent state, not game code: leave them alone and keep them gitignored. `.agents/` and `skills-lock.json` are the opposite — committed shared skills (see Skill index).
- `.gitignore` at minimum: `game/.godot/`, `build/`, `.venv/`, `.ruff_cache/`, `.remember/`, `.pi/`, and any local `GODOT_BIN` config.
- CI (`.github/workflows/ci.yml`) is YAML and may only shell out to `uv sync` and `uv run python -m tools check` — no inline logic, no bat/ps1.
