# 0901 Loading screen owns the boot window

- Status: Accepted
- Date: 2026-10-07

## Context

Boot shows the workbench shell immediately: a 31-button nav strip over
whatever route opens first. It reads as a debug harness because it is one —
there is no title, no loading beat, no visual identity between process start
and the first screen. The boot menu (ADR route `boot`) fixed navigation but
kept the accounting feel: labels on gray, no art, no motion, no sense that a
game is starting.

## Decision

A `LoadingScreen` owns the boot window, in three layers:

1. **Wallpaper.** One 1280x720 landscape illustration in the shared gouache
   idiom (ink `#263A35`, antique gold `#C49A53`, upper-left light), generated
   through the map pipeline's ComfyUI entrypoint with `--preview-only` so the
   map index is never polluted, then installed by hand under
   `game/assets/loading/`. It is a backdrop painting, not a map asset: no
   footprint, no collision, no index row. Provenance (checkpoint, seed, prompt)
   is recorded here, not in the catalog.
2. **VFX.** One `canvas_item` shader (drifting mist bands + vignette +
   shimmer) over the wallpaper, plus one `GPUParticles2D` emitter for rising
   qi motes with a procedural radial texture. No particle art dependency: a
   generated dot would be a resolution-locked sprite for a resolution-free job.
3. **Honest progress.** The screen preloads every `ScreenRoutes` scene, one
   per step, through a `load_step() -> {done, loaded, total}` verb the root's
   single `_process` drives (ADR 0106: no second tick caller anywhere under
   `res://src`, so the screen owns no `_process` of its own). The bar fills
   from work actually done; on a fast disk it passes in a blink, which is
   correct — a progress bar that takes a fixed two seconds would be theater.
   Headless tests drive `load_step()` in a bounded `for` loop instead, so the
   contract holds where no frame is ever delivered.

When loading completes the screen navigates to the boot menu (save exists) or
arrival (fresh), like before. The wallpaper stays as the menu's backdrop, so
title and menu are one visual.

## Provenance (loading wallpaper)

- Source: `build/map-generated/mortal_greenwood_terrain_texture_base_surface-20261007-opaque-base-s0.png`
  (local ComfyUI, prompt_id `6bc53c25-f3d3-458a-9a7a-ff0b0ab93063`, seed
  `20261007`, 1024px, `--preview-only`; map index untouched).
- Installed: `game/assets/loading/loading_wallpaper.png` (center 1024x576
  crop, LANCZOS to 1280x720). First candidate accepted, no retries: counter
  framing held (no tile look), no text/UI/watermark. One noted drift: the
  finish leans photographic rather than broad gouache planes; acceptable
  dimmed under mist, and recorded so a re-roll knows what to fix.
- Layered composition (user decision): one figure, one sword, one plate,
  composited in the loading screen instead of one baked painting.
  - Plate: seed `20261024` (figure-free golden river valley; the `20261012`
    winner carried its own fairy, which doubled the figure).
  - Fairy: seed `20261021` figure through `rembg.py` to
    `game/assets/loading/fairy.png` (1024px, bottom-center pivot). Clean
    isolation; the sword blended into the bright backing and was eaten, which
    is why the sword is its own layer.
  - Sword: blade cropped from seed `20261023` (x120–480, y550–1024), through
    `rembg.py` to `game/assets/loading/sword.png` (512px). Blade-only is
    exactly what shows: the hilt hides behind her robe in composition.
  - White-void retries (`20261022`, `20261023`) both dioramaed: the map
    tool's tile framing is immovable for this record. Brightness must come
    from checkpoint/LoRA choice, not adjectives (same lesson as the batch).
- License/provenance: generated locally; source checkpoint license terms
  apply (same as map art). No index row: backdrop paintings carry no
  footprint and must never gain one.

## Consequences

- `res://assets/loading/` is a new art directory outside the map index. Map
  tooling (`report`, `audit`, `compose`) never sees it; that exclusion is
  deliberate, and anything that scans "all game art" must learn it.
- The root's `_process` gains a loading branch. It calls no status tick and
  reads no clock; the one-tick-caller rule is about game time, and this is
  scene loading. The distinction is stated at the call site.
- First navigation after boot is instant, because every route scene is already
  loaded. That is the functional half of this ADR; the wallpaper is the other.
- What this ADR does NOT do: fake progress, a progress percentage with no
  denominator, a second `_process` under `src/ui/`, or map-index rows for
  non-map art.
