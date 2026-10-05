---
name: map-asset-pipeline
description: Plan, generate, visually review, normalize, index, compose, and recover Chaos World top-down terrain, tiles, props, and environment kits. Use for world-map art and contact/collision metadata review; use the character or item pipeline for those assets.
---

# Map Asset Pipeline

Deliver coherent, reviewed map layers with traceable sources and declared footprints. Match the requested mode: planning, generation, installation, composition, recovery, or audit. An audit request does not authorize a generation batch or replacement of existing art.

## Sources and boundaries

- Read the top-down world-map section of [art direction](../../../docs/art-direction.md) before preparing prompts or judging art.
- The catalog is `game/assets/map-asset-index.jsonl`; command behavior belongs to [map_assets.py](../../../tools/map_assets.py), [map_generate.py](../../../tools/map_generate.py), and [map_layout.py](../../../tools/map_layout.py). Code wins when this skill disagrees.
- Read [the data and geometry reference](references/data-matrix-spec.md) for index fields, composition layouts, source recovery, or matrix work. Do not load the bundled scripts for ordinary art generation.
- Use only `uv run python -m tools <task>` entrypoints. Run gates in the background with output under `build/`, as required by `AGENTS.md`.
- The bundled scripts measure diagnostic geometry and validate its consistency. Their authored collision, destruction, vision, audio, and cultivation fields do not establish runtime support. Trace the actual consumer before promising gameplay behavior.

## 1. Inspect and choose a small slice

```text
uv run python -m tools assets map report
uv run python -m tools assets map next --count 6
uv run python -m tools assets map generate --help
```

Read the selected index records, including `environment_theme`, `alpha`, `pivot`, `canvas_px`, `footprint_cells`, and `collision`. Use existing art when it fits. `next` suggests coverage gaps; it does not choose the user's scope. Counts and environment lists come from the live catalog, not this skill.

For a new environment kit, start with its opaque terrain surface, then a representative blocker, resource node, route/entrance, and landmark. Compare them together before scaling the batch. Optional tiles follow the base surface. Make variants differ in silhouette, material, or structure; a hue-only recolor is not new art.

Before installation, claim the index and destination paths and check their working-tree state. The installer rewrites the whole index: serialize index writers, inspect the current diff, and do not merge or overwrite another session's uncommitted entries. Use `scaffold` only when the catalog is absent; it refuses an existing index. Use `migrate` only for missing legacy alpha/footprint metadata, not to refresh environment themes.

## 2. Generate with a concrete brief

Describe the indexed subject, environment materials, distinguishing silhouette, and intended footprint. Preserve the shared gouache finish, dark ink contours, broad value planes, and restrained upper-left light. The local generator adds production framing and the catalog's environment theme; do not add contradictory camera instructions.

- Camera & Angle: 2D orthographic top-down ($\sim 45^\circ$) world-map angle with credible ground contact and base anchors, or strictly overhead per environment requirements.
- Transparency & Background Prompting Strategy:
  * Always prompt for `transparent background` first in the generation brief.
  * If the diffusion generator cannot emit native alpha or produces solid backing, ensure the prompt explicitly appends `Solid plain white background` at the very end to guarantee a clean contrast edge for cutout.
  * Only when the result lacks transparency support does the pipeline route through AI background removal (`scripts/rembg.py` using ComfyUI's `RMBG-2.0` node).
- Strict File Format (PNG Enforcement):
  * **All game-ready production runtime assets MUST be saved as PNG (`.png`).**
  * JPG (`.jpg`) does not support alpha channels and is strictly forbidden for runtime assets (JPG is permitted ONLY for local, gitignored raw generation caches under `original/`).
  * Dedicated background removal and normalization tool: `scripts/rembg.py`. Usage:
    `uv run python .agents/skills/map-asset-pipeline/scripts/rembg.py --input <raw-image> --output <runtime.png> --size <w> <h> --pivot <center|bottom_center>`
- Terrain: continuous, opaque surface with quiet detail; no embedded props, framed platform, or focal object. A terrain texture need not tile seamlessly.
- Repeatable tile: joined edges without border seams; use the indexed alpha mode.
- Prop: one complete indexed subject or intentional cluster, clear silhouette and padding, transparent surroundings, short attached shadows, and the indexed pivot. Keep ground contact visually credible without changing the camera angle.
- No baked text, UI, frame, watermark, unrelated objects, or explicit sexual content.

A local generation request uses the configured ComfyUI workflow. Do not silently change provider, install models, or change shared checkpoint/LoRA settings. If the workflow is unavailable, report the dependency and finish any independent planning or review work.

Use a fixed seed for comparable candidates. Set `--target-size` deliberately for direct installation: it defaults to `--size`, which can otherwise install a 1024 px prop. Use the selected record's intended runtime canvas; this flag accepts a square side, a multiple of 16 in 64–2048. `install` uses the record's existing canvas and also supports rectangular records. Resolution never determines `footprint_cells`.

```text
uv run python -m tools assets map generate --asset-id <catalog-id> --prompt "<subject brief>" --seed <seed> --size 1024 --target-size <runtime-side> --preview-only
```

The placeholders above are a command template. `--preview-only` creates a source under `build/map-generated/` and leaves the catalog unchanged. Use it for experiments and replacement candidates. For an established recipe and a new `planned` asset, direct `generate` may install a provisional `generated` result; review that installed result before calling it accepted.

Render sequentially. Review the first candidate before the next. When comparing cutout models, add `--compare-rembg` to the preview run so installed removers share one prompt and seed; choose the result that preserves fine detail. Source filenames include the asset ID, seed, remover and LoRA settings, and existing filenames are refused. Reuse an existing candidate rather than blindly rerunning it. Do not strip a background by color-key guessing or erode away real trunks, leaves, or arch openings.

Default retry budget: the initial candidate plus two targeted retries per asset, unless the user specifies another budget. Name the defect and change one relevant factor per retry. A timeout or submission error may leave a ComfyUI job running: inspect the existing job/history before resubmitting. Stop repeated failures, preserve their artifacts, and report the unresolved dependency or defect.

## 3. Inspect the pixels, then install

Open actual source and runtime images with an image-viewing tool; filenames, generation success, and audit output cannot prove visual quality. Review every candidate at its intended display scale and on contrasting backgrounds or a checkerboard:

- Correct subject, environment materials, strictly overhead projection, and shared lighting.
- Complete silhouette; no clipped crown/base, stray fragments, opaque backdrop, checkerboard baked into pixels, white halo, or cutout holes.
- Fine contact details survive normalization; padding and pivot seat the object correctly.
- Terrain stays quieter than blockers, harvest nodes, routes, and landmarks. Check seams in a repeated preview only for assets intended to repeat.
- Neighboring assets share scale and contrast; distinguish visual overhang from physical ground contact. Record concrete defects by asset ID.

Install a reviewed preview without generating it again:

```text
uv run python -m tools assets map install --asset-id <catalog-id> --source "<reviewed-source.png>" --source-name "<actual tool/model>" --license "<actual terms>" --generated-on <YYYY-MM-DD> --prompt-ref "<generation identifier>" --prompt "<exact production prompt>" --reference-id "docs/art-direction.md#top-down-world-map"
uv run python -m tools assets map preview --asset-id <catalog-id>
```

For local preview-only runs, recover the expanded production prompt and run details from source workflow metadata or ComfyUI history; the short subject brief alone is not the exact production prompt. Record only provenance you can verify. Reference IDs document guidance; they do not imply the generator consumed a reference image.

The installer normalizes alpha/padding and archives the exact PNG supplied to it. Review the normalized output again: cropping and resizing can damage an otherwise good source. `planned` becomes `generated`; `approved` requires real approval attribution. An agent's visual review does not invent user approval or prove an in-game review.

Use `--replace-generated` only for an explicitly requested replacement or correction of this task's own provisional output, after preserving and comparing the old result. The tool refuses replacement of `approved` assets. Do not downgrade status to bypass that protection.

## 4. Compose and verify

For an environment kit, create an editable JSON layout under `build/` using the reference's grid contract, then compose the reviewed layers:

```text
uv run python -m tools assets map compose --layout build/map-layout.json
uv run python -m tools assets map audit
uv run python -m tools map_theme check
uv run python -m tools check
```

Inspect `build/map-compositions/<layout-id>.png`. Check pivots, relative scale, art overlap, quiet walkable ground, clear routes, and readable interactions. A composite is a preview; retain its terrain and individual sprites. The composer's alpha overlap mask is a placement check, not a navigation, projectile, or sight mask.

An asset-only task can finish with visual review and catalog validation. Report in-game scale/collision as unverified unless the real consumer and representative gameplay patch were exercised. Run relevant gameplay suites when changing a consumer, and run the full repository gate before committing. If unrelated work blocks that gate, name the failing stage and do not repair foreign dirty paths.

When changing the bundled measurement or audit helpers, run their isolated fixture gate:

```text
uv run python -m tools selftest run --suite map-geometry
```

It tests crop offsets, alpha noise, partial subcells, cutout failures, contact projection, matrix shape, and failing audits without altering the catalog or art. See the reference for coordinate spaces and remaining limitations.

## 5. Preserve and recover sources

Runtime layers belong in `game/assets/world_map/`; untouched source PNGs belong in gitignored `art-source/map-originals/`. `source_images` in the catalog records paths, full SHA-256 hashes, dimensions, and provenance. There is no separate provenance ledger written by this pipeline. A gitignored archive is local storage, not a backup available from a fresh clone.

The installer may receive a PNG that already had its background removed. Preserve the pre-cutout render separately when it exists and re-cutting may be needed. Archiving a cutout cannot reconstruct removed pixels. `recover-originals` proposes source matches by date/alpha heuristics; it neither proves their identity nor re-bakes runtime sprites. `derive.py` measures geometry and does not reprocess images.

Use recovery without `--apply` first, inspect `build/map-original-recovery.jsonl`, and visually verify candidate identity. Archive a known source with `preserve-original`; apply recovery only to verified matches. See the reference for commands and limitations.

## Completion

Report accepted/reused asset IDs and paths, unresolved visual defects, source/provenance gaps, validation results, and whether gameplay was actually checked. Commit only this task's files and imported sidecars after reviewing the diff; keep generated previews and source archives out of Git. Do not create status notes or claim engine integration from diagnostic matrices.
