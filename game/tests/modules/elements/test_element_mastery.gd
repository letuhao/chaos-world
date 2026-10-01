extends TestCase

## ADR 0004: elemental mastery is a cultivation path that gates element tiers.


func test_path_def_ranks() -> void:
	var def := ElementMastery.path_def()
	assert_eq(def.id, ElementMastery.PATH_ID, "path id")
	assert_eq(def.ranks.size(), 6, "six ranks")
	assert_eq(def.ranks[0], &"awakened", "first rank")
	assert_eq(def.ranks[5], &"sovereign", "last rank")


func test_tier_gating() -> void:
	assert_eq(ElementMastery.max_tier(&"awakened"), 1, "awakened tier 1")
	assert_eq(ElementMastery.max_tier(&"adept"), 2, "adept tier 2")
	assert_eq(ElementMastery.max_tier(&"sovereign"), 3, "sovereign tier 3")
	assert_eq(ElementMastery.max_tier(&"unknown"), 1, "unknown defaults to tier 1")
