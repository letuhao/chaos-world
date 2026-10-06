# Ancient Chinese Mortal World Pack (Phàm Nhân Trần Thế & Sơ Nhập Tu Chân)
*Comprehensive World Map Asset Specification for Ancient Chinese Mortal Civilizations, Daily Life, Law, Warfare & Low-Realm Cultivation*

---

## 1. Overview & Vision
This pack models the vibrant, grounded **Mortal World of Ancient China (Cửu Châu Phàm Trần)**. It captures the authentic contrast between the everyday struggles of agrarian peasants, the rigid majesty of imperial dynastic administration, the blood-and-honor conflicts of the Jianghu underworld, and the nascent mysteries of low-realm rogue cultivators (Qi Condensation & Foundation Establishment).

* **Target Asset Count**: ~730 – 750 assets
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

## 2. Category Architecture & Budget

| # | Category ID | Name (English / Vietnamese) | Asset Count | Core Gameplay Role & Themes |
|---|---|---|:---:|---|
| **1** | `terrain_and_surface` | Terrain & Soils *(Địa Hình & Thổ Nhưỡng)* | **45** | Yellow loess soil, fertile river delta loam, muddy paddy fields, stone pavers, dry cracked clay, gravel paths. |
| **2** | `path_and_way` | Roads & Waterways *(Đường Đi, Cầu Cống & Kênh Đào)* | **50** | Wheel-rut dirt courier highways, stone arched bridges, village alleys, canal embankments, wooden trestle walkways. |
| **3** | `civilian_settlement` | Village & Town Living *(Thôn Trang, Thị Trấn & Dân Cư)* | **65** | Courtyard residences (siheyuan), thatched cottages, tea houses, wine taverns, pharmacies, ancestral clan halls, watermills. |
| **4** | `imperial_and_law` | Imperial Administration & Law *(Nha Môn, Công Đường & Quân Pháp)* | **45** | Magistrate courts (Nha Môn), Drum of Grievance, county jails, pillories, courier post-stations (dịch trạm), wanted poster noticeboards. |
| **5** | `military_and_fortress` | Fortresses, Gates & Borders *(Thành Quách, Tiêu Điểm & Biên Giới)* | **60** | Rammed-earth walls, crenellated brick bastions, gatehouses with portcullis, signal beacon spires, military barracks, training grounds. |
| **6** | `war_and_battlefield` | Warfare, Siege & Battle Ruins *(Chiến Trường, Công Thành & Tàn Tích)* | **55** | Spiked barricades (cheval-de-frise), catapult batteries, broken supply wagons, battle arrows stuck in earth, war drums, siege ladders. |
| **7** | `river_and_maritime` | Canal, Fishery & River Docks *(Bến Thuyền, Kênh Đào & Thủy Đạo)* | **45** | Wooden piers, houseboats, fishing sampans, cargo grain barges, ferry crossings, fish-drying nets, water toll checkpoints. |
| **8** | `trade_craft_industry` | Industry, Crafts & Sericulture *(Nghề Thủ Công, Lò Gốm & Khai Khoáng)* | **55** | Salt evaporation flats, brick/ceramic kilns, charcoal burning mounds, iron smithy furnaces, dye vats with hanging textiles, silk reeling sheds. |
| **9** | `outlaw_and_jianghu` | Bandits, Wilderness Inns & Shadow World *(Sơn Tặc, Hắc Điếm & Tiêu Cục)* | **50** | Mountain bandit stockades, skull boundary poles, remote wilderness taverns (Dragon Gate Inn style), secret cellars, caravan escort wagons. |
| **10** | `folk_religion_fengshui` | Folk Shrines, Graves & Feng Shui *(Miếu Thần, Lăng Mộ & Phong Thủy)* | **50** | Earth God shrines (Thổ Địa Miếu), City God altars, roadside warding stones (Thạch Cảm Đương), earthen burial mounds, paper money burning braziers. |
| **11** | `low_realm_cultivation` | Low-Tier Sects & Qi Condensation *(Sơ Nhập Tu Tiên & Môn Phái Dân Gian)* | **60** | Martial training halls, wooden dummies (mộc nhân thung), iron sand pans, bronze medicinal stoves, low-grade herbal patches, spirit-testing steles. |
| **12** | `destructible_and_loot` | Destructibles & Treasure Containers *(Vật Phá Hủy & Rương Báu)* | **50** | Glazed wine jars, wooden supply crates, grain urns, merchant lockboxes, bandit iron chests, loose paving caches. |
| **13** | `creature_and_denizen` | Commoners, Troops & Draft Beasts *(Nhân Vật, Binh Sĩ & Súc Vật)* | **85** | **Civilians**: Peasants, dockworkers, merchants, elders.<br>**Martial**: Town guards, bandit raiders, caravan guards, low-qi cultivators.<br>**Fauna**: Water buffaloes, mules, pack horses, guard dogs, pigs, ducks. |
| **14** | `flora_and_ambience` | Plants, Trees & Atmospheric Dressing *(Thực Vật, Cảnh Quan & Khí Quyển)* | **65** | Weeping willows, ginkgo trees, peach blossoms, bamboo groves, red festival lanterns, wine flag banners, stone wellheads, scarecrows. |
| **∑** | **Total Planned Assets** | **All Categories Combined** | **~730** | **Complete World Simulator & Action RPG Content Matrix** |

---

## 3. Sub-Category Gaps & Gameplay Verification

### Identified Gaps & Granular Solutions
1. **Seasonal / Agricultural Rhythms (Nông Nghiệp Thời Vụ)**:
   - Need clear differentiation between dry harvest seasons and wet planting (flooded paddy tiles vs sun-baked wheat threshing floors). Handled under `terrain_and_surface` and `trade_craft_industry`.
2. **Jianghu Transit & Roadside Safety (Dịch Trạm & Tiêu Điểm)**:
   - Long-distance travel between mortal cities requires milestones (dặm đình), rest sheds (lương đình), and courier horse-changing stalls. Handled under `path_and_way` and `imperial_and_law`.
3. **Mortal Crime vs Supernatural Low Qi**:
   - Mortal crimes use mundane iron chains, execution stages, and wooden cages. Low-realm entities use crude yellow paper hexes, peach-wood demon-dispelling swords (kiếm gỗ đào), and copper bell talismans. Handled under `folk_religion_fengshui` and `low_realm_cultivation`.
4. **Collision Roles**:
   - `ground_contact` for trees, streetlamps, banners, and archways (allowing walking behind/under).
   - `solid` / `full_body` for heavy ramparts, magistrate buildings, and boulders.
   - `walk_surface` for bridge decks, canal walkways, and stone steps.
   - `none` for decals, dropped litter, weeds, and shallow water puddles.
