# Foundation gaps — build handoff

Measured 2026-10-03 against commit `0bc65db8`. Every line below was verified by
running a command or reading a named file. Claims marked **WRONG** are ones a survey
agent got wrong, so you do not repeat them.

## Rule for this task

`AGENTS.md` defines done as: `tools check` passes, behaviour has tests, and a
boundary move gets an ADR. The repo's own harder standard is in `docs/backlog.jsonl`
(BL-0297): **a feature is done when it has a PRODUCTION CALLER** — something in
`game/src/app/`, `game/src/core/` or `game/src/ui/` calls it. A passing test is
not acceptance. `tools/check.py` says the same: "Content that no player can reach is
still a green suite."

## The two hard blockers

### B1. The game crashes on boot

```
uv run python -m tools run --headless --quit-after 120
# exit 0xC0000005 (access violation), two lines of output, no SCRIPT ERROR
```

Scripts now **load** cleanly (0 parse errors). The crash is after load, with no
message. Two earlier defects were live during this survey and appear fixed —
confirm rather than trust:

- `game/src/modules/sect/api.gd:746` could not resolve `SectReadModel` (parser error)
- `game/src/app/institution_resolver.gd:98` called `NationApi.act()`, which does
  not exist on the facade (verified: 0 definitions of `static func act` in
  `game/src/modules/nation/api.gd`)

**This is your first task.** Nothing else can be verified while the entry scene
does not run. `tools boot` exceeded 300 s on the last attempt, so it may be the
same fault rather than a slow probe.

### B2. The test process crashes after reporting

```
uv run python -m tools test --suite tests/ui
# Results: 2888 passed, 15 failed (31 suite(s))  then exit 0xC0000005
```

The results line prints, then the process dies in teardown. **The exit code is
therefore unreliable** — a run that reports 0 failures still fails CI. Read
`AGENTS.md` §"Logs, memory, and runaway loops": anything instantiated in a test
must be freed; `queue_free()` in `res://src` is banned because the headless runner
drives `_ready()` from `_initialize()` and a deferred free never runs.

**Where to look, and why the guards do not help you.** `test_no_deferred_free.gd`
(`AGENTS.md:50`) scans `res://src` for `queue_free()` — it catches a *deferred* free,
not a *missing* one. A node that is instantiated and never freed passes it cleanly.
`tests/arch_rules` is green at 3029 passed, which is consistent with exactly that:
the leak is an absent `free()`, which no source scan can see. Three power-cycles in
this repo came from that class of defect (67 GB resident), so treat it as the
prime suspect rather than a long tail.

## Failing suites (15)

| Suite | Fails | Sample |
|---|---|---|
| `tests/ui/test_character_creation.gd` | 9 | screen not routed |
| `tests/ui/test_ui_conventions.gd` | 5 | convention guards |
| `tests/ui/test_world_map_screen.gd` | 1 | — |

`tests/arch_rules` is green (3029 passed), so the runaway/leak guards do not fire.
That is itself informative: whatever leaks is not in a pattern they scan.

## Then, in order

### F1. Make the build shippable

- **No `game/export_presets.cfg`** and `tools/export.py:17` builds
  `--export-release <preset>` with **no output path**, so the command is malformed
  even once presets exist. `export` is not in `tools check`, so it has never run.
- **CI cannot pass**: `.github/workflows/ci.yml` installs `uv` and runs
  `tools check`, but the three engine-dependent steps (guards, `boot`, `test`)
  resolve Godot via `GODOT_BIN`, the gitignored `.godot-bin`, or `PATH`. None is
  present on `ubuntu-latest`.
- **`project.godot` has no `[display]` section** — no window size, no stretch
  mode. For an anchors-and-containers UI that is unspecified behaviour.

### F2. Wire what already exists

Each of these is written and tested; only a caller is missing. Verify each claim
before acting — the code moves under you.

| System | Evidence |
|---|---|
| `SaveApi` — 167 lines, 8 public methods (`persist`, `restore`, `publish_world`, `world_state`…) | **0 callers** in `app/` or `ui/` |
| `PlayerAdapter extends CharacterBody2D`, holds a `Camera2D` | never instantiated |
| `WorldStage`, `DomainBoot`, `EconomyBoot`, `CharacterCreation` | **0 `.new()` calls** |
| `CharacterCreation` screen | **0 hits** in `app/screen_routes.gd` |
| `WorldMapScreen.location_selected` signal | no listener |

> **WRONG in the survey:** `SaveApi` was described as "a 6-line empty stub" and the
> 2D layer as "absent from the codebase". Both exist. The gap is wiring, not code.

`SaveApi` is the highest-value one: with no production caller, a player loses
realm, meridians, acupoints, sea, loot, quests and events on quit — only
`ItemsApi.serialize` is written today.

### F3. Fill the empty authoring trees

- `game/data/traits/` — **`.gitkeep` only** (verified 1 entry). Traits are the
  mandatory input for personality, needs, reputation and bloodlines.
- `game/data/elements/` — **`.gitkeep` only**. Five-element counters are hardcoded
  in `elements/default_elements.gd:10-17` rather than authored.

### F4. Add the missing mechanics

- **Gathering & Production is entirely absent.** Verified: no `gather`, `mine`,
  `harvest`, `forage` or `hunt` function exists anywhere in `game/src/`. Crafting
  needs inputs and nothing in production produces raw materials.
- **No `age`/`lifespan` on `Actor`** — verified 0 matches in `core/actor.gd`.
  Blocks Aging & Lifespan, Lifespan Cultivation, NPC Life Simulation and
  generational succession.
- **No decision-maker.** `WorldPulse` and `BeatDirector` exist and are wired
  (`item_workbench_app.gd:77` constructs the director), but nothing consumes a beat
  to *decide* anything. This is why 17 of 37 modules are authored-not-wired:
  quests are never accepted, NPCs never act, children are never born.

## Context you will need

- 37 modules under `game/src/modules/`, each with an `api.gd` facade capped at
  **12 public methods** (`tools/arch/rules.py`). Reaching the cap means split the
  facade, not append to it.
- `ui/` may only reference a module through its facade; `tools arch` enforces
  this by scanning **bare class references**, so any module type named from `ui/`
  fails the gate. Hold recipes as plain dictionaries for the same reason.
- 16 routed screens; 6 are read-only boards over a 12-method facade (`sect`,
  `nation`, `destiny`, `set_bonus`, `world`, `technique_codex`).
- The three cultivation paths and the pill chain work end to end.
- ~14,500 authored `.tres` files across 28 trees. **Every tree has a code
  consumer** — nothing is orphaned at the data layer. The failure is one level up:
  catalogs load and no player verb reaches them.

## Verify before you claim

```
uv run python -m tools run --headless --quit-after 120   # must exit 0
uv run python -m tools test --suite tests/ui             # must exit 0, not just report
uv run python -m tools arch
uv run python -m tools check
```

Report the **exit codes**, not just the "Results:" line — that distinction is the
whole of B1 and B2.
