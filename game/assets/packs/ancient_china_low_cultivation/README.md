# Ancient Chinese Mortal World Cultivation Asset Pack
**ID**: `ancient_china_low_cultivation`  
**World Tier**: Mortal World (Phàm Nhân Giới / Cửu Châu) — Full 9 Realms Ladder (Qi Refining -> Tribulation Crossing)  
**Total Macro-Domains**: 25  
**Total Planned Categories**: 426  
**Architecture Standard**: `Domain` → `Sub-Domain` → `Detail Asset` → `Variants`

---

## 1. Core World Tier: The 9 Mortal Realms in Chaos World
In this repository, the Mortal Tier encompasses all 9 foundational realms before ascension into the Spirit/Immortal realms:
1. **Qi Refining** (Luyện Khí / 练气) — Novice body circulation, mundane weapons, rural chores, low-tier spirit beasts.
2. **Foundation Establishment** (Trúc Cơ / 筑基) — True fire ignition, basic flying swords, outer disciple missions, pill trials.
3. **Core Formation** (Kết Đan / 结丹) — Golden core condensation, magical treasures, sect inner courts, spirit auctions.
4. **Nascent Soul** (Nguyên Anh / 元婴) — Spirit teleportation, ancient cave abodes, sect elder councils, domain auras.
5. **Spirit Transformation** (Hóa Thần / 化神) — Domain perception, peak mortal ancestors, continent roaming, void fissures.
6. **Void Refinement** (Luyện Hư / 炼虚) — Spatial comprehension, high-altitude floating peaks, celestial sky islands.
7. **Body Integration** (Hợp Thể / 合体) — Flesh and soul fusion, colossal war puppets, ancient battlefields, beast tides.
8. **Great Ascension** (Đại Thừa / 大乘) — Mortal realm apex, trans-continental teleport arrays, ancestral inheritances.
9. **Tribulation Crossing** (Độ Kiếp / 渡劫) — Nine-Heaven lightning tribulation, Dengtian ascension staircases to the heavens.

---

## 2. 4-Tier Hierarchy Architecture

```
[Domain] (25 Macro-Domains)
   └── [Sub-Domain] (Specific functional or environmental cluster)
         └── [Detail Asset] (Base archetype with geometry, footprint & collisions)
               └── [Variants] (State variations reacting dynamically to world conditions)
```

### The Living Map Principle
A cultivation world map must never feel static or painted once. An asset changes its visual presentation, particle attachments, and collision/interactive footprint dynamically depending on:
- **Time of Day & Sun Position** (Dawn mist, Noon blaze, Dusk shadows, Midnight Yin hour)
- **Four Seasons** (Spring blossom, Summer monsoon, Autumn decay, Winter snow/frost)
- **Dynamic Weather** (Clear sky, Rain downpour, Snow blizzard, Miasma fog, Tribulation lightning)
- **Spiritual Leyline & Corruption** (Pure spiritual Qi, Baleful Yin miasma, Scorched earth, Flooded water)
- **Water & Tide Level** (Low tide exposed silt, Normal flow, Monsoon flood submergence)
- **Structural Integrity & Damage** (Pristine 100%, Weathered 75%, Breached 35%, Ruined Rubble 0%)
- **Rotations & Orientations** (4-way / 8-way facings for isometric perspective)
- **Settlement Alertness** (Bustling market day, Night lockdown, Wartime sect defense)
- **Creature Stances & Ecology** (Grazing, Hunting, Alert, Combat, Wounded, Sleeping, Carcass, Mount)
- **Atmospheric VFX Overlays** (Floating flower petals, drifting snow, spiritual motes, barrier domes)

---

## 3. The 25 Complete Macro-Domains

| # | Domain Identifier | Domain Name (En / Vi / Zh) | Categories | Core Scope |
|---|---|---|:---:|---|
| **1** | `terrain_and_geology` | Terrains & Geological Formations (Địa Hình & Thổ Nhưỡng / 地形地质) | **26** | Loess plateaus, karst spires, Danxia red crags, bone earth, scree. |
| **2** | `flora_and_spirit_plants` | Natural Flora & Spiritual Plants (Linh Thảo & Tiên Mộc / 灵草仙木) | **28** | Iron bamboo, ancient pines, blood ginseng, peach wood, spirit rice. |
| **3** | `water_and_springs` | Water Systems & Spiritual Springs (Thủy Hệ & Linh Tuyền / 水系灵泉) | **20** | Mountain brooks, low-grade spirit springs, frigid Yin pools, canals. |
| **4** | `hazards_and_phenomena` | Environmental Hazards & Phenomena (Khí Hậu & Dị Tượng / 气候异象) | **20** | Five-poison miasmas, cloud seas, ghost mist, lightning zones. |
| **5** | `mortal_and_jianghu` | Mortal Settlements & Jianghu (Phàm Nhân Thôn Trấn & Giang Hồ / 凡人城邑) | **32** | Thatched cottages, magistrate courts, inns, escort agencies, martial halls. |
| **6** | `sect_facilities_and_dwellings` | Cultivation Sect Facilities & Dwellings (Tông Môn Cơ Sở & Động Phủ / 宗门设施) | **30** | Sect gates, barracks, pill rooms, forge halls, scripture towers, Dongfu. |
| **7** | `religious_sanctuaries` | Daoist, Buddhist & Folk Religious Sites (Đạo Quán, Phật Tự & Dân Gian Miếu / 宗教场所) | **26** | Mountain hermitages, Maoshan altars, relic pagodas, Earth God shrines. |
| **8** | `crypts_tombs_and_ruins` | Crypts, Tombs & Ancient Ruins (Cổ Mộ & Di Tích / 陵墓古迹) | **22** | Tumulus tombs, terracotta pits, mercury trenches, hanging coffins. |
| **9** | `fauna_and_spirit_beasts` | Low-Realm Fauna & Spirit Beasts (Yêu Thú, Linh Thú & Sơn Hải Kinh / 妖兽灵兽) | **36** | Spirit wolves, iron hawks, cave pythons, Jiangshi zombies, Shan Hai beasts. |
| **10** | `artifacts_and_paraphernalia` | Cultivation Artifacts & Paraphernalia (Pháp Bảo, Trận Pháp & Khí Cụ / 法宝器物) | **28** | Wind-skiffs, cauldrons, flying swords, paper talismans, Bagua mirrors. |
| **11** | `evil_sects_and_demonic` | Evil Sects & Demonic Cultivation (Ma Đạo Tông Môn & Tà Tu / 魔道宗门) | **12** | Corpse Yin pits, Ten Thousand Soul banners, blood demon altars, Gu pits. |
| **12** | `mining_and_metallurgy` | Mining, Metallurgy & Mineral Extraction (Khai Khoáng & Luyện Kim / 采矿冶炼) | **12** | Deep shafts, timber shoring, ore carts, stamping mills, blast furnaces. |
| **13** | `races_and_tribal_enclaves` | Non-Human Races, Bloodlines & Enclaves (Dị Tộc, Yêu Tộc & Huyết Mạch / 种族异族) | **12** | Stoneborn, Emberblood, Tidecaller merfolk, Fox clan, Wood spirits, Asura. |
| **14** | `floating_terrains_and_sky_crags` | Floating Terrains & Celestial Sky Crags (Huyền Không Phù Đảo / 悬空浮岛) | **10** | Floating islands, iron chain sky-bridges, cloud waterfalls, magnetic peaks. |
| **15** | `underwater_and_abyssal_realms` | Underwater Realms & Dragon Palaces (Thủy Hạ Thế Giới & Thủy Cung / 水下世界) | **10** | Crystal dragon palaces, fluorescent coral forests, trenches, air bubbles. |
| **16** | `underground_abyss_and_caverns` | Underground Abyss & Subterranean Depths (Địa Hạ Thế Giới & Cửu U / 地底深渊) | **10** | Giant mushroom caverns, stalactite forests, magma rivers, nether lakes. |
| **17** | `peak_mortal_and_tribulation` | Peak Mortal Sects & Tribulation Platforms (Đỉnh Phong Tông Môn & Độ Kiếp / 渡劫飞升) | **10** | Elder seclusion grottos, Nine-Heaven tribulation platforms, grand sect arrays. |
| **18** | `atmospheric_vfx_and_phenomena` | Atmospheric VFX, Seasonal Overlays & Particles (Khí Quyển VFX & Linh Lực / 天气特效) | **12** | Falling blossoms, snow blizzards, rain ripples, Qi motes, barrier domes. |
| **19** | `secret_realms_and_grotto_heavens`| Secret Realms, Ancient Grottos & Inheritances (Bí Cảnh & Động Thiên Phúc Địa / 秘境洞天) | **10** | Sealed ancient hermit caves, Sword-Intent cliffs, sky fissures, trial towers. |
| **20** | `cultivation_commerce_and_auctions`| Cultivation Commerce, Auctions & Wandering Caravans (Phường Thị & Đấu Giá / 坊市拍卖) | **10** | Treasure auction houses, black markets, flying skiff caravans, pawn halls. |
| **21** | `world_events_and_calamities` | World Calamities, Beast Tides & War Ruins (Thiên Tai, Thú Triều & Chiến Địa / 浩劫战墟) | **10** | Beast tide wreckage, breached palisades, cratered battlefields, sinkholes. |
| **22** | `body_cultivation_and_tempering` | Body Cultivation & Physical Tempering Grounds (Thể Tu & Đoán Thể / 体修淬体) | **10** | Waterfall impact crags, medicinal bath cauldrons, gravity wells, plum stakes. |
| **23** | `spirit_farming_and_sericulture` | Spirit Farming, Herbal Agriculture & Sericulture (Linh Thực & Tàm Tang / 灵植蚕桑) | **10** | Rain talisman flumes, pest braziers, compost pits, silkworm trays, bee hives. |
| **24** | `elemental_sanctuaries_and_extremes`| Natural Elemental Sanctuaries & Extreme Leylines (Thiên Địa Dị Vật & Cực Địa / 天地极地) | **10** | Heavenly flame rifts, lightning pools, glacial springs, Gangfeng razor gorges. |
| **25** | `dao_companions_and_sanctuary_living`| Dao Companions, Dual Cultivation & Sanctuary Living (Đạo Lữ, Song Tu & Động Phủ / 双修居所) | **10** | Tea pavilions, dual Yin-Yang meditation mats, Guqin terraces, moon gates. |
| **TOTAL** | **25 Macro-Domains** | **Exhaustive Living Xianxia Mortal World Master Taxonomy** | **426** | Complete coverage across all 9 mortal realms, factions, and nature. |

---

## 4. Deep Breakdown of Domains 18 to 25

### Domain 18: Atmospheric VFX, Seasonal Overlays & Particles (`atmospheric_vfx_and_phenomena`)
1. `VFX-01` Spring Peach Blossom & Willow Catkin Drift (Đào Hoa Liễu Hư Phiêu Lạc / 桃花柳絮随风舞)
2. `VFX-02` Autumn Ginkgo & Crimson Maple Leaf Swirl (Ngân Hạnh Phong Diệp Toàn Phong / 银杏红枫旋风)
3. `VFX-03` Winter Gentle Snow Flurry & Blizzard Streaks (Băng Tuyết Cuồng Phong Lạc Tiết / 漫天飞雪狂风)
4. `VFX-04` Summer Monsoon Rain Sheet & Ground Splash Ripples (Bạo Vũ Như Chú Thủy Hoa / 暴雨如注地面溅水)
5. `VFX-05` Ascending Cyan/Gold Spiritual Qi Particle Motes (Thanh Kim Linh Quang Thăng Đằng / 升腾灵光粒子)
6. `VFX-06` Summer Reedbed & Water Pond Fireflies (Hạ Dạ Đầm Trạch Huỳnh Hỏa Trùng / 夏夜水泽萤火虫)
7. `VFX-07` Baleful Yin-Qi & Cemetery Black Smoke Tendrils (Cửu U Âm Sát Hắc Yên Ti / 阴煞地气黑烟丝)
8. `VFX-08` Toxic Swamp Miasma Spore Bubbles (Ngũ Độc Chướng Khí Huỳnh Khí Bào / 毒沼绿色气泡瘴气)
9. `VFX-09` Translucent Hexagonal Array Barrier Dome (Hộ Sơn Trận Pháp Quang Mạc / 六角蜂窝护宗光幕)
10. `VFX-10` Ground Bagua Runes Inscription Glow (Địa Diện Bát Quái Lưu Quang Trận / 八卦阵图地面流光)
11. `VFX-11` Spatial Void Distortion Heat Shimmer Ripple (Hư Không Liệt Phùng Khí Lãng / 空间扭曲涟漪)
12. `VFX-12` Nine-Heaven Tribulation Thundercloud with Lightning Serpents (Độ Kiếp Lôi Vân Điện Xà / 渡劫劫云雷蛇狂舞)

### Domain 19: Secret Realms, Ancient Grottos & Inheritances (`secret_realms_and_grotto_heavens`)
1. `SEC-R01` Ancient Hermit Sealed Cave Abode (Cổ Tu Sĩ Phong Ấn Động Phủ / 蔓藤枯石古修遗府)
2. `SEC-R02` Dao Enlightenment Sword-Intent Cliff (Vạn Niên Kiếm Ý Ngộ Đạo Nhai / 万载剑痕悟道崖)
3. `SEC-R03` Secret Realm Sky Fissure Portal (Bí Cảnh Thời Không Liệt Phùng / 秘境虚空传送裂口)
4. `SEC-R04` Ancient Nine-Tier Trial Tower (Cửu Trọng Thí Luyện Tháp / 远古九重试炼石塔)
5. `SEC-R05` Meditating Bone Inheritance Master (Bạch Cốt Chân Truyền Tọa Hóa / 枯骨真传玉简遗骸)
6. `SEC-R06` Grotto-Heaven Spiritual Medicine Pocket (Động Thiên Phúc Địa Dược Viên / 洞天药圃封闭灵田)
7. `SEC-R07` Ancient Pill Recipe Monument Stele (Thái Cổ Đan Phương Tàn Phá Bi / 太古丹方残断石碑)
8. `SEC-R08` Ancient Five-Element Restriction Gate (Ngũ Hành Phong Ấn Cấm Chế Môn / 五行禁制流光石门)
9. `SEC-R09` Giant Divine Beast Skeleton Bridge (Thượng Cổ Thần Thú Cốt Kiều / 巨兽脊骨天堑桥梁)
10. `SEC-R10` Heavenly Book Floating Jade Pedestal (Thiên Thư Huyền Không Ngọc Thai / 天书悬浮传功玉台)

### Domain 20: Cultivation Commerce, Auctions & Wandering Caravans (`cultivation_commerce_and_auctions`)
1. `COM-01` Immortal Treasure Grand Auction Hall (Đấu Giá Đại Điện / 万宝巨型拍卖大殿)
2. `COM-02` Underground Cultivator Black Market Stalls (Hắc Thị Bí Mật Than Vị / 阴暗黑市斗笠地摊)
3. `COM-03` Traveling Flying-Skiff Merchant Caravan (Vân Du Thương Thuyền / 云游飞舟泊桩商埠)
4. `COM-04` Spiritual Treasure Appraisal Pavilion (Giám Bảo Các / 法宝灵物鉴宝台)
5. `COM-05` Spirit Stone Bank & Escrow Vault (Thiên Thần Ngân Hàng Tiền Trang / 灵石庄通商钱庄)
6. `COM-06` Exotic Beast Mount Trading Corral (Linh Thú Tọa Kỵ Giao Dịch Trường / 灵兽驯化交易围栏)
7. `COM-07` Bulk Herb & Pill Wholesale Warehouse (Linh Dược Bách Hóa Thương Khố / 宗门大宗药材栈房)
8. `COM-08` Rogue Cultivator Flea Market Ground Cloth (Tán Tu Bãi Than Bạch Bố / 散修置换草席地摊)
9. `COM-09` Bounty Hunter & Mercenary Hall (Tiêu Cục Tán Tu Trảm Yêu Đường / 斩妖除魔赏金公会)
10. `COM-10` Smuggler Hidden Waterway Pier (Thủy Vận Tư Vận Ám Đầu / 水道走私黑水暗埠)

### Domain 21: World Calamities, Beast Tides & War Ruins (`world_events_and_calamities`)
1. `CAL-01` Beast Tide Breached City Gate (Thú Triều Xung Phá Thành Môn / 狂暴兽潮撞裂城门)
2. `CAL-02` Smashed Iron Palisade & Claw Gouges (Cự Thú Trảo Ngân Thiết Sách / 碎裂鹿角巨爪撕裂痕)
3. `CAL-03` Beast Corpse Slaughter Trench (Yêu Thú Thi Hài Đống / 万妖伏诛积尸大坑)
4. `CAL-04` Righteous-Demonic Divine Crater Battlefield (Chính Ma Đại Chiến Thần Hãm / 大能法术轰击巨坑)
5. `CAL-05` Fallen Giant Flying Sword Wreckage (Đoạn Liệt Cự Đại Phi Kiếm / 斜插大地万年断残剑)
6. `CAL-06` Collapsed Mine Shaft & Trapped Timbering (Khoáng Nạn Băng Tháp Hãm / 坑道垮塌木架碎裂处)
7. `CAL-07` Heavenly Tribulation Scorched Glass Earth (Thiên Hỏa Phần Thiêu Thao / 劫火燎原琉璃焦坑)
8. `CAL-08` Depleted Leyline Dried Sinkhole (Linh Mạch Khô Kiệt Thiên Khanh / 灵气抽干龟裂干涸坑)
9. `CAL-09` Desecrated Ancestor Tablet Shrine Ruins (Phá Bại Tông Miếu Đoạn Bích / 战火残毁祖师宗祠)
10. `CAL-10` Ambushed Escort Wagon Caravan Ruins (Bị Kiếp Tiêu Xa Hỏa Thiêu Tàn / 遇袭劫掠起火断车)

### Domain 22: Body Cultivation & Physical Tempering Grounds (`body_cultivation_and_tempering`)
1. `BOD-01` Waterfall Impact Crag Boulder (Thác Nước Luyện Thể Cự Thạch / 飞瀑轰顶炼体石)
2. `BOD-02` Medicinal Herb Bath Bronze Cauldron (Dược Dục Đồng Đỉnh / 滚沸药浴淬体鼎)
3. `BOD-03` Gravity-Inversion Runic Well Pit (Trọng Lực Thâm Tỉnh / 百倍重力沉石井)
4. `BOD-04` Plum Blossom Iron Agility Stakes (Mai Hoa Thiết Trụ Trận / 绝壁梅花铁桩阵)
5. `BOD-05` Primordial Beast Blood Quenching Basin (Thối Thể Huyết Trì / 远古大妖血淬池)
6. `BOD-06` Iron Sand Punching & Striking Pots (Thiết Sa Chưởng Cương / 烈火铁砂淬掌缸)
7. `BOD-07` Heavy Stone Yokes & Millstone Weights (Huyền Thiết Thạch Tỏa Giá / 玄铁千斤石锁架)
8. `BOD-08` Mountain-Cleaving Blade Practice Rock (Trảm Nhai Thí Lực Nham / 裂山断石试力岩)
9. `BOD-09` Nine-Dragon Wooden Agility Slalom Log (Cửu Long Khổ Luyện Mộc / 九龙穿林翻腾木)
10. `BOD-10` Frigid Ice-Needle Flesh-Tempering Slab (Thấu Cốt Hàn Băng Thạch / 极寒玄冰透骨床)

### Domain 23: Spirit Farming, Herbal Agriculture & Sericulture (`spirit_farming_and_sericulture`)
1. `FAR-01` Talisman Rain-Calling Irrigation Flume (Linh Vũ Trận Mộc Cừ / 灵雨符阵引水槽)
2. `FAR-02` Spirit Insect Pest Repelling Brazier (Khu Trùng Linh Huân Lô / 驱蝗逐蛊熏烟炉)
3. `FAR-03` Spirit Beast Compost & Fertilizer Pit (Linh Phì Uẩn Đột Khanh / 灵兽百草沤肥窖)
4. `FAR-04` Runic Warding Straw Scarecrow (Trấn Thú Phù Bù Nhìn / 镇禽诛兽符草人)
5. `FAR-05` Spirit Soil Aeration Tiller & Hoe Rack (Phá Linh Nham Bào Giá / 破岩除草灵锄架)
6. `FAR-06` Golden Silkworm Bamboo Mulberry Shelves (Linh Tàm Trúc Giá / 冰蚕吐丝竹屉架)
7. `FAR-07` Seedling Nursery Cold Frames & Glaze (Linh Chủng Ôn Sàng / 暖玉灵苗育种温床)
8. `FAR-08` Medicinal Root Washing Basin & Troughs (Tẩy Dược Thạch Trì / 洗药石渠剖根台)
9. `FAR-09` Spirit Grain Sun-Drying Woven Baskets (Linh Cốc Sái Ky / 晒谷篾席晾药盘)
10. `FAR-10` Pollinating Spirit Honey Bee Wooden Boxes (Dưỡng Phong Mộc Hạp / 采英灵蜂寄木箱)

### Domain 24: Natural Elemental Sanctuaries & Extreme Leylines (`elemental_sanctuaries_and_extremes`)
1. `ELE-01` Earth-Heart Heavenly Flame Volcanic Rift (Thiên Địa Dị Hỏa Liệt Khúc / 地心异火喷涌谷)
2. `ELE-02` Pure Yang Heavenly Lightning Pool Basin (Thuần Dương Lôi Trì / 九霄神雷引雷池)
3. `ELE-03` Millennial Glacial Frost Bone Spring (Vạn Niên Hàn Băng Khê / 万年玄冰凝髓溪)
4. `ELE-04` Gangfeng Sky-Cleaving Razor Gorge (Cương Phong Hạp Cốc / 九天罡风如刃峡)
5. `ELE-05` Heavy Earth Magnetite Crags & Monoliths (Trọng Thổ Huyền Từ Nham / 玄黄重土元磁岩)
6. `ELE-06` Primeval Mother Tree Emerald Core Hollow (Thanh Mộc Tinh Khí Cổ Thụ / 青木神髓古树心)
7. `ELE-07` Pure Yang Golden Sun Solstice Summit (Thuần Dương Kim Đỉnh / 纯阳金顶朝阳峰)
8. `ELE-08` Sunken Nether Cold Water Abyssal Trench (Huyền Minh Âm Thủy Đàm / 玄冥幽水千丈潭)
9. `ELE-09` Five-Elements Leyline Convergence Vortex (Ngũ Hành Giao Hội Khí Nhãn / 五行逆乱交汇眼)
10. `ELE-10` Profound Heavenly Relic Residual Crater (Huyền Thiên Di Tích Khanh / 玄天残宝坠落坑)

### Domain 25: Dao Companions, Dual Cultivation & Sanctuary Living (`dao_companions_and_sanctuary_living`)
1. `COM-D01` Dao Companion Secluded Tea Gazebo (Đạo Lữ Thính Tùng Đình / 伴侣听风品茗亭)
2. `COM-D02` Dual Meditation Yin-Yang Interlocking Dais (Song Tu Bát Quái Ngọc Đài / 太极阴阳双修台)
3. `COM-D03` Zither & Falling Peach Blossom Terrace (Cầm Âm Lạc Hoa Đài / 抚琴引凤弄花台)
4. `COM-D04` Secluded Inner Courtyard Moon Gate (Nguyệt Môn Hoa Viên / 幽闺通幽月亮门)
5. `COM-D05` Twin Lotuses Intertwined Arch Bridge (Tịnh Đế Liên Hoa Kiều / 并蒂同心连理桥)
6. `COM-D06` Embroidered Silk Canopy Bed Chamber (Hương La Trướng Noãn Sàng / 香罗轻幔暖玉榻)
7. `COM-D07` Wine Warmer Brazier with Celadon Cups (Ôn Tửu Lô Song Bôi / 红泥小炉温酒几)
8. `COM-D08` Carved Jade Wardrobe & Dressing Screen (Ngọc Y Bình Phong / 雕花翠玉更衣屏)
9. `COM-D09` Fragrant Floral Spring Bathing Pool (Phương Thảo Dục Tuyền / 兰汤凝脂芳草池)
10. `COM-D10` Star-Gazing Sky Pavilion & Telescope (Quan Tinh Vọng Nguyệt Đài / 望月观星登仙台)

---

## 5. Expanded Variant Taxonomy by Asset Class

### Class A: Architecture & Structural Buildings
1. **Destruction & Durability**:
   - `pristine`: Fresh lacquer, intact ceramic tiles, perfect structure (100% HP).
   - `weathered`: Moss on foundations, faded paint, aged wood (75% HP).
   - `damaged`: Breached wall holes, shattered roof tiles, scorch marks (35% HP).
   - `ruined_rubble`: Collapsed smoking timber, rubble piles, scavengeable (0% HP).
2. **Time of Day & Illumination**:
   - `day`: Natural sunlight, dark paper lanterns.
   - `night_lit`: Amber candlelight behind paper windows; glowing lanterns.
   - `night_dark`: Abandoned, unlit, shadowed.
3. **Seasons**:
   - `spring`: Peach/cherry blossom drifts on roofs and steps.
   - `summer`: Clean rain runoff, lush ivy creepers.
   - `autumn`: Golden ginkgo/maple leaf drift accumulated on eaves.
   - `winter_snow`: Heavy white snow blankets roofs, hanging icicles.
4. **Settlement Activity / Faction Alertness**:
   - `bustling_peace`: Stalls active, banners unfurled, gates wide open.
   - `night_quiet`: Barred doors, closed shutters, watchman torches.
   - `wartime_lockdown`: Defensive barrier glowing, archers on parapets, barricades up.
5. **Rotations / Facings (4-Way)**:
   - `south` (primary entrance facade), `north` (rear wall), `east` / `west` (flank profiles).

---

### Class B: Natural Terrain & Surface Ground Tiles
1. **Moisture & Weather Surface**:
   - `dry`: Dusty, loose earth, windblown sand.
   - `wet_rain`: Darkened saturated mud, reflective standing puddles.
   - `snow_frost`: Crisp white snow layer, frozen ice patches.
   - `scorched`: Vitrified blackened stone from lightning strikes or fire.
2. **Water Level & Tide State**:
   - `low_tide_ebb`: Water recedes, exposing river silt, clams, and slippery stones.
   - `normal_level`: Standard water line.
   - `monsoon_flood`: Water rises, submerging docks, bridges, and low paths.
3. **Spiritual Leyline Saturation & Corruption**:
   - `pure_spiritual`: Glowing cyan/azure Qi crystals, shimmering mist.
   - `normal_mundane`: Natural earthly soil.
   - `qi_depleted`: Bleached parched soil, cracked clay, dead roots.
   - `yin_corrupted`: Ash-grey dead soil, violet miasma seepage, skull fragments.
4. **Autotile Transitions**: Center fill, 4 edges, 4 corners, Wang tile margins.

---

### Class C: Flora, Trees & Spiritual Plants
1. **Seasonal Cycles (Four Seasons)**:
   - `spring_bloom`: Tender green leaves, budding blossoms, floral fragrance.
   - `summer_canopy`: Dense deep emerald foliage, maximum shade cover.
   - `autumn_harvest`: Golden/crimson leaves, ripe spirit berries and pine nuts.
   - `winter_bare`: Stripped gnarled boughs, snow resting on branches.
2. **Harvesting & Depletion States**:
   - `unharvested_intact`: Ripe, glowing with spiritual vitality, harvestable.
   - `harvested_stump`: Clipped stems or stripped boughs awaiting regrowth timer.
   - `withered_spent`: Drained of Qi, dried brown husk.
3. **Weather Reactions**:
   - `calm`: Gentle idle ambient sway.
   - `gale_wind`: Violent directional sway bending tree trunks.
   - `rain_drenched`: Heavy drooping fronds dripping with moisture.

---

### Class D: Props, Workstations & Interactive Objects
1. **Interactive States**:
   - `idle_dormant`: Cold furnace, unworked anvil, tied wagon.
   - `active_operating`: Roaring blue furnace flames, glowing heated ingot, turning wheel.
   - `closed_locked` vs `open_looted`: Unopened lockbox vs cracked open empty chest.
   - `unlit` vs `lit_burning`: Cold incense burner vs smoldering sandalwood with rising smoke.
2. **Destruction & Salvage**:
   - `intact`: Functional container or barricade obstacle.
   - `broken_shattered`: Smashed ceramic pottery shards, splintered wood slats.
3. **4-Way Rotations**:
   - `south`, `north`, `east`, `west`.

---

### Class E: Living Creatures, Spirit Beasts & Denizens
1. **Behavioral Stances & Life States**:
   - `idle_peaceful`: Neutral breathing, pacing, perched on branch.
   - `alert_suspicious`: Ears perked, bared fangs, scanning territory.
   - `combat_attacking`: Striking pose, biting, charging, breath attack.
   - `wounded_staggered`: Limping, bleeding from flank, cracked horn, damaged wing.
   - `sleeping_resting`: Curled up asleep in den or nest.
   - `dead_carcass`: Fallen on ground, harvestable beast core/meat/hide.
2. **Wildlife Ecological Moods**:
   - `peaceful_grazing`: Herbivores browsing grass in herds.
   - `hunting_stalking`: Carnivores prowling low in the reedbeds.
   - `territorial_warning`: Defensive growls and posture before aggro.
   - `panicked_stampede`: Fleeing in panic from beast tides or heavenly calamities.
3. **Cultivation Evolution & Tier Stages**:
   - `juvenile_cub`: Small, lower stats, companion pet candidate.
   - `adult_wild`: Standard dangerous wild encounter.
   - `mutated_beast_king`: Massive scale, crown horns, glowing elemental crests, boss tier.
   - `tamed_mount`: Fitted with leather harness, saddle, luggage pouches.
4. **Elemental & Bloodline Mutations**:
   - `base_natural`: Standard coat/scales.
   - `demonic_corrupted`: Black baleful miasma smoke, blood-red eyes.
   - `thunder_blessed`: Azure lightning crackling across fur and antlers.
   - `flame_infused`: Blazing fiery mane, smoking molten hooves.
5. **Directional Orientations**: 4-way or 8-way directional sprites.

---

### Class F: Environmental, Floating & Subaquatic Phenomena
1. **Atmospheric Intensity**:
   - `subtle`: Light drifting mist, gentle bubbling spring.
   - `active`: Billowing poison cloud, rushing torrential flow.
   - `calamity`: Violent spatial rift lightning, tidal wave flood surge.
2. **Lighting & Bioluminescence**:
   - `day_natural`: Natural water refraction, soft shadow.
   - `night_phosphorescent`: Cyan glowing deep-sea coral, green cemetery ghost-lights.
3. **Altitude & Medium States**:
   - Floating: `low_drift`, `high_drift`, `chain_tethered`.
   - Subaquatic: `sunlit_shallow`, `abyssal_trench_dark`, `water_warding_bubble`.

---

### Class G: Atmospheric VFX & Particle Emitters
1. **Seasonal Weather Overlays**:
   - `spring_petals`: Soft floating pink petals drifting diagonally across viewport.
   - `summer_monsoon`: Angled rain streaks with ground circular splash ripple rings.
   - `autumn_leaves`: Spiraling golden ginkgo and red maple leaf clusters.
   - `winter_blizzard`: White snow flakes drifting gently or whipping in gale streaks.
2. **Spiritual & Elemental Particle Motes**:
   - `spirit_motes`: Tiny rising luminous cyan/gold sparks hovering over herb plots.
   - `fireflies`: Gentle pulsing yellow/green points of light bobbing over night water.
   - `heat_haze`: Wavy refractive distortion layer over magma and blast furnaces.
   - `yin_smoke`: Curling black/violet vapor ribbons drifting low along ground.
3. **Barrier & Formation Projections**:
   - `barrier_dome_idle`: Faint translucent hexagonal grid slowly pulsing.
   - `barrier_dome_impact`: Bright gold ripple expanding outward from strike point.
   - `ground_array_runes`: Rotating concentric circles of glowing Hanzi seals.
   - `tribulation_clouds`: Heavy black swirling vortex with internal blue lightning arcs.

---

## 6. Metadata Architecture Schema (Planned Assets Specification)

In the upcoming data asset registration, every detailed asset definition will support the dynamic `variants` schema:

```json
{
  "id": "ancient_china_low_cultivation.sect_facilities.fur_bronze_trigram_furnace",
  "archetype": "bronze_trigram_pill_furnace",
  "domain": "sect_facilities_and_dwellings",
  "sub_domain": "alchemy_and_pill_refining",
  "asset_class": "prop_workstation",
  "name": "Bronze Trigram Pill Furnace",
  "hanzi": "八卦纯阳青铜丹炉",
  "vietnamese_name": "Bát Quái Thuần Dương Thanh Đồng Đan Lô",
  "dimensions": {
    "footprint_cells": [2, 2],
    "canvas_px": [256, 256],
    "pivot": "bottom_center"
  },
  "collision_type": "solid",
  "interactive_verb": "craft_alchemy_pill",
  "variants": {
    "rotations": ["south", "north", "east", "west"],
    "operational_states": ["dormant_unlit", "active_pill_fire", "overheated_surging"],
    "damage_states": ["pristine", "cracked", "exploded_rubble"],
    "time_of_day": ["day", "night_fire_glow"],
    "seasons": ["normal", "winter_snow_capped"],
    "elements": ["pure_yang_orange", "corrupted_yin_green_flame"]
  },
  "vfx_attachments": [
    {
      "socket": "chimney_top",
      "vfx_type": "pill_smoke_ribbon",
      "trigger": "operational_states == active_pill_fire"
    }
  ]
}
```

This architecture ensures that map composition tools, chunk streaming, and Godot runtime renderers can swap sprite variants and attach particle effects dynamically when rain falls, night falls, seasons advance, or battles destroy the terrain!

---

## 7. Deferred Technical Gaps & Engine Integration Roadmap
*(Note: These technical systems are documented here for future architecture planning. They will be scheduled and implemented in later engine/tooling phases, not in the current asset taxonomy phase).*

### 1. Dynamic Collision Mask Mutation on Destruction
- **Gap**: Current pack packaging computes static `matrix_data` based on a single image. When an asset transitions between damage variants (`pristine` -> `damaged` -> `ruined_rubble`), its collision footprints and pathfinding masks need to mutate dynamically at runtime.
- **Future Plan**:
  - `pristine`: Full collision boundary (`collision_type = "solid"`, blocks projectiles and actors).
  - `damaged_breached`: Wall breaches carve out specific 32px subcells as `walk_surface`, creating dynamic entryways or siege breach points.
  - `ruined_rubble`: Entire footprint converts to traversable rubble (`collision_type = "walk_surface"` with a 0.8x movement speed penalty and sound effects for footsteps on debris).

### 2. Godot `PointLight2D` Dynamic Lighting Metadata
- **Gap**: `night_lit` variants currently describe glowing lanterns or windows as static art layers, but Godot 2D lighting requires engine-level light nodes.
- **Future Plan**:
  - Add light emitter anchors in asset metadata:
    ```json
    "light_emitters": [
      {
        "socket": "eaves_lantern_left",
        "offset_px": [-24, -48],
        "color": "#FFB040",
        "energy": 0.85,
        "radius_px": 160,
        "mode": "gentle_candle_flicker"
      }
    ]
    ```
  - Standardize light color palettes: Warm Amber `#FFB040` (mortal candles), Ethereal Cyan `#40E0D0` (spirit pearls), Necrotic Ghost Green `#30FF70` (cemetery lights), Celestial Gold `#FFE080` (ascension arrays).

### 3. Audio Ambient SFX Hooks (`sfx_attachments`)
- **Gap**: Changing visual variants without matching audio leaves the world feeling half-alive (e.g. active furnace with roaring fire looks alive but sounds silent).
- **Future Plan**:
  - Link audio stream IDs to operational and environmental variant states:
    - Furnaces: `res://assets/audio/sfx/furnace_idle_hum.ogg` vs `furnace_roaring_fire.ogg`.
    - Weathered pavilions: `res://assets/audio/sfx/wind_creaking_timber.ogg`.
    - Riverbanks: `res://assets/audio/sfx/brook_calm.ogg` vs `river_flood_torrent.ogg` during monsoon floods.
    - Graveyards: `res://assets/audio/sfx/eerie_yin_whisper.ogg` activated during midnight Yin hours.

### 4. Standardized Interactive Verb Registry
- **Gap**: Interactive assets need a unified contract mapping player actions to backend module APIs (e.g. `cultivation`, `alchemy`, `foraging`, `mining`).
- **Future Plan**:
  - Formalize supported verbs across asset categories:
    - `harvest_herb` (calls `GatheringApi` with herb grade and respawn timer).
    - `mine_vein` (calls `MiningApi` with tool tier check).
    - `meditate_cultivate` (calls `QiCultivation` EXP sitting loop).
    - `craft_alchemy_pill` / `craft_forge_weapon` (opens crafting UI).
    - `pray_blessing` / `burn_joss_paper` (applies karma / luck buffs).
    - `enter_portal` / `enter_cave` (triggers chunk or scene transition).
    - `open_looted_chest` (triggers drop loot table and flips variant).
    - `tame_beast` (initiates beast-binding ritual).

### 5. VFX Particle Socket Anchoring & Dynamic Shaders
- **Gap**: Particle overlays (Class G) need exact pixel anchor sockets so that smoke rises from furnace chimneys, chimney sparks drift downwind, and barrier ripples expand from collision points.
- **Future Plan**:
  - Add socket vectors `socket_px: [x, y]` relative to the sprite pivot.
  - Integrate wind direction parameters into Godot canvas shaders so particle drift matches regional weather wind vectors.

### 6. Map Chunk State Persistence & Smooth Variant Crossfading
- **Gap**: When weather or time shifts, switching 100+ sprites instantaneously causes a visual pop.
- **Future Plan**:
  - Implement a 1.5-second alpha crossfade or shader dissolve between variants in the chunk renderer (`MapChunkStreamer`).
  - Persist destroyed and harvested object states in the save system (`SaveApi`) so cleared mines or looted chests remain in their correct variants upon reload.

---

## 8. Master Prompt Architecture & Game-Ready Isolation Guidelines

### 8.1 Critical Failure Analysis from Medieval Pack (Root Causes & Anti-Patterns)
Inspection of failed generation batches in `medieval_western` revealed four structural flaws in prompt construction that made generated assets unusable as standalone game sprites:

1. **The Miniature Diorama / Terrain Slab Trap (`floating_island_defect`)**:
   - *Failure*: Prompts containing environmental keywords (`"warm yellow sunlight on flowering grass"`, `"damp autumn mud and rain-bowed heavy grain stalks"`) caused the diffusion model to render an entire 3D diorama vignette—complete with floating cutaway dirt slabs, grass mounds, wooden fences, and cottages.
   - *Fix*: Environmental conditions must NEVER describe the ground or landscape surrounding an asset. Conditions must be expressed strictly as **surface modifications on the asset itself** (e.g., moisture droplets on bronze, frost on roof eaves).

2. **The Handheld Tool vs. Two-Story Building Scale Inversion (`giant_tool_cottage_defect`)**:
   - *Failure*: Prompts for small tools (e.g., wool shears, sickles) included thematic context keywords like `"Medieval pastoral livestock and dairy farming style"`. The model rendered a full farmhouse estate with sheep pens and dropped a 20-foot tall pair of shears into the yard as a colossal statue.
   - *Fix*: Handheld items and loose pickups belong to a dedicated **Item/Icon Archetype** rendered with macro isolation on pure white backgrounds, completely stripped of architectural, farm, or structural nouns.

3. **Mechanical Chimera Conflation (`hybrid_object_defect`)**:
   - *Failure*: Conflating agricultural terminology (e.g., `"wooden scratch plow"` + `"ready for scythe"` + `"toothed iron sickle"` + `"threshing floor"`) produced chimeric abominations—such as a wheeled plow cart sprouting a vertical scythe blade, or a wheeled harrow axle welded to a sickle blade.
   - *Fix*: Prompts must focus on **exactly one primary noun** and restrict technical terminology strictly to that singular object's mechanical parts.

4. **The Literal Anchor / "On Post" Trap (`welded_support_defect`)**:
   - *Failure*: To make small tools stand vertically in an RPG perspective, prompts used phrases like `"reaping sickle on post"`. The model took this literally, welding the tool onto a vertical fence post, cross-stake, or wooden pale.
   - *Fix*: Use camera orientation cues (`"2D orthographic top-down RPG view"`, `"lying flat"` or `"standing upright"`) instead of inventing physical posts or stakes.

---

### 8.2 The 7 Master Guardrails (Solving the 7 Audited Gaps)

```
┌────────────────────────────────────────────────────────────────────────┐
│                   THE 7 MASTER ISOLATION & PIPELINE GUARDRAILS         │
├────────────────────────────────────────────────────────────────────────┤
│ 1. STRUCTURAL GEOMETRY ANCHORS & 2-STAGE VARIANT PIPELINE              │
│    Lock base geometry in prompt. Variants use Img2Img (denoise 0.35)   │
│    or fixed seeds to prevent morphing between seasons/states.          │
│ ────────────────────────────────────────────────────────────────────── │
│ 2. ADAPTIVE CONTRAST KEYING (NO WHITE-ON-WHITE ERASURE)                │
│    Snow, white crane, jade use neutral grey/olive background so        │
│    RMBG-2.0 doesn't clip white asset edges. Standard items use white.  │
│ ────────────────────────────────────────────────────────────────────── │
│ 3. LUMINANCE-TO-ALPHA FOR VFX (BYPASS REMBG)                           │
│    VFX renders on pure black (#000000) and converts luminance to       │
│    alpha directly. Never pass soft spiritual motes through RemBG.      │
│ ────────────────────────────────────────────────────────────────────── │
│ 4. ALBEDO PURITY (NO DOUBLE-DARKENING NIGHT SPRITES)                   │
│    Never bake midnight darkness into albedo. Only add window/lantern   │
│    glow; let Godot's CanvasModulate handle world night shading.        │
│ ────────────────────────────────────────────────────────────────────── │
│ 5. ZERO DIRECTIONAL SHADOWS (MICRO CONTACT OCCLUSION ONLY)             │
│    No cast drop shadows on white background. Ground contact only at    │
│    feet/base. Godot runtime handles directional shadow decals.         │
│ ────────────────────────────────────────────────────────────────────── │
│ 6. CULTURAL ANTI-DRIFT GUARD (NO JAPANESE/WESTERN CONFUSION)           │
│    Enforce Chinese Tang-Song/Xianxia architectural & weapon terms.     │
│    Block torii, katana, samurai, gothic stone castles, witch cauldrons.│
│ ────────────────────────────────────────────────────────────────────── │
│ 7. SCALE-AWARE LINE WEIGHT (AVOID 128px DOWNSCALING MUSH)              │
│    1x1 cell items use bold chunky value planes and heavy contours;     │
│    large 4x4 buildings carry intricate architectural micro-detail.     │
└────────────────────────────────────────────────────────────────────────┘
```

---

### 8.3 Archetype-Specific Prompt Recipes with Variant Awareness

#### Common Cultural Anti-Drift Clause (Appended to All Negative Prompts)
```text
Japanese style, torii gate, shinto shrine, katana, samurai armor, tatami, ninja, western gothic castle, medieval stone fortress, European church, witch cauldron, laboratory glassware, modern objects, anime mech, sci-fi wires.
```

---

#### Archetype 1: Items, Handheld Tools, Weapons & Pickups (`item_tool`, `weapon`, `talisman`)
- **Engine Role**: Inventory icons, dropped ground loot, equipped artifacts, alchemical reagents.
- **Framing & Projection**: Macro product shot, centered, floating against contrast background. Zero ground shadow, zero pedestal.
- **Canvas / Footprint**: 1x1 cell (`128x128` or `256x256` px), `alpha: cutout`, `pivot: center`.
- **Adaptive Background Rule**:
  - Standard items: `centered on solid pure white background (#FFFFFF)`.
  - Pale/White items (white jade, silver swords, snow talismans, frost ginseng): `centered on solid neutral contrast grey background (#D0D0D0)` to prevent RMBG-2.0 edge clipping.
- **Master Positive Formula**:
  ```text
  Single isolated 2D game asset of {item_name}, {material_and_workmanship}, {variant_surface_state}, Ancient Chinese Xianxia cultivation mortal realm aesthetic, double-edged Chinese straight sword or authentic Daoist implement, bold readable silhouette, clean grouped value planes, chunky stylized proportions for 2D icon clarity, fine dark #263A35 ink contours, gouache hand-painted, centered on {adaptive_background}.
  ```
- **Master Negative Formula**:
  ```text
  diorama, miniature scene, floating island, dirt slab, grass pedestal, ground plane, floor, surface, shadow on ground, building, house, cottage, farm, fence, landscape, trees, field, human hands, fingers, holding, multiple items, collection, collage, border, frame, UI, watermark, blurry edges, microscopic high-frequency noise, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Items**:
  - `pristine`: `"immaculate polished cold iron blade, unblemished dark rosewood grip wrapped in tight clean black silk cord"`.
  - `weathered`: `"faint grey patina on bronze fuller, slightly softened edges, seasoned aged bamboo grip"`.
  - `rain_soaked`: `"wet glistening metallic surface with micro water droplets, darkened damp rosewood grip, high surface sheen"`.
  - `winter_frost`: `"delicate rim of white rime ice along cutting edge, pale frosted wood grain"`.
  - `damaged_chipped`: `"nicked cutting edge with several small notches, splintered pommel, fraying cord bindings"`.
  - `qi_resonating`: `"subtle ethereal cyan spiritual glow running along engraved talismanic blade fuller"`.
- **Item Position & Rotation Matrices**:
  - `pos_inventory_icon_45deg`: Macro 45° diagonal presentation for equipment grid / inventory slots (`zero ground shadow, zero pedestal`).
  - `pos_ground_drop_flat_east`: Lying flat horizontally pointing East in 2D orthographic top-down RPG perspective (`subtle micro contact shadow directly underneath only, resting flat`), anchoring to terrain.
  - `pos_ground_drop_flat_south`: Pointing South (downward) with 2D vertical foreshortening and micro contact shadow.
  - `rot_north_0deg`: Upright straight sword/implement pointing vertically North (0°), symmetrical alignment.
  - `rot_west_270deg`: Horizontal straight orientation pointing West (270°), preserving fixed top-left (10:30) light source and natural downward tassel hang.

---

#### Archetype 2: Workstations, Heavy Apparatus & Functional Props (`prop_workstation`, `apparatus`)
- **Engine Role**: Interactive crafting stations, pill furnaces, anvils, looms, mining carts, tea tables.
- **Framing & Projection**: 2D orthographic top-down 45-degree angle RPG map view. Micro ambient contact occlusion directly under feet/wheels only. Zero directional cast shadow.
- **Canvas / Footprint**: 1x1 to 2x2 cells (`128x128` to `256x256` px), `alpha: cutout`, `pivot: bottom_center`.
- **Master Positive Formula**:
  ```text
  Single isolated 2D RPG game prop of {prop_name}, {immutable_geometry_anchor}, {material_and_structure}, {variant_state}, Ancient Chinese Xianxia cultivation aesthetic, authentic Chinese tripod ding cauldron or traditional workshop implement, gouache hand-painted with crisp dark #263A35 ink contours, flat zero-cast-shadow baseline, micro ambient contact occlusion directly under feet only, isolated on solid plain white background.
  ```
- **Master Negative Formula**:
  ```text
  diorama, miniature base, floating island, dirt chunk, grass slab, square tile pedestal, floor plane, room interior, walls, ceiling, surrounding furniture, background building, trees, outdoor scenery, multiple objects, human operator, worker, collage, frame, directional cast shadow, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Workstations**:
  - `idle_dormant`: `"cold dark cast-bronze surface with pale verdigris patina, extinguished dark combustion vents, closed iron flue"`.
  - `active_operating`: `"roaring scarlet spiritual flames visible through carved trigram draft grates, glowing internal cauldron belly, faint heat shimmer around rim"`.
  - `overheated`: `"white-hot molten bronze belly, escaping violet vapor jets at lid seam, intense thermal glow"`.
  - `rain_soaked`: `"dark wet glistening metal surfaces, rainwater rivulets running down cauldron legs, cool damp exterior"`.
  - `winter_snow`: `"thin crisp layer of white snow clinging to cold bronze lid and handles, frost-lined rim"`.
  - `damaged_cracked`: `"prominent spiderweb fracture along belly seam, soot-blackened blast scorch on front face"`.
  - `ruined_shattered`: `"collapsed fractured cauldron base, shattered bronze shards, scattered cold ash pile"`.

---

#### Archetype 3a: Architecture, Sect Facilities & Dwellings (`structure_building`, `gateway`, `structure_temple`, `structure_cottage`)
- **Engine Role**: Sect gates, pill refinement halls, scripture towers, Daoist temple halls, mortal inns, hermit cottages, cave portals.
- **Framing & Projection**: Steep high-angle top-down RPG world-map perspective (~65°–70° overhead camera angle looking down). The broad roof surface is dominant and occupies 70%–80% of the sprite's vertical height. Front entrance facade, columns, and steps are foreshortened beneath the southern eaves at the bottom. Clear horizontal baseline for Godot Y-sort anchoring. Micro ambient occlusion at foundation base only.
- **Canvas / Footprint**: 2x2 to 4x4 cells (`256x256` to `512x512` px), `alpha: cutout`, `pivot: bottom_center`.
- **Architectural Typology Discrimination (Formal vs Rustic)**:
  - **Formal / Monumental Architecture** (`structure_temple`, `gateway`, `pagoda`, `pavilion`, `hall`, `shrine`):
    - *Roof & Gable*: `"broad glazed ceramic roof tiles and curved dougong eaves dominant and fully visible overhead (occupying 70%-80% of vertical sprite height), high-angle triangular dougong timber gable end"`
    - *Negative Ban*: `"thatched straw roof, straw hut, hay, rustic shack, "`
  - **Vernacular / Rustic Architecture** (`structure_cottage`, `dwelling`, `hut`, `bamboo`, `thatch`):
    - *Roof & Gable*: `"authentic uniform golden thatched straw roof surface dominant and fully visible overhead (occupying 70%-80% of vertical sprite height), split bamboo ridge rafters and thick straw eaves seen from above, high-angle triangular thatched timber gable end"`
    - *Negative Ban*: `"ceramic tiles, glazed tiles, blue roof tiles, dark roof tiles, terracotta tiles, dougong brackets, imperial palace, temple hall, "`
- **Master Positive Formula**:
  ```text
  Single isolated 2D top-down world-map building sprite of {building_name}, {immutable_geometry_anchor}, {architectural_features_and_materials}, {variant_state}, Ancient Chinese Tang-Song Xianxia architectural style, steep high-angle top-down RPG map perspective looking down from above, {directionally_adaptive_roof_and_perspective}, gouache hand-painted with dark #263A35 ink contours, flat grounded baseline, short attached micro contact shadow only, isolated on solid plain white background.
  ```
- **Master Negative Formula**:
  ```text
  {material_negative_ban}{direction_negative_ban}diorama, miniature landscape, floating rock island, cutaway foundation, courtyard boundary walls, garden lawn, surrounding trees, forest, mountains, sky, clouds, horizon, roads, cobblestone path, eye-level view, flat front elevation drawing, flat side view profile, side-scroller, human figures, isometric box frame, cutout diorama base, directional drop shadow, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Buildings & Structures**:
  - `day_pristine`: `"crisp daylight, vibrant vermilion timber columns, immaculate emerald glazed roof tiles, clean white rice-paper lattice windows, pure albedo exposure"`.
  - `night_lit`: `"pure daylight albedo base materials, warm golden candlelight glowing through rice-paper lattice windows, lit crimson eaves lanterns emitting soft light, no artificial dark blue tinting on walls"`.
  - `night_dark`: `"abandoned unlit facade, cold translucent paper windows, dark unlit lanterns, unpainted timber"`.
  - `spring_blossom`: `"delicate pink peach blossom petal drifts scattered along curved roof valleys and entryway steps"`.
  - `autumn_decay`: `"golden ginkgo leaves accumulated in roof gutters, faded vermilion pillar lacquer"`.
  - `winter_snow`: `"heavy thick white snow blanket settled on curved eaves, delicate hanging icicles along gutters, frosted stone steps"`.
  - `rain_storm`: `"dark saturated wet roof tiles, water runoff streaming off eave corners, darkened damp timber pillars"`.
  - `damaged_breached`: `"gaping breach in left roof wing with shattered tiles and splintered rafters, scorch marks on entrance pillars"`.
  - `ruined_rubble`: `"collapsed heap of shattered glazed tiles, splintered charred timber beams, cracked stone foundation slab with weeds"`.
- **Full 4-Way Directional Rotation Formulas**:
  - `rot_south_facade` (Front / South): `"steep top-down RPG map angle looking down, roof ridge running East-West with broad southern roof surface dominant from overhead (70%-80% of height), foreshortened front walls and entrance visible beneath eaves at bottom-center, stone courtyard steps descending at bottom"`. Negative: `"eye-level view, flat front elevation drawing, flat side view profile"`.
  - `rot_north_rear` (Back / North): `"steep top-down RPG map angle looking down, roof ridge running East-West with broad northern rear roof surface dominant from overhead (70%-80% of height), solid timber lattice back wall or rear masonry foreshortened beneath eaves at bottom, zero entrance steps, clean horizontal baseline"`. Negative: `"front entrance door, open doorway, entrance steps, door plaque, front veranda"`.
  - `rot_west_flank` (Left / West): `"steep top-down RPG map angle looking down, building rotated 90 degrees with roof ridge running North-South, western roof slope and high-angle triangular gable end dominant overhead, western side wall foreshortened beneath eaves at bottom, side window or railing, entrance steps extending toward bottom-right"`. Negative: `"symmetrical front entrance facade, central double doors at bottom, front steps at bottom-center"`.
  - `rot_east_flank` (Right / East): `"steep top-down RPG map angle looking down, building rotated 90 degrees with roof ridge running North-South, eastern roof slope and high-angle triangular gable end dominant overhead, eastern side wall foreshortened beneath eaves at bottom, side window or railing, entrance steps extending toward bottom-left"`. Negative: `"symmetrical front entrance facade, central double doors at bottom, front steps at bottom-center"`.

---

#### Archetype 3b: Natural Geological Landmarks & Mountain Spires (`landmark_mountain`, `spire`, `cliff`, `crag_pillar`)
- **Engine Role**: Towering karst mountain spires, cultivation peaks, precipitous meditation cliffs, sacred boulder shrines.
- **Framing & Projection**: Steep high-angle top-down RPG world-map perspective (~65°–70° overhead camera angle looking down). Summit crest and upper plateau terraces fully visible from above, with stepped rock tiers descending toward the bottom. Bare rock contact base resting on terrain with short attached micro shadow.
- **Canvas / Footprint**: 2x3 to 3x4 cells (`256x384` to `384x512` px), `alpha: cutout`, `pivot: bottom_center`.
- **Master Positive Formula**:
  ```text
  Single isolated 2D top-down world-map natural landmark sprite of {landmark_name}, {immutable_geometry_anchor}, {geological_material_and_features}, {variant_state}, Ancient Chinese Xianxia landscape style, steep high-angle top-down RPG map perspective looking down from above, {directionally_adaptive_mountain_perspective}, bare natural rock base resting directly on ground, gouache hand-painted with dark #263A35 ink contours, clean grounded baseline, micro contact shadow only, isolated on solid plain white background.
  ```
- **Master Negative Formula**:
  ```text
  diorama, miniature base, floating rock island, sky, clouds, horizon, distant mountains, landscape vista, eye-level view, side-view portrait, flat elevation, landscape painting, grass patch, turf, lawn, meadow, green ground plane, soil patch, path, cobblestone, road, frame, border, UI, watermark, human figures, birds in sky, {anti_drift_clause}
  ```
- **Full 4-Way Directional Rotation Formulas for Mountain Landmarks**:
  - `facing_south_front` (Front / South): `"steep top-down RPG map angle looking down onto mountain landmark, summit crest and rocky upper plateau terrace dominant from above, twisted green cliff pine canopy spreading over middle ledge, stepped limestone crag tiers descending toward camera"`.
  - `facing_north_back` (Back / North): `"steep top-down RPG map angle looking down onto mountain landmark from behind, sheer northern limestone rock face and upper summit plateau surface dominant from overhead, weathered crag terraces descending away from summit, zero trees on northern rock wall"`.
  - `facing_west_left` (Left / West): `"steep top-down RPG map angle looking down onto mountain landmark rotated 90 degrees, elongated rock ridge running North-South, narrow summit crest and western stepped cliff strata seen from high overhead, protruding pine branch visible on left side"`.
  - `facing_east_profile` (Right / East): `"steep top-down RPG map angle looking down onto mountain landmark rotated 90 degrees, elongated rock ridge running North-South, narrow summit crest and eastern stepped cliff strata seen from high overhead, protruding pine branch visible on right side"`.
  - `winter_frost`: `"sheer limestone crag capped in glistening white frost, snow dusting the gnarled pine branches, icicles clinging to rock fissures"`.
  - `thunder_blessed`: `"azure lightning scorch lines along the monolith spire apex, faint celestial electrical sparks dancing on the summit"`.

---

#### Archetype 4: Flora, Spirit Herbs & Sacred Trees (`flora_herb`, `flora_tree`)
- **Engine Role**: Gatherable medicinal plants, spirit bamboo groves, ancient pine landmarks, garden beds.
- **Framing & Projection**: 2D orthographic top-down 45-degree RPG nature prop. Root/stem contact at bottom pivot.
- **Canvas / Footprint**: 1x1 to 2x2 cells (`128x128` to `256x256` px), `alpha: cutout`, `pivot: bottom_center`.
- **Master Positive Formula**:
  ```text
  Single isolated 2D RPG plant sprite of {flora_name}, {botanical_traits}, {variant_state}, Ancient Chinese herbal lore aesthetic, traditional Bencao Gangmu medicinal plant style, gouache hand-painted with dark ink contours, ground root base contact only, zero terrain mound, isolated on solid plain white background.
  ```
- **Master Negative Formula**:
  ```text
  diorama, plant pot, planter, flowerbed border, dirt mound base, turf chunk, forest background, surrounding grass, garden scene, landscape, mountains, sky, multiple clumps, human hands, shears, trowel, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Flora**:
  - `spring_sprout`: `"tender pale-emerald shoots, fresh budding floral calyxes, delicate glistening dew drops"`.
  - `summer_lush`: `"vibrant deep jade-green foliage, plump translucent spirit berry clusters, fully expanded leaf fronds"`.
  - `autumn_mature`: `"golden-amber foliage with crimson tips, fully ripened glowing seed pods, dry fibrous leaf edges"`.
  - `winter_rime`: `"withered dormant boughs coated in sparkling white frost, delicate crystalline rime needles on stems"`.
  - `harvested_stump`: `"clipped central medicinal stalk, freshly harvested fibrous root stump with glistening sap bead, missing flower"`.
  - `qi_overflow`: `"pulsing veins of ethereal azure bioluminescence glowing through translucent leaf veins"`.

---

#### Archetype 5: Fauna, Spirit Beasts, Demons & Denizens (`fauna_beast`, `creature`)
- **Engine Role**: Roaming wild beasts, sect guardian mounts, demonic invaders, wandering Daoist NPCs.
- **Framing & Projection**: 2D orthographic top-down 45-degree RPG creature sprite. Foot contact shadow only.
- **Canvas / Footprint**: 1x1 to 3x3 cells (`128x128` to `384x384` px), `alpha: cutout`, `pivot: bottom_center`.
- **Adaptive Background Rule**: White beasts (White Tiger, Crane, Nine-Tailed White Fox) use neutral grey `#D0D0D0` background.
- **Master Positive Formula**:
  ```text
  Single isolated 2D game creature sprite of {creature_name}, {anatomical_traits}, {variant_posture_and_mood}, Shan Hai Jing ancient Chinese mythological bestiary style, gouache painted with dark ink contours, ground foot contact shadow only, zero directional drop shadow, isolated on {adaptive_background}.
  ```
- **Master Negative Formula**:
  ```text
  diorama, cage, stable, pen, pasture, fence, saddle, reins, rider, trainer, human hands, background scenery, landscape, grass chunk, multiple animals, herd, UI healthbar, floating icons, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Creatures**:
  - `idle_peaceful`: `"relaxed four-legged standing stance, calm neutral head position, softly curved tail"`.
  - `alert_hunting`: `"lowered hunting crouch, tensed sinews, perked ears, piercing focused forward gaze, raised bristling hackles"`.
  - `combat_aggressive`: `"menacing battle roar pose, bared predatory fangs, flared spirit crest, unsheathed razor claws"`.
  - `wounded_staggered`: `"staggered off-balance stance, singed fur patches, cracked horn tip, bloodied flank wound"`.
  - `sleeping_den`: `"peacefully curled into circular resting posture on ground, closed eyes, relaxed limp limbs"`.
  - `dead_carcass`: `"lifeless prone side posture on ground, limp neck, exposed harvestable beast core and intact pelt"`.
  - `yin_corrupted`: `"swirling dark purple miasma smoke curling off spine, glowing sinister crimson eyes, blackened claws"`.

---

#### Archetype 6: Ground Terrains, Walk Surfaces & Path Decals (`terrain_tile`, `surface_decal`)
- **Engine Role**: Base map tilemap layers, path transitions, scorched earth decals, water surfaces.
- **Framing & Projection**: Strict 90-degree perpendicular overhead top-down bird's-eye plan view. 100% canvas edge-to-edge fill.
- **Canvas / Footprint**: 1x1 to 2x2 cells (`128x128` to `256x256` px), `alpha: opaque` (tiles) or `cutout` (decals), `pivot: center`.
- **Master Positive Formula**:
  ```text
  Seamless flat 2D top-down ground terrain texture of {terrain_type}, {surface_texture_and_materials}, {variant_surface_condition}, 90-degree perpendicular overhead camera angle, completely flat planar surface filling 100% of canvas corner-to-corner, gouache painted, dark ink linework, zero perspective, zero horizon, no focal prop.
  ```
- **Master Negative Formula**:
  ```text
  perspective, 45-degree angle, isometric, horizon, 3D elevation, relief shading, trees, plants, buildings, houses, fences, focal object, standalone prop, pedestal, frame, borders, {anti_drift_clause}
  ```
- **Variant Awareness Matrix for Terrains**:
  - `dry_temperate`: `"fine pale loess dust, dry cracked clay fissures, scattered small weathered pebbles"`.
  - `wet_rain`: `"darkened saturated deep loam, glassy reflective standing rainwater puddle sheets, soft mud ruts"`.
  - `winter_snow`: `"compacted white snow crust, icy patch glazes, exposed frozen dark soil edges"`.
  - `scorched_lightning`: `"vitrified blackened stone patches, radiating fractal scorch scars from lightning impact"`.
  - `leyline_pure`: `"intricate subterranean glowing cyan spiritual Qi crystal veins branching through bedrock"`.

---

#### Archetype 7: Atmospheric VFX & Overlay Particle Sheets (`vfx_particle`, `overlay`)
- **Engine Role**: Particle emitters, weather overlays, protective formation barriers, spiritual auras.
- **Framing & Projection**: Planar 2D VFX sprite against solid pitch black `#000000` background.
- **Pipeline Rule**: **Bypasses RMBG-2.0 with Automated Unmultiplied Black-to-Alpha Conversion**. The raw model renders luminous particles on pure black `#000000`, and the pipeline automatically converts it into a pure transparent RGBA PNG ($A = \max(R, G, B)$ with unmultiplied color $\text{RGB} = \text{RGB} / A$). This delivers 100% game-ready alpha transparency for Godot standard sprite rendering without black boxes, dark fringes, or halo erosion.
- **Canvas / Footprint**: 1x1 to 4x4 cells (`128x128` to `512x512` px), `alpha: transparent`, `pivot: center`.
- **Master Positive Formula**:
  ```text
  2D game particle VFX sprite of {vfx_name}, {particle_dynamics_and_motion}, {variant_intensity}, luminous spiritual motes, soft radiant glow edges, glowing magical energy, isolated on solid pure black background (#000000) for additive alpha blending.
  ```
- **Master Negative Formula**:
  ```text
  white background, opaque solid shapes, opaque borders, ground, floor, landscape, characters, buildings, terrain, solid geometry, ui frames.
  ```
- **Variant Awareness Matrix for VFX**:
  - `subtle_ambient`: `"sparse tiny drifting luminous motes, gentle pulsing transparency, faint soft glow"`.
  - `rushing_surge`: `"dense swirling vortex streaks of cyan spiritual energy, high brightness core, fast rotational blur"`.
  - `violent_calamity`: `"crackling erratic jagged lightning arcs, blinding flash center, explosive spark scatter"`.

---

### 8.4 Verification Checklist for Pipeline Testing
Before approving any generated asset wave into the game pack, each output file must pass this 7-step quality gate:

1. **Alpha Cutout Purity (`rembg_transparency_check`)**:
   - The sprite must have 0% alpha across all border pixels.
   - No residual gray halo or white fringing around the silhouette (`#263A35` ink contour intact).
2. **White Asset Edge Integrity (`white_on_white_guard`)**:
   - White assets (snow, cranes, white jade) must show zero clipping holes or jagged bite marks on white elements.
3. **Pedestal & Diorama Absence (`no_diorama_guard`)**:
   - The sprite must NOT sit upon an artificial dirt slab, grass circle, stone plate, or floating island.
   - For props and structures, the bottom-most non-transparent pixel row must correspond strictly to the physical ground-contact point.
4. **Zero Directional Cast Shadow (`zero_drop_shadow_guard`)**:
   - No directional diagonal shadows cast onto the background; only tight ambient contact occlusion under feet.
5. **Cultural Authenticity (`anti_drift_cultural_guard`)**:
   - Zero Japanese Torii gates, zero Katana curved blades, zero Western Gothic masonry, zero witch cauldrons.
6. **Variant Morphological Consistency (`geometry_anchor_check`)**:
   - When switching between variants (`pristine` -> `damaged` -> `winter`), the primary silhouette, legs, and bounding footprint must maintain $\le 4$ px drift from the base archetype.
7. **Downscaling Silhouette Legibility (`128px_readability_check`)**:
   - 1x1 cell items downscaled to 128x128 px must maintain high-contrast silhouette clarity without turning into unreadable micro-noise.

---

### 8.5 Empirical Candidate Test Results & Validation Log (Deep Gaps, Item Positions & Structure Rotations Proven)

The prompt formulas and variant mechanics were verified across all archetypes, deep gameplay state axes, item position/rotation orientations, and map structure/landmark rotations using local ComfyUI (`krea2/raySemiReal_krea2TurboV1Nsfw` + `Scottie:1.0` LoRA) and automated headless validation.

| # | Archetype | Candidate Asset Slug | Canonical Name | Variants Tested & Proven | Core Validation Outcome |
|---|---|---|---|---|---|
| **1** | `item_tool` | `crescent_spirit_herb_sickle` | Liềm Cắt Linh Thảo Nguyệt Nha | `pristine`, `rain_soaked`, `winter_frost`, `damaged_chipped`, `pos_ground_drop_flat`, `rot_vertical_north` | **PASSED (Item Position & Rotation Proven)**: 100% clean cutout icon. `pos_ground_drop_flat` shows sickle resting flat on ground plane with subtle micro contact shadow; `rot_vertical_north` shows vertical upright orientation. Zero diorama, zero fence posts. |
| **2** | `item_weapon` | `azure_frost_flying_sword` | Thanh Sương Phi Kiếm | `pos_inventory_icon_45deg`, `pos_ground_drop_flat_east`, `pos_ground_drop_flat_south`, `rot_north_0deg`, `rot_west_270deg` | **PASSED (Item Position & Rotation Proven)**: Macro 45° diagonal icon; flat horizontal ground drop with contact shadow; flat south drop with perspective foreshortening; 0° North vertical straight sword; 270° West horizontal profile with top-light preservation and hanging tassel. |
| **3** | `prop_workstation` | `bronze_trigram_pill_furnace` | Bát Quái Thanh Đồng Đan Lô | `dormant_unlit`, `active_fire`, `winter_snow`, `damaged_cracked` | **PASSED**: Authentic 3-legged tripod ding cauldron at 45° angle. Active fire visible through Bagua vents, snow caps on lid, identical tripod foot contact baseline. |
| **4** | `prop_container` | `carved_rosewood_spirit_pill_chest` | Điêu Hoa Tử Đàn Linh Đan Hạp | `closed_locked`, `open_looted`, `broken_shattered` | **PASSED (Gap 1 Proven)**: Container lifecycle. Closed box with Daoist brass padlock; hinged lid flipped backward showing empty velvet interior; smashed fractured lid planks on ground. Base footprint and brass corners preserved across all 3 states. |
| **5** | `structure_building` | `azure_cloud_mountain_gate` | Thanh Vân Sơn Môn Bài Lâu | `day_pristine`, `night_lit`, `winter_snow`, `damaged_breached`, `wartime_lockdown`, `ruined_rubble` | **PASSED (Gap 2 Proven)**: Complete durability range. `wartime_lockdown` renders an active glowing cyan Bagua shield dome and heavy spiked barricades; `ruined_rubble` renders a 0% HP collapsed caved-in roof and weeds on cracked foundation while keeping the baseline aligned. |
| **6** | `fauna_beast` | `azure_crest_cloud_crane` | Thanh Đỉnh Linh Vân Hạc | `idle_standing`, `alert_aggressive`, `wounded_staggered`, `dead_carcass`, `yin_demonic_corrupted` | **PASSED (Gap 3 Proven)**: Core combat & hunting loop. `wounded_staggered` shows drooping wing and bloodied flank; `dead_carcass` lies limp on the ground with an exposed harvestable glowing cyan spirit core; `yin_demonic_corrupted` features violet demonic miasma smoke and crimson eyes. Zero diorama turf, zero plumage clipping. |
| **7** | `flora_herb` | `blood_crystal_ginseng` | Huyết Tinh Linh Sâm | `spring_sprout`, `ripe_blooming`, `qi_overflow`, `harvested_stump`, `withered_spent` | **PASSED (Gap 4 Proven)**: Full botanical lifecycle. `spring_sprout` tender shoot; `ripe_blooming` crystal root and berries; `qi_overflow` pulsing radiant azure Qi veins; `harvested_stump` clipped flat root neck; `withered_spent` dried brown shriveled husk. |
| **8** | `terrain_tile` | `danxia_red_crag_stone` | Đan Hà Hồng Sa Thạch Điền | `dry_temperate`, `wet_rain`, `leyline_pure`, `yin_corrupted` | **PASSED (Gap 5 Proven)**: Leyline & corruption. `leyline_pure` illuminates subterranean azure energy conduits; `yin_corrupted` scorches identical conduits with demonic black/purple miasma. Near-zero ($\le 2\text{ px}$) geometric layout drift. |
| **9** | `vfx_particle` | `ascending_spiritual_qi_motes` | Thanh Kim Linh Quang Thăng Đằng | `subtle_ambient`, `surging_vortex` | **PASSED**: 100% transparent RGBA PNG. Pure black background automatically converted to alpha using unmultiplied color keying, eliminating dark fringes and black boxes. |
| **10** | `vfx_particle` | `nine_heavens_tribulation_lightning` | Cửu Tiêu Thần Lôi Kiếp Điệp | `calamity_arc` | **PASSED (Gap 6 Proven)**: Heavenly breakthrough tribulation calamity. Blinding azure lightning core with delicate jagged branching plasma filaments, 100% transparent background with fine alpha preservation. |
| **11** | `structure_temple` | `pure_yang_daoist_temple` | Thuần Dương Đạo Quán Đại Điện | `rot_south_facade` (Front), `rot_north_rear` (Back), `rot_west_flank` (Left), `rot_east_flank` (Right) | **PASSED (Full 4-Way 360° Rotations Proven)**: True 65°–70° steep overhead camera angle matching world-map storehouses and workbenches. Roof hips dominate 75%–78% of sprite height across all 4 directions. Front shows foreshortened double doors and courtyard steps; Back shows solid timber lattice with zero steps; Left (West) shows North-South ridge, triangular dougong gable, and western wall; Right (East) shows North-South ridge and eastern wall. Consistent foundation elevation, scale, and textures. |
| **12** | `structure_cottage` | `bamboo_spirit_hermit_cottage` | Trúc Lâm Ẩn Sĩ Thảo Lư | `rot_south_facade` (Front), `rot_north_rear` (Back), `rot_west_flank` (Left), `rot_east_flank` (Right) | **PASSED (Full 4-Way 360° Rotations Proven)**: Golden thatched straw roof and bamboo ridge poles dominant from overhead (75% height) in all 4 cardinal angles. Front shows veranda porch and open tea room door; Back shows solid woven bamboo wall, rear roof clay chimney, and zero steps; Left (West) shows western thatched gable, circular bamboo window, and stilt footings; Right (East) shows eastern thatched gable and side veranda railing. |
| **13** | `landmark_mountain` | `azure_cloud_karst_peak_spire` | Thanh Vân Thạch Phong Tiêm Nhai | `facing_south_front` (Front), `facing_north_back` (Back), `facing_west_left` (Left), `facing_east_profile` (Right) | **PASSED (Full 4-Way Overhead Landmark Proven)**: Summit crest plateau surfaces and rock column heads clearly visible looking down from high overhead; Front shows wide limestone crags and spreading pine canopy; Back shows sheer northern cliff face and descending terraces; Left (West) shows North-South rock spine with pine branch on left; Right (East) shows slender rock spine with pine branch on right. Zero diorama box, clean bare rock grounding. |

#### Key Tuning Lessons & Production Rules:
1. **Item Position Modes (UI Icon vs Ground Drop)**: Inventory icons require a 45° diagonal presentation with macro framing and zero ground shadow (`zero ground shadow, zero pedestal`). In contrast, world ground drops require lying flat on the floor plane in 2D orthographic top-down RPG perspective with subtle micro contact shadow underneath (`subtle micro contact shadow directly underneath only, resting flat`), anchoring the dropped item to world terrain without floating.
2. **Item Rotation & Fixed Lighting**: Rotating 2D sprites via game engine code flips the directional lighting upside down. Pre-rendered rotation frames (`rot_north_0deg`, `rot_west_270deg`, `pos_ground_drop_flat_east`) maintain the fixed top-left (10:30 o'clock) lighting highlight and bottom shadow while allowing tassels and accessories to obey gravity naturally.
3. **Orthographic Foreshortening**: Items pointing North or South exhibit perspective foreshortening on the vertical axis, whereas East and West orientations display full blade profile length.
4. **Separation of Containers/Furnishings from Cauldrons**: Generic prop prompts defaulting to "tripod ding cauldron" cause chests to distort into cauldrons. The pipeline now splits Archetype 2 into `prop_workstation` (furnaces/anvils) and `prop_container` (carved rosewood joinery and Daoist caskets with brass latching).
5. **Contact Shadow Adaptation for Carcasses & Dead States**: Standing creatures require `ground foot contact shadow only`. In contrast, dead carcasses and harvestable corpses must specify `contact shadow directly under body only` with negative clauses forbidding `standing upright, flying, walking`.
6. **Adaptive Contrast Backgrounds for White Cutouts**: White assets (snow, white cranes, white jade) must never be prompted against `#FFFFFF`. A neutral grey `#D0D0D0` background allows RMBG-2.0 to preserve fine white feather tips, icicles, and white jade rims without erosion or jagged bite marks.
7. **Bypassing RemBG with Automated Black-to-Alpha for VFX**: Atmospheric particles, Qi motes, and tribulation lightning are generated on `#000000` pitch black to prevent RemBG erosion, then converted via unmultiplied alpha mapping into 100% transparent RGBA PNGs.
8. **Material-First Phrasing for Ground Surfaces**: Diffusion models convert architectural nouns ("crag", "canyon", "pedestal") into 3D scenes. Ground surfaces must use material terminology ("uniform flat soil surface", "fine mineral silt", "broad planar pavement") with 90-degree perpendicular overhead angles.
9. **Immutable Geometry Anchors for State Progression**: Keeping base materials, perspective angles, and contact pivots identical across variants guarantees seamless sprite swapping in Godot without collision jitter or visual popping.
10. **The Camera Angle Imperative (Steep Overhead 65°–70° vs Eye-Level Elevation Traps)**: Words like `"building facade"` or `"45-degree angle"` without explicit overhead cues cause the diffusion model to render shallow ~15°–20° architectural elevation drawings (tall flat walls, huge doors, tiny slivers of roof) or flat 0° side-view cross-sections. Top-down RPG map sprites require **steep overhead map-camera phrasing (~65°–70° downward tilt)** where the **roof surface dominates 70%–80% of the sprite**, while walls and doorways are foreshortened underneath the eaves at the bottom. Negative prompts must explicitly ban `"eye-level view, flat front elevation drawing, flat side view profile, side-scroller"`.
11. **Landmark Mountain Spires vs. Flat Ground Dioramas**: Mountain spires, cliffs, and karst peaks in `terrain_and_geology` must never share the flat ground tile prompt template. Classifying them as `landmark_mountain` with Archetype 3b ("steep high-angle top-down RPG map perspective looking down from above, summit crest and upper rock terraces fully visible from above") prevents both the cutaway grass diorama cube and the flat eye-level landscape painting trap, yielding authentic standalone natural map landmarks.
12. **Elevated Stilt Architecture & Foundation Anchoring**: For bamboo dwellings and hermit cottages built on wooden stilts, grounding is anchored at the bottom of the foundation stilts/stone footings. Negative prompts must explicitly forbid surrounding gardens, fences, and grass slabs so the cottage can be placed seamlessly over any map terrain layer (water, grass, dirt).
13. **Full 4-Way Directional Rotation Sets (Front, Back, Left, Right)**: Map structures require complete 4-cardinal orientation sets for road and player approach flexibility. Each orientation requires directionally adaptive prompts: Front features South-facing entrance and steps foreshortened under eaves at bottom-center; Back features North-facing solid timber/masonry rear wall with negative prompts banning doorways and steps (`front entrance door, open doorway, entrance steps, door plaque`); Left (West) and Right (East) feature North-South ridge rotation with triangular dougong/thatch gable ends and side windows/railings while keeping consistent top-left lighting.



