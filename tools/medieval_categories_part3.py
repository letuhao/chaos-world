# -*- coding: utf-8 -*-
"""Medieval Western Categories Part 3 (Categories 16 - 22: 1,220 assets)."""

from __future__ import annotations

def generate_part3(make_asset) -> list[dict]:
    items: list[dict] = []

    # Variants 13 (for 2 * 13 = 26)
    variants_13 = [
        ("norman_chiseled", "Norman Sturdy", "Kiểu Norman Chắc Chắn", "norman", "heavy oak timbers and solid mortared stone"),
        ("weathered_aged", "Ancient Weathered", "Dãi Dầu Năm Tháng", "anglo_saxon", "lichen-encrusted and grayed by rain"),
        ("mossy_overgrown", "Mossy Overgrown", "Phủ Rêu Xanh Thẫm", "celtic", "blanketed in damp green moss and ivy vines"),
        ("flemish_guild", "Flemish Crafted", "Chế Tác Vùng Flanders", "flemish", "carefully fashioned with iron fittings and stamped marks"),
        ("capetian_royal", "Capetian Royal", "Hoàng Triều Pháp Capetian", "french_capetian", "refined stonework with royal decorative lines"),
        ("germanic_staufen", "Germanic Imperial", "Đế Chế Đức Kiên Cố", "germanic_holy_roman", "rugged dark timber with heavy forged nails"),
        ("rustic_poacher", "Rustic Outlaw Poacher", "Thợ Săn Trộm Dân Gian", "universal_feudal", "camouflaged with brushwood and untrimmed bark"),
        ("haunted_decay", "Ominous Blighted", "Ám Ảnh U Tối", "universal_feudal", "decayed edges, mold stains, and cold stone feel"),
        ("iron_reinforced", "Iron-Banded Heavy", "Bọc Đai Sắt Gia Cố", "norman", "reinforced with riveted black iron straps"),
        ("autumn_foliage", "Autumn Leaf-Strewn", "Phủ Đầy Lá Vàng Thu", "universal_feudal", "scattered golden beech leaves and dried acorns"),
        ("burned_scorched", "Fire-Scorched Charred", "Cháy Xém Than Đen", "universal_feudal", "blackened wood and cracked soot-stained masonry"),
        ("frost_dusted", "Winter Frost-Rimed", "Phủ Băng Giá Mùa Đông", "germanic_holy_roman", "rime frost crystals coating upper edges"),
        ("ancient_celtic", "Ancient Celtic Relic", "Cổ Vật Xứ Celtic", "celtic", "weathered gray granite marked with archaic spiral lines"),
    ]

    # Variants 10 (for 5 * 10 = 50)
    variants_10 = [
        ("ancient_primeval", "Ancient Primeval", "Nguyên Sinh Cổ Đại", "celtic", "centuries-old gnarled bark, massive twisted roots, and heavy moss"),
        ("mature_healthy", "Mature Thriving", "Trưởng Thành Tốt Tươi", "norman", "broad lush foliage canopy with healthy vigorous bark"),
        ("autumn_golden", "Golden Autumn", "Vàng Rực Mùa Thu", "french_capetian", "brilliant ochre, amber, and russet seasonal foliage"),
        ("winter_bare", "Winter Bare-Branch", "Trơ Trụi Cành Đông", "germanic_holy_roman", "stark silhouetted bare branches dusted with white frost"),
        ("lightning_struck", "Lightning-Struck Split", "Sét Đánh Tách Thân", "universal_feudal", "hollow split trunk with blackened heartwood and jagged limbs"),
        ("wind_bent", "Highland Wind-Sheared", "Gió Bão Uốn Cong", "anglo_saxon", "low sweeping horizontal boughs sculpted by coastal gales"),
        ("moss_draped", "Deep Greenwood Moss-Draped", "Rêu Phong Rừng Thẳm", "flemish", "thick beard lichens and hanging moss tendrils"),
        ("spring_flowering", "Spring Vernal Blossoming", "Mùa Xuân Đơm Hoa", "universal_feudal", "fresh pale green buds and delicate woodland blossoms"),
        ("rain_soaked", "Rain-Drenched Woodland", "Ngấm Nước Mưa Ướt", "universal_feudal", "dark glistening wet bark with dripping foliage"),
        ("old_coppiced", "Ancient Coppiced Regrowth", "Gốc Cây Đốn Mọc Chồi", "universal_feudal", "multiple straight stems sprouting from an ancient stool"),
    ]

    # Variants 9 (for 4 * 9 = 36)
    variants_9 = [
        ("chalk_white", "White Chalk Escarpment", "Vách Đá Vôi Trắng", "anglo_saxon", "bright crumbling pale limestone and chalk ledges"),
        ("dark_granite", "Tor Granite Weathered", "Đá Hoa Cương Đen Tự Nhiên", "celtic", "dark weathered stone blocks and lichen-stained faces"),
        ("slate_blue", "Blue Slate Stratified", "Đá Phiến Xanh Phân Tầng", "norman", "layered fissured blue-grey metamorphic rock slabs"),
        ("sandstone_red", "Red Sandstone Escarpment", "Vách Sa Thạch Đỏ", "germanic_holy_roman", "warm ferruginous sandstone with deep wind-hollowed cavities"),
        ("mossy_spring", "Mossy Brook Spray", "Rêu Phong Suối Nước", "universal_feudal", "coated with wet weeping moss and dripping mountain moisture"),
        ("heather_crowned", "Heather-Crowned Highland", "Phủ Hoa Thạch Nam Vùng Cao", "celtic", "topped with blooming purple bell heather and wild bilberries"),
        ("scree_talus", "Loose Talus Scree", "Đá Vụn Sụt Lở", "universal_feudal", "shattered frost-wedged rock shards piled at base"),
        ("cavernous_cleft", "Deep Shadow Cleft", "Khe Nứt Vực Sâu", "universal_feudal", "narrow vertical fissures opening into dark underground chasms"),
        ("frost_shattered", "Glacial Frost-Shattered", "Đá Vỡ Do Băng Giá", "germanic_holy_roman", "sharp angular blocks split by freezing winter ice"),
    ]

    # Variants 19 (for 2 * 19 = 38)
    variants_19 = [
        ("oak_iron_banded", "Iron-Banded Oak", "Gỗ Sồi Bọc Đai Sắt", "norman", "heavy quarter-sawn oak with riveted black iron straps"),
        ("weathered_carved", "Weathered Carved Walnut", "Gỗ Óc Chó Chạm Khắc Cũ", "french_capetian", "softened antique wax polish and subtle heraldic reliefs"),
        ("merchant_padlocked", "Merchant Guild Padlocked", "Thương Hội Khóa Chặt", "flemish", "solid brass tumbler padlock and guild lead seal"),
        ("rough_hewn_pine", "Rough-Hewn Rustic Pine", "Gỗ Thông Đẽo Thô", "universal_feudal", "rough unplaned pine boards with visible wood grain"),
        ("royal_gilt_studded", "Royal Gilt-Studded Velvet", "Hoàng Gia Nạm Vàng Rực Rỡ", "french_capetian", "adorned with gilded brass studs and scarlet lining"),
        ("shipwreck_barnacled", "Shipwreck Barnacle-Crusted", "Đắm Tàu Bám Hà Biển", "norman", "salt-stained timbers with green verdigris fittings"),
        ("smuggler_camouflaged", "Smuggler Peat-Stained", "Buôn Lậu Vấy Bùn Than", "celtic", "dark peat stains and mud coating to conceal in bog"),
        ("cellar_cobwebbed", "Dusty Cobwebbed Cellar", "Mạng Nhện Bụi Bặm Hầm Rượu", "universal_feudal", "draped in thick grey cobwebs and dry cellar dust"),
        ("reinforced_steel_strapped", "Armory Steel-Strapped", "Kho Binh Khí Bọc Thép", "germanic_holy_roman", "armored steel corner braces and tamper-proof hasp"),
        ("battlefield_dented", "Battlefield Arrow-Notched", "Vết Tên Rạch Chiến Trường", "universal_feudal", "scratched by blades and notched with arrow strikes"),
        ("monastic_inscribed", "Monastic Latin Inscribed", "Tu Viện Khắc Chữ Latinh", "universal_feudal", "carved with protective Latin crosses and prayers"),
        ("burgundian_ebony", "Burgundian Dark Ebony", "Gỗ Mun Đen Burgundy", "french_capetian", "gleaming pitch-black timber with polished brass corners"),
        ("mossy_tomb_find", "Tomb Relic Damp-Stained", "Hầm Mộ Cổ Ẩm Ướt", "celtic", "green lichen patches from centuries in stone crypts"),
        ("autumn_leaf_covered", "Forest Hidden Leaf-Strewn", "Giấu Dưới Rừng Lá Thu", "universal_feudal", "blanketed in crisp brown oak leaves and forest loam"),
        ("dwarfed_compact", "Travelers Compact Saddle", "Hành Lý Gọn Gàng Cưỡi Ngựa", "universal_feudal", "compact reinforced construction with leather tie straps"),
        ("tarred_waterproof", "Tarred Naval Waterproof", "Quét Hắc Ín Chống Nước Hải Quân", "norman", "pitch-coated seams completely impervious to sea spray"),
        ("charred_fire_salvage", "Burned House Salvaged", "Cứu Khỏi Đám Cháy Xém Than", "universal_feudal", "partially charred wood with gleaming brass latch"),
        ("heavy_lead_lined", "Heavy Lead-Lined Secure", "Lót Chì Nặng Chống Nước", "flemish", "impermeable lead sheet interior lining"),
        ("cracked_splintered", "Fragile Cracked Splintered", "Rạn Nứt Dễ Vỡ", "universal_feudal", "dry splintered wood ready to shatter on impact"),
    ]

    # Variants 7 (for 6 * 7 = 42)
    variants_7 = [
        ("norman_stout", "Norman Feudal", "Phong Kiến Norman", "norman", "heavy mail, stout wool tunic, and Norman nasal helmet"),
        ("anglo_saxon_fyrd", "Anglo-Saxon Freeholder", "Thường Dân Tự Do Anglo-Saxon", "anglo_saxon", "dyed linen kirtle, leather shoes, and woven leg wraps"),
        ("capetian_courtly", "Capetian French Courtly", "Quý Tộc Pháp Capetian", "french_capetian", "embroidered woolen cotehardie and leather belt purse"),
        ("germanic_staufen", "Germanic Imperial Townsman", "Thị Dân Đế Chế Đức", "germanic_holy_roman", "quilted gambeson, iron kettle hat, and leather gauntlets"),
        ("flemish_guildsman", "Flemish Guild Bourgeois", "Thị Dân Phường Hội Flanders", "flemish", "fine woven broadcloth, fur-trimmed hood, and pouch"),
        ("celtic_highlander", "Celtic Highlander Clansman", "Chiến Binh Bộ Tộc Celtic", "celtic", "woolen braccae trousers, rough mantle, and brooch"),
        ("rugged_frontier", "Wilderness Frontier Hardy", "Lãng Du Biên Giới Bụi Bặm", "universal_feudal", "weathered traveling cloak, stout walking staff, and boots"),
    ]

    # =========================================================================
    # 16. outlaw_brigand_and_wilderness_hideout (130 assets: 5 subcats * 26: 2*13)
    # =========================================================================
    cid = "outlaw_brigand_and_wilderness_hideout"
    cat16_subs = [
        ("bandit_campsite_and_lean_to", [
            ("camouflaged_brushwood_lean_to", "Camouflaged Forest Brushwood Lean-To (2x2)", "Lán Trú Ẩn Rừng Ngụy Trang Cành Cây (2x2)", [2, 2], "wood"),
            ("bandit_campfire_roasted_game", "Concealed Campfire with Spitted Roasting Boar (2x1)", "Bếp Lửa Trại Nướng Thịt Rừng (2x1)", [2, 1], "stone"),
        ]),
        ("robber_baron_ruins", [
            ("crumbled_robber_baron_keep", "Crumbled Stone Robber Baron Watchtower (3x3)", "Tàn Tích Pháo Đài Sơn Tặc Bằng Đá (3x3)", [3, 3], "stone"),
            ("breached_stockade_palisade", "Breached Spiked Timber Palisade Wall (2x1)", "Tường Rào Gỗ Sơn Tặc Bị Chọc Thủng (2x1)", [2, 1], "wood"),
        ]),
        ("traps_and_ambush", [
            ("camouflaged_pitfall_punji_trap", "Foliage-Concealed Punji Stake Pitfall Trap (2x2)", "Hố Bẫy Chông Cắm Ngụy Trang Lá Khô (2x2)", [2, 2], "earth"),
            ("deadfall_suspended_log_trap", "Tripwire Suspended Heavy Log Deadfall Trap (2x1)", "Bẫy Gỗ Nặng Treo Dây Bẫy Bật Đổ (2x1)", [2, 1], "wood"),
        ]),
        ("gallows_and_warnings", [
            ("roadside_timber_gibbet_cage", "Iron Gibbet Cage Suspended from Gallows (1x2)", "Lồng Sắt Treo Thi Thể Tên Cướp Đường (1x2)", [1, 2], "iron"),
            ("severed_bandit_head_on_pike", "Warning Bandit Head on Upright Iron Pike (1x1)", "Đầu Lâu Tên Cướp Cắm Cọc Sắt Cảnh Báo (1x1)", [1, 1], "iron"),
        ]),
        ("smuggler_cache", [
            ("hollow_oak_tree_stash_cache", "Hollow Gnarled Oak Smuggler Treasure Cache (2x2)", "Hốc Cây Sồi Cổ Thụ Giấu Kho Báu (2x2)", [2, 2], "wood"),
            ("buried_stone_coffer_camouflaged", "Brush-Covered Buried Ironbound Loot Coffer (1x1)", "Rương Tiền Chôn Dưới Đất Phủ Cành Rào (1x1)", [1, 1], "iron"),
        ]),
    ]
    for sub_id, concepts in cat16_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_13:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "disarm_trap" if "trap" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Outlaw brigand hideout element ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 else "prop"
                ))

    # =========================================================================
    # 17. graveyard_crypt_and_charnel_house (130 assets: 5 subcats * 26: 2*13)
    # =========================================================================
    cid = "graveyard_crypt_and_charnel_house"
    cat17_subs = [
        ("headstone_and_cross", [
            ("carved_celtic_high_cross", "Carved Stone Celtic High Wheel Cross (1x1)", "Thánh Giá Bánh Xe Bằng Đá Celtic (1x1)", [1, 1], "stone"),
            ("weathered_slate_leaning_headstone", "Mossy Leaning Slate Gravestone Slab (1x1)", "Bia Mộ Đá Phiến Nghiêng Phủ Rêu (1x1)", [1, 1], "stone"),
        ]),
        ("sarcophagus_and_mausoleum", [
            ("gothic_stone_mausoleum_vault", "Gabled Gothic Stone Family Mausoleum Vault (3x2)", "Lăng Mộ Gia Tộc Bằng Đá Mái Nhọn Gothic (3x2)", [3, 2], "stone"),
            ("open_gravedigger_pit_mound", "Freshly Dug Earth Grave Pit with Spades (2x1)", "Huyệt Mộ Đất Mới Đào Kèm Xẻng (2x1)", [2, 1], "earth"),
        ]),
        ("charnel_house_and_ossuary", [
            ("stacked_bone_charnel_house", "Limestone Charnel House with Stacked Skull Walls (2x2)", "Nhà Chứa Hài Cốt Xếp Tường Sọ Người (2x2)", [2, 2], "stone"),
            ("ossuary_altar_carved_bones", "Carved Bone Relic Ossuary Altar Table (2x1)", "Bàn Thờ Xương Người Hầm Mộ (2x1)", [2, 1], "bone"),
        ]),
        ("cemetery_gates_and_enclosure", [
            ("spiked_wrought_iron_graveyard_gate", "Rusty Spiked Iron Cemetery Gates with Stone Piers (2x1)", "Cổng Sắt Nghĩa Trang Hoen Gỉ Có Cột Đá (2x1)", [2, 1], "iron"),
            ("mossy_cemetery_perimeter_wall", "Overgrown Fieldstone Churchyard Wall Bay (2x1)", "Tường Đá Ranh Giới Khu Nghĩa Trang (2x1)", [2, 1], "stone"),
        ]),
        ("mourning_and_funerary", [
            ("covered_timber_lychgate_porch", "Covered Timber Lychgate Coffin Resting Porch (2x2)", "Cổng Mái Che Lychgate Đặt Quan Tài (2x2)", [2, 2], "wood"),
            ("carved_stone_weeping_angel_effigy", "Sculpted Stone Mourning Angel Monument (1x1)", "Tượng Đá Thiên Thần Buồn Khóc Tưởng Niệm (1x1)", [1, 1], "stone"),
        ]),
    ]
    for sub_id, concepts in cat17_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_13:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "read_headstone" if "headstone" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval cemetery & funerary fixture ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 else "prop"
                ))

    # =========================================================================
    # 18. forest_ecology_and_ancient_woods (250 assets: 5 subcats * 50: 5*10)
    # =========================================================================
    cid = "forest_ecology_and_ancient_woods"
    cat18_subs = [
        ("ancient_oaks_and_beech", [
            ("gnarled_royal_oak_veteran", "Gnarled Royal English Oak Veteran Tree (3x3)", "Cây Sồi Cổ Thụ Hoàng Gia Anh Vặn Vẹo (3x3)", [3, 3], "plant"),
            ("towering_beech_smooth_bark", "Towering European Beech Cathedral Tree (3x3)", "Cây Dẻ Gai Châu Âu Vươn Cao (3x3)", [3, 3], "plant"),
            ("ancient_sacred_yew_hollow", "Ancient Churchyard Hollow Yew Tree (2x2)", "Cây Thủy Tùng Cổ Thụ Rỗng Ruột (2x2)", [2, 2], "plant"),
            ("coppiced_hornbeam_pollard", "Pollarded Hornbeam Ancient Boundary Tree (2x2)", "Cây Trăn Cắt Ngọn Cổ Đánh Dấu Ranh Giới (2x2)", [2, 2], "plant"),
            ("sprawling_sweet_chestnut_cluster", "Sprawling Sweet Chestnut Grove Tree (3x3)", "Cây Hạt Dẻ Trùng Điệp Trái Nở (3x3)", [3, 3], "plant"),
        ]),
        ("conifers_and_birch", [
            ("scots_pine_red_bark_crown", "Highland Scots Pine with Orange-Red Bark (2x2)", "Cây Thông Scotland Vỏ Đỏ Cam (2x2)", [2, 2], "plant"),
            ("silver_birch_paper_bark_stand", "Cluster of Slender Silver Birch Trees (2x2)", "Cụm Cây Bạch Dương Bạc Vỏ Giấy (2x2)", [2, 2], "plant"),
            ("norway_spruce_conical_timber", "Dense Norway Spruce Conical Evergreen (2x2)", "Cây Vân Sam Châu Âu Tán Nón Dày (2x2)", [2, 2], "plant"),
            ("mountain_larch_golden_needles", "Alpine Larch Tree with Feathery Needles (2x2)", "Cây Lạc Diệp Tùng Vàng Ruộm Vùng Núi (2x2)", [2, 2], "plant"),
            ("quaking_aspen_fluttering_grove", "Quaking Aspen Grove with Shimmering Leaves (2x2)", "Khóm Cây Lá Rung Xào Xạc Trong Gió (2x2)", [2, 2], "plant"),
        ]),
        ("understory_and_brambles", [
            ("dense_bracken_fern_thicket", "Waist-High Bracken Fern Undergrowth Patch (2x1)", "Bụi Cây Dương Xỉ Rậm Cao Ngang Lưng (2x1)", [2, 1], "plant"),
            ("wild_blackberry_bramble_tangle", "Thorny Wild Blackberry Bramble Thicket (2x1)", "Bụi Dâu Rừng Gai Góc Um Tùm (2x1)", [2, 1], "plant"),
            ("gorse_and_broom_yellow_shrub", "Prickly Spiky Gorse Bush with Yellow Flowers (1x1)", "Bụi Cây Đậu Kim Vàng Gai Nhọn (1x1)", [1, 1], "plant"),
            ("woodland_wildflower_primrose_drift", "Carpet of Bluebells & Primroses Woodland Floor (2x1)", "Thảm Hoa Chuông Xanh & Anh Thảo Rừng (2x1)", [2, 1], "plant"),
            ("tall_foxglove_poison_stand", "Towering Purple Foxglove Bellflower Cluster (1x1)", "Cụm Hoa Mao Địa Hoàng Tím Ngắt (1x1)", [1, 1], "plant"),
        ]),
        ("decay_and_forest_floor", [
            ("mossy_hollow_nurse_log", "Decaying Hollow Fallen Oak Nurse Log (3x1)", "Thân Cây Sồi Đổ Rỗng Ruột Phủ Rêu (3x1)", [3, 1], "wood"),
            ("bracket_fungus_birch_stump", "Rotted Birch Tree Stump with Bracket Fungi (1x1)", "Gốc Cây Mục Bám Đầy Nấm Linh Chi Rừng (1x1)", [1, 1], "wood"),
            ("fairy_ring_toadstool_circle", "Woodland Fairy Ring of Spotted Toadstools (2x2)", "Vòng Tròn Nấm Độc Tiên Nữ Rừng Xanh (2x2)", [2, 2], "plant"),
            ("deep_leaf_litter_decay_patch", "Deep Mouldering Beech Leaf Litter Layer (2x1)", "Lớp Mùn Lá Dẻ Gai Mục Nát Dày (2x1)", [2, 1], "earth"),
            ("shattered_root_ball_crater", "Uprooted Tree Root Ball and Water-Filled Pit (2x2)", "Gốc Rễ Cây Bật Khỏi Đất Kèm Vũng Nước (2x2)", [2, 2], "earth"),
        ]),
        ("wetland_alder_and_willow", [
            ("gnarled_weeping_river_willow", "Gnarled Weeping Willow Overhanging Water (3x3)", "Cây Liễu Rủ Uốn Lượn Mặt Nước (3x3)", [3, 3], "plant"),
            ("stilted_black_alder_carr_tree", "Stilted Black Alder Tree Growing in Bog (2x2)", "Cây Cơm Cháy Đen Mọc Chân Cao Đầm Lầy (2x2)", [2, 2], "plant"),
            ("marsh_cattail_and_bulrush_bed", "Dense Marsh Cattails & Bulrushes Reeds Bed (2x1)", "Bãi Cỏ Bồn Bồn & Cây Cói Nước Dày (2x1)", [2, 1], "plant"),
            ("yellow_flag_iris_water_clump", "Flowering Yellow Flag Water Iris Clump (1x1)", "Bụi Hoa Diên Vĩ Vàng Nở Ven Suối (1x1)", [1, 1], "plant"),
            ("peat_moss_floating_bog_mat", "Floating Sphagnum Quaking Bog Turf Island (2x2)", "Thảm Rêu Than Bùn Nổi Rung Rinh (2x2)", [2, 2], "plant"),
        ]),
    ]
    for sub_id, concepts in cat18_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_10:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid" if fprint[0] >= 2 else "ground_contact", True, "transparent",
                    "gather_herbs" if "understory" in sub_id or "fungus" in c_slug else "inspect",
                    f"Primeval forest ecological feature ({c_name}).", False, mat, cult, prompt,
                    asset_type="flora"
                ))

    # =========================================================================
    # 19. cliffs_caves_and_highlands (180 assets: 5 subcats * 36: 4*9)
    # =========================================================================
    cid = "cliffs_caves_and_highlands"
    cat19_subs = [
        ("limestone_cliff_and_escarpment", [
            ("vertical_stratified_cliff_face", "Vertical Stratified Limestone Cliff Face (3x2)", "Vách Đá Vôi Đứng Phân Tầng Rõ Nét (3x2)", [3, 2], "stone"),
            ("hanging_rock_shelf_escarpment", "Overhanging Rock Shelf Escarpment Ledge (3x1)", "Gờ Vách Đá Nhô Ra Lơ Lửng (3x1)", [3, 1], "stone"),
            ("steep_chalk_scree_gully", "Steep Ravine Chalk Chasm Cutting (2x2)", "Hẻm Vực Núi Đá Vôi Trắng Dốc Đứng (2x2)", [2, 2], "stone"),
            ("natural_rock_arch_portal", "Natural Weathered Rock Bridge Arch (3x2)", "Vòm Cổng Cầu Đá Tự Nhiên (3x2)", [3, 2], "stone"),
        ]),
        ("boulder_fields_and_scree", [
            ("glacial_erratic_granite_boulder", "Giant Glacial Erratic Granite Boulder (2x2)", "Khối Đá Tảng Hoa Cương Lớn Tự Nhiên (2x2)", [2, 2], "stone"),
            ("weathered_granite_tor_stack", "Weathered Mountain Granite Tor Outcrop (3x2)", "Đỉnh Núi Đá Tảng Xếp Chồng Tor (3x2)", [3, 2], "stone"),
            ("loose_talus_scree_slope", "Unstable Sloping Talus Rock Scree Slide (2x2)", "Dốc Đá Vụn Sụt Lở Bấp Bênh (2x2)", [2, 2], "stone"),
            ("river_cataract_boulder_cluster", "Whitewater River Rapids Torrent Boulders (2x2)", "Cụm Đá Tảng Giữa Dòng Nước Xiết (2x2)", [2, 2], "stone"),
        ]),
        ("cavern_and_grotto_entrances", [
            ("dark_limestone_cave_mouth", "Dark Limestone Cavern Gaping Mouth (3x2)", "Miệng Hang Động Đá Vôi Tối Sâu (3x2)", [3, 2], "stone"),
            ("subterranean_river_sink_hole", "Disappearing River Underground Sinkhole (2x2)", "Hố Sụt Nước Ngầm Nuốt Dòng Suối (2x2)", [2, 2], "stone"),
            ("hidden_fissure_cleft_opening", "Narrow Concealed Cliff Fissure Crevice (2x1)", "Khe Nứt Vách Đá Hẹp Bí Ẩn (2x1)", [2, 1], "stone"),
            ("stalactite_fringed_grotto_portal", "Stalactite-Fringed Sacred Mountain Grotto (2x2)", "Hang Thạch Nhũ Nhỏ Rủ Tự Nhiên (2x2)", [2, 2], "stone"),
        ]),
        ("highland_moor_and_heather", [
            ("ancient_stone_cairn_waymarker", "Stacked Stone Highland Trail Cairn Monument (1x1)", "Đống Đá Xếp Đánh Dấu Đường Vùng Cao (1x1)", [1, 1], "stone"),
            ("sweeping_purple_heather_mound", "Blooming Purple Bell Heather Moorland Hummock (2x2)", "Gò Đất Thạch Nam Tím Bạt Ngàn (2x2)", [2, 2], "plant"),
            ("highland_standing_megalith_monolith", "Ancient Prehistoric Standing Stone Monolith (1x2)", "Cột Đá Cự Thạch Đứng Thời Tiền Sử (1x2)", [1, 2], "stone"),
            ("cut_peat_trench_highland_turf", "Deep Hand-Cut Peat Extraction Trench (2x1)", "Mương Đào Than Bùn Sâu Vùng Cao (2x1)", [2, 1], "earth"),
        ]),
        ("waterfalls_and_mountain_brooks", [
            ("roaring_gorge_waterfall_drop", "Roaring Mountain Waterfall Cascade Plunge (3x3)", "Thác Nước Hẻm Núi Đổ Ầm Ầm (3x3)", [3, 3], "water"),
            ("cascading_mountain_stream_pool", "Terraced Rocky Stream Pools with Splashes (2x2)", "Hồ Bậc Thang Suối Núi Nước Trong (2x2)", [2, 2], "water"),
            ("mossy_spray_wet_rock_ledges", "Lush Wet Spray Rock Ledges with Liverworts (2x1)", "Gờ Đá Ướt Đẫm Bụi Nước Bám Rêu (2x1)", [2, 1], "stone"),
            ("mountain_brook_chattering_rapids", "Pebbled Chattering Mountain Brook Rapids (2x1)", "Dòng Suối Núi Róc Rách Đầy Sỏi Đá (2x1)", [2, 1], "water"),
        ]),
    ]
    for sub_id, concepts in cat19_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_9:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "enter_cavern" if "cave" in sub_id or "cavern" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Highland geology & water feature ({c_name}).", False, mat, cult, prompt,
                    asset_type="structure" if fprint[0] >= 3 else "prop"
                ))

    # =========================================================================
    # 20. alchemy_herbalism_and_occult (130 assets: 5 subcats * 26: 2*13)
    # =========================================================================
    cid = "alchemy_herbalism_and_occult"
    cat20_subs = [
        ("alchemical_apparatus", [
            ("glass_retort_and_alembic_bench", "Alchemical Distillation Bench with Glass Alembic (2x1)", "Bàn Chưng Cất Bình Thủy Tinh Giả Kim (2x1)", [2, 1], "glass"),
            ("athanor_philosophical_furnace", "Brick Athanor Slow-Combustion Alchemical Oven (2x1)", "Lò Lửa Chậm Athanor Luyện Kim Thuật (2x1)", [2, 1], "brick"),
        ]),
        ("herbalist_workstation", [
            ("apothecary_dried_herb_press_table", "Apothecary Wooden Screw Herb Press & Mortars (2x1)", "Bàn Ép Thuốc & Cối Giã Thảo Dược (2x1)", [2, 1], "wood"),
            ("hanging_mandrake_belladonna_bundle", "Ceiling Bundles of Drying Mandrake & Belladonna (2x1)", "Bó Rễ Cây Nhân Lạc & Cà Độc Dược Treo Phơi (2x1)", [2, 1], "plant"),
        ]),
        ("astrology_and_study", [
            ("brass_armillary_sphere_astrolabe", "Brass Rotating Armillary Sphere on Carved Stand (1x1)", "Quả Cầu Hỗn Thiên Bằng Đồng Thau (1x1)", [1, 1], "brass"),
            ("celestial_parchment_scroll_lectern", "Scholars Carved Oak Lectern with Star Charts (1x1)", "Giá Đọc Sách Chứa Biểu Đồ Sao Bằng Da (1x1)", [1, 1], "wood"),
        ]),
        ("witch_and_folklore_dwellings", [
            ("stilt_swamp_witch_hovel", "Bog Stilt Witch Hut with Animal Skulls (2x2)", "Nhà Chòi Phù Thủy Đầm Lầy Dựng Cọc (2x2)", [2, 2], "wood"),
            ("boiling_iron_cauldron_brazier", "Bubbling Green Slime Iron Cauldron on Embers (1x1)", "Vạc Sắt Nấu Nước Độc Sủi Bọt (1x1)", [1, 1], "iron"),
        ]),
        ("plague_doctor_and_leper_ward", [
            ("plague_doctor_carbolic_fumigation_pan", "Aromatic Herb Fumigation Brazier Pan (1x1)", "Chảo Xông Khói Thảo Dược Trừ Dịch Bệnh (1x1)", [1, 1], "iron"),
            ("leper_isolation_warning_bell_pole", "Leper Lazar House Warning Wooden Clapper Post (1x1)", "Cột Treo Chuông Cảnh Báo Trại Người Hủi (1x1)", [1, 1], "wood"),
        ]),
    ]
    for sub_id, concepts in cat20_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_13:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "brew_potion" if "alchem" in sub_id or "herb" in sub_id else "inspect"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "solid", True, "transparent",
                    verb, f"Medieval alchemy, herbalism and folklore facility ({c_name}).", False, mat, cult, prompt
                ))

    # =========================================================================
    # 21. destructibles_containers_and_loot (190 assets: 5 subcats * 38: 2*19)
    # =========================================================================
    cid = "destructibles_containers_and_loot"
    cat21_subs = [
        ("chests_and_strongboxes", [
            ("iron_banded_oak_treasure_chest", "Heavy Iron-Banded Oak Treasure Chest (1x1)", "Rương Báu Gỗ Sồi Bọc Đai Sắt Nặng (1x1)", [1, 1], "wood"),
            ("brass_hasp_merchant_coffer", "Carved Merchant Money Coffer with Brass Hasp (1x1)", "Hòm Tiền Thương Nhân Có Khóa Đồng (1x1)", [1, 1], "wood"),
        ]),
        ("barrels_casks_and_tuns", [
            ("stout_oak_ale_barrel", "Heavy Staved Oak Ale Barrel with Iron Hoops (1x1)", "Thùng Gỗ Sồi Đựng Bia Đai Sắt (1x1)", [1, 1], "wood"),
            ("sealed_pitch_tar_powder_keg", "Pitch-Sealed Powder and Tar Keg (1x1)", "Thùng Gỗ Nhỏ Chứa Hắc Ín Kín Miệng (1x1)", [1, 1], "wood"),
        ]),
        ("sacks_urns_and_baskets", [
            ("tied_burlap_grain_flour_sack", "Tied Coarse Burlap Grain Flour Sack (1x1)", "Bao Tải Vải Bố Buộc Chặt Đựng Bột Mì (1x1)", [1, 1], "cloth"),
            ("woven_wicker_market_produce_hamper", "Sturdy Woven Willow Produce Hamper Basket (1x1)", "Giỏ Mây Đan Đựng Nông Sản (1x1)", [1, 1], "wood"),
        ]),
        ("pottery_and_domestic_loot", [
            ("glazed_earthenware_cider_jug", "Glazed Brown Stoneware Cider Flagon Jug (1x1)", "Bình Rượu Gốm Men Nâu Có Quai (1x1)", [1, 1], "ceramic"),
            ("silver_pennies_scattered_coin_pile", "Spilled Velvet Pouch with Silver Pennies (1x1)", "Túi Nhung Đổ Tràn Đồng Xu Bạc (1x1)", [1, 1], "silver"),
        ]),
        ("breakables_and_debris", [
            ("stackable_wooden_cargo_crate", "Rough Timber Cargo Crate with Rope Handles (1x1)", "Thùng Gỗ Kiện Hàng Có Quai Dây Thừng (1x1)", [1, 1], "wood"),
            ("shattered_terracotta_amphora_shards", "Broken Terracotta Oil Vessel and Shards (1x1)", "Mảnh Vỡ Bình Gốm Đất Nung Đựng Dầu (1x1)", [1, 1], "ceramic"),
        ]),
    ]
    for sub_id, concepts in cat21_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_19:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down view of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "ground_contact", False, "transparent",
                    "open_chest" if "chest" in c_slug or "coffer" in c_slug else "break_container",
                    f"Destructible container & loot drop ({c_name}).", True, mat, cult, prompt,
                    asset_type="container"
                ))

    # =========================================================================
    # 22. creatures_denizens_and_livestock (210 assets: 5 subcats * 42: 6*7)
    # =========================================================================
    cid = "creatures_denizens_and_livestock"
    cat22_subs = [
        ("serfs_peasants_and_labourers", [
            ("plowman_serf_with_wooden_goad", "Field Plowman Peasant with Ox Goad", "Nông Nô Cày Ruộng Cầm Gậy Đuổi Bò", [1, 1], "flesh"),
            ("milkmaid_with_wooden_pail", "Village Milkmaid in Apron Carrying Pail", "Cô Gái Vắt Sữa Đeo Tạp Dề Xách Xô Gỗ", [1, 1], "flesh"),
            ("woodcutter_with_felling_axe", "Hardy Woodcutter with Felling Axe on Shoulder", "Thợ Đốn Củi Vác Rìu Trên Vai", [1, 1], "flesh"),
            ("master_village_blacksmith", "Soot-Stained Blacksmith with Leather Apron & Tongs", "Bác Thợ Rèn Da Sạm Bụi Than Đeo Tạp Dề Da", [1, 1], "flesh"),
            ("flour_covered_village_miller", "White Flour-Dusted Miller in Cap", "Bác Thợ Xay Phủ Đầy Bụi Bột Trắng", [1, 1], "flesh"),
            ("tavern_serving_wench_with_ale", "Tavern Serving Maid Carrying Pewter Tankards", "Cô Phục Vụ Quán Rượu Bưng Khay Cốc Thiếc", [1, 1], "flesh"),
        ]),
        ("burghers_merchants_and_clerics", [
            ("prosperous_guild_merchant", "Prosperous Wool Guild Merchant in Fur Mantle", "Thương Nhân Phường Hội Len Dạ Áo Choàng Lông", [1, 1], "flesh"),
            ("franciscan_friar_in_brown_robe", "Franciscan Friar in Hooded Habit and Rope Cincture", "Tu Sĩ Dòng Phanxicô Áo Nâu Buộc Thừng", [1, 1], "flesh"),
            ("monastery_abbot_with_pastoral_crozier", "Monastery Abbot with Gilded Pastoral Crozier", "Viện Trưởng Tu Viện Cầm Gậy Mục Tử Mạ Vàng", [1, 1], "flesh"),
            ("chancery_legal_notary_scribe", "Court Notary Scribe with Inkpot and Ledger", "Thư Ký Công Chứng Cầm Bình Mực & Sổ Sách", [1, 1], "flesh"),
            ("town_crier_with_handbell", "Town Crier in Livery with Brass Handbell", "Người Đọc Lệnh Thị Trấn Rung Chuông Đồng", [1, 1], "flesh"),
            ("itinerant_pilgrim_with_scallop_shell", "Pilgrim with Staff and Santiago Scallop Shell", "Khách Hành Hương Cầm Gậy Gắn Vỏ Sò", [1, 1], "flesh"),
        ]),
        ("guards_soldiers_and_knights", [
            ("city_watch_halberdier_guard", "City Watch Halberdier in Kettle Hat and Gambeson", "Lính Canh Thành Cầm Kích Đội Mũ Sắt", [1, 1], "flesh"),
            ("veteran_pavise_crossbowman", "Veteran Crossbowman with Pavise and Quiver", "Xạ Thủ Nỏ Dạn Dày Có Khiên Chắn Lưng", [1, 1], "flesh"),
            ("welsh_longbowman_in_leather", "Welsh Longbowman in Brigandine with Yew Bow", "Cung Thủ Cung Dài Xứ Wales Áo Giáp Đinh", [1, 1], "flesh"),
            ("man_at_arms_in_chainmail_hauberk", "Heavy Man-at-Arms with Kite Shield and Arming Sword", "Binh Sĩ Thiết Giáp Mang Khiên & Kiếm", [1, 1], "flesh"),
            ("plate_armored_knightly_champion", "Knight Champion in Full White Plate Armor with Greatsword", "Kỵ Sĩ Vô Địch Giáp Tấm Toàn Thân Kiếm Lớn", [1, 1], "flesh"),
            ("mounted_feudal_sergeant", "Mounted Sergeant on Armored Courser with Lance", "Kỵ Binh Phong Kiến Cưỡi Ngựa Cầm Giáo", [2, 2], "flesh"),
        ]),
        ("outlaws_and_highwaymen", [
            ("hooded_forest_poacher_archer", "Lincoln Green Hooded Poacher with Shortbow", "Thợ Săn Trộm Rừng Áo Choàng Xanh Cầm Cung", [1, 1], "flesh"),
            ("masked_roadside_highwayman", "Masked Highwayman with Dagger and Flocked Cloak", "Kẻ Cướp Đường Đeo Mặt Nạ Cầm Dao Găm", [1, 1], "flesh"),
            ("ruthless_bandit_cutpurse", "Slum Cutpurse Thief with Concealed Stiletto", "Tên Móc Túi Giấu Dao Găm Nhọn Trong Người", [1, 1], "flesh"),
            ("mercenary_brabançon_routier", "Scarred Routier Mercenary in Scalemail with Battleaxe", "Lính Đánh Thuê Brabant Giáp Vảy Cầm Rìu Chiến", [1, 1], "flesh"),
            ("outlaw_gang_chieftain", "Fierce Outlaw Captain in Looted Fur & Mail", "Thủ Lĩnh Sơn Tặc Mặc Giáp Cướp Đoạt", [1, 1], "flesh"),
            ("camp_follower_scavenger", "Battlefield Scavenger Looting Fallen Arms", "Kẻ Hôi Của Bãi Chiến Trường Nhặt Nhạnh Vũ Khí", [1, 1], "flesh"),
        ]),
        ("horses_draft_and_livestock", [
            ("heavy_shire_draft_plow_horse", "Heavy Dapple Shire Draft Horse with Bridle (2x2)", "Ngựa Kéo Xe Nặng Shire Đeo Dây Cương (2x2)", [2, 2], "flesh"),
            ("armored_destrier_warhorse", "Armored Caparisoned Knight Destrier Warhorse (2x2)", "Chiến Mã Hiệp Sĩ Khoác Giáp Vải Phù Hiệu (2x2)", [2, 2], "flesh"),
            ("castrated_heavy_plow_ox", "Heavy Muscular Castrated Plow Ox with Horns (2x1)", "Con Bò Đực Cày Ruộng Khỏe Khoắn Có Sừng (2x1)", [2, 1], "flesh"),
            ("spotted_milch_dairy_cow", "Spotted Horned Dairy Cow with Bell (2x1)", "Bò Sữa Có Sừng Đeo Chuông Cổ (2x1)", [2, 1], "flesh"),
            ("wooly_merino_ram_with_horns", "Curled-Horn Wooly Ram with Thick Fleece (1x1)", "Cừu Đực Sừng Cong Lông Dày Xù (1x1)", [1, 1], "flesh"),
            ("boarhound_mastiff_guard_dog", "Broad-Chested Mastiff Guard Dog with Spiked Collar (1x1)", "Chó Ngao Săn Lợn Rừng Đeo Vòng Gai (1x1)", [1, 1], "flesh"),
        ]),
    ]
    for sub_id, concepts in cat22_subs:
        for c_slug, c_name, c_vn, fprint, mat in concepts:
            for v_slug, v_name, v_vn, cult, desc in variants_7:
                slug = f"{c_slug}_{v_slug}"
                name = f"{v_name} {c_name}"
                vn = f"{c_vn} ({v_vn})"
                prompt = (
                    f"2D orthographic top-down character sprite of {name.lower()}, {desc}, "
                    f"gouache hand-painted anime style, ink contours, transparent background."
                )
                verb = "interact_animal" if "livestock" in sub_id or "horse" in sub_id else "talk_to"
                items.append(make_asset(
                    cid, slug, name, vn, sub_id, fprint, "ground_contact", True, "transparent",
                    verb, f"Medieval human denizen or draft beast ({c_name}).", True, mat, cult, prompt,
                    asset_type="denizen"
                ))

    return items
