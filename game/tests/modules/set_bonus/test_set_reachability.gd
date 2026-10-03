extends TestCase

## Every authored set tier must be genuinely winnable, and "winnable" has to mean
## a real body wearing real items — not a number comparing correctly against
## another number.
##
## The bug this file exists for: `void_serpent_coil` shipped a `count: 6` tier
## while `Equipment.SLOTS` has five entries, so no body could ever reach it. The
## old guard asserted `needed <= member_count()` and `active_tier_indices(
## member_count())`, both pure arithmetic over the set's own declarations, so it
## reported that dead tier as reachable. The ceiling now reads the same slot list
## the runtime iterates, and the tiers are checked on a stat stack after equipping.

## The subtype-to-slot routing the shipped equip path uses. Kept here rather than
## imported from `ui/` so this stays a gameplay test. A member whose subtype is
## not in this map falls through to an accessory slot, so a new subtype makes the
## `filled N slots` assertion below fail loudly rather than quietly misplace a
## piece.
const SUBTYPE_SLOT := {
	&"weapon": &"weapon",
	&"armor": &"armor",
	&"artifact": &"artifact",
}

const ACCESSORY_SLOTS: Array[StringName] = [&"accessory_a", &"accessory_b"]


func _set_ids() -> Array[StringName]:
	return SetBonusApi.sets()


func test_every_authored_threshold_is_actually_reachable_with_the_declared_members() -> void:
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		# The ceiling is the REAL slot list, not arithmetic over the set's own
		# member count: that arithmetic could not fail, and it called a six-member
		# tier reachable on a five-slot body.
		var ceiling := set_def.max_equippable()
		var previous := 0
		var reachable := 0
		for index in set_def.tiers.size():
			var tier: Dictionary = set_def.tiers[index]
			var needed := int(tier.get("count", 0))
			assert_eq(needed > previous, true, "%s tier %d is ascending" % [set_id, index])
			previous = needed
			assert_eq(
				needed <= ceiling,
				true,
				(
					(
						"%s tier %d (%s) needs %d distinct members, but at most %d can ever be "
						+ "worn: %d declared members across %d equipment slots"
					)
					% [
						set_id,
						index,
						String(tier.get("label", "")),
						needed,
						ceiling,
						set_def.member_count(),
						Equipment.SLOTS.size(),
					]
				)
			)
			assert_eq(needed >= 2, true, "%s tier %d needs a pair" % [set_id, index])
			assert_ne(String(tier.get("label", "")), "", "%s tier %d is labelled" % [set_id, index])
			assert_eq(
				(tier.get("options", []) as Array).is_empty(),
				false,
				"%s tier %d grants" % [set_id, index]
			)
			reachable += 1
		assert_eq(reachable >= 2, true, "%s has more than one threshold" % set_id)
		assert_eq(set_def.unreachable_tier_indices(), [], "%s: no authored tier is dead" % set_id)
		assert_eq(
			(set_def.active_tier_indices(ceiling) as Array).size(),
			set_def.tiers.size(),
			"%s: a fully worn set activates every threshold" % set_id
		)


## The ceiling above has to be able to fail, or it is decoration. A tier one
## member wider than any body has must be reported unreachable, one exactly as
## wide must not be, and declaring more members must never quietly raise the
## ceiling — because that is exactly the edit that made a six-member tier on a
## five-slot body look fine.
func test_the_reachability_ceiling_follows_the_equipment_slots_and_nothing_else() -> void:
	var slots := Equipment.SLOTS.size()
	var overwide := _probe(slots + 3, [slots + 1])
	assert_eq(overwide.member_count(), slots + 3, "the probe declares more members than slots")
	assert_eq(
		overwide.max_equippable(), slots, "the ceiling is the slot list, not the member count"
	)
	assert_eq(overwide.unreachable_tier_indices(), [0], "one member wider than a body is dead")

	var exact := _probe(slots + 3, [slots])
	assert_eq(exact.unreachable_tier_indices(), [], "exactly as wide as the slots is reachable")

	var widest := _probe(slots * 4, [slots + 1])
	assert_eq(
		widest.max_equippable(), slots, "members beyond the slot count do not raise the ceiling"
	)
	assert_eq(widest.unreachable_tier_indices(), [0], "still unreachable with far more members")

	var narrow := _probe(2, [2])
	assert_eq(narrow.max_equippable(), 2, "a set narrower than a body is capped by its own members")
	assert_eq(narrow.unreachable_tier_indices(), [], "and every one of its tiers is reachable")


## Reachability asserted by equipping, not by arithmetic. Every shipped set is put
## on a real actor, in real slots, routed the way the shipped subtype-to-slot rule
## routes it, and each threshold's contribution is checked on the stat stack — so
## "reachable" means the module handed the player the bonus. A set authored wider
## than a body (the void coil has six members and five slots) is worn to its
## ceiling, never to its headcount.
func test_every_authored_tier_is_earned_by_actually_wearing_a_full_set() -> void:
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		var ceiling := set_def.max_equippable()
		var top := set_def.tiers.size() - 1
		assert_ne(top, -1, "%s has a capstone to reach" % set_id)
		var actor := _wearing(set_id, ceiling)
		var live: Dictionary = (SetBonusApi.state(actor).get("sets", {}) as Dictionary).get(
			String(set_id), {}
		)
		assert_eq(
			int(live.get("distinct", 0)),
			ceiling,
			"%s: %d distinct members worn at once" % [set_id, ceiling]
		)
		assert_eq(
			(live.get("slots", {}) as Dictionary).size(),
			ceiling,
			"%s: each worn member records its own slot" % set_id
		)
		assert_eq(
			(live.get("active_tiers", []) as Array).size(),
			set_def.tiers.size(),
			"%s: a full set activates every threshold" % set_id
		)
		for index in set_def.tiers.size():
			assert_eq(
				_has_source(actor, String(SetBonusState.tier_source(set_id, index))),
				true,
				"%s: tier %d applied its bonus" % [set_id, index]
			)
		var view: Dictionary = SetBonusApi.inspect(actor)["sets"][String(set_id)]
		assert_eq(bool(view["complete"]), true, "%s: a full set reads as complete" % set_id)
		assert_eq(
			int(view["equippable_count"]),
			ceiling,
			"%s: the reported ceiling is the slot list" % set_id
		)
		assert_eq(
			bool((view["thresholds"] as Array)[top]["active"]),
			true,
			"%s: the capstone threshold is active" % set_id
		)


func _has_source(actor: Actor, source: String) -> bool:
	for modifier in actor.stats._modifiers:
		if String(modifier.source) == source:
			return true
	return false


## An actor wearing as many distinct members of one set as any body can hold.
## Members are placed by their own subtype, exactly as the shipped routing does,
## and the unique goes first so a full set never depends on which member happens
## to appear in a loot table. Members whose subtype needs a slot already taken by
## a stronger member are skipped rather than double-parked, which is what keeps
## the void coil's two weapon members a real choice instead of a free extra.
func _wearing(set_id: StringName, count: int) -> Actor:
	var actor := Actor.new(&"full_set", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	ItemsApi.attach(actor, 64)
	SetBonusApi.attach(actor)
	var set_def := SetBonusApi.set_definition(set_id)
	# Unique first, then pieces in declaration order: a deterministic pick the
	# headless runner can rely on.
	var ordered: Array[StringName] = []
	ordered.append_array(set_def.uniques)
	ordered.append_array(set_def.pieces)
	var taken: Array[StringName] = []
	for member_id in ordered:
		if taken.size() >= count:
			break
		var def := SetBonusApi.definition(member_id)
		if def == null:
			continue
		var subtype := StringName(def.subcategory)
		var slot: StringName = SUBTYPE_SLOT.get(subtype, &"")
		if slot == &"":
			slot = _free_accessory(taken)
		if taken.has(slot):
			continue
		ItemsApi.inventory(actor).add(def, 1)
		assert_eq(
			ItemsApi.equip_item(actor, slot, def),
			true,
			"%s: wore %s (%s) in %s" % [set_id, member_id, subtype, slot]
		)
		taken.append(slot)
	assert_eq(taken.size(), count, "%s: filled %d slots" % [set_id, count])
	return actor


func _free_accessory(taken: Array[StringName]) -> StringName:
	for slot in ACCESSORY_SLOTS:
		if not taken.has(slot):
			return slot
	return ACCESSORY_SLOTS[0]


## A bare set definition for probing the ceiling, with no catalog load behind it.
## `counts` are the tier widths to author; every probe tier grants one option so
## only the width is under test.
func _probe(members: int, counts: Array) -> SetDef:
	var set_def := SetDef.new()
	set_def.id = &"probe"
	for index in members:
		set_def.pieces.append(StringName("probe_member_%d" % index))
	for count in counts:
		(
			set_def
			. tiers
			. append(
				{
					"count": int(count),
					"label": "Probe",
					"options": [{"option_id": &"core_defense_physical", "value": 5.0}],
				}
			)
		)
	return set_def
