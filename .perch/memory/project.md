## Blender pipeline (blender/)

- `D:\Works\source\chaos-world\blender` is the Blender/VFX workspace, copied from `D:\Works\source\Keepverse\gk-assets` on 2026-10-03. It keeps gk-assets' two-part licence (CC BY 4.0 artwork, MIT tooling) and its attribution requirement.
- **No MCP.** The repo drives a live GUI Blender over a local HTTP bridge instead, because the user wants to watch the session work. `tools/blender_launch.py` opens Blender with `tools/blender_bridge.py` loaded; `tools/blender_cli.py` is the client. Env vars: `CHAOS_BRIDGE_PORT` (default 8765), `CHAOS_BRIDGE_HOST` (loopback), `CHAOS_BRIDGE_TOKEN` (optional auth). See `blender/LIVE_SESSION.md`.
- The bridge is a port of the key idea from `D:\Works\source\blender_mcp\addon\blender_mcp_addon\`: HTTP on a worker thread, bpy work executed only on the main thread via `bpy.app.timers` queue draining. Breaking that rule crashes the handler silently.
- Intended next work: character animation (walk, dodge, attack, jump, rotate) built in 3D and exported to 2.5D/2D for the 2D Godot game.

## Character generation (CharMorph)

- CharMorph installed 2026-10-03 at `%APPDATA%\Blender Foundation\Blender\5.1\scripts\addons\CharMorph` (git clone --recursive, 969 files / 2.27 GB, v0.4.0-3). Chosen over MB-Lab because MB-Lab is final at 1.8.1 and its dev moved to CharMorph.
- **Licence, verified from CharMorph/license.txt** — critical for this repo:
  - Code (all .py): GPL-3.
  - Character database / base meshes (mb_female, mb_male, etc.): **AGPL-3**. Models generated from them are derivative works and must be AGPL-3.
  - **2D renders are explicitly NOT derivative**: the licence says rendered 2D images/video are an original work, so exported sprite sheets can be licensed however you like, including closed-source commercial. This is exactly the chaos-world export path, so baked sprites are safe.
  - Prefer the CC-BY character sets if 3D models ever need to ship closed-source.
- Verified working: `bpy.ops.charmorph.import_char()` builds an 18,210-vertex humanoid; `bpy.ops.charmorph.rig()` with `ui.rig = "gaming"` builds a 159-bone metarig. Rigify then needs `bpy.ops.pose.rigify_generate()` (deform bones) — not yet completed via the bridge.
- Gotcha: the session must be in OBJECT mode before CharMorph operators poll; a failed call leaves it in POSE mode and every later operator fails with a misleading "context is incorrect".

## Character pipeline (built and verified)

The full character pipeline is built and verified (2026-10-03). Run in this order against the live session:
`blender_cli.py run tools/char_build.py` -> `char_walk.py` -> `char_render.py`. Output: `characters/chaos_humanoid_rigged.blend` (702-bone Rigify rig, 160 deform, action `chaos_walk_cycle` 24f@24fps) and `out/walk/walk_01..24.png`. Docs in `blender/CHARACTER_PIPELINE.md`.

Four hard-won gotchas, all now handled in code:
1. Rigify aborts with "No bone collections have UI buttons assigned" unless a bone collection has `rigify_ui_row > 0`. CharMorph's metarig ships with all rows at 0.
2. **Rigify does not transfer weights and nothing warns you.** CharMorph authors weights against metarig names (`thigh.L`); Rigify deforms via `DEF-thigh.L`. A clean, error-free generation leaves the mesh completely motionless. `transfer_weights()` mirrors each group onto its `DEF-` twin (47 groups, ~19k entries).
3. Blender 5.1 removed `VertexGroup.data`; read `vertex.groups`, and `add()` takes ONE scalar weight per call.
4. Blender 5.1 Actions are slotted: `action.fcurves` is gone; walk `action.layers[].strips[].channelbags[].fcurves`.

Also: always pass absolute render paths (Blender's CWD is not reliably the repo root), and a failed CharMorph operator leaves Blender in POSE mode so every later operator fails with a misleading "context is incorrect".

## Preview video encoding

Preview videos work end to end (2026-10-03). Two-step by design: `blender_cli.py run tools/char_preview.py` renders opaque frames to `out/walk_bg/bg_01..24.png`, then `powershell -File tools/char_preview.ps1` encodes `out/walk_preview.mp4` (1s, one cycle) and `out/walk_loop_x4.mp4` (4s, four cycles). Watch the 4s one: a jump once per second means the cycle does not loop. Use the transparent `out/walk/` sequence for compositing; the preview uses an opaque `#263A35` world because h.264 has no alpha.

ffmpeg 8.0 is at `C:\Users\NeneScarlet\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.0-full_build\bin\ffmpeg.exe`. Two traps: a `color=` filter source with no `-t`/frame limit never terminates (it burned 4300s CPU and wrote a 55 MB broken MP4 that stayed locked until the process was killed), and ffmpeg prints its banner to stderr which PowerShell treats as terminating under `$ErrorActionPreference = "Stop"`. Always probe with `ffprobe -count_frames` and compare against the expected frame count rather than trusting a successful write.

## Story module + content-authoring guidance (BL-0068)

### Story module + content-authoring guidance (BL-0068)

Built 2026-10-10. `game/src/modules/story/` (api.gd, story_def.gd, story_chapter_def.gd, story_gate.gd, story_catalog.gd). Verified: `tools test --suite story` = 77 passed / 0 failed (2 suites), `tools arch` exit 0, `gdlint` clean.

- Story owns NO state: no save schema, no write verbs. Chapters are derived from gates, so an unmet gate HIDES content and can never block play (that is BL-0068's "ignorable, coexists with sandbox").
- `StoryGate` adds exactly one verb, `quest_done`; `fact` delegates to `WorldFact`, fate verbs to `DestinyApi.gate`. Needed because `QuestApi.complete` writes NO fact, so a chapter cannot gate on a quest via `fact`.
- Chapters have no `grants` and no `on_enter` deliberately: the quest pays, and a second payer is this repo's recurring duplicated-rule defect.
- `progress()` walks `chapters` POSITIONALLY and stops at the first failing gate. Branching is only visible via `offered()`. `progress().done` is STORY-level (needs `is_ending` + that gate), not chapter-level.
- Guidance doc: `docs/content-definitions.md` (quest/event/story schemas, gate grammar, `.tres` rules, mod recipes, author checklist). Cross-linked from `docs/modding-guide.md`.
- Example content: `game/data/story/stories/the_long_account.tres` chains 4 shipped quests; locale sink `game/locale/story.tres` (10 en rows). `tools i18n check` went 242 -> 232 problems (my 10 cleared, zero net new).

Four gotchas learned the hard way, all now handled:
1. `as Array[Dictionary]` on a plain Array returns NULL in Godot 4, not a converted array. Copy row by row. Assigning an untyped Array to a typed export is a FATAL runtime error that aborts a builder before its `return`, so a fixture silently installs null and looks like "no catalog".
2. `expect_assertions(0)` does NOT exempt a test from the "asserted nothing" failure (`asserted <= 0` is checked first). A content test iterating shipped data must always assert, e.g. accumulate offenders then assert the list is empty.
3. Adding a module requires mirroring deps into `BASE_DEPS` in `game/src/modules/mods/module_registry.gd` (registry.json minus layer deps) or `tools arch` fails on drift.
4. A new content family needs its own `game/locale/<owner>.tres`; locale files load by directory scan so there is no list to append to, and `i18n extract` will not create the file.

Pre-existing failure NOT mine and NOT fixed: `test_module_registry.gd::test_seed_list_resolves_in_registry_json` expects 52, got 46. Six modules (`base_grant`, `clan_building`, `consumables`, `dialogue`, `foundation`, `worldmap`) are in HEAD's registry.json but were never in HEAD's BASE_DEPS. Needs their real deps, which I did not want to guess.

## Module registry / BASE_DEPS

## Module registry / BASE_DEPS

- `game/src/modules/mods/module_registry.gd` `BASE_DEPS` is a static mirror of `tools/arch/registry.json` with the implicit layer deps (`contracts`, `core`) stripped. `registry.json` is the source of truth, so a missing mirror entry is a mechanical fix, never a judgement call.
- **Absence is not emptiness.** `_is_satisfied()` answers from `BASE_DEPS`, so a module missing from the mirror is *not a base module to the registry*: a mod declaring a dep on it is refused with `unknown_dependency`. `order()` only walks `_registered`, so dangling base-to-base edges stay invisible. On 2026-10-10 six modules sat in that state (`base_grant`, `clan_building`, `consumables`, `dialogue`, `foundation`, `worldmap`) while nine base modules depended on `foundation`.
- `tools/arch/enforce.py:base_deps_drift()` used to compare `base_deps.get(name, set())` against registry deps, which conflates "absent" with "has no deps" and could never see the gap above. Fixed to check membership before comparing sets.
- `tools test` exits nonzero on ANY `SCRIPT ERROR` in the log even when every test passes. A half-saved file from another concurrent session therefore reddens unrelated suites. Read `Results: N passed, M failed` before concluding a failure is yours.
- This repo is worked on concurrently by other agents. `git stash` fails with "could not write index" (locked index) — do not touch git state to test causality. Instead toggle the edit with a file copy, or diff the implicated files against HEAD and check they are clean.
