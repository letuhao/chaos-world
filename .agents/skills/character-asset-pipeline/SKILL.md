---
name: character-asset-pipeline
description: Generate and register diverse, tagged Chaos World map sprites and dialogue portraits from the private character catalog. Use for batches of existing PC, NPC, and boss profiles; use create-unique-character for a named, lore-authored character.
---

# Character Asset Pipeline

Use the existing tagged catalog to produce consistent map sprites and dialogue portraits at scale. Keep identity traits, privacy, generation settings, and catalog state intact so another agent can continue without reconstructing the workflow.

## Start from current state

1. Read the repository `AGENTS.md` and follow its Python, Git, and Godot rules.
2. Check any generation or import command already running. Poll that same process/session; do not resubmit a render because output is slow or silent.
3. Inspect catalog state and validity:

   ```text
   uv run python -m tools character_assets report
   uv run python -m tools character_assets audit
   ```

4. Choose profiles with the coverage-aware selector, then inspect the selected tags:

   ```text
   uv run python -m tools character_assets next --count 12 --slot map_sprite
   ```

   Use `next --help` for the current options. Prefer planned slots and profiles that extend visual coverage across age, race, presentation, setting, clothing, disability, and injury. Generate both slots for a profile when useful; avoid spending a batch on near-identical profiles. Do not change profile tags to fit an image.

   As of 2026-10-04 the catalog is scaffolded to its full 2,000 profiles (`MIN_CHARACTERS`) with 2,000 unique visual signatures, and is **early in generation**: 62 generated / 10 approved map sprites, 62 / 11 dialogue portraits, against ~1,928 still planned per slot. Coverage pressure is therefore in `presentation` (`masculine=666, feminine=667, androgynous=667`), `attire` (`bikini=20` against ~105-115 for every other attire), and `disability`/`injury` (roughly 57-97 each, against `none=1457` and `none=1382`) — not in the balanced axes. Re-read the report rather than trusting these numbers; they move every batch.

## Ground visual ideas in the world

For characters whose setting benefits from a specific cultural detail, read the matching material in `lore/prose/worlds/` and search the Lore Bible with `uv run python -m tools lore search <query>` or inspect an existing entity with `uv run python -m tools lore show <id>`. Use established details as prompt inspiration. Do not invent a named faction, place, or historical fact for a catalog profile, and do not edit lore as part of routine asset generation.

Keep the batch visually broad. Mix contemporary and cultivation-world wardrobes, practical workwear, formal looks, streetwear, outdoor clothing, swimwear, and other catalog attire. Use a profile's setting and tags to adapt its clothes instead of defaulting every character to historical robes. Include children and teens as well as adults and elders; visibly depict the tagged disability or healing injury when the framing permits. Disability and injury are separate traits, and neither should be treated as a character's whole identity.

## The one resident model

**This PC has a single 24 GB GPU and cannot hold two Krea2 UNETs at once** (12.4 GB + 12.25 GB > 24 GB). Characters and item icons therefore share one UNET:

- character + item: `krea2/vxpKrea2Nsfw_beta4AnimeINT8.safetensors` — `tools/map_generate.py` `KREA2_MODEL`, which `tools/character_assets.py` `CHARACTER_PROFILES["krea2"]["checkpoint"]` reads directly. It is also node 761 of the standalone workflow `G:\Works\local-image-generator-service\workflows\moodyKrea2Minimal_v40_api_v2.json`.

**Never point either pipeline at a second model.** `raySemiReal_krea2TurboV1Nsfw.safetensors` is still on disk and still resolvable by ComfyUI, so a wrong name fails as an OOM or a silent swap, not a missing-file error. If character and item generation must both happen, run them **sequentially, never concurrently**. Change the model in `map_generate.py` only — the character tool inherits it, so editing one constant realigns both.

`--profile` accepts only `krea2` (`character_assets.py` line 353), so Flux is not reachable by flag. The dormant `flux1s` profile entry pins a third checkpoint, `FLUX1984AnimeStyleFeat_v20Fp8Noclip.safetensors`; leave it alone rather than "fixing" it toward the shared model.

## Generate with the established profile

- Use Krea2 only. The character tool defaults to Krea2; pass `--profile krea2` if making the choice explicit. Never switch to Flux.
- Leave all LoRA strengths at their defaults, currently zero. Do not add a style or pose LoRA unless the user asks for that variation. The 32 slots are exposed as `--lora-<key>-strength` flags, generated from `map_generate.KREA2_LORAS`.
- Keep the configured Krea2 background-removal path enabled (`--background-mode rembg`, `RMBG-2.0`). The standard prompt ends with a white background to support removal. Do not replace it with chroma-key processing or another model unless the user requests a pipeline change. `--background-mode chroma-key` exists and prompts a flat `#FF00FF` field for Python-side removal, but it is not the default and requires Krea2.
- The tool appends slot-specific negatives itself: map sprites get `top-down view, overhead camera, bird's-eye view, isometric view`, and portraits get gaze terms (`looking up`, `looking down`, `looking away`, `profile view`, …). Passing `--negative` replaces only the base `CHARACTER_NEGATIVE`, which already excludes text, watermarks, lineups/collages/turnarounds, photorealism, 3D render, and sexualized framing. Never weaken it to force a render.
- Seed is derived from `character_id` (`_stable_seed`, a SHA-256 of `"<id>:identity"`), so omitting `--seed` on both slots already yields the same seed and a recognizable face across them. Pass `--seed` only to override deliberately. The map-sprite pose variant is likewise chosen from that seed, so a given character keeps one pose.
- The user has delegated automatic approval for valid catalog assets. A direct `generate` call normalizes, validates, imports, and marks the asset approved; do not stop for per-image approval. The user performs the final recheck and may ask for deletion or regeneration. Do not replace an already generated or approved slot without an explicit request.

Generate a map sprite:

```text
uv run python -m tools character_assets generate --character-id character-0001 --slot map_sprite --profile krea2 --detail "<profile-specific direction>"
```

Generate its dialogue portrait with the same seed if needed:

```text
uv run python -m tools character_assets generate --character-id character-0001 --slot dialogue_portrait --profile krea2 --seed <same-seed> --detail "<identity locks and portrait direction>"
```

Omit `--seed` on both slots and the tool derives the same stable character seed for each; the second example's `--seed <same-seed>` is only needed if you overrode it on the first. See `uv run python -m tools character_assets generate --help` for current options and LoRA names.

### Framing and identity

- **Map sprite:** the tool uses a 2:3 portrait ratio and normal eye-level full-body framing. Keep the face toward the camera, feet and ground-contact aids visible, and a readable silhouette. Wheelchair users must have the whole chair in frame. The tool excludes top-down, overhead, bird's-eye, and isometric views; do not reintroduce them in detail text.
- **Dialogue portrait:** the tool uses a 3:4 ratio and a straight-on head-and-shoulders view at eye height. Ask for a level, direct gaze and a calm natural expression. Avoid conflicting directions to look up, down, away, or at a prop.
- Use a few concrete pose variations for map sprites. Keep one character in one view; no lineups, grids, collages, or pose sheets.
- For children and teens, specify clearly age-appropriate proportions and clothing. Never sexualize a minor. Adult clothing may be revealing when the profile and request call for it, but exclude explicit sexual content, exposed breasts or nipples, and genitals. Follow the current negative prompt and repository safety rules; do not weaken them to force a render.
- Preserve tagged disability and injury plainly and respectfully. Make mobility aids functional and visible in full-body art; portraits may naturally crop aids outside the frame. Keep wounds non-graphic.

## Preview and install when needed

Use `--preview-only` only when a preview must be reviewed before registration or a tool output needs to be reused. It leaves the catalog unchanged. Inspect the preview, then use the documented installer to place it in the private asset subfolder and record provenance:

```text
uv run python -m tools character_assets install --character-id character-0001 --slot map_sprite --source <preview.png> --prompt "<generation/source description>" --source-name "ComfyUI Krea2; LoRA strengths 0" --license "Generated locally; source checkpoint and LoRA license terms apply" --seed <seed>
```

The installer performs normalization, validation, Godot import, and approval. Never write `.import` metadata by hand or start Godot directly; all imports go through the character tool and the repository's guarded launcher. If import is waiting on the shared Godot lock, leave the process alive and poll it. Do not launch duplicate imports or bypass the lock.

## Privacy and completion check

Generated PNGs belong only in the ignored character asset subfolders under `game/assets/characters/`. Keep the tagged `character-index.jsonl` in the repository; do not broaden `.gitignore` to hide the catalog, tags, or index. Before staging anything, verify the PNG is ignored and the index is not:

```text
git check-ignore -v game/assets/characters/map_sprites/<file>.png
git check-ignore game/assets/characters/character-index.jsonl
```

After a batch, confirm the catalog's approved counts and run its audit:

```text
uv run python -m tools character_assets report
uv run python -m tools character_assets audit
```

Do not run the full game test suite for image-only generation. Commit only tracked catalog changes that belong to this work; never stage private PNGs or unrelated dirty files.

## Handoff

When work moves to another agent, pass this skill path and the active process/session IDs. Ask the next agent to inspect the current report and poll active processes before generating. Summarize completed character IDs and slots, approved versus pending status, render seeds, and any known import blockers so the next agent can continue from current state.
