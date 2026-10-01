extends TestCase

## ADR 0025: master option catalog runtime — rarity/realm policy and seeded rolls.


func _catalog() -> OptionCatalog:
	return OptionCatalog.new()


func test_rarity_tier_mapping() -> void:
	var catalog := _catalog()
	assert_eq(catalog.rarity_tier(&"common"), 0, "common tier 0")
	assert_eq(catalog.rarity_tier(&"magic"), 1, "magic tier 1")
	assert_eq(catalog.rarity_tier(&"rare"), 2, "rare tier 2")
	assert_eq(catalog.rarity_tier(&"legendary"), 3, "legendary tier 3")


func test_magnitude_bounds_scale_with_realm_and_rarity() -> void:
	var catalog := _catalog()
	var base: Dictionary = catalog.magnitude_bounds("magnitude", 0, 0)
	var scaled: Dictionary = catalog.magnitude_bounds("magnitude", 29, 3)
	assert_almost_eq(base["min"], 1.0, "base min at realm 0")
	assert_almost_eq(base["max"], 10.0, "base max at realm 0")
	# realm 29 (index) and legendary (3) scale up.
	assert_eq(scaled["min"] > base["min"], true, "min grows with realm/rarity")
	assert_eq(scaled["max"] > base["max"], true, "max grows with realm/rarity")


func test_roll_affixes_produces_modifiers() -> void:
	var catalog := _catalog()
	var def := ItemDef.new()
	def.id = &"test_sword"
	def.category = ItemCategory.EQUIPMENT
	def.roll_spec = {"contexts": ["prefix", "postfix"], "count": 2}
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729
	var modifiers: Array[StatModifier] = catalog.roll_affixes(def, 0, 0, 2, rng)
	assert_eq(modifiers.size(), 2, "two affixes rolled")
	for modifier in modifiers:
		assert_eq(modifier.source, &"roll", "tagged as roll")


func test_roll_affixes_seeded_reproducible() -> void:
	var catalog := _catalog()
	var def := ItemDef.new()
	def.id = &"test_sword"
	def.category = ItemCategory.EQUIPMENT
	def.roll_spec = {"contexts": ["prefix", "postfix"], "count": 2}
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var mods1: Array[StatModifier] = catalog.roll_affixes(def, 0, 0, 2, rng1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var mods2: Array[StatModifier] = catalog.roll_affixes(def, 0, 0, 2, rng2)
	assert_eq(mods1.size(), mods2.size(), "same count")
	for i in mods1.size():
		assert_eq(mods1[i].stat, mods2[i].stat, "same stat at %d" % i)
		assert_almost_eq(mods1[i].value, mods2[i].value, "same value at %d" % i)


func test_roll_affixes_empty_spec() -> void:
	var catalog := _catalog()
	var def := ItemDef.new()
	def.id = &"test_rock"
	def.category = ItemCategory.MATERIAL
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(catalog.roll_affixes(def, 0, 0, 2, rng).size(), 0, "no roll spec, no rolls")
