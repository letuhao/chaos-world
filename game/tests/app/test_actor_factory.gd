extends TestCase

## ADR 0002: the composition root (app/) registers module providers with actors.


func test_dual_cultivation_registration() -> void:
	var actor := ActorFactory.with_dual_cultivation(
		Actor.new(&"hero", {DualCultivationApi.CHARM: 10.0})
	)
	assert_eq(actor.stats.provider_count(), 1, "provider registered")
	assert_almost_eq(actor.stats.derived(DualCultivationStats.ALLURE), 20.0, "module stat live")


func test_fertility_registration() -> void:
	var actor := ActorFactory.with_fertility(
		Actor.new(&"mother", {DualCultivationApi.FERTILITY: 10.0})
	)
	assert_eq(actor.stats.provider_count(), 1, "provider registered")
