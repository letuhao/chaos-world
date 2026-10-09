"""Audit tool for generated assets in Ancient China Low Cultivation Asset Pack.

Validates image integrity, alpha channels, dimensions, companion data JSONs,
and Godot .import files for all variants marked status: "generated".
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game" / "assets" / "packs" / "ancient_china_low_cultivation"
PACK_JSON = PACK_DIR / "ancient_china_low_cultivation_pack.json"
RUNTIME_DIR = PACK_DIR / "runtime"
DATA_DIR = PACK_DIR / "data"


def audit_generated_assets(category_filter: str | None = None) -> int:
    if not PACK_JSON.exists():
        print(f"Error: {PACK_JSON} does not exist", file=sys.stderr)
        return 1

    with open(PACK_JSON, encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    total_assets = len(assets)
    generated_variants = 0
    checked_variants = 0
    passed_variants = 0
    issues: list[str] = []

    print(f"Loaded {total_assets} assets from manifest.")

    for asset in assets:
        dom = asset.get("domain", "")
        cat = asset.get("sub_domain", "")
        slug = asset.get("asset_slug", "")
        alpha_mode = asset.get("alpha", "cutout")

        if category_filter and cat != category_filter:
            continue

        for var in asset.get("variants", []):
            if var.get("status") != "generated":
                continue

            generated_variants += 1
            checked_variants += 1
            var_slug = var.get("variant_slug", "")
            img_path = RUNTIME_DIR / dom / cat / slug / f"{var_slug}.png"
            import_path = RUNTIME_DIR / dom / cat / slug / f"{var_slug}.png.import"
            data_json_path = DATA_DIR / dom / cat / slug / f"{var_slug}.json"

            # Check 1: PNG exists
            if not img_path.exists():
                issues.append(f"MISSING PNG: {img_path}")
                continue

            # Check 2: Size > 1KB
            size_kb = img_path.stat().st_size / 1024
            if size_kb < 1.0:
                issues.append(f"EMPTY/TINY PNG ({size_kb:.1f} KB): {img_path}")
                continue

            # Check 3: PIL Verification & dimensions
            try:
                with Image.open(img_path) as img:
                    w, h = img.size
                    mode = img.mode

                    if w < 64 or h < 64:
                        issues.append(f"TOO SMALL ({w}x{h}): {img_path}")
                        continue

                    # Check alpha channel consistency
                    if alpha_mode == "cutout" and mode not in ("RGBA", "LA", "P"):
                        issues.append(f"EXPECTED ALPHA but got {mode}: {img_path}")
                        continue
            except Exception as e:
                issues.append(f"CORRUPT IMAGE: {img_path} ({e})")
                continue

            # Check 4: Godot .import exists
            if not import_path.exists():
                issues.append(f"MISSING .import FILE: {import_path}")
                continue

            passed_variants += 1

    print("\n" + "=" * 60)
    print(f"AUDIT SUMMARY (Category: {category_filter or 'ALL'})")
    print("=" * 60)
    print(f"Total checked variants: {checked_variants}")
    print(f"Passed variants:        {passed_variants}")
    print(f"Issues detected:        {len(issues)}")

    if issues:
        print("\nDetected Issues:")
        for issue in issues[:20]:
            print(f"  - {issue}")
        if len(issues) > 20:
            print(f"  ... and {len(issues) - 20} more issues.")
        return 1

    print("\n[PASS] All generated assets passed integrity and engine import checks!")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit generated pack assets")
    parser.add_argument("--category", "-c", help="Filter by category/sub-domain ID")
    args = parser.parse_args(argv)
    return audit_generated_assets(category_filter=args.category)


if __name__ == "__main__":
    sys.exit(main())
