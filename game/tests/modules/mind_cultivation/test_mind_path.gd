extends TestCase

## ADR 0013: mind cultivation is a cultivation system with a shared ladder
## and its own 30-stage vocabulary.


func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
				MindStats.MENTAL_CLARITY: 15.0,
			}
		)
	)
	MindCultivationApi.attach(actor)
	return actor


func test_path_vocabulary() -> void:
	var def := MindCultivationApi.path_def()
	assert_eq(def.id, MindPath.PATH_ID, "path id")
	assert_eq(def.stage_names.size(), 30, "30 stages")
	assert_eq(def.stage_name(&"qi_refining"), "Mind Awakening", "first stage")
	assert_eq(def.stage_name(&"spirit_sea"), "Introspection", "spirit stage")
	assert_eq(def.stage_name(&"dao_ancestor"), "Mind Dao Ancestor", "transcendent stage")


## Mind's mental output is scaled by one bounded per-realm RATE. Both
## expectations below are derived from the code under test rather than pinned to
## literals that a retune of the step would strand.
func _rate(rank_id: StringName) -> float:
	return MindRealmProfile.factor(rank_id)


func test_stats_scale_with_ladder_rank() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(MindStats.MENTAL_ATTACK), 62.5, "no path")
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	assert_almost_eq(actor.stats.derived(MindStats.MENTAL_ATTACK), 62.5, "rank 0")
	actor.path(MindPath.PATH_ID).rank_id = &"spirit_sea"
	var expected := 62.5 * _rate(&"spirit_sea")
	assert_almost_eq(
		actor.stats.derived(MindStats.MENTAL_ATTACK), expected, "rank 10 scales", 0.0001
	)


func test_spiritual_sense_range_from_rank() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(MindPath.PATH_ID, &"earth_immortal"))
	# 50.0 + 20 * 5.0 + rate * 10.0
	var expected := 150.0 + _rate(&"earth_immortal") * 10.0
	assert_almost_eq(
		actor.stats.derived(MindStats.SPIRITUAL_SENSE_RANGE), expected, "sense range", 0.0001
	)
