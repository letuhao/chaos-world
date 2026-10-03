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
