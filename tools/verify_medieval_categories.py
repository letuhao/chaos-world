# -*- coding: utf-8 -*-
"""Verification script for Medieval Western 48 Categories."""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CATEGORIES_PATH = REPO_ROOT / "game/assets/packs/medieval_western/categories.json"

def main():
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories = json.load(f)

    print(f"Total categories: {len(categories)}")
    total_assets = sum(c["planned_count"] for c in categories)
    print(f"Total planned assets: {total_assets}")

    spheres = {}
    all_subs = []
    cat_ids = []

    for c in categories:
        cid = c["id"]
        cat_ids.append(cid)
        s = c["sphere"]
        spheres.setdefault(s, []).append(c)
        all_subs.extend(c["sub_categories"])

    print(f"Total subcategories: {len(all_subs)} (Unique: {len(set(all_subs))})")
    print(f"Unique Category IDs: {len(set(cat_ids))}")

    print("\nBreakdown by Sphere:")
    for s_name, cats in spheres.items():
        s_count = sum(c["planned_count"] for c in cats)
        print(f"  [{s_name}]: {len(cats)} categories, {s_count} assets")
        for c in cats:
            print(f"    - {c['id']} ({c['planned_count']}): {len(c['sub_categories'])} subs")

    assert len(categories) == 48, f"Expected 48 categories, found {len(categories)}"
    assert total_assets == 5600, f"Expected 5,600 assets, found {total_assets}"
    assert len(all_subs) == len(set(all_subs)), "Duplicate subcategory found!"
    assert len(cat_ids) == len(set(cat_ids)), "Duplicate category ID found!"
    print("\n[SUCCESS] Categories verification passed 100%!")

if __name__ == "__main__":
    main()
