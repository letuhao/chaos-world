# -*- coding: utf-8 -*-
"""Appends Domains 18-21 (VFX, Secret Realms, Commerce, Calamities) to low_realm_cultivation_taxonomy.md,
completing the 386-category 21-domain master reference document.
"""

from __future__ import annotations
from pathlib import Path

MD_PATH = Path(
    r"C:\Users\NeneScarlet\.gemini\antigravity-ide\brain\7a8e638b-79b7-4ad0-9075-e3c4c3594f07\low_realm_cultivation_taxonomy.md"
)

NEW_DOMAINS_18_21 = """

## Domain 18: Atmospheric VFX, Seasonal Overlays & Particles (天气特效与灵气粒子) — 12 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| VFX-01 | Spring Peach Blossom & Willow Catkin Drift | 桃花柳絮随风舞 (Táohuāpiāo) | Đào Hoa Liễu Hư Phiêu Lạc | Soft pink petals and white fluff drifting diagonally across the screen in spring. | Seasonal screen particle overlay |
| VFX-02 | Autumn Ginkgo & Crimson Maple Leaf Swirl | 银杏红枫旋风 (Yínxìngfēng) | Ngân Hạnh Phong Diệp Toàn Phong | Golden and scarlet leaf clusters spiraling in wind gusts over mountain paths. | Seasonal screen particle overlay |
| VFX-03 | Winter Gentle Snow Flurry & Blizzard Streaks | 漫天飞雪狂风 (Fēixuěkuángfēng) | Băng Tuyết Cuồng Phong Lạc Tiết | White crystalline flakes drifting gently or whipping violently in blizzard gales. | Seasonal weather screen overlay |
| VFX-04 | Summer Monsoon Rain Sheet & Splash Ripples | 暴雨如注地面溅水 (Bàoyǔjiànshuǐ) | Bạo Vũ Như Chú Thủy Hoa | Angled rain streaks with concentric circular ripples on puddles and rivers. | Weather rain shader + impact VFX |
| VFX-05 | Ascending Cyan/Gold Spiritual Qi Particles | 升腾灵光粒子 (Língguāng) | Thanh Kim Linh Quang Thăng Đằng | Glowing luminescent motes rising from herb gardens, spirit veins, and fountains. | High-Qi indicator particle field |
| VFX-06 | Summer Reedbed & Water Pond Fireflies | 夏夜水泽萤火虫 (Yínghuǒchóng) | Hạ Dạ Đầm Trạch Huỳnh Hỏa Trùng | Pulsing yellow-green points of light bobbing gently over nighttime wetlands. | Nighttime ambient nature particle |
| VFX-07 | Baleful Yin-Qi & Cemetery Black Smoke Curls| 阴煞地气黑烟丝 (Yīnshàyān) | Cửu U Âm Sát Hắc Yên Ti | Wisps of black and violet smoke creeping along grave soils and demon rifts. | Yin/Corrupted ground aura VFX |
| VFX-08 | Toxic Swamp Miasma Spore Bubbles | 毒沼绿色气泡瘴气 (Dúzhǎopào) | Ngũ Độc Chướng Khí Huỳnh Khí Bào | Floating toxic green globules popping and emitting faint poisonous vapor. | Hazard area particle emitter |
| VFX-09 | Translucent Hexagonal Array Barrier Dome | 六角蜂窝护宗光幕 (Guāngmù) | Hộ Sơn Trận Pháp Quang Mạc | Shimmering hexagonal energy shield enveloping sect mountain crests. | Active defense barrier VFX |
| VFX-10 | Ground Bagua Runes Inscription Glow | 八卦阵图地面流光 (Bāguàliúguāng) | Địa Diện Bát Quái Lưu Quang Trận | Glowing golden runic calligraphy pulsing rhythmically on array platforms. | Combat arena array VFX |
| VFX-11 | Spatial Void Distortion Heat Shimmer Ripple| 空间扭曲涟漪 (Kōngjiān Liányī) | Hư Không Liệt Phùng Khí Lãng | Refractive optical heat ripple around active teleport arrays and void tears. | Teleport / Void distortion VFX |
| VFX-12 | Nine-Heaven Tribulation Clouds & Lightning | 渡劫劫云雷蛇狂舞 (Jiéyúnléishé) | Độ Kiếp Lôi Vân Điện Xà | Inky black swirling vortex with blinding blue/violet lightning serpents striking. | Ascension breakthrough event VFX |

---

## Domain 19: Secret Realms, Ancient Grottos & Inheritances (秘境洞天与古修遗府) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| SEC-R01| Ancient Hermit Sealed Cave Abode | 蔓藤枯石古修遗府 (Gǔxiūyífǔ) | Cổ Tu Sĩ Phong Ấn Động Phủ | Cliff cavern sealed by withered vines, cracked illusion stones, and yellow talismans. | Secret dungeon entrance |
| SEC-R02| Dao Enlightenment Sword-Intent Cliff | 万载剑痕悟道崖 (Wùdàoyá) | Vạn Niên Kiếm Ý Ngộ Đạo Nhai | Sheer rock precipice marked with ancient sword gouges still radiating sword intent.| Skill comprehension site |
| SEC-R03| Secret Realm Sky Fissure Portal | 秘境虚空传送裂口 (Bìjìnglièkǒu) | Bí Cảnh Thời Không Liệt Phùng | Swirling celestial void rift opening on specific lunar cycles to secret dimensions.| Timed portal event |
| SEC-R04| Ancient Nine-Tier Trial Tower | 远古九重试炼石塔 (Shìliàntǎ) | Cửu Trọng Thí Luyện Tháp | Weathered pagoda challenging cultivators to ascend floor-by-floor against phantoms.| Sequential combat trial dungeon |
| SEC-R05| Meditating Bone Inheritance Master | 枯骨真传玉简遗骸 (Kūgǔyíhái) | Bạch Cốt Chân Truyền Tọa Hóa | Petrified skeleton of ancient master sitting in lotus position holding jade slip.| High-tier skill inheritance node |
| SEC-R06| Grotto-Heaven Spiritual Medicine Pocket | 洞天药圃封闭灵田 (Dòngtiānpǔ) | Động Thiên Phúc Địa Dược Viên | Isolated micro-realm where 10,000-year herbs grow undisturbed by mortal seasons. | Ultra-rare harvestable herb biome |
| SEC-R07| Ancient Pill Recipe Monument Stele | 太古丹方残断石碑 (Dānfāngbēi) | Thái Cổ Đan Phương Tàn Phá Bi | Weathered granite tablet carved with archaic seal script describing lost pills. | Crafting recipe discovery stele |
| SEC-R08| Ancient Five-Element Restriction Gate | 五行禁制流光石门 (Wǔxíngshímén) | Ngũ Hành Phong Ấn Cấm Chế Môn | Stone portal locked by Five Element colored seals requiring matching Qi to unseal.| Puzzle gateway barrier |
| SEC-R09| Giant Divine Beast Skeleton Bridge | 巨兽脊骨天堑桥梁 (Shòugǔqiáo) | Thượng Cổ Thần Thú Cốt Kiều | Colossal fossilized spine of a primordial behemoth spanning a bottomless chasm. | Landmark natural bridge |
| SEC-R10| Heavenly Book Floating Jade Pedestal | 天书悬浮传功玉台 (Tiānshūtái) | Thiên Thư Huyền Không Ngọc Thai | Octagonal white jade dais where a glowing golden celestial tome hovers in mid-air.| Supreme legacy inheritance pedestal|

---

## Domain 20: Cultivation Commerce, Auctions & Wandering Caravans (坊市拍卖与行商) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| COM-01 | Immortal Treasure Grand Auction Hall | 万宝巨型拍卖大殿 (Pàimàidiàn) | Đấu Giá Đại Điện / Vạn Bảo Các | Tiered amphitheater with silk VIP curtain boxes and central display stage. | Rare treasure auction house |
| COM-02 | Underground Cultivator Black Market Stalls | 阴暗黑市斗笠地摊 (Hēishì) | Hắc Thị Bí Mật Than Vị | Dimly lit subterranean alley of cloaked vendors selling contraband and stolen pills.| Illegal goods exchange hub |
| COM-03 | Traveling Flying-Skiff Merchant Caravan | 云游飞舟泊桩商埠 (Fēizhōushāng) | Vân Du Thương Thuyền Bạc Thao | Flying wooden galleons moored to mountain peaks selling exotic continent curios. | Traveling luxury vendor |
| COM-04 | Spiritual Treasure Appraisal Pavilion | 法宝灵物鉴宝台 (Jiànbǎotái) | Giám Bảo Các / Pháp Bảo Đài | Brass counters with magnifying crystals and spiritual scales to value relics. | Item identification / appraisal |
| COM-05 | Spirit Stone Bank & Escrow Vault | 灵石庄通商钱庄 (Língshízhuāng) | Tiền Trang / Linh Thạch Khố | Reinforced stone vault guarded by puppets, storing sect spirit stone promissory notes.| Banking and wealth storage |
| COM-06 | Exotic Beast Mount Trading Corral | 灵兽驯化交易围栏 (Shòuchǎng) | Linh Thú Tọa Kỵ Giao Dịch Trường | Heavy wooden paddocks showcasing tame crane mounts, spirit wolves, and armored oxen.| Mount vendor & beast stables |
| COM-07 | Bulk Herb & Pill Wholesale Warehouse | 宗门大宗药材栈房 (Yàocáicāng) | Linh Dược Bách Hóa Thương Khố | Multi-story timber storage barns packed with burlap bags of roots and ceramic urns.| Bulk commodity trade warehouse |
| COM-08 | Rogue Cultivator Flea Market Ground Cloth | 散修置换草席地摊 (Sǎnjiē) | Tán Tu Bãi Than Bạch Bố | Woven straw mats spread with rusted iron daggers, chipped talismans, and seeds. | Low-tier player barter market |
| COM-09 | Bounty Hunter & Mercenary Guild Hall | 斩妖除魔赏金公会 (Shǎngjīnháng) | Tiêu Cục Tán Tu Trảm Yêu Đường | Tavern-like lodge with wooden bounty plaques for rogue demonic cultivators and beasts.| Mercenary quest guild hub |
| COM-10 | Smuggler Hidden Waterway Pier | 水道走私黑水暗埠 (Sīyùnmǎtóu) | Thủy Vận Tư Vận Ám Đầu | Camouflaged river cove behind weeping willows where illegal ores are loaded onto barges.| Contraband smuggling dock |

---

## Domain 21: World Calamities, Beast Tides & War Ruins (浩劫战墟与凶煞险地) — 10 Categories

| ID | English Name | Hanzi / Pinyin | Sino-Vietnamese | Category Scope & Novel/Lore Grounding | Gameplay & Asset Type |
|---|---|---|---|---|---|
| CAL-01 | Beast Tide Breached City Gate | 狂暴兽潮撞裂城门 (Shòucháomén) | Thú Triều Xung Phá Thành Môn | Iron-reinforced gates splintered inward, surrounded by blood pools and crushed spikes.| Post-siege ruin gateway |
| CAL-02 | Smashed Iron Palisade & Claw Gouges | 碎裂鹿角巨爪撕裂痕 (Zhùlùjiǎo) | Cự Thú Trảo Ngân Thiết Sách | Defensive wooden chevau-de-frise snapped like twigs, marked by 3-meter claw gouges. | Breached barricade obstacle |
| CAL-03 | Beast Corpse Slaughter Trench | 万妖伏诛积尸大坑 (Jīshīkēng) | Yêu Thú Thi Hài Đống | Deep burial trenches filled with bloated demonic beast bodies waiting to be burned.| Diseased terrain hazard |
| CAL-04 | Righteous-Demonic Divine Crater Battlefield | 大能法术轰击巨坑 (Dànéngkēng) | Chính Ma Đại Chiến Thần Hãm | Enormous glass-rimmed crater caused by high-realm divine technique detonations. | Blast crater terrain |
| CAL-05 | Fallen Giant Flying Sword Wreckage | 斜插大地万年断残剑 (Duànjiàn) | Đoạn Liệt Cự Đại Phi Kiếm | 30-meter rusted divine blade driven into granite bedrock, humming with residual Qi.| Giant weapon landmark obstacle |
| CAL-06 | Collapsed Mine Shaft & Trapped Timbering | 坑道垮塌木架碎裂处 (Kuàngtā) | Khoáng Nạn Băng Tháp Hãm | Crushed timber frames and tumbled boulders blocking access to lower mine galleries.| Blocked path obstacle puzzle |
| CAL-07 | Heavenly Tribulation Scorched Glass Earth | 劫火燎原琉璃焦坑 (Jiāokēng) | Thiên Hỏa Phần Thiêu Thao | Vitrified translucent earth where heaven's tribulation fire liquefied solid bedrock. | High heat / scorched earth terrain |
| CAL-08 | Depleted Leyline Dried Sinkhole | 灵气抽干龟裂干涸坑 (Línggānkēng) | Linh Mạch Khô Kiệt Thiên Khanh | Hexagonal cracked desert pit where an ancient spirit spring was drained dry. | Desolate parched sinkhole |
| CAL-09 | Desecrated Ancestor Tablet Shrine Ruins | 战火残毁祖师宗祠 (Cáncí) | Phá Bại Tông Miếu Đoạn Bích | Collapsed ancestral temple with shattered spirit tablets and toppled stone pillars.| Lootable sacred ruins |
| CAL-10 | Ambushed Escort Wagon Caravan Ruins | 遇袭劫掠起火断车 (Duànchē) | Bị Kiếp Tiêu Xa Hỏa Thiêu Tàn | Overturned baggage wagons with broken wheel spokes, spilled crates, and cut ropes.| Wilderness loot ambush encounter |

---

## Summary of Total Categories (Across All 21 Macro-Domains)

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
| **Domain 18** | Atmospheric VFX, Seasonal Overlays & Particles (Khí Quyển VFX & Linh Lực / 天气特效) | **12** |
| **Domain 19** | Secret Realms, Grotto-Heavens & Inheritances (Bí Cảnh & Động Thiên Phúc Địa / 秘境洞天) | **10** |
| **Domain 20** | Cultivation Commerce, Auctions & Wandering Caravans (Phường Thị & Đấu Giá / 坊市拍卖) | **10** |
| **Domain 21** | World Calamities, Beast Tides & War Ruins (Thiên Tai, Thú Triều & Chiến Địa / 浩劫战墟) | **10** |
| **TOTAL** | **Comprehensive 21-Domain Living Xianxia World** | **386 Categories** |
"""

def main():
    content = MD_PATH.read_text(encoding="utf-8")
    
    # Strip old summary table if present
    split_pos = content.find("## Summary of Total Categories")
    if split_pos != -1:
        base_content = content[:split_pos].rstrip()
    else:
        base_content = content.rstrip()
    
    updated_content = base_content + NEW_DOMAINS_18_21
    MD_PATH.write_text(updated_content, encoding="utf-8")
    print(f"Updated {MD_PATH} with Domains 18-21 (total 386 categories).")

if __name__ == "__main__":
    main()
