---
name: map-asset-pipeline
description: Plan, generate, normalize, index, and audit top-down world-map assets and multi-layer gameplay collision matrices for Chaos World. Supports dual-tier lossy/original storage, dynamic scale profiles, destruction states, variants, and cultivation/resource metadata.
---

# Map Asset Pipeline

Turn generative AI concept renders and top-down map cutouts into deterministic, engine-ready world-map assets with full gameplay collision, destruction states, dynamic sizing, and cultivation metadata.

---

## 1. Storage & Provenance Architecture

To prevent repo bloat while maintaining non-destructive, lossless source re-derivation, asset storage is divided into two tiers:

```
art-source/map-originals/                 <-- GITIGNORED (Raw ComfyUI 1024-2048px outputs)
  ├── <environment>/<category>/
  │     └── <asset_id>__<sha256_16>.png   (Untouched original PNGs with prompt & seed payload)
  └── provenance_ledger.jsonl              (Local mapping of image hashes to generation runs)

game/assets/world_map/                     <-- COMMITTED (Engine-ready, normalized runtime sprites)
  └── <environment>/<category>/
        └── <suffix>.png                   (Normalized, trimmed, alpha-padded to declared cell unit)
```

### Invariant Rules
1. **Never commit raw full-res originals to `game/`**: High-resolution renders stay in `art-source/map-originals/` (enforced by `.gitignore`).
2. **Every installed runtime asset links to its original**: The record in `game/assets/map-asset-index.jsonl` tracks `source_images: [{"path": "...", "sha256": "...", "size_px": [1024, 1024]}]`.
3. **Idempotent Re-derivation**: If background removal, alpha erode thresholds, or color grading rules change, runtime assets can be completely re-baked from the archived originals using `tools assets map recover-originals` and `scripts/derive.py`.

---

## 2. Comprehensive Asset Data Matrix

Each archetype and asset record defines a multi-layered matrix consumed by rendering, pathfinding, combat, and cultivation systems. See [data-matrix-spec.md](references/data-matrix-spec.md) for the complete JSON schema.

### A. Spatial & Collision Geometry
* **Data Cell**: Standard tile unit ($128\times 128\text{ px}$).
* **Sub-Cell Precision**: Collision is evaluated on a $32\times 32\text{ px}$ sub-grid ($4\times 4$ sub-cells per data cell, matching Godot's TileSet region size).
* **`occluder_rule`**:
  * `ground_contact`: Only the bottom row blocks; upper cells are treated as canopy overhang. (Canopy trees measure $\sim 0.44$ top coverage vs $0.12$ bottom coverage).
  * `full_body`: Blocks if coverage $\ge \text{cov\_gate}$ ($0.20$ default, $0.10$ for single-cell props).
  * `core_ring`: Openwork gates/arches maintain passable central openings while side pillars block.
  * `none`: Completely non-blocking (decals, ground textures, shallow water).
* **`passable_under`**: True for tree canopies and bridge decks.
* **`walk_surface`**: True for bridges, fallen logs, and ramps that turn blocked water or elevation gaps into walkable paths.

### B. Combat & Vision Layers (Cross-Genre Extensibility)
* **`blocks_projectile`**:
  * `false` for shallow water, deep water, low fences, and low fallen logs — allowing ranged martial arts, arrows, and flying swords to traverse chasms.
  * `true` for dense boulders, tree trunks, and buildings.
* **`vision_mode`**:
  * `solid`: Blocks raycasts for Fog of War and Line-of-Sight.
  * `canopy`: Line-of-Sight passes underneath; canopy fades when the player walks below it.
  * `brush`: Stealth/concealment zone (e.g. dense shrubs, tall bamboo); hides units inside from outside sight.
  * `transparent`: Free line-of-sight (decals, paths, shallow water).
* **`acoustic_profile`**: Acoustic footstep/impact category (`earth`, `stone`, `wood`, `foliage`, `water`, `crystal`, `metal`, `cloth`).

### C. Destruction & Environmental States (Cost-Optimized Hybrid Model)
To avoid unnecessary AI generation costs for hundreds of bespoke broken assets:
* **Generic Fallback Archetype (`on_destroy`)**:
  * Demolished props default to swapping with a shared generic archetype (`stone_and_ore.rubble`, `ground_tile.cracked_ground`, `landmark_and_environment_detail.ground_decal`), freeing upper blocked cells immediately.
* **Unique Destroyed Sprites (`unique_destroyed_archetype`)**:
  * Reserved strictly for key landmark structures and story anchors (defaults to `null`).
* **Destruction Parameters**:
  * `material`: Material type (`earth`, `foliage`, `wood`, `stone`, `metal`, `crystal`, `spirit`, `cloth`).
  * `tier`: Required cultivation/tool tier to break (Tier 1: Mortal hands/tools, Tier 2: Refined tools, Tier 3: Foundation qi weapons, Tier 4: Spirit treasures).
  * `hp`: Health points before state transition.
  * `elemental_vulnerabilities`: Fire burns wood/foliage; Earth/Crushing shatters crystal and stone; Metal cuts wood; Acid/Corrosion pits metal.
  * `reveals_loot_category`: Item category dropped on destruction (`timber`, `stone`, `herb`, `ore`, `crystal`).

### D. Cultivation Leyline & Resource Fields
* **Five Elements & Qi Affinity**:
  * `element`: `wood`, `fire`, `earth`, `metal`, `water`, `spirit`, `void`, or `none`.
  * `qi_affinity`: `ambient_absorb`, `ambient_emit`, `condensed_vein`, or `neutral`.
  * `qi_density_modifier`: Multiplier on local cell spiritual concentration (e.g., $1.25\times$ for spirit bamboo, $2.0\times$ for cultivation altars).
  * `resonance_radius_cells`: Aura propagation distance in cells ($0\text{--}3$).
  * `feng_shui_direction`: Polarity of environmental Qi (`yin`, `yang`, `neutral`).
* **Resource Yields & State Reversion**:
  * `resource_type`: `herb`, `ore`, `crystal`, `timber`, `water`, `qi_shard`, or `relic`.
  * `base_yield`: Harvest quantity.
  * `respawn_turns`: Regeneration period ($0$ for non-renewable nodes until world reset).
  * `min_realm_tier`: Cultivation realm required to extract safely (Realms 1–30).
  * `harvest_tool_tag`: Tool requirement (`sickle`, `pickaxe`, `axe`, `spiritual_gourd`, `bare_hands`).
  * Harvest state preserves original archetype to enable non-destructive restoration upon seasonal cycles or game loading.

### E. Dynamic Size Profiles
* **Scale Separation**: Distinguishes **Visual Scale** (sprite size) from **Contact Scale** (trunk/base ground contact):
  * Props support discrete scale tiers: `[0.85, 1.0, 1.15, 1.35, 1.6]`.
  * Under `contact_rule: constant_subcell`, an ancient tree scaled up to $1.25\times$ expands its visual canopy while its physical trunk remains clamped to $1$ sub-cell ($32\text{ px}$).
  * Only when visual scale crosses major thresholds ($> 1.35\times$) does the blocked cell footprint step up.

---

## 3. Tool Scripts & Pipelines

The skill bundle provides tested Python tools under `scripts/`:

```
.agents/skills/map-asset-pipeline/
  ├── SKILL.md
  ├── references/
  │     └── data-matrix-spec.md    # Master specification of all data fields
  └── scripts/
        ├── semantics.py           # Per-archetype authored semantics (65 roles)
        ├── derive.py              # Raster coverage & multi-layer matrix generator
        ├── audit.py               # Structural quality gates for occlusion & passability
        └── subcell.py             # 32px contact patch extractor & trunk rect calculator
```

### Derivation & Audit Execution:
```bash
# 1. Derive cell coverage matrices, projectile/vision masks, and destruction data
uv run python .agents/skills/map-asset-pipeline/scripts/derive.py

# 2. Calculate 32px sub-cell contact patch and narrow trunk rects
uv run python .agents/skills/map-asset-pipeline/scripts/subcell.py

# 3. Audit all matrix rules and ensure zero occluder leakage
uv run python .agents/skills/map-asset-pipeline/scripts/audit.py
```

---

## 4. Main Toolchain Integration

Map assets integrate with the root tools runner:
```bash
# Check catalog coverage across 19 environments and 9 categories
uv run python -m tools assets map report

# Select next 12 underrepresented map assets prioritizing gaps
uv run python -m tools assets map next --count 12

# Audit map asset index integrity
uv run python -m tools assets map audit
```
