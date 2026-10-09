extends TestCase

## BL-0951 / ADR 0939, S14: the karmic-memory floor on the record.
##
## The floor is a FLOOR, not an addition: a re-embodied soul starts a little above nothing,
## and a body whose own past already exceeds the floor is unchanged. Both directions are
## asserted, because "raises the starting foundation" and "never inflates a good record" are
## the two halves of the same rule.
##
## Every loop is a bounded `for`; there is no `while`.


func _hero() -> Actor:
	return Actor.new(&"karmic_hero", {Stat.PHYSIQUE: 10.0})


func test_the_floor_raises_a_fresh_bodys_starting_foundation() -> void:
	var actor := _hero()
	assert_almost_eq(FoundationApi.foundation(actor), 0.0, "a fresh body starts at nothing")
	var seeded := FoundationApi.seed_karmic(actor, 0.1)
	assert_eq(bool(seeded.get("ok", false)), true, "the floor seeds")
	assert_almost_eq(FoundationApi.karmic(actor), 0.1, "and is read back")
	assert_almost_eq(FoundationApi.foundation(actor), 0.1, "so the starting foundation is raised")


func test_the_floor_is_a_floor_not_an_addition() -> void:
	var actor := _hero()
	FoundationApi.snapshot(actor, &"qi_refining", 0.4)
	FoundationApi.seed_karmic(actor, 0.1)
	assert_almost_eq(
		FoundationApi.foundation(actor), 0.4, "a past above the floor is left unchanged"
	)


func test_the_floor_lifts_a_past_below_it() -> void:
	var actor := _hero()
	FoundationApi.snapshot(actor, &"qi_refining", 0.05)
	FoundationApi.seed_karmic(actor, 0.2)
	assert_almost_eq(FoundationApi.foundation(actor), 0.2, "a past below the floor is lifted to it")


func test_the_floor_round_trips_a_save() -> void:
	var actor := _hero()
	FoundationApi.seed_karmic(actor, 0.15)
	var parsed: Variant = JSON.parse_string(
		JSON.stringify(actor.get_module_data(FoundationRecord.SLOT))
	)
	assert_eq(parsed is Dictionary, true, "the record stays JSON-clean with a floor in it")
	var restored := Actor.from_dict(actor.to_dict())
	assert_almost_eq(FoundationApi.karmic(restored), 0.15, "the floor survives a save")


## A non-positive floor is refused by name: there is nothing to seed, and a silent no-op
## would read as a raise.
func test_a_non_positive_floor_is_refused() -> void:
	var actor := _hero()
	assert_eq(
		String(FoundationApi.seed_karmic(actor, 0.0).get("reason", "")),
		FoundationApi.R_BAD_AMOUNT,
		"nothing to seed"
	)
	assert_eq(
		String(FoundationApi.seed_karmic(null, 0.1).get("reason", "")),
		FoundationApi.R_NO_ACTOR,
		"a null actor is named"
	)
	assert_almost_eq(FoundationApi.karmic(actor), 0.0, "and a refusal seeds nothing")


## The floor never touches the SNAPSHOT map: it is a separate field, so a reader that walks
## the snapshots (`mend_target`, a path's gate arithmetic) cannot mistake it for a realm.
func test_the_floor_is_not_a_snapshot() -> void:
	var actor := _hero()
	FoundationApi.seed_karmic(actor, 0.2)
	assert_eq(
		FoundationRecord.count(
			FoundationRecord.normalize(actor.get_module_data(FoundationRecord.SLOT))
		),
		0,
		"no realm was left, so the snapshot map is empty"
	)
	assert_eq(FoundationApi.mend_target(actor), &"", "and there is no scar to mend")
