# unique

Private repo for Chaos World unique character assets and exclusive content. Not shared — for private use only.

## What this is

Consumer repo — contains only scripts and generated assets. All models, workflows, and LoRAs live in `local-image-generator-service`. This repo never clones or stores generation models.

### Reproducibility gap — what a reader cannot recover from this repo

The renders in `outputs/` are **not reproducible from this checkout alone**, and the reason is
structural rather than an oversight:

- **Checkpoints and LoRAs are out of repo.** `scripts/generate.py` resolves them from
  `local-image-generator-service/models/`, which is a separate private repository. The exact
  `.safetensors` used for a given render is not recorded in any file here.
- **The ComfyUI graph is not in this repo either.** The graph a render is driven by lives in the
  out-of-repo service's `workflows/`. A consumer of this repo therefore cannot re-run a generation,
  only re-validate a render that already exists.
- **No sidecar is written per render.** Prompt, seed, checkpoint, licence and generation timestamp
  are not emitted beside a PNG, so a render found loose in `outputs/` cannot be traced to the
  settings that produced it. This is why the character catalog cannot index the remaining renders
  with truthful provenance — see `DEF-0308` in the Chaos World repo.
- **`scripts/` runs against a live service.** Every command below needs ComfyUI reachable and
  expects the out-of-repo models to be present; it is not an offline batch.

Commands are invoked as `uv run python scripts/<file>.py`. That keeps every entrypoint on the
project's package runner and its lockfile instead of whatever Python happens to be first on `PATH`
— which is the reason bare `python` was wrong here, not a style preference.

## Architecture

```
unique/                      (this repo — consumer)
  scripts/generate.py       # CLI tool → talks to ComfyUI
  scripts/generate_single.py # One-shot generation with agent inspection
  scripts/validate.py       # Automated validation (V1-V9)
  context/                  # Per-character context summaries
  outputs/                  # Generated PNGs (gitignored)
  README.md
  WORKFLOW.md
  ART_CRITERIA.md

local-image-generator-service/  (generation backend)
  workflows/                # ComfyUI workflow JSON
  models/loras/krea2/       # LoRA weights
  ComfyUI at 127.0.0.1:8188
```

## First character: Ilsa Renn (`unique-0001`)

| Field | Value |
|-------|-------|
| **Name** | Ilsa Renn |
| **Aliases** | "the standard", "the null reading" |
| **Role** | npc |
| **Path** | unaffiliated |
| **Faction** | organizations.saltledger |
| **Home** | geography.mortal_plains |
| **Realm** | no gate, no ladder |
| **Race** | races.echoless |

### Appearance

- **Age**: 41 (ordinary human span — the ordinariness is the point)
- **Build**: Average and unadapted, never asked to carry a load or take a gate
- **Complexion**: Ordinary warm human skin, no flush, no scar tissue, no qi-sheen
- **Hair**: Dark brown, cropped short, cut with a blade rather than a style
- **Eyes**: Dark, level, very steady — cannot be read for intent at any range
- **Palette**: Near-monochrome: warm ivory, ash grey, pale jade, single dull brass accent
- **Attire**: Travelling coat of undyed wool over high-collared linen shift, sleeves full, wrists bound with plain cord. No livery, no sect colour, no rank marking.
- **Marks**: None. No clan mark, no oath burn, no cultivation scarring. The absence is the most alarming thing about her in a room of cultivators.
- **Bearing**: Absolutely still by default, trained rather than inherited. Does not fidget, shift, or fill a silence.

### Tags

`role:calibrator`, `standing:unrecorded`, `gift:uncultivated`, `burden:unwarnable`, `class:echoless`

### Nine-prompt visual set

| Slot | Kind | Min | Notes |
|------|------|-----|-------|
| `map_sprite` | map_sprite | 1 | small-scale exploration token |
| `dialogue_portrait` | dialogue | 1 | waist-up, neutral default |
| `character_portrait` | portrait | 1 | polished primary |
| `concept_art` | concept | 1 | full body, clothing and equipment readable |
| `environmental_concept` | concept | 1 | scene must name a lore-correct location |
| `combat_concept` | concept | 1 | weapon, abilities, fighting identity |
| `relationship_scene` | scene | 1 | scene required; interpersonal or dramatic |
| `expression_set` | portrait | 9 | distinct expression text |
| `pose_set` | portrait | 6 | distinct pose text |

## How agents use it

```bash
# List available profiles
uv run python scripts/generate.py --list-profiles

# List available LoRAs (grouped by category)
uv run python scripts/generate.py --list-loras

# List workflow LoRA slots
uv run python scripts/generate.py --list-slots

# Generate a portrait
uv run python scripts/generate.py --profile portrait --prompt "Ilsa Renn, a plain woman with dark cropped hair and steady eyes, travelling coat of undyed wool" --output outputs/ilsa_portrait.png

# Generate with LoRA variation (style + expression)
uv run python scripts/generate.py --profile portrait --prompt "Ilsa Renn" \
    --lora style=0.8 --lora expression=0.6 --output outputs/ilsa_v2.png

# Generate full-body, no background, fixed seed
uv run python scripts/generate.py --profile fullbody --prompt "Ilsa Renn" \
    --no-bg --seed 42 --output outputs/ilsa_fullbody.png
```

## Profiles

| Profile | Ratio | MP | BG | Description |
|---------|-------|----|----|-------------|
| `portrait` | 3:4 | 2 | yes | Bust-up character portrait |
| `fullbody` | 2:3 | 2 | yes | Full-body character sprite |
| `square` | 1:1 | 2 | yes | Square composition |
| `landscape` | 16:9 | 2 | yes | Landscape scene |
| `no-bg` | 3:4 | 2 | no | Portrait with transparent background |
| `sprite` | 1:1 | 1 | no | Small game sprite, transparent |

## LoRA categories

- `style` — Art style / aesthetic
- `expression` — Facial expression / emotion
- `pose` — Body pose / framing
- `control` — ControlNet (pose/structure)

Assign LoRAs to slots in order: `--lora style=0.8 --lora expression=0.6`. First LoRA loads outermost.

## Data structure

From ADR 0138: The named cast is a separate catalog (`unique-index.jsonl`), keyed by `unique-NNNN`. Stats are prose. Shots are free-form with `id`, `kind`, `pose`, `expression`, `framing`, `scene`, `canvas`. `kind` is a closed set: `concept`, `portrait`, `dialogue`. Per-character canvas (not fixed slot size).

Art folder: `game/assets/characters/unique/<id>/` (gitignored via `game/assets/characters/*/`).

## Requirements

- `local-image-generator-service` repo with ComfyUI running at `http://127.0.0.1:8188`
- Krea2 Turbo model + workflow installed in ComfyUI
- LoRAs in `local-image-generator-service/models/loras/krea2/`

## Tips for agents

- Use `--seed` for reproducible variants of the same character
- Combine `--lora style` + `--lora expression` + `--lora pose` for unique variants
- Use `--no-bg` for game sprites that need transparent backgrounds
- Use `--ratio` to override the profile's default aspect ratio
- Check `--list-loras` to see what's available before requesting
- Ilsa Renn is deliberately plain — near-monochrome palette, unremarkable features, no marks. The absence of distinguishing features is the character.
