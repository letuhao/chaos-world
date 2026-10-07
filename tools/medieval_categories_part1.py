# -*- coding: utf-8 -*-
"""Medieval Western Categories Part 1 (Categories 1 - 7: 2,130 assets)."""

from __future__ import annotations

def generate_part1(make_asset) -> list[dict]:
    items: list[dict] = []

    # =========================================================================
    # 1. terrain_and_ground_cover (220 assets: 5 subcats * 44)
    # =========================================================================
    cid = "terrain_and_ground_cover"
    cat1_subs = [
        ("cobblestone_and_pavement", [
            ("square_sett", "Square Basalt Sett Pavement", "Đá Lát Quảng Trường Vuông", "stone"),
            ("river_round_cobble", "River Pebble Cobblestone", "Đá Cuội Tròn Lát Đường", "stone"),
            ("worn_church_flagstone", "Cathedral Plaza Flagstone", "Phiến Đá Lát Sân Giáo Đường", "stone"),
            ("irregular_slate_paving", "Irregular Slate Paving", "Đá Phiến Tự Nhiên Lát Lối Đi", "stone"),
        ]),
        ("dirt_loam_and_mud", [
            ("churned_cart_loam", "Churned Cart-Rut Loam", "Đất Thịt Lún Vết Bánh Xe", "earth"),
            ("black_manure_soil", "Rich Manured Farmland Dirt", "Đất Nông Trại Trộn Phân", "earth"),
            ("dry_cracked_clay", "Sun-Baked Cracked Clay Dirt", "Đất Sét Khô Nứt Nẻ", "earth"),
            ("deep_sticky_quagmire", "Heavy Rain Sticky Quagmire", "Bãi Lầy Đất Bùn Quánh", "earth"),
        ]),
        ("meadow_turf_and_pasture", [
            ("clover_manor_lawn", "English Clover Manor Turf", "Thảm Cỏ Xanh Ba Lá Điền Trang", "plant"),
            ("grazed_sheep_pasture", "Short-Grazed Sheep Pasture", "Đồng Cỏ Chăn Cừu Xén Ngắn", "plant"),
            ("autumn_leaf_turf", "Autumn Beech Leaf Carpet", "Thảm Cỏ Phủ Lá Cây Dẻ Gai Vàng", "plant"),
            ("flowering_oxeye_meadow", "Flowering Wildflower Meadow", "Đồng Cỏ Nở Hoa Dại", "plant"),
        ]),
        ("gravel_scree_and_quarry", [
            ("river_gravel_patch", "Riverbank Washed Gravel", "Bãi Sỏi Lòng Sông Rửa Sạch", "stone"),
            ("chalk_quarry_rubble", "Crushed White Chalk Rubble", "Đá Vôi Trắng Nghiền Vụn", "stone"),
            ("slate_shingle_scree", "Blue Slate Quarry Shingle", "Mảnh Đá Phiến Xanh Vỡ Vụn", "stone"),
            ("ironstone_gravel_track", "Iron-Stained Red Gravel", "Sỏi Nâu Đỏ Quặng Sắt", "stone"),
        ]),
        ("peat_mire_and_bog", [
            ("spongy_sphagnum_bog", "Spongy Sphagnum Peat Bog", "Đầm Lầy Than Bùn Rêu Ẩm", "earth"),
            ("dark_fen_sludge", "Dark Stagnant Fen Sludge", "Bùn Đầm Đen Đọng Nước Chua", "earth"),
            ("heather_peat_turf", "Highland Heather Peat Turf", "Mặt Đất Than Bùn Cây Thạch Nam", "earth"),
            ("sedge_mire_hummock", "Waterlogged Sedge Grass Hummock", "Gò Cỏ Cói Ngập Nước Chua", "plant"),
        ]),
    ]
    variants_11 = [
        ("raw_pristine", "Clean", "Nguyên Bản", "norman", "fresh even texture"),
        ("wet_rain", "Rain-Soaked", "Ngấm Mưa Ẩm Ướt", "norman", "glistening damp surface with dark puddles"),
        ("rutted_wagon", "Deep Wagon Rutted", "Hằn Vết Bánh Xe Nặng", "anglo_saxon", "parallel heavy iron wagon ruts"),
        ("mossy_overgrown", "Moss-Overgrown", "Phủ Rêu Xanh", "celtic", "lush green velvet moss patches"),
        ("frost_rimed", "Morning Frost Rimed", "Phủ Sương Muối Sáng Sớm", "germanic_holy_roman", "crisp pale frost dusting on edges"),
        ("autumn_leaves", "Fallen Leaf Strewn", "Rơi Rụng Lá Thu", "french_capetian", "scattered golden and russet oak leaves"),
        ("trodden_busy", "Heavy Foot-Trodden", "Bị Dẫm Đạp Dày Đặc", "flemish", "worn smooth by boots and draft beasts"),
        ("cracked_weathered", "Weather-Cracked", "Nứt Nẻ Thời Tiết", "universal_feudal", "surface hairline fractures and fissures"),
        ("patchwork_repaired", "Roughly Repaired", "Vá Dặm Chắp Vá", "universal_feudal", "mismatched filler material repairs"),
        ("mud_splattered", "Mud-Splattered", "Bắn Đầy Bùn Đất", "anglo_saxon", "clods of splattered clay and soil"),
        ("fallow_weed", "Fallow Weed-Choked", "Mọc Đầy Cỏ Dại", "universal_feudal", "invaded by thistles, dandelions and plantain"),
    ]

    for sub_id, concepts in cat1_subs:
        for c_slug, c_name, c_vn, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_11:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down seamless terrain texture of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, authentic European medieval texture, ink contours."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, [1, 1], "walk_surface", False, "transparent",
                    "step_on", f"Walkable medieval ground layer ({c_name}).", False, mat, cult, prompt,
                    asset_type="terrain_texture", alpha="opaque", pivot="center"
                ))

    # =========================================================================
    # 2. roads_bridges_and_crossings (160 assets: 5 subcats * 32)
    # =========================================================================
    cid = "roads_bridges_and_crossings"
    cat2_subs = [
        ("paved_royal_highway", [
            ("roman_via_straight", "Paved Roman Military Highway Segment", "Đoạn Đường Quân Sự La Mã", [2, 1], "stone", "walk_surface"),
            ("curbed_town_high_street", "Town High Street Paved Avenue", "Đại Lộ Đá Lát Phố Chính", [2, 1], "stone", "walk_surface"),
            ("royal_post_milestone", "Carved Royal Road Milestone Stele", "Cột Mốc Đo Dặm Hoàng Gia", [1, 1], "stone", "solid"),
            ("toll_barrier_turnpike", "Highway Timber Toll Barrier Gate", "Trạm Barie Thu Phí Bằng Gỗ", [2, 1], "wood", "solid"),
        ]),
        ("rutted_country_track", [
            ("sunken_lane_holloway", "Sunken Earth Holloway Track", "Đường Mòn Đất Trũng Lòng Chảo", [2, 1], "earth", "walk_surface"),
            ("hedgerow_country_lane", "Hedgerow-Bordered Cart Track", "Đường Đồng Cỏ Viền Hàng Rào Cây", [2, 1], "earth", "walk_surface"),
            ("winding_forest_packhorse_path", "Winding Packhorse Dirt Trail", "Đường Mòn Ngựa Thồ Rừng Rậm", [2, 1], "earth", "walk_surface"),
            ("muddy_field_junction", "Muddy Country Road Three-Way Fork", "Ngã Ba Đường Đất Đồng Quê Lầy Lội", [2, 2], "earth", "walk_surface"),
        ]),
        ("stone_arched_bridge", [
            ("norman_barrel_arch_span", "Norman Barrel-Arch Stone Bridge Span", "Nhịp Cầu Vòm Đá Kiểu Norman", [2, 2], "stone", "solid"),
            ("gothic_pointed_arch_bridge", "Gothic Pointed Arch Stone River Bridge", "Cầu Đá Vòm Nhọn Gothic", [3, 2], "stone", "solid"),
            ("fortified_bridge_gatehouse", "Fortified Bridge Defensive Gate Tower", "Tháp Canh Cổng Cầu Kiên Cố", [2, 2], "stone", "solid"),
            ("bridge_cutwater_pier", "V-Shaped Stone Bridge Cutwater Pier", "Trụ Cầu Mũi Rẽ Nước Bằng Đá", [1, 2], "stone", "solid"),
        ]),
        ("wooden_trestle_bridge", [
            ("heavy_oxcart_trestle_span", "Heavy Timber Oxcart Trestle Bridge", "Cầu Giàn Gỗ Tải Trọng Nặng Xe Bò", [2, 1], "wood", "solid"),
            ("rustic_log_footbridge", "Rustic Peeled Log Stream Footbridge", "Cầu Thân Gỗ Suối Nhỏ Mộc Mạc", [2, 1], "wood", "walk_surface"),
            ("timber_drawbridge_span", "Winch-Lifted Timber Drawbridge Span", "Nhịp Cầu Rút Bằng Gỗ Kéo Tay", [2, 2], "wood", "solid"),
            ("swamp_duckboard_walkway", "Marsh Timber Duckboard Raised Walkway", "Lối Đi Ván Gỗ Kê Cao Đầm Lầy", [2, 1], "wood", "walk_surface"),
        ]),
        ("river_ford_and_crossing", [
            ("granite_stepping_stones", "Granite Boulder River Stepping Stones", "Bậc Đá Băng Qua Lòng Suối", [2, 1], "stone", "walk_surface"),
            ("shallow_gravel_cart_ford", "Shallow River Gravel Wagon Ford", "Bến Lội Sỏi Cạn Cho Xe Ngựa", [2, 2], "water", "walk_surface"),
            ("cable_ferry_dock_landing", "River Cable Ferry Wooden Landing Pier", "Bến Đỗ Phà Kéo Dây Cáp Đường Sông", [2, 1], "wood", "solid"),
            ("wicker_fascine_crossing", "Brushwood Fascine Mud Causeway", "Lối Băng Bùn Bằng Bó Củi Cành Rào", [2, 1], "wood", "walk_surface"),
        ]),
    ]
    variants_8 = [
        ("norman_sturdy", "Norman Sturdy", "Kiểu Norman Chắc Chắn", "norman", "massive square-cut ashlar and heavy timbers"),
        ("weathered_aged", "Time-Weathered", "Dãi Dầu Thời Gian", "anglo_saxon", "softened edges, worn wheel tracks and lichen"),
        ("mossy_overgrown", "Mossy River", "Phủ Rêu Sông Nước", "celtic", "damp green moss coating lower timbers and waterlines"),
        ("royal_reinforced", "Royal Crown-Maintained", "Hoàng Gia Gia Cố Bảo Trì", "french_capetian", "reinforced iron strapping and royal surveyor stone stamps"),
        ("rustic_serf_built", "Rustic Peasant-Built", "Dân Làng Đốn Dựng", "universal_feudal", "coarse unhewn timber poles and rough drystone"),
        ("flood_strained", "Flood-Battered", "Chống Chọi Lũ Lụt", "flemish", "water-borne driftwood debris lodged against supports"),
        ("autumn_bordered", "Autumn Foliage-Lined", "Viền Lá Thu Rơi", "germanic_holy_roman", "bordered by dry fallen leaves and golden fern fronds"),
        ("iron_bracketed", "Iron-Bolted Heavy", "Bắt Vít Bát Sắt Nặng", "norman", "prominent black wrought-iron strapping and rivets"),
    ]

    for sub_id, concepts in cat2_subs:
        for c_slug, c_name, c_vn, fprint, mat, col in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_8:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "cross_bridge" if "bridge" in sub_id or "ford" in sub_id else "walk_along"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, col, col == "solid", "transparent",
                    verb, f"Road and water crossing waypoint ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 3. modular_castle_and_fortification (480 assets: 6 subcats * 80)
    # =========================================================================
    cid = "modular_castle_and_fortification"
    cat3_subs = [
        ("curtain_wall_and_rampart", [
            ("straight_curtain_wall_1x1", "Ashlar Curtain Wall Segment (1x1)", "Tường Thành Đá Vuông (1x1)", [1, 1], "solid"),
            ("straight_curtain_wall_2x1", "Ashlar Curtain Wall Long Bay (2x1)", "Đoạn Dài Tường Thành Đá (2x1)", [2, 1], "solid"),
            ("battered_sloped_wall_base", "Sloped Talus Curtain Wall Base (1x1)", "Chân Thành Vát Dốc Chống Đào Hầm (1x1)", [1, 1], "solid"),
            ("corner_angle_curtain_wall", "Ninety-Degree Angle Wall Corner (1x1)", "Góc Vuông Tường Thành (1x1)", [1, 1], "solid"),
            ("internal_wallwalk_corridor", "Rampart Timber Walkway Allure (2x1)", "Hành Lang Gỗ Đi Tuần Lưng Thành (2x1)", [2, 1], "solid"),
            ("buttressed_curtain_wall", "Buttress-Reinforced Heavy Wall (1x1)", "Tường Thành Có Cột Chống Chịu Lực (1x1)", [1, 1], "solid"),
            ("curtain_wall_sally_port", "Wall Footing Iron Sally Port Door (1x1)", "Cửa Xuất Kích Bí Mật Dưới Chân Thành (1x1)", [1, 1], "solid"),
            ("wall_drain_gargoyle_section", "Wall Parapet Drainage Chute (1x1)", "Máng Thoát Nước Rãnh Đi Tuần (1x1)", [1, 1], "solid"),
        ]),
        ("crenellation_and_hoarding", [
            ("crenel_merlon_battlements_1x1", "Stone Crenel and Merlon Crest (1x1)", "Lỗ Châu Mai & Bờ Thành Đá (1x1)", [1, 1], "solid"),
            ("crenel_merlon_battlements_2x1", "Stone Crenel Parapet Bay (2x1)", "Dải Lỗ Châu Mai Tường Thành (2x1)", [2, 1], "solid"),
            ("machicolation_corbelled_gallery", "Machicolation Overhanging Gallery (2x1)", "Lỗ Thả Đá Nhô Ra Khỏi Thành (2x1)", [2, 1], "solid"),
            ("wooden_hoarding_fighting_box", "Covered Wooden Hoarding Combat Gallery (2x1)", "Lầu Gỗ Nhô Phòng Thủ Bắn Cung (2x1)", [2, 1], "solid"),
            ("crenel_wooden_swinging_shutter", "Battlement Timber Pivot Arrow Shutter (1x1)", "Cánh Cửa Gỗ Chắn Tên Lỗ Châu Mai (1x1)", [1, 1], "solid"),
            ("corner_gargoyle_machicolation", "Corner Bastion Overhang Murder Spout (1x1)", "Lỗ Thả Dầu Sôi Góc Lâu Đài (1x1)", [1, 1], "solid"),
            ("hoarding_timber_support_brace", "Projecting Timber Hoarding Struts (1x1)", "Thanh Chống Gỗ Đỡ Lầu Bắn Tên (1x1)", [1, 1], "solid"),
            ("crenellation_shield_notch", "Arrow-Rest Crenellation Parapet (1x1)", "Bờ Thành Đá Có Rãnh Tựa Nỏ (1x1)", [1, 1], "solid"),
        ]),
        ("tower_bastion_and_turret", [
            ("round_drum_flanking_tower", "Round Stone Drum Flanking Tower (2x2)", "Tháp Tròn Canh Gác Khống Chế Góc (2x2)", [2, 2], "solid"),
            ("square_norman_mural_tower", "Square Norman Mural Tower (2x2)", "Tháp Vuông Kiểu Norman (2x2)", [2, 2], "solid"),
            ("d_shaped_curtain_bastion", "D-Shaped Projecting Curtain Bastion (2x2)", "Pháo Đài Bán Nguyệt Chữ D (2x2)", [2, 2], "solid"),
            ("corner_corbelled_bartizan", "Corbelled Hanging Corner Bartizan Turret (1x1)", "Chòi Canh Treo Lơ Lửng Góc Tường (1x1)", [1, 1], "solid"),
            ("tower_conical_slate_roof", "Conical Slate Roof Tower Cap (2x2)", "Chóp Mái Nón Lợp Đá Phiến Cho Tháp (2x2)", [2, 2], "solid"),
            ("tower_open_gorge_rear_wall", "Open-Gorge Inner Tower Platform (2x2)", "Sàn Tháp Mở Hướng Vào Trong Thành (2x2)", [2, 2], "solid"),
            ("watch_beacon_brazier_turret", "Signal Fire Beacon Basket Turret (1x1)", "Chòi Đốt Lửa Hiệu Báo Động (1x1)", [1, 1], "solid"),
            ("octagonal_high_spire_turret", "Octagonal Castle Lookout Spire (2x2)", "Tháp Nhọn Bát Giác Quan Sát Đỉnh Cao (2x2)", [2, 2], "solid"),
        ]),
        ("gatehouse_and_barbican", [
            ("twin_drum_gatehouse_entrance", "Twin-Towered Main Castle Gatehouse (3x2)", "Cổng Thành Kép Hai Tháp Canh (3x2)", [3, 2], "solid"),
            ("iron_banded_oak_portcullis", "Iron-Spiked Dropping Oak Portcullis (2x1)", "Cửa Sắt Kéo Thả Có Răng Nhọn (2x1)", [2, 1], "solid"),
            ("heavy_studded_double_gates", "Massive Iron-Studded Oak Double Doors (2x1)", "Cửa Gỗ Sồi Hai Cánh Bọc Đinh Tán (2x1)", [2, 1], "solid"),
            ("outer_barbican_walled_entry", "Outer Barbican Choke Point Enclosure (3x2)", "Tiền Đồn Đỡ Cổng Barbican (3x2)", [3, 2], "solid"),
            ("drawbridge_timber_ram", "Counterweight Raising Drawbridge (2x2)", "Cầu Kéo Bằng Gỗ Có Đối Trọng (2x2)", [2, 2], "solid"),
            ("drawbridge_pivot_chains_frame", "Overhead Drawbridge Iron Winding Chains (2x1)", "Xích Sắt Và Ròng Rọc Kéo Cầu (2x1)", [2, 1], "solid"),
            ("gatehouse_murder_hole_vault", "Inner Gatehouse Murder Hole Vault (2x1)", "Mái Vòm Lỗ Sát Thủ Thả Dầu Sôi (2x1)", [2, 1], "solid"),
            ("postern_gate_wicket_door", "Pedestrian Wicket Postern Sub-Gate (1x1)", "Cửa Nách Đi Bộ Cạnh Cổng Chính (1x1)", [1, 1], "solid"),
        ]),
        ("moat_ditch_and_earthwork", [
            ("water_filled_moat_section", "Water-Filled Defensive Moat Channel (2x1)", "Hào Nước Sâu Phòng Thủ (2x1)", [2, 1], "solid"),
            ("sloping_escarp_stone_bank", "Sloping Stone-Reveted Escarp Bank (2x1)", "Bờ Vách Dốc Kè Đá Hào Thành (2x1)", [2, 1], "solid"),
            ("counterscarp_earth_berm", "Outer Counterscarp Earth Glacis Berm (2x1)", "Gờ Đất Chắn Bên Ngoài Hào (2x1)", [2, 1], "solid"),
            ("submerged_punji_stake_row", "Submerged Sharpened Oak Stakes Row (2x1)", "Hàng Cọc Gỗ Vót Nhọn Dưới Lòng Hào (2x1)", [2, 1], "solid"),
            ("dry_ditch_cheval_de_frise", "Dry Moat Spiked Timber Obstacle (2x1)", "Rào Chông Gỗ Chữ Thập Đáy Hào Khô (2x1)", [2, 1], "solid"),
            ("moat_culvert_sluice_grate", "Moat Water Inflow Sluice Iron Grate (1x1)", "Chấn Song Sắt Cống Nạp Nước Hào (1x1)", [1, 1], "solid"),
            ("earthen_rampart_berm", "Steep Rammed Chalk Glacis Berm (2x1)", "Bờ Lũy Đất Vôi Nén Dốc Đứng (2x1)", [2, 1], "solid"),
            ("moat_wooden_service_wharf", "Moat Maintenance Boat Dock Landing (2x1)", "Bến Thuyền Nhỏ Vớt Rác Lòng Hào (2x1)", [2, 1], "solid"),
        ]),
        ("arrow_slit_and_stairs", [
            ("cross_cruciform_arrow_slit", "Cruciform Cross Bowyer Arrow Slit (1x1)", "Lỗ Châu Mai Hình Chữ Thập (1x1)", [1, 1], "solid"),
            ("plunging_oillet_slit", "Plunging Oillet Crossbow Arrow Slit (1x1)", "Lỗ Bắn Nỏ Tròn Góc Cúi Thấp (1x1)", [1, 1], "solid"),
            ("spiral_newel_stone_staircase", "Spiral Stone Tower Staircase (2x2)", "Cầu Thang Đá Xoắn Ốc Trong Tháp (2x2)", [2, 2], "solid"),
            ("straight_rampart_stone_steps", "Straight Stone Rampart Access Steps (2x1)", "Bậc Thang Đá Lên Mặt Bờ Thành (2x1)", [2, 1], "solid"),
            ("arched_intramural_doorway", "Pointed Arched Intramural Stone Portal (1x1)", "Cửa Vòm Nhọn Lối Đi Trong Tường (1x1)", [1, 1], "solid"),
            ("corbelled_stone_bracket_pair", "Corbelled Heavy Stone Support Brackets (1x1)", "Cặp Trụ Đá Nhô Đỡ Sàn Đi Tuần (1x1)", [1, 1], "solid"),
            ("parapet_drain_scupper_hole", "Parapet Drainage Scupper Waterway (1x1)", "Lỗ Thoát Nước Mưa Mặt Thành (1x1)", [1, 1], "solid"),
            ("wall_archers_firing_bench", "Wall Archer Firing Step Wooden Bench (1x1)", "Bục Gỗ Kê Chân Cho Cung Thủ Bắn (1x1)", [1, 1], "solid"),
        ]),
    ]
    variants_10 = [
        ("norman_chisel", "Norman Chiseled Ashlar", "Đá Đẽo Kiểu Norman", "norman", "heavy limestone ashlar with tight lime mortar joints"),
        ("weathered_mossy", "Ancient Weathered Mossy", "Rêu Phong Cổ Kính", "celtic", "gray damp limestone coated in green moss and lichens"),
        ("siege_scarred", "Trebuchet-Damaged Scarred", "Vết Nứt Đạn Đá Công Thành", "universal_feudal", "cracked masonry, impact chips, and emergency timber bracing"),
        ("royal_capetian", "Capetian Royal Limestone", "Đá Hoàng Triều Capetian", "french_capetian", "creamy Caen stone with clean gothic lines"),
        ("germanic_staufen", "Holy Roman Imperial Rusticated", "Đá Nhám Hoàng Đế La Mã Thần Thánh", "germanic_holy_roman", "bossed rusticated stone blocks with high structural mass"),
        ("flemish_brickwork", "Flemish Red-Brick Reinforced", "Gạch Đỏ Vùng Flanders Gia Cố", "flemish", "deep red clinker bricks mixed with limestone quoins"),
        ("anglo_sandstone", "Red Sandstone Fortified", "Đá Sa Thạch Đỏ Kiên Cố", "anglo_saxon", "warm reddish sandstone blocks showing tool dressing marks"),
        ("iron_reinforced", "Iron-Plated Reinforced", "Bọc Bản Sắt Gia Cố", "norman", "wrought-iron tie plates and heavy reinforcing anchor bolts"),
        ("dark_basalt", "Dark Basalt Mountain", "Đá Núi Lửa Đen Sẫm", "universal_feudal", "somber charcoal volcanic stone blocks impervious to fire"),
        ("crenellated_heraldic", "Heraldic Pennant-Draped", "Treo Cờ Hiệu Quý Tộc", "french_capetian", "flying bright red and gold heraldic swallowtail banners"),
    ]

    for sub_id, concepts in cat3_subs:
        for c_slug, c_name, c_vn, fprint, col in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_10:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, dark ink contours, transparent background."
                )
                verb = "climb_stairs" if "stairs" in c_slug or "steps" in c_slug else "inspect_wall"
                if "gate" in c_slug or "portcullis" in c_slug:
                    verb = "open_gate"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, col, True, "solid",
                    verb, f"Modular stone castle component ({c_name}).", False, "stone", cult, prompt,
                    asset_type="structure"
                ))

    # =========================================================================
    # 4. keep_palace_and_royal_court (260 assets: 4 subcats * 45 + 2 subcats * 40)
    # =========================================================================
    cid = "keep_palace_and_royal_court"
    cat4_subs_45 = [
        ("throne_dais_and_court", [
            ("high_backed_carved_throne", "Carved Oak High-Backed Royal Throne", "Ngai Vàng Gỗ Sồi Chạm Khắc", [1, 1], "wood"),
            ("carpeted_three_step_dais", "Crimson-Carpeted Three-Step Throne Dais", "Bục Ngai Vàng Ba Cấp Trải Thảm Đỏ", [2, 2], "cloth"),
            ("velvet_heraldic_canopy", "Fringed Velvet Throne Overhang Canopy", "Màn Trướng Nhung Treo Trên Ngai Vàng", [2, 1], "cloth"),
            ("chancellors_privy_bench", "Carved Privy Council Walnut Bench", "Ghế Dài Hội Đồng Cơ Mật", [2, 1], "wood"),
            ("gilded_fleur_de_lis_pedestal", "Gilded Royal Scepter Display Pedestal", "Bệ Trưng Bày Vương Trượng Mạ Vàng", [1, 1], "stone"),
        ]),
        ("great_hall_feasting", [
            ("lords_feasting_trestle_table", "Long Heavy Oak Feasting Trestle Table", "Bàn Tiệc Gỗ Sồi Chân Chữ X Dài", [3, 1], "wood"),
            ("knights_high_backed_bench", "High-Backed Dining Hall Timber Bench", "Ghế Dài Tựa Cao Phòng Đại Yến", [2, 1], "wood"),
            ("wrought_iron_candle_chandelier", "Ring Wrought-Iron Beeswax Chandelier", "Đèn Chùm Sắt Tròn Thắp Nến Sáp Ong", [2, 2], "iron"),
            ("silver_ewers_feasting_sideboard", "Carved Oak Display Cupboard (Dresser)", "Tủ Kệ Trưng Bày Bình Bạc Đại Sảnh", [2, 1], "wood"),
            ("minstrels_balcony_parapet", "Minstrels' Overhanging Timber Gallery", "Ban Công Nhạc Công Bằng Gỗ Đại Sảnh", [3, 1], "wood"),
        ]),
        ("fireplace_and_chimney", [
            ("monumental_carved_hearth", "Monumental Carved Stone Great Hearth", "Lò Sưởi Đá Đại Điện Lâu Đài", [3, 2], "stone"),
            ("iron_fireback_heraldic_plate", "Cast-Iron Heraldic Beast Fireback Plate", "Tấm Chắn Lưng Lò Sưởi Bằng Gang Đúc", [1, 1], "iron"),
            ("hearth_spit_and_firedogs", "Wrought-Iron Hearth Andirons with Roasting Spit", "Chạc Đỡ Củi & Trục Quay Thịt Bằng Sắt", [2, 1], "iron"),
            ("stacked_ash_cordwood_pile", "Neat Stacked Ash & Oak Hearth Firewood", "Chồng Củi Gỗ Dẻ Lò Sưởi Xếp Ngăn Nắp", [2, 1], "wood"),
            ("sculpted_limestone_chimney_breast", "Sculpted Chimney Flue with Coats of Arms", "Chóp Ống Khói Đá Điêu Khắc Gia Huy", [2, 2], "stone"),
        ]),
        ("royal_bedchamber", [
            ("four_poster_oak_canopy_bed", "Four-Poster Oak Bed with Velvet Curtains", "Giường Cọc Bốn Góc Gỗ Sồi Rèm Nhung", [2, 2], "wood"),
            ("carved_linen_storage_cassone", "Carved Walnut Dowry Chest (Cassone)", "Rương Gỗ Óc Chó Chạm Khắc Đựng Khăn", [2, 1], "wood"),
            ("gilded_prie_dieu_kneeler", "Gilded Devotional Prayer Kneeler (Prie-Dieu)", "Bàn Quỳ Cầu Nguyện Bằng Gỗ Mạ Vàng", [1, 1], "wood"),
            ("brass_pan_long_bedwarmer", "Perforated Brass Bedwarming Pan with Long Handle", "Chảo Đồng Sưởi Giường Cán Dài", [1, 1], "brass"),
            ("noble_privy_closet_wardrobe", "Wardrobe Armoire with Iron Strap Hinges", "Tủ Quần Áo Quý Tộc Có Bản Lề Sắt", [2, 1], "wood"),
        ]),
    ]
    variants_9 = [
        ("norman_ducal", "Norman Ducal", "Công Tước Norman", "norman", "robust heavy oak with deep geometric relief carvings"),
        ("capetian_royal", "Capetian French Royal", "Hoàng Triều Capetian Pháp", "french_capetian", "fleur-de-lis motifs, ultramarine velvet and gold leaf accents"),
        ("staufen_imperial", "Holy Roman Imperial", "Đế Chế La Mã Thần Thánh", "germanic_holy_roman", "double-headed eagle escutcheons and dark burnished ironwork"),
        ("flemish_gothic", "Flemish High Gothic", "Gothic Vùng Flanders", "flemish", "intricate openwork tracery and rich scarlet damask"),
        ("plantagenet_lion", "Plantagenet Lion", "Sư Tử Plantagenet", "anglo_saxon", "carved heraldic leopards, quarters of gold and gules"),
        ("burgundian_court", "Burgundian Courtly", "Triều Đình Burgundy", "french_capetian", "luxurious black-and-gold brocade with polished walnut"),
        ("celtic_highland", "Celtic Chieftain", "Thủ Lĩnh Xứ Celt", "celtic", "interlace knotwork carvings and tartan woolen throws"),
        ("weathered_relic", "Aged Dynastic Heirlooms", "Gia Truyền Niên Đại", "universal_feudal", "softened beeswax patina and century-old battle scratches"),
        ("ceremonial_gilt", "Ceremonial Gilt", "Nghi Lễ Mạ Vàng", "universal_feudal", "gleaming gold-leaf highlights and polished brass fittings"),
    ]

    for sub_id, concepts in cat4_subs_45:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_9:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "sit_on_throne" if "throne" in c_slug else "inspect"
                if "bed" in c_slug:
                    verb = "rest"
                elif "table" in c_slug:
                    verb = "feast_at_table"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Castle keep interior furnishing ({c_name}).", False, mat, cult, prompt
                ))

    # Cat 4 remaining 2 subcats * 40 assets = 80 assets
    cat4_subs_40 = [
        ("tapestry_and_heraldry", [
            ("bayeux_style_narrative_tapestry", "Woven Wool Narrative Chronicle Tapestry (3x1)", "Thảm Dệt Kể Chuyện Lịch Sử (3x1)", [3, 1], "cloth"),
            ("unicorn_hunt_millefleur_hanging", "Millefleur Garden Unicorn Wall Hanging (2x1)", "Thảm Dệt Kỳ Lân Nền Hoa Ngàn Sắc (2x1)", [2, 1], "cloth"),
            ("heraldic_shield_mantling_display", "Carved Wooden Coat of Arms with Mantling (1x1)", "Khiên Gia Huy Điêu Khắc Có Dải Lụa (1x1)", [1, 1], "wood"),
            ("tournament_victory_pennant_stand", "Silk Tournament Victory Guidon Banner (1x1)", "Cờ Lụa Chiến Thắng Đấu Thương (1x1)", [1, 1], "cloth"),
            ("coronation_damask_drapery", "Gold-Thread Coronation Damask Wall Drape (2x1)", "Màn Gấm Dát Chỉ Vàng Lễ Đăng Quang (2x1)", [2, 1], "cloth"),
        ]),
        ("chancery_and_treasury", [
            ("high_scribe_scriptorium_desk", "Slanted Oak Scribe Desk with Parchment Rolls", "Bàn Kê Dốc Của Người Chép Sử (2x1)", [2, 1], "wood"),
            ("royal_charter_wax_seal_press", "Brass Screw Wax Seal Press & Bulla Matrix", "Máy Ép Dấu Sáp Niêm Phong Hoàng Gia (1x1)", [1, 1], "brass"),
            ("iron_banded_money_chest", "Heavy Three-Padlock Iron Guild Treasury Chest", "Rương Kho Bạc Sắt Ba Ổ Khóa (2x1)", [2, 1], "iron"),
            ("sovereign_coin_counting_table", "Checked Cloth Coin Tally Table (Exchequer)", "Bàn Kẻ Ô Đếm Thuế Tiền Xu (2x1)", [2, 1], "wood"),
            ("illuminated_feudal_roll_cabinet", "Fiefdom Roll Parchment Pigeonhole Shelving", "Kệ Ô Đựng Khế Ước Phong Kiến (2x1)", [2, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat4_subs_40:
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
                    "inspect", f"Palace state & chancery fixture ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 5. modular_timber_frame_architecture (480 assets: 6 subcats * 80)
    # =========================================================================
    cid = "modular_timber_frame_architecture"
    cat5_subs = [
        ("stone_footing_and_plinth", [
            ("rubble_dwarf_wall_foundation", "Drystone Dwarf Wall Foundation Bay (2x1)", "Chân Móng Tường Đá Thấp (2x1)", [2, 1], "stone"),
            ("carved_granite_corner_padstone", "Carved Granite Timber Padstone Pier (1x1)", "Khối Đá Kê Chân Cột Gỗ Chống Ẩm (1x1)", [1, 1], "stone"),
            ("cobblestone_courtyard_border", "Curbed Stone Threshold Border (2x1)", "Bờ Đá Kê Ngưỡng Cửa Nhà Gỗ (2x1)", [2, 1], "stone"),
            ("cellar_ventilation_grate_plinth", "Slotted Iron Cellar Air Vent Plinth (1x1)", "Lỗ Thông Khí Hầm Rượu Có Song Sắt (1x1)", [1, 1], "iron"),
            ("flint_and_mortar_rubble_plinth", "Knapped Flint Plinth Wall (2x1)", "Móng Đá Lửa Đập Vụn Trát Vữa (2x1)", [2, 1], "stone"),
            ("timber_sill_plate_sole_beam", "Treated Oak Sole Plate Sill Beam (2x1)", "Thanh Gỗ Dầm Đế Kê Chân Khung (2x1)", [2, 1], "wood"),
            ("low_flagstone_entry_steps", "Low Worn Flagstone Entrance Steps (1x1)", "Bậc Thềm Đá Nhẵn Lối Vào (1x1)", [1, 1], "stone"),
            ("timber_post_iron_bracket_foot", "Iron-Stirrup Reinforced Post Foot (1x1)", "Chân Cột Gỗ Bọc Đai Sắt Gia Cố (1x1)", [1, 1], "iron"),
        ]),
        ("cruck_and_timber_framing", [
            ("massive_curved_cruck_blade_pair", "Massive Curved Oak Cruck Arch Frame (2x2)", "Cặp Cột Gỗ Cong Cruck Chịu Lực (2x2)", [2, 2], "wood"),
            ("half_timber_st_andrews_cross", "Half-Timber Frame with St. Andrew's Cross (2x1)", "Khung Gỗ Chữ Thập Thánh Andrew (2x1)", [2, 1], "wood"),
            ("jetty_cantilever_bracket_beam", "Overhanging Cantilever Jetty Beam (1x1)", "Dầm Gỗ Nhô Tầng Hai Công-Xôn (1x1)", [1, 1], "wood"),
            ("vertical_close_studding_bay", "Dense Vertical Studding Wall Bay (2x1)", "Đoạn Tường Cột Gỗ Xếp Khít (2x1)", [2, 1], "wood"),
            ("horizontal_tie_beam_collar", "Heavy Chamber Tie Beam with Scarf Joint (2x1)", "Dầm Gỗ Ngang Giằng Mái Nối Mộng (2x1)", [2, 1], "wood"),
            ("corner_dragon_beam_bracket", "Corner Jetty Dragon Beam Diagonal Strut (1x1)", "Thanh Dầm Chéo Góc Đỡ Tầng Nhô (1x1)", [1, 1], "wood"),
            ("half_timber_aisle_arcade_post", "Internal Barn Arcaded Timber Post (1x1)", "Cột Gỗ Trụ Kho Thóc Lớn (1x1)", [1, 1], "wood"),
            ("carved_timber_bressummer_beam", "Carved Foliage Bressummer Lintel (2x1)", "Thanh Xà Ngang Chạm Khắc Hoa Lá (2x1)", [2, 1], "wood"),
        ]),
        ("wattle_daub_and_brick_infill", [
            ("whitewashed_wattle_daub_panel", "Whitewashed Wattle-and-Daub Infill (2x1)", "Vách Đan Nứa Trát Vữa Quét Vôi (2x1)", [2, 1], "earth"),
            ("herringbone_red_brick_nogging", "Herringbone Red Brick Nogging Panel (2x1)", "Vách Lát Gạch Đỏ Xương Cá (2x1)", [2, 1], "brick"),
            ("exposed_clay_straw_plaster", "Unbleached Straw-Clay Rough Plaster (2x1)", "Vách Rơm Trộn Đất Sét Thô (2x1)", [2, 1], "earth"),
            ("plaster_pargeting_relief_panel", "Decorative Pargeted Plaster Floral Panel (2x1)", "Vách Thạch Cao Đắp Nổi Hoa Văn (2x1)", [2, 1], "earth"),
            ("basket_weave_split_hazel_hurdle", "Unplastered Woven Hazel Wattle Bay (2x1)", "Khung Đan Cành Dẻ Gai Chưa Trát (2x1)", [2, 1], "wood"),
            ("weathered_flaking_lime_wall", "Aged Flaking Limewash Over Daub (2x1)", "Vách Vôi Tróc Lộ Khung Trát (2x1)", [2, 1], "earth"),
            ("timber_diagonal_braced_brick", "Brick Infill with Diagonal Oak Braces (2x1)", "Vách Gạch Có Thanh Giằng Gỗ Chéo (2x1)", [2, 1], "brick"),
            ("pebble_dash_roughcast_panel", "Roughcast Lime & Gravel Harled Wall (2x1)", "Vách Vữa Trộn Sỏi Dăm Bền Chắc (2x1)", [2, 1], "stone"),
        ]),
        ("window_and_door_bays", [
            ("leaded_diamond_pane_window_bay", "Leaded Diamond-Pane Casement Window (2x1)", "Cửa Sổ Kính Quả Trám Khung Chì (2x1)", [2, 1], "glass"),
            ("arched_timber_plank_doorway", "Pointed Arched Heavy Oak Plank Doorway (1x1)", "Khung Cửa Vòm Gỗ Sồi Ghép Tấm (1x1)", [1, 1], "wood"),
            ("wooden_board_hinged_shutters", "Twin Timber Board Window Shutters (1x1)", "Cánh Cửa Sổ Bằng Ván Gỗ Khép Kín (1x1)", [1, 1], "wood"),
            ("oriel_bay_window_overhang", "Cantilevered Timber Oriel Bay Window (2x1)", "Cửa Sổ Nhô Ra Ngoài Kiểu Oriel (2x1)", [2, 1], "wood"),
            ("iron_strap_hinged_stable_door", "Dutch Split Stable Door with Strap Hinges (1x1)", "Cửa Chuồng Ngựa Tách Đôi Bản Lề Sắt (1x1)", [1, 1], "wood"),
            ("iron_grille_transom_door", "Reinforced Entry Door with Iron Bar Grille (1x1)", "Cửa Chính Có Ô Thoáng Song Sắt (1x1)", [1, 1], "iron"),
            ("sliding_timber_unglazed_wicket", "Sliding Slatted Wooden Ventilation Vent (1x1)", "Cửa Chớp Trượt Bằng Gỗ Thông Khí (1x1)", [1, 1], "wood"),
            ("carved_gothic_wooden_doorhead", "Carved Trefoil Arch Oak Doorhead (1x1)", "Khung Gỗ Cửa Khắc Hình Lá Ba Cánh (1x1)", [1, 1], "wood"),
        ]),
        ("roof_gable_and_dormer", [
            ("steep_pitched_thatch_gable", "Steeply Pitched Wheat Thatch Gable Roof (2x2)", "Mái Đầu Hồi Lợp Rơm Dốc Đứng (2x2)", [2, 2], "straw"),
            ("terracotta_plain_tile_roof_bay", "Red Terracotta Plain Clay Tile Roof (2x2)", "Mái Lợp Ngói Đất Nung Đỏ (2x2)", [2, 2], "ceramic"),
            ("blue_slate_gabled_roof_ridge", "Welsh Blue Slate Roof with Lead Flashing (2x2)", "Mái Lợp Đá Phiến Xanh Xám (2x2)", [2, 2], "stone"),
            ("timber_bargeboard_dormer_window", "Carved Bargeboard Roof Dormer Window (1x1)", "Cửa Sổ Mái Dormer Có Diềm Gỗ (1x1)", [1, 1], "wood"),
            ("thatched_eyebrow_roof_curve", "Flowing Thatched Eyebrow Window Curve (2x1)", "Mái Rơm Uốn Cong Kiểu Mí Mắt (2x1)", [2, 1], "straw"),
            ("roof_ridge_woven_straw_finial", "Cross-Stitched Straw Thatch Ridge Cap (2x1)", "Bờ Nóc Mái Rơm Khâu Đan Hoa Văn (2x1)", [2, 1], "straw"),
            ("hipped_timber_roof_end", "Half-Hipped Timber Shingle Roof End (2x2)", "Mái Cắt Góc Lợp Ngói Gỗ Shingle (2x2)", [2, 2], "wood"),
            ("lead_valley_flashing_junction", "Lead Valley Roof Drainage Gulley (1x1)", "Máng Chì Thoát Nước Rãnh Mái (1x1)", [1, 1], "iron"),
        ]),
        ("chimney_veranda_and_annex", [
            ("twisted_tudor_brick_chimney_stack", "Twisted Spiral Brick Chimney Stack (1x1)", "Ống Khói Gạch Xoắn Kiểu Tudor (1x1)", [1, 1], "brick"),
            ("rustic_rubble_stone_chimney_breast", "Exterior Fieldstone Chimney Breast (1x2)", "Lưng Ống Khói Bằng Đá Cuội Thô (1x2)", [1, 2], "stone"),
            ("covered_timber_veranda_porch", "Covered Timber Porch Lean-To Veranda (2x1)", "Mái Hiên Gỗ Che Nắng Mưa (2x1)", [2, 1], "wood"),
            ("timber_penthouse_annex_shed", "Timber Penthouse Extension Lean-To (2x1)", "Nhà Kho Chái Bằng Gỗ Áp Mái (2x1)", [2, 1], "wood"),
            ("projecting_cellar_bulkhead_doors", "Slanted Timber Cellar Bulkhead Doors (1x1)", "Cửa Hầm Nằm Nghiêng Bằng Gỗ (1x1)", [1, 1], "wood"),
            ("outside_covered_timber_staircase", "Exterior Covered Wooden Staircase (1x2)", "Cầu Thang Gỗ Có Mái Che Ngoài Trời (1x2)", [1, 2], "wood"),
            ("timber_washhouse_lean_to", "Washhouse Timber Lean-To with Copper Vat (2x1)", "Chái Nhà Giặt Bằng Gỗ Có Chảo Đồng (2x1)", [2, 1], "wood"),
            ("wrought_iron_bracketed_gutter", "Wrought-Iron Supported Timber Roof Gutter (2x1)", "Máng Nối Gỗ Có Bát Đỡ Bằng Sắt (2x1)", [2, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat5_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_10:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, dark ink contours, transparent background."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "solid",
                    "inspect", f"Vernacular half-timbered modular component ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure"
                ))

    # =========================================================================
    # 6. church_cathedral_and_monastery (310 assets: 2*55 + 4*50)
    # =========================================================================
    cid = "church_cathedral_and_monastery"
    cat6_subs_55 = [
        ("cathedral_portal_and_facade", [
            ("pointed_arch_portal_tympanum", "Pointed Arch Portal with Carved Tympanum (3x2)", "Cổng Vòm Nhọn Điêu Khắc Vòm Cửa (3x2)", [3, 2], "stone"),
            ("jamb_statues_colonnade", "Apostle Jamb Statues Portal Column (1x2)", "Hàng Tượng Thánh Khắc Trên Trụ Cổng (1x2)", [1, 2], "stone"),
            ("stained_glass_rose_window", "Monumental Twelve-Petal Rose Window (3x3)", "Cửa Sổ Hoa Hồng Kính Màu Lớn (3x3)", [3, 3], "glass"),
            ("twin_gothic_portal_doors", "Carved Oak Twin Cathedral Doors with Iron Scrolls (2x2)", "Cửa Gỗ Hai Cánh Khắc Hoa Văn Sắt (2x2)", [2, 2], "wood"),
            ("arcaded_gallery_of_kings", "Arcaded Stone Gallery of Kings Relief (3x1)", "Dãy Tượng Các Vị Vua Trên Mặt Tiền (3x1)", [3, 1], "stone"),
        ]),
        ("buttress_and_spire", [
            ("flying_buttress_arch_span", "Double-Tier Flying Buttress Arch (2x2)", "Nhịp Cung Bay Đỡ Mái Vòm Nhà Thờ (2x2)", [2, 2], "stone"),
            ("buttress_pinnacle_crocket", "Pinnacle Pier with Carved Crocket Spire (1x1)", "Tháp Nhỏ Đỉnh Cột Trụ Đính Hoa Đá (1x1)", [1, 1], "stone"),
            ("carved_grotesque_gargoyle_spout", "Carved Stone Grotesque Water Spout (1x1)", "Tượng Thú Đá Răng Nanh Miệng Máng Nước (1x1)", [1, 1], "stone"),
            ("octagonal_bell_tower_belfry", "Octagonal Stone Belfry Louvered Window (2x2)", "Tầng Gác Chuông Bát Giác Lỗ Chớp (2x2)", [2, 2], "stone"),
            ("soaring_leaded_spire_finial", "Leaded Timber Cross Spire Finial (1x3)", "Đỉnh Tháp Nhọn Bọc Chì Cắm Thánh Giá (1x3)", [1, 3], "stone"),
        ]),
    ]
    for sub_id, concepts in cat6_subs_55:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_11:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    "pray", f"Gothic ecclesiastical cathedral component ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure"
                ))

    cat6_subs_50 = [
        ("altar_and_choir_sanctuary", [
            ("carrara_marble_high_altar", "Carved White Marble High Altar (2x1)", "Bàn Thờ Chính Bằng Đá Cẩm Thạch Trắng (2x1)", [2, 1], "stone"),
            ("gilded_crucifix_altar_cross", "Gilded Bronze Altar Crucifix Cross (1x1)", "Thánh Giá Bằng Đồng Mạ Vàng (1x1)", [1, 1], "bronze"),
            ("carved_oak_choir_stalls_misericord", "Carved Oak Choir Stalls with Misericords (3x1)", "Hàng Ghế Ca Đoàn Gỗ Sồi Có Điểm Tựa (3x1)", [3, 1], "wood"),
            ("octagonal_stone_baptismal_font", "Carved Octagonal Stone Baptismal Font (1x1)", "Bình Rửa Tội Bát Giác Bằng Đá (1x1)", [1, 1], "stone"),
            ("ornate_stone_preaching_pulpit", "Elevated Stone Preaching Pulpit with Canopy (2x2)", "Tòa Giảng Bằng Đá Nâng Cao Có Mái (2x2)", [2, 2], "stone"),
        ]),
        ("reliquary_and_shrine", [
            ("golden_saint_reliquary_casket", "Champlevé Enamel Saint Reliquary Chasse (1x1)", "Hòm Đựng Xương Thánh Men Màu Mạ Vàng (1x1)", [1, 1], "gold"),
            ("tiered_votive_candle_stand", "Tiered Wrought-Iron Votive Candle Stand (1x1)", "Giá Đỡ Nến Khấn Nguyện Bằng Sắt Uốn (1x1)", [1, 1], "iron"),
            ("carved_stone_holy_water_stoup", "Carved Angel Basin Holy Water Stoup (1x1)", "Bồn Nước Thánh Hình Thiên Thần Bằng Đá (1x1)", [1, 1], "stone"),
            ("pilgrim_donation_iron_almsbox", "Chained Oak Pilgrim Alms Collection Box (1x1)", "Hòm Công Đức Buộc Xích Sắt (1x1)", [1, 1], "wood"),
            ("miraculous_icon_triptych_altarpiece", "Hinged Gilded Triptych Altarpiece (2x1)", "Bức Tranh Thánh Ba Cánh Mạ Vàng (2x1)", [2, 1], "wood"),
        ]),
        ("monastery_cloister_and_scriptorium", [
            ("arcaded_cloister_walk_bay", "Arcaded Monastic Cloister Walkway Bay (2x1)", "Hành Lang Mái Vòm Tu Viện (2x1)", [2, 1], "stone"),
            ("cloister_central_lavabo_fountain", "Octagonal Stone Monastic Lavabo Fountain (2x2)", "Đài Phun Nước Rửa Tay Tu Viện (2x2)", [2, 2], "stone"),
            ("scriptorium_manuscript_desk", "Slanted Dual Scriptorium Scribe Desk (2x1)", "Bàn Chép Kinh Đôi Độ Dốc Cao (2x1)", [2, 1], "wood"),
            ("parchment_quill_inkpot_stand", "Ox-Horn Inkpot and Quill Carved Stand (1x1)", "Khay Mực Sừng Bò & Bút Lông Ngỗng (1x1)", [1, 1], "wood"),
            ("monastic_herb_drying_ceiling_rack", "Hanging Medicinal Herb Drying Racks (2x1)", "Giàn Treo Phơi Thảo Dược Tu Viện (2x1)", [2, 1], "wood"),
        ]),
        ("crypt_and_ossuary", [
            ("ribbed_vault_crypt_pillar", "Low Romanesque Ribbed Crypt Pillar (1x1)", "Trụ Đá Thấp Vòm Hầm Mộ (1x1)", [1, 1], "stone"),
            ("gothic_knight_effigy_tomb", "Knight Carved Gisant Stone Sarcophagus (2x1)", "Quan Tài Đá Khắc Tượng Hiệp Sĩ Nằm (2x1)", [2, 1], "stone"),
            ("stacked_skull_ossuary_niche", "Stacked Bone & Skull Ossuary Wall Niche (2x1)", "Hốc Tường Xếp Xương Đầu Lâu Hầm Mộ (2x1)", [2, 1], "bone"),
            ("crypt_iron_cresset_torch_bracket", "Wrought-Iron Crypt Wall Cresset Torch (1x1)", "Giá Đỡ Đuốc Dầu Bằng Sắt Trong Hầm Mộ (1x1)", [1, 1], "iron"),
            ("underground_relic_vault_gate", "Heavy Iron Barred Crypt Sanctum Grate (1x1)", "Cửa Song Sắt Kho Chứa Thánh Tích Dưới Đất (1x1)", [1, 1], "iron"),
        ]),
    ]
    for sub_id, concepts in cat6_subs_50:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_10:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "pray"
                if "fountain" in c_slug:
                    verb = "drink"
                elif "desk" in c_slug:
                    verb = "inspect"
                elif "tomb" in c_slug:
                    verb = "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Ecclesiastical sanctuary & monastic fixture ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 7. village_cottage_and_homestead (220 assets: 5 subcats * 44)
    # =========================================================================
    cid = "village_cottage_and_homestead"
    cat7_subs = [
        ("peasant_hovel_and_hut", [
            ("turf_roofed_stone_hovel", "Low Fieldstone Turf-Roofed Peasant Hovel (2x2)", "Túp Lều Nông Dân Bằng Đá Lợp Cỏ (2x2)", [2, 2], "stone"),
            ("wattle_daub_thatched_cottage", "Wattle-and-Daub Straw Thatched Cottage (2x2)", "Nhà Tranh Vách Đất Nông Thôn (2x2)", [2, 2], "wood"),
            ("smoke_hole_hearth_hovel", "Round Peasant Hut with Central Smoke Hole (2x2)", "Lều Đất Tròn Có Lỗ Thoát Khói Đỉnh (2x2)", [2, 2], "earth"),
            ("cob_clay_peasant_dwelling", "Cob Earth Plaster Peasant Cottage (2x2)", "Nhà Đất Sét Nén Mộc Mạc (2x2)", [2, 2], "earth"),
        ]),
        ("village_well_and_pump", [
            ("circular_stone_wellhead", "Circular Stone Wellhead with Timber Crank (1x1)", "Giếng Nước Đá Tròn Có Tay Quay Gỗ (1x1)", [1, 1], "stone"),
            ("oak_shadoof_counterweight_sweep", "Timber Shadoof Counterweight Well Sweep (2x1)", "Cần Cẩu Nước Có Đối Trọng Bằng Gỗ (2x1)", [2, 1], "wood"),
            ("communal_hollow_log_water_trough", "Carved Hollow Log Washing Trough (2x1)", "Máng Nước Gỗ Đục Thân Cây Rửa Đồ (2x1)", [2, 1], "wood"),
            ("lead_spout_village_fountain", "Village Green Stone Cistern with Lead Spout (1x1)", "Bể Nước Công Cộng Vòi Chì (1x1)", [1, 1], "stone"),
        ]),
        ("hearth_and_bread_oven", [
            ("domed_clay_bread_oven", "Outdoor Domed Cob Clay Bread Oven (1x1)", "Lò Nướng Bánh Mì Đất Sét Vòm Ngoài Trời (1x1)", [1, 1], "earth"),
            ("outdoor_iron_cauldron_tripod", "Campfire Iron Tripod with Stew Cauldron (1x1)", "Kiềng Sắt Ba Chân Nấu Nồi Nước Dùng (1x1)", [1, 1], "iron"),
            ("drying_fish_meat_smokehouse", "Woven Wattle Smoker Shed with Peat Hearth (1x1)", "Chòi Xông Khói Cá Thịt Đốt Than Bùn (1x1)", [1, 1], "wood"),
            ("domestic_turning_spit_hearth", "Stone Hearth Pit with Roasting Pig Spit (2x1)", "Bếp Lò Đá Quay Thịt Ngoài Trời (2x1)", [2, 1], "stone"),
        ]),
        ("fence_and_stone_wall", [
            ("drystone_sheep_dyke_wall", "Drystone Field Boundary Dyke Wall (2x1)", "Tường Đá Xếp Ngăn Bờ Ruộng (2x1)", [2, 1], "stone"),
            ("woven_wattle_hurdle_fence", "Woven Hazel Hurdle Movable Enclosure (2x1)", "Hàng Rào Đan Cành Dẻ Gai Di Động (2x1)", [2, 1], "wood"),
            ("split_rail_timber_post_fence", "Split-Rail Oak Timber Pasture Fence (2x1)", "Rào Gỗ Sồi Ghép Thanh Nẹp Đồng Cỏ (2x1)", [2, 1], "wood"),
            ("wooden_stile_steps_over_wall", "Wooden A-Frame Steps Stile Over Wall (1x1)", "Bậc Thang Vượt Tường Bằng Gỗ (1x1)", [1, 1], "wood"),
        ]),
        ("homestead_shed_and_woodpile", [
            ("stacked_oak_cordwood_pile", "Neat Stacked Split Oak Cordwood (2x1)", "Chồng Củi Gỗ Sồi Chẻ Xếp Ngăn Nắp (2x1)", [2, 1], "wood"),
            ("thatch_tool_storage_shed", "Lean-To Thatched Implement Tool Shed (2x1)", "Chòi Chái Lợp Tranh Cất Nông Cụ (2x1)", [2, 1], "wood"),
            ("thatched_dog_kennel_coop", "Thatched Hound Kennel with Straw Bedding (1x1)", "Chuồng Chó Săn Lợp Tranh Lót Rơm (1x1)", [1, 1], "wood"),
            ("peat_fuel_drying_rick", "Stacked Dark Peat Turf Fuel Rick (2x1)", "Đống Khối Than Bùn Phơi Khô Đốt Lửa (2x1)", [2, 1], "earth"),
        ]),
    ]
    for sub_id, concepts in cat7_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_11:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "enter" if "cottage" in c_slug or "hovel" in c_slug else "inspect"
                if "well" in c_slug or "pump" in c_slug or "trough" in c_slug:
                    verb = "draw_well_water"
                elif "oven" in c_slug:
                    verb = "bake_bread"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Rural serf homestead structure ({c_name}).", True, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 2 and fprint[1] >= 2 else "prop"
                ))

    return items
