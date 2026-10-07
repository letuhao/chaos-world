# -*- coding: utf-8 -*-
"""Master Scaffolding Orchestrator for Medieval Western 48-Category Pack (5,600 Assets).

Assembles and validates 5,600 comprehensive assets across 48 categories and 7 Life Spheres:
  - Loads categories from game/assets/packs/medieval_western/categories.json
  - Executes modular sphere generators (Spheres 1 to 7)
  - Enforces 100% semantic uniqueness (IDs, English names, Vietnamese names)
  - Emits game/assets/packs/medieval_western/medieval_western_pack.json
  - Updates game/assets/packs/index.json
  - Ensures runtime, data, and original category folders are prepared
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


def main():
    print("=" * 80)
    print("SCAFFOLDING MEDIEVAL WESTERN 48-CATEGORY PACK (TARGET: 5,600 ASSETS)")
    print("=" * 80)

    # 1. Load categories
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories = json.load(f)

    target_total = sum(c["planned_count"] for c in categories)
    print(f"Loaded {len(categories)} categories. Target total: {target_total}")
    assert len(categories) == 48, f"Expected 48 categories, found {len(categories)}"
    assert target_total == 5600, f"Expected 5,600 assets, found {target_total}"

    # 2. Import generators
    from tools.medieval_scaffold_common import make_asset
    from tools.medieval_sphere1_crossroads import generate_sphere1
    from tools.medieval_sphere2_architecture import generate_sphere2
    from tools.medieval_sphere3_faith import generate_sphere3
    from tools.medieval_sphere4_supply_chains import generate_sphere4
    from tools.medieval_sphere5_commerce import generate_sphere5
    from tools.medieval_sphere6_warfare import generate_sphere6
    from tools.medieval_sphere7_ecology import generate_sphere7

    all_assets: list[dict] = []
    t0 = time.time()

    print("\n--- GENERATING 7 LIFE SPHERES ---")
    s1 = generate_sphere1(make_asset)
    print(f"  Sphere 1 (Cultural Crossroads):        {len(s1)} assets")
    all_assets.extend(s1)

    s2 = generate_sphere2(make_asset)
    print(f"  Sphere 2 (Built Architecture):         {len(s2)} assets")
    all_assets.extend(s2)

    s3 = generate_sphere3(make_asset)
    print(f"  Sphere 3 (Faith & Mortality):          {len(s3)} assets")
    all_assets.extend(s3)

    s4 = generate_sphere4(make_asset)
    print(f"  Sphere 4 (Manorial Supply Chains):     {len(s4)} assets")
    all_assets.extend(s4)

    s5 = generate_sphere5(make_asset)
    print(f"  Sphere 5 (Commerce & Urban Life):      {len(s5)} assets")
    all_assets.extend(s5)

    s6 = generate_sphere6(make_asset)
    print(f"  Sphere 6 (War & Underworld):           {len(s6)} assets")
    all_assets.extend(s6)

    s7 = generate_sphere7(make_asset)
    print(f"  Sphere 7 (Ecology & Living Traces):    {len(s7)} assets")
    all_assets.extend(s7)

    print(f"\nTotal generated: {len(all_assets)} in {time.time() - t0:.2f}s")
    assert len(all_assets) == 5600, f"Expected 5,600, got {len(all_assets)}"

    # 3. Validation checks
    ids = [a["id"] for a in all_assets]
    names = [a["name"] for a in all_assets]
    vns = [a["vietnamese_name"] for a in all_assets]

    print("\n--- VALIDATION ---")
    print(f"Unique IDs:             {len(set(ids))} / {len(all_assets)}")
    print(f"Unique English Names:   {len(set(names))} / {len(all_assets)}")
    print(f"Unique VN Names:        {len(set(vns))} / {len(all_assets)}")

    assert len(set(ids)) == 5600, f"Duplicate IDs detected! Found {len(set(ids))} unique."
    assert len(set(names)) == 5600, f"Duplicate English names detected! Found {len(set(names))} unique."
    assert len(set(vns)) == 5600, f"Duplicate Vietnamese names detected! Found {len(set(vns))} unique."

    # Category count validation
    cat_counts = {}
    for a in all_assets:
        cat_counts[a["category"]] = cat_counts.get(a["category"], 0) + 1

    for c in categories:
        cid = c["id"]
        exp = c["planned_count"]
        act = cat_counts.get(cid, 0)
        assert act == exp, f"Category {cid}: expected {exp}, got {act}"

    print("All 48 category allocations strictly match categories.json planned counts!")

    # Subcategory representation validation
    sub_counts = {}
    for a in all_assets:
        sub_counts[a["sub_category"]] = sub_counts.get(a["sub_category"], 0) + 1

    all_defined_subs = [s for c in categories for s in c["sub_categories"]]
    for sub in all_defined_subs:
        assert sub in sub_counts, f"Subcategory {sub} has 0 generated assets!"
        assert sub_counts[sub] > 0, f"Subcategory {sub} has 0 assets!"

    print(f"All {len(all_defined_subs)} subcategories are fully represented and populated!")

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
            "rembg_model": "RMBG-2.0",
        },
        "supported_gameplay_modes": [
            "Feudal RPG Combat & Jousting Melee",
            "Manorial Economy & Feudal Simulation",
            "Castle Construction & Siege Warfare",
            "Guild Crafting & Trade Logistics",
            "Monastic Life, Pilgrimage & Alchemy",
            "Wilderness Exploration & Living Ecology",
        ],
        "total_categories": len(categories),
        "total_assets": len(all_assets),
        "categories": categories,
        "assets": all_assets,
    }

    print(f"\nWriting master pack manifest to: {MANIFEST_PATH}...")
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    file_size_mb = MANIFEST_PATH.stat().st_size / (1024 * 1024)
    print(f"Manifest written successfully! ({file_size_mb:.2f} MB)")

    # 5. Update index.json
    print(f"\nUpdating {PACKS_INDEX_PATH}...")
    with open(PACKS_INDEX_PATH, "r", encoding="utf-8") as f:
        packs_index = json.load(f)

    found = False
    for p in packs_index.get("packs", []):
        if p.get("pack_id") == "medieval_western":
            p["asset_count"] = len(all_assets)
            p["has_manifest"] = True
            found = True
            break

    if not found:
        packs_index["packs"].append({
            "pack_id": "medieval_western",
            "asset_count": len(all_assets),
            "has_manifest": True,
        })

    packs_index["total_packs"] = len(packs_index["packs"])
    packs_index["total_assets"] = sum(p["asset_count"] for p in packs_index["packs"])

    with open(PACKS_INDEX_PATH, "w", encoding="utf-8") as f:
        json.dump(packs_index, f, indent=2, ensure_ascii=False)
    print(f"Packs index updated! Total packs: {packs_index['total_packs']}, Total assets: {packs_index['total_assets']}")

    # 6. Verify directory structure
    for prefix in ["runtime", "data", "original"]:
        for c in categories:
            d = PACK_DIR / prefix / c["id"]
            d.mkdir(parents=True, exist_ok=True)
    print("Verified runtime, data, and original directories for all 48 categories.")

    print("\n" + "=" * 80)
    print("[SUCCESS] MEDIEVAL WESTERN 48-CATEGORY PACK SCAFFOLDING COMPLETE!")
    print("=" * 80)


if __name__ == "__main__":
    main()
