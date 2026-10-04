---
name: item-asset-generation
description: Generate, index, and audit reusable item-family images with Chaos World's local ComfyUI CLI. Use when expanding item art or analyzing visual coverage.
---

# Item Asset Generation

Use the local Krea2 item profile to expand reusable item images while keeping `game/assets/asset-index.jsonl` as the source of truth. Generate focused batches and inspect each result; do not try to create one image per seed.

## Before a batch

1. Read `docs/art-direction.md` and inspect nearby indexed examples.
2. Run `uv run python -m tools data distribution` and `uv run python -m tools assets audit`. Use the distribution report to choose an underrepresented visual characteristic (for example, equipment form and masculine/feminine presentation), not only a category with many seeds.
3. Check `git status --short` for the asset index and target image paths before editing. Use the claim guard for paths if concurrent work is active.
4. Choose seeds that can share one icon: same category and subcategory, with a coherent silhouette/material. Prefer a useful family covering multiple seeds, but don't force unlike items together.

## Generate and link

The CLI talks to local ComfyUI and defaults to Krea2. Generate at 512, install at 256, and record descriptive diversity tags:

```text
uv run python -m tools assets generate --family-id bronze_sunward_robe --match-item <seed-id> --match-item <another-seed-id> --prompt "Isolated square game inventory icon of a ...; ..." --size 512 --target-size 256 --visual-trait form:robe --visual-trait presentation:masculine --visual-trait palette:vermillion
```

Use `--asset-id <existing-id> --replace-generated` to regenerate an existing generated family. `--match-item` is only valid with `--family-id`. All seeds in a new family must share category and subcategory; the CLI rejects invalid or already-owned matches. Keep the icon isolated, centered, readable at 256px, with a distinct silhouette, material, motif, and palette. Avoid text, UI frames, scenery, duplicate objects, and cropped edges. Vary palette and motifs across batches; do not default everything to jade/green.

Krea2 LoRAs bundled in the item workflow are at zero strength by default. Keep that setting for item generation unless a deliberate comparison is requested. Use `--preview-only` to preview without installing or modifying the index.

## Inspect, audit, and continue

- Inspect each generated PNG at game icon size for silhouette/readability, prompt match, palette variety, accidental text/glyphs, artifacts, and cutout quality. Regenerate weak outputs before proceeding.
- After each batch run `uv run python -m tools assets audit` and `uv run python -m tools data distribution`; verify every intended seed resolves to the correct indexed family and trait counts reflect the intended diversity.
- Keep generated files under `game/assets/items/generated/`. The CLI writes the asset index; do not hand-edit it while a generation is running, because the CLI reloads it after rendering to preserve concurrent edits.
- Work toward at least 2,000 unique item image files, measuring unique files rather than family or seed counts. Before each wave, use current audits and trait distribution to target missing characteristics.
- Commit only the skill-owned/generated paths for the completed slice. Never stage unrelated asset-index edits.
