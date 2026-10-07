"""Test generation script for candidate assets across the 7 Archetypes.

Validates game-ready isolation, variant awareness, and guardrail rules
for ancient_china_low_cultivation against local ComfyUI.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.common import ToolError
from tools.generate_and_package_low_cultivation import ComfyArgs, build_game_ready_prompt
from tools.map_generate import generate

OUTPUT_DIR = REPO_ROOT / "build" / "candidate_archetype_tests"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

CANDIDATES = [
    # 1. Item / Handheld Tool (Crescent Spirit Herb Sickle)
    {
        "id": "ancient_china_low_cultivation.flora_and_spirit_plants.crescent_spirit_herb_sickle",
        "asset_slug": "crescent_spirit_herb_sickle",
        "name": "Crescent Spirit Herb Sickle",
        "vietnamese_name": "Liềm Cắt Linh Thảo Nguyệt Nha",
        "domain": "flora_and_spirit_plants",
        "sub_domain": "harvesting_tools",
        "asset_class": "item_tool",
        "type": "item_icon",
        "material": "forged cold iron crescent blade with polished dark rosewood handle",
        "footprint_cells": [1, 1],
        "canvas_px": [128, 128],
        "pivot": "center",
        "alpha": "cutout",
        "collision_type": "none",
        "environment_name": "Mortal Realm",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "pristine",
                "name": "Pristine Sharp Crescent Sickle",
                "prompt_modifier": "immaculate polished cold iron blade, razor sharp edge, clean dark rosewood grip wrapped in black silk cord",
                "seed_offset": 101,
            },
            {
                "variant_slug": "rain_soaked",
                "name": "Rain-Soaked Crescent Sickle",
                "prompt_modifier": "wet glistening metallic surface with micro water droplets on blade, darkened damp rosewood grip",
                "seed_offset": 102,
            },
            {
                "variant_slug": "winter_frost",
                "name": "Winter Frosted Crescent Sickle",
                "prompt_modifier": "delicate rim of white crystalline rime ice along cutting edge, pale frosted wood grain",
                "seed_offset": 103,
            },
            {
                "variant_slug": "damaged_chipped",
                "name": "Damaged Chipped Crescent Sickle",
                "prompt_modifier": "notched jagged blade edge with small chipped cracks, splintered pommel, frayed binding twine",
                "seed_offset": 104,
            },
        ],
    },
    # 2. Prop / Workstation (Bronze Trigram Pill Furnace)
    {
        "id": "ancient_china_low_cultivation.sect_facilities_and_dwellings.bronze_trigram_pill_furnace",
        "asset_slug": "bronze_trigram_pill_furnace",
        "name": "Bronze Trigram Pill Furnace",
        "vietnamese_name": "Bát Quái Thanh Đồng Đan Lô",
        "domain": "sect_facilities_and_dwellings",
        "sub_domain": "alchemy_and_pill_refining",
        "asset_class": "prop_workstation",
        "type": "prop",
        "material": "heavy cast bronze tripod ding cauldron with carved Bagua trigram ventilation vents",
        "footprint_cells": [2, 2],
        "canvas_px": [256, 256],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Sect Grounds",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "dormant_unlit",
                "name": "Dormant Unlit Bronze Furnace",
                "prompt_modifier": "cold dark cast-bronze surface with pale verdigris patina, extinguished dark draft grates, closed iron flue",
                "seed_offset": 201,
            },
            {
                "variant_slug": "active_fire",
                "name": "Active Pill Refining Fire Furnace",
                "prompt_modifier": "roaring scarlet spiritual flames visible through carved trigram draft grates, glowing internal cauldron belly, faint heat shimmer",
                "seed_offset": 202,
            },
            {
                "variant_slug": "winter_snow",
                "name": "Winter Snow Capped Bronze Furnace",
                "prompt_modifier": "thin crisp layer of white snow clinging to cold bronze lid and handles, frost-lined rim",
                "seed_offset": 203,
            },
            {
                "variant_slug": "damaged_cracked",
                "name": "Damaged Cracked Pill Furnace",
                "prompt_modifier": "prominent spiderweb fracture along belly seam, soot-blackened blast scorch on front face, cold fractured rim",
                "seed_offset": 204,
            },
        ],
    },
    # 3. Structure / Architecture (Azure Cloud Mountain Gate)
    {
        "id": "ancient_china_low_cultivation.sect_facilities_and_dwellings.azure_cloud_mountain_gate",
        "asset_slug": "azure_cloud_mountain_gate",
        "name": "Azure Cloud Mountain Gate",
        "vietnamese_name": "Thanh Vân Sơn Môn Bài Lâu",
        "domain": "sect_facilities_and_dwellings",
        "sub_domain": "sect_architecture",
        "asset_class": "structure_building",
        "type": "prop",
        "material": "vermilion lacquered cedar columns, multi-tiered upturned dougong brackets, emerald glazed ceramic roof tiles",
        "footprint_cells": [3, 2],
        "canvas_px": [384, 256],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Sect Mountain Entry",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "day_pristine",
                "name": "Day Pristine Sect Gate",
                "prompt_modifier": "crisp daylight, vibrant vermilion timber columns, immaculate emerald glazed roof tiles, pure albedo exposure",
                "seed_offset": 301,
            },
            {
                "variant_slug": "night_lit",
                "name": "Night Lit Lantern Gate",
                "prompt_modifier": "pure daylight albedo base materials, hanging crimson eaves lanterns emitting warm golden light, gentle illuminated entryway",
                "seed_offset": 302,
            },
            {
                "variant_slug": "winter_snow",
                "name": "Winter Snow Sect Gate",
                "prompt_modifier": "heavy thick white snow blanket settled on curved eaves, delicate hanging icicles along gutters, frosted stone base",
                "seed_offset": 303,
            },
            {
                "variant_slug": "damaged_breached",
                "name": "Damaged Breached Gate",
                "prompt_modifier": "shattered roof tiles with exposed splintered rafters on left wing, scorched impact scars on right vermilion pillar",
                "seed_offset": 304,
            },
        ],
    },
    # 4. Flora / Spirit Herb (Blood Crystal Spirit Ginseng)
    {
        "id": "ancient_china_low_cultivation.flora_and_spirit_plants.blood_crystal_ginseng",
        "asset_slug": "blood_crystal_ginseng",
        "name": "Blood Crystal Spirit Ginseng",
        "vietnamese_name": "Huyết Tinh Linh Sâm",
        "domain": "flora_and_spirit_plants",
        "sub_domain": "spiritual_herbs",
        "asset_class": "flora_herb",
        "type": "prop",
        "material": "translucent crimson crystalline ginseng root with deep jade green leaves and crimson berry cluster",
        "footprint_cells": [1, 1],
        "canvas_px": [128, 128],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "cover",
        "environment_name": "Spirit Herb Garden",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "ripe_blooming",
                "name": "Ripe Blooming Blood Ginseng",
                "prompt_modifier": "plump translucent crimson crystal root partially exposed, vibrant jade leaves, ripe scarlet berries glowing with Qi",
                "seed_offset": 401,
            },
            {
                "variant_slug": "harvested_stump",
                "name": "Harvested Blood Ginseng Stump",
                "prompt_modifier": "clipped flat root neck, harvested fibrous ginseng root stump resting low on ground, cut stem with red medicinal sap bead, missing leaves, missing flowers, missing berries, zero upright stalks, zero tall crystals",
                "seed_offset": 402,
            },
        ],
    },
    # 5. Fauna / Spirit Beast (Azure Crest Cloud Crane)
    {
        "id": "ancient_china_low_cultivation.fauna_and_spirit_beasts.azure_crest_cloud_crane",
        "asset_slug": "azure_crest_cloud_crane",
        "name": "Azure Crest Cloud Crane",
        "vietnamese_name": "Thanh Đỉnh Linh Vân Hạc",
        "domain": "fauna_and_spirit_beasts",
        "sub_domain": "avian_spirit_beasts",
        "asset_class": "fauna_beast",
        "type": "prop",
        "material": "pure white plumage with black wingtip feathers, slender dark legs, glowing azure crest crown",
        "footprint_cells": [1, 1],
        "canvas_px": [128, 128],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Sect Peaks",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "idle_standing",
                "name": "Idle Standing Cloud Crane",
                "prompt_modifier": "graceful standing posture on one slender dark leg with second leg tucked, curved elegant S-neck, smooth folded white wings, calm expression",
                "seed_offset": 501,
            },
            {
                "variant_slug": "alert_aggressive",
                "name": "Alert Threatening Cloud Crane",
                "prompt_modifier": "spread magnificent white wings, upright elongated neck, standing on two slender dark legs, open sharp beak emitting spirit call, tensed alert pose",
                "seed_offset": 502,
            },
        ],
    },
    # 6. Terrain / Ground Surface (Danxia Red Crag Stone)
    {
        "id": "ancient_china_low_cultivation.terrain_and_geology.danxia_red_crag_stone",
        "asset_slug": "danxia_red_crag_stone",
        "name": "Danxia Red Sandstone Soil Surface",
        "vietnamese_name": "Đan Hà Hồng Sa Thạch Điền",
        "domain": "terrain_and_geology",
        "sub_domain": "danxia_formations",
        "asset_class": "terrain_tile",
        "type": "terrain_texture",
        "material": "uniform flat red terracotta sandstone soil and fine ochre mineral silt",
        "footprint_cells": [2, 2],
        "canvas_px": [256, 256],
        "pivot": "center",
        "alpha": "opaque",
        "collision_type": "walk_surface",
        "environment_name": "Danxia Mortal Plains",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "dry_temperate",
                "name": "Dry Temperate Danxia Stone",
                "prompt_modifier": "dry pale terracotta sand and smooth mineral dust, flat continuous ground surface, uniform texture",
                "seed_offset": 631,
            },
            {
                "variant_slug": "wet_rain",
                "name": "Wet Rain Soaked Danxia Stone",
                "prompt_modifier": "damp dark crimson red sandstone silt, shallow reflective water sheen on flat ground, uniform wet surface",
                "seed_offset": 632,
            },
        ],
    },
    # 7. Atmospheric VFX Overlay (Ascending Spiritual Qi Motes)
    {
        "id": "ancient_china_low_cultivation.atmospheric_vfx_and_phenomena.ascending_spiritual_qi_motes",
        "asset_slug": "ascending_spiritual_qi_motes",
        "name": "Ascending Spiritual Qi Motes",
        "vietnamese_name": "Thanh Kim Linh Quang Thăng Đằng",
        "domain": "atmospheric_vfx_and_phenomena",
        "sub_domain": "spiritual_particles",
        "asset_class": "vfx_particle",
        "type": "prop",
        "material": "luminous cyan and gold spiritual essence energy motes, gentle floating upward drift",
        "footprint_cells": [2, 2],
        "canvas_px": [256, 256],
        "pivot": "center",
        "alpha": "opaque",
        "collision_type": "none",
        "environment_name": "Spiritual Leyline",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "subtle_ambient",
                "name": "Subtle Ambient Qi Motes",
                "prompt_modifier": "sparse tiny floating cyan and golden light particles, gentle soft ethereal glow, faint vertical drift trails",
                "seed_offset": 701,
            },
            {
                "variant_slug": "surging_vortex",
                "name": "Surging Spiral Qi Torrent",
                "prompt_modifier": "dense swirling vortex ribbon of bright cyan spiritual energy, intense luminous core, upward spiraling sparks",
                "seed_offset": 702,
            },
        ],
    },
]


def run_candidate_test(
    candidate_slug: str | None = None,
    variant_slug: str | None = None,
    base_seed: int = 8800,
) -> int:
    targets = [c for c in CANDIDATES if not candidate_slug or c["asset_slug"] == candidate_slug]
    if not targets:
        print(f"Error: Candidate '{candidate_slug}' not found.")
        return 1

    print(f"=== Running Candidate Archetype Tests: {len(targets)} candidates ===")

    for cand in targets:
        c_slug = cand["asset_slug"]
        c_name = cand["name"]
        variants = cand.get("variants", [])
        if variant_slug:
            variants = [v for v in variants if v["variant_slug"] == variant_slug]

        cand_out_dir = OUTPUT_DIR / c_slug
        cand_out_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n[{c_slug}] {c_name} ({len(variants)} variants)")

        for var in variants:
            v_slug = var["variant_slug"]
            v_name = var["name"]
            seed = base_seed + var.get("seed_offset", 0)

            print(f"  -> Generating Variant: [{v_slug}] '{v_name}' (seed={seed})")

            pos_prompt, neg_prompt = build_game_ready_prompt(cand, var)

            args = ComfyArgs()
            args.prompt = pos_prompt
            args.negative = neg_prompt
            args.seed = seed

            # Canvas sizing
            cw, ch = cand.get("canvas_px", [256, 256])
            args.size = max(cw, ch) * 2  # Generate at 2x resolution
            if args.size < 512:
                args.size = 512
            elif args.size > 1024:
                args.size = 1024

            out_subfolder = f"candidate_tests/{c_slug}"

            t0 = time.time()
            success = False
            for attempt in range(3):
                try:
                    out_path, used_prompt, used_seed = generate(
                        cand,
                        args,
                        output_dir=out_subfolder,
                    )
                    dt = time.time() - t0
                    print(f"     [OK] Output generated in {dt:.1f}s: {out_path.name}")
                    print(f"     Prompt: {used_prompt[:120]}...")
                    success = True
                    break
                except ToolError as te:
                    if "refusing to overwrite" in str(te):
                        print(f"     [SKIPPED] Already generated: {te}")
                        success = True
                        break
                    print(f"     [Attempt {attempt + 1}/3] ToolError: {te}")
                    time.sleep(3)
                except Exception as ex:
                    print(f"     [Attempt {attempt + 1}/3] Exception: {ex}")
                    time.sleep(3)
            if not success:
                print(f"     [FAILED after 3 attempts]: {c_slug} -> {v_slug}")

    print(f"\nAll candidate tests finished. Inspect outputs in: {OUTPUT_DIR}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Test Candidate Archetypes Generator")
    parser.add_argument(
        "--candidate", "-c", help="Specific candidate slug (e.g. crescent_spirit_herb_sickle)"
    )
    parser.add_argument("--variant", "-v", help="Specific variant slug (e.g. pristine)")
    parser.add_argument("--seed", type=int, default=8800, help="Base seed")
    parser.add_argument("--list", action="store_true", help="List all candidate archetypes")

    args = parser.parse_args(argv)

    if args.list:
        print("Registered Candidate Archetypes:")
        for idx, c in enumerate(CANDIDATES, 1):
            print(
                f"{idx}. [{c['asset_class']}] {c['asset_slug']} - {c['name']} ({len(c['variants'])} variants)"
            )
        return 0

    return run_candidate_test(
        candidate_slug=args.candidate,
        variant_slug=args.variant,
        base_seed=args.seed,
    )


if __name__ == "__main__":
    raise SystemExit(main())
