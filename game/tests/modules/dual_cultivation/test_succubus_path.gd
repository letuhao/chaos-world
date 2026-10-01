extends TestCase

## Succubus is a cultivation system: shared ladder + its own 30-stage vocabulary,
## and its stats scale with ladder rank (ADR 0005/0006).


func _actor_with_module() -> Actor:
	var actor := (
		Actor
		. new(
			&"succubus",
			{
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				Stat.WILL: 10.0,
				DualCultivationStats.CHARM: 20.0,
			}
		)
	)
	DualCultivationApi.attach(actor)
	return actor


func test_path_vocabulary() -> void:
	var def := DualCultivationApi.succubus_path()
	assert_eq(def.id, SuccubusPath.PATH_ID, "path id")
	assert_eq(def.stage_names.size(), 30, "30 stages")
	assert_eq(def.stage_name(&"qi_refining"), "Flicker", "first stage")
	assert_eq(def.stage_name(&"spirit_sea"), "Dreamweaver", "spirit stage")
	assert_eq(def.stage_name(&"dao_ancestor"), "Desire Dao Ancestor", "transcendent stage")


func test_stats_scale_with_ladder_rank() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 40.0, "no path")
	actor.set_path(PathState.new(SuccubusPath.PATH_ID, &"qi_refining"))
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 40.0, "rank 0")
	actor.path(SuccubusPath.PATH_ID).rank_id = &"spirit_sea"
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 60.0, "rank 10 scales")


func test_dominion_from_rank() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(SuccubusPath.PATH_ID, &"earth_immortal"))
	assert_almost_eq(actor.stats.derived(DualCultivationStats.SUCCUBUS_DOMINION), 18.0, "dominion")
