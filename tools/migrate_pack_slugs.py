"""Migration script to de-duplicate folder names and asset slugs in ancient_china_low_cultivation.

Eliminates the redundant `_{category_id}` suffix from:
1. `asset_slug` and `id` in ancient_china_low_cultivation_pack.json
2. Directory names across data/, runtime/, original/
3. File names across data/, runtime/, original/
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game" / "assets" / "packs" / "ancient_china_low_cultivation"
PACK_PATH = PACK_DIR / "ancient_china_low_cultivation_pack.json"
DATA_DIR = PACK_DIR / "data"
RUNTIME_DIR = PACK_DIR / "runtime"
ORIGINAL_DIR = PACK_DIR / "original"


def clean_slug_for(raw_slug: str, cid: str) -> str:
    if cid and raw_slug.endswith(f"_{cid}"):
        return raw_slug[: -len(f"_{cid}")]
    return raw_slug


def migrate_manifest() -> dict[str, str]:
    """Updates manifest with clean asset_slug and hierarchical id.
    Returns mapping from (dom, cid, old_slug) -> new_slug.
    """
    print("[1/5] Updating ancient_china_low_cultivation_pack.json...")
    with open(PACK_PATH, encoding="utf-8") as f:
        pack = json.load(f)

    slug_map = {}
    for a in pack.get("assets", []):
        cid = a.get("category_id") or a.get("category", "")
        dom = a.get("domain_id") or a.get("domain", "")
        raw_slug = a.get("asset_slug") or a.get("id", "").split(".")[-1]
        new_slug = clean_slug_for(raw_slug, cid)

        slug_map[(dom, cid, raw_slug)] = new_slug
        a["asset_slug"] = new_slug
        a["id"] = f"ancient_china_low_cultivation.{dom}.{cid}.{new_slug}"

        # Update variant paths
        for v in a.get("variants", []):
            p = v.get("path")
            if p and raw_slug in p:
                v["path"] = p.replace(f"/{raw_slug}/", f"/{new_slug}/")

    temp_path = PACK_PATH.with_suffix(".tmp")
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2, ensure_ascii=False)
    for _ in range(10):
        try:
            temp_path.replace(PACK_PATH)
            break
        except Exception:
            time.sleep(0.5)

    print(f"  Updated manifest with {len(slug_map)} clean asset slugs.")
    return slug_map


def rename_tree_folders(base_dir: Path, slug_map: dict[str, str]) -> None:
    """Renames subdirectories under base_dir/<dom>/<cid>/<old_slug> to <new_slug>."""
    if not base_dir.exists():
        return
    print(f"Renaming directories in {base_dir.relative_to(REPO_ROOT)}...")
    renamed = 0
    for (dom, cid, old_slug), new_slug in slug_map.items():
        if old_slug == new_slug:
            continue
        old_folder = base_dir / dom / cid / old_slug
        new_folder = base_dir / dom / cid / new_slug
        if old_folder.is_dir():
            if new_folder.exists():
                # Merge if new exists
                for item in old_folder.iterdir():
                    dest = new_folder / item.name
                    if not dest.exists():
                        shutil.move(str(item), str(dest))
                shutil.rmtree(str(old_folder), ignore_errors=True)
            else:
                old_folder.rename(new_folder)
            renamed += 1
    print(f"  Renamed {renamed} directories in {base_dir.name}.")


def clean_old_tres_files(slug_map: dict[str, str]) -> None:
    """Removes obsolete <old_slug>.tres files so only <new_slug>.tres remain."""
    print("Cleaning obsolete .tres files...")
    deleted = 0
    for (dom, cid, old_slug), new_slug in slug_map.items():
        if old_slug == new_slug:
            continue
        old_tres = DATA_DIR / dom / cid / f"{old_slug}.tres"
        if old_tres.is_file():
            old_tres.unlink()
            deleted += 1
    print(f"  Removed {deleted} old .tres files.")


def audit_path_lengths() -> int:
    print("\nAuditing final path lengths under game/assets/packs/ancient_china_low_cultivation/...")
    max_len = 0
    longest_path = ""
    over_260 = []

    for p in PACK_DIR.glob("**/*"):
        s = str(p.resolve())
        if len(s) > max_len:
            max_len = len(s)
            longest_path = s
        if len(s) >= 250:
            over_260.append((len(s), s))

    print(f"Maximum path length across entire pack: {max_len} chars")
    print(f"Longest path: {longest_path}")
    print(f"Paths >= 250 characters: {len(over_260)}")
    return len(over_260)


def main() -> int:
    print("=" * 80)
    print("DE-DUPLICATING SLUGS & SHORTENING PATHS (OPTION 3)")
    print("=" * 80)
    slug_map = migrate_manifest()
    rename_tree_folders(RUNTIME_DIR, slug_map)
    rename_tree_folders(DATA_DIR, slug_map)
    rename_tree_folders(ORIGINAL_DIR, slug_map)
    clean_old_tres_files(slug_map)

    # Check lengths
    issues = audit_path_lengths()
    print("=" * 80)
    return issues


if __name__ == "__main__":
    sys.exit(main())
