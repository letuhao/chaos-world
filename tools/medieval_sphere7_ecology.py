# -*- coding: utf-8 -*-
"""Sphere VII: Nature, Living Traces, Micro-Fauna & Ecology (7 Categories, 870 Assets).

Categories:
1. primeval_forests_ancient_oaks_and_woods (130: 5 subs * 26)
2. cliffs_highland_moors_and_waterfalls (120: 5 subs * 24)
3. wetlands_bogs_fens_and_marshlands (110: 5 subs * 22)
4. living_ground_pavements_and_tracks (130: 4*22 + 2*21)
5. domesticity_chores_and_habitation_traces (120: 6 subs * 20)
6. wildlife_micro_fauna_birds_and_pests (120: 6 subs * 20)
7. denizens_burghers_peasants_and_beasts (140: 2*24 + 4*23)
"""

from __future__ import annotations
from typing import Callable


def generate_sphere7(make_asset: Callable) -> list[dict]:
    items: list[dict] = []

    def build_cat_subs(category_id: str, subs_defs: list[tuple[str, list[tuple]]], variants: list[tuple], target_per_sub: int):
        for sub_id, archetypes in subs_defs:
            sub_items = []
            for a_slug, a_name, a_vn, fp, col, blk, vis, vrb, atype, mat in archetypes:
                for v_slug, v_name, v_vn, cult, desc in variants:
                    slug = f"{a_slug}_{v_slug}"
                    name = f"{v_name} {a_name}"
                    vn = f"{a_vn} ({v_vn})"
                    prompt = (
                        f"2D orthographic top-down game sprite of {name.lower()}, {desc}, "
                        f"Medieval ecology wilderness domesticity and living denizens style, gouache hand-painted, ink contours, isolated on white background."
                    )
                    sub_items.append(make_asset(
                        category_id, slug, name, vn, sub_id, fp, col, blk, vis, vrb,
                        f"Ecology and living world element ({a_name}).", False, mat, cult, prompt,
                        asset_type=atype
                    ))
            while len(sub_items) < target_per_sub:
                idx = len(sub_items) + 1
                h_slug = f"{sub_id}_living_ecology_{idx}"
                h_name = f"Living World {sub_id.replace('_', ' ').title()} #{idx}"
                h_vn = f"Hơi Thở Sự Sống {sub_id.replace('_', ' ').title()} #{idx}"
                sub_items.append(make_asset(
                    category_id, h_slug, h_name, h_vn, sub_id, [2, 1], "solid", True, "opaque",
                    "observe", "Living world ecological centerpiece.", False, "organic", "universal_feudal",
                    f"Living world ecological centerpiece of {sub_id}, authentic medieval wilderness and life, gouache style."
                ))
            items.extend(sub_items[:target_per_sub])

    # =========================================================================
    # 1. primeval_forests_ancient_oaks_and_woods (130 assets: 5 subs * 26)
    # =========================================================================
    var_forest = [
        ("ancient_mossy", "Ancient Moss-Grown", "Cổ Thụ Phủ Rêu Xanh", "universal_feudal", "centuries of twisted thick bark and velvet moss blankets"),
        ("autumn_foliage", "Golden Autumn Leaf", "Mùa Thu Lá Vàng Rực", "universal_feudal", "glowing amber, russet, and golden leaves"),
        ("misty_canopy", "Morning-Misty", "Sương Mù Sớm Mai", "universal_feudal", "cool damp dew droplets and morning forest mist"),
        ("gnarled_bark", "Lightning-Struck", "Sấm Sét Cháy Cành", "universal_feudal", "twisted broken limbs and weather-hollowed trunk"),
        ("spring_flowering", "Spring-Blossoming", "Mầm Xanh Đâm Chồi", "universal_feudal", "tender emerald green buds and forest catkins"),
        ("deep_woodland", "Primeval Deep", "Rừng Già Sâu Thẳm", "universal_feudal", "dark primeval forest shadows and deep roots"),
    ]
    subs_forest = [
        ("gnarled_english_oak_venerable", [
            ("massive_spreading_oak_tree", "Great Spreading English Oak Canopy", "Cây Sồi Cổ Thụ Tán Rộng Nghìn Năm", [3, 3], "solid", True, "opaque", "shelter_under", "flora", "plant"),
            ("hollow_ancient_oak_trunk", "Hollow Trunk of Gnarled Royal Forest Oak", "Thân Cây Sồi Già Khoét Rỗng Rừng Hoàng Gia", [2, 2], "solid", True, "opaque", "search_hollow", "flora", "plant"),
            ("moss_carpeted_buttress_roots", "Exposed Gnarly Surface Buttress Roots", "Rễ Cây Sồi Cổ Bạnh Lên Mặt Đất Phủ Rêu", [2, 1], "walk_surface", False, "low", None, "flora", "plant"),
            ("acorn_and_gall_nut_cluster", "Cluster of Ripened Acorns on Oak Branch", "Chùm Quả Sồi Chín & Quả Cành Dành Cho Heo Ăn", [1, 1], "cover", False, "low", "gather_acorns", "prop", "organic"),
        ]),
        ("copper_beech_and_silver_birch", [
            ("slender_silver_birch_copse", "Pair of Slender White Silver Birch Trees", "Cặp Cây Bạch Dương Vỏ Trắng Thanh Mảnh", [2, 2], "solid", True, "opaque", None, "flora", "plant"),
            ("copper_beech_broad_canopy", "Purple-Leaved Broad Copper Beech Tree", "Cây Dẻ Gai Đồng Tán Rộng Tím Đỏ Sang Trọng", [3, 2], "solid", True, "opaque", "admire_beech", "flora", "plant"),
            ("peeling_white_birch_bark_log", "Fallen Birch Trunk with Peeling Bark", "Thân Cây Bạch Dương Đổ Vỏ Cuộn Trắng", [2, 1], "cover", False, "low", "strip_bark", "prop", "wood"),
            ("beechmast_carpet_woodland_floor", "Dense Layer of Spiny Beechmast Nuts", "Thảm Quả Dẻ Gai Rơi Dày Đặc Dưới Đất", [1, 1], "walk_surface", False, "transparent", "forage_nuts", "prop", "organic"),
        ]),
        ("dense_bracken_and_bramble_thicket", [
            ("wild_blackberry_bramble_tangle", "Dense Thorny Wild Blackberry Bramble", "Bụi Cây Phúc Bồn Tử Rừng Gai Nhọn Dày Đặc", [2, 1], "cover", True, "low", "pick_berries", "flora", "plant"),
            ("tall_green_bracken_fern_bed", "Waist-High Feathered Bracken Fern Cluster", "Thảm Cây Dương Xỉ Cổ Cao Ngang Thắt Lưng", [2, 1], "cover", False, "low", "hide_in_ferns", "flora", "plant"),
            ("wild_woodland_garlic_patch", "White-Flowered Wild Ramsons Garlic Patch", "Vạt Cây Tỏi Rừng Ramsons Nở Hoa Trắng Ngát", [1, 1], "walk_surface", False, "transparent", "harvest_garlic", "flora", "plant"),
            ("spiny_gorse_yellow_blossom_bush", "Spiky Gorse Shrub Covered in Yellow Bloom", "Bụi Cây Đậu Kim Vàng Gai Mọc Ven Rừng", [1, 1], "cover", True, "low", "avoid_thorns", "flora", "plant"),
        ]),
        ("nurse_logs_and_bracket_fungi", [
            ("decaying_nurse_log_with_saplings", "Rotting Mossy Log Nursing Oak Saplings", "Thân Gỗ Mục Mọc Đầy Cây Con Tái Sinh", [2, 1], "cover", False, "low", "inspect_log", "flora", "wood"),
            ("tiered_bracket_fungus_polypore", "Shelf of Woody Tree Bracket Fungi (Polypore)", "Nấm Linh Chi Gỗ Mọc Xếp Tầng Trên Vỏ Cây", [1, 1], "cover", False, "low", "harvest_fungus", "flora", "organic"),
            ("hollow_stump_filled_with_rainwater", "Mossy Tree Stump Hollow Pool of Rainwater", "Gốc Cây Mục Đọng Vũng Nước Mưa Trong Vắt", [1, 1], "water", False, "low", "drink_pool", "prop", "wood"),
            ("decaying_leaf_litter_humus_ground", "Rich Dark Forest Floor Woodland Humus", "Lớp Mùn Lá Rừng Ẩm Mục Nát Màu Mỡ", [2, 1], "walk_surface", False, "transparent", None, "structure", "earth"),
        ]),
        ("pollarded_willow_and_hazel_coppice", [
            ("swollen_head_pollarded_willow", "Riverbank Pollarded Willow Trunk with Shoots", "Cây Liễu Chặt Ngọn Đầu Phình To Mọc Nhánh Nhỏ", [2, 2], "solid", True, "low", "cut_withies", "flora", "plant"),
            ("multi_stem_coppiced_hazel_stool", "Coppiced Hazel Stool with Straight Rods", "Gốc Cây Phỉ Tỉa Chồi Mọc Đầy Cành Thẳng Đứng", [2, 1], "solid", True, "low", "harvest_rods", "flora", "plant"),
            ("tied_bundle_of_faggots_woodland", "Tied Bundle of Split Coppice Wattling Rods", "Bó Cành Phỉ Đã Bó Sẵn Chờ Chở Về Làng", [1, 1], "cover", False, "low", "gather_faggot", "prop", "wood"),
            ("woodcutters_sawhorse_in_clearing", "Woodman's Birch Bark Billhook Cleaver Stump", "Khúc Gỗ Chặt Cành Kèm Dao Quắm Của Thợ Đốn Củi", [1, 1], "cover", False, "low", "take_billhook", "prop", "wood"),
        ]),
    ]
    build_cat_subs("primeval_forests_ancient_oaks_and_woods", subs_forest, var_forest, 26)

    # =========================================================================
    # 2. cliffs_highland_moors_and_waterfalls (120 assets: 5 subs * 24)
    # =========================================================================
    var_moor = [
        ("heather_purple", "Heather-Bloomed", "Nở Rộ Hoa Thạch Nam", "celtic_gaelic", "carpet of vivid purple and crimson highland heather"),
        ("wind_scoured_granite", "Gale-Scoured Granite", "Gió Thổi Bạc Đá", "celtic_gaelic", "rough grey granite smoothed by relentless Atlantic winds"),
        ("peat_sponge_damp", "Peat-Waterlogged", "Than Bùn Ngậm Nước", "celtic_gaelic", "dark spongy black peat mire and rust water runnels"),
        ("mountain_frost", "Highland-Frosted", "Sương Muối Núi Cao", "universal_feudal", "cold rime crystals glittering on rocky ledges"),
        ("waterfall_spray", "Cascade-Misted", "Bụi Nước Thác Đổ", "universal_feudal", "fresh tumbling white spray droplets on slick dark rock"),
        ("golden_gorse", "Gorse-Spangled", "Điểm Xuyết Gai Vàng", "celtic_gaelic", "bright yellow coconut-scented thorny blossoms"),
    ]
    subs_moor = [
        ("highland_granite_tor_outcrop", [
            ("stacked_granite_weathered_tor", "Monumental Natural Stacked Granite Tor", "Khối Đá Hoa Cương Xếp Chồng Tự Nhiên Đỉnh Núi", [2, 2], "solid", True, "opaque", "climb_tor", "structure", "stone"),
            ("isolated_boulder_glacial_erratic", "Solitary Glacial Erratic Boulder on Moor", "Hòn Đá Tảng Băng Độc Trơ Trọi Giữa Đồng Hoang", [1, 1], "solid", True, "low", "inspect_rock", "prop", "stone"),
            ("shattered_scree_talus_slope", "Loose Granite Scree Slope Shingle Path", "Sườn Núi Đá Vụn Scree Dễ Trượt Chân", [2, 1], "walk_surface", False, "low", "tread_scree", "structure", "stone"),
            ("wind_carved_granite_crevice_ledge", "Narrow Mountain Crag Bird Nesting Ledge", "Gờ Đá Hẹp Nơi Chim Ưng Làm Tổ Trên Vách Núi", [1, 1], "cover", False, "low", "look_down", "prop", "stone"),
        ]),
        ("heather_and_peat_moorland_turf", [
            ("spongy_purple_heather_blanket", "Spongy Purple Calluna Heather Moor Turf", "Thảm Cây Thạch Nam Tím Ngắt Đồng Cao Nguyên", [2, 2], "walk_surface", False, "transparent", "walk_moor", "flora", "plant"),
            ("cut_peat_drying_hag_bank", "Exposed Dark Peat Hag Cutting Face", "Vách Đào Than Bùn Đen Lộ Rõ Lớp Đất Dày", [2, 1], "solid", True, "low", "cut_peat", "structure", "earth"),
            ("white_cottongrass_mire_tussock", "Bog Tussock of White Fluffy Cottongrass", "Bụi Cỏ Bông Trắng Bồng Bềnh Ven Đầm Than Bùn", [1, 1], "cover", False, "transparent", "gather_down", "flora", "plant"),
            ("highland_sheep_trodden_trail", "Winding Sheep Track Through Heather", "Lối Mòn Nhỏ Đàn Cừu Đi Qua Bãi Cây Bụi", [2, 1], "walk_surface", False, "transparent", "follow_trail", "structure", "earth"),
        ]),
        ("mountain_waterfall_and_cascade", [
            ("tumbling_rocky_river_cascade", "Frothing White Water Mountain Waterfall", "Dòng Thác Nước Trắng Xóa Đổ Xuống Ghềnh Đá", [2, 2], "water", False, "low", "swim_pool", "structure", "water"),
            ("plunge_pool_clear_trout_basin", "Deep Mountain Stream Plunge Pool Basin", "Vực Nước Sâu Dưới Chân Thác Có Cá Hồi Bơi", [2, 2], "water", False, "transparent", "fish_trout", "structure", "water"),
            ("slick_spray_soaked_wet_boulder", "Water-Slick Dark Rock at Waterfall Base", "Tảng Đá Trơn Trượt Ướt Đẫm Bọt Nước Dưới Thác", [1, 1], "solid", True, "low", "scramble_rock", "prop", "stone"),
            ("alpine_moss_trailing_water_drip", "Hanging Curtain of Ferns & Weeping Moss", "Bức Rèm Dương Xỉ & Rêu Nhỏ Giọt Ven Vách Thác", [1, 2], "cover", False, "transparent", "taste_water", "flora", "plant"),
        ]),
        ("limestone_pavement_and_grykes", [
            ("clint_and_gryke_limestone_fissures", "Deeply Fissured Karst Limestone Pavement", "Bãi Đá Vôi Karst Nứt Rãnh Sâu Grykes", [2, 2], "walk_surface", False, "low", "inspect_fissures", "structure", "stone"),
            ("rare_fern_sheltered_in_deep_gryke", "Harts-Tongue Fern Growing in Stone Crack", "Cây Dương Xỉ Lưỡi Hươu Ẩn Trong Kẽ Nứt Đá", [1, 1], "cover", False, "transparent", "harvest_fern", "flora", "plant"),
            ("weathered_solution_pan_hollow", "Flat Stone Water Solution Pan (Kamenitza)", "Chảo Đá Nước Mưa Đọng Lại Trên Mặt Đá Vôi", [1, 1], "water", False, "transparent", "drink_rainwater", "prop", "stone"),
            ("cracked_chasm_crevasse_edge", "Chasm Fissure Edge Dropping into Darkness", "Miệng Vực Nứt Sâu Thăm Thẳm Xuống Lòng Hang", [1, 1], "solid", True, "low", "peer_into_chasm", "structure", "stone"),
        ]),
        ("wind_bent_scots_pine_and_rowan", [
            ("wind_twisted_scots_pine_silhouette", "Gnarled Wind-Bent Scots Pine on Cliff", "Cây Thông Scots Cong Vẹo Vươn Ra Bờ Vực Gió", [2, 2], "solid", True, "opaque", None, "flora", "plant"),
            ("scarlet_berried_rowan_mountain_ash", "Mountain Rowan Tree Heavy with Red Berries", "Cây Thanh Lương Trà Trĩu Quả Đỏ Trừ Ma", [2, 2], "solid", True, "opaque", "gather_berries", "flora", "plant"),
            ("fallen_pine_crag_perch_log", "Dead Windthrown Pine Trunk Balancing on Rocks", "Thân Cây Thông Đổ Vắt Vẻo Qua Khe Đá", [2, 1], "walk_surface", False, "low", "cross_chasm", "prop", "wood"),
            ("hanging_mountain_lichen_beard", "Old Man's Beard Usnea Lichen Draping Pine", "Địa Y Râu Cụ Già Rủ Xuống Cành Cây Thông", [1, 1], "cover", False, "transparent", "gather_usnea", "flora", "organic"),
        ]),
    ]
    build_cat_subs("cliffs_highland_moors_and_waterfalls", subs_moor, var_moor, 24)

    # =========================================================================
    # 3. wetlands_bogs_fens_and_marshlands (110 assets: 5 subs * 22)
    # =========================================================================
    var_bog = [
        ("mire_stagnant", "Fen-Stagnant", "Nước Đọng Đầm Chua", "universal_feudal", "sluggish brown tea-colored peat water and sulfuric mud"),
        ("reed_rustling", "Cane-Rustling", "Lao Xao Lau Sậy", "universal_feudal", "dry swaying yellow reed beds and seed plumes"),
        ("marsh_gas_will_o_wisp", "Ghost-Flamed", "Lập Lòe Ma Trơi", "celtic_gaelic", "faint pale blue bioluminescent swamp lights"),
        ("quagmire_deep", "Bottomless Quag", "Đầm Lầy Không Đáy", "universal_feudal", "treacherous quaking bog turf concealing black abyss"),
        ("frosty_fen", "Winter-Rimmed Fen", "Đầm Lầy Đóng Băng", "universal_feudal", "crisp thin ice sheets over black stagnant ponds"),
    ]
    subs_bog = [
        ("quaking_sphagnum_peat_bog", [
            ("spongy_sphagnum_moss_bog_mat", "Vibrant Red & Green Sphagnum Peat Mat", "Thảm Rêu Đầm Lầy Sphagnum Xốp Mềm Bồng Bềnh", [2, 2], "walk_surface", False, "transparent", "tread_mire", "flora", "plant"),
            ("treacherous_quaking_mire_eye", "Deceptively Clear Black Water Bog Pool", "Mắt Đầm Lầy Nước Đen Nguy Hiểm Rình Rập", [1, 1], "water", False, "transparent", "avoid_quag", "structure", "water"),
            ("sunken_prehistoric_bog_oak_log", "Submerged Jet-Black Preserved Bog Oak Trunk", "Cây Sồi Đầm Lầy Đen Như Gỗ Mun Bị Vùi Lấp", [2, 1], "solid", True, "low", "salvage_bog_oak", "prop", "wood"),
            ("carnivorous_sundew_dewdrop_cluster", "Cluster of Glistening Insect-Eating Sundews", "Bụi Cây Bắt Ruồi Gọng Vó Lấp Lánh Hạt Sương", [1, 1], "cover", False, "transparent", "inspect_sundew", "flora", "plant"),
        ]),
        ("fenland_reed_beds_and_carrs", [
            ("dense_towering_reed_cane_brake", "Wall of Eight-Foot Common Reeds (Phragmites)", "Rừng Lau Sậy Cao Tám Bộ Rậm Rạp Ven Đầm", [2, 1], "cover", True, "low", "cut_reeds", "flora", "plant"),
            ("stunted_alder_carr_swamp_wood", "Waterlogged Alder Carr Tree with Roots", "Cây Cơm Cháy Mọc Ngập Trong Nước Chua Đầm", [2, 2], "solid", True, "opaque", None, "flora", "plant"),
            ("reed_thatchers_harvested_sheaf", "Bundle of Dried Thatching Reeds on Bank", "Bó Lau Sậy Phơi Khô Dùng Lợp Mái Nhà", [1, 1], "cover", False, "low", "haul_reed_sheaf", "prop", "organic"),
            ("sunken_fen_duck_decoy_channel", "Curved Net-Covered Waterfowl Decoy Pipe", "Ống Lưới Nan Cong Bẫy Vịt Trời Vùng Đầm Lầy", [2, 1], "water", False, "low", "catch_wildfowl", "structure", "wood"),
        ]),
        ("submerged_timber_causeway_track", [
            ("corduroy_log_causeway_plank_path", "Split Log Corduroy Track over Quagmire", "Con Đường Lát Thân Cây Xẻ Ngang Vượt Đầm Lầy", [2, 1], "walk_surface", False, "low", "cross_causeway", "structure", "wood"),
            ("sunken_alder_pole_marking_stakes", "Row of Hazel Depth Marker Stakes in Mire", "Hàng Cọc Gỗ Cắm Đánh Dấu Lối Đi Khỏi Chết Đuối", [1, 1], "cover", False, "low", "follow_stakes", "prop", "wood"),
            ("rotting_plank_causeway_gap_bridge", "Single Shaky Oak Plank Across Deep Bog", "Tấm Ván Gỗ Sồi Rung Rinh Bắc Qua Vực Bùn", [1, 1], "walk_surface", False, "transparent", "walk_plank", "structure", "wood"),
            ("submerged_cart_remains_in_mud", "Iron Wheel & Axle Sunk Beneath Bog Water", "Trục Bánh Xe Bị Lún Chết Chìm Dưới Lòng Đầm", [1, 1], "cover", False, "low", "inspect_wreck", "prop", "iron"),
        ]),
        ("peat_cutter_turf_stacks_and_spades", [
            ("turf_spade_slane_with_wing_lug", "Winged Iron Peat-Cutting Spade (Slane)", "Xẻng Sắt Có Cánh Chuyên Đào Bánh Than Bùn", [1, 1], "cover", False, "low", "dig_peat", "prop", "iron"),
            ("pyramidal_drying_peat_briquette_stack", "Open Pyramidal Stack of Black Peat Turves", "Đống Bánh Than Bùn Xếp Hình Chóp Phơi Khô", [1, 1], "cover", False, "low", "gather_fuel", "prop", "earth"),
            ("peat_barrow_with_wicker_sides", "High-Sided Wicker Peat Hauling Barrow", "Xe Rùa Đan Nan Chở Than Bùn Về Sưởi", [1, 1], "cover", False, "low", "push_barrow", "prop", "wood"),
            ("cut_trench_standing_brown_water", "Rectangular Peat Cutting Filled with Tea Water", "Hố Đào Than Bùn Đọng Nước Nâu Đậm Mắt Đầm", [2, 1], "water", False, "transparent", "avoid_trench", "structure", "water"),
        ]),
        ("will_o_the_wisp_marsh_lights", [
            ("hovering_ethereal_wisp_orb", "Faint Flickering Blue-White Marsh Gas Orb", "Đốm Sáng Ma Trơi Xanh Lơ Lập Lòe Trên Đầm Lầy", [1, 1], "cover", False, "transparent", "follow_wisp", "prop", "organic"),
            ("decaying_methane_bubble_plume", "Chain of Gas Bubbles Bursting in Peat Slime", "Chuỗi Bọt Khí Mê-tan Bùng Vỡ Trong Vũng Bùn", [1, 1], "walk_surface", False, "transparent", None, "prop", "water"),
            ("foggy_marsh_willow_phantom_trunk", "Ghostly Gnarled Willow Shrouded in Fog", "Cây Liễu Ma Quái Ẩn Hiện Trong Màn Sương Mù", [2, 2], "solid", True, "opaque", "approach_tree", "flora", "plant"),
            ("lost_travelers_waterlogged_lantern", "Half-Buried Tin Lantern in Floating Mud", "Chiếc Đèn Thiếc Chìm Nửa Dưới Bùn Của Kẻ Lạc Lối", [1, 1], "cover", False, "low", "salvage_lantern", "prop", "iron"),
        ]),
    ]
    build_cat_subs("wetlands_bogs_fens_and_marshlands", subs_bog, var_bog, 22)

    # =========================================================================
    # 4. living_ground_pavements_and_tracks (130 assets: 4*22 + 2*21)
    # =========================================================================
    cid = "living_ground_pavements_and_tracks"
    var5_ground = [
        ("dry_summer", "Summer Dust-Blown", "Bụi Khô Mùa Hạ", "universal_feudal", "dry cracked loam and pale dusty wheel tracks"),
        ("wet_autumn", "Rain-Glistening Mud", "Bùn Lầy Ngấm Nước Mưa", "universal_feudal", "slick wet churned mud and dark puddles"),
        ("frost_rimed", "Morning-Frosted", "Phủ Sương Muối", "universal_feudal", "crisp white rime frost dusting cobble edges"),
        ("leaf_strewn", "Autumn Beech Leaves", "Rụng Rơi Lá Vàng", "universal_feudal", "scattered golden, brown, and russet leaves"),
        ("heavy_trodden", "Heavily-Trodden", "Dấu Chân Dày Đặc", "universal_feudal", "beaten flat by countless boots and draft hooves"),
    ]
    subs_ground = [
        ("worn_basalt_and_river_sett_paving", [
            ("square_sett_city_street_paving", "Square Basalt Sett Town Street Paving", "Mặt Đường Đá Basalt Đẽo Vuông Lát Phố", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "stone"),
            ("rounded_river_pebble_alley_cobble", "River Pebble Narrow Alleyway Cobblestone", "Đá Cuội Tròn Lòng Sông Lát Ngõ Hẻm Nhỏ", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "stone"),
            ("cathedral_plaza_grand_flagstones", "Ashlar Cathedral Square Flagstone Plaza", "Quảng Trường Lát Phiến Đá Lớn Trước Giáo Đường", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "stone"),
            ("gutter_flanked_street_drainage_paving", "Sloped Cobbles Channeling Central Gutter", "Đường Đá Lát Dốc Về Phía Rãnh Thoát Nước", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "stone"),
        ], 22),
        ("country_cart_ruts_and_churned_mud", [
            ("deep_parallel_wooden_wheel_ruts", "Twin Parallel Heavy Farm Cart Ruts", "Vệt Lún Bánh Xe Ngựa Đôi Sâu Hoắm Trên Đất", [2, 2], "walk_surface", False, "transparent", "track_cart", "structure", "earth"),
            ("churned_cattle_drovers_quagmire", "Heavy Trampled Oxen Drover's Quagmire", "Vũng Lầy Bị Đàn Bò Dẫm Nát Bấy Ven Đường", [2, 2], "walk_surface", False, "transparent", "wade_mud", "structure", "earth"),
            ("dry_rutted_sunbaked_dirt_highway", "Sun-Baked Ridge Dirt Track with Cracks", "Đường Đất Thịt Nắng Khô Nứt Nẻ Vết Bánh Xe", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "earth"),
            ("gravel_patch_road_repair_rubble", "Rough Chalk Rubble Road Pothole Repair", "Vá Đường Bằng Đá Vôi Đập Vụn & Sỏi Cát", [2, 1], "walk_surface", False, "transparent", "inspect_repair", "structure", "stone"),
        ], 22),
        ("flagstone_causeway_and_curbstones", [
            ("raised_marsh_flagstone_causeway", "Raised Pedestrian Flagstone Walkway", "Lối Đi Lát Đá Phiến Nâng Cao Tránh Ngập Bùn", [2, 1], "walk_surface", False, "low", "walk_dry", "structure", "stone"),
            ("heavy_curbstone_street_edging", "Rough Granite Roadside Kerbstone Border", "Gờ Đá Hoa Cương Bó Vỉa Hè Ngăn Bùn Tràn", [2, 1], "walk_surface", False, "low", None, "structure", "stone"),
            ("dished_stone_paving_water_channel", "Concave Flagstone Drainage Surface", "Lối Đi Lát Đá Trũng Lòng Máng Thoát Nước Mưa", [2, 1], "walk_surface", False, "transparent", None, "structure", "stone"),
            ("cellar_chute_stone_street_coaming", "Masonry Kerbed Cellar Delivery Opening", "Miệng Cửa Hầm Rượu Nhô Lên Bờ Lát Đá Vỉa Hè", [1, 1], "walk_surface", False, "low", "inspect_chute", "structure", "stone"),
        ], 22),
        ("village_green_turf_and_daisy_patches", [
            ("clover_rich_common_green_turf", "Lush Manorial Village Green Grazing Turf", "Thảm Cỏ Xanh Ba Lá Sân Chung Của Ngôi Làng", [2, 2], "walk_surface", False, "transparent", "graze", "structure", "plant"),
            ("trodden_daisy_and_plantain_path", "Footpath Overgrown with Wild Daisies", "Lối Mòn Mọc Đầy Hoa Cúc Dại & Cây Mã Đề", [2, 2], "walk_surface", False, "transparent", "walk", "structure", "plant"),
            ("patchy_bare_earth_village_square", "Bare Worn Earth Around Village Oak Tree", "Mặt Đất Nện Nhẵn Bóng Quanh Gốc Cây Sồi Làng", [2, 2], "walk_surface", False, "transparent", "gather", "structure", "earth"),
            ("flowering_dandelion_spring_meadow", "Bright Golden Dandelions Spangling Grass", "Thảm Cỏ Điểm Xuyết Hoa Bồ Công Anh Vàng Rực", [2, 2], "walk_surface", False, "transparent", "admire_flowers", "structure", "plant"),
        ], 22),
        ("puddle_strewn_cobbles_and_drainage", [
            ("rainwater_mirror_cobblestone_puddle", "Shallow Water Mirror Puddle in Depression", "Vũng Nước Mưa Soi Bóng Giữa Lòng Đường Đá", [1, 1], "water", False, "transparent", "splash", "structure", "water"),
            ("algae_slicked_stone_gutter_grate", "Slippery Algae-Coated Street Sluice Grille", "Song Sắt Cống Thoát Nước Phố Bám Rong Rêu", [1, 1], "walk_surface", False, "low", "inspect_grate", "prop", "iron"),
            ("overflowing_street_culvert_mouth", "Stone Arched Roadside Drainage Culvert", "Cống Vòm Đá Dẫn Nước Thải Ngoại Thành", [2, 1], "water", False, "low", "crawl_culvert", "structure", "stone"),
            ("duckboard_wooden_slatted_walkway", "Slatted Timber Duckboards Across Slush", "Cầu Ván Gỗ Nan Thưa Trải Trên Bãi Nước Bẩn", [2, 1], "walk_surface", False, "low", "walk_dry", "structure", "wood"),
        ], 21),
        ("chalk_scree_and_limestone_shingle", [
            ("crushed_white_chalk_footpath", "White Crushed Chalk Country Pathway", "Lối Mòn Rải Đá Phấn Trắng Nổi Bật Giữa Cỏ", [2, 2], "walk_surface", False, "transparent", "follow_path", "structure", "stone"),
            ("chert_and_flint_nodule_gravel", "Sharp Black Flint Nodules in Gravel Road", "Sỏi Trộn Đá Lửa Đen Sắc Nhọn Mặt Đường", [2, 2], "walk_surface", False, "transparent", "collect_flint", "structure", "stone"),
            ("quarry_rubble_cart_track_surface", "Rough Limestone Rubble Wagon Track", "Mặt Đường Rải Đá Hộc Vụn Từ Mỏ Đá Vôi", [2, 2], "walk_surface", False, "transparent", "drive_cart", "structure", "stone"),
            ("chalk_quarry_scarp_washout_slide", "Washed-Out White Chalk Gravel Bank", "Bờ Đá Phấn Trắng Bị Nước Mưa Xói Mòn Trượt Xuống", [2, 1], "walk_surface", False, "low", None, "structure", "stone"),
        ], 21),
    ]

    for sub_id, archetypes, target_count in subs_ground:
        sub_items = []
        for a_slug, a_name, a_vn, fp, col, blk, vis, vrb, atype, mat in archetypes:
            for v_slug, v_name, v_vn, cult, desc in var5_ground:
                slug = f"{a_slug}_{v_slug}"
                name = f"{v_name} {a_name}"
                vn = f"{a_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down seamless ground surface of {name.lower()}, {desc}, "
                    f"Medieval living ground pavement and terrain layer, gouache hand-painted, ink contours."
                )
                sub_items.append(make_asset(
                    cid, slug, name, vn, sub_id, fp, col, blk, vis, vrb,
                    f"Ground and street living surface ({a_name}).", False, mat, cult, prompt,
                    asset_type="terrain_texture", alpha="opaque", pivot="center"
                ))
        needed = target_count - len(sub_items)
        for i in range(needed):
            hero_id = f"{sub_id}_royal_highway_paving_{i+1}"
            hero_name = f"Royal Highroad {sub_id.replace('_', ' ').title()} #{i+1}"
            hero_vn = f"Đại Lộ Hoàng Gia {sub_id.replace('_', ' ').title()} #{i+1}"
            sub_items.append(make_asset(
                cid, hero_id, hero_name, hero_vn, sub_id, [2, 2], "walk_surface", False, "transparent",
                "march", "Royal paved highway surface.", False, "stone", "universal_feudal",
                f"Royal paved highway section of {sub_id}, dressed ashlar flagstones, medieval style.",
                asset_type="terrain_texture", alpha="opaque", pivot="center"
            ))
        items.extend(sub_items)

    # =========================================================================
    # 5. domesticity_chores_and_habitation_traces (120 assets: 6 subs * 20)
    # =========================================================================
    var4_trace = [
        ("freshly_done", "Freshly-Washed", "Vừa Giặt Phơi Xong", "universal_feudal", "flapping in wind with sweet water smell"),
        ("weather_stained", "Mud & Soot Stained", "Lấm Lem Tro Bụi", "universal_feudal", "earthy grime from hard manual daily labor"),
        ("dappled_sunlight", "Sunlit Yard", "Nắng Rọi Sân Nhà", "universal_feudal", "warm afternoon sunlight filtering through branches"),
        ("busy_active", "Daily Chore Active", "Đang Làm Việc Nhà", "universal_feudal", "active steam, embers, or fresh tool marks"),
    ]
    subs_trace = [
        ("linen_washing_lines_and_bleaching_greens", [
            ("hemp_rope_clothesline_with_shirts", "Hemp Washing Line Hung with Linen Tunics", "Dây Thừng Treo Phơi Áo Sơ Mi Vải Lanh", [2, 1], "cover", False, "low", "take_linen", "prop", "cloth"),
            ("forked_wooden_prop_clothesline_pole", "Forked Ashwood Line Prop Pole", "Cây Sào Gỗ Chống Đỡ Dây Phơi Quần Áo", [1, 1], "cover", False, "transparent", None, "prop", "wood"),
            ("bleaching_linen_meadow_spread", "Linen Smocks Bleaching on Green Grass", "Áo Vải Lanh Trải Phơi Nắng Trên Bãi Cỏ", [2, 1], "walk_surface", False, "transparent", "bleach_clothes", "prop", "cloth"),
            ("washing_tub_and_wooden_beater_paddle", "Oak Wash Tub with Grooved Beating Bat", "Chậu Gỗ Giặt Quần Áo & Bàn Gỗ Đập Vải", [1, 1], "water", False, "low", "wash_laundry", "prop", "wood"),
            ("wicker_laundry_basket_linen_pile", "Woven Willow Basket of Folded Linens", "Sọt Đan Nan Liễu Đựng Quần Áo Đã Gấp Gọn", [1, 1], "cover", False, "low", "loot_linens", "prop", "cloth"),
        ]),
        ("manure_middens_and_muck_heaps", [
            ("steaming_straw_manure_midden", "High Steaming Stable Dung Heap with Straw", "Đống Phân Chuồng Bốc Khói Mùn Lẫn Rơm", [2, 2], "solid", True, "low", "shovel_manure", "structure", "earth"),
            ("wooden_muck_fork_stuck_in_dung", "Four-Prong Iron Muck Fork in Dunghill", "Cào Sắt Bốn Răng Cắm Trên Đống Phân Chuồng", [1, 1], "cover", False, "low", "take_fork", "prop", "iron"),
            ("liquid_manure_cesspool_pit", "Covered Wooden Cesspit Drain Opening", "Miệng Hố Nước Thải Phân Lỏng Có Nắp Gỗ Đậy", [1, 1], "walk_surface", False, "low", "avoid_cesspool", "structure", "wood"),
            ("manure_basket_wheelbarrow_rig", "Two-Wheeled Dunghill Spreading Barrow", "Xe Cút Kít Chở Phân Chuồng Bón Ruộng", [2, 1], "cover", False, "low", "haul_manure", "prop", "wood"),
            ("scavenging_flies_swarming_dung", "Swarm of Flies Hovering Over Midden", "Đàn Ruồi Bay Vo Ve Quanh Đống Phân Chuồng", [1, 1], "walk_surface", False, "transparent", None, "prop", "organic"),
        ]),
        ("outdoor_chopping_blocks_and_axe_splits", [
            ("giant_oak_tree_chopping_stump", "Massive Splitting Block with Iron Wedge", "Khúc Gỗ Sồi Khổng Lồ Chẻ Củi Kèm Nêm Sắt", [1, 1], "solid", True, "low", "chop_wood", "prop", "wood"),
            ("felling_axe_embedded_in_timber", "Forged Iron Felling Axe Lodged in Stump", "Lưỡi Rìu Sắt Cắm Chặt Vào Thân Khúc Gỗ Sồi", [1, 1], "cover", False, "low", "pull_axe", "prop", "iron"),
            ("scatter_of_fresh_wood_chips_debris", "Scatter of Pale Hewn Splinters on Grass", "Mảnh Vụn Phoi Gỗ Bắn Tung Tóe Trên Bãi Cỏ", [1, 1], "walk_surface", False, "transparent", "gather_kindling", "prop", "wood"),
            ("split_oak_kindling_basket", "Basket Filled with Dry Resinous Kindling", "Giỏ Nan Đựng Đầy Củi Chẻ Nhỏ Nhóm Lò", [1, 1], "cover", False, "low", "take_kindling", "prop", "wood"),
            ("stacked_neat_cordwood_wall", "Neatly Stacked Half-Cord Firewood Wall", "Bức Tường Củi Gỗ Xếp Ngăn Nắp Che Gió", [2, 1], "solid", True, "low", "take_firewood", "structure", "wood"),
        ]),
        ("muddy_cartwheel_ruts_and_puddles", [
            ("deep_curving_cartwheel_mud_tracks", "Curving Wheel Ruts Filled with Brown Water", "Vệt Bánh Xe Uốn Cong Chứa Đầy Nước Mưa Đục", [2, 2], "walk_surface", False, "transparent", None, "structure", "earth"),
            ("abandoned_broken_wooden_wagon_spoke", "Broken Spoke & Rim Fragment in Mud Rut", "Nan Hoa Gỗ Bị Gãy Rơi Trong Vũng Bùn Lầy", [1, 1], "walk_surface", False, "transparent", "salvage_spoke", "prop", "wood"),
            ("stepped_muddy_footprints_cluster", "Cluster of Clouted Peasant Bootprints", "Dấu Ủng Đóng Đinh Sắt Của Nông Dân Lún Bùn", [1, 1], "walk_surface", False, "transparent", "track_footsteps", "structure", "earth"),
            ("ox_hoofprint_clover_depression", "Cloven Ox Hoofmarks Stamped in Wet Clay", "Vết Móng Bò Chẻ Đôi Dẫm Sâu Xuống Đất Sét", [1, 1], "walk_surface", False, "transparent", "track_cattle", "structure", "earth"),
            ("drainage_board_across_deep_rut", "Split Plank Bridging Muddy Cart Trench", "Tấm Ván Gỗ Bác Qua Vũng Bùn Cho Dân Đi Bộ", [2, 1], "walk_surface", False, "low", "cross_rut", "structure", "wood"),
        ]),
        ("hearth_ash_pits_and_charcoal_sweepings", [
            ("outdoor_hearth_grey_ash_pit", "Circular Pit of Cool Grey Fireplace Ash", "Hố Đổ Tro Bếp Xám Lạnh Ngoài Sân", [1, 1], "walk_surface", False, "transparent", "spread_ash", "structure", "earth"),
            ("charcoal_sweepings_black_soil_patch", "Black Charcoal-Enriched Kitchen Garden Soil", "Mảng Đất Trồng Rau Bón Than Củi Đen Xì", [1, 1], "walk_surface", False, "transparent", "cultivate_soil", "structure", "earth"),
            ("iron_fire_rake_leaning_on_wall", "Forged Iron Ash Scraper Leaning on Stone", "Cào Sắt Cào Tro Tựa Vào Tường Đá", [1, 1], "cover", False, "transparent", "take_scraper", "prop", "iron"),
            ("potash_leaching_wooden_barrel", "Perforated Barrel Leaching Potash for Soap", "Thùng Gỗ Lọc Tro Lấy Nước Kiềm Nấu Xà Phòng", [1, 1], "cover", False, "low", "drain_potash", "prop", "wood"),
            ("charred_kindling_debris_heap", "Heap of Extinguished Smudged Pine Twigs", "Đống Cành Cây Thông Cháy Dở Đen Đúa", [1, 1], "cover", False, "low", "salvage_charcoal", "prop", "wood"),
        ]),
        ("thatched_eaves_drying_herbs_and_onions", [
            ("plaited_onion_and_garlic_braid", "Braided Strings of Drying Golden Onions", "Dây Hành Tây & Tỏi Bện Treo Dưới Mái Hiên", [1, 1], "cover", False, "transparent", "take_onion", "prop", "organic"),
            ("hanging_dried_thyme_and_sage_bunches", "Bouquets of Fragrant Hanging Dried Sage", "Từng Chùm Cây Xô Thơm & Xạ Hương Khô Treo Rủ", [1, 1], "cover", False, "transparent", "harvest_herbs", "prop", "organic"),
            ("dried_salted_ham_in_linen_sack", "Smoked Pork Ham in Burlap Hanging from Beam", "Đùi Heo Hun Khói Bọc Vải Bao Tải Treo Dầm Gỗ", [1, 1], "cover", False, "low", "cut_ham", "prop", "organic"),
            ("clay_jugs_hung_on_timber_fence_palings", "Row of Inverted Clay Milk Jugs on Posts", "Dãy Bình Gốm Đựng Sữa Úp Ngược Trên Cọc Rào", [2, 1], "cover", False, "low", "take_jug", "prop", "stone"),
            ("drying_red_apple_rings_on_string", "Festoon of Sliced Apple Rings Drying", "Dây Xâu Táo Cắt Lát Phơi Khô Chua Ngọt", [1, 1], "cover", False, "transparent", "taste_apple_rings", "prop", "organic"),
        ]),
    ]
    build_cat_subs("domesticity_chores_and_habitation_traces", subs_trace, var4_trace, 20)

    # =========================================================================
    # 6. wildlife_micro_fauna_birds_and_pests (120 assets: 6 subs * 20)
    # =========================================================================
    var4_fauna = [
        ("perched_alert", "Alert-Perched", "Đậu Cảnh Giác", "universal_feudal", "feathers ruffled and sharp watchful eyes"),
        ("scavenging_busy", "Ground-Scavenging", "Kiếm Ăn Dưới Đất", "universal_feudal", "pecking grain and scratching in loam"),
        ("nesting_snug", "Eaves-Nesting", "Làm Tổ Trong Mái", "universal_feudal", "woven straw and mud mud daubed nests"),
        ("fleeting_startled", "Startled-Fluttering", "Giật Mình Bay Lên", "universal_feudal", "wings spreading to take flight"),
    ]
    subs_fauna = [
        ("cathedral_roosting_pigeons_and_doves", [
            ("flock_of_stone_perched_pigeons", "Pigeons Roosting on Gothic Stone Corbel", "Đàn Bồ Câu Đậu Trên Mỏm Đá Đầu Cột Giáo Đường", [1, 1], "cover", False, "low", "scatter_pigeons", "creature", "organic"),
            ("white_dove_in_belfry_archway", "White Peace Dove in Cathedral Belfry Niche", "Chim Bồ Câu Trắng Trong Hốc Tháp Chuông", [1, 1], "cover", False, "transparent", "coo_dove", "creature", "organic"),
            ("pigeon_dropping_whitened_masonry", "Stone Pier Splattered with White Guano", "Mảng Tường Đá Loang Lổ Vết Phân Chim Bồ Câu", [1, 1], "cover", False, "transparent", None, "prop", "stone"),
            ("twigs_and_straw_pigeon_nest", "Messy Stick Nest with Two White Eggs", "Tổ Bồ Câu Đan Bằng Cành Cây Có Hai Trứng", [1, 1], "cover", False, "low", "loot_eggs", "prop", "organic"),
            ("pecking_pigeons_in_market_cobbles", "Pigeons Pecking Spilled Breadcrumbs on Ground", "Đàn Bồ Câu Mổ Mảnh Bánh Mì Rơi Trên Đá", [1, 1], "walk_surface", False, "transparent", "chase_birds", "creature", "organic"),
        ]),
        ("gallows_carrion_crows_and_ravens", [
            ("black_raven_perched_on_gibbet_crossbar", "Glossy Black Raven on Gallows Timber Beam", "Con Quạ Đen Óng Ả Đậu Trên Xà Ngang Giá Treo Cổ", [1, 1], "cover", False, "low", "listen_croak", "creature", "organic"),
            ("pair_of_squabbling_hooded_crows", "Pair of Hooded Crows Fighting over Bone", "Cặp Quạ Đen Giành Nhau Khúc Xương Trên Cỏ", [1, 1], "cover", False, "low", "shoo_crows", "creature", "organic"),
            ("carrion_bird_perched_on_skull_spike", "Magpie Perched on Iron Impaling Spike", "Chim Ác Là Đậu Trên Cọc Sắt Cắm Đầu Tội Nhân", [1, 1], "cover", False, "low", "watch_magpie", "creature", "organic"),
            ("black_feather_shedding_in_mud", "Glossy Raven Flight Feathers Dropped in Dirt", "Lông Vũ Quạ Đen Óng Ánh Rơi Trên Vết Bùn", [1, 1], "walk_surface", False, "transparent", "collect_feather", "prop", "organic"),
            ("crows_calling_from_dead_oak_branch", "Carrion Crow Calling from Bare Oak Bough", "Quạ Đen Kêu Kêu Thảm Thiết Trên Cành Sồi Khô", [1, 1], "cover", False, "low", "listen_omen", "creature", "organic"),
        ]),
        ("thatched_roof_barn_swallows", [
            ("mud_built_barn_swallow_cup_nest", "Mud Pellets & Straw Swallow Nest Under Eaves", "Tổ Chim Nhạn Đắp Bằng Đất Sét Dưới Mái Tranh", [1, 1], "cover", False, "transparent", "inspect_nest", "prop", "earth"),
            ("fork_tailed_barn_swallows_perched", "Row of Fork-Tailed Swallows on Timber Rafter", "Hàng Chim Nhạn Đuôi Kéo Đậu Trên Xà Gồ Mái", [1, 1], "cover", False, "transparent", "admire_swallows", "creature", "organic"),
            ("flying_barn_swallow_skimming_pasture", "Swallow Skimming Low over Village Pond", "Chim Nhạn Chao Lượn Sát Mặt Nước Bắt Muỗi", [1, 1], "cover", False, "transparent", "watch_flight", "creature", "organic"),
            ("hungry_chicks_gaping_in_mud_nest", "Four Yellow-Beaked Swallow Chicks in Nest", "Bốn Chú Chim Nhạn Non Há Mỏ Đòi Mồi Trong Tổ", [1, 1], "cover", False, "transparent", "feed_chicks", "creature", "organic"),
            ("swallow_chirping_on_cottage_ridge", "Singing Barn Swallow on Thatched Ridge Spar", "Chim Nhạn Đậu Trên Đỉnh Nóc Nhà Hót Véo Von", [1, 1], "cover", False, "low", "listen_song", "creature", "organic"),
        ]),
        ("granary_rats_and_field_mice", [
            ("fat_brown_wharf_rat_near_grain_sack", "Brown Wharf Rat Gnawing on Burlap Sack", "Con Chuột Cống Nâu Béo Đang Gặm Bao Thóc", [1, 1], "cover", False, "low", "strike_rat", "creature", "organic"),
            ("burrowing_field_mouse_in_straw_bale", "Field Mouse Peeking from Golden Haycock", "Chuột Đồng Nhỏ Thò Đầu Ra Khỏi Bó Rơm Vàng", [1, 1], "cover", False, "low", "catch_mouse", "creature", "organic"),
            ("rat_gnawed_wooden_granary_baseboard", "Oak Skirting Board with Chewed Hole", "Gờ Chân Tường Gỗ Sồi Bị Chuột Khoét Lỗ", [1, 1], "cover", False, "transparent", "plug_hole", "prop", "wood"),
            ("deadfall_slate_mouse_trap_rig", "Slate Slab Propped on Figure-Four Stick", "Bẫy Chuột Phiến Đá Kê Cành Gỗ Chữ Bốn", [1, 1], "cover", False, "low", "set_trap", "prop", "stone"),
            ("rats_nest_of_shredded_parchment", "Rat Nest Built of Shredded Old Charters", "Tổ Chuột Làm Bằng Giấy Da Cũ Bị Xé Vụn", [1, 1], "cover", False, "low", "search_nest", "prop", "organic"),
        ]),
        ("timber_wall_geckos_and_spiders", [
            ("heavy_funnel_spider_web_in_corner", "Dusty Funnel Cobweb in Barn Timber Joint", "Mạng Nhện Màng Phễu Bám Đầy Bụi Góc Xà Gỗ", [1, 1], "cover", False, "transparent", "clear_web", "prop", "organic"),
            ("garden_spider_in_dew_orb_web", "Orb-Weaver Spider in Beaded Morning Dew Web", "Nhện Hoa Đan Lưới Tròn Đọng Hạt Sương Sớm", [1, 1], "cover", False, "transparent", "admire_web", "creature", "organic"),
            ("timber_bark_creeping_woodlouse", "Cluster of Slaters & Woodlice in Damp Bark", "Đàn Bọ Cắn Gỗ Woodlice Nấp Dưới Vỏ Cây Mục", [1, 1], "walk_surface", False, "transparent", "examine_bugs", "creature", "organic"),
            ("timber_beetle_deathwatch_hole", "Exit Holes of Deathwatch Wood-Boring Beetle", "Lỗ Mọt Gỗ Deathwatch Đục Thủng Dầm Gỗ Sồi", [1, 1], "cover", False, "transparent", "inspect_rot", "prop", "wood"),
            ("centipede_scuttling_under_stone", "Red-Banded Stone Centipede under Flagstone", "Con Rết Đá Đỏ Bò Ra Khỏi Khe Phiến Đá Lát", [1, 1], "walk_surface", False, "transparent", "stomp_centipede", "creature", "organic"),
        ]),
        ("fen_marsh_frogs_and_water_beetles", [
            ("common_green_frog_on_waterlily_pad", "Common Green Frog Resting on Broad Pond Pad", "Con Ếch Xanh Ngồi Trên Lá Sen Đầm Lầy", [1, 1], "cover", False, "transparent", "catch_frog", "creature", "organic"),
            ("great_diving_beetle_in_clear_water", "Great Diving Water Beetle with Silver Bubble", "Bọ Nước Lớn Lặn Bắt Mồi Có Bong Bóng Khí", [1, 1], "water", False, "transparent", "observe_beetle", "creature", "organic"),
            ("ribbon_of_black_toad_spawn_in_mud", "Jelly Ribbon of Black Toad Spawn in Shallows", "Dải Trứng Cóc Đen Quánh Bám Cành Cây Dưới Nước", [1, 1], "water", False, "transparent", "inspect_spawn", "prop", "organic"),
            ("croaking_common_toad_on_peat_turf", "Warty Brown Toad Crouched on Peat Moss", "Con Cóc Nâu Da Cóc Sần Sùi Ngồi Trên Thảm Than Bùn", [1, 1], "cover", False, "low", "poke_toad", "creature", "organic"),
            ("metallic_dragonfly_perched_on_reed", "Blue Damselfly Resting on Tip of Bulrush", "Chuồn Chuồn Kim Xanh Lam Đậu Đầu Ngọn Cỏ Sậy", [1, 1], "cover", False, "transparent", "admire_damselfly", "creature", "organic"),
        ]),
    ]
    build_cat_subs("wildlife_micro_fauna_birds_and_pests", subs_fauna, var4_fauna, 20)

    # =========================================================================
    # 7. denizens_burghers_peasants_and_beasts (140 assets: 2*24 + 4*23)
    # =========================================================================
    cid = "denizens_burghers_peasants_and_beasts"
    var_denizen = [
        ("laboring_day", "Daily Laboring", "Đang Làm Việc", "universal_feudal", "active working tools and earnest posture"),
        ("market_dressed", "Town Sunday-Best", "Trang Phục Đi Chợ", "universal_feudal", "clean dyed tunics and polished leather belts"),
        ("weary_evening", "Weary Respite", "Nghỉ Ngơi Chiều Tà", "universal_feudal", "relaxed seated resting posture"),
        ("chivalric_martial", "Martial-Bearing", "Phong Thái Hiệp Sĩ", "universal_feudal", "erect posture and hand upon weapon"),
    ]
    subs_denizen = [
        # Sub 1: 24 (4 archetypes * 6 variants = 24)
        ("peasant_serfs_and_field_laborers", [
            ("scythe_wielding_peasant_harvester", "Peasant Harvester with Long Scythe", "Nông Nô Cầm Lưỡi Hái Gặt Lúa Mì", [1, 1], "solid", False, "low", "talk_peasant", "creature", "organic"),
            ("gleaner_woman_with_grain_sheaf", "Gleaner Maiden Carrying Straw Sheaf", "Cô Gái Nhặt Thóc Ôm Bó Rơm Vàng", [1, 1], "solid", False, "low", "talk_gleaner", "creature", "organic"),
            ("elderly_peasant_with_walking_staff", "Aged Serf Leaning on Knotted Blackthorn Staff", "Lão Nông Nô Chống Gậy Gỗ Gai Già Nua", [1, 1], "solid", False, "low", "greet_elder", "creature", "organic"),
            ("barefoot_serf_boy_leading_oxen", "Young Serf Boy Holding Oxen Lead Rope", "Cậu Bé Nông Nô Chân Đất Dắt Mũi Bò", [1, 1], "solid", False, "low", "talk_boy", "creature", "organic"),
        ], 24),
        # Sub 2: 24
        ("guild_artisans_and_master_craftsmen", [
            ("leather_aproned_blacksmith_master", "Master Blacksmith Holding Sledgehammer", "Thầy Thợ Rèn Mặc Tạp Dề Da Cầm Búa Tạ", [1, 1], "solid", False, "low", "talk_smith", "creature", "organic"),
            ("flour_dusted_miller_with_grain_sack", "Miller in White Hood Carrying Rye Sack", "Bác Thợ Xay Áo Bám Bột Mì Vác Bao Thóc", [1, 1], "solid", False, "low", "talk_miller", "creature", "organic"),
            ("cordwainer_shoemaker_with_awl", "Cobbler Seated with Knife & Leather Shoe", "Thợ Đóng Giày Cầm Dùi Khâu Đang Làm Việc", [1, 1], "solid", False, "low", "order_shoes", "creature", "organic"),
            ("brewster_woman_with_pewter_measure", "Female Alewife Holding Copper Pitcher", "Bà Chủ Nấu Bia Cầm Bình Đồng Đong Bia", [1, 1], "solid", False, "low", "order_ale", "creature", "organic"),
        ], 24),
        # Sub 3: 23 (4 archetypes * 5 = 20 + 3 hero = 23)
        ("burgher_merchants_and_civic_clerks", [
            ("fur_trimmed_hanseatic_guild_elder", "Prosperous Burgher Merchant in Woolen Robe", "Trưởng Lão Phường Hội Mặc Áo Dạ Viền Lông", [1, 1], "solid", False, "low", "negotiate_trade", "creature", "organic"),
            ("chancery_scribe_with_parchment_quill", "Chancery Clerk Holding Ledger & Inkwell", "Thư Lại Cầm Cuộn Sổ Da & Ống Bút Mực", [1, 1], "solid", False, "low", "read_contract", "creature", "organic"),
            ("town_watch_bailiff_with_wooden_staff", "City Bailiff with Seal & Painted Staff", "Viên Chức Tòa Thị Chính Cầm Gậy Quyền Năng", [1, 1], "solid", False, "low", "pay_fine", "creature", "organic"),
            ("moneychanger_inspecting_silver_penny", "Moneychanger at Table Weighing Coins", "Người Đổi Tiền Cân Bạc Trên Bàn Cân", [1, 1], "solid", False, "low", "exchange_currency", "creature", "organic"),
        ], 23),
        # Sub 4: 23
        ("clergy_monks_friars_and_bishops", [
            ("brown_robed_franciscan_wandering_friar", "Barefoot Franciscan Friar with Knotted Cord", "Tu Sĩ Dòng Phanxicô Áo Nâu Chân Trần", [1, 1], "solid", False, "low", "receive_blessing", "creature", "organic"),
            ("black_habited_benedictine_abbot", "Benedictine Abbot with Pectoral Gold Cross", "Viện Phụ Áo Đen Dòng Biển Đức Đeo Thánh Giá", [1, 1], "solid", False, "low", "seek_counsel", "creature", "organic"),
            ("parish_priest_with_communion_chalice", "Village Parish Priest with Open Bible", "Cha Xứ Ngôi Làng Cầm Sách Kinh Mở Sẵn", [1, 1], "solid", False, "low", "confess_sins", "creature", "organic"),
            ("cloistered_cistercian_nun_in_wimple", "Cistercian Nun in White Wimple & Rosary", "Nữ Tu Sĩ Cistercian Khăn Trùm Đầu Trắng", [1, 1], "solid", False, "low", "request_prayers", "creature", "organic"),
        ], 23),
        # Sub 5: 23
        ("feudal_knights_men_at_arms_and_watch", [
            ("chainmail_hauberk_town_watch_halberdier", "Town Watch Guard with Halberd & Kettle Hat", "Lính Gác Cửa Thành Cầm Kích Đội Nón Sắt", [1, 1], "solid", False, "low", "challenge_guard", "creature", "organic"),
            ("chivalric_armored_knight_with_broadsword", "Knight in Polished Plate with Sheathed Sword", "Hiệp Sĩ Mặc Giáp Thép Kiếm Dài Đeo Hông", [1, 1], "solid", False, "low", "salute_knight", "creature", "organic"),
            ("yeoman_longbowman_with_yew_bow", "Yeoman Archer Holding Six-Foot Yew Longbow", "Cung Thủ Dân Quân Cầm Cung Dài Cây Thủy Tùng", [1, 1], "solid", False, "low", "inspect_arrows", "creature", "organic"),
            ("mounted_patrolling_sergeant_on_horse", "Mounted Sergeant at Arms on Sturdy Gelding", "Hạ Sĩ Quan Kỵ Mã Cầm Ngọn Giáo Đi Tuần", [2, 1], "solid", False, "low", "report_sentry", "creature", "organic"),
        ], 23),
        # Sub 6: 23
        ("domestic_draft_beasts_oxen_and_steeds", [
            ("heavy_muscled_yoked_plow_ox", "Horned White Draft Ox with Wooden Yoke", "Con Bò Kéo Cày Trắng Vạm Vỡ Đeo Ách Gỗ", [2, 1], "solid", False, "low", "pat_ox", "creature", "organic"),
            ("armored_destrier_warhorse_stallion", "Muscular War Destrier with Studded Bridle", "Chiến Mã Destrier To Lớn Đeo Cương Sắt", [2, 1], "solid", False, "low", "mount_destrier", "creature", "organic"),
            ("pannier_laden_donkey_pack_mule", "Shaggy Pack Donkey Carrying Wicker Baskets", "Con Lừa Thồ Hàng Lông Xù Đeo Đôi Sọt Gỗ", [1, 1], "solid", False, "low", "lead_donkey", "creature", "organic"),
            ("brindle_shepherds_working_collie_dog", "Shepherd's Alert Sheepdog Crouched on Turf", "Chó Chăn Cừu Chân Nhanh Nằm Canh Đàn Cừu", [1, 1], "cover", False, "low", "pet_dog", "creature", "organic"),
        ], 23),
    ]

    for sub_id, archetypes, target_count in subs_denizen:
        sub_items = []
        if target_count == 24:
            var6_d = var_denizen + [
                ("festive_fair", "Fairground-Festive", "Trang Phục Lễ Hội", "universal_feudal", "adorned with festive ribbons and polished brass buckle"),
                ("hardened_veteran", "Battle-Hardened", "Dạn Dày Sương Gió", "universal_feudal", "scars of honorable service and seasoned gaze"),
            ]
            for a_slug, a_name, a_vn, fp, col, blk, vis, vrb, atype, mat in archetypes:
                for v_slug, v_name, v_vn, cult, desc in var6_d:
                    slug = f"{a_slug}_{v_slug}"
                    name = f"{v_name} {a_name}"
                    vn = f"{a_vn} ({v_vn})"
                    prompt = (
                        f"2D orthographic top-down game sprite of {name.lower()}, {desc}, "
                        f"Medieval living denizen character portrait sprite, gouache hand-painted, ink contours, isolated on white background."
                    )
                    sub_items.append(make_asset(
                        cid, slug, name, vn, sub_id, fp, col, blk, vis, vrb,
                        f"Living medieval denizen character ({a_name}).", False, mat, cult, prompt,
                        asset_type=atype
                    ))
        elif target_count == 23:
            var5_d = var_denizen + [
                ("travel_cloaked", "Travel-Cloaked", "Áo Choàng Đi Đường", "universal_feudal", "heavy wool traveling cloak and hood against rain"),
            ]
            for a_slug, a_name, a_vn, fp, col, blk, vis, vrb, atype, mat in archetypes:
                for v_slug, v_name, v_vn, cult, desc in var5_d:
                    slug = f"{a_slug}_{v_slug}"
                    name = f"{v_name} {a_name}"
                    vn = f"{a_vn} ({v_vn})"
                    prompt = (
                        f"2D orthographic top-down game sprite of {name.lower()}, {desc}, "
                        f"Medieval living world inhabitant character, gouache hand-painted, ink contours, isolated on white background."
                    )
                    sub_items.append(make_asset(
                        cid, slug, name, vn, sub_id, fp, col, blk, vis, vrb,
                        f"Living feudal inhabitant ({a_name}).", False, mat, cult, prompt,
                        asset_type=atype
                    ))
            needed = target_count - len(sub_items)
            for i in range(needed):
                hero_id = f"{sub_id}_legendary_figure_{i+1}"
                hero_name = f"Legendary {sub_id.replace('_', ' ').title()} #{i+1}"
                hero_vn = f"Nhân Vật Huyền Thoại {sub_id.replace('_', ' ').title()} #{i+1}"
                sub_items.append(make_asset(
                    cid, hero_id, hero_name, hero_vn, sub_id, [1, 1], "solid", False, "low",
                    "commune", "Legendary living world inhabitant.", False, "organic", "universal_feudal",
                    f"Legendary living world historical figure of {sub_id}, authentic medieval portrayal, gouache anime style.",
                    asset_type="creature"
                ))
        items.extend(sub_items)

    return items
