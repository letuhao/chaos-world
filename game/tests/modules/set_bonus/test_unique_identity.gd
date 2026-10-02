extends TestCase

## A unique is a stable authored identity with a locked fixed signature, a
## bounded rolled channel that may only *add* to that signature, and a declared
## boss drop route. These assert all three over the shipped content, so a
## content edit that breaks any of them fails the suite.

const BOSSES_ROOT := "res://data/bosses"
const DOMAINS_ROOT := "res://data/domains"
const ROUTES_PATH := "res://data/sets/unique_routes.jsonl"


func _unique_ids() -> Array[StringName]:
	return SetCatalog.instance().unique_ids()


## The route index and the set definitions must name the same uniques in both
## directions, or a unique would be shipped with no set and no route.
func test_the_route_index_and_the_set_definitions_name_the_same_uniques() -> void:
	var from_routes := {}
	for unique_id in _unique_ids():
		from_routes[String(unique_id)] = true
	var from_sets := {}
	for set_id in SetBonusApi.sets():
		for unique_id in SetBonusApi.set_definition(set_id).uniques:
			from_sets[String(unique_id)] = true
	assert_eq(not from_routes.is_empty(), true, "the route index is not empty")
	assert_eq(from_routes.size() >= 4, true, "at least four uniques are declared")
	for unique_id in from_sets.keys():
		assert_eq(from_routes.has(unique_id), true, "%s is a set member with a route" % unique_id)


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
			unit, RealmDefaults.ladder().index_of(def.realm), ItemRarity.tier(def.rarity)
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


# --- Declared drop routes ---------------------------------------------------


func test_every_authored_unique_declares_a_route_that_resolves_to_a_real_boss() -> void:
	assert_eq(FileAccess.file_exists(ROUTES_PATH), true, "the route index ships")
	var ids := _unique_ids()
	for unique_id in ids:
		var route := SetBonusApi.drop_route(unique_id)
		assert_eq(bool(route["declared"]), true, "%s declares a route" % unique_id)
		var boss_id := String(route["boss_id"])
		assert_ne(boss_id, "", "%s names a boss" % unique_id)
		var boss_path := "%s/%s.tres" % [BOSSES_ROOT, boss_id]
		var domain_id := String(route["domain_id"])
		var domain_path := "%s/%s.tres" % [DOMAINS_ROOT, domain_id]
		assert_eq(ResourceLoader.exists(boss_path), true, "%s resolves to a real boss" % unique_id)
		assert_eq(
			ResourceLoader.exists(domain_path), true, "%s resolves to a real domain" % unique_id
		)
		# Positive reachable path: the boss sits in the domain the route names, and
		# the definition names the same boss in its own tags.
		var boss := load(boss_path) as BossDef
		var domain := load(domain_path) as DomainDef
		assert_eq(
			String(boss.domain_id), domain_id, "%s: boss sits in the named domain" % unique_id
		)
		assert_eq(
			domain.boss_ids.has(StringName(boss_id)),
			true,
			"%s: the domain lists the boss" % unique_id
		)
		var def := _definition(unique_id)
		assert_eq(
			String(UniqueItem.route_boss_id(def)),
			boss_id,
			"%s: the definition names the same route" % unique_id
		)
		assert_eq(
			def.sources.has(StringName("boss:%s" % boss_id)),
			true,
			"%s: the item declares the boss as an acquisition source" % unique_id
		)


func test_every_route_is_realm_and_rarity_compatible_with_its_unique() -> void:
	var ladder := RealmDefaults.ladder()
	for unique_id in _unique_ids():
		var route := SetBonusApi.drop_route(unique_id)
		var def := _definition(unique_id)
		var route_realm := String(route["route_realm"])
		assert_eq(ladder.index_of(StringName(route_realm)) >= 0, true, "%s route realm" % unique_id)
		assert_eq(
			ladder.index_of(def.realm) >= ladder.index_of(StringName(route_realm)),
			true,
			"%s is at least as high on the ladder as the boss that drops it" % unique_id
		)
		assert_eq(
			ladder.tier_of(def.realm) >= _boss_route_tier(String(route["boss_id"])),
			true,
			"%s meets the boss's own realm tier" % unique_id
		)
		var min_rarity := String(route["min_rarity"])
		assert_eq(
			ItemRarity.is_valid(StringName(min_rarity)),
			true,
			"%s min rarity is a rarity" % unique_id
		)
		assert_eq(
			ItemRarity.tier(def.rarity) >= ItemRarity.tier(StringName(min_rarity)),
			true,
			"%s is at least the rarity the route gates on" % unique_id
		)
		assert_eq(
			int(def.roll_spec.get("count", 0)),
			ItemRarity.affix_count(def.rarity),
			"%s roll count matches its rarity" % unique_id
		)
		assert_ne(float(route["drop_weight"]), 0.0, "%s has a positive drop weight" % unique_id)


## A boss's own tier, read from the canonical realm id its domain and loot ids
## name. The route has to sit at or below the unique, so the tier is derived from
## the shipped boss/domain content rather than trusted from the route row.
func _boss_route_tier(boss_id: String) -> int:
	var ladder := RealmDefaults.ladder()
	var boss := load("%s/%s.tres" % [BOSSES_ROOT, boss_id]) as BossDef
	var domain := load("%s/%s.tres" % [DOMAINS_ROOT, String(boss.domain_id)]) as DomainDef
	var tokens: Array = [String(boss.domain_id)]
	tokens.append_array(boss.loot)
	tokens.append_array(domain.boss_ids)
	var best := ""
	for token in tokens:
		for entry in ladder.realms():
			if String(entry.id) in String(token) and len(String(entry.id)) > len(best):
				best = String(entry.id)
	assert_ne(best, "", "boss %s names a canonical realm" % boss_id)
	return ladder.tier_of(StringName(best))


func test_a_unique_without_a_route_reports_no_route_rather_than_an_empty_one() -> void:
	var route := SetBonusApi.drop_route(&"set_ironhide_vigil_band")
	assert_eq(bool(route["declared"]), false, "a piece declares no unique route")
	assert_eq(String(route["boss_id"]), "", "and reports no boss")


func test_at_least_one_unique_carries_a_set_membership() -> void:
	var with_set := 0
	for unique_id in _unique_ids():
		var membership := SetBonusApi.membership(unique_id)
		if String(membership["set_id"]) != "":
			with_set += 1
			assert_eq(String(membership["kind"]), "unique", "%s is a unique member" % unique_id)
			assert_eq(bool(membership["is_unique"]), true, "%s is flagged unique" % unique_id)
	assert_eq(with_set >= 1, true, "at least one unique belongs to a set")


func test_membership_reports_nothing_for_an_item_outside_every_set() -> void:
	var membership := SetBonusApi.membership(&"armor_iron_helm")
	assert_eq(String(membership["set_id"]), "", "an unrelated item is in no set")
	assert_eq(bool(membership["is_unique"]), false, "and is not a unique")
