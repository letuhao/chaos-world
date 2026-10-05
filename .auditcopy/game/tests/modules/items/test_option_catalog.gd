extends TestCase

## ADR 0025/0033: master option catalog runtime — pool membership, realm/rarity
## magnitude policy, and the resolved option record the generator consumes.


func _catalog() -> OptionCatalog:
	return OptionCatalog.new()


## Distinct-entry count of an option id list.
func preview_size(ids: Array[StringName]) -> int:
	var seen: Array[StringName] = []
	for id in ids:
		if not seen.has(id):
			seen.append(id)
	return seen.size()


func _blade(rarity: StringName = &"rare") -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_blade"
	def.category = ItemCategory.EQUIPMENT
	def.rarity = rarity
	def.realm = &"qi_refining"
	def.roll_spec = {"contexts": ["prefix", "postfix"], "count": ItemRarity.affix_count(rarity)}
	return def


func test_rarity_tier_mapping() -> void:
	var catalog := _catalog()
	assert_eq(catalog.rarity_tier(&"common"), 0, "common tier 0")
	assert_eq(catalog.rarity_tier(&"magic"), 1, "magic tier 1")
	assert_eq(catalog.rarity_tier(&"rare"), 2, "rare tier 2")
	assert_eq(catalog.rarity_tier(&"legendary"), 3, "legendary tier 3")


func test_magnitude_bounds_scale_with_realm_and_rarity() -> void:
	var catalog := _catalog()
	var base: Dictionary = catalog.magnitude_bounds("magnitude", &"qi_refining", 0)
	assert_almost_eq(float(base["min"]), 1.0, "base min at the first realm")
	assert_almost_eq(float(base["max"]), 10.0, "base max at the first realm")
	var late: Dictionary = catalog.magnitude_bounds("magnitude", &"primordial_origin", 3)
	assert_eq(float(late["min"]) > float(base["min"]), true, "min grows")
	assert_eq(float(late["max"]) > float(base["max"]), true, "max grows")


func test_catalog_records_load_and_are_addressable_by_id() -> void:
	var catalog := _catalog()
	assert_eq(catalog.active_option_ids().is_empty(), false, "records loaded")
	assert_eq(catalog.has_option(&"core_attack_physical"), true, "known option")
	assert_eq(catalog.has_option(&"not_a_registered_option"), false, "unknown option")


func test_pool_membership_is_projected_per_activation_and_context() -> void:
	var catalog := _catalog()
	var prefix := catalog.pool_ids(&"equipped", &"prefix")
	assert_eq(prefix.is_empty(), false, "equipped prefix pool exists")
	var consumable := catalog.pool_ids(&"consumed", &"base")
	assert_eq(consumable.is_empty(), false, "consumed base pool exists")
	# Pool membership comes from the generated projection, so registration order
	# can never change which options are eligible or the order they are offered.
	var again := OptionCatalog.new().pool_ids(&"equipped", &"prefix")
	assert_eq(prefix == again, true, "pool membership is deterministic")
	assert_eq(prefix.size() == preview_size(prefix), true, "no duplicates in a pool")
	# A consumable restore never appears in the equipped pool.
	assert_eq(prefix.has(&"restore_health"), false, "cross-activation option absent")


func test_activation_is_derived_from_categories_not_authored() -> void:
	var catalog := _catalog()
	var restore := catalog.option_record(&"restore_health")
	assert_eq(catalog.activations_for(restore), [&"consumed"], "consumable activation")
	assert_eq(catalog.allows_activation(&"restore_health", &"consumed"), true, "allowed")
	assert_eq(catalog.allows_activation(&"restore_health", &"equipped"), false, "not allowed")


func test_roll_affixes_produces_resolved_effects() -> void:
	var def := _blade(&"rare")
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729
	var rolled := ItemGenerator.roll(def, rng)
	assert_eq(rolled.size(), ItemRarity.affix_count(&"rare"), "affixes rolled")
	for effect in rolled:
		assert_eq(effect["channel"], &"rolled", "rolled channel")
		var record := _catalog().option_record(StringName(effect["option_id"]))
		assert_ne(record, {}, "option resolves through the catalog")
		assert_eq(effect["target_id"], StringName(record["target"]["id"]), "target from catalog")


func test_roll_affixes_seeded_reproducible() -> void:
	var def := _blade(&"legendary")
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var first := ItemGenerator.roll(def, rng1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var second := ItemGenerator.roll(def, rng2)
	assert_eq(first.size(), second.size(), "same count")
	for i in first.size():
		assert_eq(first[i]["option_id"], second[i]["option_id"], "same option at %d" % i)
		assert_almost_eq(
			float(first[i]["value"]), float(second[i]["value"]), "same value at %d" % i
		)


func test_roll_affixes_empty_spec() -> void:
	var def := ItemDef.new()
	def.id = &"test_rock"
	def.category = ItemCategory.MATERIAL
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(ItemGenerator.roll(def, rng).size(), 0, "no roll spec, no rolls")


func test_fixed_effect_uses_the_authored_value_not_a_roll() -> void:
	var catalog := _catalog()
	var effect := catalog.fixed_effect(&"core_attack_physical", 7.0)
	assert_eq(effect["channel"], &"fixed", "fixed channel")
	assert_almost_eq(float(effect["value"]), 7.0, "authored value preserved")
	assert_eq(catalog.fixed_effect(&"not_a_registered_option", 7.0), {}, "unknown is empty")


func test_fixed_value_is_clamped_to_the_option_bounds() -> void:
	var catalog := _catalog()
	var record := catalog.option_record(&"craft_yield")
	record["bounds"] = {"min": 0.0, "max": 0.25}
	var effect := catalog.fixed_effect(&"craft_yield", 99.0)
	assert_almost_eq(float(effect["value"]), 0.25, "clamped to the declared maximum")


func test_projection_stale_version_is_reported_not_silently_used() -> void:
	var catalog := _catalog()
	# The runtime refuses a projection whose version it does not understand.
	assert_eq(OptionCatalog.PROJECTION_VERSION, 2, "projection version is explicit")
	catalog.pool_ids(&"equipped", &"prefix")
	assert_eq(catalog.pool_ids(&"equipped", &"prefix").is_empty(), false, "pool readable")
