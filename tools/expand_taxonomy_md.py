# -*- coding: utf-8 -*-
"""Expands low_realm_cultivation_taxonomy.md with 7 new domains (76 new categories),
bringing total categories to 344 across the full 9-realm Mortal World ladder.
"""

from __future__ import annotations
from pathlib import Path

MD_PATH = Path(
    r"C:\Users\NeneScarlet\.gemini\antigravity-ide\brain\7a8e638b-79b7-4ad0-9075-e3c4c3594f07\low_realm_cultivation_taxonomy.md"
)

NEW_DOMAINS_TEXT = """

## Domain 11: Evil Sects & Demonic Cultivation (魔道宗门与邪修) — 12 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| EVI-01 | Corpse Refining Pit & Embalming Vats | 尸阴炼尸血池 (Liànshīchí) | Luyện Thi Trì / Thi Âm Tông | Black putrid fluids and embalming salt pits for raising iron/bronze Jiangshi. | Corpse refining crafting node |
| EVI-02 | Ten Thousand Soul Banner Altar | 万魂幡白骨坛 (Wànhúnfān) | Vạn Hồn Phiên Tế Đàn | Obsidian dais fluttering with black banners trapping howling ghost souls. | High-tier evil boss altar |
| EVI-03 | Blood Demon Altar & Blood Basin | 嗜血魔煞祭坛 (Xuèshàtán) | Huyết Sát Tông Ma Trì | Crimson stone font collecting fresh cultivator blood for blood-essence pills. | Blood cultivation station |
| EVI-04 | White Bone Throne & Skull Pavilion | 累累白骨宝座 (Báigǔzuò) | Bạch Cốt Đầu Lâu Bảo Tọa | Ornate pavilion built from thousands of human skulls and demon vertebrae. | Evil sect master throne hall |
| EVI-05 | Demonic Cauldron Chamber (Lu Ding) | 幽闭炉鼎采补室 (Lúdǐngshì) | Lô Đỉnh Song Tu Mật Thất | Silken-curtained secret rooms used for non-consensual Qi drainage and extraction. | Clinical villain lore facility |
| EVI-06 | Myriad Gu Pit & Poison Basin | 万蛊翻滚毒坑 (Wàngǔkēng) | Vạn Cổ Trùng Độc Quật | Deep stone pit teeming with centipedes, scorpions, and spiders cannibalizing. | Gu master crafting pit |
| EVI-07 | Soul Extraction & Torture Pillar | 搜魂剥皮刑柱 (Sōuhúnzhù) | Sưu Hồn Trạc Hình Trụ | Iron-spiked bronze pillar inscribed with soul-scouring runes for interrogation. | Interactive prisoner execution |
| EVI-08 | Baleful Earth-Qi Geyser Vent | 九幽地煞黑风眼 (Dìshàfēng) | Cửu U Địa Sát Phong Huyệt | Fissure blasting freezing black Yin gales used to temper demonic artifacts. | Extreme Yin cultivation spot |
| EVI-09 | Demonic Blood Infant Offering Shrine| 滴血邪婴阴龛 (Xiéyīngkān) | Huyết Anh Ma Khám | Sinister altar with crimson clay statuettes fed on spiritual blood offerings. | Dark karma offering node |
| EVI-10 | Suspended Corpse Coffin Racks | 悬空阴尸排架 (Yīnshījià) | Huyền Thi Mộc Giá | Towering scaffolding holding hundreds of chained coffins steeping in miasma. | Zombie storage storage racks |
| EVI-11 | Nether Ghost Fire Melting Crucible | 幽冥鬼火化骨鼎 (Guǐhuǒdǐng) | U Minh Quỷ Hỏa Đỉnh | Green-flame cauldron melting human bones into white bone flying needles. | Evil weapon crafting forge |
| EVI-12 | Flayed Skin Talisman Inscribing Screen| 鞣制人皮符屏 (Rénpífú) | Nhân Bì Họa Phù Bình Phong | Drying parchment screens made from demonic beast or cultivator skins. | Dark talisman crafting bench |

---

## Domain 12: Mining, Metallurgy & Mineral Extraction (采矿冶炼与矿脉) — 12 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| MIN-01 | Deep Mine Shaft Headframe & Windlass| 绞盘深井井架 (Jǐngjià) | Khai Khoáng Tỉnh Khẩu Gỗ | Heavy timber headframe with hemp cable and winches lowering miners into abyss. | Mine dungeon elevator entrance |
| MIN-02 | Mine Tunnel Timber Shoring Sets | 坑道加固木撑 (Kēngmù) | Hầm Mỏ Khung Gỗ Chống Đỡ | Square wooden portal frames and lagging planks preventing tunnel cave-ins. | Underground walkway corridor |
| MIN-03 | Mine Cart Tracks & Iron Push Wagons | 矿车木轨与铁斗 (Kuàngchē) | Khoáng Xa Thiết Quỹ / Thiết Đấu| Narrow wooden or iron tracks with heavy push carts laden with raw ore. | Resource transport rail |
| MIN-04 | Water-Powered Ore Stamping Mill | 水力重锤碓矿机 (Shuǐlìduì) | Thủy Lực Đập Quặng Cối | Triple-trip wooden stamping hammers powered by stream flow to crush quartz. | Animated ore processing station |
| MIN-05 | High-Draft Blast Smelting Furnace | 炼铁化铜耐火高炉 (Gāolú) | Luyện Quặng Cao Lô | Cylindrical clay and brick furnace with dual piston bellows melting raw copper. | Metal ingot smelting station |
| MIN-06 | Mineral Slag & Tailings Dump Mound | 灰黑矿渣弃料堆 (Kuàngzhā) | Khoáng Xỉ Đống / Phế Liệu | Vast piles of glassy black and rusty brown smelting slag and broken rock. | Industrial waste terrain |
| MIN-07 | Deep Marrow Jade Crystal Geode Cave | 纯阳髓玉晶洞 (Suǐyùdòng) | Tủy Ngọc Tinh Thạch Quật | Crystalline cavern glistening with luminescent translucent jade spikes. | High-tier mining node |
| MIN-08 | Embedded Raw Spirit Stone Seam Wall | 嵌石灵脉岩壁 (Língmài) | Linh Thạch Khảm Nham Vách | Natural granite bedrock striated with embedded raw azure spirit stone chunks. | Pickaxe harvestable rock wall |
| MIN-09 | Miner Encampment Huts & Sump Basin | 矿奴窝棚与积水井 (Wōpéng) | Thợ Mỏ Lán Trại & Tụ Thủy | Crude timber lean-tos, clay braziers, and wooden drainage bucket troughs. | Subterranean camp / rest zone |
| MIN-10 | Mine Overseer Station & Great Scale | 监工点卯大秤棚 (Chèngpéng) | Giám Công Đài & Cân Quặng | Elevated timber office with heavy iron balance beam scales for quota weighing. | Quest turn-in / quota desk |
| MIN-11 | Thunder Talisman Blasting Drill Hole| 破岩天雷符炮眼 (Pàoyǎn) | Liệt Khoáng Lôi Phù Hãm | Boreholes in rock face stuffed with yellow explosive blasting talismans. | Environmental destruction puzzle |
| MIN-12 | Stacked Smelted Ingot Storage Depot | 锭铁铅块堆栈 (Dìngkuài) | Linh Kim Trữ Kho / Kim Loại | Pyramidal stacks of cast iron pigs, copper ingots, and silver-tin bricks. | Heavy crafting commodity piles |

---

## Domain 13: Non-Human Races, Bloodlines & Tribal Enclaves (种族异族与血脉) — 12 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| RAC-01 | Stoneborn Megalithic Rock Dwellings | 巨石族古岩叠垒 (Jùshízú) | Thạch Tộc Cự Thạch Khám | Cyclopean stone architecture carved directly out of solid bedrock. | Stoneborn faction architecture |
| RAC-02 | Emberblood Magma Forge Hearths | 炎血熔岩锻舍 (Yánxuèfáng) | Viêm Tộc Dung Nham Thất | Obsidian houses built over open magma channels; home of fire-affinity tribes. | Emberblood faction settlement |
| RAC-03 | Tidecaller Conch & Mother-of-Pearl | 鲛人螺贝水寨 (Jiāorénzhài) | Giao Nhân Ốc Xà Cừ Phòng | Iridescent giant conch shell homes and pearl-inlaid floating pontoons. | Tidecaller / Merfolk water town |
| RAC-04 | Fox Spirit Illusion Burrow Pavilion| 青丘幻木地穴轩 (Qīngqiūxué) | Hồ Tộc Huyễn Mộc Hiên | Camouflaged underground burrows masked by blossom trees and pink mist. | Beastkin / Fox clan hideout |
| RAC-05 | Wolf Shifter Bone & Hide Yurts | 荒原狼族兽骨帐 (Lángzúzhàng) | Lang Tộc Lang Đầu Lều Bạt | Heavy yurts constructed from mammoth ribs, covered in cured wolf pelts. | Nomadic beast tribe camp |
| RAC-06 | Primate Mountain Totem Pillars | 通臂灵猿图腾石柱 (Túténgzhù) | Viên Hầu Đồ Đằng Trụ | Giant rough-hewn stone pillars painted with ochre monkey and ape totems. | Tribal boundary marking stele |
| RAC-07 | Wood Spirit Living Tree Canopies | 木灵活树织巢 (Mùlíngcháo) | Mộc Linh Thụ Quan Thất | Dwellings formed from magically coaxed living tree branches and biolichen. | Wood Spirit aerial village |
| RAC-08 | Asura Blood-Bone Combat Arena | 修罗血斗骨场 (Xiūluózhǎng) | Tu La Huyết Cốt Đàn | Sunken sand pit bordered by rusted iron spikes and warrior trophies. | Combat trial ring |
| RAC-09 | Ghost-Soul Pale Lantern Hamlet | 游魂幽冥水乡 (Yóuhúnzhēn) | Quỷ Tộc Bạch Đăng Thôn | Eerie floating village where translucent spirit denizens drift between stilts. | Yin realm merchant village |
| RAC-10 | Giant Avian Cliffside Cloud Eyrie | 羽族绝壁鹰巢 (Yǔzúcháo) | Vũ Tộc Cự Sào Phong | Giant woven wicker platforms cantilevered over mile-deep abysses. | Flying race aerial aerie |
| RAC-11 | Snakefolk Sunken Egg Incubation Grotto| 灵蛇地宫温巢 (Língshécháo) | Xà Tộc Ấp Trứng Động | Warm humid caverns filled with soft river sand and glowing white serpent eggs. | Snake clan breeding nursery |
| RAC-12 | Borderland Multi-Species Trade Bazaar | 万灵杂处边榷市 (Biānquèshì) | Dị Tộc Biên Thùy Phường Thị | Neutral trading ground where beastmen, humans, and spirits barter exotic pelts. | Cosmopolitan border hub |

---

## Domain 14: Floating Terrains & Celestial Sky Crags (悬空浮岛与天外浮石) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| FLT-01 | Inverted Floating Rock Cone Base | 悬浮孤岛倒石锥 (Dàoshízhuī) | Huyền Không Đảo Căn Cơ | Teardrop-shaped floating island undersides trailing trailing vines and roots. | Floating island base tile |
| FLT-02 | Heavy Iron Chain Suspension Sky-Bridge| 天堑万丈铁锁桥 (Tiěsuǒqiáo) | Huyền Không Thiết Tỏa Kiều | Giant forged iron chains spanning bottomless voids between floating peaks. | Perilous walking bridge |
| FLT-03 | Sky-Cascading Cloud Waterfall | 垂天浮岛云飞瀑 (Chuítiānfēipù) | Huyền Không Phi Bộc | Waterfall pouring off the edge of a floating isle into empty air and clouds. | Spectacular animated hazard |
| FLT-04 | Magnetic Inversion Levitation Peak | 元磁极光浮峰 (Yuáncí Gūfēng) | Nguyên Từ Phong Đỉnh | High mountain shard hovering via magnetic repulsion; repels metal blades. | Flight / Special metal obstacle |
| FLT-05 | Floating Spirit Herb Terraced Ledge | 悬崖浮翠药台 (Fúcuìtái) | Huyền Không Dược Nhai | Tiered gardens floating in mid-air absorbing unpolluted heavenly sunlight. | Sky harvest farm plot |
| FLT-06 | Cloud-Anchored Stone Altar Platform | 罡风云海锚定台 (Yúnhǎitái) | Vân Hải Ngưng Phong Đài | Carved octagonal flagstone platform held stationary by four runic sky anchors. | Sky ritual / flight platform |
| FLT-07 | Drifting Asteroid Belt & Sky Scree | 浮空漂石乱流带 (Luànliúdài) | Phù Thạch Toái Đái | Swarm of small tumbling boulders suspended in anti-gravity current. | Dynamic platforming stepping stones |
| FLT-08 | High-Altitude Heavenly Windmill Rig | 凌霄迎罡风水轮 (Yíngfēngchē) | Ngự Phong Khí Cơ Đài | Giant wooden aerodynamic rotor harvesting high-altitude heavenly wind power. | Energy harvesting mechanism |
| FLT-09 | Cloud-Riding Pavilion on Floating Rock| 乘云悬石小榭 (Chéngyúnxiè) | Thừa Vân Huyền Thạch Đình | Small red-lacquer gazebo anchored to a solitary drifting cloud boulder. | High scenic resting point |
| FLT-10 | Sky-Rift Spatial Void Crack | 虚空碎裂裂缝 (Xūkōng Lièfèng) | Hư Không Vỡ Vụn Liệt Phùng | Jagged black rift in sky emitting spatial turbulence; instant death boundary. | Hard map boundary edge |

---

## Domain 15: Underwater Realms, Ocean Trenches & Water Palaces (水下世界与水底龙宫) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| UND-01 | Sunken Crystal Dragon Palace Ruins | 水晶龙宫残垣 (Shuǐjīnggōng) | Thủy Tinh Cung Điện Tàn Tích | Semi-translucent aquamarine quartz colonnades and collapsed shell arches. | Sunken underwater dungeon |
| UND-02 | Bioluminescent Coral Forest Thicket | 荧光千彩珊瑚林 (Shānhúlín) | Huỳnh Quang San Hô Lâm | Towering antler and brain coral glowing with soft pink, blue, and gold light. | Underwater forest biome |
| UND-03 | Abyssal Oceanic Trench Rifts | 万丈深海黑海沟 (Hǎigōu) | Vạn Trượng Hải Hác | Pitch-black chasms cutting into sea floor, leaking freezing abyssal water. | Deep sea impassable chasm |
| UND-04 | Water-Repelling Bubble Grotto Dome | 避水宝珠气泡洞 (Bìshuǐdòng) | Tị Thủy Tinh Giới Động | Air-filled underwater caverns preserved by ancient water-warding beads. | Walkable dry underwater haven |
| UND-05 | Giant Clam Pearl Seabed Bank | 巨蚌吐珠海沙洲 (Jùbàngzhōu) | Cự Bạng Châu Sa Than | White sandy dunes dotted with car-sized clams opening to reveal pearls. | Valuable gathering node / ambush |
| UND-06 | Sunken Fleet Shipwreck Graveyard | 千年沉船折戟墓 (Chénchuánmù) | Thủy Để Trầm Thuyền Mộ | Rotted oak and cedar hulls encrusted with barnacles, holding waterlogged loot. | Underwater salvage maze |
| UND-07 | Giant Kelp Forest Seaweed Maze | 遮日巨藻海带丛 (Jùzǎocóng) | Hải Tảo Cự Thung Mê Cung | Thick 30-meter vertical brown ribbons obstructing line-of-sight and slowing swim.| Underwater stealth hiding canopy |
| UND-08 | Submerged Geothermal Black Smoker Chimneys| 海底硫磺热液柱 (Rèyèzhù) | Hải Để Nhiệt Dịch Miệng Núi | Towering mineral chimneys belching superheated black water and mineral clouds. | Scalding thermal water hazard |
| UND-09 | Deep Sea Flood Dragon Sea-Eye Lair | 蹈海蛟龙海眼穴 (Hǎiyǎnxué) | Thủy Quái Hải Nhãn Thao | Massive swirling vortex drain hole on seabed serving as aquatic boss nest. | Underwater boss lair |
| UND-10 | Submerged Imperial Marble Sacred Way | 水底汉白玉神道 (Shuǐdǐ Shéndào) | Thủy Phủ Thạch Dũng Đạo | Ancient paved processional road submerged beneath clear lake waters. | Submerged road path tile |

---

## Domain 16: Underground Abyss, Caverns & Deep Earth (地底深渊与九幽洞府) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| SUB-01 | Giant Bioluminescent Mushroom Forest | 巨型荧光菌伞洞 (Jùjùndòng) | Cự Hình Huỳnh Quang Nấm Lâm | Multi-story purple and cyan mushrooms emitting ambient spores and dim light. | Subterranean forest biome |
| SUB-02 | Stalactite & Stalagmite Stone Pillars | 钟乳千柱连天林 (Zhōngrǔzhù) | Thạch Nhũ Thạch Măng Mê Cung | Massive calcified columns formed where ceiling drips meet floor mounds. | Underground natural obstacles |
| SUB-03 | Subterranean Magma River & Basalt Shore| 地火熔岩赤火溪 (Róngyánhé) | Địa Hỏa Nham Tương Khê | Searing orange molten rock rivers bordered by jagged black basalt rock shores. | Fire elemental river hazard |
| SUB-04 | Nether Black Water Sunless Lake | 九幽冥水绝命潭 (Jǐuyōután) | Cửu U Hắc Thủy Đàm | Pitch-black subterranean lake absorbing all light, home to eyeless pale fish. | Frigid water crossing |
| SUB-05 | Ancient Sunless Pre-Historic Stone City| 地底盲目石殿城 (Dìdǐ Shíchéng) | Địa Hạ Di Tích Thành Quách | Massive cyclopean gates, monoliths, and silent plazas buried miles beneath earth. | Subterranean ruin dungeon |
| SUB-06 | Thousand-Year Tree Deep Root Labyrinth| 万年古木穿地根 (Chuāndìgēn) | Vạn Niên Địa Căn Khổng Động | Gigantic petrified wood root networks forming ceilings, walls, and cages. | Root-walled tunnel maze |
| SUB-07 | Deep Chasm Abyssal Suspension Bridge | 绝壑千仞荡铁索 (Duànhuòsuǒ) | Địa Uyên Sách Kiều | Swaying wooden plank bridge crossing bottomless subterranean darkness. | Chasm crossing walkway |
| SUB-08 | Blind Subterranean Beast Burrow Colony | 幽暗盲兽穿山穴 (Mángshòuxué) | Địa Hạt Độc Trùng Oa | Clay and saliva tunnels dug by eyeless burrowing horrors. | Monster spawn tunnels |
| SUB-09 | Amethyst Luminescent Geode Chamber | 紫晶地髓聚灵穹 (Zǐjīngqiōng) | Tử Tinh Khảm Nham Quật | Vaulted cavern studded with giant purple crystal clusters humming with Qi. | High-tier mining chamber |
| SUB-10 | Echoing Wind Chasm / Earth Flute | 地籁天风回音壑 (Dìlàihè) | Địa Âm Phùng Phong Hác | Narrow geological cleft where underground air currents produce eerie melodies. | Sonic hazard / puzzle cavern |

---

## Domain 17: Peak Mortal Sects, Grand Arrays & Tribulation Platforms (巅峰宗门、护宗大阵与渡劫飞升) — 10 Categories
*(Covering Mortal Realms 6 to 9: Void Refinement 炼虚, Body Integration 合体, Great Ascension 大乘, Tribulation Crossing 渡劫)*

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| HMO-01 | Nascent Soul & Deva Seclusion Grotto | 洞天福地辟谷禁阁 (Bìgǔgé) | Nguyên Anh Lão Tổ Bế Quan Động | Heavily warded mountain grotto where supreme sect elders retreat for centuries. | Milestone elder NPC sanctuary |
| HMO-02 | Nine-Heaven Heavenly Tribulation Altar| 九重天劫引雷台 (Yǐnléitái) | Cửu Thiên Độ Kiếp Đài | Stepped obsidian pyramid encircled by lightning-grounding bronze pillars. | Breakthrough ascension arena |
| HMO-03 | Grand Sect-Protecting Formation Gate | 护山通天天门楼 (Tiānménlóu) | Hộ Sơn Đại Trận Thiên Môn | Colossal gatehouse projecting a golden dome barrier visible across provinces. | Grand faction fortress border |
| HMO-04 | Core Transformation Golden Elixir Pavilion| 金丹演化万宝楼 (Wànbǎolóu) | Kim Đan Các / Linh Bảo Các | Multi-eaved grand pagoda housing treasures and heavenly materials of mortal realm.| High-tier sect treasury |
| HMO-05 | Soul Transformation Void Meditation Hall| 化神悟道悬空大殿 (Wùdàodiàn) | Hóa Thần Hư Không Điện | Grand hall hovering above clouds with glass floor looking down upon continents. | Philosophical breakthrough site |
| HMO-06 | Giant Heavenly Mechanism Puppet Foundry | 天机机关千偶工坊 (Tiānjīgōng) | Thiên Cơ Khôi Lỗi Các | Colossal bronze foundries assembling mountain-sized mechanical war guardians. | Ancient tech / puppet factory |
| HMO-07 | Trans-Continental Ancient Teleport Array| 跨陆八荒古传送阵 (Chuánsòngzhèn)| Xuyên Châu Viễn Cổ Truyền Tống Trận| Octagonal stone monolith array fueled by top-grade spirit stones spanning oceans.| Long-distance continent travel |
| HMO-08 | Ancestral Patriarch Immortal Tablet Tower| 历代飞升祖师宝塔 (Zǔshītǎ) | Vạn Niên Tông Từ Trưởng Lão Tháp | Monumental 9-tier pagoda preserving life slips and spiritual portraits of ascended.| Sect inheritance shrine |
| HMO-09 | Floating Sect Master Palace (Qiankun Hall)| 乾坤倒转掌门大殿 (Zhǎngméndiàn) | Càn Khôn Đảo Chuyển Chưởng Môn Điện| The supreme floating palace anchoring the entire sect's spiritual leyline. | Faction capital center |
| HMO-10 | Heavenly Road Ascension Staircase (Dengtian)| 登仙万阶通天梯 (Tōngtiāntī) | Đăng Thiên Vạn Giai Thông Thiên Thê | Thousands of pure white jade steps ascending into golden clouds of the heavens. | Final mortal realm boundary |

---

## Summary of Total Categories (Across All 9 Mortal Realms)

| Domain Number | Domain Name (Vi / En / Zh) | Category Count |
|---|---|:---:|
| **Domain 1** | Terrains & Geological Formations (Địa Hình & Thổ Nhưỡng / 地形地质) | **26** |
| **Domain 2** | Natural Flora & Spiritual Plants (Linh Thảo & Tiên Mộc / 灵草仙木) | **28** |
| **Domain 3** | Water Systems & Spiritual Springs (Thủy Hệ & Linh Tuyền / 水系灵泉) | **20** |
| **Domain 4** | Environmental Hazards & Phenomena (Khí Hậu & Dị Tượng / 气候异象) | **20** |
| **Domain 5** | Mortal Settlements & Jianghu (Phàm Nhân Thôn Trấn & Giang Hồ / 凡人城邑) | **32** |
| **Domain 6** | Cultivation Sect Facilities & Dwellings (Tông Môn Cơ Sở & Động Phủ / 宗门设施) | **30** |
| **Domain 7** | Daoist, Buddhist & Folk Religious Sites (Đạo Quán, Phật Tự & Dân Gian Miếu / 宗教场所) | **26** |
| **Domain 8** | Crypts, Tombs & Ancient Ruins (Cổ Mộ & Di Tích / 陵墓古迹) | **22** |
| **Domain 9** | Low-Realm Fauna, Spirit & Shan Hai Beasts (Yêu Thú, Linh Thú & Sơn Hải Kinh / 妖兽灵兽) | **36** |
| **Domain 10** | Cultivation Artifacts & Paraphernalia (Pháp Bảo, Trận Pháp & Khí Cụ / 法宝器物) | **28** |
| **Domain 11** | Evil Sects & Demonic Cultivation (Ma Đạo Tông Môn & Tà Tu / 魔道宗门) | **12** |
| **Domain 12** | Mining, Metallurgy & Smelting (Khai Khoáng & Luyện Kim / 采矿冶炼) | **12** |
| **Domain 13** | Non-Human Races, Bloodlines & Enclaves (Dị Tộc, Yêu Tộc & Huyết Mạch / 种族异族) | **12** |
| **Domain 14** | Floating Terrains & Celestial Sky Crags (Huyền Không Phù Đảo / 悬空浮岛) | **10** |
| **Domain 15** | Underwater Realms & Dragon Palaces (Thủy Hạ Thế Giới & Thủy Cung / 水下世界) | **10** |
| **Domain 16** | Underground Abyss & Subterranean Depths (Địa Hạ Thế Giới & Cửu U / 地底深渊) | **10** |
| **Domain 17** | Peak Mortal Sects & Tribulation Platforms (Đỉnh Phong Tông Môn & Độ Kiếp / 渡劫飞升) | **10** |
| **TOTAL** | **Comprehensive 9-Realm Mortal World Xianxia Taxonomy** | **344 Categories** |
"""

def main():
    content = MD_PATH.read_text(encoding="utf-8")
    
    # 1. Update header description
    old_sub = "*Target World Tier: Mortal Realm (凡人界 / Cửu Châu) & Early Cultivation (Qi Condensation / Luyện Khí 练气, Foundation Establishment / Trúc Cơ 筑基, Early Core Formation / Kết Đan 结丹)*"
    new_sub = "*Target World Tier: Mortal World (Phàm Nhân Giới / Cửu Châu) — Complete 9 Mortal Realms Ladder (1. Qi Refining / 练气, 2. Foundation Establishment / 筑基, 3. Core Formation / 结丹, 4. Nascent Soul / 元婴, 5. Spirit Transformation / 化神, 6. Void Refinement / 炼虚, 7. Body Integration / 合体, 8. Great Ascension / 大乘, 9. Tribulation Crossing / 渡劫)*"
    
    if old_sub in content:
        content = content.replace(old_sub, new_sub)
    
    # Replace the old summary block at the end
    split_pos = content.find("## Summary of Total Categories")
    if split_pos != -1:
        base_content = content[:split_pos].rstrip()
    else:
        base_content = content.rstrip()
    
    updated_content = base_content + NEW_DOMAINS_TEXT
    MD_PATH.write_text(updated_content, encoding="utf-8")
    print(f"Updated {MD_PATH} successfully with 17 domains.")

if __name__ == "__main__":
    main()
