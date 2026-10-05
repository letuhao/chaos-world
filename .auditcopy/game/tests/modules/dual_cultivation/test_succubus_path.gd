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


## Every realm-scaled contribution is priced by the ONE shared rate,
## `RealmRate.factor` — the same call the other three providers make. It used to be
## a private `1.0 + ladder_ordinal * 0.05` in the provider: a fourth rate curve with
## no ADR and no bound, whose `60.0` and `18.0` literals are what these two tests
## used to assert.
##
## Deriving from `RealmRate` is what makes a change land as a failure, and it keeps
## the expectations true across a legitimate `RATE_STEP` retune.
func test_stats_scale_with_ladder_rank() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 40.0, "no path")
	actor.set_path(PathState.new(SuccubusPath.PATH_ID, &"qi_refining"))
	# R1 is the ladder's first ordinal, so the factor is neutral.
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 40.0, "rank 0")
	actor.path(SuccubusPath.PATH_ID).rank_id = &"spirit_sea"
	var rate := RealmRate.factor(&"spirit_sea")
	var rank_10: float = actor.stats.derived(DualCultivationStats.ALLURE)
	assert_almost_eq(rank_10, 40.0 * rate, "rank 10 scales")
	# the point of the test: a higher rank must actually scale harder
	assert_eq(rank_10 > 40.0, true, "rank 10 outranks rank 0")


## `SUCCUBUS_DOMINION` reports the realm rate the succubus rank resolves to, not a
## bare ladder ordinal — an ordinal published as a derived stat put an array
## position where a caller reads a value, and `PathState.rank_id` already carries
## it. So this is the same number the provider multiplies its contributions by.
func test_dominion_is_the_shared_rate_for_the_rank() -> void:
	var actor := _actor_with_module()
	actor.set_path(PathState.new(SuccubusPath.PATH_ID, &"earth_immortal"))
	var rate := RealmRate.factor(&"earth_immortal")
	assert_almost_eq(actor.stats.derived(DualCultivationStats.SUCCUBUS_DOMINION), rate, "dominion")


## A rate is a gain and never a magnitude, so the whole ladder is under 2x. The
## private curve this replaced reached 2.45x at R30 and nothing bounded it.
func test_the_rate_stays_a_gain_across_the_whole_ladder() -> void:
	var realms := RealmDefaults.ladder().realms()
	var last := realms[realms.size() - 1].id
	var actor := _actor_with_module()
	actor.set_path(PathState.new(SuccubusPath.PATH_ID, last))
	var dominion: float = actor.stats.derived(DualCultivationStats.SUCCUBUS_DOMINION)
	assert_eq(dominion < 2.0, true, "R30 dominion is under 2x, not a magnitude (%s)" % dominion)
	assert_eq(dominion > 1.0, true, "and it still rises, or the path stops paying")
