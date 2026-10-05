extends TestCase

## A unique's *identity*: a stable authored tag, a locked fixed signature, and a
## bounded rolled channel that may only *add* to that signature. Its boss drop
## route is the other half of a unique and lives in `test_unique_routes.gd`.


func _unique_ids() -> Array[StringName]:
	return SetCatalog.instance().unique_ids()


func _definition(item_id: StringName) -> ItemDef:
	var def := SetBonusApi.definition(item_id)
	assert_ne(def, null, "definition %s resolves" % item_id)
	return def


# --- Identity and locking ---------------------------------------------------


func test_every_shipped_unique_is_an_authored_identity() -> void:
	var ids := _unique_ids()
	assert_eq(ids.size() >= 4, true, "at least four uniques are shipped")
	for unique_id in ids:
		var def := _definition(unique_id)
		assert_eq(SetBonusApi.is_unique(def), true, "%s is a unique" % unique_id)
		assert_eq(SetBonusApi.is_unique(unique_id), true, "%s answers by id too" % unique_id)
		assert_ne(def.display_name, "", "%s has a display name" % unique_id)
		assert_ne(def.description, "", "%s has a description" % unique_id)
		assert_eq(def.category, ItemCategory.EQUIPMENT, "%s is equipment" % unique_id)
		assert_eq(def.stackable, false, "%s stays a distinct instance" % unique_id)


func test_a_unique_keeps_its_locked_fixed_options_and_still_receives_rolled_additions() -> void:
	var def := _definition(&"unique_ironhide_hearthguard")
	var locked := UniqueItem.locked_option_ids(def)
	assert_eq(locked.size(), 3, "the signature is three authored options")
	var instance := SetBonusApi.forge_unique(&"unique_ironhide_hearthguard", 104729)
	assert_ne(instance, null, "the unique forges")
	# The signature survives the roll untouched, and still applies.
	var fixed := def.effects(null).filter(
		func(effect: Dictionary) -> bool: return String(effect["channel"]) == "fixed"
	)
	assert_eq(fixed.size(), locked.size(), "every locked option still resolves")
	var applied := def.effects(instance)
	for effect in fixed:
		var matches := applied.filter(
			func(other: Dictionary) -> bool: return other["option_id"] == effect["option_id"]
		)
		assert_ne(matches.size(), 0, "%s still applies" % effect["option_id"])
	# The rolled channel is real, bounded, and never reuses a locked option.
	assert_eq(instance.rolled.size(), ItemGenerator.roll_count(def), "the roll count is filled")
	for effect in instance.rolled:
		var option_id := StringName(effect["option_id"])
		assert_eq(locked.has(option_id), false, "a locked option was never rolled")
		assert_eq(SetBonusApi.is_locked(def, option_id), false, "and is not reported as locked")
		var unit := String(effect.get("unit", "magnitude"))
		var window := OptionCatalog.instance().magnitude_bounds(
			unit, def.realm, ItemRarity.tier(def.rarity)
		)
		assert_eq(
			(
				float(effect["value"]) >= float(window["min"]) - 0.0001
				and float(effect["value"]) <= float(window["max"]) + 0.0001
			),
			true,
			"%s rolled inside its window" % option_id
		)


func test_a_unique_reports_its_locked_options_and_refuses_to_let_them_be_altered() -> void:
	var def := _definition(&"unique_stormcall_thunder_seal")
	for entry in def.fixed_modifiers:
		var option_id := StringName(entry["option_id"])
		assert_eq(SetBonusApi.is_locked(def, option_id), true, "%s is locked" % option_id)
		assert_eq(
			SetBonusApi.is_locked(&"unique_stormcall_thunder_seal", option_id),
			true,
			"and is locked by id too"
		)
	# An option the unique does not carry is not locked, so a treatment is free to
	# work on it: the predicate refuses only the authored signature.
	assert_eq(SetBonusApi.is_locked(def, &"core_crit_damage"), false, "an uncarried option is free")
	# A set piece is not a unique, so it has no locked signature at all: a
	# treatment is free to work on every option it carries.
	var piece := _definition(&"set_ironhide_vigil_band")
	for entry in piece.fixed_modifiers:
		assert_eq(
			SetBonusApi.is_locked(piece, StringName(entry["option_id"])),
			false,
			"a piece locks nothing: %s" % entry["option_id"]
		)


func test_an_ordinary_piece_is_not_a_unique_and_forges_nothing() -> void:
	var def := _definition(&"set_ironhide_vigil_band")
	assert_eq(SetBonusApi.is_unique(def), false, "a piece is not a unique")
	assert_eq(
		SetBonusApi.forge_unique(&"set_ironhide_vigil_band", 7), null, "a piece is not forged"
	)
	assert_eq(SetBonusApi.forge_unique(&"no_such_item", 7), null, "an unknown id is refused")


func test_forging_a_unique_is_deterministic_and_refills_around_the_locked_signature() -> void:
	var first := SetBonusApi.forge_unique(&"unique_void_coil_coiled_heart", 4242)
	var second := SetBonusApi.forge_unique(&"unique_void_coil_coiled_heart", 4242)
	assert_eq(first.stacking_signature(), second.stacking_signature(), "same seed, same roll")
	var other := SetBonusApi.forge_unique(&"unique_void_coil_coiled_heart", 99)
	assert_eq(other.stacking_signature() != first.stacking_signature(), true, "a new seed differs")
	var def := _definition(&"unique_void_coil_coiled_heart")
	var locked := UniqueItem.locked_option_ids(def)
	for seed_value in range(12):
		var instance := SetBonusApi.forge_unique(&"unique_void_coil_coiled_heart", seed_value)
		assert_ne(instance, null, "forged at seed %d" % seed_value)
		var seen: Array[String] = []
		for effect in instance.rolled:
			var option_id := String(effect["option_id"])
			assert_eq(locked.has(StringName(option_id)), false, "locked at seed %d" % seed_value)
			assert_eq(seen.has(option_id), false, "no repeat at seed %d" % seed_value)
			seen.append(option_id)
		assert_eq(
			instance.rolled.size(),
			ItemGenerator.roll_count(def),
			"count filled at seed %d" % seed_value
		)
