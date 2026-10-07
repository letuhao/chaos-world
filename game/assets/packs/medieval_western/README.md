# Medieval Western Living World Pack (Lãnh Địa Phong Kiến & Thế Giới Sống Phương Tây)
*Comprehensive 2D Top-Down World Map Asset Specification for High & Late Medieval European Civilization, Feudal Crossroads, Manorial Supply Chains, Domestic Traces, and Gothic Architecture*

---

## 1. Overview & Vision: What Makes a Western World Truly 'Living'?
To transcend a static video-game backdrop and construct an authentic **Living World (Thế Giới Sống Động)**, this pack models the complete physical, social, and ecological reality of Medieval Europe across **7 Life Spheres** and **48 Specialized Categories** totaling **5,600 assets**.

### The 5 Pillars of Medieval Living World Design
1. **Cultural Crossroads (Giao Lộ Văn Hóa)**: Europe was never a monolithic monoculture. A living world reflects the porous friction of frontiers: Anglo-Norman feudal heartlands, red-brick Hanseatic burgher towns, turf-roofed Nordic coastal havens, Moorish arcaded patios in Al-Andalus, Slavic taiga logcraft, Celtic highland crannogs, and Byzantine/Crusader outposts.
2. **Complete Supply Chains (Chuỗi Cung Ứng Khép Kín)**: Every loaf of rye bread and iron horseshoe has an origin. The world contains full physical infrastructure: strip-farmed fields, scythes, ox-plows, threshing barns, water/wind mills, miller hoppers, bakeries, sheep folds, wool shears, dye vats, weavers' looms, bloomery iron furnaces, charcoal hearths, and blacksmith anvils.
3. **Intimate Traces of Daily Domesticity (Dấu Vết Đời Sống Thường Nhật)**: True life is found in what people leave behind: steaming manure middens behind pigsties, linen washing lines drying in breezes, hearth ash heaps, chopping blocks with lodged iron axes, puddle ruts carved by wooden cartwheels, and herb gardens drying sprigs of thyme.
4. **Micro-Fauna, Pests & Ecological Sub-layers (Hệ Sinh Thái & Sinh Vật Vi Mô)**: Pigeons roosting on cathedral spires, rats rummaging grain sacks, magpies perched on gallows, barn swallow nests beneath timber eaves, frogs in fen bogs, and rooting semi-wild swine in beech woods.
5. **Feudal & Spiritual Social Tensions (Xung Đột Xã Hội & Đức Tin)**: The visual dialogue between serf hovels of wattle-and-daub huddled beneath monumental limestone cathedrals; tithe barns taking grain from hungry peasants; gibbets outside city gates; plague quarantine crosses; and rogue forest outlaws hiding beyond the sheriff's reach.

### Technical Specifications
* **Total Categories**: **48 Categories** across **7 Life Spheres**
* **Total Asset Target**: **5,600 assets**
* **Total Subcategories**: **250 distinct subcategories**
* **Standard Reference Tile**: 128x128 px
* **Sub-cell Collision Unit**: 32x32 px (4x4 subcells per tile)
* **Camera & Viewport**: Orthographic top-down (~45° projection for vertical buildings, foliage, and props; 90° overhead plan for terrain surfaces, pavements, and ground decals).
* **Art Style**: Gouache hand-painted anime style with dark ink contour lines (`#263A35`), grounded historical medieval European palette, upper-left directional daylight (315°).
* **Color Palette**:
  * *Stone & Masonry*: Ashlar limestone grey (`#8A8D8F`), aged mortar cream (`#DFD7C6`), dark Welsh slate (`#4A5568`), river cobblestone (`#5A6065`), Hanseatic red brick (`#8A3324`).
  * *Timber & Thatch*: Aged English oak timber (`#5C4033`), weathered chestnut (`#785338`), golden thatch straw (`#C7A75C`), whitewashed wattle-and-daub (`#EFE6D5`).
  * *Heraldic & Court*: Royal heraldic vermilion (`#9B2C2C`), French royal azure (`#2B6CB0`), knightly lion gold (`#D69E2E`), liturgical bishop purple (`#553C9A`), iron soot black (`#2D3748`).
  * *Nature & Ecology*: Primeval oak moss green (`#4A5D3E`), damp peat bog brown (`#3D3028`), highland heather purple (`#6B4668`), autumn beech leaf russet (`#A0522D`).

---

## 2. Category Architecture by Life Sphere

### Sphere I: Cultural Crossroads (Giao Lộ Văn Hóa Phương Tây) — 8 Categories, 900 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **1** | `anglo_norman_feudal_heartland` | **Anglo-Norman Feudal Heartland**<br>*Trọng Tâm Phong Kiến Anglo-Norman* | **120** | • Motte And Bailey Earthwork<br>• • Square Norman Donjon Keep<br>• • Chevron Carved Stone Archway<br>• • Great Hall Oak Dais<br>• • Feudal Homage Court Furnishing | **culture_affinity**: anglo_norman<br>**feudal_tier**: baronial_court<br>**oath_system**: fealty_and_homage |
| **2** | `hanseatic_and_flemish_burgher` | **Hanseatic & Flemish Burgher Town**<br>*Đô Thị Phường Hội Hanseatic & Flanders* | **120** | • Stepped Gable Brick Facade<br>• • Canal Water Lock And Embankment<br>• • Cloth Hall And Weigh House<br>• • Guild Merchant Counting Room<br>• • Belfry Curfew Bell Spire | **culture_affinity**: flemish_hanseatic<br>**merchant_banking**: letter_of_credit<br>**guild_privilege**: hanseatic_charter |
| **3** | `nordic_and_norse_coastal` | **Nordic & Norse Coastal Settlement**<br>*Khu Định Cư Ven Biển Bắc Âu & Norse* | **120** | • Turf Roofed Timber Longhouse<br>• • Stave Pillar Dragon Carving<br>• • Runestone Monument And Grave<br>• • Boathouse Naust And Skiff<br>• • Whalebone Arch And Stockfish | **culture_affinity**: nordic_norse<br>**seafaring_weathering**: salt_and_frost_resistant<br>**ancestral_rites**: runic_inscription |
| **4** | `mediterranean_and_moorish_quarter` | **Mediterranean & Moorish Quarter**<br>*Khu Phố Địa Trung Hải & Moorish (Al-Andalus)* | **120** | • Arcaded Patio Courtyard<br>• • Azulejo Glazed Tile Fountain<br>• • Terracotta Stucco Villa Wall<br>• • Olive Press And Citrus Grove<br>• • Spice Bazaar And Silk Alcove | **culture_affinity**: mediterranean_moorish<br>**hydraulic_system**: cistern_and_aqueduct<br>**exotic_trade**: ['spices', 'silk', 'olive_oil'] |
| **5** | `slavic_eastern_taiga_and_logcraft` | **Slavic Eastern Taiga & Logcraft**<br>*Làng Gỗ Rừng Taiga Đông Slav (Kievan Rus)* | **110** | • Interlocking Log Izba Cabin<br>• • Wooden Kremlin Rampart Wall<br>• • Onion Domed Timber Chapel<br>• • Carved Window Nalichniki Frame<br>• • Taiga Fur Trappers Post | **culture_affinity**: slavic_rus<br>**winter_insulation**: russian_clay_stove<br>**commodity_trade**: fine_furs_and_amber |
| **6** | `celtic_highland_and_atlantic_fringe` | **Celtic Highland & Atlantic Fringe**<br>*Vùng Cao Nguyên & Rìa Đại Tây Dương Celtic* | **110** | • Circular Drystone Broch Tower<br>• • Lake Dwelling Crannog Jetty<br>• • Turf Beehive Clochan Hut<br>• • Celtic Wheel High Cross<br>• • Peat Fire Hearth And Well | **culture_affinity**: celtic_gaelic<br>**clan_structure**: highland_kinship<br>**holy_sites**: cloutie_well_offering |
| **7** | `byzantine_and_crusader_frontier` | **Byzantine & Crusader Outposts**<br>*Tiền Đồn Byzantine & Thập Tự Quân* | **100** | • Crusader Limestone Curtain Wall<br>• • Byzantine Brick And Stone Band<br>• • Roadside Iconostasis Shrine<br>• • Caravanserai Walled Compound<br>• • Border Beacon Watchtower | **culture_affinity**: byzantine_crusader<br>**fortification_type**: concentric_frontier_redoubt<br>**caravan_rest**: caravanserai_hospitality |
| **8** | `wayfarers_nomads_and_tinker_camps` | **Wayfarers, Nomads & Tinker Camps**<br>*Khu Cắm Trại Dân Du Mục & Thợ Hàn Nồi* | **100** | • Barrel Top Wooden Vardo Wagon<br>• • Tinker Brazier And Tin Pots<br>• • Nomad Canvas Wedge Tent<br>• • Horse Tether Line And Saddles<br>• • Campfire Circle And Instruments | **lifestyle**: itinerant_travelers<br>**repair_services**: traveling_metal_tinker<br>**folk_entertainment**: wandering_minstrels |

### Sphere II: Built Architecture (Kiến Trúc Định Cư & Công Sự) — 6 Categories, 800 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **9** | `modular_timber_frame_fachwerk` | **Modular Timber-Frame (Fachwerk)**<br>*Kiến Trúc Khung Gỗ Fachwerk Lắp Ghép* | **160** | • Cruck Blade And Tie Beam<br>• • Jetty Cantilever Bracket Bay<br>• • Wattle Daub And Brick Infill<br>• • Leaded Diamond Casement Window<br>• • Roof Gable Thatch And Tile<br>• • Veranda Porch And Dormer | **assembly_grid**: modular_building_snap_128<br>**material_grades**: ['rustic_oak', 'dressed_timber', 'painted_fachwerk']<br>**insulation_value**: temperate_climate |
| **10** | `village_cottages_and_serf_hovels` | **Village Cottages & Serf Hovels**<br>*Nhà Tranh Thôn Xóm & Túp Lều Nông Nô* | **120** | • Peasant Turf Roofed Hovel<br>• • Wattle Thatched Cottage Dwelling<br>• • Outdoor Clay Bread Oven<br>• • Drystone Boundary Wall And Stile<br>• • Homestead Woodpile And Shed | **social_tier**: serf_and_villager<br>**manorial_rent**: labor_corvee<br>**domestic_recovery**: straw_mattress_rest |
| **11** | `castles_curtain_walls_and_bastions` | **Castles, Curtain Walls & Bastions**<br>*Lâu Đài, Tường Thành Đá & Pháo Đài* | **180** | • Ashlar Curtain Wall And Talus<br>• • Crenellation And Hoarding Crest<br>• • Round Drum And Square Tower<br>• • Gatehouse Barbican And Portcullis<br>• • Moat Ditch And Sloping Bank<br>• • Arrow Slit And Intramural Stairs | **defense_rating**: heavy_concentric_fortress<br>**breach_resistance**: siege_resistant<br>**arrow_slits**: projectile_firing_port |
| **12** | `palace_keeps_and_royal_chambers` | **Palace Keeps & Royal Chambers**<br>*Đại Điện Cung Điện & Phòng Hoàng Gia* | **120** | • Throne Dais And Royal Canopy<br>• • Great Hall Feasting Trestles<br>• • Monumental Carved Stone Hearth<br>• • Four Poster Oak Bedchamber<br>• • Chivalric Heraldic Tapestry<br>• • Chancery And Treasury Chests | **authority_zone**: monarch_and_high_lord<br>**audience_diplomacy**: feudal_petition<br>**treasury_storage**: royal_bullion_vault |
| **13** | `garrisons_barracks_and_watchtowers` | **Garrisons, Barracks & Watchtowers**<br>*Doanh Trại Đồn Trú & Tháp Canh Biên Giới* | **100** | • Border Stone Watchtower<br>• • Soldiers Timber Bunkhouse<br>• • Armory Rack Spears And Halberds<br>• • Archery Practice Butt Range<br>• • Signal Fire Beacon Turret | **garrison_spawn**: feudal_men_at_arms<br>**alarm_beacon**: signal_smoke_call<br>**weapons_depot**: restock_munitions |
| **14** | `city_gates_bridges_and_portals` | **City Gates, Bridges & Portals**<br>*Cổng Thành, Cầu Đá & Trạm Thu Phí* | **120** | • Twin Towered City Gatehouse<br>• • Norman Barrel Arch Stone Bridge<br>• • Timber Oxcart Trestle Bridge<br>• • Curfew Bell And Toll Station<br>• • River Ford And Stepping Stones | **chokepoint_security**: gate_inspection_and_toll<br>**river_transit**: high_load_bridge<br>**curfew_rules**: night_closure |

### Sphere III: Faith & Mortality (Đức Tin, Tu Viện, Sinh Tử & Huyền Thuật) — 7 Categories, 760 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **15** | `gothic_cathedrals_and_monumental_abbeys` | **Gothic Cathedrals & Monumental Abbeys**<br>*Đại Giáo Đường Gothic & Tu Viện Kỳ Vĩ* | **140** | • Flying Buttress And Pinacle<br>• • Rose Window And Lancet Glass<br>• • High Altar And Reredos Screen<br>• • Carved Choir Stalls And Misericord<br>• • Cathedral Bell Chamber And Carillon<br>• • Processional Crosses And Reliquaries | **sanctuary_law**: ecclesiastical_immunity<br>**divine_favor**: cathedral_mass_buff<br>**liturgical_calendar**: holy_feast_days |
| **16** | `monasteries_cloisters_and_scriptoria` | **Monasteries, Cloisters & Scriptoria**<br>*Hành Lang Tu Viện & Phòng Chép Kinh* | **120** | • Cloister Quadrangle Arcaded Walk<br>• • Monastic Scriptorium Desk<br>• • Refectory Dining And Pulpit<br>• • Physic Garden Monastic Herbs<br>• • Monastic Cell And Dormitory | **scholarly_craft**: manuscript_illumination<br>**apothecary_brewing**: herbal_remedies<br>**monastic_rule**: benedictine_routine |
| **17** | `parish_chapels_and_wayside_shrines` | **Parish Chapels & Wayside Shrines**<br>*Nhà Nguyện Giáo Xứ & Miếu Thờ Ven Đường* | **100** | • Wayside Stone Cross Crucifix<br>• • Thatched Field Chapel Building<br>• • Pilgrims Sacred Spring Shrine<br>• • Hollow Tree Saint Shrine<br>• • Tithe Barn Parish Compound | **pilgrim_waypoint**: blessing_of_safe_travel<br>**confession**: forgive_sins_and_karma<br>**communal_burial**: parish_record_keeping |
| **18** | `graveyards_crypts_and_charnel_houses` | **Graveyards, Crypts & Charnel Houses**<br>*Nghĩa Trang, Hầm Mộ & Nhà Chứa Xương* | **110** | • Gothic Sarcophagus And Tomb<br>• • Charnel House Ossuary Skull Wall<br>• • Churchyard Standing Slate Headstones<br>• • Ancient Churchyard Yew Tree<br>• • Subterranean Catacomb Niches | **spiritual_ground**: consecrated_vs_unconsecrated<br>**undead_boundary**: ward_against_ghouls<br>**mourning_rites**: grave_offerings |
| **19** | `medieval_alchemy_and_natural_philosophy` | **Medieval Alchemy & Natural Philosophy**<br>*Giả Kim Thuật & Triết Học Tự Nhiên* | **100** | • Athanor Tower Furnace And Alembic<br>• • Astrolabe Armillary Sphere And Charts<br>• • Herbal Apothecary Drawers And Jars<br>• • Homunculus Jar And Transmutation Crucible<br>• • Scholars Reading Pulpit And Codices | **esoteric_crafting**: transmutation_and_tincture<br>**astrological_alignment**: planetary_influence<br>**philosophical_heresy**: inquisition_suspicion |
| **20** | `witchcraft_folklore_and_bog_magic` | **Witchcraft, Folklore & Bog Magic**<br>*Phù Thủy, Phong Tục Dân Gian & Phép Đầm Lầy* | **100** | • Bog Stilt Thatched Witch Hut<br>• • Straw Corn Dolly And Hex Poppets<br>• • Poisonous Nightshade And Fungi Ring<br>• • Wyrd Standing Boulder And Offerings<br>• • Divination Table And Bone Casting | **folk_curses**: evil_eye_and_hex<br>**forbidden_foraging**: black_henbane_and_nightshade<br>**pagan_survivals**: seasonal_solstice_fire |
| **21** | `plague_lazarettos_and_quarantine` | **Plague Lazarettos & Quarantine**<br>*Trại Phong Hủi & Khu Cách Ly Dịch Bệnh* | **90** | • Lazaretto Pest House Ward<br>• • Plague Doctor Attire And Station<br>• • Quarantine Barrier And Watch Line<br>• • Mass Pestilence Trench Grave<br>• • Fumigation Herbs And Cleansing Fires | **contagion_hazard**: black_death_infection<br>**isolation_cordon**: quarantine_enforcement<br>**penitence_movement**: flagellant_procession |

### Sphere IV: Manorial Supply Chains (Chuỗi Cung Ứng Điền Trang & Phường Hội) — 10 Categories, 1140 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **22** | `grain_agriculture_and_harvesting` | **Grain Agriculture & Harvesting**<br>*Canh Tác Lúa Mì & Thu Hoạch Mùa Màng* | **130** | • Ridge And Furrow Open Fields<br>• • Wheeled Moldboard Carruca Plow<br>• • Reaping Scythes Sickles And Stooks<br>• • Threshing Barn And Flails<br>• • Thatched Hayrick And Straw Stacks<br>• • Gleaning And Autumn Field Scarecrows | **crop_cycle**: three_field_rotation<br>**staple_yield**: flour_and_bread<br>**tithe_fraction**: one_tenth_to_church |
| **23** | `pastoralism_livestock_and_dairy` | **Pastoralism, Livestock & Dairy**<br>*Chăn Thả Gia Súc & Chế Biến Bơ Sữa* | **130** | • Wattle Hurdle Sheep Pen<br>• • Ox Stable Manger And Byre<br>• • Dairy Churn And Cheese Press<br>• • Pigsty Troughs And Swill Buckets<br>• • Sheepshearing Bench And Fleeces<br>• • Beehive Skeps And Mead Vats | **pastoral_products**: ['wool', 'cheese', 'butter', 'mutton', 'honey']<br>**transhumance**: summer_upland_pasture |
| **24** | `orchards_vineyards_and_brewing` | **Orchards, Vineyards & Brewing**<br>*Vườn Cây Ăn Trái, Vườn Nho & Lò Nấu Rượu* | **120** | • Espalier Apple And Pear Orchard<br>• • Terrace Vineyard Grape Trellis<br>• • Grape Treading Vat And Press<br>• • Brewhouse Mash Tun And Copper<br>• • Alehouse Cellar Casks And Stillions | **beverage_economy**: ['ale', 'cider', 'wine', 'mead']<br>**seasonal_press**: grape_harvest_vendange |
| **25** | `watermills_windmills_and_milling` | **Watermills, Windmills & Milling**<br>*Cối Xay Nước, Cối Xay Gió & Xay Xát* | **110** | • Overshot Timber Waterwheel<br>• • Post Mill And Tower Windmill Sails<br>• • Granite Millstones And Hopper<br>• • Millers Flour Sacks And Chute<br>• • Millpond Weir And Sluice Gates | **manorial_monopoly**: lord_milling_ban<br>**power_generation**: ['hydro_kinetic', 'aeolian_wind']<br>**output_milling**: fine_white_and_whole_meal |
| **26** | `blacksmithing_and_metal_refining` | **Blacksmithing & Metal Refining**<br>*Rèn Đúc Sắt Thép & Tinh Luyện Kim Loại* | **120** | • Stone Forge Hearth And Bellows<br>• • Iron Anvil And Water Swage Block<br>• • Blacksmith Tongs Hammers Chisel Rack<br>• • Tempering Water Trough And Quench Barrel<br>• • Iron Bloomery Furnace And Slag Heap | **metallurgy**: bloomery_wrought_iron<br>**crafting_recipes**: ['plowshares', 'horseshoe', 'broadsword', 'armor_plate']<br>**fuel_demand**: charcoal_burning |
| **27** | `forestry_timber_and_cooperage` | **Forestry, Timber & Cooperage**<br>*Lâm Nghiệp, Xẻ Gỗ & Đóng Thùng* | **110** | • Two Man Pit Saw And Sawpit<br>• • Broadaxe Adzes And Hewing Benches<br>• • Cooper Cask Stave Bending Fire<br>• • Charcoal Burners Earthen Kiln<br>• • Timber Sled And Ox Skidding Trail | **timber_yield**: ['heart_oak', 'ash_shafts', 'yew_staves', 'pine_planks']<br>**cooper_production**: watertight_casks_and_tuns |
| **28** | `wool_textile_and_dyeing_guilds` | **Wool, Textile & Dyeing Guilds**<br>*Phường Hội Dệt Nỉ, Nhuộm Màu & Kéo Sợi* | **110** | • Broadloom Warp And Weft Weaving<br>• • Dye Vats Woad Madder And Weld<br>• • Fulling Mill Water Powered Stocks<br>• • Teasel Raising And Shearing Table<br>• • Tentering Frame Meadow Stretching | **textile_export**: flemish_broadcloth<br>**dye_spectrum**: ['woad_blue', 'madder_red', 'weld_yellow']<br>**guild_regulation**: staple_port_wool |
| **29** | `tannery_leatherwork_and_cordwaining` | **Tannery, Leatherwork & Cordwaining**<br>*Thuộc Da, Đóng Giày & Thuộc Bằng Vỏ Cây* | **100** | • Lime Pit And Beaming Knives<br>• • Tanbark Liquor Vats And Crushers<br>• • Cordwainers Shoemaking Last And Awls<br>• • Saddlery Harnesses And Sheaths<br>• • Tallow Renderers Vat And Candles | **leather_products**: ['cuirbouilli_armor', 'bridles', 'turnshoes', 'scabbards']<br>**noxious_craft**: downwind_city_placement |
| **30** | `pottery_glassblowing_and_masonry` | **Pottery, Glassblowing & Masonry**<br>*Gốm Sứ, Thổi Thủy Tinh & Đẽo Đá* | **110** | • Potters Wheel And Updraft Kiln<br>• • Stonemasons Banker Bench And Mallet<br>• • Glassblowers Potash Furnace And Pipes<br>• • Earthenware Storage Crocks And Jugs<br>• • Forest Glass Crown Window Disks | **mineral_craft**: ['terracotta_roof_tile', 'stained_glass', 'dressed_ashlar']<br>**fire_hazard**: furnace_spark_danger |
| **31** | `mining_quarries_and_lime_kilns` | **Mining, Quarries & Lime Kilns**<br>*Khai Mỏ, Mỏ Đá & Lò Nung Vôi* | **100** | • Limestone Quarry Face And Wedges<br>• • Shored Timber Mine Adit Portal<br>• • Flare Lime Kiln And Quicklime Pit<br>• • Alluvial Lead And Tin Streaming<br>• • Salt Pan And Brine Evaporation | **ore_extraction**: ['iron_bog_ore', 'lead_ore', 'silver_galena', 'building_chalk']<br>**subterranean_hazards**: mine_flooding_and_cave_in |

### Sphere V: Commerce & Urban Life (Thương Nghiệp, Đô Thị & Cảng Biển) — 5 Categories, 590 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **32** | `urban_street_markets_and_civic_life` | **Urban Street Markets & Civic Life**<br>*Chợ Đường Phố & Đời Sống Dân Cư Đô Thị* | **130** | • Canvas Roofed Market Stalls<br>• • Civic Market Cross And Pillory<br>• • Swinging Wrought Iron Inn Signs<br>• • Town Well And Water Conduit<br>• • Muddy Cart Ruts And Street Gutters | **market_days**: weekly_charter_fair<br>**price_controls**: assize_of_bread_and_ale<br>**public_order**: watch_and_ward |
| **33** | `taverns_coaching_inns_and_alehouses` | **Taverns, Coaching Inns & Alehouses**<br>*Quán Rượu, Trạm Cỗ Xe & Quán Bia Cỏ* | **120** | • Heavy Oak Tavern Bar Counter<br>• • Common Room Bench And Trestles<br>• • Coaching Inn Courtyard And Stables<br>• • Taproom Hearth And Roast Spit<br>• • Guest Chamber Pallet Beds | **social_gathering**: rumor_and_bounty_leads<br>**hospitality**: ale_and_stew_buffs<br>**lodging_recovery**: inn_rest |
| **34** | `harbors_quays_and_hanseatic_cogs` | **Harbors, Quays & Hanseatic Cogs**<br>*Bến Cảng, Bờ Kè & Thuyền Buồm Cog* | **130** | • Heavy Timber Wharf And Quays<br>• • Hanseatic Single Masted Cog<br>• • Treadwheel Harbor Hoisting Crane<br>• • Herring Salting Barrels And Wharf<br>• • Customs Tollhouse And Weighing Scale | **maritime_shipping**: bulk_grain_and_timber<br>**customs_duty**: sound_toll_and_anchorage<br>**naval_repairs**: careening_and_pitch |
| **35** | `river_fisheries_waterways_and_ferries` | **River Fisheries, Waterways & Ferries**<br>*Nghề Cá Sông, Kênh Đào & Phà Bến Nước* | **100** | • Cable Guided River Punting Ferry<br>• • Wicker Fish Weir And Eel Traps<br>• • Coracle Skiffs And Flat Bottom Punts<br>• • River Lock Flash Gate Sluice<br>• • Watercress Beds And Reedy Channels | **freshwater_harvest**: ['river_eel', 'salmon', 'pike']<br>**ferry_transit**: cross_wide_estuary |
| **36** | `fairs_festivals_and_carnivals` | **Fairs, Festivals & Carnivals**<br>*Hội Chợ, Lễ Hội Mùa & Diễn Xướng* | **110** | • Striped Pageant And Charter Pavilions<br>• • Minstrels Stage And Puppets<br>• • Maypole Ribbons And Green Man<br>• • Games Of Chance And Archery Prizes<br>• • Roasting Ox Open Pit And Cider Tents | **community_morale**: festival_celebration_buff<br>**mystery_plays**: religious_theatricals<br>**annual_charter**: exemption_from_tolls |

### Sphere VI: War & Underworld (Chiến Tranh, Công Thành, Tội Phạm & Ngục Tối) — 5 Categories, 540 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **37** | `knighthood_tournaments_and_chivalry` | **Knighthood, Tournaments & Chivalry**<br>*Đấu Thương Hiệp Sĩ & Tinh Thần Thượng Võ* | **110** | • Jousting Tilt Barrier And Rails<br>• • Royal Heraldic Viewing Stand<br>• • Rotating Quintain Training Target<br>• • Knightly Armory And Plate Armor<br>• • Knights Heraldic Camp Pavilions | **chivalric_honor**: courtly_reputation<br>**martial_contest**: ['joust_of_peace', 'melee_at_the_barriers']<br>**ransom_system**: capture_knight_and_horse |
| **38** | `siege_engines_and_heavy_artillery` | **Siege Engines & Heavy Artillery**<br>*Máy Bắn Đá, Vũ Khí Công Thành & Đột Kích* | **120** | • Counterweight Trebuchet Warwolf<br>• • Covered Battering Ram And Cat<br>• • Torsion Ballista And Springald<br>• • Wooden Siege Tower Belfry<br>• • Siege Ammunition Pyramids And Pots | **siege_destruction**: wall_breach_mechanic<br>**battering_gate**: destroy_portcullis<br>**ammunition**: ['limestone_boulders', 'fire_pots', 'carcass_projectiles'] |
| **39** | `military_camps_and_field_works` | **Military Camps & Field Works**<br>*Doanh Trại Quân Sự & Công Sự Dã Ngoại* | **110** | • Soldiers Wedge Canvas Bell Tent<br>• • Spiked Chevaux De Frise Barricade<br>• • Military Camp Hearth And Mess<br>• • Pallisaded Camp Earthen Rampart<br>• • Command Tent And War Council Map | **army_encampment**: mobilization_field_base<br>**cavalry_obstacle**: caltrop_and_stake_slowdown<br>**supply_attrition**: rations_and_forage |
| **40** | `battlefield_aftermath_and_ruins` | **Battlefield Aftermath & Ruins**<br>*Chiến Trường Tàn Tích & Dấu Vết Bại Trận* | **90** | • Broken Wagon And Shattered Wheels<br>• • Scattered Arms And Dented Armor<br>• • Burned Cottage Ruins And Cinders<br>• • Carrion Birds And Battlefield Piles<br>• • Looted Caravan And Ransacked Chests | **battlefield_scavenge**: broken_armor_and_salvage<br>**desolation_hazard**: unburied_carrion_disease<br>**war_trophies**: captured_standards |
| **41** | `outlaws_bandits_and_dungeon_depths` | **Outlaws, Bandits & Dungeon Depths**<br>*Sơn Tặc, Ngục Tối & Lòng Đất Hắc Ám* | **110** | • Robber Barons Ruined Keep<br>• • Forest Hideout Lean To Shelters<br>• • Roadside Gallows And Gibbets<br>• • Subterranean Oubliette And Dungeon<br>• • Smugglers Cave And Concealed Trapdoors | **banditry**: highway_ambush<br>**imprisonment**: dungeon_breakout<br>**bounty_system**: outlaw_head_reward |

### Sphere VII: Ecology & Living Traces (Tự Nhiên, Dấu Vết Sống, Sinh Thái & Cư Dân) — 7 Categories, 870 Assets

| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |
|---|---|---|:---:|---|---|
| **42** | `primeval_forests_ancient_oaks_and_woods` | **Primeval Forests, Ancient Oaks & Woods**<br>*Rừng Nguyên Sinh, Sồi Cổ Thụ & Dẻ Gai* | **130** | • Gnarled English Oak Venerable<br>• • Copper Beech And Silver Birch<br>• • Dense Bracken And Bramble Thicket<br>• • Nurse Logs And Bracket Fungi<br>• • Pollarded Willow And Hazel Coppice | **royal_forest_law**: verderer_and_venison_ban<br>**foraging_yield**: ['truffles', 'boletus', 'wild_honey', 'bilberries']<br>**canopy_occlusion**: dense_foliage_fade |
| **43** | `cliffs_highland_moors_and_waterfalls` | **Cliffs, Highland Moors & Waterfalls**<br>*Vách Đá Vôi, Cao Nguyên Than Bùn & Thác Nước* | **120** | • Highland Granite Tor Outcrop<br>• • Heather And Peat Moorland Turf<br>• • Mountain Waterfall And Cascade<br>• • Limestone Pavement And Grykes<br>• • Wind Bent Scots Pine And Rowan | **verticality**: climbing_and_ledges<br>**cavern_exploration**: dungeon_entry_portal<br>**water_physics**: flowing_torrents |
| **44** | `wetlands_bogs_fens_and_marshlands` | **Wetlands, Bogs, Fens & Marshlands**<br>*Đầm Lầy Than Bùn, Bãi Sậy & Nước Chua* | **110** | • Quaking Sphagnum Peat Bog<br>• • Fenland Reed Beds And Carrs<br>• • Submerged Timber Causeway Track<br>• • Peat Cutter Turf Stacks And Spades<br>• • Will O The Wisp Marsh Lights | **movement_impediment**: mire_and_quagmire_slow<br>**peat_fuel**: extract_turf_blocks<br>**bog_preservation**: bog_body_archeology |
| **45** | `living_ground_pavements_and_tracks` | **Living Ground, Pavements & Tracks**<br>*Mặt Đất Đời Sống, Lối Đi & Vết Bánh Xe* | **130** | • Worn Basalt And River Sett Paving<br>• • Country Cart Ruts And Churned Mud<br>• • Flagstone Causeway And Curbstones<br>• • Village Green Turf And Daisy Patches<br>• • Puddle Strewn Cobbles And Drainage<br>• • Chalk Scree And Limestone Shingle | **terrain_nav**: walk_surface<br>**footstep_acoustics**: ['stone_clatter', 'squelch_mud', 'crunch_leaves', 'splash_puddle']<br>**wheel_traction**: weather_dependent_speed |
| **46** | `domesticity_chores_and_habitation_traces` | **Domesticity, Chores & Habitation Traces**<br>*Đời Sống Gia Đình, Việc Nhà & Dấu Vết Sinh Hoạt* | **120** | • Linen Washing Lines And Bleaching Greens<br>• • Manure Middens And Muck Heaps<br>• • Outdoor Chopping Blocks And Axe Splits<br>• • Muddy Cartwheel Ruts And Puddles<br>• • Hearth Ash Pits And Charcoal Sweepings<br>• • Thatched Eaves Drying Herbs And Onions | **ambient_habitation**: visual_life_indicator<br>**sanitation_level**: smell_and_squalor_meter<br>**domestic_chores**: daily_npc_animations |
| **47** | `wildlife_micro_fauna_birds_and_pests` | **Wildlife, Micro-Fauna, Birds & Pests**<br>*Động Vật Hoang Dã, Chim Muông & Thú Nhỏ* | **120** | • Cathedral Roosting Pigeons And Doves<br>• • Gallows Carrion Crows And Ravens<br>• • Thatched Roof Barn Swallows<br>• • Granary Rats And Field Mice<br>• • Timber Wall Geckos And Spiders<br>• • Fen Marsh Frogs And Water Beetles | **ecological_ambience**: organic_movement_sprites<br>**omen_system**: stork_good_luck_vs_crows_ill_omen<br>**pest_control**: cats_reduce_grain_loss |
| **48** | `denizens_burghers_peasants_and_beasts` | **Denizens, Burghers, Peasants & Beasts**<br>*Cư Dân, Thị Dân, Nông Dân & Súc Vật Kéo* | **140** | • Peasant Serfs And Field Laborers<br>• • Guild Artisans And Master Craftsmen<br>• • Burgher Merchants And Civic Clerks<br>• • Clergy Monks Friars And Bishops<br>• • Feudal Knights Men At Arms And Watch<br>• • Domestic Draft Beasts Oxen And Steeds | **npc_routine**: ['day_labor', 'market_trading', 'night_curfew', 'tavern_leisure']<br>**dialogue_hooks**: feudal_social_standing<br>**draft_power**: pull_carts_and_heavy_plows |

---

## 3. Comprehensive Category Summary Matrix

| Life Sphere | Category Count | Asset Target | Key Physical & Gameplay Focus |
|---|:---:|:---:|---|
| **Sphere I: Cultural Crossroads** (*Giao Lộ Văn Hóa Phương Tây*) | **8** | **900** | Anglo-Norman Feudal Heartland, Hanseatic & Flemish Burgher Town et al. |
| **Sphere II: Built Architecture** (*Kiến Trúc Định Cư & Công Sự*) | **6** | **800** | Modular Timber-Frame (Fachwerk), Village Cottages & Serf Hovels et al. |
| **Sphere III: Faith & Mortality** (*Đức Tin, Tu Viện, Sinh Tử & Huyền Thuật*) | **7** | **760** | Gothic Cathedrals & Monumental Abbeys, Monasteries, Cloisters & Scriptoria et al. |
| **Sphere IV: Manorial Supply Chains** (*Chuỗi Cung Ứng Điền Trang & Phường Hội*) | **10** | **1140** | Grain Agriculture & Harvesting, Pastoralism, Livestock & Dairy et al. |
| **Sphere V: Commerce & Urban Life** (*Thương Nghiệp, Đô Thị & Cảng Biển*) | **5** | **590** | Urban Street Markets & Civic Life, Taverns, Coaching Inns & Alehouses et al. |
| **Sphere VI: War & Underworld** (*Chiến Tranh, Công Thành, Tội Phạm & Ngục Tối*) | **5** | **540** | Knighthood, Tournaments & Chivalry, Siege Engines & Heavy Artillery et al. |
| **Sphere VII: Ecology & Living Traces** (*Tự Nhiên, Dấu Vết Sống, Sinh Thái & Cư Dân*) | **7** | **870** | Primeval Forests, Ancient Oaks & Woods, Cliffs, Highland Moors & Waterfalls et al. |
| **TOTAL LIVING WORLD MATRIX** | **48** | **5,600** | **Complete Medieval Western Feudal & Chivalric Simulation Matrix** |

---

## 4. Modular Construction Kits

### 4.1 Concentric Stone Castle Kit (`castles_curtain_walls_and_bastions`: 180 Assets)
* **Foundation & Talus Batter**: Sloped ashlar limestone bases preventing siege sapping; 128 px unit modularity.
* **Curtain Walls**: Straight wall bays (1x1, 2x1, 3x1), crenellated wall walks with murder-hole corbels and timber hoardings.
* **Defensive Towers**: Round drum towers (2x2), D-shaped mural bastions (2x2), square Norman keeps (3x3, 4x4), corbelled bartizans (1x1).
* **Gatehouses & Portcullises**: Heavy double-drum barbicans, iron-banded drawbridge pivot mechanisms, and murder holes.

### 4.2 Modular Timber-Frame Fachwerk Kit (`modular_timber_frame_fachwerk`: 160 Assets)
* **Dwarf Stone Footings**: Rubble masonry plinths elevating load-bearing cruck timber timbers above mud.
* **Cruck Timber Framing**: Heavy oak posts, mortise-and-tenon joints, St. Andrew's cross bracings, and cantilevered upper-storey jetties.
* **Wall Infills**: Whitewashed wattle-and-daub, herringbone red brick nogging, and diamond leaded glass windows.
* **Roof Systems**: Thatch bundles, terracotta plain tiles, and blue Welsh slates with carved dragon/gargoyle bargeboards.

### 4.3 Gothic Cathedral & Cloister Kit (`gothic_cathedrals_and_monumental_abbeys`: 140 Assets)
* **Skeletal Stonework**: Flying buttresses, ribbed quadripartite vault piers, pointed lancet windows, and high rose tracery.
* **Monastic Cloister Arcades**: Quadrangle open-arcaded walks with central garth well, lavatorium stone basins, and stone scriptorium desks.

### 4.4 Manorial Supply Chain Kit (`grain_agriculture_and_harvesting` + `pastoralism_livestock_and_dairy`: 260 Assets)
* **Arable Strips & Harvesting**: Ridge-and-furrow wheat strips, heavy wheeled moldboard plows, scythes, stooks of grain, and thatched threshing barns.
* **Pastoralism & Dairy**: Wattle hurdle sheep pens, shearing trestles, milk pails, butter churns, and aging cheese wheel racks.

---

## 5. Technical Generation Pipeline & Verification
* **Approved Checkpoint**: `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors`
* **LoRA**: `krea2/Scottie__Krea2.safetensors` (Weight 1.0, Node 917)
* **Sampler**: `euler_ancestral`, Scheduler: `beta`, Steps: 8, CFG: 1.0
* **Alpha Cutout**: `RMBG-2.0` high-precision semantic background removal ensuring clean ink contours without halos.
* **Asset Directory Architecture**:
  * `runtime/<category_id>/`: Game-ready `.png` textures and Godot `.import` cache files.
  * `data/<category_id>/`: Individual asset metadata (`.json`) with collision subcells, footprints, and interaction hooks.
  * `original/<category_id>/`: Uncompressed raw generation outputs before alpha extraction.
