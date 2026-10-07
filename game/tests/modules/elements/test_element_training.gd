extends TestCase

## ADR 0004's second half, made playable: `element_mastery_<e>` is writable, the races'
## affinities are the training set, the shared rate prices a sitting, and the provider
## turns the channel into the power the damage path reads — the end-to-end proof that
## practice moves the stat combat actually consumes.


func _actor(id: StringName = &"element_practice") -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	ElementsApi.attach(actor)
	return actor


func test_a_sitting_raises_mastery_by_the_shared_rate() -> void:
	var actor := _actor()
	actor.set_affinity(ElementStats.FIRE, 5.0)
	assert_eq(ElementsApi.can_practise(actor, ElementStats.FIRE), true, "a spark may practise")
	assert_eq(ElementsApi.practise(actor, ElementStats.FIRE), true, "the sitting lands")
	assert_almost_eq(
		ElementsApi.mastery_of(actor, ElementStats.FIRE),
		ElementsApi.PRACTICE_STEP * RealmRate.factor(&"qi_refining"),
		"the gain is the step priced by the shared rate at the first rung",
		1e-6
	)


func test_no_spark_no_sitting() -> void:
	var actor := _actor()
	assert_eq(ElementsApi.can_practise(actor, ElementStats.LIGHTNING), false, "no spark, no gate")
	assert_eq(ElementsApi.practise(actor, ElementStats.LIGHTNING), false, "and no gain")
	assert_almost_eq(
		ElementsApi.mastery_of(actor, ElementStats.LIGHTNING), 0.0, "nothing was written", 1e-9
	)


func test_an_unknown_element_is_refused() -> void:
	var actor := _actor()
	actor.set_affinity(&"no_such_element", 5.0)
	assert_eq(ElementsApi.can_practise(actor, &"no_such_element"), false, "not in the rules")
	assert_eq(ElementsApi.practise(actor, &"no_such_element"), false, "so no sitting")


func test_the_elemental_paths_own_rank_prices_the_sitting() -> void:
	var low := _actor(&"element_low")
	low.set_affinity(ElementStats.FIRE, 5.0)
	var high := _actor(&"element_high")
	high.set_affinity(ElementStats.FIRE, 5.0)
	high.set_path(PathState.new(ElementMastery.PATH_ID, &"spirit_sea"))
	assert_eq(ElementsApi.practise(low, ElementStats.FIRE), true, "the first sits")
	assert_eq(ElementsApi.practise(high, ElementStats.FIRE), true, "the second sits")
	assert_eq(
		(
			ElementsApi.mastery_of(high, ElementStats.FIRE)
			> ElementsApi.mastery_of(low, ElementStats.FIRE)
		),
		true,
		"the elemental path's own rank prices its own sittings"
	)


func test_mastery_reaches_the_power_the_damage_path_reads() -> void:
	var actor := _actor()
	actor.set_affinity(ElementStats.FIRE, 10.0)
	var before := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_eq(ElementsApi.practise(actor, ElementStats.FIRE), true, "one sitting")
	var after := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_eq(after > before, true, "and the power the damage path reads rose")


func test_a_rare_resource_opens_an_element_the_race_never_gave() -> void:
	var actor := _actor()
	assert_eq(ElementsApi.can_practise(actor, ElementStats.LIGHTNING), false, "no lightning spark")
	assert_eq(ElementsApi.awaken(actor, ElementStats.LIGHTNING, 3.0), true, "the resource opens it")
	assert_eq(ElementsApi.can_practise(actor, ElementStats.LIGHTNING), true, "the spark is real")
	assert_eq(ElementsApi.practise(actor, ElementStats.LIGHTNING), true, "and it trains")
	assert_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.LIGHTNING)) > 0.0,
		true,
		"with affinity and mastery both real, the power channel is live"
	)
