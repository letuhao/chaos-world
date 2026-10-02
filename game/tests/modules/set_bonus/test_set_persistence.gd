extends TestCase

## The set state is a versioned plain dictionary under `actor.module_data`, so
## core persists it without ever naming a set type (ADR 0027). These assert the
## payload round trips, that a legacy save with no set state loads as empty, and
## that the live state is always re-derived from what is worn.

const MODULE_KEY := &"set_state"
const SET_ID := &"ironhide_vigil"
const BAND := "set_ironhide_vigil_band"
const PLATE := "set_ironhide_vigil_wardplate"
const BLADE := "set_ironhide_vigil_greatblade"


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor, 48)
	SetBonusApi.attach(actor)
	return actor


func _wear(actor: Actor, slot: StringName, def_id: String) -> void:
	var def := SetBonusApi.definition(StringName(def_id))
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(actor, slot, def), true, "wore %s" % def_id)


func _set_entry(actor: Actor) -> Dictionary:
	return SetBonusApi.state(actor).get("sets", {}).get(String(SET_ID), {})


## The total value the SET itself contributes, summed over every threshold the
## actor currently holds. Read from the modifier stack, so a member's own rolled
## affixes are excluded.
func _set_total(actor: Actor) -> float:
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if String(modifier.source).begins_with(SetBonusState.SOURCE_PREFIX):
			total += modifier.value
	return total


# --- The payload ------------------------------------------------------------


func test_the_set_state_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), SetBonusState.SCHEMA_VERSION, "versioned")
	assert_eq((stored["sets"] as Dictionary).has(String(SET_ID)), true, "the set is recorded")
	var entry: Dictionary = (stored["sets"] as Dictionary)[String(SET_ID)]
	assert_eq(int(entry["distinct"]), 2, "two distinct members")
	assert_eq(entry["members"] as Array, [BAND, PLATE], "members by definition id")
	assert_eq(String((entry["slots"] as Dictionary)[PLATE]), "armor", "the slot each member fills")
	assert_eq(entry["active_tiers"] as Array, [0], "the threshold it reaches")
	assert_eq(SetBonusApi.state(actor), stored, "the facade reports the persisted payload")


func test_membership_equipped_pieces_and_active_thresholds_survive_a_payload_round_trip() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	_wear(actor, &"weapon", BLADE)
	var before := _set_entry(actor)
	assert_eq(before["active_tiers"] as Array, [0, 1], "two thresholds were active")
	# A real actor payload round trip: to_dict -> from_dict, no set type involved.
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	var carried: Dictionary = restored.get_module_data(MODULE_KEY)
	assert_eq(carried, SetBonusApi.state(actor), "the payload carried the set state verbatim")
	assert_eq((carried["sets"] as Dictionary)[String(SET_ID)], before, "and the whole set entry")
	# It survives a JSON hop, which is what a file-backed save does. JSON has one
	# number type, so the load path normalizes back to the persisted shape rather
	# than comparing raw floats.
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(
		SetBonusState.normalize(from_json.get_module_data(MODULE_KEY)),
		SetBonusApi.state(actor),
		"JSON round trip"
	)


func test_a_restored_actor_re_derives_the_same_state_from_what_is_worn() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	_wear(actor, &"weapon", BLADE)
	var before := _set_entry(actor)
	var before_total := _set_total(actor)
	var restored := Actor.from_dict(actor.to_dict())
	ItemsApi.attach(restored, 48)
	SetBonusApi.attach(restored)
	# Worn pieces come back through the items layer, then the set state is
	# re-derived from them rather than trusted from the payload.
	for entry in [["accessory_a", BAND], ["armor", PLATE], ["weapon", BLADE]]:
		_wear(restored, StringName(entry[0]), String(entry[1]))
	SetBonusApi.refresh(restored)
	assert_eq(_set_entry(restored), before, "the same members, slots and thresholds")
	# The set's own contribution is compared rather than a whole derived stat:
	# each worn piece is rolled afresh here, so a member's own affixes are not
	# expected to match, while the set's authored bonus must.
	assert_almost_eq(_set_total(restored), before_total, "and the same set-owned applied total")


func test_a_legacy_payload_with_no_set_state_loads_cleanly_as_the_empty_state() -> void:
	var actor := _hero()
	_wear(actor, &"accessory_a", BAND)
	_wear(actor, &"armor", PLATE)
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	legacy.erase("item_state")
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no set state")
	ItemsApi.attach(restored, 48)
	SetBonusApi.attach(restored)
	var state := SetBonusApi.state(restored)
	assert_eq(int(state["version"]), SetBonusState.SCHEMA_VERSION, "still versioned")
	assert_eq(state["sets"] as Dictionary, {}, "and empty, not partial")
	assert_eq(restored.get_module_data(MODULE_KEY)["sets"] as Dictionary, {}, "written back empty")
	assert_eq(SetBonusApi.inspect(restored)["active_set_ids"], [], "no set reports active")


func test_an_unreadable_set_state_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{},
		{"version": 0, "sets": {"ironhide_vigil": {"distinct": 9}}},
		{"version": 1},
		{"version": 1, "sets": "not a dictionary"},
	]:
		var normalized := SetBonusState.normalize(payload)
		assert_eq(normalized["sets"] as Dictionary, {}, "rejected payload %s" % [payload])
	var restored := _hero(&"corrupt")
	restored.set_module_data(MODULE_KEY, {"version": 1, "sets": {"ghost_set": {"distinct": 4}}})
	SetBonusApi.attach(restored)
	var state := SetBonusApi.state(restored)
	assert_eq(state["sets"] as Dictionary, {}, "a set that no longer exists is not kept")


func test_a_set_state_normalizes_a_legacy_shape_with_no_slots_or_tiers() -> void:
	var normalized := SetBonusState.normalize(
		{"version": 1, "sets": {"ironhide_vigil": {"distinct": 2, "members": [PLATE, BAND]}}}
	)
	var entry: Dictionary = (normalized["sets"] as Dictionary)["ironhide_vigil"]
	assert_eq(entry["members"] as Array, [BAND, PLATE], "members are canonically ordered")
	assert_eq(entry["slots"] as Dictionary, {}, "no slots recorded")
	assert_eq(entry["active_tiers"] as Array, [], "no thresholds recorded")
	assert_eq(int(entry["distinct"]), 2, "the count survives")


func test_attaching_to_an_actor_with_no_items_is_harmless() -> void:
	var bare := Actor.new(&"bare", {Stat.PHYSIQUE: 10.0})
	SetBonusApi.attach(bare)
	var state := SetBonusApi.state(bare)
	assert_eq(state["sets"] as Dictionary, {}, "no items, no set state")
	assert_eq(SetBonusApi.refresh(bare), state, "a refresh reproduces the same state")
	assert_eq(SetBonusApi.inspect(bare)["has_actor"], true, "an actor is still reported")
	assert_eq(SetBonusApi.state(null), {"version": 1, "sets": {}}, "a null actor is empty")
	assert_eq(SetBonusApi.inspect(null), {}, "nothing to inspect without an actor")
	assert_eq(SetBonusApi.refresh(null), {}, "and nothing to refresh")
