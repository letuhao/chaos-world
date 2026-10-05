extends TestCase

## ADR 0002: the dual_cultivation module contributes its stats through a StatProvider.


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


func test_attach_adds_resources() -> void:
	var actor := _actor_with_module()
	assert_eq(actor.resource(DualCultivationStats.CORRUPTION) != null, true, "corruption pool")
	assert_eq(actor.resource(DualCultivationStats.ESSENCE) != null, true, "essence pool")


func test_allure_scales_with_charm() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 40.0, "allure")


func test_essence_capacity_and_pool() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ESSENCE_CAPACITY), 120.0, "capacity")
	assert_almost_eq(actor.resource(DualCultivationStats.ESSENCE).maximum, 120.0, "pool max")


func test_purity_falls_with_corruption() -> void:
	var actor := _actor_with_module()
	assert_almost_eq(actor.stats.derived(DualCultivationStats.PURITY), 1.0, "start pure")
	actor.change_resource(DualCultivationStats.CORRUPTION, 100.0)
	assert_almost_eq(actor.stats.derived(DualCultivationStats.PURITY), 0.0, "full corruption")


func test_yin_yang_balance_is_pure_yang() -> void:
	var actor := _actor_with_module()
	actor.change_resource(DualCultivationStats.YANG, 100.0)
	assert_almost_eq(actor.stats.derived(DualCultivationStats.YIN_YANG_BALANCE), 1.0, "pure yang")
