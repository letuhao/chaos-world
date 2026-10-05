extends TestCase

## ADR 0025: core resource pools follow the derived capacities, and raising a
## capacity must never refill the pool (an equip/unequip refill exploit).


func _hero() -> Actor:
	return ActorFactory.build(&"hero", {Stat.PHYSIQUE: 10.0, Stat.AGILITY: 5.0})


func test_core_pools_are_created_and_sized_from_derived_stats() -> void:
	var actor := _hero()
	var health := actor.resource(&"health")
	assert_ne(health, null, "health pool exists")
	assert_ne(actor.resource(&"stamina"), null, "stamina pool exists")
	assert_almost_eq(
		health.maximum, actor.stats.derived(Stat.MAX_HEALTH), "health sized from the stat"
	)
	assert_almost_eq(
		health.regen, actor.stats.derived(Stat.HEALTH_REGEN), "regen sized from the stat"
	)


func test_raising_capacity_does_not_refill() -> void:
	var actor := _hero()
	var health := actor.resource(&"health")
	health.change(-40.0)
	var before := health.current
	actor.stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, 500.0, &"test"))
	actor.mark_stats_dirty()
	assert_eq(health.current == before, true, "extra capacity does not heal")
	assert_eq(health.current > health.maximum, false, "current stays within the new maximum")


func test_lowering_capacity_clamps_current_to_the_new_maximum() -> void:
	var actor := _hero()
	var health := actor.resource(&"health")
	var full := health.maximum
	assert_almost_eq(health.current, full, "a fresh actor starts full")
	actor.stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, -full + 10.0, &"test"))
	actor.mark_stats_dirty()
	assert_almost_eq(health.maximum, 10.0, "capacity reduced")
	assert_almost_eq(health.current, 10.0, "current clamped down")


func test_repeated_recomposition_does_not_drift() -> void:
	var actor := _hero()
	var health := actor.resource(&"health")
	var maximum := health.maximum
	var regen := health.regen
	for _i in 40:
		actor.mark_stats_dirty()
	assert_almost_eq(health.maximum, maximum, "maximum stable")
	assert_almost_eq(health.regen, regen, "regen stable")
	assert_eq(health.maximum == health.current, true, "a full actor stays full, no accumulation")


func test_resource_pool_survives_a_save_round_trip() -> void:
	var actor := _hero()
	actor.resource(&"health").change(-25.0)
	var payload := actor.to_dict()
	var restored := Actor.from_dict(payload)
	assert_ne(restored.resource(&"health"), null, "pool restored")
	assert_almost_eq(
		restored.resource(&"health").current, actor.resource(&"health").current, "value"
	)
	assert_almost_eq(
		restored.resource(&"health").maximum, actor.resource(&"health").maximum, "maximum"
	)
