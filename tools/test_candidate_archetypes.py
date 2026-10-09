"""Test generation script for candidate assets across the 7 Archetypes.

Validates game-ready isolation, variant awareness, and guardrail rules
for ancient_china_low_cultivation against local ComfyUI.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.common import ToolError
from tools.generate_and_package_low_cultivation import (
    ComfyArgs,
    build_game_ready_prompt,
    convert_black_bg_to_alpha,
)
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
            {
                "variant_slug": "pos_ground_drop_flat",
                "name": "Ground Drop Flat Reaping Sickle",
                "prompt_modifier": "world loot drop presentation, sickle lying flat horizontally on ground plane in 2D orthographic top-down RPG perspective, subtle micro contact shadow beneath wooden handle and curved blade, resting flat",
                "seed_offset": 105,
            },
            {
                "variant_slug": "rot_vertical_north",
                "name": "Vertical Upright Sickle",
                "prompt_modifier": "vertical straight orientation with handle pointing downward and curved crescent hook facing upward at the top, centered alignment",
                "seed_offset": 106,
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
            {
                "variant_slug": "wartime_lockdown",
                "name": "Wartime Lockdown Gate",
                "prompt_modifier": "active glowing cyan Bagua trigram defensive barrier dome humming over the gate, heavy spiked ironwood cross-barricades barring the entryway, battle-ready sect posture",
                "seed_offset": 305,
            },
            {
                "variant_slug": "ruined_rubble",
                "name": "Ruined Rubble Collapsed Gate",
                "prompt_modifier": "0% HP completely collapsed heap of shattered emerald ceramic roof tiles, charred splintered timber columns, cracked foundation stone slab with weeds, fully destroyed ruin",
                "seed_offset": 306,
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
            {
                "variant_slug": "spring_sprout",
                "name": "Spring Sprout Blood Ginseng",
                "prompt_modifier": "small immature tender pale-green seedling sprout with two tiny leaves, small undeveloped root bud resting low on soil, delicate growth stage",
                "seed_offset": 403,
            },
            {
                "variant_slug": "qi_overflow",
                "name": "Qi Overflow Mutated Blood Ginseng",
                "prompt_modifier": "thousand-year mature ginseng intensely glowing with bright azure bioluminescent veins pulsing through radiant crimson crystal root, brilliant spiritual aura",
                "seed_offset": 404,
            },
            {
                "variant_slug": "withered_spent",
                "name": "Withered Spent Qi Ginseng Husk",
                "prompt_modifier": "dried shriveled Qi-depleted brown fibrous root husk, withered curled brittle brown leaves, completely drained medicinal energy",
                "seed_offset": 405,
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
            {
                "variant_slug": "wounded_staggered",
                "name": "Wounded Staggered Cloud Crane",
                "prompt_modifier": "staggered off-balance standing posture on two legs, drooping singed left wing, stained blood on white plumage, chipped beak, combat-injured state",
                "seed_offset": 503,
            },
            {
                "variant_slug": "dead_carcass",
                "name": "Dead Carcass Hunted Crane",
                "prompt_modifier": "lifeless crane body fallen flat on ground, limp elongated neck resting on side, folded limp wings, pristine white feathers, glowing faint cyan spirit beast core resting beside chest, harvestable game hunt loot",
                "seed_offset": 504,
            },
            {
                "variant_slug": "yin_demonic_corrupted",
                "name": "Yin Demonic Corrupted Cloud Crane",
                "prompt_modifier": "baleful violet and black demonic miasma smoke radiating from feathers, glowing malevolent crimson eyes, corrupted dark purple crest, jagged blackened talons",
                "seed_offset": 505,
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
            {
                "variant_slug": "leyline_pure",
                "name": "Pure Leyline Saturated Danxia Stone",
                "prompt_modifier": "intricate branching subterranean glowing cyan spiritual Qi crystal veins illuminating the red sandstone fissures, magical leyline saturation, flat 90-degree top-down ground",
                "seed_offset": 633,
            },
            {
                "variant_slug": "yin_corrupted",
                "name": "Yin Demonic Corrupted Blighted Ground",
                "prompt_modifier": "scorched ash-grey blighted stone with thin wisps of dark violet miasma seeping from blackened surface cracks, corrupt demonic ground, flat top-down surface",
                "seed_offset": 634,
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
    # 8. Interactive Container Prop (Carved Rosewood Spirit Pill Chest)
    {
        "id": "ancient_china_low_cultivation.sect_facilities_and_dwellings.carved_rosewood_spirit_pill_chest",
        "asset_slug": "carved_rosewood_spirit_pill_chest",
        "name": "Carved Rosewood Spirit Pill Chest",
        "vietnamese_name": "Điêu Hoa Tử Đàn Linh Đan Hạp",
        "domain": "sect_facilities_and_dwellings",
        "sub_domain": "furnishing_and_storage",
        "asset_class": "prop_container",
        "type": "prop",
        "material": "dark carved rosewood chest with reinforced polished brass corner brackets and Daoist talisman lock latch",
        "footprint_cells": [1, 1],
        "canvas_px": [128, 128],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Sect Interior",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "closed_locked",
                "name": "Closed Locked Spirit Chest",
                "prompt_modifier": "closed hinged heavy wooden lid, secured with engraved brass talisman padlock, pristine intact treasure container",
                "seed_offset": 801,
            },
            {
                "variant_slug": "open_looted",
                "name": "Open Looted Spirit Chest",
                "prompt_modifier": "open hinged lid flipped upright and backward, empty velvet-lined storage interior, dark wooden box base resting flat, visible brass hinges",
                "seed_offset": 802,
            },
            {
                "variant_slug": "broken_shattered",
                "name": "Broken Shattered Spirit Chest",
                "prompt_modifier": "violently broken container with splintered wooden lid planks, bent brass brackets, cracked timber slats resting on ground",
                "seed_offset": 803,
            },
        ],
    },
    # 9. Breakthrough Calamity VFX (Nine Heavens Tribulation Lightning)
    {
        "id": "ancient_china_low_cultivation.atmospheric_vfx_and_phenomena.nine_heavens_tribulation_lightning",
        "asset_slug": "nine_heavens_tribulation_lightning",
        "name": "Nine Heavens Tribulation Lightning",
        "vietnamese_name": "Cửu Tiêu Thần Lôi Kiếp Điệp",
        "domain": "atmospheric_vfx_and_phenomena",
        "sub_domain": "calamity_and_tribulation",
        "asset_class": "vfx_particle",
        "type": "prop",
        "material": "crackling jagged celestial tribulation thunderbolt with glowing electric azure core and delicate branching filament sparks",
        "footprint_cells": [2, 2],
        "canvas_px": [256, 256],
        "pivot": "center",
        "alpha": "opaque",
        "collision_type": "none",
        "environment_name": "Heavenly Tribulation",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "calamity_arc",
                "name": "Calamity Arc Tribulation Lightning",
                "prompt_modifier": "violent branching jagged electric tribulation lightning bolt striking downward, intense blinding azure and white electrical discharge, delicate branching plasma filaments, radiant glow",
                "seed_offset": 901,
            },
        ],
    },
    # 10. Item Weapon & Position/Rotation Archetype (Azure Frost Flying Sword)
    {
        "id": "ancient_china_low_cultivation.artifacts_and_paraphernalia.azure_frost_flying_sword",
        "asset_slug": "azure_frost_flying_sword",
        "name": "Azure Frost Flying Sword",
        "vietnamese_name": "Thanh Sương Phi Kiếm",
        "domain": "artifacts_and_paraphernalia",
        "sub_domain": "flying_swords",
        "asset_class": "item_weapon",
        "type": "item_icon",
        "material": "forged millennium cold iron straight blade with azure frost talismanic fuller, dark sandalwood hilt wrapped in black silk cord, carved jade pommel tassel",
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
                "variant_slug": "pos_inventory_icon_45deg",
                "name": "Inventory Icon 45-Degree Diagonal Sword",
                "prompt_modifier": "macro inventory icon presentation, tilted diagonally at 45 degrees, hilt and jade tassel at bottom-left, sharp pointed blade tip pointing toward top-right, clean square framing",
                "seed_offset": 1001,
            },
            {
                "variant_slug": "pos_ground_drop_flat_east",
                "name": "Ground Drop Flat East Sword",
                "prompt_modifier": "world loot drop presentation, lying flat horizontally pointing East (90 degrees to the right), 2D orthographic top-down RPG perspective, resting flat, subtle micro contact shadow beneath hilt and blade",
                "seed_offset": 1002,
            },
            {
                "variant_slug": "pos_ground_drop_flat_south",
                "name": "Ground Drop Flat South Sword",
                "prompt_modifier": "world loot drop presentation, lying flat pointing South (180 degrees downward toward camera), 2D orthographic top-down perspective with foreshortened blade, resting flat, subtle micro contact shadow beneath",
                "seed_offset": 1003,
            },
            {
                "variant_slug": "rot_north_0deg",
                "name": "Upright Vertical North Sword",
                "prompt_modifier": "vertical straight sword orientation pointing straight North (0 degrees upward), hilt at bottom, pointed blade tip pointing vertically up, centered symmetrical alignment",
                "seed_offset": 1004,
            },
            {
                "variant_slug": "rot_west_270deg",
                "name": "Horizontal West Pointing Sword",
                "prompt_modifier": "horizontal straight sword orientation pointing West (270 degrees to the left), hilt on right, pointed blade tip pointing horizontally to the left, centered profile",
                "seed_offset": 1005,
            },
        ],
    },
    # 11. Temple / Hall Structure Rotations (Pure Yang Daoist Temple)
    {
        "id": "ancient_china_low_cultivation.religious_sanctuaries.pure_yang_daoist_temple",
        "asset_slug": "pure_yang_daoist_temple",
        "name": "Pure Yang Daoist Temple Hall",
        "vietnamese_name": "Thuần Dương Đạo Quán Đại Điện",
        "domain": "religious_sanctuaries",
        "sub_domain": "daoist_temples",
        "asset_class": "structure_temple",
        "type": "prop",
        "material": "weathered grey granite foundation, dark vermilion lacquered timber columns, dark grey glazed curved eave roof tiles with ceramic ridge beasts",
        "footprint_cells": [3, 2],
        "canvas_px": [384, 256],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Daoist Sanctuary",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "rot_south_facade",
                "name": "South Facing Temple Front Facade",
                "prompt_modifier": "steep top-down RPG map angle looking down, roof ridge running East-West with broad glazed tile roof slopes dominant from above, front entrance doorway and carved lintel plaque foreshortened beneath southern eaves at bottom-center, stone courtyard steps descending at bottom",
                "seed_offset": 2101,
            },
            {
                "variant_slug": "rot_north_rear",
                "name": "North Facing Temple Rear Wall",
                "prompt_modifier": "steep top-down RPG map angle looking down, roof ridge running East-West with northern roof slopes dominant from above, solid dark timber lattice back wall foreshortened beneath eaves at bottom, zero entrance steps, clean rear ground baseline",
                "seed_offset": 2105,
            },
            {
                "variant_slug": "rot_west_flank",
                "name": "West Facing Temple Left Flank",
                "prompt_modifier": "steep top-down RPG map angle looking down, temple rotated 90 degrees with roof ridge running North-South, western glazed roof slope and triangular dougong gable end visible from high overhead, side lattice window and western wall foreshortened on left side",
                "seed_offset": 2104,
            },
            {
                "variant_slug": "rot_east_flank",
                "name": "East Facing Temple Right Flank",
                "prompt_modifier": "steep top-down RPG map angle looking down, temple rotated 90 degrees with roof ridge running North-South, eastern glazed roof slope and triangular dougong gable end visible from high overhead, side lattice window and eastern wall foreshortened on right side",
                "seed_offset": 2103,
            },
        ],
    },
    # 12. Cottage / Dwelling Structure Rotations (Bamboo Spirit Hermit Cottage)
    {
        "id": "ancient_china_low_cultivation.mortal_and_jianghu.bamboo_spirit_hermit_cottage",
        "asset_slug": "bamboo_spirit_hermit_cottage",
        "name": "Bamboo Spirit Hermit Cottage",
        "vietnamese_name": "Trúc Lâm Ẩn Sĩ Thảo Lư",
        "domain": "mortal_and_jianghu",
        "sub_domain": "hermit_dwellings",
        "asset_class": "structure_cottage",
        "type": "prop",
        "material": "woven split bamboo walls, thick golden thatched straw roof eaves, dark cedar stilts and corner posts",
        "footprint_cells": [2, 2],
        "canvas_px": [256, 256],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Bamboo Grove",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "rot_south_facade",
                "name": "South Facing Cottage Front Facade",
                "prompt_modifier": "steep top-down RPG map angle looking down, golden thatched straw roof dominant from overhead, front veranda porch and entrance steps visible foreshortened at bottom-center, open doorway showing interior tea table",
                "seed_offset": 2201,
            },
            {
                "variant_slug": "rot_north_rear",
                "name": "North Facing Cottage Rear Wall",
                "prompt_modifier": "steep top-down RPG map angle looking down, thatched roof ridge running East-West with northern thatch slope dominant from overhead, solid woven bamboo back wall foreshortened beneath eaves at bottom, clay chimney pipe on rear roof, zero entrance steps, clean rear ground baseline",
                "seed_offset": 2203,
            },
            {
                "variant_slug": "rot_west_flank",
                "name": "West Facing Cottage Left Flank",
                "prompt_modifier": "steep top-down RPG map angle looking down, cottage rotated 90 degrees with thatched roof ridge running North-South, western thatch roof slope and gable end visible from high overhead, circular bamboo lattice window and stilt column footing foreshortened on left side",
                "seed_offset": 2204,
            },
            {
                "variant_slug": "rot_east_flank",
                "name": "East Facing Cottage Right Flank",
                "prompt_modifier": "steep top-down RPG map angle looking down, cottage rotated 90 degrees with thatched roof ridge running North-South, eastern thatch roof slope and gable end visible from high overhead, circular bamboo lattice window and veranda railing foreshortened on right side, small clay chimney on rear roof",
                "seed_offset": 2202,
            },
        ],
    },
    # 13. Mountain Landmark Spire Rotations (Azure Cloud Karst Peak Spire)
    {
        "id": "ancient_china_low_cultivation.terrain_and_geology.azure_cloud_karst_peak_spire",
        "asset_slug": "azure_cloud_karst_peak_spire",
        "name": "Azure Cloud Karst Peak Spire",
        "vietnamese_name": "Thanh Vân Thạch Phong Tiêm Nhai",
        "domain": "terrain_and_geology",
        "sub_domain": "karst_formations",
        "asset_class": "landmark_mountain",
        "type": "prop",
        "material": "ancient sheer vertical grey karst limestone monolith with horizontal mineral strata, weathered crags, gnarled green cliff pine on middle rocky ledge",
        "footprint_cells": [2, 3],
        "canvas_px": [256, 384],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Karst Mountain Spires",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "facing_south_front",
                "name": "South Facing Broad Mountain Front",
                "prompt_modifier": "steep top-down RPG map angle looking down onto mountain landmark, summit crest and rocky upper plateau terrace dominant from above, twisted green cliff pine canopy spreading over middle ledge, stepped limestone crag tiers descending toward camera",
                "seed_offset": 2311,
            },
            {
                "variant_slug": "facing_north_back",
                "name": "North Facing Sheer Mountain Rear",
                "prompt_modifier": "steep top-down RPG map angle looking down onto mountain landmark from behind, sheer northern limestone rock face and upper summit plateau surface dominant from overhead, weathered crag terraces descending away from summit, zero trees on northern rock wall",
                "seed_offset": 2313,
            },
            {
                "variant_slug": "facing_west_left",
                "name": "West Facing Mountain Left Profile",
                "prompt_modifier": "steep top-down RPG map angle looking down onto mountain landmark rotated 90 degrees, elongated rock ridge running North-South, narrow summit crest and western stepped cliff strata seen from high overhead, protruding pine branch visible on left side",
                "seed_offset": 2314,
            },
            {
                "variant_slug": "facing_east_profile",
                "name": "East Facing Slender Spire Profile",
                "prompt_modifier": "steep top-down RPG map angle looking down onto mountain landmark rotated 90 degrees, elongated rock ridge running North-South, narrow summit crest and eastern stepped cliff strata seen from high overhead, protruding pine branch visible on right side",
                "seed_offset": 2312,
            },
        ],
    },
    # 14. Structure / 4-Way Directional Rotation Set: Sect Mountain Gate
    {
        "id": "ancient_china_low_cultivation.sect_facilities_and_dwellings.azure_cloud_mountain_gate_rotations",
        "asset_slug": "azure_cloud_mountain_gate_rotations",
        "name": "Azure Cloud Mountain Gate (4-Way Rotations)",
        "vietnamese_name": "Thanh Vân Sơn Môn Bài Lâu (Tứ Hướng)",
        "domain": "sect_facilities_and_dwellings",
        "sub_domain": "sect_architecture",
        "asset_class": "structure_building",
        "type": "prop",
        "material": "vermilion lacquered cedar columns, multi-tiered dougong brackets, emerald glazed ceramic tiles",
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
                "variant_slug": "rot_south_facade",
                "name": "South Facing Mountain Gate Facade",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, broad multi-tier emerald glazed roof dominant from above, vermilion entrance portal and courtyard steps visible foreshortened at bottom-center",
                "seed_offset": 2401,
            },
            {
                "variant_slug": "rot_north_rear",
                "name": "North Facing Mountain Gate Rear",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, broad emerald roof hip dominant from above, solid timber lintel beam and foundation base at bottom, zero entrance steps, clean rear ground baseline",
                "seed_offset": 2403,
            },
            {
                "variant_slug": "rot_west_flank",
                "name": "West Facing Mountain Gate Left Flank",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, gate rotated 90 degrees with roof ridge running North-South, western roof hip and side dougong brackets dominant from overhead, western support pillars visible on left",
                "seed_offset": 2404,
            },
            {
                "variant_slug": "rot_east_flank",
                "name": "East Facing Mountain Gate Right Flank",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, gate rotated 90 degrees with roof ridge running North-South, eastern roof hip and side dougong brackets dominant from overhead, eastern support pillars visible on right",
                "seed_offset": 2402,
            },
        ],
    },
    # 15. Structure / 4-Way Directional Rotation Set: Pill Alchemy Pavilion
    {
        "id": "ancient_china_low_cultivation.sect_facilities_and_dwellings.pill_alchemy_pavilion_rotations",
        "asset_slug": "pill_alchemy_pavilion_rotations",
        "name": "Pill Alchemy Pavilion (4-Way Rotations)",
        "vietnamese_name": "Luyện Đan Các Đình Đài (Tứ Hướng)",
        "domain": "sect_facilities_and_dwellings",
        "sub_domain": "alchemy_facilities",
        "asset_class": "structure_building",
        "type": "prop",
        "material": "weathered granite foundation, dark camphor timber frame, cinnabar glazed ceramic roof tiles",
        "footprint_cells": [3, 3],
        "canvas_px": [384, 384],
        "pivot": "bottom_center",
        "alpha": "cutout",
        "collision_type": "solid",
        "environment_name": "Sect Alchemy Grounds",
        "world_tier": "Low Cultivation",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contours",
        "variants": [
            {
                "variant_slug": "rot_south_facade",
                "name": "South Facing Alchemy Pavilion Facade",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, cinnabar roof surface dominant from above, front double doors open showing interior alchemy furnace, front steps descending at bottom-center",
                "seed_offset": 2501,
            },
            {
                "variant_slug": "rot_north_rear",
                "name": "North Facing Alchemy Pavilion Rear",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, northern cinnabar roof slope dominant from above, solid timber back wall, twin bronze roof chimney flues at rear, zero steps at bottom",
                "seed_offset": 2503,
            },
            {
                "variant_slug": "rot_west_flank",
                "name": "West Facing Alchemy Pavilion Left Flank",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, pavilion rotated 90 degrees with roof ridge running North-South, western roof slope and gable end dominant, circular Bagua vent window on left side",
                "seed_offset": 2504,
            },
            {
                "variant_slug": "rot_east_flank",
                "name": "East Facing Alchemy Pavilion Right Flank",
                "prompt_modifier": "steep high-angle top-down RPG map camera at 65-70 degrees looking down from overhead, pavilion rotated 90 degrees with roof ridge running North-South, eastern roof slope and gable end dominant, octagonal lattice window on right side",
                "seed_offset": 2502,
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

                    # Post-process VFX assets: convert black background to clean transparent alpha
                    if cand.get("asset_class") == "vfx_particle" or "vfx" in cand.get("domain", ""):
                        with Image.open(out_path) as raw_img:
                            if raw_img.mode == "RGB":
                                alpha_img = convert_black_bg_to_alpha(raw_img)
                                alpha_img.save(out_path, format="PNG", optimize=True)
                                print(
                                    f"     [POST-PROCESS] Converted black background to alpha: {out_path.name}"
                                )

                    success = True
                    break
                except ToolError as te:
                    if "refusing to overwrite" in str(te):
                        # Ensure any existing VFX candidate has black converted to alpha
                        matches = list(
                            (REPO_ROOT / "build" / out_subfolder).glob(f"*{c_slug}*{seed}*")
                        )
                        if matches and (
                            cand.get("asset_class") == "vfx_particle"
                            or "vfx" in cand.get("domain", "")
                        ):
                            with Image.open(matches[0]) as raw_img:
                                if raw_img.mode == "RGB":
                                    alpha_img = convert_black_bg_to_alpha(raw_img)
                                    alpha_img.save(matches[0], format="PNG", optimize=True)
                                    print(
                                        f"     [POST-PROCESS] Converted existing black background to alpha: {matches[0].name}"
                                    )
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


def audit_candidates(base_seed: int = 8800) -> int:
    """Audit all registered candidates and variants against generated assets."""
    print("=== Auditing Candidate Archetype Variants ===")
    total_expected = 0
    total_found = 0
    total_valid = 0
    missing = []
    errors = []

    tests_dir = REPO_ROOT / "build" / "candidate_tests"

    for idx, cand in enumerate(CANDIDATES, 1):
        c_slug = cand["asset_slug"]
        c_name = cand["name"]
        variants = cand.get("variants", [])
        cand_dir = tests_dir / c_slug

        print(f"\n{idx}. [{cand['asset_class']}] {c_name} ({len(variants)} variants)")
        for var in variants:
            v_slug = var["variant_slug"]
            v_name = var["name"]
            seed = base_seed + var.get("seed_offset", 0)
            total_expected += 1

            matches = list(cand_dir.glob(f"*{seed}*.png")) if cand_dir.exists() else []
            if not matches and cand_dir.exists():
                matches = list(cand_dir.glob(f"*{v_slug}*.png"))

            if not matches:
                missing.append(f"{c_slug}/{v_slug} (seed {seed})")
                print(f"  [MISSING] {v_slug}: {v_name} (seed={seed})")
                continue

            target_file = matches[0]
            total_found += 1

            try:
                with Image.open(target_file) as img:
                    img.verify()
                with Image.open(target_file) as img:
                    w, h = img.size
                    mode = img.mode
                total_valid += 1
                print(
                    f"  [OK] {v_slug}: {target_file.name} ({w}x{h}, {mode}, {target_file.stat().st_size / 1024:.1f} KB)"
                )
            except Exception as e:
                errors.append(f"{target_file.name}: {e}")
                print(f"  [ERROR] {v_slug}: {target_file.name} -> {e}")

    print("\n" + "=" * 50)
    print(f"Total Expected Variants: {total_expected}")
    print(f"Total Found Assets:      {total_found} / {total_expected}")
    print(f"Total Valid Images:      {total_valid} / {total_expected}")

    if missing:
        print(f"\nMissing Variants ({len(missing)}):")
        for m in missing:
            print(f"  - {m}")

    if errors:
        print(f"\nImage Corruption Errors ({len(errors)}):")
        for err in errors:
            print(f"  - {err}")

    if total_valid == total_expected and not missing and not errors:
        print("\nAll candidate variants generated and verified with 100% integrity!")
        return 0
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Test Candidate Archetypes Generator")
    parser.add_argument(
        "--candidate", "-c", help="Specific candidate slug (e.g. crescent_spirit_herb_sickle)"
    )
    parser.add_argument("--variant", "-v", help="Specific variant slug (e.g. pristine)")
    parser.add_argument("--seed", type=int, default=8800, help="Base seed")
    parser.add_argument("--list", action="store_true", help="List all candidate archetypes")
    parser.add_argument(
        "--audit", action="store_true", help="Audit all generated candidate variants"
    )

    args = parser.parse_args(argv)

    if args.list:
        print("Registered Candidate Archetypes:")
        for idx, c in enumerate(CANDIDATES, 1):
            print(
                f"{idx}. [{c['asset_class']}] {c['asset_slug']} - {c['name']} ({len(c['variants'])} variants)"
            )
        return 0

    if args.audit:
        return audit_candidates(base_seed=args.seed)

    return run_candidate_test(
        candidate_slug=args.candidate,
        variant_slug=args.variant,
        base_seed=args.seed,
    )


if __name__ == "__main__":
    raise SystemExit(main())
