# Spirit World: Celadon Faultlands

**Pack ID:** `spirit_world_celadon_faultlands`  
**Tier:** Spirit World, realms 10–18  
**Status:** production plan; no art generated

## Pack identity

The Celadon Faultlands are one dry basin in the Spirit World. An exposed leyline fractures the pale mineral floor; jade-green Qi pulses through the seams, a few stone chips hover just above them, and small streams run uphill into still pools. Bronze survey stakes and stone ward markers keep the traversable routes stable.

The signature read at game scale is **a quiet pale basin crossed by narrow celadon-lit fractures**. The region is ancient and natural, with a small amount of cultivation infrastructure built to study and contain the fault.

## Strict boundaries

- This is one regional pack, not a replacement taxonomy for the whole Spirit World.
- Keep the camera straight-down and orthographic, with grounded contact and the shared gouache finish.
- Keep walkable ground quiet. Reserve bright jade and cyan for fault seams, water, and a few resource details.
- Do not introduce bamboo forest, ghostwood, wetland, coastline, mountain skyline, cloud islands, or dense settlement imagery.
- Ley patterns are geological seams, not neon circuitry or UI-like runes.
- Plan only the 45 base assets in the manifest. Do not multiply every asset across all seasons, weather, damage, or realm states. Add a variant only when it has a clear gameplay or composition need.

## Initial asset plan

The pack uses the established nine map categories with five assets each (45 total). The first visual review set is:

1. `terrain_texture.base_surface` — opaque basin ground
2. `stone_and_ore.veinstone_boulder` — blocker and scale reference
3. `stone_and_ore.jade_seam_cluster` — resource-node reference
4. `travel_and_wayfinding.linewalker_bridge` — route reference
5. `landmark_and_environment_detail.convergence_basin` — landmark reference

Review these together in one overhead composition before generating the rest. Add the remaining base assets only after their scale, contrast, and material language match this set.

## Folder layout

- `categories.json` — the nine categories and their five planned archetypes
- `spirit_world_celadon_faultlands_pack.json` — self-contained planned asset records and intended runtime paths
- `data/<category>/` — per-asset JSON records initialized from the manifest and kept in sync by the pack tool
- `original/<category>/` — preserved high-resolution source renders
- `runtime/<category>/` — normalized PNGs at the dimensions recorded in the manifest

## Production contract

- Generate each source at 1024×1024 (or larger when the subject needs more detail) and keep that
  render unchanged in `original/<category>/<asset-name>--<sha256-prefix>.png`. Original PNGs stay
  gitignored but are excluded from Godot imports by the tracked `original/.gdignore`.
- Normalize a separate PNG into `runtime/<category>/<asset-name>.png` at the manifest's
  `canvas_px`. Never upscale a runtime sprite to recreate a source.
- The manifest's `path` is the runtime path. Each generated record's `source_path` points to the
  latest preserved original. `source_images` keeps every source path with dimensions, full SHA-256,
  provenance, and prompt, so a replacement never erases the previous render.
- Keep generated and runtime files mapped by the stable asset ID. Do not rename either file without
  updating the manifest and category data together.
- Each selected candidate needs visual review before it changes from `planned` to `generated`.
  A generated image is not approved until it has been checked at runtime size and in a composition.
- Matrix mapping is intentionally pending. Before gameplay placement, derive it from the normalized
  alpha and review coverage, blocked cells, ground contact, and anchor against the object. Do not
  infer collision from the sprite canvas or visual overhang.

## Selective living-world variants

The manifest plans only four state variants, each tied to one state axis: the jade seam's depleted
state, the veinroot bloom's harvested state, the pulse marker's active state, and the linewalker
bridge's damaged state. Other assets have no planned variants. Seasonal, weather, lighting, and
realm combinations are overlays or future scoped work, not multiplied sprite families.

## Pipeline boundary

The pack is isolated from the general map index. The current `assets map` manager accepts only its JSONL catalog and restricts managed environments to the registered world-map set; it does not audit or install this pack JSON. Keep the pack manifest as the source of truth and use the pack-local `faultlands` command. Matrix data is derived during install; visual review and generated art are still required before the pack is game-ready.

## Pack commands

```text
uv run python -m tools faultlands init-data
uv run python -m tools faultlands audit
uv run python -m tools faultlands install --asset-id <id> --source <source.png> --source-name "OpenAI image_gen" --generated-on <YYYY-MM-DD> --prompt-ref <generation-id> --prompt "<exact prompt>"
```

`install` refuses overwrites by default. Use `--replace-generated` only for an intentional
replacement; the previous source render remains archived under its own hash-based filename.
It normalizes an independent runtime PNG, derives alpha-based matrix measurements, and updates the
manifest plus the matching per-asset data file. Run `audit` after each reviewed generation.
