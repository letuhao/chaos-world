# -*- coding: utf-8 -*-
"""Master Scaffolding Orchestrator for Medieval Western Pack (5,000 Assets).

Assembles and validates 5,000 comprehensive assets across 22 categories:
  - Loads categories from game/assets/packs/medieval_western/categories.json
  - Executes modular category generators (Part 1, Part 2, Part 3)
  - Enforces 100% semantic uniqueness (IDs, English names, Vietnamese names)
  - Emits game/assets/packs/medieval_western/medieval_western_pack.json
  - Registers the pack in game/assets/packs/index.json
  - Prepares subdirectories for runtime, data, and original caches
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

PACK_DIR = REPO_ROOT / "game/assets/packs/medieval_western"
MANIFEST_PATH = PACK_DIR / "medieval_western_pack.json"
CATEGORIES_PATH = PACK_DIR / "categories.json"
PACKS_INDEX_PATH = REPO_ROOT / "game/assets/packs/index.json"


def make_asset(
    cat_id: str,
    slug: str,
    name: str,
    vn_name: str,
    sub_cat: str,
    footprint: list[int],
    collision: str,
    blocks_proj: bool,
    vision: str,
    verb: str | None,
    role: str,
    destructible: bool,
    material: str,
    culture: str,
    prompt: str,
    asset_type: str = "prop",
    alpha: str = "cutout",
    pivot: str = "bottom_center",
    hooks: dict | None = None,
) -> dict:
    return {
        "id": f"medieval_western.{cat_id}.{slug}",
        "name": name,
        "vietnamese_name": vn_name,
        "category": cat_id,
        "sub_category": sub_cat,
        "type": asset_type,
        "alpha": alpha,
        "pivot": pivot,
        "footprint_cells": footprint,
        "canvas_px": [footprint[0] * 128, footprint[1] * 128],
        "collision_type": collision,
        "blocks_projectile": blocks_proj,
        "vision_mode": vision,
        "interactive_verb": verb,
        "gameplay_role": role,
        "destructible": destructible,
        "material": material,
        "feudal_culture": culture,
        "prompt_summary": prompt,
        "racial_faction": "western_human_kingdom",
        "environment_name": "Medieval Western Feudal World (Lãnh Địa Phong Kiến Tây Âu)",
        "environment_theme": (
            "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), "
            "grounded European medieval palette."
        ),
        "world_tier": "Western Feudal Realm (Trung Cổ Phương Tây)",
        "status": "planned",
        "reference_ids": ["docs/art-direction.md#top-down-world-map"],
        "source": (
            "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, "
            "lora: krea2/Scottie__Krea2.safetensors (1.0)"
        ),
        "license": "Generated locally; source checkpoint license terms apply",
        "gameplay_gap_hooks": hooks or {},
    }


def main():
    print("=" * 80)
    print("SCAFFOLDING MEDIEVAL WESTERN PACK (TARGET: 5,000 ASSETS)")
    print("=" * 80)

    # 1. Load categories
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories = json.load(f)

    target_total = sum(c["planned_count"] for c in categories)
    print(f"Loaded {len(categories)} categories. Target total: {target_total}")
    assert target_total == 5000, f"Expected 5,000 assets, found {target_total}"

    # 2. Import generators
    from tools.medieval_categories_part1 import generate_part1
    from tools.medieval_categories_part2 import generate_part2
    from tools.medieval_categories_part3 import generate_part3

    all_assets: list[dict] = []
    t0 = time.time()

    p1 = generate_part1(make_asset)
    print(f"  Part 1 (Cats 1-7) generated:   {len(p1)} assets")
    all_assets.extend(p1)

    p2 = generate_part2(make_asset)
    print(f"  Part 2 (Cats 8-15) generated:  {len(p2)} assets")
    all_assets.extend(p2)

    p3 = generate_part3(make_asset)
    print(f"  Part 3 (Cats 16-22) generated: {len(p3)} assets")
    all_assets.extend(p3)

    print(f"Total generated: {len(all_assets)} in {time.time() - t0:.2f}s")
    assert len(all_assets) == 5000, f"Expected 5,000, got {len(all_assets)}"

    # 3. Validation checks
    ids = [a["id"] for a in all_assets]
    names = [a["name"] for a in all_assets]
    vns = [a["vietnamese_name"] for a in all_assets]

    print("\n--- VALIDATION ---")
    print(f"Unique IDs:     {len(set(ids))} / {len(all_assets)}")
    print(f"Unique English: {len(set(names))} / {len(all_assets)}")
    print(f"Unique VN:      {len(set(vns))} / {len(all_assets)}")

    assert len(set(ids)) == 5000, "Duplicate IDs detected!"
    assert len(set(names)) == 5000, "Duplicate English names detected!"
    assert len(set(vns)) == 5000, "Duplicate Vietnamese names detected!"

    # Category count validation
    cat_counts = {}
    for a in all_assets:
        cat_counts[a["category"]] = cat_counts.get(a["category"], 0) + 1

    for c in categories:
        cid = c["id"]
        exp = c["planned_count"]
        act = cat_counts.get(cid, 0)
        assert act == exp, f"Category {cid}: expected {exp}, got {act}"

    print("All category allocations strictly match categories.json planned counts!")

    # 4. Construct manifest
    manifest = {
        "pack_id": "medieval_western",
        "pack_name": "Medieval Western Feudal & Chivalric World: Lãnh Địa Phong Kiến & Hiệp Sĩ",
        "vietnamese_title": "Gói Tài Nguyên Thế Giới Trung Cổ Phương Tây: Lãnh Địa Phong Kiến & Hiệp Sĩ",
        "version": "1.0.0",
        "world_tier": "Western Feudal Realm (Trung Cổ Phương Tây)",
        "reference_unit_px": 128,
        "subcell_unit_px": 32,
        "art_style": (
            "2D Orthographic top-down (~45 degrees), gouache hand-painted, ink contour lines (#263A35), "
            "European medieval palette (ashlar limestone #8A8D8F, slate blue #4A5568, oak timber #5C4033, "
            "heraldic vermilion #9B2C2C, royal azure #2B6CB0, lion gold #D69E2E, thatch straw #C7A75C)."
        ),
        "approved_generation_recipe": {
            "unet_checkpoint": "krea2/raySemiReal_krea2TurboV1Nsfw.safetensors",
            "primary_lora": "krea2/Scottie__Krea2.safetensors",
            "primary_lora_node": "917",
            "primary_lora_weight": 1.0,
            "sampler": "euler_ancestral",
            "scheduler": "beta",
            "steps": 8,
            "cfg": 1.0,
            "rembg_model": "RMBG-2.0"
        },
        "supported_gameplay_modes": [
            "Feudal RPG Combat & Jousting Melee",
            "Manorial Economy & Feudal Simulation",
            "Castle Construction & Siege Warfare",
            "Guild Crafting & Trade Logistics"
        ],
        "total_assets": 5000,
        "categories": categories,
        "assets": all_assets
    }

    # 5. Write manifest file
    print(f"\nWriting manifest to: {MANIFEST_PATH}")
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print("Manifest successfully saved!")

    # 6. Ensure category folders in runtime, data, original
    print("\nEnsuring subdirectories for all 22 categories...")
    for c in categories:
        cid = c["id"]
        (PACK_DIR / "runtime" / cid).mkdir(parents=True, exist_ok=True)
        (PACK_DIR / "data" / cid).mkdir(parents=True, exist_ok=True)
        (PACK_DIR / "original" / cid).mkdir(parents=True, exist_ok=True)
    print("Category subdirectories created!")

    # 7. Update packs index.json registry
    if PACKS_INDEX_PATH.exists():
        with open(PACKS_INDEX_PATH, "r", encoding="utf-8") as f:
            index_data = json.load(f)

        packs = index_data.get("packs", [])
        existing_ids = {p.get("pack_id") for p in packs}

        # Also add ancient_china_mortal if missing
        if "ancient_china_mortal" not in existing_ids:
            packs.append({
                "pack_id": "ancient_china_mortal",
                "asset_count": 2280,
                "has_manifest": True
            })

        # Add medieval_western
        if "medieval_western" not in existing_ids:
            packs.append({
                "pack_id": "medieval_western",
                "asset_count": 5000,
                "has_manifest": True
            })
        else:
            for p in packs:
                if p.get("pack_id") == "medieval_western":
                    p["asset_count"] = 5000
                    p["has_manifest"] = True

        index_data["packs"] = packs
        index_data["total_packs"] = len(packs)
        index_data["total_assets"] = sum(p.get("asset_count", 0) for p in packs)

        with open(PACKS_INDEX_PATH, "w", encoding="utf-8") as f:
            json.dump(index_data, f, indent=2, ensure_ascii=False)
        print(f"Updated packs registry: {len(packs)} packs, {index_data['total_assets']} total registered assets.")

    print("\n" + "=" * 80)
    print("SCAFFOLDING COMPLETED SUCCESSFULLY!")
    print("=" * 80)


if __name__ == "__main__":
    main()
