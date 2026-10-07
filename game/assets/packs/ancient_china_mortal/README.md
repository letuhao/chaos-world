# Ancient Chinese Mortal World Pack (Phàm Nhân Trần Thế & Sơ Nhập Tu Chân)
*Comprehensive World Map Asset Specification for Ancient Chinese Mortal Civilizations, Daily Life, Law, Warfare, Modular Architecture, Geology & Low-Realm Cultivation*

---

## 1. Overview & Vision
This pack models the vibrant, grounded **Mortal World of Ancient China (Cửu Châu Phàm Trần)**. It captures the authentic contrast between the everyday struggles of agrarian peasants, the rigid majesty of imperial dynastic administration, the blood-and-honor conflicts of the Jianghu underworld, and the nascent mysteries of low-realm rogue cultivators (Qi Condensation & Foundation Establishment).

* **Total Asset Count**: **2,280 assets** across 19 categories (2,280 Completed, Runtime-Installed & Godot 4.7-Imported).
* **Standard Tile Unit**: 128x128 px
* **Sub-cell Collision Unit**: 32x32 px (4x4 subcells per tile)
* **Camera & Viewport**: Orthographic straight-down (~45° top-down projection, ground-facing silhouettes, no perspective convergence, no horizon).
* **Art Style**: Anime-painted gouache, dark ink contours (`#263A35`), broad legible value planes, upper-left directional daylight (315°), grounded material-led colors.
* **Palette**:
  * *Earth & Loess*: Yellow loess clay (`#D4A359`), sun-warmed ochre loam (`#B88648`), river silt grey (`#7D827A`), charcoal grey tile (`#3D4246`).
  * *Life & Timber*: Weeping willow greens (`#5E784D`, `#889A5E`), coarse unbleached hemp linen (`#EADBB6`), weathered pine timber (`#6B4C35`).
  * *Imperial & Civic*: Imperial vermilion lacquer (`#A8382B`), bronze patina (`#4A6B5D`), wrought iron / soot black (`#2A2826`), indigo dye (`#384D66`).
  * *Low-Realm Qi Touches*: Pale spirit cyan (`#89C4C2`), cinnabar talisman red (`#C24D38`), raw brass yellow.

---

## 2. Category Architecture & Budget (19 Categories, 2,280 Assets)

| # | Category ID | Name (English / Vietnamese) | Asset Count | Status | Core Gameplay Role & Themes |
|---|---|---|:---:|:---:|---|
| **1** | `terrain_and_surface` | Terrain & Soils *(Địa Hình & Thổ Nhưỡng)* | **45** | Generated | Yellow loess soil, fertile river delta loam, muddy paddy fields, stone pavers, dry cracked clay, gravel paths. |
| **2** | `path_and_way` | Roads & Waterways *(Đường Đi, Cầu Cống & Kênh Đào)* | **50** | Generated | Wheel-rut dirt courier highways, stone arched bridges, village alleys, canal embankments, wooden trestle walkways. |
| **3** | `civilian_settlement` | Village & Town Living *(Thôn Trang, Thị Trấn & Dân Cư)* | **65** | Generated | Courtyard residences (siheyuan), thatched cottages, tea houses, wine taverns, pharmacies, ancestral clan halls, watermills. |
| **4** | `imperial_and_law` | Imperial Administration & Law *(Nha Môn, Công Đường & Quân Pháp)* | **45** | Generated | Magistrate courts (Nha Môn), Drum of Grievance, county jails, pillories, courier post-stations (dịch trạm), wanted poster noticeboards. |
| **5** | `military_and_fortress` | Fortresses, Gates & Borders *(Thành Quách, Tiêu Điểm & Biên Giới)* | **60** | Generated | Rammed-earth walls, crenellated brick bastions, gatehouses with portcullis, signal beacon spires, military barracks, training grounds. |
| **6** | `war_and_battlefield` | Warfare, Siege & Battle Ruins *(Chiến Trường, Công Thành & Tàn Tích)* | **55** | Generated | Spiked barricades (cheval-de-frise), catapult batteries, broken supply wagons, battle arrows stuck in earth, war drums, siege ladders. |
| **7** | `river_and_maritime` | Canal, Fishery & River Docks *(Bến Thuyền, Kênh Đào & Thủy Đạo)* | **45** | Generated | Wooden piers, houseboats, fishing sampans, cargo grain barges, ferry crossings, fish-drying nets, water toll checkpoints. |
| **8** | `trade_craft_industry` | Industry, Crafts & Sericulture *(Nghề Thủ Công, Lò Gốm & Khai Khoáng)* | **55** | Generated | Salt evaporation flats, brick/ceramic kilns, charcoal burning mounds, iron smithy furnaces, dye vats with hanging textiles, silk reeling sheds. |
| **9** | `outlaw_and_jianghu` | Bandits, Wilderness Inns & Shadow World *(Sơn Tặc, Hắc Điếm & Tiêu Cục)* | **50** | Generated | Mountain bandit stockades, skull boundary poles, remote wilderness taverns (Dragon Gate Inn style), secret cellars, caravan escort wagons. |
| **10** | `folk_religion_fengshui` | Folk Shrines, Graves & Feng Shui *(Miếu Thần, Lăng Mộ & Phong Thủy)* | **50** | Generated | Earth God shrines (Thổ Địa Miếu), City God altars, roadside warding stones (Thạch Cảm Đương), earthen burial mounds, paper money burning braziers. |
| **11** | `low_realm_cultivation` | Low-Tier Sects & Qi Condensation *(Sơ Nhập Tu Tiên & Môn Phái Dân Gian)* | **60** | Generated | Martial training halls, wooden dummies (mộc nhân thung), iron sand pans, bronze medicinal stoves, low-grade herbal patches, spirit-testing steles. |
| **12** | `destructible_and_loot` | Destructibles & Treasure Containers *(Vật Phá Hủy & Rương Báu)* | **50** | Generated | Glazed wine jars, wooden supply crates, grain urns, merchant lockboxes, bandit iron chests, loose paving caches. |
| **13** | `creature_and_denizen` | Commoners, Troops & Draft Beasts *(Nhân Vật, Binh Sĩ & Súc Vật)* | **85** | Generated | Peasants, dockworkers, merchants, elders, town guards, bandit raiders, caravan guards, low-qi cultivators, water buffaloes, mules, horses, guard dogs, pigs. |
| **14** | `flora_and_ambience` | Plants, Trees & Atmospheric Dressing *(Thực Vật, Cảnh Quan & Khí Quyển)* | **65** | Generated | Weeping willows, ginkgo trees, peach blossoms, bamboo groves, red festival lanterns, wine flag banners, stone wellheads, scarecrows. |
| **15** | `modular_architecture_timber` | Modular Timber Architecture *(Kiến Trúc Gỗ Lắp Ghép & Đẩu Củng)* | **450** | Generated | Granular modular construction kit: carved granite plinths, curbstones, balustrades, dougong bracket clusters, tie-beams, lattice paper windows, moon gates, swept flying eaves, wind bells, covered verandas, beauty benches. |
| **16** | `mountain_cliff_geology` | Mountain Cliffs, Karst & Waters *(Địa Chất Núi Non, Vách Đá & Thác Nước)* | **350** | Generated | Yellow loess bluffs, stratified limestone cliffs, Danxia gorges, Guilin/Zhangjiajie karst spires, cliff-hanging shandao timber roads, talus scree, caverns, grottos, roaring waterfalls, cascading pools, stepping stones. |
| **17** | `flora_and_forest_ecology` | Forest Ecology & Wild Undergrowth *(Hệ Sinh Thái Rừng & Cây Cối Rậm Rạp)* | **250** | Generated | Ancient Huangshan dragon pines, wind-sheared conifers, giant Moso & purple bamboo groves, flowering azaleas, climbing ivy, wetland lotus ponds, and rare wild medicinal herbs (century ginseng, purple lingzhi, snow lotus). |
| **18** | `urban_street_and_market` | Urban Street Dressing & Market Stalls *(Phố Phường Sầm Uất, Chợ Búa & Biển Hiệu)* | **250** | Generated | Street food hawker stalls, three-tier fruit racks, balance scales, carved lacquer shop plaques, billowing tavern flags, oilpaper lanterns, milestone steles, night-watch gong stands, deep cart ruts, puddles. |
| **19** | `rural_farming_and_pastoral` | Rural Farming, Irrigation & Pastoral *(Nông Thôn Thâm Canh, Thủy Lợi & Chăn Nuôi)* | **200** | Generated | Colossal river norias (tongche), bamboo aqueduct flumes, dragon-bone pedal pumps, mud-wattle pigsties, thatched buffalo sheds, gourd trellises, sun-drying pepper mats, conical haystacks, stone grain roller mills. |
| **∑** | **Total Pack Assets** | **All 19 Categories Combined** | **2,280** | **2,280 Generated (100%)** | **Complete Ancient Chinese Mortal World Simulation Matrix** |

---

## 3. Comprehensive Diversity Audit & Metrics

An exhaustive programmatic multi-dimensional audit of all 2,280 entries in the manifest reveals state-of-the-art variety and balance:

### 3.1 Footprint Distribution (Width x Height cells)
The pack balances small modular dressing tiles with medium structures and landmark setpieces:
* **1x1 cells** (128x128 px): 940 assets (41.2%) — detail props, single pillars, curbstones, lanterns, flora tufts, decals.
* **2x1 cells** (256x128 px): 522 assets (22.9%) — wall bays, tie-beams, flumes, market tables, benches, ledges.
* **2x2 cells** (256x256 px): 414 assets (18.2%) — moon gates, pavilions, animal pens, boulders, mature pines, kiosks.
* **3x2 cells** (384x256 px): 108 assets (4.7%) — paifangs, grand cliffs, caverns, communal corrals, granaries.
* **3x1 cells** (384x128 px): 100 assets (4.4%) — long ridge paths, footbridges, bamboo grove walls, long flumes.
* **1x2 cells** (128x256 px): 97 assets (4.3%) — vertical plaques, tall columns, hanging banners, cliff chimneys.
* **3x3 cells** (384x384 px): 52 assets (2.3%) — ancient giant pines, threshing floors, karst mesas, crossroads hubs.
* **Large Landmarks (4x2, 4x3, 4x4, 5x4, 3x4)**: 37 assets (1.6%) — monumental waterfalls, grand palace halls, river karst islands.

### 3.2 Cultivation Element Spectrum
Unlike monochromatic generic packs, assets carry authentic Daoist / Wuxia elemental affinities:
* **Mortal (Phàm Trần)**: 654 (28.7%) — civic steles, noticeboards, market stalls, granaries, courtyards.
* **Water (Thủy)**: 322 (14.1%) — riverbanks, norias, lotus ponds, wellheads, waterfall torrents, siltstone.
* **Earth (Thổ)**: 274 (12.0%) — loess bluffs, rammed earth walls, fieldstones, pigsties, mud silos.
* **Wood (Mộc)**: 230 (10.1%) — timber joinery, pines, forest underbrush, scholar gardens, herb gardens.
* **Wind (Phong)**: 199 (8.7%) — billowing flags, wind chimes, swaying bamboos, shadoof lifters, ridge overlooks.
* **Metal (Kim)**: 171 (7.5%) — balance scales, weaponsmiths, bronze gongs, iron ore boulders, limestone.
* **Yang (Dương / Thái Dương)**: 154 (6.8%) — golden glazed tiles, sun-cured harvest racks, lightning crags, lingzhi herbs.
* **Yin (Âm / U Minh)**: 142 (6.2%) — ancestral cliff tombs, black bamboo, dark grottos, mossy ruins, withered lotus.
* **Fire (Hỏa)**: 131 (5.7%) — night-watch braziers, scorched walls, blacksmith forges, baozi steamers, beacon fires.

### 3.3 Material Distribution
* **Wood**: 619 (27.1%)
* **Stone**: 519 (22.8%)
* **Plant**: 218 (9.6%)
* **Bamboo**: 174 (7.6%)
* **Earth**: 116 (5.1%)
* **Flesh / Denizen**: 85 (3.7%)
* **Brick**: 70 (3.1%)
* **Iron**: 66 (2.9%)
* **Bronze**: 60 (2.6%)
* **Straw**: 57 (2.5%)
* **Water**: 49 (2.1%)
* **Ceramic**: 43 (1.9%)
* **Tile**: 42 (1.8%)
* **Silk**: 31 (1.4%)
* **Cloth**: 29 (1.3%)
* **Paper**: 26 (1.1%)
* **Lacquer**: 13 (0.6%)

### 3.4 Interactivity & Verbs
* **Interactive Assets**: **2,138 assets (93.8%)** feature contextual, high-immersion gameplay verbs (`talk`, `walk_along`, `enter`, `inspect_pillar`, `admire_flying_eave`, `knock_wall`, `listen_wind_bell`, `peer_through_window`, `cross_stepping_stones`, `draw_well_water`, `harvest_medicinal_herb`, `crank_dragonbone_pump`, `hide_in_haystack`, `weigh_goods_scale`, etc.).
* **Destructible Assets**: **347 assets (15.2%)** feature combat destruction, breaching, and resource gathering.

### 3.5 Semantic Uniqueness & Vocabulary
* **Unique IDs**: 2,280 / 2,280 (0 duplicates)
* **Unique English Names**: 2,280 / 2,280 (0 duplicates)
* **Unique Hanzi**: 2,280 / 2,280 (0 duplicates)
* **Unique Vietnamese Names**: 2,280 / 2,280 (0 duplicates)
* **Vocabulary Tokens**: 3,679 distinct descriptive tokens in production prompts.

---

## 4. Visual Benchmark & Approved Generation Recipe

Following comprehensive model & adapter comparison benchmarks, the official generation recipe for the **Ancient Chinese Mortal World** pack is locked:

* **UNET Checkpoint**: `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors`
* **Primary LoRA Adapter**: `krea2/Scottie__Krea2.safetensors` (Node ID `917`) at **weight = 1.0**
* **Sampler Parameters**: `euler_ancestral`, Scheduler: `beta`, Steps: `8` (standard) to `10` (complex landmarks), CFG: `1.0`
* **Background Removal**: `RMBG-2.0` (`process_res: 1024`, `sensitivity: 0.01`, Background: `Alpha`)
* **Style Qualities**:
  * Authentic Chinese vernacular architecture (timber mortise-and-tenon framing, straw thatch, loess plaster, rustic dry-stone masonry).
  * Crisp ink contours (`#263A35`) and high structural legibility without visual muddying.
  * Consistent ~45° orthographic top-down RPG projection with grounded contact pivots.
