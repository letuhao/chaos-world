extends TestCase

## ADR 0021: AscensionProvider tests.


func test_provider_returns_empty_without_ascension() -> void:
	var actor := Actor.new(&"hero")
	actor.stats.add_provider(AscensionProvider.new())
	assert_eq(actor.stats.derived(&"ascension_stage"), 0.0, "no ascension = 0")
	assert_eq(actor.stats.derived(&"ascension_dao_level"), 0.0, "no ascension = 0")
	assert_eq(actor.stats.derived(&"ascension_comprehension"), 0.0, "no ascension = 0")
	assert_eq(actor.stats.derived(&"ascension_complete"), 0.0, "no ascension = 0")


func test_provider_contributes_stats() -> void:
	var actor := Actor.new(&"hero")
	var ascension := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"fire", 3, 50.0)
	actor.ascension = ascension
	actor.stats.add_provider(AscensionProvider.new())
	assert_eq(actor.stats.derived(&"ascension_stage"), 2.0, "stage contributed")
	assert_eq(actor.stats.derived(&"ascension_dao_level"), 3.0, "dao_level contributed")
	assert_eq(actor.stats.derived(&"ascension_comprehension"), 50.0, "comprehension contributed")
	assert_eq(actor.stats.derived(&"ascension_complete"), 0.0, "not complete")


func test_provider_complete_ascension() -> void:
	var actor := Actor.new(&"hero")
	var ascension := AscensionState.new(AscensionState.STAGE_TRANSCENDENCE, &"sword", 5, 100.0)
	actor.ascension = ascension
	actor.stats.add_provider(AscensionProvider.new())
	assert_eq(actor.stats.derived(&"ascension_stage"), 3.0, "stage contributed")
	assert_eq(actor.stats.derived(&"ascension_dao_level"), 5.0, "dao_level contributed")
	assert_eq(actor.stats.derived(&"ascension_complete"), 1.0, "complete")


func test_provider_reflects_ascension_changes() -> void:
	var actor := Actor.new(&"hero")
	var ascension := AscensionState.new()
	actor.ascension = ascension
	actor.stats.add_provider(AscensionProvider.new())
	assert_eq(actor.stats.derived(&"ascension_stage"), 1.0, "initial stage")
	ascension.advance_stage()
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"ascension_stage"), 2.0, "stage updated")
	ascension.improve_dao(2)
	actor.mark_stats_dirty()
	assert_eq(actor.stats.derived(&"ascension_dao_level"), 3.0, "dao_level updated")
