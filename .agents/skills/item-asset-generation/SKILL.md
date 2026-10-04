---
name: item-asset-generation
description: Generate, index, and audit reusable item-family images with Chaos World's local ComfyUI CLI. Use when expanding item art or analyzing visual coverage.
---

# Item Asset Generation

Use the local Krea2 item profile to expand reusable item images while keeping `game/assets/asset-index.jsonl` as the source of truth. Generate focused batches and inspect each result; do not try to create one image per seed.

## The one resident model

**This PC has a single 24 GB GPU and cannot hold two Krea2 UNETs at once** (12.4 GB + 12.25 GB > 24 GB). Item generation therefore shares the character workflow's UNET:

- item + character: `krea2/vxpKrea2Nsfw_beta4AnimeINT8.safetensors` — `tools/map_generate.py` `KREA2_MODEL`, and node 761 of the character workflow `G:\Works\local-image-generator-service\workflows\moodyKrea2Minimal_v40_api_v2.json`.

**Never point item generation at a second model.** `raySemiReal_krea2TurboV1Nsfw.safetensors` is still on disk and still resolvable by ComfyUI, so a wrong name fails as an OOM or a silent swap, not a missing-file error. If item and character generation must both happen, run them **sequentially, never concurrently**.

`tools/map_generate.py` `KREA2_ITEM_WORKFLOW` is a node-for-node adaptation of that character workflow — same 43 nodes, same 32-LoRA chain, same CLIP/VAE/RMBG. It differs only in `EmptyLatentImage` for square icons, `ConditioningZeroOut` for negatives, and prompt/seed/filename. If the character workflow changes, re-check that adaptation rather than letting it drift.

## Before a batch

1. Read `docs/art-direction.md` and inspect nearby indexed examples.
2. Run `uv run python -m tools data distribution` and `uv run python -m tools assets audit`. Use the distribution report to choose an underrepresented visual characteristic (for example, equipment form and masculine/feminine presentation), not only a category with many seeds. Presentation is the thinnest axis in practice — it had 8 family tags against 236 form tags.
3. Check `git status --short` for the asset index and target image paths before editing. Use the claim guard for paths if concurrent work is active: `uv run python -m tools claim_guard claim --session <id> --paths <p>`, and release when done.
4. Choose seeds that can share one icon: same category and subcategory, with a coherent silhouette/material. Prefer a useful family covering multiple seeds, but don't force unlike items together.

## Generate and link

The CLI talks to local ComfyUI and defaults to the Krea2 profile above. Install at 256 and record descriptive diversity tags:

```text
uv run python -m tools assets generate --family-id bronze_sunward_robe --match-item <seed-id> --match-item <another-seed-id> --prompt "Isolated square game inventory icon of a ...; ..." --size 1024 --target-size 256 --visual-trait form:robe --visual-trait presentation:masculine --visual-trait palette:vermillion
```

`--size` defaults to 1024 and most recent icons were generated at 1024; pass `--size 512` to halve render time when a batch is exploratory. `--target-size` defaults to 256 and is the installed canvas — that, not `--size`, is the size the game reads.

Use `--asset-id <existing-id> --replace-generated` to regenerate an existing generated family. The CLI refuses to overwrite an existing file without that flag, so a failed regeneration costs nothing. `--match-item` is only valid with `--family-id`. All seeds in a new family must share category and subcategory; the CLI rejects invalid or already-owned matches. Keep the icon isolated, centered, readable at 256px, with a distinct silhouette, material, motif, and palette. Avoid text, UI frames, scenery, duplicate objects, and cropped edges. Vary palette and motifs across batches; do not default everything to jade/green.

Krea2 LoRAs bundled in the item workflow are at zero strength by default. Keep that setting for item generation unless a deliberate comparison is requested. Use `--preview-only` to preview without installing or modifying the index.

### The negative prompt does nothing on Krea2

The Krea2 graph wires the sampler's negative input to a `ConditioningZeroOut` node, so **every** `--negative` token and every "no X" clause in the production brief is discarded. `DEFAULT_NEGATIVE` lists `duplicate subject`, `text`, `watermark`, `border`, `UI` and `extra objects` — none of them constrain the render.

State every exclusion as a positive instruction instead:

| Instead of | Write |
|---|---|
| `no duplicate subject` | `Exactly one single <object>, one object only` |
| `no cropped edges`, `generous padding` | `sits wholly inside the frame with wide empty margins on all four sides, nothing touching any edge` |
| `no jade green` | name the palette outright: `charcoal iron, scarlet, and aged brass palette` |

A render asked for "one bell" with `No jade green` in the prompt came back with **two bells and a teal glow**, because neither instruction reached the sampler. The same render re-rolled with positive framing came back correct.

### Padding in the source is irrelevant; only edge-cropping matters

`_normalize_image` crops to the alpha bounding box, fits the result to 232px, and centres it on the 256 canvas (`tools/assets.py:118-124`). So generous source margins are thrown away, and judging a render by its margins measures the wrong thing.

Judge instead on whether the subject **touches a canvas edge**, because content past the edge is destroyed before install. Check it directly:

```text
python -c "from PIL import Image; im=Image.open(r'build/item-generated/<file>.png').convert('RGBA'); a=im.getchannel('A'); bb=a.point(lambda v:255 if v>8 else 0).getbbox(); print(bb, im.size)"
```

A bbox of `(0, 0, ...)` means the subject is cropped and that seed is unusable. Also confirm a transparent background exists at all: `alpha.getextrema()[0]` must be `0`, otherwise `_normalize_image` raises `source has no transparent pixels`.

Composite previews onto a **checkerboard**, not white. A white composite makes a correctly cut-out icon look like it still has a background and sends you hunting for a removal bug that does not exist.

The generated prompt is recorded verbatim in the index, so a record's `prompt` field shows the fixed production brief plus your `--prompt` text. Read it there when judging why an icon looks the way it does.

## Inspect, audit, and continue

- Inspect each generated PNG at game icon size for silhouette/readability, prompt match, palette variety, accidental text/glyphs, artifacts, and cutout quality. Regenerate weak outputs before proceeding.
- After each batch run `uv run python -m tools assets audit` and `uv run python -m tools data distribution`; verify every intended seed resolves to the correct indexed family and trait counts reflect the intended diversity.
- Keep generated files under `game/assets/items/generated/`. The CLI writes the asset index; do not hand-edit it while a generation is running, because the CLI reloads it after rendering to preserve concurrent edits.
- `assets report` counts families, but `assets report --diversity` reports the **unique image file** count against the 2,000 floor in `MIN_UNIQUE_IMAGE_TARGET` (`tools/assets.py`). Measure unique files, not families or seeds. As of 2026-10-04: 638 families, **535 unique files**, 1,465 remaining.
- Commit only the skill-owned/generated paths for the completed slice. Never stage unrelated asset-index edits.

## The library is not visually uniform

Icons were produced across several models and styles, so a fresh icon will not match its neighbours:

| `generation_settings.checkpoint` | records | note |
|---|---|---|
| (absent — `OpenAI image_gen`, 2026-10-01) | 408 | earliest batch, no model recorded |
| `Flux1S/originByN0utis_originFluxAnimeV1.safetensors` | 87 | 24 steps, euler/normal, `--size 512` |
| `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors` | 143 | 8 steps, euler_ancestral/beta — **the superseded model** |

Query the split with `Get-Content game/assets/asset-index.jsonl | ConvertFrom-Json | Group-Object { $_.generation_settings.checkpoint }`.

Anything generated from now on uses the shared `vxpKrea2Nsfw_beta4AnimeINT8` UNET, so the 143 `raySemiReal` icons are the ones that visibly diverge from the current pipeline. Regenerating them for consistency is `--asset-id <id> --replace-generated` per family, and costs one render each — there is no bulk image-rewrite tool. Budget it as its own wave rather than mixing it into a new-content batch.

**Diverge is not the same as worse.** A side-by-side pilot on `equipment-accessory-iron-sage-ward-bell` produced a correct, well-composed icon from the shared UNET, but the installed `raySemiReal` version was more ornate and better palette-controlled. Judge each family on its own merits and keep the old icon when it wins; a model swap is not an automatic upgrade.

## The resolve gate is global

`_validate_new_family` runs `_resolve` across **every** item seed and rejects a new family if *any* seed is unresolved, and `assets sync` refuses for the same reason. So one unmapped subcategory blocks all generation, not just its own.

Two consequences worth knowing before you start a batch:

- **`--asset-id <id> --replace-generated` bypasses the gate.** The check only runs when `--family-id` is passed, so regenerating an existing family works even while the corpus is unresolved. That is the way to smoke-test a model without first fixing the index.
- **An in-flight content migration can block the whole pipeline.** On 2026-10-05 a concurrent session moved 1,177 items from `technique/*` to `consumable/*` without adding matching families, which froze both `sync` and `generate` until ten `consumable/*` families were added by hand. If `assets audit` reports a large block of "no matching asset family", check whether those seeds are relabelled rather than new before authoring art for them:

  ```text
  git diff --name-only -- game/data/items/technique
  ```

  Seeds that appear there were moved, and their old subcategory usually already has a family with art to reuse.
