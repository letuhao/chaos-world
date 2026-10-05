# Map asset data and geometry

Read this when inspecting catalog records, composing a kit, recovering sources, or working on collision metadata. [Map assets](../../../../tools/map_assets.py), [composition](../../../../tools/map_layout.py), and the [art direction](../../../../docs/art-direction.md) own the supported contract; this reference identifies decisions that pixel coverage cannot make.

## Catalog versus diagnostic output

`game/assets/map-asset-index.jsonl` is the supported asset catalog. The skill's scripts emit experimental analysis under `build/mapdata/`. These are separate schemas: do not paste diagnostic records into the catalog or treat authored semantics as implemented gameplay.

| Catalog field | Meaning and review |
| --- | --- |
| `id`, `archetype` | Asset identity and reusable role; select existing catalog IDs rather than inventing them during installation. |
| `environment`, `environment_name`, `environment_theme`, `world_tier` | Generation context. `map_theme check` compares the theme with the authored tool data. |
| `type`, `category`, `name` | Rendering role and catalog classification. Read accepted values from the CLI/code. |
| `path` | PNG under `res://assets/world_map/`; `res://` resolves inside `game/`. |
| `canvas_px` | Actual PNG dimensions, independent of its world footprint. |
| `footprint_cells` | Authored positive `[columns, rows]` in the 128 px reference unit. |
| `alpha` | `opaque` or `transparent`; use the declared mode, including for tiles. |
| `pivot` | `center` or `bottom_center`, not a numeric pixel coordinate. |
| `collision` | `none` or `solid`; a coarse role, not a detailed geometry mask. |
| `status` | `planned`, `generated`, or `approved`; approval also needs `approved_by`. |
| `source`, `license`, `generated_on`, `prompt_ref`, `prompt`, `reference_ids` | Verifiable origin, actual terms, ISO date, exact production prompt, and guidance references. |
| `negative_prompt`, `generation_settings` | Written by direct local generation: model, seed, sampling, LoRA and cutout settings. Manual installation does not populate them automatically. |
| `source_images` | Archived PNGs with repository-relative `path`, full `sha256`, `size_px`, and copied provenance. |

`assets map audit` checks identity/path uniqueness and containment, declared fields, generated files, dimensions, alpha mode, and provenance. It checks hashes and dimensions when `source_images` is present, but does not require that field on every legacy record. New installations archive their source; identify legacy provenance gaps explicitly. The audit cannot judge the camera, subject, cutout quality, or whether a gameplay system reads an asset.

## Editable grid composition

Choose actual generated/approved IDs from one environment. This example is a layout template; replace its placeholders and save it under `build/`:

```json
{
  "id": "environment_scale_review",
  "terrain_id": "<opaque-terrain-texture-id>",
  "grid": {"cell_px": 128, "columns": 8, "rows": 8},
  "show_grid": true,
  "placements": [
    {"asset_id": "<blocker-id>", "cell": [1, 1], "scale": 1.0, "overlap": "forbid"},
    {"asset_id": "<resource-node-id>", "cell": [5, 5], "scale": 1.0, "overlap": "allow"}
  ]
}
```

- Grid extent, optionally offset by `grid.origin_px`, must fit inside the terrain image; the example assumes 1024×1024 terrain.
- `cell` names the top-left footprint cell. The compositor fits the entire sprite canvas to `footprint_cells × grid.cell_px`, then applies placement scale and pivot alignment.
- `center` centers in the footprint; `bottom_center` aligns to its bottom edge. Visible pixels must fit the grid and canvas even after scaling.
- `overlap: forbid` reserves grid cells touched by alpha at least 128. `allow` permits intentional visual layering. Default overlap depends on the catalog's coarse `collision` role.
- The overlap mask counts canopy art and painted shadows too. It is not contact geometry. A canopy may overlap a path visually while its trunk still blocks navigation.
- Output: `build/map-compositions/<id>.png`. Preserve the JSON and independent sprites as editable layers; inspect the actual image before reporting acceptance.

## Storage and source identity

| Storage | Purpose |
| --- | --- |
| `build/map-generated/` | Local candidates; disposable generation output. |
| `art-source/map-originals/<environment>/<category>/` | Gitignored archive of untouched input PNG bytes. File names contain the asset ID with dots replaced by double underscores and a 16-character hash prefix. |
| `game/assets/world_map/<environment>/<category>/` | Normalized runtime PNGs; commit with generated import sidecars when present. |
| `game/assets/map-asset-index.jsonl` | Committed catalog and source mappings; no separate provenance ledger. |

Transparent installation crops at the tool's alpha crop threshold, keeps soft edges within that crop, fits inside a 16 px margin without enlarging the subject, and pads at the indexed pivot. Opaque installation requires full opacity and resizes to the indexed canvas. Both can lose source detail; PNG encoding itself is lossless.

`source_images[].sha256` hashes the archived bytes, not the normalized runtime sprite. Archival is byte-preserving for the supplied PNG; it does not guarantee embedded prompt/seed metadata, a pre-cutout source, or reproducible diffusion output across different model/runtime versions. Direct local generation normally supplies the workflow's final output, including background removal for transparent props.

Archive a known source for an existing generated/approved asset:

```text
uv run python -m tools assets map preserve-original --asset-id <catalog-id> --source "<known-original.png>"
```

`preserve-original` copies the record's provenance onto that source; verify the source belongs to the recorded run before using it. When a pre-cutout render exists, preserve it in addition to the installed cutout. Different hashes can coexist in `source_images`; distinguish them by inspected content and run evidence. Do not invent an unavailable original or substitute the runtime sprite as raw generation evidence.

For legacy assets without mapped originals:

```text
uv run python -m tools assets map recover-originals --source-root "<local-original-directory>"
```

Inspect `build/map-original-recovery.jsonl` and compare candidate images. The matcher uses a generated-date window and alpha profile, not exact content identity; `high_confidence` is a heuristic. Ambiguous or missing matches remain unresolved. Prefer `preserve-original` for a verified source. `recover-originals --apply` archives only high-confidence proposals; review all of those before applying because it has no asset-ID selection flag. Existing mappings are skipped.

Recovery does not remove backgrounds, resize sprites, or rebuild collision. Re-normalizing a verified source uses the normal installer and its replacement rules. Lost pre-cutout pixels cannot be recovered from an archived cutout. Local originals must be restored separately on a fresh checkout because catalog auditing verifies the files they reference.

## Geometry and gameplay review

Treat these as acceptance criteria for a requested collision workflow, not as a statement that the current game implements them:

- Rendering canvas, visual footprint, ground contact, and interaction reach are different quantities. Resolution changes must not silently change authored world size.
- Navigation, walk surfaces, projectiles, and sight need separately owned rules. A water obstacle can block walking while allowing projectiles; alpha alone cannot establish either behavior.
- `none` must stay nonblocking at every supported scale. Decorative density or a painted shadow cannot create a blocker.
- `ground_contact` describes a base/trunk distinct from canopy overhang. Validate a measurable contact region at the pivot; do not turn a sparse or failed cutout into a healthy blocker by silently imposing a minimum.
- `full_body` uses authored coverage thresholds; test the resulting collision against intended solid material.
- `core_ring` needs a traversable authored opening. A bounding rectangle around pillars cannot represent a doorway; preserve the opening in every consumer and scale profile.
- `walk_surface` must provide a connected usable surface and access from its surroundings. A coverage count alone does not prove a bridge is traversable.
- Check coordinate space, crop/padding offset, pivot and scale together. Inclusive cell rectangles `[x0,y0,x1,y1]` differ from half-open pixel rectangles `[left,top,right,bottom]`.
- Keep visual scale separate from contact scale. Use the consumer's authored rule; do not claim that a 32 px measurement implies 32 px runtime collision.
- After harvesting or destruction, verify the resolved replacement/state and resulting geometry; no stale blocker or disconnected interaction. These tests belong to the actual runtime owner.

For any requested runtime change, trace the responsible facade and consumer first. Test observable behavior: a unit can pass the arch but cannot enter a pillar, travel across the bridge from both ends, collide with the intended trunk under its canopy, and navigate after destruction/restoration. Only add the cases relevant to the requested feature.

## Bundled diagnostic scripts

These helpers retain the experimental geometry model. They are imported by `uv run python -m tools selftest run --suite map-geometry`, with synthetic images and isolated output under temporary `build/` directories. They are not registered production matrix tasks; do not run them directly against live data.

| Script | Actual role and limitation |
| --- | --- |
| [semantics.py](../scripts/semantics.py) | Archetype-level authored candidates for contact, interaction, material, destruction, vision, audio, cultivation, resources, and scale. Values are not engine contracts. |
| [rembg.py](../scripts/rembg.py) | ComfyUI RMBG-2.0 background removal and RGBA PNG normalizer. Detects existing alpha, skips redundant cutouts, extracts opaque backgrounds via ComfyUI, fits canvas with 16px margins, and enforces PNG output. |
| [geometry.py](../scripts/geometry.py) | Shared 128 px reference cells, 32 px subcells, alpha threshold 128, thresholded bbox, and contact-run measurements. Missing repository markers fail clearly. |
| [derive.py](../scripts/derive.py) | Builds `mapdata/cells@1` in `build/mapdata/cells.json` from the catalog and runtime PNGs: coverage, blocking/walk masks, semantic metadata, actual canvas size, and `issues`/`failed`. Findings return 1. It does not re-bake images or emit dedicated projectile/vision masks. |
| [subcell.py](../scripts/subcell.py) | Reads `cells.json` and its runtime PNGs to build `mapdata/subcell@2` in `build/mapdata/subcell.json`: cropped 32 px fill including partial edge cells, native/reference contact estimates, rectangles, and scale variants. Missing PNGs return 1; `art_defects` remains a heuristic warning. |
| [audit.py](../scripts/audit.py) | Requires both JSON artifacts. Checks record parity, matrix shapes/values, phantom blockers, ground rows, walk surfaces, authored openings, contact bounds and scale agreement. Tree width uses the authored footprint. Returns 0 for clean stored data, 1 for findings, 2 for missing/unreadable input. It does not prove freshness or gameplay behavior. |

Coverage partitions the solid-alpha art bbox independently along each axis. It is a density measurement, not the compositor's aspect-preserving fit. `sub_fill` uses native cropped pixels; the last row/column is measured against its actual partial area. Contact uses the widest solid run in the lowest 16 native art rows; alpha below 128 cannot move the crop or contact anchor.

Contact projection uniformly fits the whole PNG canvas to the authored reference footprint and preserves the measured horizontal offset from its center. `contact_px` is native width; `contact_reference_px` and `contact_center_reference_px` use the 128 px reference space. `block_rect` equals `blocked_by_scale["1.0"]`. An exact cell-boundary tie selects the right-hand cell. Zero measured contact stays empty; the existing minimum-cell policy for measurable thin props is reported through `art_defects`.

The prototype scale list and thresholds belong to `subcell.py`. Its `block_rect` is in inclusive 128 px cell coordinates; `block_rect_px` expands those cells, rather than preserving a subcell-precise trunk shape. For `core_ring`, the subcell bounding rectangle can fill an opening that the cell mask leaves clear. Compare the actual representation used by the consumer instead of combining incompatible masks.

`sem` fields such as `blocks_projectile`, `vision_mode`, `acoustic_profile`, `destructible`, `cultivation`, and `resource` remain authored descriptions until wired and tested. Do not infer combat multipliers, concealment, audio DSP, loot drops, respawn clocks, or realm limits from these fields. Realm requirements must use the current gameplay ladder and identifiers rather than a copied fixed realm count.

If the user requests production matrix tooling, extend the responsible `tools` task with validated input/output and meaningful non-zero failures, and add red-path tests through `tools selftest run`. Verify freshness against current asset IDs, image bytes, footprint/pivot metadata and semantic inputs before accepting derived data; reject missing records and stale analysis. Do not run old prototypes against live data and call them integrated.
