"""Promote Candidate Archetype Test Assets into the Ancient China Low Cultivation Pack.

Copies and normalizes verified candidate assets from build/candidate_tests/ into
the pack's runtime directory (game/assets/packs/ancient_china_low_cultivation/runtime/)
and companion data directory (game/assets/packs/ancient_china_low_cultivation/data/).
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/ancient_china_low_cultivation"
PACK_PATH = PACK_DIR / "ancient_china_low_cultivation_pack.json"
CANDIDATE_DIR = REPO_ROOT / "build/candidate_tests"
RUNTIME_DIR = PACK_DIR / "runtime"
DATA_DIR = PACK_DIR / "data"

# Mapping: candidate_slug -> (domain_id, category_id, asset_slug, variant_mapping)
PROMOTION_MAP: dict[str, dict] = {
    "pure_yang_daoist_temple": {
        "domain": "religious_sanctuaries",
        "category": "rel_01_solitary_mountain_daoist_hermitage",
        "asset": "daoist_temple_hall",
        "seed_prefix": 10900,
        "variants": {
            "rot_south_facade": 10901,
            "rot_north_rear": 10905,
            "rot_west_flank": 10904,
            "rot_east_flank": 10903,
        },
    },
    "bamboo_spirit_hermit_cottage": {
        "domain": "mortal_and_jianghu",
        "category": "mor_01_thatch_roofed_farmer_cottage",
        "asset": "thatched_dwelling",
        "seed_prefix": 11000,
        "variants": {
            "rot_south_facade": 11001,
            "rot_north_rear": 11003,
            "rot_west_flank": 11004,
            "rot_east_flank": 11002,
        },
    },
    "azure_cloud_mountain_gate_rotations": {
        "domain": "sect_facilities_and_dwellings",
        "category": "sec_01_mountain_sect_entry_gate_shanmen",
        "asset": "monumental_sect_gate",
        "seed_prefix": 11200,
        "variants": {
            "rot_south_facade": 11201,
            "rot_north_rear": 11203,
            "rot_west_flank": 11204,
            "rot_east_flank": 11202,
        },
    },
    "pill_alchemy_pavilion_rotations": {
        "domain": "sect_facilities_and_dwellings",
        "category": "sec_01_mountain_sect_entry_gate_shanmen",
        "asset": "pill_alchemy_chamber",
        "seed_prefix": 11300,
        "variants": {
            "rot_south_facade": 11301,
            "rot_north_rear": 11303,
            "rot_west_flank": 11304,
            "rot_east_flank": 11302,
        },
    },
    "azure_cloud_karst_peak_spire": {
        "domain": "terrain_and_geology",
        "category": "ter_03_weathered_karst_peaks",
        "asset": "monumental_peak_spire",
        "seed_prefix": 11110,
        "variants": {
            "facing_south_front": 11111,
            "facing_north_back": 11113,
            "facing_west_left": 11114,
            "facing_east_profile": 11112,
        },
    },
    "blood_crystal_ginseng": {
        "domain": "flora_and_spirit_plants",
        "category": "flo_04_low_grade_blood_ginseng",
        "asset": "mature_flourishing",
        "seed_prefix": 9200,
        "variants": {
            "harvestable_ripe": 9201,
            "harvested_stump": 9202,
            "tender_sapling": 9203,
            "qi_overflow": 9204,
            "withering_spent": 9205,
        },
    },
    "azure_crest_cloud_crane": {
        "domain": "fauna_and_spirit_beasts",
        "category": "beas_05_moon_crowned_white_crane",
        "asset": "idle_peaceful_stance",
        "seed_prefix": 9300,
        "variants": {
            "idle_peaceful_stance": 9301,
            "aggressive_combat_posture": 9302,
            "wounded_staggered": 9303,
            "harvestable_carcass": 9304,
            "demonic_corrupted_form": 9305,
        },
    },
    "azure_frost_flying_sword": {
        "domain": "artifacts_and_paraphernalia",
        "category": "art_03_flying_sword_iron_pine_pattern",
        "asset": "diagonal_inventory_icon",
        "seed_prefix": 9800,
        "variants": {
            "diagonal_inventory_icon": 9801,
            "flat_ground_drop_east": 9802,
            "flat_ground_drop_south": 9803,
            "cardinal_north_facing": 9804,
            "cardinal_west_facing": 9805,
        },
    },
    "bronze_trigram_pill_furnace": {
        "domain": "artifacts_and_paraphernalia",
        "category": "art_02_low_grade_bronze_trigram_cauldron",
        "asset": "diagonal_inventory_icon",
        "seed_prefix": 9000,
        "variants": {
            "diagonal_inventory_icon": 9001,
            "flat_ground_drop_east": 9002,
            "flat_ground_drop_south": 9003,
            "cardinal_north_facing": 9004,
        },
    },
    "carved_rosewood_spirit_pill_chest": {
        "domain": "sect_facilities_and_dwellings",
        "category": "sec_01_mountain_sect_entry_gate_shanmen",
        "asset": "scripture_library_tower",
        "seed_prefix": 9600,
        "variants": {
            "pristine_dormant": 9601,
            "active_operating": 9602,
            "damaged_weathered": 9603,
        },
    },
    "danxia_red_crag_stone": {
        "domain": "terrain_and_geology",
        "category": "ter_04_danxia_red_sandstone_crags",
        "asset": "flat_surface_tile",
        "seed_prefix": 9430,
        "variants": {
            "dry_temperate": 9431,
            "wet_monsoon": 9432,
            "winter_snow_crust": 9433,
            "yin_corrupted": 9434,
        },
    },
    "crescent_spirit_herb_sickle": {
        "domain": "artifacts_and_paraphernalia",
        "category": "art_19_herb_harvester_jade_shovel_spade",
        "asset": "diagonal_inventory_icon",
        "seed_prefix": 8900,
        "variants": {
            "diagonal_inventory_icon": 8901,
            "flat_ground_drop_east": 8902,
            "flat_ground_drop_south": 8903,
            "cardinal_north_facing": 8904,
            "cardinal_west_facing": 8905,
            "pristine_forged_state": 8906,
        },
    },
    "ascending_spiritual_qi_motes": {
        "domain": "atmospheric_vfx_and_phenomena",
        "category": "vfx_05_ascending_cyangold_spiritual_qi_particles",
        "asset": "subtle_ambient_drift",
        "seed_prefix": 9500,
        "variants": {
            "subtle_ambient_drift": 9501,
            "surging_spiral_torrent": 9502,
        },
    },
    "nine_heavens_tribulation_lightning": {
        "domain": "atmospheric_vfx_and_phenomena",
        "category": "vfx_12_nine_heaven_tribulation_clouds_lightning",
        "asset": "crackling_forked_lightning",
        "seed_prefix": 9700,
        "variants": {
            "crackling_forked_lightning": 9701,
        },
    },
}


def promote_candidates() -> int:
    print("=" * 80)
    print("PROMOTING VERIFIED CANDIDATE ARCHETYPE ASSETS TO PACK")
    print("=" * 80)

    if not PACK_PATH.exists():
        print(f"Error: {PACK_PATH} not found")
        return 1

    with open(PACK_PATH, encoding="utf-8") as f:
        pack = json.load(f)

    asset_defs = {a["id"]: a for a in pack.get("assets", [])}
    promoted_images = 0
    promoted_meta = 0

    for cand_slug, cfg in PROMOTION_MAP.items():
        src_cand_dir = CANDIDATE_DIR / cand_slug
        if not src_cand_dir.exists():
            print(f"Candidate directory missing: {src_cand_dir}")
            continue

        dom = cfg["domain"]
        cat = cfg["category"]
        asset_slug = cfg["asset"]
        full_aid = f"ancient_china_low_cultivation.{cat}.{asset_slug}"
        asset_info = asset_defs.get(full_aid, {})

        dest_runtime_dir = RUNTIME_DIR / dom / cat / asset_slug
        dest_data_dir = DATA_DIR / dom / cat / asset_slug
        dest_runtime_dir.mkdir(parents=True, exist_ok=True)
        dest_data_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n[{cand_slug}] -> {dom}/{cat}/{asset_slug}")

        for var_slug, seed in cfg["variants"].items():
            matches = list(src_cand_dir.glob(f"*{seed}*.png"))
            if not matches:
                matches = list(src_cand_dir.glob(f"*{var_slug}*.png"))

            if not matches:
                print(f"  [MISSING] No candidate render found for seed={seed} / var={var_slug}")
                continue

            src_file = matches[0]
            dest_png = dest_runtime_dir / f"{var_slug}.png"
            dest_json = dest_data_dir / f"{var_slug}.json"

            # 1. Copy runtime PNG (optimizing/verifying dimensions)
            try:
                with Image.open(src_file) as img:
                    img.load()
                    w, h = img.size
                    mode = img.mode
                    # Save optimized runtime PNG
                    img.save(dest_png, format="PNG", optimize=True)
                promoted_images += 1
                print(f"  [PROMOTED] {var_slug}.png ({w}x{h}, {mode})")
            except Exception as e:
                print(f"  [ERROR] Failed copying {src_file.name}: {e}")
                continue

            # 2. Build companion metadata JSON
            matrix_data = {
                "subgrid_rows": 4,
                "subgrid_cols": 4,
                "walk_surface": True if "terrain" in dom or "tile" in asset_slug else False,
                "elevation_step": 0,
                "cliff_drop": False,
                "contact_pixels": [],
                "source_render_seed": seed,
                "source_candidate": cand_slug,
            }

            meta_content = {
                "asset_id": full_aid,
                "variant_slug": var_slug,
                "image_path": f"res://assets/packs/ancient_china_low_cultivation/runtime/{dom}/{cat}/{asset_slug}/{var_slug}.png",
                "width": w,
                "height": h,
                "footprint_cells": asset_info.get("footprint_cells", [1, 1]),
                "canvas_px": asset_info.get("canvas_px", [w, h]),
                "collision_type": asset_info.get("collision_type", "solid"),
                "matrix_data": matrix_data,
            }
            dest_json.write_text(json.dumps(meta_content, indent=2), encoding="utf-8")
            promoted_meta += 1

    print("\n" + "=" * 80)
    print(f"PROMOTION COMPLETE: {promoted_images} PNG images, {promoted_meta} companion JSON files")
    print("=" * 80)
    return 0


if __name__ == "__main__":
    raise SystemExit(promote_candidates())
