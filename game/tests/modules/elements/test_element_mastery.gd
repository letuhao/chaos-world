extends TestCase

## ADR 0004/0005: elemental mastery advances on the shared ladder and gates tiers.


func test_path_def() -> void:
	var def := ElementMastery.path_def()
	assert_eq(def.id, ElementMastery.PATH_ID, "path id")
	assert_eq(def.has_rank(&"qi_refining"), true, "uses shared ladder")


func test_tier_gating_from_realm_tier() -> void:
	assert_eq(ElementMastery.max_tier(&"qi_refining"), 1, "mortal gates tier 1")
	assert_eq(ElementMastery.max_tier(&"spirit_sea"), 2, "spirit gates tier 2")
	assert_eq(ElementMastery.max_tier(&"earth_immortal"), 3, "immortal gates tier 3")
	assert_eq(ElementMastery.max_tier(&"dao_ancestor"), 3, "transcendent capped at tier 3")
	assert_eq(ElementMastery.max_tier(&"unknown"), 1, "unknown defaults to tier 1")
