# -*- coding: utf-8 -*-
"""Complete scaffolding generator for Ancient Chinese Mortal World asset pack (Categories 7-14).

Populates the remaining 460 assets (bringing total from 320 to 780 assets)
strictly adhering to categories.json and README.md.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = REPO_ROOT / "game/assets/packs/ancient_china_mortal/ancient_china_mortal_pack.json"


def make_asset(
    cat_id: str,
    slug: str,
    name: str,
    vn_name: str,
    hanzi: str,
    sub_cat: str,
    footprint: list[int],
    collision: str,
    blocks_proj: bool,
    vision: str,
    verb: str | None,
    role: str,
    destructible: bool,
    material: str,
    element: str,
    prompt: str,
    asset_type: str,
    alpha: str,
    pivot: str,
    hooks: dict,
) -> dict:
    return {
        "id": f"ancient_china_mortal.{cat_id}.{slug}",
        "name": name,
        "vietnamese_name": vn_name,
        "hanzi": hanzi,
        "category": cat_id,
        "sub_category": sub_cat,
        "type": asset_type,
        "alpha": alpha,
        "pivot": pivot,
        "footprint_cells": footprint,
        "canvas_px": [footprint[0] * 128, footprint[1] * 128],
        "collision_type": collision,
        "blocks_projectile": blocks_proj,
        "vision_mode": vision,
        "interactive_verb": verb,
        "gameplay_role": role,
        "destructible": destructible,
        "material": material,
        "cultivation_element": element,
        "prompt_summary": prompt,
        "racial_faction": "mortal_dynasty",
        "environment_name": "Ancient China Mortal World (Cửu Châu Phàm Trần)",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), grounded East Asian mortal palette.",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu)",
        "status": "planned",
        "reference_ids": ["docs/art-direction.md#top-down-world-map"],
        "source": "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, lora: krea2/Scottie__Krea2.safetensors (1.0)",
        "license": "Generated locally; source checkpoint license terms apply",
        "gameplay_gap_hooks": hooks,
    }


def load_category_7() -> list[dict]:
    # Extract river_subs from scratch/scaffold_batches_3_4_5.py
    import ast
    src_file = Path(r"C:\Users\NeneScarlet\.gemini\antigravity-ide\brain\350ba54b-c2c7-426b-a177-d210de42b117\scratch\scaffold_batches_3_4_5.py")
    tree = ast.parse(src_file.read_text(encoding="utf-8"))
    river_subs = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and getattr(node.targets[0], "id", "") == "river_subs":
            river_subs = ast.literal_eval(node.value)
            break
    if not river_subs:
        raise RuntimeError("Failed to load river_subs")

    items = []
    for sub_name, s_items in river_subs:
        for it in s_items:
            if len(it) == 18:
                slug, name, vn, hanzi = it[0], it[1], it[2], it[3]
                fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[4:]
            elif len(it) == 19:
                slug, name, vn, hanzi, sub = it[0], it[1], it[2], it[3], it[4]
                fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[5:]
            else:
                raise ValueError(f"Unexpected item length {len(it)}")
            items.append(make_asset(
                "river_and_maritime", slug, name, vn, hanzi, sub_name, fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks
            ))
    return items


def load_category_8_9() -> list[dict]:
    import ast
    src_file = REPO_ROOT / "tools/scaffold_mortal_pack_full.py"
    tree = ast.parse(src_file.read_text(encoding="utf-8"))
    c8_subs, c9_subs = None, None
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "generate_all_remaining":
            for sub_node in node.body:
                if isinstance(sub_node, ast.Assign) and len(sub_node.targets) == 1:
                    tname = getattr(sub_node.targets[0], "id", "")
                    if tname == "c8_subs":
                        c8_subs = ast.literal_eval(sub_node.value)
                    elif tname == "c9_subs":
                        c9_subs = ast.literal_eval(sub_node.value)

    items = []
    for sub_name, s_items in c8_subs:
        for it in s_items:
            slug, name, vn, hanzi = it[0], it[1], it[2], it[3]
            fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[4:]
            items.append(make_asset("trade_craft_industry", slug, name, vn, hanzi, sub_name, fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks))

    for sub_name, s_items in c9_subs:
        for it in s_items:
            slug, name, vn, hanzi = it[0], it[1], it[2], it[3]
            fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[4:]
            items.append(make_asset("outlaw_and_jianghu", slug, name, vn, hanzi, sub_name, fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks))

    return items


def load_categories_10_to_14() -> list[dict]:
    import ast
    src_file = REPO_ROOT / "tools/scaffold_categories_10_to_14.py"
    tree = ast.parse(src_file.read_text(encoding="utf-8"))
    
    extracted = {}
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "get_categories_10_to_14":
            for sub_node in node.body:
                if isinstance(sub_node, ast.Assign) and len(sub_node.targets) == 1:
                    tname = getattr(sub_node.targets[0], "id", "")
                    if tname in ("c10", "c11", "c12", "c14", "peasant_names", "soldier_names", "wuxia_names", "bandit_names", "qi_names", "beast_names"):
                        extracted[tname] = ast.literal_eval(sub_node.value)

    items = []
    for cat_id, key in [("folk_religion_fengshui", "c10"), ("low_realm_cultivation", "c11"), ("destructible_and_loot", "c12")]:
        for sub_name, s_items in extracted[key]:
            for it in s_items:
                slug, name, vn, hanzi = it[0], it[1], it[2], it[3]
                fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[4:]
                items.append(make_asset(cat_id, slug, name, vn, hanzi, sub_name, fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks))

    # Category 13: creature_and_denizen
    c13_map = [
        ("peasant_names", "peasant_farmer_and_artisan", "Civilian NPC", "talk", "civilian"),
        ("soldier_names", "imperial_soldier_and_bailiff", "Military Guard NPC", "talk", "guard"),
        ("wuxia_names", "wandering_wuxia_swordsman", "Jianghu Martial Artist NPC", "duel", "wuxia"),
        ("bandit_names", "mountain_bandit_raider", "Bandit Hostile NPC", "attack", "hostile_bandit"),
        ("qi_names", "low_qi_disciple", "Cultivation Novice NPC", "talk", "cultivator"),
        ("beast_names", "draft_beast_and_livestock", "Fauna Creature", "interact_animal", "animal"),
    ]
    for key, sub_name, role, verb, npc_type in c13_map:
        for slug, name, vn, hanzi, col, fp, prompt in extracted[key]:
            des = (npc_type == "animal")
            items.append(make_asset(
                "creature_and_denizen", slug, name, vn, hanzi, sub_name, fp, col, False, "transparent", verb, role, des, "flesh", "mortal", prompt, "character_sprite", "transparent", "bottom_center", {"npc_type": npc_type}
            ))

    # Category 14: flora_and_ambience
    for sub_name, s_items in extracted["c14"]:
        for it in s_items:
            slug, name, vn, hanzi = it[0], it[1], it[2], it[3]
            fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks = it[4:]
            items.append(make_asset("flora_and_ambience", slug, name, vn, hanzi, sub_name, fp, col, b_proj, vis, verb, role, des, mat, el, pr, atype, alp, piv, hks))

    return items


def scaffold_all():
    pack = json.loads(PACK_PATH.read_text(encoding="utf-8"))
    existing_ids = {a["id"] for a in pack["assets"]}
    print(f"Existing assets in pack: {len(existing_ids)}")

    c7 = load_category_7()
    print(f"Loaded Category 7: {len(c7)} assets")

    c8_9 = load_category_8_9()
    print(f"Loaded Categories 8 & 9: {len(c8_9)} assets")

    c10_14 = load_categories_10_to_14()
    print(f"Loaded Categories 10-14: {len(c10_14)} assets")

    all_new = c7 + c8_9 + c10_14
    print(f"Total new assets to append: {len(all_new)}")

    added = 0
    for a in all_new:
        if a["id"] not in existing_ids:
            pack["assets"].append(a)
            existing_ids.add(a["id"])
            added += 1

    pack["total_assets"] = len(pack["assets"])
    print(f"Appended {added} assets. Total assets in pack now: {len(pack['assets'])}")

    temp_path = PACK_PATH.with_suffix(".tmp")
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2, ensure_ascii=False)
    temp_path.replace(PACK_PATH)
    print(f"Successfully saved updated pack to {PACK_PATH}")


if __name__ == "__main__":
    scaffold_all()
