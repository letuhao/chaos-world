# Unique Character Asset Generation Workflow

> A systematic pipeline for generating game-ready unique character assets.
> Each asset is a **sub-program** with its own context, criteria, prompt, and validation — not a chore.

---

## Philosophy

Every unique character emerges from their **world**, not from random trait draws. The workflow collects context first, generates art criteria from that context, builds prompts from criteria, generates assets, validates against criteria, and re-generates anything that fails.

**Core principle**: Context → Criteria → Prompt → Generate → Validate → Re-generate

---

## Phase 1: Context Collection

**Goal**: Gather everything the character's world tells us about how they should look.

### Inputs
- `unique-index.jsonl` — character record (identity, appearance, tags)
- `lore/bible/*.jsonl` — race, culture, faction, geography
- `lore/edges/*.jsonl` — relationships, conflicts, history
- `docs/adr/0138` — data structure rules

### Process
1. Read character record from `unique-index.jsonl`
2. Resolve all lore references:
   - `appearance.race` → `lore/bible/races.jsonl` (species traits, lifespan, culture)
   - `identity.faction` → `lore/bible/organizations.jsonl` (oath, role, culture)
   - `identity.home` → `lore/bible/geography.jsonl` (climate, architecture, clothing)
   - `identity.path` → cultivation path (qi/body/mind/unaffiliated)
3. Read ADR 0138 for shot structure (nine-prompt visual set)
4. Read `ART_CRITERIA.md` for per-shot criteria template

### Output
A **context summary** containing:
- Character name, role, path, faction
- Race traits (lifespan, culture, body plan)
- Home geography (climate, architecture, materials)
- Faction culture (oath, clothing style, marks)
- Personality through posture
- Color palette (from lore, not invented)

---

## Phase 2: Art Criteria Generation

**Goal**: Create per-shot criteria that are grounded in the character's world.

### Process
For each of the 22+ shots, define:

| Criterion | Source |
|-----------|--------|
| **Purpose** | Game function (map token, dialogue, combat, etc.) |
| **Visual criteria** | From appearance.* fields + race + faction + geography |
| **Mood** | From personality + tags + canon history |
| **Composition** | Camera angle, framing, distance (varied per shot) |
| **Distinguishing feature** | What makes THIS shot different from all others |
| **Prompt keywords** | Specific words from lore (not generic) |
| **Negative prompt** | What to suppress (attractiveness bias, wrong culture) |

### Key Rules
- **Clothing must match geography** — Mortal Plains = undyed wool, linen, no livery
- **Marks must match faction** — saltledger = no marks, no sect insignia
- **Palette must match lore** — near-monochrome for Ilsa, not invented colors
- **Posture must match personality** — trained stillness for Ilsa, not dynamic posing
- **No anachronisms** — no modern clothing, no wrong-culture items

### Output
Updated `ART_CRITERIA.md` with per-shot criteria grounded in lore.

---

## Phase 3: Prompt Engineering

**Goal**: Build prompts that produce the character as described, not the model's default.

### Prompt Structure
```
[POSITIVE PROMPT]
- Character identity (name, age, role)
- Appearance (from appearance.* fields — exact words)
- Clothing (from geography + faction — specific materials, no invention)
- Palette (exact hex codes from ART_CRITERIA.md)
- Posture (from personality — specific body language)
- Style (painterly illustration, NOT "anime")
- Shot-specific criteria (from ART_CRITERIA.md)

[NEGATIVE PROMPT]
- Attractiveness bias suppressors
- Wrong culture items
- Anachronisms
- Generic fantasy elements (glow, magic, ornate)
```

### Key Techniques
1. **Suppress attractiveness** — "plain, unremarkable, forgettable, the kind of face you can't reconstruct from memory"
2. **Force culture** — "undyed wool, high-collared linen shift, no livery, no sect colour"
3. **Force geography** — "Mortal Plains, stony measurement yard, open grassland"
4. **Use conceptual descriptions** — "a small hard courtesy that does not reach the eyes" > "slight smile"
5. **Vary expressions fully** — eye direction × head position × body language × light (not just mouth)

### Output
Per-shot prompt + negative prompt, ready for generation.

---

## Phase 4: Generation

**Goal**: Generate all assets with the strengthened prompts.

### Process
1. For each shot in ART_CRITERIA.md:
   - Build prompt from Phase 3
   - Set seed (deterministic, reproducible)
   - Enable background removal (wire RMBG node)
   - Generate via ComfyUI `/prompt`
   - Save to `outputs/`
2. Small delay between generations (2s)
3. Log all results

### Output
All PNGs in `outputs/` with transparent backgrounds.

---

## Phase 5: Validation

**Goal**: Check every asset against criteria — automatically and visually.

### Automated Checks
```bash
uv run python scripts/audit_images.py
```
- Alpha channel exists (background removal works)
- Transparent percentage > 20%
- Image dimensions match expected canvas

### Visual Inspection (Agent)
For each shot, check:
- **Character fidelity**: Does the character match the lore description?
- **Culture match**: Does clothing match geography + faction?
- **Palette match**: Are colors from the approved palette?
- **Diversity**: Is this shot distinct from all others?
- **Quality**: Clean lines, no artifacts, readable silhouette?

### Validation Criteria
| Check | Pass Condition |
|-------|----------------|
| Background removal | Alpha channel exists, >20% transparent |
| Character fidelity | Face, hair, eyes, build match appearance.* |
| Culture match | Clothing materials match geography |
| Palette match | Colors match approved hex codes |
| Expression diversity | Each expression differs in eyes + head + body + light |
| Pose diversity | Each pose differs in camera angle + framing |
| No attractiveness bias | Not beautiful/attractive/striking/memorable |
| No wrong items | No jewellery, no armour, no weapon (unless specified) |

### Output
Validation report with pass/fail per shot.

---

## Phase 6: Re-generation Loop

**Goal**: Fix anything that failed validation.

### Process
1. For each failed shot:
   - Identify the specific failure (fidelity, culture, palette, diversity, quality)
   - Strengthen the prompt for that specific issue
   - Regenerate with a new seed
   - Re-validate
2. Repeat until all shots pass

### Re-generation Triggers
| Failure | Fix |
|---------|-----|
| Too attractive | Strengthen negative prompt, add "plain, unremarkable, forgettable" |
| Wrong clothing | Add specific materials from geography, suppress wrong items |
| Wrong palette | Add exact hex codes, suppress wrong colors |
| Expressions too similar | Vary eye direction, head position, body language, light |
| Poses too similar | Change camera angle, framing, distance |
| Background removal failed | Check RMBG wiring, add "white background" to prompt |

### Output
All shots pass validation.

---

## Asset Sub-Program Specification

Each asset is a **sub-program** with its own complete specification:

### Template
```markdown
## Asset: [shot-name]

### Context
- Character: [name, role, path]
- Race: [species traits]
- Geography: [home, climate, materials]
- Faction: [oath, culture, marks]

### Criteria
- Purpose: [game function]
- Visual: [specific details from lore]
- Mood: [emotional tone from personality]
- Composition: [camera angle, framing]
- Distinguishing feature: [what makes this unique]

### Prompt
[Complete positive prompt]

### Negative Prompt
[Complete negative prompt]

### Validation
- [ ] Background removal works
- [ ] Character fidelity matches lore
- [ ] Culture match (clothing, materials)
- [ ] Palette match (approved hex codes)
- [ ] Distinct from all other shots
- [ ] Quality (clean lines, no artifacts)

### Generation
- Seed: [number]
- Status: [pending/complete/failed]
- Re-generations: [count]
```

---

## File Structure

```
unique/
  WORKFLOW.md              # This document
  ART_CRITERIA.md          # Per-shot criteria (generated from context)
  scripts/
    generate.py            # CLI tool (profile + LoRA slots)
    batch_generate_ilsa.py      # Batch generation (all shots)
    audit_images.py        # Automated validation (alpha, dimensions)
    validate.py            # Visual validation (fidelity, culture, diversity)
  outputs/                 # Generated PNGs (gitignored)
  context/                 # Per-character context summaries
    unique-0001-ilsa-renn.md
```

---

## Usage

### Generate ONE image at a time (REQUIRED — never batch)

```bash
# 1. Generate one shot
uv run python scripts/generate_single.py --shot character_portrait --seed 103

# 2. Agent inspects the result visually
# 3. If noise/artifacts: adjust prompt, save to file, retry
uv run python scripts/generate_single.py --shot character_portrait --attempt 2 --prompt-file adjusted_prompt.txt

# 4. Only move to next shot after current one passes inspection
```

### Validate all (after all shots generated)
```bash
uv run python scripts/validate.py
```

### Environment
Set `CHAOS_WORLD_GEN_SERVICE` to the local-image-generator-service path if not at the default location:
```bash
set CHAOS_WORLD_GEN_SERVICE=G:\Works\local-image-generator-service
```

### Agent Inspection Checklist (per shot)
After each generation, the agent MUST:
1. **Read the image** — look at it visually
2. **Check for noise** — artifacts, extra limbs, distorted features, blurry areas
3. **Check character fidelity** — face, hair, eyes, build match lore?
4. **Check culture match** — clothing, materials match geography + faction?
5. **Check palette** — colors match approved hex codes?
6. **Check diversity** — is this shot distinct from all previous shots?
7. **If any check fails** — adjust the prompt, save to file, retry with `--attempt N`
8. **Only move to next shot** after all checks pass

### Accept Criteria (lowered threshold)
- **Noise**: No visible artifacts, extra limbs, or distorted features
- **Fidelity**: Character is recognizable as the same person across shots
- **Culture**: Clothing matches geography + faction (undyed wool, linen, no livery)
- **Palette**: Near-monochrome (warm ivory, ash grey, pale jade)
- **Diversity**: Shot is visually distinct from all previous shots
- **Quality**: Clean lines, readable silhouette, no blurry areas

**Accept score**: 70% — if 70%+ of checks pass, accept the shot and move on. Don't chase perfection.

---

## Phase 7: Export & Integration

**Goal**: Deliver validated assets to the game.

### Process
1. Copy validated PNGs to `game/assets/characters/unique/<id>/`
2. Generate metadata sidecar (JSON) per shot:
   ```json
   {
     "shot": "character_portrait",
     "file": "ilsa_character_portrait.png",
     "seed": 103,
     "prompt_version": "v4",
     "criteria_version": "1.1",
     "validated": true,
     "validation_results": {"V1_format": "PASS", "V2_alpha": "PASS", ...}
   }
   ```
3. Update `unique-index.jsonl` with asset paths
4. Commit to git (assets are gitignored, but metadata is tracked)

### Output
- Game-ready PNGs in `game/assets/characters/unique/<id>/`
- Metadata sidecars in `game/assets/characters/unique/<id>/meta/`
- Updated `unique-index.jsonl`

---

## Generation Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Model | Krea2 Turbo | `raySemiReal_krea2TurboV1Nsfw.safetensors` |
| CFG | 1.0 | Flux models: higher CFG over-smooths |
| Sampler | euler_ancestral | Krea2 default |
| Scheduler | beta | Krea2 default |
| Steps | 8 | Krea2 Turbo is 2-step distilled |
| Resolution | 3:4 (768x1024) | Only ratio the workflow supports |
| CLIP skip | -1 (default) | No skip needed for Krea2 |
| Background removal | RMBG-2.0 | Wired via node 871 |

---

## Re-generation Rules

- **Max retries**: 3 attempts per shot
- **Seed strategy**: `new_seed = original_seed + attempt_number * 1000`
- **Escalation**: After 3 failures, flag for manual review
- **Prompt version**: Increment on each re-generation (v4 → v4.1 → v4.2)
- **Give up criteria**: If 3 attempts fail, mark as "needs manual review" and continue with other shots

---

## Key Principles

1. **Context first** — never generate before collecting lore context
2. **Criteria before prompt** — never write a prompt without per-shot criteria
3. **Each asset is a sub-program** — own context, criteria, prompt, validation
4. **Validate everything** — automated + visual, no exceptions
5. **Re-generate until pass** — max 3 attempts, then escalate
6. **Culture match** — clothing, materials, palette must match geography + faction
7. **Suppress attractiveness** — the model's default is the enemy
8. **Diversity by design** — vary camera, light, expression, pose — not by chance

---

*Workflow v1.1 — 2026-10-04*
