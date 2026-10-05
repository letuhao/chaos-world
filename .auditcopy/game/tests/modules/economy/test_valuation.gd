extends TestCase

## ADR 0094: the price formula. The properties asserted here are the ones that make a
## price a price rather than a number that happens to be attached to an item.

var _coin: ItemDef
var _herb: ItemDef


func setup() -> void:
	_coin = Crafting.resolve(EconomyValuation.numeraire_id())
	_herb = Crafting.resolve(&"material_herb_qi_refining") as ItemDef
	if _herb == null:
		_herb = Crafting.resolve(&"herb_qi_refining") as ItemDef


func _probe(def: ItemDef, rarity: StringName = "", realm: StringName = "") -> ItemInstance:
	var instance := ItemInstance.new(def.id, &"probe")
	instance.def_ref = def
	instance.rarity = rarity if rarity != &"" else def.rarity
	instance.realm = realm if realm != &"" else def.realm
	return instance


func test_numeraire_prices_at_one() -> void:
	assert_eq(EconomyValuation.numeraire_price(), 1, "numeraire prices at 1")


func test_numeraire_ships_and_is_sound() -> void:
	var problems := EconomyApi.validate()
	assert_eq(problems.size(), 0, "numeraire audit clean: %s" % ", ".join(problems))


func test_numeraire_is_not_rollable() -> void:
	# The failure this ADR exists to prevent: the authored worth sat in the rollable pool,
	# so a coin's worth was an rng draw.
	assert_eq(_coin.roll_spec.is_empty(), true, "numeraire declares no roll_spec")


func test_unknown_rarity_prices_as_common() -> void:
	var common := EconomyValuation.rarity_weight(ItemRarity.COMMON)
	var unknown := EconomyValuation.rarity_weight(&"mythic")
	assert_eq(unknown, common, "an unknown rarity prices as common")


func test_price_uses_rarity_weight() -> void:
	var common := EconomyValuation.unit_price(10.0, ItemRarity.COMMON, &"")
	var legendary := EconomyValuation.unit_price(10.0, ItemRarity.LEGENDARY, &"")
	assert_eq(legendary > common, true, "legendary out-prices common")
	assert_almost_eq(
		float(legendary) / float(common),
		EconomyValuation.rarity_weight(ItemRarity.LEGENDARY),
		"legendary weight applied",
		0.05
	)


func test_price_uses_the_one_shared_rate_curve() -> void:
	# The whole realm argument of ADR 0094: the price moves with the ONE shared rate and
	# nothing else, so the ladder is under 2x while the actor ladder is 551x.
	var low := EconomyValuation.unit_price(10.0, ItemRarity.COMMON, &"qi_refining")
	var high := EconomyValuation.unit_price(10.0, ItemRarity.COMMON, &"primordial_origin")
	assert_eq(high > low, true, "a deep realm pays more")
	assert_eq(
		float(high) / float(low) < 2.0,
		true,
		"the price ladder is a rate, not a magnitude (under 2x across 30 realms)"
	)


func test_price_is_realm_invariant_in_ratio() -> void:
	# ADR 0063's sentence inverted: a deep buyer pays proportionally the same for the same
	# good, so the economy cannot be beaten by out-scaling the price ladder. The base worth
	# is large enough that integer rounding is well under the tolerance: at 7 the ends round
	# to 12 and 24, where one unit of rounding is ~8%.
	var low_base := EconomyValuation.unit_price(100.0, ItemRarity.COMMON, &"qi_refining")
	var high_base := EconomyValuation.unit_price(100.0, ItemRarity.COMMON, &"primordial_origin")
	var low_twice := EconomyValuation.unit_price(200.0, ItemRarity.COMMON, &"qi_refining")
	var high_twice := EconomyValuation.unit_price(200.0, ItemRarity.COMMON, &"primordial_origin")
	assert_almost_eq(
		float(high_base) / float(low_base),
		float(high_twice) / float(low_twice),
		"the realm ratio does not depend on the base worth",
		0.02
	)


func test_price_floors_at_one() -> void:
	# An unauthored worth reads as cheap, never as unsellable: this is what lets the ~250
	# authored currency items be wrong-as-prices without the game being unable to sell them.
	assert_eq(EconomyValuation.unit_price(0.0, ItemRarity.COMMON, &""), 1, "zero floors to 1")
	assert_eq(EconomyValuation.unit_price(-5.0, ItemRarity.COMMON, &""), 1, "negative floors to 1")


func test_empty_realm_is_neutral() -> void:
	assert_almost_eq(
		EconomyValuation.unit_price(10.0, ItemRarity.COMMON, &""),
		10.0,
		"an unstamped realm is neutral",
		0.5
	)


func test_rolled_worth_is_detected() -> void:
	# The structural guard, the ADR 0084 shape: tools arch cannot see a value it does not
	# compute, so a test asserts the property that must never hold.
	var instance := _probe(_coin)
	instance.rolled.append({"option_id": OptionTarget.TRADE_VALUE, "value": 99.0})
	assert_eq(EconomyValuation.has_rolled_worth(instance), true, "a rolled worth is detected")
	assert_eq(EconomyValuation.has_rolled_worth(_probe(_coin)), false, "a plain coin is not")


func test_base_worth_reads_fixed_modifiers_only() -> void:
	var instance := _probe(_coin)
	assert_almost_eq(
		EconomyValuation.base_worth(instance), 1.0, "the numeraire's authored worth is 1.0"
	)
	var rolled := _probe(_coin)
	rolled.rolled.append({"option_id": OptionTarget.TRADE_VALUE, "value": 99.0})
	assert_almost_eq(
		EconomyValuation.base_worth(rolled), 1.0, "a rolled worth does not raise the price"
	)


func test_quantity_is_multiplicative() -> void:
	var instance := _probe(_coin)
	assert_eq(
		EconomyValuation.total_price(instance, 10),
		EconomyValuation.price_of(instance) * 10,
		"quantity multiplies"
	)
	assert_eq(EconomyValuation.total_price(instance, 0), 0, "zero quantity is free")


func test_no_second_price_channel() -> void:
	# ADR 0094 deletes `ItemDef.value`; until it is deleted, nothing may read it.
	var source := FileAccess.get_file_as_string("res://src/modules/items/item_def.gd")
	assert_eq(source.contains("@export var value:"), false, "ItemDef.value is deleted")
