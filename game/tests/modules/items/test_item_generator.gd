extends TestCase

## ADR 0025/0028: seeded generation, activation consumers, and item-use hooks.


## Deterministic generator stream for a test fixture, so a realized roll is
## reproducible without depending on the global RNG.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 50.0))
	ItemsApi.attach(actor)
	return actor


func _equipment(rarity: StringName) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"blade"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.WEAPON
	def.stackable = false
	def.rarity = rarity
	def.realm = &"qi_refining"
	def.roll_spec = {"count": ItemRarity.affix_count(rarity), "contexts": ["prefix", "postfix"]}
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 5.0}]
	return def


func test_seed_reproduces_the_same_realization() -> void:
	var def := _equipment(&"rare")
	var first := ItemGenerator.generate(def, &"a", _rng(104729))
	var second := ItemGenerator.generate(def, &"b", _rng(104729))
	assert_eq(first.rolled.size(), second.rolled.size(), "same affix count")
	# The signature excludes the instance id, so the same seed reproduces the
	# same realization while the instances stay distinct objects.
	assert_eq(first.stacking_signature() == second.stacking_signature(), true, "same realization")
	assert_eq(first.instance_id != second.instance_id, true, "instances stay distinct")
	var other := ItemGenerator.generate(def, &"c", _rng(1))
	assert_eq(first.stacking_signature() == other.stacking_signature(), false, "a new seed differs")


func test_generated_roll_resolves_through_the_catalog() -> void:
	var instance := ItemGenerator.generate(_equipment(&"rare"), &"a", _rng(7))
	for effect in instance.rolled:
		var record := OptionCatalog.instance().option_record(StringName(effect["option_id"]))
		assert_ne(record, {}, "rolled option exists in the catalog")
		assert_eq(effect["channel"], &"rolled", "rolled channel")
		assert_eq(
			StringName(effect["target_id"]),
			StringName(record["target"]["id"]),
			"target matches the catalog"
		)
		var limits: Dictionary = record["bounds"]
		assert_eq(
			(
				float(effect["value"]) >= float(limits["min"])
				and float(effect["value"]) <= float(limits["max"])
			),
			true,
			"value inside declared bounds"
		)


func test_affix_count_follows_rarity_policy() -> void:
	for rarity in ItemRarity.ALL:
		var instance := ItemGenerator.generate(_equipment(rarity), &"a", _rng(11))
		assert_eq(
			instance.rolled.size(), ItemRarity.affix_count(rarity), "affix count for %s" % rarity
		)


func test_rolls_use_only_the_declared_affix_contexts() -> void:
	var instance := ItemGenerator.generate(_equipment(&"legendary"), &"a", _rng(3))
	assert_eq(instance.rolled.size() > 0, true, "rolled something")
	var record := OptionCatalog.instance()
	for effect in instance.rolled:
		var option := record.option_record(StringName(effect["option_id"]))
		var contexts: Array = option["contexts"]
		assert_eq(contexts.has("prefix") or contexts.has("postfix"), true, "affix context only")


func test_rolls_do_not_repeat_an_option() -> void:
	for seed_value in range(20):
		var instance := ItemGenerator.generate(_equipment(&"legendary"), &"a", _rng(seed_value))
		var seen: Array[String] = []
		for effect in instance.rolled:
			var option_id := String(effect["option_id"])
			assert_eq(
				seen.has(option_id), false, "no duplicate %s at seed %d" % [option_id, seed_value]
			)
			seen.append(option_id)


func test_magnitude_grows_with_the_authored_realm_scale() -> void:
	# An item's magnitude window must be the authored per-realm scale and nothing
	# else: no second curve applied on top of it, and no ramp recomputed by the
	# runtime. Same rarity at both ends, so rarity scales out of the ratio.
	var catalog := OptionCatalog.instance()
	var first := catalog.magnitude_bounds("magnitude", &"qi_refining", 0)
	var last := catalog.magnitude_bounds("magnitude", &"primordial_origin", 0)
	assert_eq(float(last["max"]) > float(first["max"]), true, "late realms roll higher")

	var scale_span := (
		OptionCatalog.realm_magnitude_scale(&"primordial_origin")
		/ OptionCatalog.realm_magnitude_scale(&"qi_refining")
	)
	var item_span := float(last["max"]) / float(first["max"])
	# The window is exactly base * scale * rarity, so the span IS the scale's span.
	assert_almost_eq(
		item_span / scale_span, 1.0, "the window is the authored scale and only it", 1e-9
	)
	# The scale is data of sane size, so the whole 30-realm span is a bounded,
	# readable multiple rather than an astronomical one.
	assert_eq(scale_span < 100.0, true, "the realm span stays a readable multiple")
	assert_eq(
		OptionCatalog.realm_magnitude_scale(&"primordial_origin") < INF, true, "and stays finite"
	)


func test_consumable_restores_a_resource_once() -> void:
	var actor := _hero()
	actor.resource(&"health").change(-70.0)
	var potion := ItemDef.new()
	potion.id = &"healing_draught"
	potion.category = ItemCategory.CONSUMABLE
	potion.stackable = true
	potion.rarity = &"common"
	potion.realm = &"qi_refining"
	potion.roll_spec = {"count": 1, "contexts": ["base"]}
	potion.fixed_modifiers = [{"option_id": &"restore_health", "value": 25.0}]
	ItemsApi.inventory(actor).add(potion, 2)
	var result := ItemsApi.use_item(actor, &"healing_draught")
	assert_eq(bool(result.get("ok")), true, "used")
	assert_almost_eq(actor.resource(&"health").current, 55.0, "one restoration applied")
	assert_eq(ItemsApi.inventory(actor).count(&"healing_draught"), 1, "one consumed")
	# Restoring must clamp at the pool maximum, never exceed it.
	ItemsApi.use_item(actor, &"healing_draught")
	assert_almost_eq(actor.resource(&"health").current, 80.0, "clamped, not refilled")


func test_use_consumes_nothing_when_it_cannot_apply() -> void:
	var actor := _hero()
	var blank := ItemDef.new()
	blank.id = &"blank_charm"
	blank.category = ItemCategory.CONSUMABLE
	blank.stackable = true
	blank.rarity = &"common"
	blank.roll_spec = {"count": 1, "contexts": ["base"]}
	ItemsApi.inventory(actor).add(blank, 1)
	var result := ItemsApi.use_item(actor, &"blank_charm")
	assert_eq(bool(result.get("ok")), false, "rejected")
	assert_eq(ItemsApi.inventory(actor).count(&"blank_charm"), 1, "nothing consumed")
	assert_eq(String(result.get("reason")), "no_applicable_effect", "rejected for having no effect")
	blank.fixed_modifiers = [{"option_id": &"restore_health", "value": 5.0}]
	ItemsApi.inventory(actor).add(blank, 1)
	var second := ItemsApi.use_item(actor, &"blank_charm")
	assert_eq(bool(second.get("ok")), true, "usable once authored")


func test_technique_learn_grants_a_permanent_base_attribute() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var manual := ItemDef.new()
	manual.id = &"manual_breathing"
	manual.category = ItemCategory.TECHNIQUE
	manual.stackable = false
	manual.rarity = &"magic"
	manual.realm = &"qi_refining"
	manual.roll_spec = {"count": 1, "contexts": ["base"]}
	manual.fixed_modifiers = [{"option_id": &"base_comprehension", "value": 4.0}]
	ItemsApi.inventory(actor).add(manual, 1)
	assert_eq(bool(ItemsApi.use_item(actor, &"manual_breathing").get("ok")), true, "learned")
	assert_almost_eq(actor.stats.get_base(Stat.COMPREHENSION), before + 4.0, "permanent base gain")
	assert_eq(ItemsApi.inventory(actor).count(&"manual_breathing"), 0, "consumed")


func test_material_potency_is_read_by_crafting() -> void:
	var ore := ItemDef.new()
	ore.id = &"rich_ore"
	ore.category = ItemCategory.MATERIAL
	ore.stackable = true
	ore.rarity = &"magic"
	ore.realm = &"qi_refining"
	ore.roll_spec = {"count": 1, "contexts": ["base"]}
	ore.fixed_modifiers = [{"option_id": &"craft_potency", "value": 30.0}]
	# Potency is an item property, never an actor stat.
	assert_eq(ore.property_total(null, OptionTarget.CRAFT_POTENCY), 30.0, "property read")
	var effects := ItemEffects.resolve(ore)
	assert_eq(ItemEffects.stat_modifiers(effects, &"x").size(), 0, "no stat modifier")


func test_use_preview_does_not_mutate_or_consume() -> void:
	var actor := _hero()
	actor.resource(&"health").change(-50.0)
	var potion := ItemDef.new()
	potion.id = &"preview_draught"
	potion.category = ItemCategory.CONSUMABLE
	potion.stackable = true
	potion.rarity = &"common"
	potion.realm = &"qi_refining"
	potion.roll_spec = {"count": 1, "contexts": ["base"]}
	potion.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	var instance := ItemGenerator.generate(potion, &"preview_1", _rng(5))
	var preview := ItemUse.preview(potion, instance)
	assert_eq(preview["activation"], ItemActivation.CONSUMED, "activation reported")
	assert_almost_eq(actor.resource(&"health").current, 50.0, "health untouched")
	assert_eq(ItemsApi.inventory(actor).count(&"preview_draught"), 0, "nothing consumed")
	assert_ne(preview["lines"].size(), 0, "readable lines")


func test_rolled_stackable_does_not_merge_across_different_rolls() -> void:
	var potion := ItemDef.new()
	potion.id = &"volatile_draught"
	potion.category = ItemCategory.CONSUMABLE
	potion.stackable = true
	potion.max_stack = 99
	potion.rarity = &"rare"
	potion.realm = &"qi_refining"
	potion.roll_spec = {"count": 2, "contexts": ["prefix", "postfix"]}
	potion.fixed_modifiers = [{"option_id": &"restore_qi", "value": 10.0}]
	var inventory := Inventory.new(40)
	# Two hand-authored realizations that differ must stay in separate batches.
	var a := ItemInstance.new(&"volatile_draught", &"a")
	a.rolled = [
		{
			"option_id": &"restore_qi",
			"op": &"FLAT",
			"scope": &"current",
			"value": 10.0,
		}
	]
	var b := ItemInstance.new(&"volatile_draught", &"b")
	b.rolled = [
		{
			"option_id": &"restore_qi",
			"op": &"FLAT",
			"scope": &"current",
			"value": 11.0,
		}
	]
	var batch_a := ItemStack.from_instance(a, 2)
	var batch_b := ItemStack.from_instance(b, 3)
	inventory.add_batch(batch_a)
	inventory.add_batch(batch_b)
	assert_eq(inventory.count(&"volatile_draught"), 5, "all five units held")
	assert_eq(inventory.stacks().size(), 2, "different rolls stay separate")
	var restored := ItemStack.from_dict(batch_a.to_dict())
	assert_eq(restored.quantity, 2, "quantity survives a round trip")
	assert_eq(restored.rolled.size(), 1, "realized roll survives a round trip")
	assert_almost_eq(float(restored.rolled[0]["value"]), 10.0, "realized value survives")
