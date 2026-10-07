# -*- coding: utf-8 -*-
"""Synchronize categories.json subcategories with the actual sphere generator subcategories."""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

CATEGORIES_PATH = REPO_ROOT / "game/assets/packs/medieval_western/categories.json"

from tools.medieval_scaffold_common import make_asset
from tools.medieval_sphere1_crossroads import generate_sphere1
from tools.medieval_sphere2_architecture import generate_sphere2
from tools.medieval_sphere3_faith import generate_sphere3
from tools.medieval_sphere4_supply_chains import generate_sphere4
from tools.medieval_sphere5_commerce import generate_sphere5
from tools.medieval_sphere6_warfare import generate_sphere6
from tools.medieval_sphere7_ecology import generate_sphere7


def main():
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories = json.load(f)

    all_assets = []
    all_assets.extend(generate_sphere1(make_asset))
    all_assets.extend(generate_sphere2(make_asset))
    all_assets.extend(generate_sphere3(make_asset))
    all_assets.extend(generate_sphere4(make_asset))
    all_assets.extend(generate_sphere5(make_asset))
    all_assets.extend(generate_sphere6(make_asset))
    all_assets.extend(generate_sphere7(make_asset))

    # Collect subcategories preserving appearance order
    gen_subs_by_cat = {}
    for a in all_assets:
        cid = a["category"]
        sub = a["sub_category"]
        if cid not in gen_subs_by_cat:
            gen_subs_by_cat[cid] = []
        if sub not in gen_subs_by_cat[cid]:
            gen_subs_by_cat[cid].append(sub)

    # Update categories list
    for c in categories:
        cid = c["id"]
        if cid in gen_subs_by_cat:
            c["sub_categories"] = gen_subs_by_cat[cid]

    with open(CATEGORIES_PATH, "w", encoding="utf-8") as f:
        json.dump(categories, f, indent=2, ensure_ascii=False)

    total_subs = sum(len(c["sub_categories"]) for c in categories)
    unique_subs = len(set(s for c in categories for s in c["sub_categories"]))

    print(f"[SUCCESS] Synchronized {len(categories)} categories in {CATEGORIES_PATH}!")
    print(f"Total subcategories: {total_subs}, Unique subcategories: {unique_subs}")
    assert total_subs == unique_subs == 250, f"Expected 250 unique subcategories, got {unique_subs}"


if __name__ == "__main__":
    main()
