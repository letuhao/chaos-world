extends TestCase

## Set thresholds are recomputed from the equipment that is actually worn, and
## a threshold's contribution is keyed by the set's own source id. These assert
## that crossing a threshold up and back leaves nothing stale or doubled, that a
## duplicated piece is not a second member, and that many cycles do not drift.

const SET_ID := &"ironhide_vigil"
const SLOT_BAND := &"accessory_a"
const SLOT_PLATE := &"armor"
const SLOT_LENS := &"accessory_b"
const SLOT_BLADE := &"weapon"
const SLOT_GUARD := &"artifact"

## Members in slot order, so a test can wear any prefix of the set.
const BAND := "set_ironhide_vigil_band"
const PLATE := "set_ironhide_vigil_wardplate"
const LENS := "set_ironhide_vigil_lens"
const BLADE := "set_ironhide_vigil_greatblade"
const GUARD := "unique_ironhide_hearthguard"


func _hero() -> Actor:
	var actor := Actor.new(&"vigil", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor, 48)
	SetBonusApi.attach(actor)
	return actor


func _def(def_id: String) -> ItemDef:
	var def := SetBonusApi.definition(StringName(def_id))
	assert_ne(def, null, "definition %s resolves through the module" % def_id)
	return def


func _wear(actor: Actor, slot: StringName, def_id: String) -> void:
	var def := _def(def_id)
	ItemsApi.inventory(actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(actor, slot, def), true, "wore %s in %s" % [def_id, slot])


func _take_off(actor: Actor, slot: StringName) -> void:
	assert_eq(ItemsApi.unequip_to_inventory(actor, slot), true, "removed %s" % slot)


func _live(actor: Actor) -> Dictionary:
	var sets: Dictionary = SetBonusApi.state(actor).get("sets", {})
	return sets.get(String(SET_ID), {})


func _active_tiers(actor: Actor) -> Array:
	return _live(actor).get("active_tiers", [])


func _members(actor: Actor) -> Array:
	return _live(actor).get("members", [])


## Every stat-modifier source currently on the stack. The set module's own source
## ids are the point of the whole test, so they are read directly rather than
## inferred from a total.
func _sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		out.append(String(modifier.source))
	return out


func _source_count(actor: Actor, source: String) -> int:
	var total := 0
	for found in _sources(actor):
		if found == source:
			total += 1
	return total


# --- Counting: N of M distinct members --------------------------------------


func test_equipping_n_of_m_distinct_members_activates_exactly_the_thresholds_for_n() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	assert_eq(_members(actor), [BAND], "one member is one member")
	assert_eq(_active_tiers(actor), [], "one member reaches no threshold")
	_wear(actor, SLOT_PLATE, PLATE)
	assert_eq(_active_tiers(actor), [0], "two members reach the first threshold")
	_wear(actor, SLOT_BLADE, BLADE)
	assert_eq(_active_tiers(actor), [0, 1], "three members reach two thresholds")
	_wear(actor, SLOT_LENS, LENS)
	assert_eq(_active_tiers(actor), [0, 1, 2], "four members reach three thresholds")
	_wear(actor, SLOT_GUARD, GUARD)
	assert_eq(_active_tiers(actor), [0, 1, 2, 3], "five members reach every threshold")


func test_a_partial_set_activates_its_partial_thresholds_only() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var view: Dictionary = SetBonusApi.inspect(actor)["sets"][String(SET_ID)]
	var thresholds: Array = view["thresholds"]
	assert_eq(thresholds.size(), 4, "every authored threshold is reported")
	assert_eq(bool(thresholds[0]["active"]), true, "the two-member threshold is active")
	assert_eq(bool(thresholds[1]["active"]), false, "the three-member threshold is not")
	assert_eq(bool(thresholds[3]["active"]), false, "the complete threshold is not")
	assert_eq(int(view["equipped_count"]), 2, "two members worn")
	assert_eq(bool(view["complete"]), false, "the set is not complete")


func test_two_copies_of_one_piece_in_two_slots_count_as_one_member() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	# The same definition in the second accessory slot: a distinct *instance* of
	# one piece, which the declared counting policy refuses to count twice.
	_wear(actor, SLOT_LENS, BAND)
	var live := _live(actor)
	assert_eq(int(live["distinct"]), 1, "one distinct definition")
	assert_eq((live["members"] as Array).size(), 1, "one member recorded")
	assert_eq(_active_tiers(actor), [], "no threshold is reached by duplication")
	assert_eq(
		String((live["slots"] as Dictionary)[BAND]),
		String(SLOT_BAND),
		"the first slot that holds the member is the one recorded"
	)


func test_the_counting_policy_is_declared_in_data_not_implied_by_code() -> void:
	var set_def := SetBonusApi.set_definition(SET_ID)
	assert_ne(set_def, null, "the set resolves")
	assert_eq(set_def.counting, SetDef.COUNT_DISTINCT_DEFINITION, "policy is declared")
	assert_eq(_hero().component(SetBonusApi.STATE_COMPONENT) != null, true, "state attached")


# --- Ownership: the bonus belongs to the set, not to a member --------------


func test_a_threshold_bonus_is_keyed_by_the_set_not_by_a_members_instance_id() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var sources := _sources(actor)
	assert_eq(
		sources.has(String(SetBonusState.tier_source(SET_ID, 0))),
		true,
		"the set's own source is used"
	)
	for slot in [SLOT_BAND, SLOT_PLATE]:
		var instance: ItemInstance = ItemsApi.equipment(actor).equipped(slot)
		assert_ne(instance, null, "slot %s holds an instance" % slot)
		assert_eq(
			sources.has(String(instance.instance_id)), true, "the member keeps its own source"
		)
		assert_eq(
			_set_sources(sources).has(String(instance.instance_id)),
			false,
			"the set never borrows a member's instance id as its source"
		)


func _set_sources(sources: Array) -> Array:
	var out: Array = []
	for source in sources:
		if String(source).begins_with(SetBonusState.SOURCE_PREFIX):
			out.append(source)
	return out


## The total value the SET itself contributes, summed over every threshold the
## actor currently holds. Measured from the modifier stack rather than from a
## derived stat, because a threshold may grant a rate the derived total clamps.
func _set_total(actor: Actor) -> float:
	var total := 0.0
	for modifier in actor.stats._modifiers:
		if String(modifier.source).begins_with(SetBonusState.SOURCE_PREFIX):
			total += modifier.value
	return total


func test_unequipping_one_member_keeps_the_other_members_bonus_and_the_set_bonus() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var two_member_total := _set_total(actor)
	var two_member_defense := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	_wear(actor, SLOT_BLADE, BLADE)
	var three_member_total := _set_total(actor)
	assert_eq(
		three_member_total > two_member_total, true, "the third threshold added to the set's bonus"
	)
	# Defense is a stat the third threshold raises directly, so the applied total
	# moves with the set's own contribution.
	assert_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL) > two_member_defense,
		true,
		"the third threshold raised defense"
	)
	var blade: ItemInstance = ItemsApi.equipment(actor).equipped(SLOT_BLADE)
	var blade_alone := blade.stacking_signature()
	_take_off(actor, SLOT_PLATE)
	var sources := _sources(actor)
	assert_eq(
		sources.has(String(SetBonusState.tier_source(SET_ID, 0))), true, "threshold 0 still holds"
	)
	assert_eq(sources.has(String(SetBonusState.tier_source(SET_ID, 1))), false, "threshold 1 broke")
	assert_eq(sources.has(String(blade.instance_id)), true, "the other member's bonus is untouched")
	var kept: ItemInstance = ItemsApi.equipment(actor).equipped(SLOT_BLADE)
	assert_eq(kept.stacking_signature(), blade_alone, "the kept member is the same instance")
	# The set's own contribution is back to exactly the two-member one: the broken
	# threshold is gone once, and nothing else moved.
	assert_almost_eq(_set_total(actor), two_member_total, "one threshold, once")


# --- Idempotence: up and back, then many cycles -----------------------------


func test_crossing_a_threshold_upward_and_back_leaves_no_stale_or_doubled_effect() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var at_two := _fingerprint(actor)
	_wear(actor, SLOT_BLADE, BLADE)
	_wear(actor, SLOT_LENS, LENS)
	var at_four := _fingerprint(actor)
	assert_eq(at_four["set_total"] > at_two["set_total"], true, "more members, more set bonus")
	assert_eq(at_four["modifiers"] > at_two["modifiers"], true, "more members, more modifiers")
	# Poise only ever moves when the four-member threshold is active, so a changed
	# poise is direct evidence that the threshold's effect was actually applied.
	assert_eq(at_four["poise"] > at_two["poise"], true, "the four-member threshold raised poise")
	_take_off(actor, SLOT_LENS)
	_take_off(actor, SLOT_BLADE)
	var back := _fingerprint(actor)
	assert_almost_eq(back["set_total"], at_two["set_total"], "no stale bonus left behind")
	assert_eq(back["modifiers"], at_two["modifiers"], "no doubled or stale modifier")
	assert_eq(back["tiers"], at_two["tiers"], "the active thresholds are back where they were")
	assert_eq(back["sources"], at_two["sources"], "the source set is identical")
	assert_almost_eq(back["poise"], at_two["poise"], "the applied total is back too")


func test_repeated_equip_unequip_and_rebuild_cycles_do_not_drift() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var baseline := _fingerprint(actor)
	for cycle in 24:
		_wear(actor, SLOT_BLADE, BLADE)
		_wear(actor, SLOT_LENS, LENS)
		ItemsApi.equipment(actor).rebuild(actor, SLOT_BLADE)
		ItemsApi.equipment(actor).rebuild(actor, SLOT_LENS)
		SetBonusApi.refresh(actor)
		_take_off(actor, SLOT_LENS)
		_take_off(actor, SLOT_BLADE)
		var now := _fingerprint(actor)
		assert_almost_eq(now["health"], baseline["health"], "health after cycle %d" % cycle)
		assert_eq(now["modifiers"], baseline["modifiers"], "modifiers after cycle %d" % cycle)
		assert_eq(now["tiers"], baseline["tiers"], "tiers after cycle %d" % cycle)
		# The numeric total over many cycles: the set's own contribution and every
		# applied derived stat must land on exactly the baseline again.
		assert_almost_eq(
			now["set_total"], baseline["set_total"], "set total after cycle %d" % cycle
		)
		assert_almost_eq(now["poise"], baseline["poise"], "poise after cycle %d" % cycle)
		assert_almost_eq(now["defense"], baseline["defense"], "defense after cycle %d" % cycle)
		assert_eq(now["sources"], baseline["sources"], "sources after cycle %d" % cycle)


func test_a_threshold_bonus_survives_rebuild_of_every_slot() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	_wear(actor, SLOT_BLADE, BLADE)
	var before := _fingerprint(actor)
	for slot in Equipment.SLOTS:
		if ItemsApi.equipment(actor).equipped(slot) != null:
			ItemsApi.equipment(actor).rebuild(actor, slot)
	SetBonusApi.refresh(actor)
	var after := _fingerprint(actor)
	assert_eq(after["modifiers"], before["modifiers"], "a rebuild replaces, never stacks")
	assert_almost_eq(after["set_total"], before["set_total"], "the set bonus is unchanged")
	assert_almost_eq(after["poise"], before["poise"], "the total is unchanged by a rebuild")
	assert_eq(after["tiers"], before["tiers"], "the thresholds did not move")
	assert_eq(after["sources"], before["sources"], "nor did the source set")


func test_unequipping_a_whole_set_removes_the_bonus_exactly_once() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	_wear(actor, SLOT_BLADE, BLADE)
	assert_eq(_source_count(actor, String(SetBonusState.tier_source(SET_ID, 0))), 2, "two options")
	_take_off(actor, SLOT_BAND)
	_take_off(actor, SLOT_PLATE)
	_take_off(actor, SLOT_BLADE)
	assert_eq(_set_sources(_sources(actor)), [], "no set source survives an empty set")
	assert_eq(_active_tiers(actor), [], "no threshold is active")
	assert_eq(SetBonusApi.inspect(actor)["active_set_ids"], [], "no set reports active")


func test_attaching_twice_is_idempotent() -> void:
	var actor := _hero()
	_wear(actor, SLOT_BAND, BAND)
	_wear(actor, SLOT_PLATE, PLATE)
	var before := _fingerprint(actor)
	SetBonusApi.attach(actor)
	SetBonusApi.attach(actor)
	var after := _fingerprint(actor)
	assert_eq(after["modifiers"], before["modifiers"], "re-attaching never doubles a bonus")
	assert_almost_eq(after["health"], before["health"], "and never changes a total")


## Everything a numeric drift assertion needs: the derived total, the number of
## modifiers on the stack, the active threshold indices and the source set.
func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"health": actor.stats.derived(Stat.MAX_HEALTH),
		"defense": actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		"poise": actor.stats.derived(Stat.POISE),
		"set_total": _set_total(actor),
		"modifiers": actor.stats.modifier_count(),
		"tiers": _active_tiers(actor),
		"sources": _sorted(_sources(actor)),
	}


func _sorted(values: Array) -> Array:
	var out: Array = values.duplicate()
	out.sort()
	return out
