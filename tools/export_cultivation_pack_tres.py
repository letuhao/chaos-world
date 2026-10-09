"""Export and Ingest Tool for Ancient China Low Cultivation Pack Godot Resources (.tres).

Exports the 4,260 asset specifications from ancient_china_low_cultivation_pack.json
into native Godot 4 CultivationAssetDef .tres resources under:
    game/assets/packs/ancient_china_low_cultivation/data/<domain>/<category>/<asset_slug>.tres

Allows Godot scenes, procedural map generators, and domain instances to load
assets directly via ResourceLoader.load() with complete schema typing.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/ancient_china_low_cultivation"
PACK_PATH = PACK_DIR / "ancient_china_low_cultivation_pack.json"
DATA_DIR = PACK_DIR / "data"

SCRIPT_PATH = "res://src/modules/worldmap/cultivation_asset_def.gd"


def escape_tres_str(val: str) -> str:
    return val.replace('"', '\\"').replace("\n", "\\n")


def format_tres_resource(asset: dict) -> str:
    aid = asset.get("id", "")
    name = escape_tres_str(asset.get("name", ""))
    py = escape_tres_str(asset.get("pinyin", ""))
    zh = escape_tres_str(asset.get("hanzi", ""))
    dom = asset.get("domain_id") or asset.get("domain", "")
    cat = asset.get("category_id") or asset.get("category", "")
    aclass = asset.get("asset_class", "prop")
    arch = escape_tres_str(asset.get("archetype_name", ""))

    runtime_rel = f"res://assets/packs/ancient_china_low_cultivation/runtime/{dom}/{cat}"
    slug = asset.get("asset_slug") or aid.split(".")[-1]

    # Texture path default to primary variant
    variants = asset.get("variants", [])
    first_var = variants[0].get("variant_slug", "default") if variants else "default"
    tex_path = f"{runtime_rel}/{slug}/{first_var}.png"

    fp = asset.get("footprint_cells", [1, 1])
    fp_x, fp_y = int(fp[0]), int(fp[1])

    canvas = asset.get("canvas_px") or [fp_x * 128, fp_y * 128]
    px_w, px_h = int(canvas[0]), int(canvas[1])

    col = asset.get("collision_type", "solid")
    prim_mat = asset.get("primary_material", "carved_wood")
    sec_mat = asset.get("secondary_material", "glazed_tile")
    element = asset.get("cultivation_element", "earth")
    elev = int(asset.get("elevation_tier", 1))
    realm = escape_tres_str(asset.get("mortal_realm_tier", "Qi Refining"))
    verb = asset.get("interactive_verb", "examine")

    lines = [
        '[gd_resource type="Resource" script_class="CultivationAssetDef" load_steps=2 format=3]',
        "",
        f'[ext_resource type="Script" path="{SCRIPT_PATH}" id="1_cdef"]',
        "",
        "[resource]",
        'script = ExtResource("1_cdef")',
        f'id = &"{aid}"',
        f'display_name = "{name}"',
        f'pinyin = "{py}"',
        f'hanzi = "{zh}"',
        f'domain_id = &"{dom}"',
        f'category_id = &"{cat}"',
        f'asset_class = &"{aclass}"',
        f'archetype_name = "{arch}"',
        f'texture_path = "{tex_path}"',
        f"footprint_cells = Vector2i({fp_x}, {fp_y})",
        f"canvas_px = Vector2i({px_w}, {px_h})",
        f'collision_type = &"{col}"',
        f'primary_material = &"{prim_mat}"',
        f'secondary_material = &"{sec_mat}"',
        f'cultivation_element = &"{element}"',
        f"elevation_tier = {elev}",
        f'mortal_realm_tier = "{realm}"',
        f'interactive_verb = &"{verb}"',
    ]
    return "\n".join(lines) + "\n"


def export_pack_tres(
    domain_filter: str | None = None,
    category_filter: str | None = None,
    limit: int | None = None,
    dry_run: bool = False,
    audit_only: bool = False,
) -> int:
    print("=" * 80)
    print("GODOT ENGINE RESOURCE EXPORT & INGEST AUDIT (.tres)")
    print("=" * 80)

    if not PACK_PATH.exists():
        print(f"Error: manifest not found at {PACK_PATH}", file=sys.stderr)
        return 1

    with open(PACK_PATH, encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    print(f"Loaded {len(assets)} asset specifications from pack manifest.")

    filtered_assets = []
    for a in assets:
        dom = a.get("domain_id") or a.get("domain", "")
        cat = a.get("category_id") or a.get("category", "")
        if domain_filter and dom != domain_filter:
            continue
        if category_filter and cat != category_filter:
            continue
        filtered_assets.append(a)

    if limit:
        filtered_assets = filtered_assets[:limit]

    print(f"Targets to process: {len(filtered_assets)} assets.")

    if audit_only:
        print("\nAuditing existing .tres files under data/...")
        existing_count = 0
        missing_count = 0
        for a in filtered_assets:
            dom = a.get("domain_id") or a.get("domain", "")
            cat = a.get("category_id") or a.get("category", "")
            slug = a.get("asset_slug") or a.get("id", "").split(".")[-1]
            tres_path = DATA_DIR / dom / cat / f"{slug}.tres"
            if tres_path.is_file():
                existing_count += 1
            else:
                missing_count += 1
        print(f"Audit Result: {existing_count} existing, {missing_count} missing .tres files.")
        return 0

    if dry_run:
        print("\n--- DRY RUN: Export Targets Sample ---")
        for idx, a in enumerate(filtered_assets[:5], 1):
            dom = a.get("domain_id") or a.get("domain", "")
            cat = a.get("category_id") or a.get("category", "")
            slug = a.get("asset_slug") or a.get("id", "").split(".")[-1]
            tres_path = DATA_DIR / dom / cat / f"{slug}.tres"
            print(f"[{idx}] {a.get('id')} -> {tres_path.relative_to(REPO_ROOT)}")
        return 0

    t0 = time.time()
    exported_count = 0

    for _idx, a in enumerate(filtered_assets, 1):
        dom = a.get("domain_id") or a.get("domain", "")
        cat = a.get("category_id") or a.get("category", "")
        slug = a.get("asset_slug") or a.get("id", "").split(".")[-1]

        target_dir = DATA_DIR / dom / cat
        target_dir.mkdir(parents=True, exist_ok=True)

        tres_path = target_dir / f"{slug}.tres"
        content = format_tres_resource(a)
        tres_path.write_text(content, encoding="utf-8")
        exported_count += 1

    dt = time.time() - t0
    print(f"\n[OK] Successfully exported {exported_count} .tres resources in {dt:.2f}s!")
    print(f"Location: {DATA_DIR.relative_to(REPO_ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Export cultivation pack assets to Godot .tres")
    parser.add_argument("--domain", type=str, default=None, help="Filter by domain ID")
    parser.add_argument("--category", type=str, default=None, help="Filter by category ID")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of assets exported")
    parser.add_argument("--dry-run", action="store_true", default=False, help="Dry run only")
    parser.add_argument("--audit", action="store_true", default=False, help="Audit existing files")
    args = parser.parse_args()

    return export_pack_tres(
        domain_filter=args.domain,
        category_filter=args.category,
        limit=args.limit,
        dry_run=args.dry_run,
        audit_only=args.audit,
    )


if __name__ == "__main__":
    raise SystemExit(main())
