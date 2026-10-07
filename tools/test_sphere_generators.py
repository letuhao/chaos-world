# -*- coding: utf-8 -*-
"""Verification script for sphere generators."""

import sys
from pathlib import Path
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.medieval_scaffold_common import make_asset

def verify_items(items: list[dict], expected_count: int, sphere_name: str):
    print(f"\nVerifying {sphere_name} ({len(items)} / {expected_count} expected)...")
    assert len(items) == expected_count, f"{sphere_name}: expected {expected_count}, got {len(items)}"

    # Check ID uniqueness
    ids = [x["id"] for x in items]
    assert len(set(ids)) == len(ids), f"Duplicate IDs in {sphere_name}!"

    # Check category name and VN uniqueness
    cats = set(x["category"] for x in items)
    for c in cats:
        c_items = [x for x in items if x["category"] == c]
        names = [x["name"] for x in c_items]
        vns = [x["vietnamese_name"] for x in c_items]
        assert len(set(names)) == len(names), f"Duplicate English names in {c}!"
        assert len(set(vns)) == len(vns), f"Duplicate VN names in {c}!"

    print(f"  [SUCCESS] {sphere_name} passed all uniqueness and budget checks!")

if __name__ == "__main__":
    from tools.medieval_sphere1_crossroads import generate_sphere1
    s1 = generate_sphere1(make_asset)
    verify_items(s1, 900, "Sphere 1: Cultural Crossroads")

    from tools.medieval_sphere2_architecture import generate_sphere2
    s2 = generate_sphere2(make_asset)
    verify_items(s2, 800, "Sphere 2: Built Architecture")

    from tools.medieval_sphere3_faith import generate_sphere3
    s3 = generate_sphere3(make_asset)
    verify_items(s3, 760, "Sphere 3: Faith & Mortality")

    from tools.medieval_sphere4_supply_chains import generate_sphere4
    s4 = generate_sphere4(make_asset)
    verify_items(s4, 1140, "Sphere 4: Manorial Supply Chains")

    from tools.medieval_sphere5_commerce import generate_sphere5
    s5 = generate_sphere5(make_asset)
    verify_items(s5, 590, "Sphere 5: Commerce & Urban Life")

    from tools.medieval_sphere6_warfare import generate_sphere6
    s6 = generate_sphere6(make_asset)
    verify_items(s6, 540, "Sphere 6: War & Underworld")

    from tools.medieval_sphere7_ecology import generate_sphere7
    s7 = generate_sphere7(make_asset)
    verify_items(s7, 870, "Sphere 7: Ecology & Living Traces")

    total = len(s1) + len(s2) + len(s3) + len(s4) + len(s5) + len(s6) + len(s7)
    print(f"\nGRAND TOTAL ACROSS ALL 7 SPHERES: {total} / 5600 planned assets")
    assert total == 5600, f"Expected 5600, got {total}"
    print("[ALL CHECKS PASSED PERFECTLY!]")
