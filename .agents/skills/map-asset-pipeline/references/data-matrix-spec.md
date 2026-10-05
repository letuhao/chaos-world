# World Map Asset Data Matrix Specification

This document defines the normative data structure, schemas, and semantic invariants for all Chaos World top-down map assets. It bridges raw generative art cutouts and engine gameplay systems (Godot 4 action RPG with cultivation, pathfinding, combat physics, environmental destruction, and domain management).

---

## 1. Storage & Provenance Contract

To prevent git repository bloat while preserving 100% loss-free derivation reversibility:

| Tier | Path | VCS Status | Description |
| :--- | :--- | :--- | :--- |
| **Original (Lossless)** | `art-source/map-originals/<env>/<cat>/<asset_id>__<sha256_16>.png` | **Gitignored** | Full-resolution ComfyUI output (1024–2048px) containing generation metadata (prompt, seed, model parameters). |
| **Runtime (Lossy/Trimmed)** | `game/assets/world_map/<env>/<cat>/<suffix>.png` | **Committed** | Scaled, alpha-trimmed, alpha-padded ($16\text{px}$ border, bottom-aligned) runtime sprite fitted to cell multiples ($128\text{px}$). |
| **Index (Ledger)** | `game/assets/map-asset-index.jsonl` | **Committed** | Single source of truth registering every asset, its authored grid footprint, and the SHA-256 digest of its source image. |

### Reversibility Invariant
Every committed runtime asset must trace to its raw source via `source_images[].sha256`. If alpha erode passes, cutout algorithms, or color grading are refined in future iterations, runtime assets are re-derived deterministically without regenerating prompts:
```bash
uv run python -m tools assets map recover-originals
uv run python .agents/skills/map-asset-pipeline/scripts/derive.py
```

---

## 2. Master Asset Data Schema

When processed by `derive.py` and `subcell.py`, every asset produces a structured dictionary matching the JSON specification below:

```json
{
  "id": "mortal_greenwood.settlement_and_domain_prop.storehouse",
  "archetype": "settlement_and_domain_prop.storehouse",
  "category": "settlement_and_domain_prop",
  "environment": "mortal_greenwood",
  "path": "res://assets/world_map/mortal_greenwood/settlement_and_domain_prop/storehouse.png",
  "canvas_px": [512, 512],
  "cell_px": 128,
  "grid": [4, 4],
  "pivot": [256, 512],
  "coverage": [
    [0.0, 0.12, 0.45, 0.0],
    [0.15, 0.88, 0.95, 0.22],
    [0.42, 1.0, 1.0, 0.55],
    [0.11, 0.92, 0.94, 0.18]
  ],
  "blocks": [
    [false, false, true, false],
    [false, true, true, false],
    [true, true, true, true],
    [false, true, true, false]
  ],
  "walk_surface": [
    [false, false, false, false],
    [false, false, false, false],
    [false, false, false, false],
    [false, false, false, false]
  ],
  "block_cell_count": 8,
  "sem": {
    "archetype": "settlement_and_domain_prop.storehouse",
    "occluder_rule": "full_body",
    "cov_gate": 0.20,
    "small_cov_gate": 0.10,
    "passable_under": false,
    "walk_surface": false,
    "blocks_sight": true,
    "blocks_projectile": true,
    "vision_mode": "solid",
    "acoustic_profile": "wood",
    "material": "wood",
    "elevation": 1,
    "authored_open": "",
    "destructible": {
      "enabled": true,
      "tier": 2,
      "hp": 60,
      "on_destroy": "stone_and_ore.rubble",
      "unique_destroyed_archetype": null,
      "elemental_vulnerabilities": ["fire", "slash"],
      "reveals_loot_category": "timber"
    },
    "interact": {
      "verb": "enter",
      "reach_cells": 1,
      "from_adjacent": true
    },
    "cultivation": {
      "element": "wood",
      "qi_affinity": "ambient_absorb",
      "qi_density_modifier": 1.0,
      "resonance_radius_cells": 0,
      "feng_shui_direction": "neutral"
    },
    "resource": null,
    "scale_profile": {
      "min_scale": 0.85,
      "max_scale": 1.6,
      "default_scale": 1.0,
      "scale_mode": "stepped",
      "contact_rule": "constant_subcell"
    }
  }
}
```

---

## 3. Subsystem Field Definitions

### 3.1 Spatial & Collision Geometry

* **`grid`** `[cols: int, rows: int]`: Authored footprint in data cells ($128\times 128\text{ px}$).
* **`occluder_rule`** `str`:
  * `"ground_contact"`: Only the bottom cell row can block; all cells above are canopy overhang or upper trunk.
  * `"full_body"`: Standard solid body; cells block if alpha coverage $\ge \text{cov\_gate}$.
  * `"core_ring"`: Outer boundary blocks, central opening stays passable (doors, ruined arches, gates).
  * `"none"`: Never blocks navigation regardless of visual density (grass, decals, leaves, flowers).
* **`cov_gate`** `float`: Minimum alpha coverage threshold ($0.0\text{--}1.0$) for a cell to block. Defaults to $0.20$; single-cell props use $0.10$; ground-contact props use $0.02$.
* **`passable_under`** `bool`: `true` if characters can navigate beneath the upper sprite canopy/roof.
* **`walk_surface`** `bool`: `true` for bridges, ramps, and fallen logs that provide a valid walking surface above water or elevation drops.
* **`block_rect`** `[x0, y0, x1, y1] | null`: Precise sub-cell contact patch derived by `subcell.py` at $32\text{ px}$ resolution. Decouples narrow trunks ($30\text{ px}$) from wide canopies ($256\text{ px}$).

---

### 3.2 Combat, Projectiles & Vision (Cross-Genre Layer)

* **`blocks_projectile`** `bool`:
  * `false`: Arrows, throwing daggers, martial qi blasts, and flying swords can fly over this cell (e.g. low fences, streams, shallow water, low fallen logs, floor traps).
  * `true`: Solid obstacles that collide with and intercept projectiles (boulders, thick trees, walls).
* **`vision_mode`** `str`:
  * `"solid"`: Completely opaque to RayCast Line-of-Sight and Fog of War (walls, large cliffs).
  * `"canopy"`: Vision raycasts pass through underneath; canopy alpha fades when the player enters the footprint.
  * `"brush"`: Concealment zone (e.g., tall bamboo, shrubs, reed beds). Characters inside gain stealth; units outside cannot target or see inside unless within detection range.
  * `"transparent"`: Clear vision (open ground, paths, low details).
* **`acoustic_profile`** `str`: Footstep and impact sound group (`"earth"`, `"foliage"`, `"wood"`, `"stone"`, `"metal"`, `"crystal"`, `"water"`, `"spirit"`, `"cloth"`). Drives audio bus DSP filters and stealth detection radiuses.

---

### 3.3 Destruction & Interactive States (Cost-Optimized Hybrid Model)

To avoid astronomical image generation costs for hundreds of bespoke destroyed states:

* **Generic Fallback Archetype (`on_destroy`)**:
  * Instead of generating an individualized broken PNG for every rock, crate, and tree, destruction replaces the prop with a shared generic archetype:
    * Wood / Stone / Metal / Crystal $\to$ `"stone_and_ore.rubble"`
    * Earth / Mud $\to$ `"ground_tile.cracked_ground"`
    * Foliage / Crops $\to$ `"landmark_and_environment_detail.ground_decal"`
  * Swapping to the fallback immediately frees upper blocked cells and lowers elevation.
* **Unique Broken Archetypes (`unique_destroyed_archetype`)**:
  * Reserved strictly for high-impact landmarks, story shrines, or boss arena anchors (e.g. `"unique_ruined_altar"`). Defaults to `null`.
* **Break Requirements & Vulnerabilities**:
  * **`tier`** `int`: Required cultivation or tool grade:
    * Tier 1: Mortal hands / basic tools
    * Tier 2: Refined mortal iron / Qi Condensation stage
    * Tier 3: Foundation Establishment spiritual weapons
    * Tier 4: Core Formation / Spirit Treasure grade
  * **`hp`** `int`: Durability pool before transitioning to the destroyed state.
  * **`elemental_vulnerabilities`** `list[str]`: Extra damage multipliers (`"fire"`, `"water"`, `"earth"`, `"metal"`, `"wood"`, `"slash"`, `"crush"`, `"corrosion"`).
  * **`reveals_loot_category`** `str | null`: Item family dropped upon demolition (`"timber"`, `"ore"`, `"stone"`, `"herb"`).

---

### 3.4 Cultivation Leyline & Spiritual Resonance

Integrates world-map props into the cultivation progression loop (*Amazing Cultivation Simulator* / *Tale of Immortal* paradigms):

* **`element`** `str`: Five Elements system (`"metal"`, `"wood"`, `"water"`, `"fire"`, `"earth"`, `"spirit"`, `"void"`, `"none"`).
* **`qi_affinity`** `str`:
  * `"ambient_absorb"`: Siphon spiritual qi from the surrounding chunk (e.g. withered demonic trees).
  * `"ambient_emit"`: Radiates spiritual aura into neighboring cells (e.g. spirit springs, ancient spirit trees).
  * `"condensed_vein"`: Static leyline anchor cell; provides cultivation speed multipliers during breakthrough meditation.
  * `"neutral"`: Ordinary mundane matter.
* **`qi_density_modifier`** `float`: Base multiplier on cell spiritual density ($0.5\times\text{ to }3.0\times$).
* **`resonance_radius_cells`** `int`: Aura propagation radius in cells ($0\text{--}4$).
* **`feng_shui_direction`** `str`: Elemental polarity (`"yin"`, `"yang"`, `"neutral"`).

---

### 3.5 Resource Nodes & Reversibility

* **`resource_type`** `str`: Node classification (`"herb"`, `"ore"`, `"crystal"`, `"timber"`, `"water"`, `"qi_shard"`, `"relic"`).
* **`base_yield`** `int`: Base item quantity harvested.
* **`respawn_turns`** `int`: Turn count or in-game hours before the node regenerates. If $0$, non-renewable until world realm shifts.
* **`min_realm_tier`** `int`: Minimum character realm rank ($1\text{--}30$) required to harvest without backlash or destruction.
* **`harvest_tool_tag`** `str`: Tool requirement (`"sickle"`, `"pickaxe"`, `"spiritual_gourd"`, `"axe"`, `"bare_hands"`).
* **State Preservation & Reversibility**:
  * Harvested nodes maintain an in-memory state tracking `(cell_x, cell_y, original_archetype, depleted_turns_left)`.
  * Allows non-destructive restoration upon game load or seasonal spiritual resets.

---

### 3.6 Dynamic Scale Profiles

Decouples visual sprite scale from physical contact collision:

* **Tiers**: `[0.85, 1.0, 1.15, 1.35, 1.6]`.
* **`contact_rule`**:
  * `"constant_subcell"`: Between $0.85\times$ and $1.35\times$, physical trunk collision is locked to $1$ sub-cell ($32\text{ px}$). The canopy scales visually, but the player pathing corridor remains unaffected.
  * Only past the $1.35\times$ threshold does `rect_at_scale()` expand the blocked footprint.
* **`scale_mode`**: `"stepped"` (discrete tiers for deterministic collision pre-computation) vs `"constant"`.

---

## 4. Verification & Audit Invariants

The data matrix is verified by running:
```bash
uv run python .agents/skills/map-asset-pipeline/scripts/audit.py
```
All assets must satisfy:
1. **Zero Phantom Occlusion**: No cell may be marked `blocks=True` if measured alpha coverage $< \text{cov\_gate}$.
2. **Canopy Openings**: Tree canopies with `passable_under=True` must not have fully covered blocking cells.
3. **Bottom-Row Trunk Anchor**: Ground-contact props must never block rows above `rows - 1`.
4. **Footprint Narrowing**: $100\%$ of single-stem trees must block $\le 1$ cell wide at $1.0\times$ scale.
5. **Passable Archways**: Gates and arches with `core_ring` must maintain passable passage cells.
