# -*- coding: utf-8 -*-
"""Comprehensive Diversity & Quality Audit for Ancient Chinese Mortal World Pack.

Audits the 2,280 asset entries in `ancient_china_mortal_pack.json` across:
  1. Category & Subcategory Balance
  2. Footprint Grid & Aspect Ratio Diversity
  3. Collision Types & Vision Modes
  4. Material Distribution & Realism
  5. Cultivation Element Affinity
  6. Interactive Verbs & Destructibility
  7. Semantic Uniqueness (IDs, Slugs, English Names, Hanzi, Vietnamese)
  8. Prompt Richness & Vocabulary Breadth
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = REPO_ROOT / "game/assets/packs/ancient_china_mortal/ancient_china_mortal_pack.json"
REPORT_OUT = REPO_ROOT / "build/ancient_china_mortal_diversity_audit.json"


def audit_pack():
    if not PACK_PATH.exists():
        raise FileNotFoundError(f"Pack manifest not found: {PACK_PATH}")

    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    total_assets = len(assets)

    print("=" * 80)
    print(f"ANCIENT CHINESE MORTAL WORLD PACK - COMPREHENSIVE DIVERSITY AUDIT")
    print(f"Total Assets in Manifest: {total_assets}")
    print("=" * 80)

    # 1. Category & Subcategory Distribution
    cat_counts = collections.Counter()
    subcat_counts = collections.defaultdict(collections.Counter)
    status_counts = collections.Counter()

    # 2. Footprint Distribution
    footprint_counts = collections.Counter()
    footprint_area_counts = collections.Counter()

    # 3. Collision & Vision
    collision_counts = collections.Counter()
    blocks_proj_counts = collections.Counter()
    vision_counts = collections.Counter()

    # 4. Materials
    material_counts = collections.Counter()
    material_by_cat = collections.defaultdict(collections.Counter)

    # 5. Cultivation Elements
    element_counts = collections.Counter()
    element_by_cat = collections.defaultdict(collections.Counter)

    # 6. Interactivity & Verbs
    verb_counts = collections.Counter()
    destructible_counts = collections.Counter()
    role_counts = collections.Counter()

    # 7. Uniqueness
    ids = set()
    duplicate_ids = []
    names = set()
    duplicate_names = []
    hanzi_set = set()
    duplicate_hanzi = []
    vn_names = set()
    duplicate_vn = []

    # 8. Prompts & Vocabulary
    all_prompt_tokens = set()
    prompt_lengths = []

    for a in assets:
        aid = a.get("id", "")
        if aid in ids:
            duplicate_ids.append(aid)
        ids.add(aid)

        name = a.get("name", "")
        if name in names:
            duplicate_names.append((aid, name))
        names.add(name)

        hanzi = a.get("hanzi", "")
        if hanzi:
            if hanzi in hanzi_set:
                duplicate_hanzi.append((aid, hanzi))
            hanzi_set.add(hanzi)

        vn = a.get("vietnamese_name", "")
        if vn:
            if vn in vn_names:
                duplicate_vn.append((aid, vn))
            vn_names.add(vn)

        cid = a.get("category", "unknown")
        sub = a.get("sub_category", "unknown")
        cat_counts[cid] += 1
        subcat_counts[cid][sub] += 1
        status_counts[a.get("status", "unknown")] += 1

        fp = tuple(a.get("footprint_cells", [1, 1]))
        footprint_counts[fp] += 1
        footprint_area_counts[fp[0] * fp[1]] += 1

        col = a.get("collision_type", "none")
        collision_counts[col] += 1
        blocks_proj_counts[a.get("blocks_projectile", False)] += 1
        vision_counts[a.get("vision_mode", "normal")] += 1

        mat = a.get("material", "unknown")
        material_counts[mat] += 1
        material_by_cat[cid][mat] += 1

        elem = a.get("cultivation_element", "unknown")
        element_counts[elem] += 1
        element_by_cat[cid][elem] += 1

        verb = a.get("interactive_verb")
        verb_counts[verb if verb is not None else "(none)"] += 1
        destructible_counts[a.get("destructible", False)] += 1
        role_counts[a.get("gameplay_role", "unknown")] += 1

        prompt = a.get("prompt_summary", "")
        tokens = [t.strip(".,;:()[]\"'").lower() for t in prompt.split() if len(t) > 2]
        all_prompt_tokens.update(tokens)
        prompt_lengths.append(len(prompt.split()))

    # --- PRINT AUDIT FINDINGS ---
    print("\n--- 1. CATEGORY DISTRIBUTION ---")
    for cid, cnt in sorted(cat_counts.items(), key=lambda x: x[0]):
        sub_len = len(subcat_counts[cid])
        print(f"  [{cid:<32}] {cnt:>4} assets across {sub_len:>2} sub-categories")
    print(f"  Status breakdown: {dict(status_counts)}")

    print("\n--- 2. FOOTPRINT & AREA DISTRIBUTION ---")
    print("  Footprints (W x H cells):")
    for fp, cnt in sorted(footprint_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {fp[0]}x{fp[1]:<2} : {cnt:>4} ({pct:>5.1f}%)")
    print("  Cell Area (total tiles occupied):")
    for area, cnt in sorted(footprint_area_counts.items(), key=lambda x: x[0]):
        pct = (cnt / total_assets) * 100
        print(f"    Area {area:>2} tiles : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 3. COLLISION & VISION MODES ---")
    print("  Collision Type:")
    for col, cnt in sorted(collision_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {col:<18} : {cnt:>4} ({pct:>5.1f}%)")
    print(f"  Blocks Projectile : True={blocks_proj_counts[True]} ({blocks_proj_counts[True]/total_assets*100:.1f}%), False={blocks_proj_counts[False]}")
    print("  Vision Mode:")
    for vis, cnt in sorted(vision_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {vis:<22} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 4. MATERIAL DISTRIBUTION ---")
    for mat, cnt in sorted(material_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {mat:<16} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 5. CULTIVATION ELEMENT AFFINITY ---")
    for elem, cnt in sorted(element_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {elem:<14} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 6. INTERACTIVITY & GAMEPLAY ROLES ---")
    interactive_total = total_assets - verb_counts["(none)"]
    print(f"  Interactive Assets: {interactive_total} ({(interactive_total/total_assets)*100:.1f}%)")
    print("  Interactive Verbs (Top 15):")
    top_verbs = sorted([item for item in verb_counts.items() if item[0] != "(none)"], key=lambda x: -x[1])[:15]
    for v, cnt in top_verbs:
        print(f"    {v:<20} : {cnt:>4}")
    print(f"  Destructible Assets: {destructible_counts[True]} ({(destructible_counts[True]/total_assets)*100:.1f}%)")

    print("\n--- 7. UNIQUENESS CHECKS ---")
    print(f"  Unique Asset IDs     : {len(ids)} / {total_assets} (Duplicate IDs: {len(duplicate_ids)})")
    print(f"  Unique English Names : {len(names)} / {total_assets} (Duplicate Names: {len(duplicate_names)})")
    print(f"  Unique Hanzi         : {len(hanzi_set)} / {total_assets} (Duplicate Hanzi: {len(duplicate_hanzi)})")
    print(f"  Unique VN Names      : {len(vn_names)} / {total_assets} (Duplicate VN: {len(duplicate_vn)})")

    if duplicate_ids:
        print(f"  [ERROR] Found {len(duplicate_ids)} duplicate IDs! Sample: {duplicate_ids[:5]}")
    if duplicate_names:
        print(f"  [WARN] Found {len(duplicate_names)} duplicate English names. Sample: {duplicate_names[:5]}")
    if duplicate_hanzi:
        print(f"  [INFO] Found {len(duplicate_hanzi)} duplicate Hanzi names. Sample: {duplicate_hanzi[:5]}")
    if duplicate_vn:
        print(f"  [INFO] Found {len(duplicate_vn)} duplicate VN names. Sample: {duplicate_vn[:5]}")

    print("\n--- 8. PROMPT VOCABULARY RICHNESS ---")
    avg_len = sum(prompt_lengths) / len(prompt_lengths) if prompt_lengths else 0
    print(f"  Unique Vocabulary Tokens: {len(all_prompt_tokens)}")
    print(f"  Average Prompt Word Count: {avg_len:.1f} words (Min: {min(prompt_lengths)}, Max: {max(prompt_lengths)})")

    # Compile JSON report
    report = {
        "total_assets": total_assets,
        "categories": {cid: {"count": cnt, "subcategories": dict(subcat_counts[cid])} for cid, cnt in cat_counts.items()},
        "footprints": {f"{fp[0]}x{fp[1]}": cnt for fp, cnt in footprint_counts.items()},
        "areas": {str(a): cnt for a, cnt in footprint_area_counts.items()},
        "collisions": dict(collision_counts),
        "vision_modes": dict(vision_counts),
        "materials": dict(material_counts),
        "elements": dict(element_counts),
        "interactive_verbs": dict(verb_counts),
        "destructible": dict(destructible_counts),
        "uniqueness": {
            "duplicate_ids": len(duplicate_ids),
            "duplicate_names": len(duplicate_names),
            "duplicate_hanzi": len(duplicate_hanzi),
            "duplicate_vn": len(duplicate_vn),
        },
        "vocabulary_size": len(all_prompt_tokens),
        "avg_prompt_words": avg_len,
    }

    REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\nSaved detailed audit JSON report to: {REPORT_OUT}")
    print("=" * 80)
    return report


if __name__ == "__main__":
    audit_pack()
