extends TestCase

## ADR 0002: traits and techniques are data resources, not code.


func test_trait_def_modifies_derived_stat() -> void:
	var trait_def := TraitDef.new()
	trait_def.id = &"succubus"
	trait_def.percent_modifiers = {String(DualCultivationApi.CHARM): 0.5}
	var actor := Actor.new(&"hero", {DualCultivationApi.CHARM: 10.0})
	trait_def.apply(actor)
	assert_almost_eq(actor.stats.derived(DualCultivationApi.CHARM), 15.0, "percent trait")
	assert_eq(actor.traits.has(&"succubus"), true, "trait recorded")
	trait_def.remove(actor)
	assert_almost_eq(actor.stats.derived(DualCultivationApi.CHARM), 10.0, "trait removed")


func test_dual_technique_def_is_data() -> void:
	var technique := DualTechniqueDef.new()
	technique.id = &"yin_yang_exchange"
	technique.essence_cost = 25.0
	assert_eq(technique.id, &"yin_yang_exchange", "technique id")
	assert_almost_eq(technique.essence_cost, 25.0, "technique cost")
