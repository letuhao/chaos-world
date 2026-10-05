extends TestCase

## The shipped set content, asserted as data rather than mirrored in code: the
## sets are complete and usable, every threshold is reachable with the declared
## members, and every authored value sits inside its option's realm/rarity window.

const GRADE_TIER := {
	&"mortal": 1,
	&"spirit": 2,
	&"earth": 2,
	&"heaven": 3,
	&"immortal": 3,
	&"divine": 4,
}


func _set_ids() -> Array[StringName]:
	return SetBonusApi.sets()


func _def(item_id: StringName) -> ItemDef:
	var def := SetBonusApi.definition(item_id)
	assert_ne(def, null, "definition %s resolves" % item_id)
	return def


## An actor with items attached and nothing worn, so inspection reports the
## authored content rather than a live equipment state.
func _reader() -> Actor:
	var actor := Actor.new(&"reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	ItemsApi.attach(actor, 48)
	SetBonusApi.attach(actor)
	return actor


func test_at_least_three_sets_are_authored_across_two_tiers_and_mixing_rarities() -> void:
	var ids := _set_ids()
	assert_eq(ids.size() >= 3, true, "at least three sets are authored")
	var tiers := {}
	var member_rarities := {}
	for set_id in ids:
		var set_def := SetBonusApi.set_definition(set_id)
		assert_ne(set_def, null, "%s resolves" % set_id)
		tiers[RealmDefaults.ladder().tier_of(set_def.realm)] = true
		for member_id in set_def.member_ids():
			member_rarities[ItemRarity.tier(_def(member_id).rarity)] = true
	assert_eq(tiers.size() >= 2, true, "the sets span at least two realm tiers")
	assert_eq(member_rarities.size() >= 3, true, "members mix at least three rarities")
	assert_eq(
		(
			member_rarities.has(ItemRarity.tier(ItemRarity.COMMON))
			and member_rarities.has(ItemRarity.tier(ItemRarity.LEGENDARY))
		),
		true,
		"the rarities really do span common through legendary"
	)


func test_every_set_is_complete_and_usable() -> void:
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		var members := set_def.member_ids()
		assert_eq(members.size() >= 3, true, "%s has enough members to be a set" % set_id)
		assert_ne(set_def.description, "", "%s has a description" % set_id)
		assert_ne(set_def.display_name, "", "%s has a display name" % set_id)
		var seen := {}
		var subtypes := {}
		for member_id in members:
			assert_eq(seen.has(String(member_id)), false, "%s has no duplicate member" % set_id)
			seen[String(member_id)] = true
			var def := _def(member_id)
			assert_eq(
				def.category, ItemCategory.EQUIPMENT, "%s: %s is equipment" % [set_id, member_id]
			)
			assert_eq(def.stackable, false, "%s: %s is not stackable" % [set_id, member_id])
			assert_eq(
				def.sources.is_empty(),
				false,
				"%s: %s has an acquisition source" % [set_id, member_id]
			)
			assert_ne(def.description, "", "%s: %s has a description" % [set_id, member_id])
			assert_eq(
				int(def.roll_spec.get("count", 0)),
				ItemRarity.affix_count(def.rarity),
				"%s: %s roll count matches its rarity" % [set_id, member_id]
			)
			subtypes[String(def.subcategory)] = true
			assert_eq(
				int(GRADE_TIER.get(def.grade, 0)) <= RealmDefaults.ladder().tier_of(def.realm),
				true,
				"%s: %s realm is at or above its grade tier" % [set_id, member_id]
			)
		assert_eq(subtypes.size() >= 3, true, "%s spans several equipment slots" % set_id)
		assert_eq(subtypes.has(String(ItemSubtype.ARMOR)), true, "%s has an armor member" % set_id)
		for unique_id in set_def.uniques:
			assert_eq(
				UniqueItem.is_unique(_def(unique_id)),
				true,
				"%s: %s is a unique" % [set_id, unique_id]
			)


func test_every_threshold_value_sits_inside_its_option_magnitude_window() -> void:
	var catalog := OptionCatalog.instance()
	var ladder := RealmDefaults.ladder()
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		var realm_index := ladder.index_of(set_def.realm)
		var rarity_index := ItemRarity.tier(set_def.rarity)
		assert_eq(realm_index >= 0, true, "%s names a canonical realm" % set_id)
		for index in set_def.tiers.size():
			for entry in (set_def.tiers[index] as Dictionary)["options"]:
				var option_id := StringName(entry["option_id"])
				var record := catalog.option_record(option_id)
				assert_ne(record, {}, "%s tier %d: %s is registered" % [set_id, index, option_id])
				assert_eq(
					catalog.allows_activation(option_id, ItemActivation.EQUIPPED),
					true,
					"%s tier %d: %s has an equipped consumer" % [set_id, index, option_id]
				)
				var window := catalog.magnitude_bounds(
					String(record["unit"]), set_def.realm, rarity_index
				)
				var value := float(entry["value"])
				assert_eq(
					value != 0.0,
					true,
					"%s tier %d: %s grants something" % [set_id, index, option_id]
				)
				assert_eq(
					(
						value >= float(window["min"]) - 0.0001
						and value <= float(window["max"]) + 0.0001
					),
					true,
					(
						"%s tier %d: %s = %s inside [%s, %s]"
						% [
							set_id,
							index,
							option_id,
							value,
							window["min"],
							window["max"],
						]
					)
				)


func test_every_piece_fixed_value_sits_inside_its_option_magnitude_window() -> void:
	var catalog := OptionCatalog.instance()
	var ladder := RealmDefaults.ladder()
	for set_id in _set_ids():
		for member_id in SetBonusApi.set_definition(set_id).member_ids():
			var def := _def(member_id)
			assert_eq(
				not def.fixed_modifiers.is_empty(), true, "%s has a fixed channel" % member_id
			)
			var realm_index := ladder.index_of(def.realm)
			for entry in def.fixed_modifiers:
				var option_id := StringName(entry["option_id"])
				var record := catalog.option_record(option_id)
				assert_ne(
					record, {}, "%s references a registered option %s" % [member_id, option_id]
				)
				var window := (
					catalog
					. magnitude_bounds(
						String(record["unit"]),
						def.realm,
						ItemRarity.tier(def.rarity),
					)
				)
				var value := float(entry["value"])
				assert_eq(
					(
						value >= float(window["min"]) - 0.0001
						and value <= float(window["max"]) + 0.0001
					),
					true,
					"%s: %s = %s inside its window" % [member_id, option_id, value]
				)
			for source in def.sources:
				var parts := String(source).split(":", true, 1)
				assert_eq(parts.size(), 2, "%s: %s is a typed source" % [member_id, source])
				assert_eq(parts[0], "boss", "%s names a real acquisition kind" % member_id)
				assert_eq(
					ResourceLoader.exists("res://data/bosses/%s.tres" % parts[1]),
					true,
					"%s: boss %s exists" % [member_id, parts[1]]
				)


func test_inspection_reports_identity_membership_and_active_thresholds_for_every_set() -> void:
	var snapshot := SetBonusApi.inspect(_reader())
	assert_eq(int(snapshot["set_count"]), _set_ids().size(), "every set is reported")
	assert_eq(int(snapshot["unique_total"]) >= 4, true, "at least four uniques are reported")
	for set_id in _set_ids():
		var view: Dictionary = snapshot["sets"][String(set_id)]
		assert_eq(String(view["set_id"]), String(set_id), "identity")
		assert_ne(String(view["display_name"]), "", "display name")
		assert_ne(String(view["description"]), "", "description")
		assert_eq(String(view["counting"]), String(SetDef.COUNT_DISTINCT_DEFINITION), "policy")
		assert_eq((view["members"] as Array).size(), int(view["member_count"]), "membership")
		assert_eq(
			(view["thresholds"] as Array).size(),
			SetBonusApi.set_definition(set_id).tiers.size(),
			"every authored threshold is listed"
		)
		assert_eq(int(view["equipped_count"]), 0, "nothing is worn on a bare actor")
		for threshold in view["thresholds"]:
			assert_eq(
				bool(threshold["active"]), false, "no threshold is active when nothing is worn"
			)
			assert_eq(
				(threshold["options"] as Array).is_empty(), false, "a threshold grants something"
			)
			assert_eq(
				String(threshold["source"]),
				String(SetBonusState.tier_source(set_id, int(threshold["index"]))),
				"the threshold names its own source"
			)
		for member in view["members"]:
			var entry: Dictionary = member
			assert_ne(String(entry["kind"]), "", "%s reports its kind" % entry["def_id"])
			assert_eq(bool(entry["equipped"]), false, "nothing is worn")
			assert_eq(
				(entry["fixed_options"] as Array).is_empty(), false, "its own fixed options show"
			)
			if bool(entry["is_unique"]):
				assert_eq(
					(entry["locked_option_ids"] as Array).is_empty(),
					false,
					"a unique shows its lock"
				)
				assert_ne(String(entry["route_boss_id"]), "", "and its route")


func test_set_ids_are_canonically_ordered_so_a_screen_can_cycle_them() -> void:
	var ids := _set_ids()
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted, "the catalog hands out a stable order")
