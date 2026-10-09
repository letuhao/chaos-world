extends TestCase

## BL-0951 / ADR 0939: the foundation wall on the mind path.
##
## An actor standing at a realm without the history a real climb snapshots is REFUSED by
## name in the same preview a player reads; the history such a climb must have had clears
## the same wall. The mind's measure is channel refinement toward the realm's authored cap.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


## An actor at `rank_id` with NO foundation history — the state a fixture can hold and a
## player cannot, which is exactly what a synthetic wall test needs.
func _unhistorical(rank_id: StringName) -> Actor:
	var actor := Actor.new(
		&"wall_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 0.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	return actor


func test_an_actor_without_history_is_refused_by_name() -> void:
	var actor := _unhistorical(&"core_formation")
	var preview := MindAdvancement.preview(actor)
	assert_eq(
		(preview.get("conditions", []) as Array).has("foundation_insufficient"),
		true,
		"the wall is reported by name before it is hit"
	)


func test_the_implied_history_clears_the_wall() -> void:
	var actor := Probe.fresh_actor(&"core_formation")
	var preview := MindAdvancement.preview(actor)
	assert_eq(
		(preview.get("conditions", []) as Array).has("foundation_insufficient"),
		false,
		"a climbed mind clears the authored floor"
	)
