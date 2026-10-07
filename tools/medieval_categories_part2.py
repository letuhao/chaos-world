# -*- coding: utf-8 -*-
"""Medieval Western Categories Part 2 (Categories 8 - 15: 1,650 assets)."""

from __future__ import annotations

def generate_part2(make_asset) -> list[dict]:
    items: list[dict] = []

    variants_8 = [
        ("norman_sturdy", "Norman Sturdy", "Kiểu Norman Bền Chắc", "norman", "massive oak timbers and hand-forged iron reinforcements"),
        ("weathered_aged", "Time-Weathered", "Dãi Dầu Năm Tháng", "anglo_saxon", "distressed surfaces with rich dark patina"),
        ("flemish_guild", "Flemish Master Guild", "Phường Hội Flanders", "flemish", "expert joinery, polished copper accents, and guild marks"),
        ("capetian_royal", "Capetian Royal Licensed", "Đặc Quyền Hoàng Triều Pháp", "french_capetian", "refined detailing with stamped royal fleur-de-lis seals"),
        ("germanic_imperial", "Germanic Imperial", "Đế Chế Đức", "germanic_holy_roman", "heavy industrial steel strapping and geometric bracing"),
        ("rustic_common", "Rustic Common Folk", "Dân Dã Thường Dân", "universal_feudal", "unadorned local timber and rough drystone"),
        ("celtic_traditional", "Celtic Traditional", "Truyền Thống Xứ Celt", "celtic", "notched joinery with carved knotwork border motifs"),
        ("heavy_reinforced", "Iron-Banded Reinforced", "Bọc Đai Sắt Gia Cố", "norman", "heavy iron banding and square clenched nails"),
    ]

    variants_9 = [
        ("norman_sturdy", "Norman Sturdy", "Kiểu Norman Bền Chắc", "norman", "massive oak timbers and hand-forged iron reinforcements"),
        ("weathered_aged", "Time-Weathered", "Dãi Dầu Năm Tháng", "anglo_saxon", "distressed surfaces with rich dark patina"),
        ("flemish_guild", "Flemish Master Guild", "Phường Hội Flanders", "flemish", "expert joinery, polished copper accents, and guild marks"),
        ("capetian_royal", "Capetian Royal Licensed", "Đặc Quyền Hoàng Triều Pháp", "french_capetian", "refined detailing with stamped royal fleur-de-lis seals"),
        ("germanic_imperial", "Germanic Imperial", "Đế Chế Đức", "germanic_holy_roman", "heavy industrial steel strapping and geometric bracing"),
        ("rustic_common", "Rustic Common Folk", "Dân Dã Thường Dân", "universal_feudal", "unadorned local timber and rough drystone"),
        ("celtic_traditional", "Celtic Traditional", "Truyền Thống Xứ Celt", "celtic", "notched joinery with carved knotwork border motifs"),
        ("heavy_reinforced", "Iron-Banded Reinforced", "Bọc Đai Sắt Gia Cố", "norman", "heavy iron banding and square clenched nails"),
        ("autumn_harvest", "Autumn Golden Harvest", "Vụ Mùa Vàng Thu", "universal_feudal", "decorated with drying grain sheaves and autumn russet tones"),
    ]

    variants_11 = [
        ("norman_sturdy", "Norman Sturdy", "Kiểu Norman Bền Chắc", "norman", "heavy stone and stout oak timbers"),
        ("weathered_aged", "Time-Weathered", "Dãi Dầu Năm Tháng", "anglo_saxon", "worn smooth by decades of everyday use"),
        ("flemish_guild", "Flemish Guild Master", "Phường Hội Flanders", "flemish", "richly crafted with brass fittings and guild crests"),
        ("capetian_royal", "Capetian Royal Ordinance", "Sắc Lệnh Hoàng Gia Pháp", "french_capetian", "painted in regal azure and gold trims"),
        ("germanic_imperial", "Germanic Imperial Staufen", "Hoàng Đế La Mã Thần Thánh", "germanic_holy_roman", "heavily fortified with studded iron bands"),
        ("rustic_common", "Rustic Common Folk", "Dân Gian Thô Mộc", "universal_feudal", "coarse local materials and weathered hemp rope"),
        ("celtic_traditional", "Celtic Traditional", "Truyền Thống Celtic", "celtic", "coarse granite and bog-oak framing"),
        ("heavy_reinforced", "Iron-Banded Heavy", "Bọc Sắt Nặng Gia Cố", "norman", "braced with heavy iron strapping and thick rivets"),
        ("autumn_harvest", "Autumn Golden Season", "Mùa Thu Vàng Ruộm", "universal_feudal", "garnished with wheat straw and fallen maple foliage"),
        ("battle_worn", "Frontier Battle-Worn", "Chiến Trận Biên Cương", "universal_feudal", "notched with blade marks and smoke scorched edges"),
        ("mossy_river", "Riverbank Moss-Grown", "Phủ Rêu Bờ Nước", "universal_feudal", "damp green velvet moss encrusted along footings"),
    ]

    # =========================================================================
    # 8. guild_crafts_and_industry (260 assets: 4*45 + 2*40)
    # =========================================================================
    cid = "guild_crafts_and_industry"
    cat8_subs_45 = [
        ("blacksmith_and_armory", [
            ("hearth_bellows_forge", "Stone Blacksmith Hearth Forge with Leather Bellows (2x1)", "Lò Rèn Đá Có Ống Thổi Da (2x1)", [2, 1], "stone"),
            ("heavy_swage_anvil_block", "Heavy Master Anvil Mounted on Oak Tree Trunk (1x1)", "Đe Rèn Sắt Trên Thân Cây Sồi (1x1)", [1, 1], "iron"),
            ("brine_quenching_trough", "Iron-Strapped Wooden Brine Quenching Trough (2x1)", "Máng Nước Muối Tôi Kim Loại (2x1)", [2, 1], "wood"),
            ("blacksmith_tongs_hammer_rack", "Wall Tool Rack with Tongs, Sledges and Chisels (2x1)", "Giá Treo Kìm Búa Đục Thợ Rèn (2x1)", [2, 1], "iron"),
            ("armor_beating_swage_stand", "Cuirass Shaping Stake and Swage Block (1x1)", "Khuôn Đập Áo Giáp Tấm (1x1)", [1, 1], "iron"),
        ]),
        ("carpenter_and_cooper", [
            ("cooper_barrel_trussing_brazier", "Cooper Barrel-Bending Fire Brazier and Truss (2x1)", "Lò Đốt Uốn Nan Gỗ Đóng Thùng (2x1)", [2, 1], "iron"),
            ("joiners_sturdy_shaving_horse", "Woodworker Shaving Horse Bench with Drawknife (2x1)", "Ghế Bào Gỗ Cắt Kéo Chân Đạp (2x1)", [2, 1], "wood"),
            ("cooper_stacked_barrel_hoops", "Coiled Wrought-Iron Barrel Hoops & Staves (1x1)", "Vòng Đai Sắt & Nan Gỗ Đóng Thùng (1x1)", [1, 1], "iron"),
            ("carpenters_mortise_workbench", "Heavy Oak Joiners Workbench with Wooden Screw Vice (2x1)", "Bàn Thợ Mộc Có Ê-Tô Gỗ (2x1)", [2, 1], "wood"),
            ("timber_seasoning_drying_stack", "Stacked Air-Drying Oak Planks on Gluts (2x1)", "Chồng Ván Gỗ Sồi Phơi Khô (2x1)", [2, 1], "wood"),
        ]),
        ("tannery_and_leatherwork", [
            ("oak_bark_tan_liquor_vat", "Sunken Wooden Tan-Bark Leather Soaking Vat (2x2)", "Hầm Ngâm Da Thuộc Nước Vỏ Sồi (2x2)", [2, 2], "wood"),
            ("fleshing_beam_and_blades", "Curved Tanners Fleshing Beam with Two-Handed Knife (2x1)", "Khúc Gỗ Cạo Mỡ Da Thuộc (2x1)", [2, 1], "wood"),
            ("hide_stretching_trestle_frame", "Timber Frame with Cord-Tensioned Drying Hide (2x1)", "Khung Căng Căng Da Động Vật (2x1)", [2, 1], "wood"),
            ("lime_slaking_depilation_pit", "Stone-Lined Lime Pits for Dehairing Hides (2x1)", "Hố Vôi Ngâm Rụng Lông Da (2x1)", [2, 1], "stone"),
            ("curriers_tallow_finishing_table", "Leather Curriers Tallow Dressing Table (2x1)", "Bàn Bôi Mỡ Đánh Bóng Da Thuộc (2x1)", [2, 1], "wood"),
        ]),
        ("textile_fulling_and_dyeing", [
            ("madder_woad_dye_boiling_vat", "Copper Dye Vat on Brick Furnace with Boiling Woad (2x1)", "Chảo Nhuộm Đồng Nấu Nước Chàm (2x1)", [2, 1], "bronze"),
            ("fulling_mill_water_hammer_stocks", "Water-Driven Timber Fulling Hammer Stocks (2x2)", "Búa Gỗ Đập Nén Vải Dạ Nhờ Nước (2x2)", [2, 2], "wood"),
            ("broadcloth_tenter_drying_frames", "Long Tenter Field Drying Rack with Hooks (3x1)", "Giàn Phơi Căng Vải Nỉ Khổ Rộng (3x1)", [3, 1], "wood"),
            ("horizontal_treadle_loom_frame", "Weavers Horizontal Treadle Loom Frame (2x2)", "Khung Cửi Dệt Vải Bàn Đạp Chân (2x2)", [2, 2], "wood"),
            ("carding_combs_wool_drop_spindle", "Wool Distaff, Drop Spindles and Carding Combs (1x1)", "Con Suốt & Lược Chải Lông Cừu (1x1)", [1, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat8_subs_45:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_9:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "forge" if "forge" in c_slug or "anvil" in c_slug else "craft"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval guild workshop station ({c_name}).", False, mat, cult, prompt
                ))

    cat8_subs_40 = [
        ("pottery_and_glasswork", [
            ("kick_wheel_potters_bench", "Timber Kick-Wheel Throwing Potters Bench (1x1)", "Bàn Xoay Vuốt Gốm Đạp Chân (1x1)", [1, 1], "wood"),
            ("beehive_ceramic_brick_kiln", "Beehive Brick Updraft Pottery Kiln (2x2)", "Lò Nung Gốm Gạch Hình Tổ Ong (2x2)", [2, 2], "brick"),
            ("glassblowers_melting_pot_furnace", "Glassblowers Melting Furnace with Iron Blowpipes (2x1)", "Lò Nấu Thủy Tinh & Ống Thổi (2x1)", [2, 1], "stone"),
            ("drying_terracotta_pitcher_racks", "Timber Shelves of Unfired Clay Jugs and Pots (2x1)", "Kệ Phơi Bình Gốm Đất Mộc (2x1)", [2, 1], "ceramic"),
            ("glazing_slip_slurry_troughs", "Glaze Dipping Tubs with Mineral Pigments (1x1)", "Thùng Men Tráng Khoáng Chất (1x1)", [1, 1], "wood"),
        ]),
        ("masonry_and_stonecutter", [
            ("stonecutters_banker_bench", "Heavy Banker Workbench with Mallet & Chisels (2x1)", "Bàn Đẽo Đá Chắc Chắn Của Thợ (2x1)", [2, 1], "stone"),
            ("treadwheel_timber_hoist_crane", "Man-Powered Treadwheel Timber Lifting Crane (3x2)", "Cần Trục Bánh Xe Lồng Chân Kéo Đá (3x2)", [3, 2], "wood"),
            ("rough_ashlar_blocks_pallet", "Stack of Dressed Limestone Ashlar Blocks (2x1)", "Chồng Khối Đá Vôi Đã Đẽo Gọt (2x1)", [2, 1], "stone"),
            ("lime_mortar_mixing_pan", "Ox-Drawn Circular Lime Mortar Mixing Pan (2x2)", "Chảo Trộn Vữa Vôi Tròn Kéo Bò (2x2)", [2, 2], "stone"),
            ("masons_lifting_tongs_lewis", "Iron Lewis Pin Lifting Tackle and Shear-Legs (1x2)", "Chốt Kẹp Sắt Nâng Khối Đá Lớn (1x2)", [1, 2], "iron"),
        ]),
    ]
    for sub_id, concepts in cat8_subs_40:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    "craft", f"Craftsman workshop fixture ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 9. mills_mining_and_quarry (160 assets: 5 subcats * 32)
    # =========================================================================
    cid = "mills_mining_and_quarry"
    cat9_subs = [
        ("watermill_and_sluice", [
            ("overshot_wooden_waterwheel", "Heavy Oak Overshot Waterwheel (2x2)", "Bánh Xe Nước Chảy Tràn Bằng Gỗ (2x2)", [2, 2], "wood"),
            ("millrace_timber_flume_channel", "Raised Timber Millrace Flume Channel (3x1)", "Máng Nước Gỗ Dẫn Vào Cối Xay (3x1)", [3, 1], "wood"),
            ("millstone_pair_in_vat_casing", "Granite Millstones in Octagonal Wood Vat (2x1)", "Cặp Cối Đá Nghiền Vỏ Gỗ Bát Giác (2x1)", [2, 1], "stone"),
            ("sluice_gate_rack_pinion_winch", "Timber Sluice Control Gate with Iron Winch (1x1)", "Cửa Đập Điều Tiết Nước Tay Quay (1x1)", [1, 1], "wood"),
        ]),
        ("windmill_and_sails", [
            ("post_windmill_timber_body", "Trestle Post Windmill Wooden Structure (3x3)", "Cối Xay Gió Khung Gỗ Xoay Được (3x3)", [3, 3], "wood"),
            ("canvas_rigged_mill_sails_quarter", "Canvas-Rigged Lattice Windmill Sails (2x2)", "Cánh Buồm Vải Cối Xay Gió (2x2)", [2, 2], "cloth"),
            ("tailpole_turning_wheel_lever", "Timber Tailpole Winch for Turning Windmill (2x1)", "Cần Đòn Gỗ Kéo Đổi Hướng Cối Xay (2x1)", [2, 1], "wood"),
            ("grain_hopper_and_meal_sacks", "Grain Chute Hopper with Stacked Flour Sacks (2x1)", "Phễu Đổ Thóc & Bao Bột Mì (2x1)", [2, 1], "cloth"),
        ]),
        ("quarry_and_stone_pit", [
            ("limestone_quarry_stepped_face", "Stepped Ashlar Quarry Extraction Wall (3x2)", "Vách Khai Thác Đá Vôi Cắt Bậc (3x2)", [3, 2], "stone"),
            ("iron_plug_and_feather_wedges", "Iron Wedges Driven into Rock Splitting Line (1x1)", "Nêm Sắt Đóng Tách Khối Đá (1x1)", [1, 1], "iron"),
            ("quarry_timber_hoist_derrick", "Timber Shear-Leg Quarry Hoist Derrick (2x2)", "Cần Cẩu Chạc Gỗ Kéo Đá Hầm Mỏ (2x2)", [2, 2], "wood"),
            ("dressed_slab_sled_transport", "Heavy Oak Stone Drag Sled on Rollers (2x1)", "Máng Trượt Gỗ Kéo Khối Đá Nặng (2x1)", [2, 1], "wood"),
        ]),
        ("mine_adit_and_drift", [
            ("timber_shored_mine_adit_portal", "Timber-Shored Dark Mine Entrance Adit (2x2)", "Cửa Hầm Mỏ Gỗ Chống Đỡ Chắc Chắn (2x2)", [2, 2], "wood"),
            ("wooden_rail_and_ore_cart", "Wooden Flanged Track with Loaded Ore Cart (2x1)", "Đường Ray Gỗ & Xe Đẩy Quặng (2x1)", [2, 1], "wood"),
            ("mine_ventilation_leather_bellows", "Hand-Cranked Mine Air Bellows and Pipe (1x1)", "Ống Thổi Khí Thông Gió Hầm Mỏ (1x1)", [1, 1], "leather"),
            ("adit_drainage_wooden_trough", "Mine Sump Timber Drainage Launder Trough (2x1)", "Máng Gỗ Thoát Nước Rò Hầm Mỏ (2x1)", [2, 1], "wood"),
        ]),
        ("smelter_and_calcining", [
            ("iron_bloomery_shaft_furnace", "Clay-Lined Iron Bloomery Smelting Furnace (2x1)", "Lò Luyện Gang Thỏi Bọc Đất Sét (2x1)", [2, 1], "earth"),
            ("charcoal_burning_earthen_mound", "Steaming Charcoal Burning Earth Mound (2x2)", "Ụ Đốt Than Củi Phủ Đất Khói Bốc (2x2)", [2, 2], "earth"),
            ("smelter_slag_tapping_trench", "Slag Tapping Channel with Cooled Iron Slag (2x1)", "Rãnh Xả Xỉ Quặng Sắt Nguội (2x1)", [2, 1], "stone"),
            ("cast_iron_pig_ingots_stack", "Stacked Cast-Iron Bloom and Pig Bars (1x1)", "Chồng Thỏi Sắt Đúc Thành Phẩm (1x1)", [1, 1], "iron"),
        ]),
    ]
    for sub_id, concepts in cat9_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "mine" if "quarry" in sub_id or "mine" in sub_id else "operate_mill"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "solid",
                    verb, f"Milling, quarrying and mining fixture ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 2 and fprint[1] >= 2 else "prop"
                ))

    # =========================================================================
    # 10. agriculture_field_and_pastoral (270 assets: 5 subcats * 54: 6*9)
    # =========================================================================
    cid = "agriculture_field_and_pastoral"
    cat10_subs = [
        ("strip_field_and_furrows", [
            ("ridge_and_furrow_wheat_plot", "Ridge-and-Furrow Ripening Wheat Strip (3x2)", "Dải Ruộng Lúa Mì Vồng Luống Dài (3x2)", [3, 2], "plant"),
            ("spring_barley_furrow_plot", "Spring Barley Green Sprouting Furrows (3x2)", "Luống Mạ Đại Mạch Vụ Xuân (3x2)", [3, 2], "plant"),
            ("cabbage_and_leek_fenced_garden", "Peasant Cabbage & Leek Raised Beds (2x2)", "Vườn Bắp Cải & Tỏi Tây Luống Cao (2x2)", [2, 2], "plant"),
            ("fallow_field_with_grazing_clover", "Fallow Clover Field with Grazing Cow (3x2)", "Ruộng Nghỉ Trồng Cỏ Ba Lá (3x2)", [3, 2], "plant"),
            ("turnip_and_parsnip_root_patch", "Turnip & Parsnip Earth Root Vegetable Bed (2x1)", "Luống Củ Cải Trắng & Củ Cải Vàng (2x1)", [2, 1], "earth"),
            ("flax_linen_field_flowering_blue", "Flowering Blue Flax Fiber Plot (2x2)", "Bãi Cây Đay Nở Hoa Xanh Biếc (2x2)", [2, 2], "plant"),
        ]),
        ("plowing_and_harvesting", [
            ("wheeled_heavy_moldboard_plow", "Heavy Wheeled Moldboard Iron Plow (Carruca) (2x1)", "Cày Bánh Xe Lưỡi Lật Bọc Sắt (2x1)", [2, 1], "wood"),
            ("ox_drawn_wooden_harrow_frame", "Square Timber Spike Harrow for Soil Clods (2x1)", "Bừa Gỗ Răng Sắt Đập Đất (2x1)", [2, 1], "wood"),
            ("hay_wain_four_wheeled_wagon", "Loaded High-Sided Timber Hay Wain Wagon (3x2)", "Xe Bò Chở Cỏ Khô Bốn Bánh (3x2)", [3, 2], "wood"),
            ("harvesting_scythes_and_sheaves", "Crossed Harvesting Scythes and Wheat Sheaves (1x1)", "Lưỡi Hái Gặt & Bó Lúa Mì (1x1)", [1, 1], "iron"),
            ("threshing_flails_and_winnow_basket", "Jointed Threshing Flails and Winnowing Fan (1x1)", "Đòn Đập Lúa Khớp Nối & Sàng Thóc (1x1)", [1, 1], "wood"),
            ("heavy_ox_yoke_and_trace_chains", "Two-Ox Timber Yoke with Iron Trace Chains (2x1)", "Ách Gỗ Buộc Hai Bò Kéo Xích Sắt (2x1)", [2, 1], "wood"),
        ]),
        ("hayrick_and_granary", [
            ("conical_thatched_hayrick", "Tall Conical Thatched Straw Hayrick (2x2)", "Đống Rơm Lợp Mái Nón Cao (2x2)", [2, 2], "straw"),
            ("staddle_stone_raised_timber_granary", "Mushroom Staddle-Stone Timber Granary (2x2)", "Kho Thóc Gỗ Kê Chân Đá Nấm Tránh Chuột (2x2)", [2, 2], "wood"),
            ("flail_threshing_stone_floor", "Outdoor Cobbled Circular Threshing Floor (2x2)", "Sân Đập Lúa Tròn Lát Đá (2x2)", [2, 2], "stone"),
            ("corn_drying_hanging_timber_rack", "Outdoor A-Frame Corn Ear Drying Rack (2x1)", "Giá Phơi Bắp Ngô Bằng Gỗ Ngoài Trời (2x1)", [2, 1], "wood"),
            ("chaff_and_grain_storage_silos", "Woven Wattle Clay-Plastered Grain Silo (2x2)", "Bồ Đựng Thóc Đan Tre Trát Đất Sét (2x2)", [2, 2], "earth"),
            ("tithe_barn_massive_timber_bay", "Monastic Tithe Barn Heavy Timber Bay (3x2)", "Gian Kho Thóc Đóng Thuế Nhà Thờ (3x2)", [3, 2], "wood"),
        ]),
        ("orchard_and_vineyard", [
            ("cider_apple_espalier_trees", "Row of Gnarled Cider Apple Trees with Red Fruit (3x2)", "Hàng Cây Táo Rượu Nở Đầy Trái Đỏ (3x2)", [3, 2], "plant"),
            ("pear_and_plum_orchard_grove", "Mixed Pear & Damson Plum Orchard (3x2)", "Vườn Mận & Lê Quả Trĩu Cành (3x2)", [3, 2], "plant"),
            ("vineyard_post_wire_trellis", "Post-and-Wire Terraced Grape Vineyard Row (3x1)", "Giàn Nho Ruộng Bậc Thang Cột Gỗ (3x1)", [3, 1], "plant"),
            ("wooden_screw_cider_wine_press", "Heavy Timber Screw Press with Stone Weight (2x2)", "Máy Ép Nho Rượu Vang Trục Vít Gỗ (2x2)", [2, 2], "wood"),
            ("bushel_baskets_fresh_apples", "Woven Wicker Bushel Baskets Overspilling Fruit (1x1)", "Giỏ Mây Đầy Ắp Táo Mới Hái (1x1)", [1, 1], "wood"),
            ("fermenting_must_oak_tuns", "Row of Large Oak Must Fermenting Vats (2x1)", "Dãy Thùng Gỗ Sồi Lên Men Nước Nho (2x1)", [2, 1], "wood"),
        ]),
        ("livestock_pasture_and_fold", [
            ("drystone_walled_sheepfold", "Drystone Circular Upland Sheepfold Enclosure (3x3)", "Bờ Rào Đá Tròn Nhốt Cừu Vùng Cao (3x3)", [3, 3], "stone"),
            ("timber_cattle_hay_manger", "Covered Timber Cattle Feed Manger Trough (2x1)", "Máng Cỏ Cho Bò Ăn Có Mái Che (2x1)", [2, 1], "wood"),
            ("muddy_pig_wallow_pen", "Timber Post Pig Pen with Mud Wallow (2x2)", "Chuồng Lợn Rào Gỗ Có Vũng Bùn (2x2)", [2, 2], "wood"),
            ("straw_skep_bee_apiary_stand", "Sheltered Thatched Bee Skep Apiary Shelf (2x1)", "Kệ Đặt Giỏ Rơm Nuôi Ong Mật (2x1)", [2, 1], "straw"),
            ("goose_and_duck_pond_shelter", "Village Duck Pond with Thatched Island Coop (2x2)", "Ao Vịt Có Nhà Tranh Giữa Đảo Nhỏ (2x2)", [2, 2], "water"),
            ("sheep_shearing_timber_trestle", "Outdoor Sheep Shearing Wooden Trestle Table (2x1)", "Bàn Gỗ Cắt Lông Cừu Ngoài Trời (2x1)", [2, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat10_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_9:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "harvest_grain" if "harvest" in sub_id or "strip" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Manorial agriculture & livestock facility ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 2 and fprint[1] >= 2 else "prop"
                ))

    # =========================================================================
    # 11. urban_street_life_and_markets (220 assets: 5 subcats * 44)
    # =========================================================================
    cid = "urban_street_life_and_markets"
    cat11_subs = [
        ("market_stall_and_booth", [
            ("striped_canvas_market_booth", "Striped Linen Canvas Market Hawker Booth (2x1)", "Quầy Hàng Chợ Mái Vải Bạt Kẻ Sọc (2x1)", [2, 1], "cloth"),
            ("butcher_block_hanging_carcass", "Butchers Heavy Block with Hanging Game & Hams (2x1)", "Bàn Bán Thịt Có Móc Treo Thịt Rừng (2x1)", [2, 1], "wood"),
            ("fishmonger_iced_trough_stall", "Fishmonger Crushed Ice Stone Table with Eel (2x1)", "Bàn Đá Bán Cá & Lươn Tươi (2x1)", [2, 1], "stone"),
            ("bakers_crusty_bread_trestle", "Bakers Trestle Table with Sourdough Boules (2x1)", "Bàn Bày Bán Bánh Mì Lên Men (2x1)", [2, 1], "wood"),
        ]),
        ("trade_sign_and_plaque", [
            ("wrought_iron_hanging_tavern_sign", "Swinging Wrought-Iron Tavern Signpost (1x1)", "Biển Hiệu Quán Rượu Bằng Sắt Uốn (1x1)", [1, 1], "iron"),
            ("guild_master_carved_coat_plaque", "Carved Guild Shield Trade Plaque on Post (1x1)", "Biển Phù Hiệu Phường Hội Gỗ Chạm (1x1)", [1, 1], "wood"),
            ("barbers_bleeding_bowl_sign", "Barber-Surgeon Brass Bleeding Bowl Pole (1x1)", "Cột Treo Chậu Đồng Thầy Thuốc Cắt Tóc (1x1)", [1, 1], "brass"),
            ("bootmakers_gilded_shoe_emblem", "Shoemakers Carved Gilded Wooden Boot Sign (1x1)", "Biển Giày Gỗ Mạ Vàng Của Thợ Đóng Giày (1x1)", [1, 1], "wood"),
        ]),
        ("civic_infrastructure_and_law", [
            ("carved_gothic_market_cross", "Carved Gothic Stone Town Market Cross (2x2)", "Cột Đá Thánh Giá Chợ Thị Trấn Gothic (2x2)", [2, 2], "stone"),
            ("town_hall_parchment_noticeboard", "Timber Noticeboard with Royal Tax Proclamations (2x1)", "Bảng Cáo Thị Gỗ Dán Thông Báo Hoàng Gia (2x1)", [2, 1], "wood"),
            ("wooden_pillory_and_foot_stocks", "Public Shame Timber Pillory & Stocks on Dais (2x1)", "Gông Cổ & Cùm Chân Bằng Gỗ Bêu Nắng (2x1)", [2, 1], "wood"),
            ("civic_beam_steelyard_scales", "Town Fair Large Iron Beam Steelyard Scales (2x1)", "Cân Đòn Sắt Lớn Kiểm Tra Hàng Chợ (2x1)", [2, 1], "iron"),
        ]),
        ("street_clutter_and_refuse", [
            ("rainwater_street_gutter_puddle", "Cobblestone Street Gutter with Rainy Puddle (2x1)", "Rãnh Thoát Nước Mưa Đường Phố Có Vũng Nước (2x1)", [2, 1], "water"),
            ("horse_manure_and_straw_pile", "Street Mud Mound with Horse Manure & Straw (1x1)", "Đống Rơm Lẫn Phân Ngựa Lề Đường (1x1)", [1, 1], "earth"),
            ("broken_barrel_and_splintered_crates", "Smashed Cargo Barrel Staves and Rubbish Heap (2x1)", "Đống Rác Thùng Gỗ Vỡ & Mảnh Ván Rác (2x1)", [2, 1], "wood"),
            ("deep_carriage_mud_ruts_crossing", "Deep Parallel Carriage Ruts in Muddy Street (2x1)", "Rãnh Bánh Xe Ngựa Lún Sâu Lầy Lội (2x1)", [2, 1], "earth"),
        ]),
        ("street_lighting_and_braziers", [
            ("iron_cresset_basket_wall_mount", "Wrought-Iron Wall Pitch Cresset Basket (1x1)", "Giỏ Sắt Đốt Hắc Ín Gắn Tường Phố (1x1)", [1, 1], "iron"),
            ("town_watch_square_street_brazier", "Town Watch Open Charcoal Fire Brazier (1x1)", "Lò Than Sưởi Ấm Của Lính Canh Đêm (1x1)", [1, 1], "iron"),
            ("horned_glass_hanging_street_lantern", "Horne-Pane Glazed Hanging Oil Street Lantern (1x1)", "Đèn Dầu Treo Đường Phố Bằng Tấm Sừng (1x1)", [1, 1], "iron"),
            ("post_mounted_tar_barrel_beacon", "Iron-Banded Tar Barrel Warning Beacon Post (1x1)", "Cột Treo Thùng Hắc Ín Đốt Báo Hiệu (1x1)", [1, 1], "iron"),
        ]),
    ]
    for sub_id, concepts in cat11_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_11:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "browse_market" if "stall" in sub_id or "booth" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid" if "cross" in c_slug else "ground_contact", True, "transparent",
                    verb, f"Medieval city street dressing ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 12. tavern_inn_and_brewhouse (160 assets: 5 subcats * 32)
    # =========================================================================
    cid = "tavern_inn_and_brewhouse"
    cat12_subs = [
        ("bar_counter_and_taps", [
            ("heavy_oak_tavern_bar_counter", "Heavy Waxed Oak Tavern Bar Counter (3x1)", "Quầy Bar Quán Rượu Gỗ Sồi Đánh Sáp (3x1)", [3, 1], "wood"),
            ("pewter_tankards_drying_rack", "Wall Shelves of Pewter Tankards and Clay Mugs (2x1)", "Kệ Ly Bằng Thiếc & Cốc Gốm (2x1)", [2, 1], "iron"),
            ("brass_spigots_wine_cask_stand", "Under-Counter Wine Cask Spigots Dispenser (2x1)", "Giá Đỡ Vòi Rượu Vang Bằng Đồng Thau (2x1)", [2, 1], "brass"),
            ("tavern_chalkboard_tab_slate", "Hanging Chalk Slate for Customer Drink Tabs (1x1)", "Bảng Đá Viết Phấn Ghi Nợ Rượu (1x1)", [1, 1], "stone"),
        ]),
        ("drinking_hall_and_hearth", [
            ("round_communal_tavern_table", "Round Communal Oak Drinking Table with Stools (2x2)", "Bàn Uống Rượu Tròn Bằng Gỗ Kèm Ghế Đẩu (2x2)", [2, 2], "wood"),
            ("tavern_long_benches_dining_set", "Long Trestle Tavern Table with Bench Seats (3x1)", "Bàn Dài Quán Rượu Có Băng Ghế Dài (3x1)", [3, 1], "wood"),
            ("open_tavern_fire_spit_hearth", "Central Open Hearth Fire with Stew Pot (2x2)", "Bếp Lò Trung Tâm Quán Rượu Treo Nồi Hầm (2x2)", [2, 2], "stone"),
            ("dice_and_card_gaming_table", "Green Felt Gaming Table with Dice Cups & Cards (1x1)", "Bàn Đổ Xúc Xắc & Đánh Bài (1x1)", [1, 1], "wood"),
        ]),
        ("brewhouse_and_casks", [
            ("copper_mash_tun_brewing_vat", "Huge Copper Mash Tun Brewing Kettle (2x2)", "Nồi Nấu Bia Bằng Đồng Lớn (2x2)", [2, 2], "bronze"),
            ("stacked_oak_beer_hogsheads", "Pyramid Stack of Oak Ale Hogsheads and Casks (2x1)", "Chồng Thùng Gỗ Sồi Đựng Bia Ủ (2x1)", [2, 1], "wood"),
            ("wort_cooling_shallow_troughs", "Shallow Timber Wort Cooling Troughs (3x1)", "Máng Gỗ Làm Nguội Nước Cốt Bia (3x1)", [3, 1], "wood"),
            ("wooden_bung_mallet_barrel_tap", "Cooper Bung Mallet and Wooden Barrel Faucets (1x1)", "Búa Gõ Nút Thùng & Vòi Rượu Bằng Gỗ (1x1)", [1, 1], "wood"),
        ]),
        ("inn_stables_and_coaching", [
            ("horse_stalls_hay_rack_partition", "Twin Horse Stalls with Oak Manger Racks (2x2)", "Chuồng Hai Ngựa Có Máng Cỏ (2x2)", [2, 2], "wood"),
            ("saddle_and_bridle_wall_tack_rack", "Leather Saddles and Bridles Harness Rack (2x1)", "Giá Treo Yên Ngựa & Cương Da (2x1)", [2, 1], "leather"),
            ("stone_horse_watering_trough", "Carved Stone Courtyard Horse Water Trough (2x1)", "Máng Nước Uống Cho Ngựa Bằng Đá (2x1)", [2, 1], "stone"),
            ("coaching_wheel_timber_jack", "Wheelwright Coach Timber Jack and Spare Wheels (2x1)", "Kích Nâng Sửa Xe Ngựa Bằng Gỗ (2x1)", [2, 1], "wood"),
        ]),
        ("lodging_and_cellar", [
            ("common_straw_sleeping_pallet_loft", "Common Room Straw Mattresses on Timber Floor (2x2)", "Sàn Gác Lót Nệm Rơm Cho Khách Trọ (2x2)", [2, 2], "straw"),
            ("heavy_timber_four_tier_bunk_bed", "Double-Tier Heavy Timber Travelers Bunk Bed (2x1)", "Giường Tầng Bằng Gỗ Cho Khách Du Hành (2x1)", [2, 1], "wood"),
            ("cellar_barrel_racks_stone_vault", "Stone-Vaulted Cellar Beer Cask Racks (2x1)", "Kệ Thùng Rượu Dưới Hầm Đá Vòm (2x1)", [2, 1], "wood"),
            ("secret_cellar_smugglers_trapdoor", "Iron-Ring Secret Smugglers Floor Trapdoor (1x1)", "Cửa Sập Bí Mật Buôn Lậu Dưới Sàn (1x1)", [1, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat12_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "drink_ale" if "bar" in sub_id or "drinking" in sub_id else "inspect"
                if "lodging" in sub_id:
                    verb = "rest"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval inn, tavern and brewhouse facility ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 13. harbor_docks_and_river_trade (200 assets: 5 subcats * 40: 5*8)
    # =========================================================================
    cid = "harbor_docks_and_river_trade"
    cat13_subs = [
        ("wharf_quay_and_pier", [
            ("heavy_oak_wharf_piling_pier", "Heavy Timber Wharf Pier on Oak Pilings (3x2)", "Cầu Cảng Bằng Gỗ Sồi Cọc Trụ Lớn (3x2)", [3, 2], "wood"),
            ("ashlar_stone_quayside_wall", "Ashlar Stone Quayside Wall with Mooring Rings (2x1)", "Bờ Kè Cảng Bằng Đá Có Khuyên Buộc Tàu (2x1)", [2, 1], "stone"),
            ("wooden_gangplank_to_vessel", "Cleated Timber Boarding Gangplank (2x1)", "Cầu Ván Gỗ Bước Lên Thuyền (2x1)", [2, 1], "wood"),
            ("heavy_iron_mooring_bollard", "Cast-Iron Mushroom Mooring Bollard (1x1)", "Cột Bích Sắt Buộc Dây Neo Tàu (1x1)", [1, 1], "iron"),
            ("low_tide_muddy_quay_steps", "Algae-Slick Stone Quayside Water Steps (2x1)", "Bậc Thang Đá Lên Xuống Nước Bám Tảo (2x1)", [2, 1], "stone"),
        ]),
        ("trade_vessels_and_boats", [
            ("hanseatic_single_mast_cog", "Hanseatic Merchant Single-Mast Cog Ship (4x3)", "Thuyền Buôn Cog Một Cột Buồm Hanseatic (4x3)", [4, 3], "wood"),
            ("river_cargo_shallow_punt", "River Flat-Bottom Cargo Barge Punt (3x1)", "Thuyền Đáy Bằng Chở Hàng Đường Sông (3x1)", [3, 1], "wood"),
            ("fisherman_clinker_built_rowboat", "Clinker-Built Oak Rowing Fishing Boat (2x1)", "Thuyền Đánh Cá Gỗ Ghép Mộng (2x1)", [2, 1], "wood"),
            ("harbor_patrol_armed_skiff", "Harbor Guard Armed Longboat with Crossbows (3x1)", "Thuyền Canh Tuần Tra Bến Cảng Có Nỏ (3x1)", [3, 1], "wood"),
            ("moored_timber_houseboat_barge", "Moored Timber Houseboat Dwelling Barge (3x2)", "Thuyền Nhà Bằng Gỗ Neo Đậu Định Cư (3x2)", [3, 2], "wood"),
        ]),
        ("harbor_crane_and_cargo", [
            ("treadwheel_harbor_timber_crane", "Dual-Treadwheel Timber Wharf Lifting Crane (3x3)", "Cần Cẩu Cảng Bánh Xe Lồng Chân Đôi (3x3)", [3, 3], "wood"),
            ("rope_cargo_net_sling_crates", "Suspended Rope Cargo Net of Bundled Goods (2x1)", "Lưới Dây Thừng Treo Hàng Hóa (2x1)", [2, 1], "cloth"),
            ("tarred_canvas_waterproof_bales", "Stack of Tarred Canvas Covered Wool Bales (2x1)", "Kiện Len Bọc Vải Bạt Chống Nước (2x1)", [2, 1], "cloth"),
            ("coiled_hemp_mooring_hawsers", "Coiled Heavy Hemp Mooring Rope Hawsers (1x1)", "Cuộn Dây Thừng Gai Buộc Neo Lớn (1x1)", [1, 1], "plant"),
            ("block_and_tackle_shearlegs", "Shear-Leg Timber Lifting Tackle Derrick (2x1)", "Giàn Kéo Hàng Bằng Gỗ Có Ròng Rọc (2x1)", [2, 1], "wood"),
        ]),
        ("fish_market_and_saltery", [
            ("fish_gutting_blood_drain_bench", "Sloped Zinc-Topped Fish Gutting Trough (2x1)", "Bàn Mổ Cá Có Rãnh Thoát Máu (2x1)", [2, 1], "wood"),
            ("salted_herring_stacked_barrels", "Tiered Stack of Salted Herring Oak Barrels (2x1)", "Chồng Thùng Gỗ Sồi Muối Cá Trích (2x1)", [2, 1], "wood"),
            ("wind_drying_stockfish_pole_rack", "Hanging Wind-Drying Cod Stockfish Racks (2x2)", "Giàn Treo Phơi Khô Cá Tuyết Trong Gió (2x2)", [2, 2], "wood"),
            ("woven_willow_creel_oyster_baskets", "Woven Willow Lobster Creels & Oyster Pots (1x1)", "Lồng Đan Cây Liễu Bắt Tôm Cua & Hàu (1x1)", [1, 1], "wood"),
            ("salt_pan_crystallizing_pans", "Coastal Timber Brine Evaporation Flats (2x2)", "Ruộng Muối Khung Gỗ Bốc Hơi Ven Biển (2x2)", [2, 2], "wood"),
        ]),
        ("harbor_customs_and_beacon", [
            ("timber_harbor_customs_tollhouse", "Timber-Framed Customs Tollhouse Station (2x2)", "Trạm Thu Thuế Hải Quan Khung Gỗ (2x2)", [2, 2], "wood"),
            ("stone_harbor_breakwater_beacon", "Round Stone Breakwater Beacon Light Tower (2x2)", "Tháp Đèn Báo Hiệu Đê Chắn Sóng Bằng Đá (2x2)", [2, 2], "stone"),
            ("timber_wharf_safety_lifebuoys", "Cork and Canvas Ring Buoys on Dock Posts (1x1)", "Phao Cứu Sinh Bằng Vải Bạt & Vỏ Cây (1x1)", [1, 1], "cloth"),
            ("customs_cargo_iron_inspection_tongs", "Customs Weighing Scales & Testing Probes (1x1)", "Cân Hải Quan & Dụng Cụ Kiểm Tra Hàng (1x1)", [1, 1], "iron"),
            ("sea_wall_breakwater_granite_riprap", "Rough Granite Riprap Breakwater Arm (3x1)", "Đê Kè Đá Hoa Cương Chắn Sóng (3x1)", [3, 1], "stone"),
        ]),
    ]
    for sub_id, concepts in cat13_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "moor_vessel" if "vessel" in sub_id or "wharf" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval maritime trade and harbor facility ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 and fprint[1] >= 2 else "prop"
                ))

    # =========================================================================
    # 14. warfare_siege_and_camps (220 assets: 5 subcats * 44)
    # =========================================================================
    cid = "warfare_siege_and_camps"
    cat14_subs = [
        ("siege_engines", [
            ("counterweight_trebuchet_engine", "Massive Counterweight Timber Trebuchet (4x3)", "Máy Bắn Đá Đối Trọng Bằng Gỗ Khổng Lồ (4x3)", [4, 3], "wood"),
            ("wheeled_covered_battering_ram", "Covered Wheeled Battering Ram with Rawhide Roof (3x2)", "Xe Phá Thành Bằng Gỗ Bọc Da Trâu (3x2)", [3, 2], "wood"),
            ("heavy_skein_torsion_ballista", "Heavy Torsion Ballista on Wheeled Carriage (2x2)", "Máy Bắn Nỏ Ném Giáo Bánh Xe (2x2)", [2, 2], "wood"),
            ("traction_mangonel_rock_thrower", "Traction Rope-Pulled Mangonel Catapult (3x2)", "Máy Bắn Đá Kéo Dây Thừng (3x2)", [3, 2], "wood"),
        ]),
        ("field_fortifications", [
            ("spiked_chevaux_de_frise_barrier", "Spiked Timber Chevaux-de-Frise Cavalry Barrier (2x1)", "Rào Chông Ngựa Gỗ Chữ Thập Nhọn (2x1)", [2, 1], "wood"),
            ("curved_wicker_gabion_earthwork", "Earth-Filled Woven Wicker Gabion Basket (1x1)", "Sọt Đan Đựng Đất Chắn Tên Gabion (1x1)", [1, 1], "earth"),
            ("heavy_mantlet_pavise_arrow_shield", "Wheeled Timber Mantlet Pavise Arrow Screen (2x1)", "Tấm Khiên Gỗ Lớn Chắn Tên Có Bánh Xe (2x1)", [2, 1], "wood"),
            ("sharpened_caltrop_iron_hazard", "Scattered Four-Point Iron Caltrops Patch (1x1)", "Bãi Chông Sắt Bốn Chấu Chống Ngựa (1x1)", [1, 1], "iron"),
        ]),
        ("military_camp_and_tents", [
            ("conical_canvas_bell_tent", "Conical Canvas Soldiers Bell Pavilion Tent (2x2)", "Lều Vải Bạt Hình Chuông Binh Lính (2x2)", [2, 2], "cloth"),
            ("knights_heraldic_ridge_marquee", "Knight Commanders Striped Ridge Marquee Tent (3x2)", "Lều Chỉ Huy Có Mái Nhọn Sọc Màu (3x2)", [3, 2], "cloth"),
            ("camp_mess_cauldron_iron_tripod", "Iron Field Cooking Cauldron with Smoke Fire (1x1)", "Nồi Quân Nhu Nấu Bếp Dã Ngoại (1x1)", [1, 1], "iron"),
            ("stacked_polearms_weapon_pyramid", "Pyramid Stack of Halberds and Spears (1x1)", "Chồng Cây Thương & Kích Dựng Đứng (1x1)", [1, 1], "iron"),
        ]),
        ("battlefield_ruins_and_debris", [
            ("shattered_wagon_wheel_axle", "Smashed Supply Wagon Wheel and Broken Axle (2x1)", "Bánh Xe Tiếp Tế Gãy Trục Vỡ Vụn (2x1)", [2, 1], "wood"),
            ("cluster_stuck_crossbow_bolts", "Volley of Crossbow Bolts Embedded in Soil (1x1)", "Chùm Tên Nỏ Cắm Dày Đặc Dưới Đất (1x1)", [1, 1], "iron"),
            ("scorched_earth_fire_crater", "Firepot Scorched Earth Crater with Ash (2x2)", "Hố Đạn Cháy Đen Đầy Tro Tàn (2x2)", [2, 2], "earth"),
            ("abandoned_tattered_heraldic_pennon", "Mud-Splattered Torn Heraldic Pennon on Broken Spear (1x1)", "Cờ Hiệu Rách Bùn Cắm Trên Cán Thương Gãy (1x1)", [1, 1], "cloth"),
        ]),
        ("entrenchment_and_barricades", [
            ("spiked_revetment_siege_trench", "Deep Siege Approach Trench with Timber Revetment (2x1)", "Hào Tiến Công Đào Sâu Kè Gỗ (2x1)", [2, 1], "earth"),
            ("palisade_log_stockade_wall", "Pointed Split-Log Defensive Palisade Wall (2x1)", "Tường Rào Gỗ Cắm Nhọn Phòng Thủ (2x1)", [2, 1], "wood"),
            ("abatis_felled_tree_obstacle", "Sharpened Abatis Felled Tree Branch Obstacle (2x1)", "Cành Cây Đốn Ngã Vót Nhọn Chắn Lối (2x1)", [2, 1], "wood"),
            ("sandbag_and_sod_revetment_breastwork", "Sod Turf & Sandbag Parapet Breastwork (2x1)", "Bờ Lũy Đất Đắp Chắn Tên Bằng Bao Cát (2x1)", [2, 1], "earth"),
        ]),
    ]
    for sub_id, concepts in cat14_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_11:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "fire_engine" if "engine" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval warfare and siege fixture ({c_name}).", True, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 else "prop"
                ))

    # =========================================================================
    # 15. knighthood_tournament_and_armory (160 assets: 5 subcats * 32)
    # =========================================================================
    cid = "knighthood_tournament_and_armory"
    cat15_subs = [
        ("tournament_lists_and_barrier", [
            ("cloth_draped_tilt_barrier", "Cloth-Draped Timber Jousting Tilt Barrier (3x1)", "Rào Chắn Đấu Thương Bọc Vải Màu (3x1)", [3, 1], "wood"),
            ("herald_trumpet_stand_platform", "Trumpeters Elevated Fanfare Platform (2x1)", "Bục Kèn Đồng Hiệu Lệnh Trận Đấu (2x1)", [2, 1], "wood"),
            ("tournament_entrance_heraldic_portal", "Heraldic Crested Jousting Arena Entrance Portal (2x1)", "Cổng Đấu Trường Có Phù Hiệu (2x1)", [2, 1], "wood"),
            ("lance_rack_rest_barrier", "Timber Jousting Lance Rest & Replacement Stand (2x1)", "Giá Đỡ Thương Dự Phòng Sân Đấu (2x1)", [2, 1], "wood"),
        ]),
        ("royal_viewing_stand", [
            ("velvet_draped_royal_box", "Velvet-Canopied Royal Spectators Box (3x2)", "Khán Đài Danh Dự Hoàng Gia Màn Nhung (3x2)", [3, 2], "cloth"),
            ("ladies_courtly_viewing_gallery", "Carved Timber Ladies Gallery with Cushions (3x1)", "Khán Đài Phụ Nữ Quý Tộc Đệm Nhung (3x1)", [3, 1], "wood"),
            ("judges_marshall_raised_dais", "Tournament Marshall Scored Judgment Dais (2x1)", "Bục Trọng Tài Chấm Điểm Đấu Thương (2x1)", [2, 1], "wood"),
            ("coronation_prize_display_table", "Silver Laurel & Gold Purse Prize Table (2x1)", "Bàn Trao Giải Thưởng Vòng Nguyệt Quế (2x1)", [2, 1], "wood"),
        ]),
        ("training_and_quintain", [
            ("rotating_timber_shield_quintain", "Rotating Quintain Dummy with Shield and Sandbag (1x1)", "Bù Nhìn Xoay Đấu Thương Có Bao Cát (1x1)", [1, 1], "wood"),
            ("straw_stuffed_archery_butts", "Straw Butt Target with Painted Bullseye (1x1)", "Bia Rơm Bắn Cung Có Vòng Tròn Đỏ (1x1)", [1, 1], "straw"),
            ("wooden_sword_pell_post", "Upright Oak Pell Post for Sword Striking (1x1)", "Cột Gỗ Luyện Kiếm Pell (1x1)", [1, 1], "wood"),
            ("foot_combat_wooden_ring_barrier", "Melee Training Sand Pit with Timber Ring (2x2)", "Vòng Gỗ Sàn Cát Luyện Đấu Kiếm (2x2)", [2, 2], "wood"),
        ]),
        ("armory_and_weapon_racks", [
            ("full_plate_armor_display_stand", "Complete Suit of Polished Plate Armor on Stand (1x1)", "Bộ Áo Giáp Tấm Đánh Bóng Trên Giá (1x1)", [1, 1], "iron"),
            ("longsword_and_scabbard_rack", "Wall Rack of Broadswords and Bastard Swords (2x1)", "Giá Treo Kiếm Dài & Bao Da (2x1)", [2, 1], "iron"),
            ("heater_and_kite_shield_display", "Display of Painted Kite and Heater Shields (2x1)", "Giá Trưng Bày Khiên Hình Giọt Nước (2x1)", [2, 1], "wood"),
            ("chainmail_cleaning_barrel_rotator", "Revolving Sand Barrel for Polishing Mail (1x1)", "Thùng Cát Quay Đánh Bóng Áo Giáp Xích (1x1)", [1, 1], "wood"),
        ]),
        ("knight_pavilion_and_livery", [
            ("two_pole_heraldic_valance_tent", "Double-Pole Conical Knight Pavilion with Valance (3x2)", "Lều Hiệp Sĩ Hai Cột Có Rèm Viền (3x2)", [3, 2], "cloth"),
            ("caparisoned_destrier_grooming_stall", "Warhorse Grooming Stall with Armored Barding (2x2)", "Chuồng Chăm Sóc Chiến Mã Bọc Giáp (2x2)", [2, 2], "wood"),
            ("squire_armor_polishing_bench", "Squires Armor Burnishing Bench with Oil and Emery (2x1)", "Bàn Đánh Bóng Giáp Của Hầu Cận (2x1)", [2, 1], "wood"),
            ("tournament_shield_tree_post", "Heraldic Shield Tree for Challenging Knights (1x1)", "Cột Treo Khiên Thách Đấu Hiệp Sĩ (1x1)", [1, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat15_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "charge_quintain" if "training" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Chivalric tournament and knightly facility ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 and fprint[1] >= 2 else "prop"
                ))

    return items
