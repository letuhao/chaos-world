# -*- coding: utf-8 -*-
"""Comprehensive Generator for Medieval Western 48 Categories Specification."""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/medieval_western"
CATEGORIES_PATH = PACK_DIR / "categories.json"

CATEGORIES = [
    # =========================================================================
    # SPHERE I: THE CULTURAL CROSSROADS (8 Categories, 900 Assets)
    # =========================================================================
    {
        "id": "anglo_norman_feudal_heartland",
        "name": "Anglo-Norman Feudal Heartland",
        "vietnamese_name": "Trọng Tâm Phong Kiến Anglo-Norman",
        "sphere": "Cultural Crossroads",
        "description": "Motte-and-bailey timber stockades, square keeps, Norman chevron arch carvings, heavy oak halls, chivalric court seats.",
        "sub_categories": [
            "motte_and_bailey_earthwork",
            "square_norman_donjon_keep",
            "chevron_carved_stone_archway",
            "great_hall_oak_dais",
            "feudal_homage_court_furnishing"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "culture_affinity": "anglo_norman",
            "feudal_tier": "baronial_court",
            "oath_system": "fealty_and_homage"
        }
    },
    {
        "id": "hanseatic_and_flemish_burgher",
        "name": "Hanseatic & Flemish Burgher Town",
        "vietnamese_name": "Đô Thị Phường Hội Hanseatic & Flanders",
        "sphere": "Cultural Crossroads",
        "description": "Backsteingotik red-brick stepped gables, canal lock gates, cloth halls, weighing houses (Waag), guild counting houses, leaded bay windows.",
        "sub_categories": [
            "stepped_gable_brick_facade",
            "canal_water_lock_and_embankment",
            "cloth_hall_and_weigh_house",
            "guild_merchant_counting_room",
            "belfry_curfew_bell_spire"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "culture_affinity": "flemish_hanseatic",
            "merchant_banking": "letter_of_credit",
            "guild_privilege": "hanseatic_charter"
        }
    },
    {
        "id": "nordic_and_norse_coastal",
        "name": "Nordic & Norse Coastal Settlement",
        "vietnamese_name": "Khu Định Cư Ven Biển Bắc Âu & Norse",
        "sphere": "Cultural Crossroads",
        "description": "Turf-roofed longhouses, dragon-carved stave pillars, runic memorial stones, boathouses (naust), whalebone arches, drying cod racks.",
        "sub_categories": [
            "turf_roofed_timber_longhouse",
            "stave_pillar_dragon_carving",
            "runestone_monument_and_grave",
            "boathouse_naust_and_skiff",
            "whalebone_arch_and_stockfish"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "culture_affinity": "nordic_norse",
            "seafaring_weathering": "salt_and_frost_resistant",
            "ancestral_rites": "runic_inscription"
        }
    },
    {
        "id": "mediterranean_and_moorish_quarter",
        "name": "Mediterranean & Moorish Quarter",
        "vietnamese_name": "Khu Phố Địa Trung Hải & Moorish (Al-Andalus)",
        "sphere": "Cultural Crossroads",
        "description": "Arcaded cool courtyards (patios), azulejo glazed tile fountains, terracotta tiled roofs, olive oil presses, spice souks, whitewashed stucco walls.",
        "sub_categories": [
            "arcaded_patio_courtyard",
            "azulejo_glazed_tile_fountain",
            "terracotta_stucco_villa_wall",
            "olive_press_and_citrus_grove",
            "spice_bazaar_and_silk_alcove"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "culture_affinity": "mediterranean_moorish",
            "hydraulic_system": "cistern_and_aqueduct",
            "exotic_trade": ["spices", "silk", "olive_oil"]
        }
    },
    {
        "id": "slavic_eastern_taiga_and_logcraft",
        "name": "Slavic Eastern Taiga & Logcraft",
        "vietnamese_name": "Làng Gỗ Rừng Taiga Đông Slav (Kievan Rus)",
        "sphere": "Cultural Crossroads",
        "description": "Interlocking round-log cabins (izbas), wooden kremlins (gorodishche), carved window frames (nalichniki), onion-domed timber chapels, fur-trading posts.",
        "sub_categories": [
            "interlocking_log_izba_cabin",
            "wooden_kremlin_rampart_wall",
            "onion_domed_timber_chapel",
            "carved_window_nalichniki_frame",
            "taiga_fur_trappers_post"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "culture_affinity": "slavic_rus",
            "winter_insulation": "russian_clay_stove",
            "commodity_trade": "fine_furs_and_amber"
        }
    },
    {
        "id": "celtic_highland_and_atlantic_fringe",
        "name": "Celtic Highland & Atlantic Fringe",
        "vietnamese_name": "Vùng Cao Nguyên & Rìa Đại Tây Dương Celtic",
        "sphere": "Cultural Crossroads",
        "description": "Drystone broch towers, lake crannogs, turf beehive huts (clochán), high Celtic wheel crosses, peat fire hearths, holy wells with votive ribbons.",
        "sub_categories": [
            "circular_drystone_broch_tower",
            "lake_dwelling_crannog_jetty",
            "turf_beehive_clochan_hut",
            "celtic_wheel_high_cross",
            "peat_fire_hearth_and_well"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "culture_affinity": "celtic_gaelic",
            "clan_structure": "highland_kinship",
            "holy_sites": "cloutie_well_offering"
        }
    },
    {
        "id": "byzantine_and_crusader_frontier",
        "name": "Byzantine & Crusader Outposts",
        "vietnamese_name": "Tiền Đồn Byzantine & Thập Tự Quân",
        "sphere": "Cultural Crossroads",
        "description": "Rough limestone border watchtowers with stone hoardings, Byzantine brick-mortar layers, orthodox roadside icon shrines, caravanserai courtyards.",
        "sub_categories": [
            "crusader_limestone_curtain_wall",
            "byzantine_brick_and_stone_band",
            "roadside_iconostasis_shrine",
            "caravanserai_walled_compound",
            "border_beacon_watchtower"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "culture_affinity": "byzantine_crusader",
            "fortification_type": "concentric_frontier_redoubt",
            "caravan_rest": "caravanserai_hospitality"
        }
    },
    {
        "id": "wayfarers_nomads_and_tinker_camps",
        "name": "Wayfarers, Nomads & Tinker Camps",
        "vietnamese_name": "Khu Cắm Trại Dân Du Mục & Thợ Hàn Nồi",
        "sphere": "Cultural Crossroads",
        "description": "Barrel-top wooden vardo wagons, horse tether lines, tinker metalwork bellows, campfire fiddles, fortune-telling tapestries, wanderer canvas lean-tos.",
        "sub_categories": [
            "barrel_top_wooden_vardo_wagon",
            "tinker_brazier_and_tin_pots",
            "nomad_canvas_wedge_tent",
            "horse_tether_line_and_saddles",
            "campfire_circle_and_instruments"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "lifestyle": "itinerant_travelers",
            "repair_services": "traveling_metal_tinker",
            "folk_entertainment": "wandering_minstrels"
        }
    },

    # =========================================================================
    # SPHERE II: BUILT ARCHITECTURE & FORTIFICATIONS (6 Categories, 800 Assets)
    # =========================================================================
    {
        "id": "modular_timber_frame_fachwerk",
        "name": "Modular Timber-Frame (Fachwerk)",
        "vietnamese_name": "Kiến Trúc Khung Gỗ Fachwerk Lắp Ghép",
        "sphere": "Built Architecture",
        "description": "European half-timbering: cruck frames, jetty bays, wattle-daub, leaded diamond windows, thatch eaves, clay tile gables, dormers.",
        "sub_categories": [
            "cruck_blade_and_tie_beam",
            "jetty_cantilever_bracket_bay",
            "wattle_daub_and_brick_infill",
            "leaded_diamond_casement_window",
            "roof_gable_thatch_and_tile",
            "veranda_porch_and_dormer"
        ],
        "planned_count": 160,
        "gameplay_gap_hooks": {
            "assembly_grid": "modular_building_snap_128",
            "material_grades": ["rustic_oak", "dressed_timber", "painted_fachwerk"],
            "insulation_value": "temperate_climate"
        }
    },
    {
        "id": "village_cottages_and_serf_hovels",
        "name": "Village Cottages & Serf Hovels",
        "vietnamese_name": "Nhà Tranh Thôn Xóm & Túp Lều Nông Nô",
        "sphere": "Built Architecture",
        "description": "Peasant turf huts, smoke-hole thatch hovels, mud-cob walls, outdoor clay bread ovens, drystone dykes, dog kennels, woodpiles.",
        "sub_categories": [
            "peasant_turf_roofed_hovel",
            "wattle_thatched_cottage_dwelling",
            "outdoor_clay_bread_oven",
            "drystone_boundary_wall_and_stile",
            "homestead_woodpile_and_shed"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "social_tier": "serf_and_villager",
            "manorial_rent": "labor_corvee",
            "domestic_recovery": "straw_mattress_rest"
        }
    },
    {
        "id": "castles_curtain_walls_and_bastions",
        "name": "Castles, Curtain Walls & Bastions",
        "vietnamese_name": "Lâu Đài, Tường Thành Đá & Pháo Đài",
        "sphere": "Built Architecture",
        "description": "Ashlar curtain walls, sloped talus bases, battlements, machicolation overhangs, drum bastions, barbicans, portcullises, murder holes, moats.",
        "sub_categories": [
            "ashlar_curtain_wall_and_talus",
            "crenellation_and_hoarding_crest",
            "round_drum_and_square_tower",
            "gatehouse_barbican_and_portcullis",
            "moat_ditch_and_sloping_bank",
            "arrow_slit_and_intramural_stairs"
        ],
        "planned_count": 180,
        "gameplay_gap_hooks": {
            "defense_rating": "heavy_concentric_fortress",
            "breach_resistance": "siege_resistant",
            "arrow_slits": "projectile_firing_port"
        }
    },
    {
        "id": "palace_keeps_and_royal_chambers",
        "name": "Palace Keeps & Royal Chambers",
        "vietnamese_name": "Đại Điện Cung Điện & Phòng Hoàng Gia",
        "sphere": "Built Architecture",
        "description": "Carved oak thrones, feasting trestle tables, heraldic tapestries, monumental fireplaces, four-poster canopy beds, chancery scriptoria.",
        "sub_categories": [
            "throne_dais_and_royal_canopy",
            "great_hall_feasting_trestles",
            "monumental_carved_stone_hearth",
            "four_poster_oak_bedchamber",
            "chivalric_heraldic_tapestry",
            "chancery_and_treasury_chests"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "authority_zone": "monarch_and_high_lord",
            "audience_diplomacy": "feudal_petition",
            "treasury_storage": "royal_bullion_vault"
        }
    },
    {
        "id": "garrisons_barracks_and_watchtowers",
        "name": "Garrisons, Barracks & Watchtowers",
        "vietnamese_name": "Doanh Trại Đồn Trú & Tháp Canh Biên Giới",
        "sphere": "Built Architecture",
        "description": "Border stone watchtowers, garrison bunkhouses, armory weapon racks, archery shooting butts, signal beacon fire baskets.",
        "sub_categories": [
            "border_stone_watchtower",
            "soldiers_timber_bunkhouse",
            "armory_rack_spears_and_halberds",
            "archery_practice_butt_range",
            "signal_fire_beacon_turret"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "garrison_spawn": "feudal_men_at_arms",
            "alarm_beacon": "signal_smoke_call",
            "weapons_depot": "restock_munitions"
        }
    },
    {
        "id": "city_gates_bridges_and_portals",
        "name": "City Gates, Bridges & Portals",
        "vietnamese_name": "Cổng Thành, Cầu Đá & Trạm Thu Phí",
        "sphere": "Built Architecture",
        "description": "Twin-towered town gates, toll booths, curfew bell towers, Norman stone barrel-arch bridges, timber ox-cart trestles, river fords.",
        "sub_categories": [
            "twin_towered_city_gatehouse",
            "norman_barrel_arch_stone_bridge",
            "timber_oxcart_trestle_bridge",
            "curfew_bell_and_toll_station",
            "river_ford_and_stepping_stones"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "chokepoint_security": "gate_inspection_and_toll",
            "river_transit": "high_load_bridge",
            "curfew_rules": "night_closure"
        }
    },

    # =========================================================================
    # SPHERE III: FAITH, MONASTICISM, MORTALITY & OCCULT (7 Cats, 760 Assets)
    # =========================================================================
    {
        "id": "gothic_cathedrals_and_monumental_abbeys",
        "name": "Gothic Cathedrals & Monumental Abbeys",
        "vietnamese_name": "Đại Giáo Đường Gothic & Tu Viện Kỳ Vĩ",
        "sphere": "Faith & Mortality",
        "description": "Pointed arch portals, carved tympanums, flying buttresses, rose stained glass windows, high marble altars, choir stalls, reliquary chasses.",
        "sub_categories": [
            "pointed_portal_and_tympanum",
            "flying_buttress_and_pinnacle",
            "rose_stained_glass_window",
            "carrara_marble_high_altar",
            "choir_stalls_and_misericords",
            "golden_saint_reliquary_chasse"
        ],
        "planned_count": 140,
        "gameplay_gap_hooks": {
            "sanctuary_law": "ecclesiastical_immunity",
            "divine_favor": "cathedral_mass_buff",
            "liturgical_calendar": "holy_feast_days"
        }
    },
    {
        "id": "monasteries_cloisters_and_scriptoria",
        "name": "Monasteries, Cloisters & Scriptoria",
        "vietnamese_name": "Hành Lang Tu Viện & Phòng Chép Kinh",
        "sphere": "Faith & Mortality",
        "description": "Arcaded cloister walks, lavabo fountains, scriptorium manuscript desks, herb drying ceiling racks, refectory tables, monk cell cots.",
        "sub_categories": [
            "arcaded_monastic_cloister_walk",
            "octagonal_stone_lavabo_fountain",
            "scriptorium_manuscript_desk",
            "monastery_herb_drying_racks",
            "refectory_table_and_cell_cot"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "scholarly_craft": "manuscript_illumination",
            "apothecary_brewing": "herbal_remedies",
            "monastic_rule": "benedictine_routine"
        }
    },
    {
        "id": "parish_chapels_and_wayside_shrines",
        "name": "Parish Chapels & Wayside Shrines",
        "vietnamese_name": "Nhà Nguyện Giáo Xứ & Miếu Thờ Ven Đường",
        "sphere": "Faith & Mortality",
        "description": "Village stone chapels, thatched hermit huts, roadside Madonna shrines, holy wellsprings, penitent stone prayer benches.",
        "sub_categories": [
            "fieldstone_village_parish_chapel",
            "thatched_hermit_forest_hut",
            "roadside_timber_madonna_shrine",
            "holy_votive_wellspring",
            "penitent_kneeling_stone_bench"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "pilgrim_waypoint": "blessing_of_safe_travel",
            "confession": "forgive_sins_and_karma",
            "communal_burial": "parish_record_keeping"
        }
    },
    {
        "id": "graveyards_crypts_and_charnel_houses",
        "name": "Graveyards, Crypts & Charnel Houses",
        "vietnamese_name": "Nghĩa Trang, Hầm Mộ & Nhà Chứa Xương",
        "sphere": "Faith & Mortality",
        "description": "Slate headstones, Celtic wheel crosses, knightly effigy sarcophagi (gisants), charnel house skull walls, weeping yew trees, lychgates.",
        "sub_categories": [
            "weathered_slate_headstone",
            "knightly_gisant_stone_sarcophagus",
            "skull_ossuary_charnel_wall",
            "covered_timber_lychgate_porch",
            "consecrated_weeping_yew_tree"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "spiritual_ground": "consecrated_vs_unconsecrated",
            "undead_boundary": "ward_against_ghouls",
            "mourning_rites": "grave_offerings"
        }
    },
    {
        "id": "medieval_alchemy_and_natural_philosophy",
        "name": "Medieval Alchemy & Natural Philosophy",
        "vietnamese_name": "Giả Kim Thuật & Triết Học Tự Nhiên",
        "sphere": "Faith & Mortality",
        "description": "Athanor slow-combustion ovens, glass alembics, retorts, brass armillary spheres, dried mandrake roots, celestial star charts.",
        "sub_categories": [
            "athanor_brick_slow_furnace",
            "glass_alembic_distillation_bench",
            "brass_armillary_sphere_astrolabe",
            "celestial_parchment_star_chart",
            "apothecary_cabinet_and_mortars"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "esoteric_crafting": "transmutation_and_tincture",
            "astrological_alignment": "planetary_influence",
            "philosophical_heresy": "inquisition_suspicion"
        }
    },
    {
        "id": "witchcraft_folklore_and_bog_magic",
        "name": "Witchcraft, Folklore & Bog Magic",
        "vietnamese_name": "Phù Thủy, Phong Tục Dân Gian & Phép Đầm Lầy",
        "sphere": "Faith & Mortality",
        "description": "Peat bog witch stilt huts, boiling iron cauldrons, animal skull charms, wicker effigies, cursed fairy rings, protective hex marks.",
        "sub_categories": [
            "stilt_bog_witch_dwelling",
            "bubbling_iron_cauldron_brazier",
            "animal_skull_totem_and_fetish",
            "woven_wicker_effigy_man",
            "toadstool_fairy_ring_circle"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "folk_curses": "evil_eye_and_hex",
            "forbidden_foraging": "black_henbane_and_nightshade",
            "pagan_survivals": "seasonal_solstice_fire"
        }
    },
    {
        "id": "plague_lazarettos_and_quarantine",
        "name": "Plague Lazarettos & Quarantine",
        "vietnamese_name": "Trại Phong Hủi & Khu Cách Ly Dịch Bệnh",
        "sphere": "Faith & Mortality",
        "description": "Leper isolation wards, warning wooden clappers, plague quarantine chalk door crosses, aromatic herb burning pans, mass burial pits.",
        "sub_categories": [
            "leper_lazar_house_isolation_hut",
            "wooden_warning_clapper_post",
            "plague_marked_chalk_cross_door",
            "aromatic_fumigation_fire_pan",
            "quicklime_mass_burial_plague_pit"
        ],
        "planned_count": 90,
        "gameplay_gap_hooks": {
            "contagion_hazard": "black_death_infection",
            "isolation_cordon": "quarantine_enforcement",
            "penitence_movement": "flagellant_procession"
        }
    },

    # =========================================================================
    # SPHERE IV: MANORIAL SUPPLY CHAINS & GUILDS (10 Cats, 1,140 Assets)
    # =========================================================================
    {
        "id": "grain_agriculture_and_harvesting",
        "name": "Grain Agriculture & Harvesting",
        "vietnamese_name": "Canh Tác Lúa Mì & Thu Hoạch Mùa Màng",
        "sphere": "Manorial Supply Chains",
        "description": "Ridge-and-furrow wheat plots, barley rows, heavy wheeled moldboard plows, scythes, sickles, wheat sheaves, conical hayricks.",
        "sub_categories": [
            "ridge_and_furrow_wheat_strip",
            "wheeled_moldboard_carruca_plow",
            "harvesting_scythe_and_sheaves",
            "four_wheeled_hay_wain_wagon",
            "conical_thatched_hayrick_stack",
            "staddle_stone_raised_granary"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "crop_cycle": "three_field_rotation",
            "staple_yield": "flour_and_bread",
            "tithe_fraction": "one_tenth_to_church"
        }
    },
    {
        "id": "pastoralism_livestock_and_dairy",
        "name": "Pastoralism, Livestock & Dairy",
        "vietnamese_name": "Chăn Thả Gia Súc & Chế Biến Bơ Sữa",
        "sphere": "Manorial Supply Chains",
        "description": "Hillside drystone sheepfolds, cattle feeding mangers, sheep shearing trestles, pig wallow pens, straw bee skeps, dairy butter churns.",
        "sub_categories": [
            "drystone_hillside_sheepfold",
            "covered_cattle_manger_trough",
            "sheep_shearing_timber_trestle",
            "timber_fenced_pig_wallow_pen",
            "thatched_straw_bee_skep_apiary",
            "dairy_butter_churn_and_press"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "pastoral_products": ["wool", "cheese", "butter", "mutton", "honey"],
            "transhumance": "summer_upland_pasture"
        }
    },
    {
        "id": "orchards_vineyards_and_brewing",
        "name": "Orchards, Vineyards & Brewing",
        "vietnamese_name": "Vườn Cây Ăn Trái, Vườn Nho & Lò Nấu Rượu",
        "sphere": "Manorial Supply Chains",
        "description": "Apple espaliers, grape trellises, wooden screw wine presses, copper mash tuns, fermenting vats, stacked oak beer hogsheads.",
        "sub_categories": [
            "cider_apple_espalier_trees",
            "terraced_grape_vineyard_trellis",
            "wooden_screw_wine_cider_press",
            "copper_mash_tun_brewing_kettle",
            "oak_fermenting_vat_and_casks"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "beverage_economy": ["ale", "cider", "wine", "mead"],
            "seasonal_press": "grape_harvest_vendange"
        }
    },
    {
        "id": "watermills_windmills_and_milling",
        "name": "Watermills, Windmills & Milling",
        "vietnamese_name": "Cối Xay Nước, Cối Xay Gió & Xay Xát",
        "sphere": "Manorial Supply Chains",
        "description": "Overshot waterwheels, millraces, sluice gates, canvas-rigged post windmills, granite millstones in octagonal casings.",
        "sub_categories": [
            "overshot_timber_waterwheel",
            "millrace_raised_wooden_flume",
            "millstone_pair_in_vat_casing",
            "post_windmill_timber_structure",
            "sluice_control_gate_and_winch"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "manorial_monopoly": "lord_milling_ban",
            "power_generation": ["hydro_kinetic", "aeolian_wind"],
            "output_milling": "fine_white_and_whole_meal"
        }
    },
    {
        "id": "blacksmithing_and_metal_refining",
        "name": "Blacksmithing & Metal Refining",
        "vietnamese_name": "Rèn Đúc Sắt Thép & Tinh Luyện Kim Loại",
        "sphere": "Manorial Supply Chains",
        "description": "Hearth forges with leather bellows, heavy anvils, quench troughs, swage blocks, iron bloomery smelters, charcoal burner mounds.",
        "sub_categories": [
            "hearth_forge_with_leather_bellows",
            "heavy_anvil_on_oak_trunk",
            "brine_quench_trough_and_tongs",
            "clay_lined_bloomery_iron_furnace",
            "charcoal_burning_earthen_mound"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "metallurgy": "bloomery_wrought_iron",
            "crafting_recipes": ["plowshares", "horseshoe", "broadsword", "armor_plate"],
            "fuel_demand": "charcoal_burning"
        }
    },
    {
        "id": "forestry_timber_and_cooperage",
        "name": "Forestry, Timber & Cooperage",
        "vietnamese_name": "Lâm Nghiệp, Xẻ Gỗ & Đóng Thùng",
        "sphere": "Manorial Supply Chains",
        "description": "Sawpit trenches with two-man saws, shaving horses, cooper barrel-trussing braziers, iron barrel hoops, seasoning lumber stacks.",
        "sub_categories": [
            "two_man_sawpit_trench_log",
            "woodworkers_shaving_horse_bench",
            "cooper_barrel_trussing_brazier",
            "stacked_air_drying_lumber_planks",
            "wheelwright_coach_tire_jack"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "timber_yield": ["heart_oak", "ash_shafts", "yew_staves", "pine_planks"],
            "cooper_production": "watertight_casks_and_tuns"
        }
    },
    {
        "id": "wool_textile_and_dyeing_guilds",
        "name": "Wool, Textile & Dyeing Guilds",
        "vietnamese_name": "Phường Hội Dệt Nỉ, Nhuộm Màu & Kéo Sợi",
        "sphere": "Manorial Supply Chains",
        "description": "Drop spindles, horizontal treadle looms, woad/madder dye vats, tenter field drying frames, water-powered fulling stocks.",
        "sub_categories": [
            "wool_distaff_and_drop_spindles",
            "horizontal_treadle_loom_frame",
            "copper_dye_vat_woad_and_madder",
            "outdoor_tenter_drying_frames",
            "water_powered_fulling_hammers"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "textile_export": "flemish_broadcloth",
            "dye_spectrum": ["woad_blue", "madder_red", "weld_yellow"],
            "guild_regulation": "staple_port_wool"
        }
    },
    {
        "id": "tannery_leatherwork_and_cordwaining",
        "name": "Tannery, Leatherwork & Cordwaining",
        "vietnamese_name": "Thuộc Da, Đóng Giày & Thuộc Bằng Vỏ Cây",
        "sphere": "Manorial Supply Chains",
        "description": "Oak-bark tanning pits, fleshing beams, hide stretching frames, lime slaking pits, cobbler lasts, leather currying tables.",
        "sub_categories": [
            "oak_bark_tan_liquor_soaking_pit",
            "tanners_curved_fleshing_beam",
            "cord_tensioned_hide_drying_frame",
            "stone_lined_lime_depilation_pit",
            "cobbler_workbench_lasts_and_awls"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "leather_products": ["cuirbouilli_armor", "bridles", "turnshoes", "scabbards"],
            "noxious_craft": "downwind_city_placement"
        }
    },
    {
        "id": "pottery_glassblowing_and_masonry",
        "name": "Pottery, Glassblowing & Masonry",
        "vietnamese_name": "Gốm Sứ, Thổi Thủy Tinh & Đẽo Đá",
        "sphere": "Manorial Supply Chains",
        "description": "Kick-wheel benches, beehive brick kilns, glassblower annealing furnaces, stonecutter banker benches, treadwheel lifting cranes.",
        "sub_categories": [
            "potters_kick_wheel_throwing_bench",
            "beehive_brick_pottery_kiln",
            "glassblower_melting_pot_furnace",
            "stonecutter_banker_bench_mallets",
            "treadwheel_timber_crane_hoist"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "mineral_craft": ["terracotta_roof_tile", "stained_glass", "dressed_ashlar"],
            "fire_hazard": "furnace_spark_danger"
        }
    },
    {
        "id": "mining_quarries_and_lime_kilns",
        "name": "Mining, Quarries & Lime Kilns",
        "vietnamese_name": "Khai Mỏ, Mỏ Đá & Lò Nung Vôi",
        "sphere": "Manorial Supply Chains",
        "description": "Open limestone quarry faces, timber-shored mine adits, wooden ore carts, mine drainage troughs, calcining lime kilns.",
        "sub_categories": [
            "stepped_limestone_quarry_face",
            "timber_shored_mine_adit_portal",
            "wooden_rail_flanged_ore_cart",
            "stone_calcining_mortar_lime_kiln",
            "mine_ventilation_bellows_pipe"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "ore_extraction": ["iron_bog_ore", "lead_ore", "silver_galena", "building_chalk"],
            "subterranean_hazards": "mine_flooding_and_cave_in"
        }
    },

    # =========================================================================
    # SPHERE V: COMMERCE, URBAN LIFE & HANSEATIC PORTS (5 Cats, 590 Assets)
    # =========================================================================
    {
        "id": "urban_street_markets_and_civic_life",
        "name": "Urban Street Markets & Civic Life",
        "vietnamese_name": "Chợ Đường Phố & Đời Sống Dân Cư Đô Thị",
        "sphere": "Commerce & Urban Life",
        "description": "Striped canvas market booths, public steelyard scales, town market crosses, town hall noticeboards, pillories, foot stocks.",
        "sub_categories": [
            "striped_canvas_market_booth",
            "town_square_gothic_market_cross",
            "civic_beam_steelyard_scales",
            "town_hall_proclamation_noticeboard",
            "public_pillory_and_foot_stocks"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "market_days": "weekly_charter_fair",
            "price_controls": "assize_of_bread_and_ale",
            "public_order": "watch_and_ward"
        }
    },
    {
        "id": "taverns_coaching_inns_and_alehouses",
        "name": "Taverns, Coaching Inns & Alehouses",
        "vietnamese_name": "Quán Rượu, Trạm Cỗ Xe & Quán Bia Cỏ",
        "sphere": "Commerce & Urban Life",
        "description": "Heavy oak bar counters, pewter mugs, central roast hearths, gaming tables (dice & cards), horse coaching stables, straw sleeping lofts.",
        "sub_categories": [
            "heavy_oak_tavern_bar_counter",
            "open_hearth_spit_roast_fireplace",
            "round_drinking_table_and_stools",
            "coaching_inn_horse_stables",
            "common_sleeping_pallet_loft"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "social_gathering": "rumor_and_bounty_leads",
            "hospitality": "ale_and_stew_buffs",
            "lodging_recovery": "inn_rest"
        }
    },
    {
        "id": "harbors_quays_and_hanseatic_cogs",
        "name": "Harbors, Quays & Hanseatic Cogs",
        "vietnamese_name": "Bến Cảng, Bờ Kè & Thuyền Buồm Cog",
        "sphere": "Commerce & Urban Life",
        "description": "Heavy oak timber quays, stone breakwaters, Hanseatic cogs, river punts, treadwheel harbor cranes, herring salting barrels, tollhouses.",
        "sub_categories": [
            "heavy_timber_wharf_piling_quay",
            "hanseatic_single_mast_cog_ship",
            "wharf_treadwheel_cargo_crane",
            "salted_herring_barrel_stack",
            "harbor_customs_tollhouse_station"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "maritime_shipping": "bulk_grain_and_timber",
            "customs_duty": "sound_toll_and_anchorage",
            "naval_repairs": "careening_and_pitch"
        }
    },
    {
        "id": "river_fisheries_waterways_and_ferries",
        "name": "River Fisheries, Waterways & Ferries",
        "vietnamese_name": "Nghề Cá Sông, Kênh Đào & Phà Bến Nước",
        "sphere": "Commerce & Urban Life",
        "description": "Clinker fishing rowboats, fish-drying nets, reed fish weirs, cable ferry landings, river toll booms, boathouse sheds.",
        "sub_categories": [
            "clinker_built_fishing_rowboat",
            "hanging_wind_drying_fish_nets",
            "wicker_eel_trap_and_fish_weir",
            "river_cable_ferry_wooden_dock",
            "water_toll_barrier_boom_chain"
        ],
        "planned_count": 100,
        "gameplay_gap_hooks": {
            "freshwater_harvest": ["river_eel", "salmon", "pike"],
            "ferry_transit": "cross_wide_estuary"
        }
    },
    {
        "id": "fairs_festivals_and_carnivals",
        "name": "Fairs, Festivals & Carnivals",
        "vietnamese_name": "Hội Chợ, Lễ Hội Mùa & Diễn Xướng",
        "sphere": "Commerce & Urban Life",
        "description": "Pageant miracle play wagons, puppet stages, flower-wound Maypoles, roasted whole ox spits, heraldic tournament lists, juggler props.",
        "sub_categories": [
            "miracle_play_pageant_wagon",
            "flower_wound_ribbon_maypole",
            "whole_roasted_ox_festival_spit",
            "jugglers_platform_and_troupe_tent",
            "colorful_heraldic_pennant_line"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "community_morale": "festival_celebration_buff",
            "mystery_plays": "religious_theatricals",
            "annual_charter": "exemption_from_tolls"
        }
    },

    # =========================================================================
    # SPHERE VI: WAR, SIEGE, CRIME & UNDERWORLD (5 Cats, 540 Assets)
    # =========================================================================
    {
        "id": "knighthood_tournaments_and_chivalry",
        "name": "Knighthood, Tournaments & Chivalry",
        "vietnamese_name": "Đấu Thương Hiệp Sĩ & Tinh Thần Thượng Võ",
        "sphere": "War & Underworld",
        "description": "Jousting tilt barriers, velvet royal viewing boxes, rotating quintains, weapon racks, knightly heraldic pavilions.",
        "sub_categories": [
            "cloth_draped_jousting_tilt_barrier",
            "velvet_canopied_royal_viewing_box",
            "rotating_shield_quintain_dummy",
            "suit_of_plate_armor_display_stand",
            "knights_two_pole_heraldic_pavilion"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "chivalric_honor": "courtly_reputation",
            "martial_contest": ["joust_of_peace", "melee_at_the_barriers"],
            "ransom_system": "capture_knight_and_horse"
        }
    },
    {
        "id": "siege_engines_and_heavy_artillery",
        "name": "Siege Engines & Heavy Artillery",
        "vietnamese_name": "Máy Bắn Đá, Vũ Khí Công Thành & Đột Kích",
        "sphere": "War & Underworld",
        "description": "Counterweight trebuchets, heavy ballistas, covered battering rams, mangonels, wheeled mantlets (pavises), siege trenches.",
        "sub_categories": [
            "counterweight_timber_trebuchet",
            "heavy_torsion_wheeled_ballista",
            "covered_rawhide_battering_ram",
            "wheeled_mantlet_pavise_screen",
            "approach_sapping_siege_trench"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "siege_destruction": "wall_breach_mechanic",
            "battering_gate": "destroy_portcullis",
            "ammunition": ["limestone_boulders", "fire_pots", "carcass_projectiles"]
        }
    },
    {
        "id": "military_camps_and_field_works",
        "name": "Military Camps & Field Works",
        "vietnamese_name": "Doanh Trại Quân Sự & Công Sự Dã Ngoại",
        "sphere": "War & Underworld",
        "description": "Conical canvas bell tents, officer marquees, camp cook cauldrons, weapon pyramids, chevaux-de-frise cavalry barriers, wicker gabions.",
        "sub_categories": [
            "conical_canvas_soldiers_bell_tent",
            "officer_striped_ridge_marquee",
            "field_mess_cook_iron_cauldron",
            "pyramid_stacked_halberds_and_pikes",
            "chevaux_de_frise_and_wicker_gabion"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "army_encampment": "mobilization_field_base",
            "cavalry_obstacle": "caltrop_and_stake_slowdown",
            "supply_attrition": "rations_and_forage"
        }
    },
    {
        "id": "battlefield_aftermath_and_ruins",
        "name": "Battlefield Aftermath & Ruins",
        "vietnamese_name": "Chiến Trường Tàn Tích & Dấu Vết Bại Trận",
        "sphere": "War & Underworld",
        "description": "Smashed wagons, stuck crossbow bolts, charred earth craters, tattered heraldic banners, broken polearms, open looting pits.",
        "sub_categories": [
            "shattered_supply_wagon_debris",
            "cluster_embedded_crossbow_bolts",
            "burnt_earth_and_scorched_crater",
            "mud_splattered_tattered_banner",
            "battlefield_scavenger_loot_pile"
        ],
        "planned_count": 90,
        "gameplay_gap_hooks": {
            "battlefield_scavenge": "broken_armor_and_salvage",
            "desolation_hazard": "unburied_carrion_disease",
            "war_trophies": "captured_standards"
        }
    },
    {
        "id": "outlaws_bandits_and_dungeon_depths",
        "name": "Outlaws, Bandits & Dungeon Depths",
        "vietnamese_name": "Sơn Tặc, Ngục Tối & Lòng Đất Hắc Ám",
        "sphere": "War & Underworld",
        "description": "Brushwood lean-tos, pitfall traps, roadside gallows, iron gibbets, hollow-tree caches, iron maiden, wall manacles, oubliette grates.",
        "sub_categories": [
            "concealed_forest_brushwood_lean_to",
            "foliage_covered_pitfall_spike_trap",
            "roadside_timber_gibbet_iron_cage",
            "hollow_tree_smuggler_cache",
            "dungeon_wall_chains_and_oubliette"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "banditry": "highway_ambush",
            "imprisonment": "dungeon_breakout",
            "bounty_system": "outlaw_head_reward"
        }
    },

    # =========================================================================
    # SPHERE VII: ECOLOGY, FAUNA, LIVING TRACES & NATURE (7 Cats, 880 Assets)
    # =========================================================================
    {
        "id": "primeval_forests_ancient_oaks_and_woods",
        "name": "Primeval Forests, Ancient Oaks & Woods",
        "vietnamese_name": "Rừng Nguyên Sinh, Sồi Cổ Thụ & Dẻ Gai",
        "sphere": "Ecology & Living Traces",
        "description": "Gnarled Sherwood oaks, towering beeches, Scots pines, bracken ferns, wild blackberry brambles, hollow nurse logs, fairy rings.",
        "sub_categories": [
            "gnarled_royal_oak_veteran_tree",
            "towering_european_beech_tree",
            "highland_scots_pine_cluster",
            "dense_bracken_fern_and_brambles",
            "decaying_hollow_nurse_log_fungi"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "royal_forest_law": "verderer_and_venison_ban",
            "foraging_yield": ["truffles", "boletus", "wild_honey", "bilberries"],
            "canopy_occlusion": "dense_foliage_fade"
        }
    },
    {
        "id": "cliffs_highland_moors_and_waterfalls",
        "name": "Cliffs, Highland Moors & Waterfalls",
        "vietnamese_name": "Vách Đá Vôi, Cao Nguyên Than Bùn & Thác Nước",
        "sphere": "Ecology & Living Traces",
        "description": "Stratified limestone cliffs, granite tors, dark cavern mouths, purple heather moors, rushing waterfall drops, scree slopes.",
        "sub_categories": [
            "stratified_limestone_cliff_wall",
            "weathered_mountain_granite_tor",
            "dark_cavern_mouth_and_grotto",
            "blooming_purple_heather_moor",
            "cascading_mountain_waterfall_pool"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "verticality": "climbing_and_ledges",
            "cavern_exploration": "dungeon_entry_portal",
            "water_physics": "flowing_torrents"
        }
    },
    {
        "id": "wetlands_bogs_fens_and_marshlands",
        "name": "Wetlands, Bogs, Fens & Marshlands",
        "vietnamese_name": "Đầm Lầy Than Bùn, Bãi Sậy & Nước Chua",
        "sphere": "Ecology & Living Traces",
        "description": "Spongy sphagnum peat bogs, dark fen sludge, willow carrs, cattail marshes, water iris clumps, peat cutting trenches.",
        "sub_categories": [
            "spongy_sphagnum_peat_bog_mat",
            "dark_stagnant_fen_sludge_pool",
            "gnarled_weeping_willow_carr",
            "marsh_cattail_and_bulrush_bed",
            "hand_cut_peat_extraction_trench"
        ],
        "planned_count": 110,
        "gameplay_gap_hooks": {
            "movement_impediment": "mire_and_quagmire_slow",
            "peat_fuel": "extract_turf_blocks",
            "bog_preservation": "bog_body_archeology"
        }
    },
    {
        "id": "living_ground_pavements_and_tracks",
        "name": "Living Ground, Pavements & Tracks",
        "vietnamese_name": "Mặt Đất Đời Sống, Lối Đi & Vết Bánh Xe",
        "sphere": "Ecology & Living Traces",
        "description": "Roman paved highways, sunken holloways, cobblestone pavements, deep muddy cart ruts, puddle reflections, autumn leaf carpets, rime frost.",
        "sub_categories": [
            "square_sett_city_cobblestone",
            "deep_carriage_mud_ruts_track",
            "rainwater_puddle_street_gutter",
            "sunken_holloway_dirt_lane",
            "autumn_beech_leaf_carpet",
            "morning_rime_frost_ground"
        ],
        "planned_count": 130,
        "gameplay_gap_hooks": {
            "terrain_nav": "walk_surface",
            "footstep_acoustics": ["stone_clatter", "squelch_mud", "crunch_leaves", "splash_puddle"],
            "wheel_traction": "weather_dependent_speed"
        }
    },
    {
        "id": "domesticity_chores_and_habitation_traces",
        "name": "Domesticity, Chores & Habitation Traces",
        "vietnamese_name": "Đời Sống Gia Đình, Việc Nhà & Dấu Vết Sinh Hoạt",
        "sphere": "Ecology & Living Traces",
        "description": "Hanging laundry lines, steaming cow dung heaps, butter churns, wash tubs, chimney smoke drifts, chamberpot slops.",
        "sub_categories": [
            "hanging_linen_laundry_drying_line",
            "steaming_barnyard_dung_heap",
            "wooden_wash_tub_with_scrub_board",
            "chimney_smoke_wisp_and_flue",
            "chamberpot_slop_street_puddle",
            "outdoor_dishwashing_tallow_bench"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "ambient_habitation": "visual_life_indicator",
            "sanitation_level": "smell_and_squalor_meter",
            "domestic_chores": "daily_npc_animations"
        }
    },
    {
        "id": "wildlife_micro_fauna_birds_and_pests",
        "name": "Wildlife, Micro-Fauna, Birds & Pests",
        "vietnamese_name": "Động Vật Hoang Dã, Chim Muông & Thú Nhỏ",
        "sphere": "Ecology & Living Traces",
        "description": "Stork nests atop thatched chimneys, swallow barn nests, barn cats stalking mice, stray tavern curs, roosting pigeons, gallows crows.",
        "sub_categories": [
            "stork_basket_nest_on_chimney",
            "barn_swallow_mud_eave_nest",
            "mousing_barn_cat_and_cellar_rats",
            "stray_village_cur_hunting_dog",
            "roosting_town_pigeons_cluster",
            "carrion_crow_flock_on_scaffold"
        ],
        "planned_count": 120,
        "gameplay_gap_hooks": {
            "ecological_ambience": "organic_movement_sprites",
            "omen_system": "stork_good_luck_vs_crows_ill_omen",
            "pest_control": "cats_reduce_grain_loss"
        }
    },
    {
        "id": "denizens_burghers_peasants_and_beasts",
        "name": "Denizens, Burghers, Peasants & Beasts",
        "vietnamese_name": "Cư Dân, Thị Dân, Nông Dân & Súc Vật Kéo",
        "sphere": "Ecology & Living Traces",
        "description": "Serfs, milkmaids, blacksmiths, monks, friars, town watchmen, armored knights, highwaymen, heavy shire draft horses, oxen, sheep flocks.",
        "sub_categories": [
            "serf_peasant_and_milkmaid_laborer",
            "guild_burgher_and_cloth_merchant",
            "monastery_friar_and_parish_priest",
            "town_watchman_and_plate_knight",
            "outlaw_highwayman_and_poacher",
            "shire_draft_horse_and_plow_oxen"
        ],
        "planned_count": 140,
        "gameplay_gap_hooks": {
            "npc_routine": ["day_labor", "market_trading", "night_curfew", "tavern_leisure"],
            "dialogue_hooks": "feudal_social_standing",
            "draft_power": "pull_carts_and_heavy_plows"
        }
    }
]

total_count = sum(c["planned_count"] for c in CATEGORIES)
print("=" * 80)
print(f"GENERATING 48 MEDIEVAL WESTERN CATEGORIES (TOTAL BUDGET: {total_count} ASSETS)")
print("=" * 80)

# Verify uniqueness of category IDs
cat_ids = [c["id"] for c in CATEGORIES]
assert len(cat_ids) == 48, f"Expected 48 categories, found {len(cat_ids)}"
assert len(set(cat_ids)) == 48, "Duplicate category IDs found!"

# Verify uniqueness of subcategories across categories
all_subcats = []
for c in CATEGORIES:
    all_subcats.extend(c["sub_categories"])
print(f"Total sub-categories defined: {len(all_subcats)}")
print(f"Unique sub-categories:        {len(set(all_subcats))}")

# Write categories.json
PACK_DIR.mkdir(parents=True, exist_ok=True)
with open(CATEGORIES_PATH, "w", encoding="utf-8") as f:
    json.dump(CATEGORIES, f, indent=2, ensure_ascii=False)

print(f"Successfully saved 48 categories to: {CATEGORIES_PATH}")

# Ensure subdirectories exist for all 48 categories
for c in CATEGORIES:
    cid = c["id"]
    (PACK_DIR / "runtime" / cid).mkdir(parents=True, exist_ok=True)
    (PACK_DIR / "data" / cid).mkdir(parents=True, exist_ok=True)
    (PACK_DIR / "original" / cid).mkdir(parents=True, exist_ok=True)

print("Created runtime, data, and original folders for all 48 categories!")
