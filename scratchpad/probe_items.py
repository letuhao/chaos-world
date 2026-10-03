"""READ-ONLY: how much prose do gather items actually carry, and what ARE they?

Checks the question the brief asks -- "are they herbs and ores, or crafting
inputs?" -- against the fields that actually exist. ItemDef HAS a description
field (item_def.gd:18); this measures whether it is ever authored.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools import data as D  # noqa: E402


def main() -> None:
    records, _ = D._load(D.DATA_ROOT)
    items = records["item"]

    def kinds(iid: str) -> set[str]:
        return {s.partition(":")[0] for s in items[iid]["arrays"].get("sources", [])}

    gather = sorted(i for i in items if "gather" in kinds(i))
    quest = sorted(i for i in items if "quest" in kinds(i))
    craft = sorted(i for i in items if "craft" in kinds(i))
    boss = sorted(i for i in items if "boss" in kinds(i))

    out: dict = {}
    # Does ANY item carry a non-empty description?
    with_desc = [i for i in items if items[i]["scalars"].get("description", "").strip()]
    out["items_with_non_empty_description"] = len(with_desc)
    out["total_items"] = len(items)

    # What do gather items look like, by subcategory / name?
    out["gather_subcategory_census"] = dict(
        Counter(items[i]["scalars"].get("subcategory", "").strip() or "(none)" for i in gather).most_common(30)
    )
    out["quest_subcategory_census"] = dict(
        Counter(items[i]["scalars"].get("subcategory", "").strip() or "(none)" for i in quest).most_common(30)
    )

    # Is a gather item also a recipe INPUT? (the "crafting input" hypothesis)
    input_ids: set[str] = set()
    for r in records["recipe"].values():
        input_ids.update(r["arrays"].get("inputs", []))
    out["gather_items_that_are_recipe_inputs"] = len(set(gather) & input_ids)
    out["gather_items_total"] = len(gather)
    out["quest_items_that_are_recipe_inputs"] = len(set(quest) & input_ids)

    # Is a gather item a recipe OUTPUT? (would mean gathering duplicates crafting)
    out["gather_items_that_are_recipe_outputs"] = len(set(gather) & set(
        o for r in records["recipe"].values() for o in r["arrays"].get("outputs", [])
    ))

    # Are gather items worn/equippable or consumable -> "picked up in the world"?
    out["gather_category_vs_craft_category"] = {
        "gather": dict(Counter(items[i]["scalars"]["category"].strip() for i in gather).most_common()),
        "craft_declaring": dict(Counter(items[i]["scalars"]["category"].strip() for i in craft).most_common()),
    }

    # 12 hand-picked gather samples spread across categories, with name+subcategory
    buckets: dict[str, list[str]] = {}
    for i in gather:
        cat = items[i]["scalars"]["category"].strip()
        buckets.setdefault(cat, []).append(i)
    samples = []
    for cat in ("material", "consumable", "equipment", "technique", "currency", "key", "misc", "quest"):
        pool = buckets.get(cat, [])
        for iid in pool[:: max(1, len(pool) // 2)][:2]:
            s = items[iid]["scalars"]
            samples.append({
                "category": cat,
                "subcategory": s.get("subcategory", ""),
                "id": iid,
                "display_name": s.get("display_name", ""),
                "description": s.get("description", ""),
                "sources": items[iid]["arrays"].get("sources", []),
                "is_recipe_input": iid in input_ids,
            })
    out["gather_SAMPLES_by_category"] = samples

    # The one item we can read in full as a shape example
    out["authored_quests_on_disk"] = sorted(
        p.name for p in D.QUEST_DIR.glob("*.tres")
    ) if D.QUEST_DIR.is_dir() else []
    out["QUEST_DIR"] = str(D.QUEST_DIR)
    out["quest_dir_exists"] = D.QUEST_DIR.is_dir()

    # holdings node defs on disk
    holdings = D.DATA_ROOT / "holdings"
    out["holdings_data_dir_exists"] = holdings.is_dir()
    out["holdings_nodes_dir_exists"] = (holdings / "nodes").is_dir()

    print(json.dumps(out, indent=1, default=str, ensure_ascii=False))


if __name__ == "__main__":
    main()
