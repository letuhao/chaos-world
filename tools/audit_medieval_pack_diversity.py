# -*- coding: utf-8 -*-
"""Comprehensive Diversity & Quality Audit for Medieval Western Pack.

Audits the 5,000 asset entries in `medieval_western_pack.json` across:
  1. Category & Subcategory Balance (22 categories)
  2. Footprint Grid & Aspect Ratio Diversity
  3. Collision Types & Vision Modes
  4. Material Distribution & Realism
  5. Feudal Culture Spectrum
  6. Interactive Verbs & Destructibility
  7. Semantic Uniqueness (IDs, Slugs, English Names, Vietnamese)
  8. Prompt Richness & Vocabulary Breadth
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = REPO_ROOT / "game/assets/packs/medieval_western/medieval_western_pack.json"
REPORT_OUT = REPO_ROOT / "build/medieval_western_diversity_audit.json"


def audit_pack():
    if not PACK_PATH.exists():
        raise FileNotFoundError(f"Pack manifest not found: {PACK_PATH}")

    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    total_assets = len(assets)

    print("=" * 80)
    print("MEDIEVAL WESTERN PACK - COMPREHENSIVE DIVERSITY AUDIT")
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
    vision_counts = collections.Counter()
    blocks_proj_counts = collections.Counter()

    # 4. Material & Culture
    material_counts = collections.Counter()
    culture_counts = collections.Counter()

    # 5. Interactive Verbs & Destructibles
    verb_counts = collections.Counter()
    destructible_count = 0

    # 6. Uniqueness
    ids = set()
    dup_ids = set()
    names = set()
    dup_names = set()
    vns = set()
    dup_vns = set()

    # 7. Vocabulary
    vocab_tokens = set()
    prompt_lengths = []

    for a in assets:
        aid = a.get("id", "")
        if aid in ids:
            dup_ids.add(aid)
        ids.add(aid)

        name = a.get("name", "")
        if name in names:
            dup_names.add(name)
        names.add(name)

        vn = a.get("vietnamese_name", "")
        if vn in vns:
            dup_vns.add(vn)
        vns.add(vn)

        cat = a.get("category", "unknown")
        subcat = a.get("sub_category", "unknown")
        cat_counts[cat] += 1
        subcat_counts[cat][subcat] += 1
        status_counts[a.get("status", "unknown")] += 1

        fp = tuple(a.get("footprint_cells", [1, 1]))
        footprint_counts[fp] += 1
        footprint_area_counts[fp[0] * fp[1]] += 1

        collision_counts[a.get("collision_type", "unknown")] += 1
        vision_counts[a.get("vision_mode", "unknown")] += 1
        blocks_proj_counts[a.get("blocks_projectile", False)] += 1

        mat = a.get("material", "unknown")
        material_counts[mat] += 1

        culture = a.get("feudal_culture", "unknown")
        culture_counts[culture] += 1

        verb = a.get("interactive_verb")
        if verb:
            verb_counts[verb] += 1

        if a.get("destructible", False):
            destructible_count += 1

        prompt = a.get("prompt_summary", "")
        words = [w.strip(".,;:\"'()") for w in prompt.lower().split() if len(w) > 2]
        vocab_tokens.update(words)
        prompt_lengths.append(len(words))

    # --- PRINT SUMMARY REPORT ---
    print("\n--- 1. CATEGORY DISTRIBUTION (22 Categories) ---")
    for cat, count in sorted(cat_counts.items(), key=lambda x: -x[1]):
        sub_len = len(subcat_counts[cat])
        print(f"  [{cat:<36}] {count:>4} assets across {sub_len:>2} sub-categories")
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
    print(f"  Blocks Projectile : True={blocks_proj_counts[True]} ({(blocks_proj_counts[True]/total_assets)*100:.1f}%), False={blocks_proj_counts[False]}")
    print("  Vision Mode:")
    for vis, cnt in sorted(vision_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {vis:<22} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 4. MATERIAL DISTRIBUTION ---")
    for mat, cnt in sorted(material_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {mat:<16} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 5. FEUDAL CULTURE SPECTRUM ---")
    for cult, cnt in sorted(culture_counts.items(), key=lambda x: -x[1]):
        pct = (cnt / total_assets) * 100
        print(f"    {cult:<24} : {cnt:>4} ({pct:>5.1f}%)")

    print("\n--- 6. INTERACTIVITY & GAMEPLAY ROLES ---")
    interactive_total = sum(verb_counts.values())
    print(f"  Interactive Assets: {interactive_total} ({(interactive_total/total_assets)*100:.1f}%)")
    print("  Top Interactive Verbs:")
    for verb, cnt in verb_counts.most_common(15):
        print(f"    {verb:<20} : {cnt:>4}")
    print(f"  Destructible Assets: {destructible_count} ({(destructible_count/total_assets)*100:.1f}%)")

    print("\n--- 7. UNIQUENESS CHECKS ---")
    print(f"  Unique Asset IDs     : {len(ids)} / {total_assets} (Duplicate IDs: {len(dup_ids)})")
    print(f"  Unique English Names : {len(names)} / {total_assets} (Duplicate Names: {len(dup_names)})")
    print(f"  Unique VN Names      : {len(vns)} / {total_assets} (Duplicate VN: {len(dup_vns)})")

    print("\n--- 8. PROMPT VOCABULARY RICHNESS ---")
    print(f"  Unique Vocabulary Tokens: {len(vocab_tokens)}")
    avg_words = sum(prompt_lengths) / max(1, len(prompt_lengths))
    print(f"  Average Prompt Word Count: {avg_words:.1f} words (Min: {min(prompt_lengths)}, Max: {max(prompt_lengths)})")

    report_data = {
        "pack_id": "medieval_western",
        "total_assets": total_assets,
        "categories": {k: {"count": v, "subcategories": dict(subcat_counts[k])} for k, v in cat_counts.items()},
        "footprints": {f"{k[0]}x{k[1]}": v for k, v in footprint_counts.items()},
        "collision": dict(collision_counts),
        "materials": dict(material_counts),
        "feudal_cultures": dict(culture_counts),
        "verbs": dict(verb_counts),
        "destructible_count": destructible_count,
        "uniqueness": {
            "duplicate_ids": list(dup_ids),
            "duplicate_names": list(dup_names),
            "duplicate_vns": list(dup_vns),
        },
        "vocabulary_size": len(vocab_tokens),
        "avg_prompt_length": avg_words
    }

    REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        json.dump(report_data, f, indent=2, ensure_ascii=False)

    print(f"\nSaved detailed audit JSON report to: {REPORT_OUT}")
    print("=" * 80)


if __name__ == "__main__":
    audit_pack()
