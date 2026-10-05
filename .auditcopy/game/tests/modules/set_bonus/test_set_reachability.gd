extends TestCase

## Every authored set tier must be genuinely winnable, and "winnable" has to mean
## a real body wearing real items — not a number comparing correctly against
## another number.
##
## The bug this file exists for: `void_serpent_coil` shipped a `count: 6` tier
## while `Equipment.SLOTS` has five entries, so no body could ever reach it. The
## old guard asserted `needed <= member_count()` and `active_tier_indices(
## member_count())`, both pure arithmetic over the set's own declarations, so it
## reported that dead tier as reachable. A second, quieter version of the same
## hole survived that fix: `min(member_count(), Equipment.SLOTS.size())` is a
## COUNT, and a count cannot see that two artifacts contend for one artifact slot.
## A five-member set with two artifacts has a ceiling of four, and a `count: 5`
## tier on it is dead content the count calls reachable.
##
## The ceiling is therefore a placement ([SetPlacement]), computed by the catalog
## from the same authored subtype ruling the equip path enforces, and every tier
## is then checked by actually wearing a set to that ceiling and reading the
## contribution off the stat stack.


func _catalog() -> SetCatalog:
	return SetCatalog.instance()


func _set_ids() -> Array[StringName]:
	return SetBonusApi.sets()


## The shipped ladder is winnable end to end. Both halves of the gate, asserted
## separately because they fail independently: every threshold is at or under what
## a body can place (satisfiable), and no threshold is trivially met by one member
## (non-trivial).
func test_every_authored_threshold_is_actually_reachable_with_the_declared_members() -> void:
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		var ceiling := _catalog().max_wearable(set_id)
		assert_eq(
			ceiling,
			_set_placed(set_id),
			"%s: the ceiling is the number of members a body can really place" % set_id
		)
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
						"%s tier %d (%s) needs %d distinct members, but only %d can ever be worn: "
						+ "%d declared members across %d equipment slots"
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
		assert_eq(
			_catalog().unreachable_tier_indices(set_id), [], "%s: no authored tier is dead" % set_id
		)
		assert_eq(
			(set_def.active_tier_indices(ceiling) as Array).size(),
			set_def.tiers.size(),
			"%s: a fully worn set activates every threshold" % set_id
		)


## How many members the catalog's own placement put into slots.
func _set_placed(set_id: StringName) -> int:
	var total := 0
	for slot in _catalog().placement(set_id):
		if slot != &"":
			total += 1
	return total


## The ceiling has to be able to fail, or it is decoration. These are the member
## shapes a count cannot tell apart, handed to the same algorithm production uses:
##
##   - five placeable members across five slots is exactly winnable;
##   - five members where two contend for the one artifact slot is FOUR, and this
##     is the case `min(member_count(), slots)` calls five;
##   - three accessories do not fit two accessory slots;
##   - a member with no slot at all is never placed;
##   - declaring ever more members never raises the ceiling.
func test_the_ceiling_is_a_placement_and_not_a_count() -> void:
	var accessory := [&"accessory_a", &"accessory_b"]
	assert_eq(
		SetPlacement.placed_count([accessory, [&"armor"], [&"artifact"], [&"weapon"], accessory]),
		5,
		"five placeable members fill five slots"
	)
	assert_eq(
		SetPlacement.placed_count(
			[[&"artifact"], [&"artifact"], [&"armor"], [&"weapon"], accessory]
		),
		4,
		"two artifacts contend for one artifact slot, so the ceiling is four and not five"
	)
	assert_eq(
		SetPlacement.placed_count([accessory, accessory, accessory, [&"armor"], [&"weapon"]]),
		4,
		"three accessories do not fit two accessory slots"
	)
	assert_eq(
		SetPlacement.placed_count([[], [&"armor"], [&"artifact"], [&"weapon"], accessory]),
		4,
		"a member with no wearable slot is never placed"
	)
	assert_eq(
		(
			SetPlacement
			. placed_count(
				[
					[&"artifact"],
					[&"artifact"],
					[&"artifact"],
					[&"armor"],
					[&"weapon"],
					accessory,
					accessory,
				]
			)
		),
		5,
		"declaring far more members never raises the ceiling past the slots"
	)
	assert_eq(SetPlacement.placed_count([]), 0, "a set with no members places nothing")


## The assignment is constructive, not just a number: every slot it hands out is
## one the member's subtype actually permits, and no slot is handed out twice.
## This is what lets a caller wear a set to the ceiling instead of guessing.
func test_the_placement_hands_out_only_permitted_slots_and_never_one_twice() -> void:
	var accessory := [&"accessory_a", &"accessory_b"]
	var members := [[&"artifact"], [&"armor"], [&"weapon"], accessory, accessory]
	var placement := SetPlacement.assign(members)
	assert_eq(placement.size(), members.size(), "one answer per member")
	var seen: Dictionary = {}
	for index in members.size():
		var slot: StringName = placement[index]
		assert_ne(slot, &"", "member %d is placed" % index)
		assert_eq(
			(members[index] as Array).has(slot),
			true,
			"member %d occupies '%s', which its own slot options offer" % [index, slot]
		)
		assert_eq(seen.has(slot), false, "slot '%s' is handed out once" % slot)
		seen[slot] = true


## The same content answers the same way twice, so a tier's reachability is a
## property of the shipped content and not of a lucky run order.
func test_the_placement_is_deterministic_across_repeated_reads() -> void:
	for set_id in _set_ids():
		var first := _catalog().placement(set_id)
		var second := _catalog().placement(set_id)
		assert_eq(first, second, "%s: the same placement every time" % set_id)


## Reachability asserted by equipping, not by arithmetic. Every shipped set is put
## on a real actor, in real slots, routed by the SAME placement the ceiling is
## computed from, and each threshold's contribution is checked on the stat stack —
## so "reachable" means the module handed the player the bonus. A set authored
## wider than a body (the void coil has six members and five slots) is worn to its
## ceiling, never to its headcount.
func test_every_authored_tier_is_earned_by_actually_wearing_a_full_set() -> void:
	for set_id in _set_ids():
		var set_def := SetBonusApi.set_definition(set_id)
		var ceiling := _catalog().max_wearable(set_id)
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
			"%s: the reported ceiling is the placement" % set_id
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
##
## The arrangement is the catalog's own placement, never a second subtype-to-slot
## map written here. That map existed, and it is the reason the guard was weaker
## than it looked: it duplicated the rule, so a rule change and a test change were
## two edits instead of one, and a set routed only by the test's copy could pass
## while the shipped path refused. Now the only way to learn where a member goes
## is to ask the code that decides where a member goes.
func _wearing(set_id: StringName, count: int) -> Actor:
	var actor := Actor.new(&"full_set", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	ItemsApi.attach(actor, 64)
	SetBonusApi.attach(actor)
	var set_def := SetBonusApi.set_definition(set_id)
	var placement := _catalog().placement(set_id)
	var worn := 0
	for index in set_def.member_ids().size():
		if worn >= count:
			break
		var slot: StringName = placement[index]
		if slot == &"":
			continue
		var member_id := set_def.member_ids()[index]
		var def := SetBonusApi.definition(member_id)
		assert_ne(def, null, "%s: member %s resolves" % [set_id, member_id])
		ItemsApi.inventory(actor).add(def, 1)
		assert_eq(
			ItemsApi.equip_item(actor, slot, def),
			true,
			"%s: wore %s (%s) in %s" % [set_id, member_id, def.subcategory, slot]
		)
		worn += 1
	assert_eq(worn, count, "%s: filled %d slots" % [set_id, count])
	return actor
