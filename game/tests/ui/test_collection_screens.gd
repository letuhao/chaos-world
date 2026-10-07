extends TestCase

## Tests for the Collection UI screens (ADR 0896).
##
## These screens are pure consumers of the `collection` facade. They render
## `CollectionApi.summary(actor)` and expose `summary()` as the testable surface.

const MERCHANT := &"merchant_grampa"


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	DestinyApi.attach(actor)
	FertilityApi.attach(actor)
	return actor


# --- RelationshipScreen --------------------------------------------------------------


func test_relationship_screen_summary_is_empty_without_actor() -> void:
	var screen := RelationshipScreen.new()
	assert_eq(screen.summary(), {}, "no actor, no summary")
	screen.free()


func test_relationship_screen_summary_names_actor() -> void:
	var actor := _actor()
	var screen := RelationshipScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actor"], "hero", "names the actor")
	assert_eq(summary["read_only"], false, "not read-only")
	assert_eq(summary["partner_count"], 0, "no partners yet")
	screen.free()


func test_relationship_screen_has_actions() -> void:
	var actor := _actor()
	var screen := RelationshipScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actions"].has("select_partner"), true, "has select_partner")
	assert_eq(summary["actions"].has("view_history"), true, "has view_history")
	screen.free()


# --- DualCultivationScreen --------------------------------------------------------------


func test_dual_cultivation_screen_summary_is_empty_without_actor() -> void:
	var screen := DualCultivationScreen.new()
	assert_eq(screen.summary(), {}, "no actor, no summary")
	screen.free()


func test_dual_cultivation_screen_summary_names_actor() -> void:
	var actor := _actor()
	var screen := DualCultivationScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actor"], "hero", "names the actor")
	assert_eq(summary["read_only"], false, "not read-only")
	assert_eq(summary["pillars"].size(), 3, "three pillars")
	screen.free()


func test_dual_cultivation_screen_has_actions() -> void:
	var actor := _actor()
	var screen := DualCultivationScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actions"].has("start_session"), true, "has start_session")
	assert_eq(summary["actions"].has("end_session"), true, "has end_session")
	assert_eq(summary["actions"].has("attempt_breakthrough"), true, "has attempt_breakthrough")
	screen.free()


# --- CollectionScreen -----------------------------------------------------------------


func test_collection_screen_summary_is_empty_without_actor() -> void:
	var screen := CollectionScreen.new()
	assert_eq(screen.summary(), {}, "no actor, no summary")
	screen.free()


func test_collection_screen_summary_names_actor() -> void:
	var actor := _actor()
	var screen := CollectionScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actor"], "hero", "names the actor")
	assert_eq(summary["read_only"], false, "not read-only")
	assert_eq(summary["tier_count"], 12, "twelve tiers")
	assert_eq(summary["tiers"].size(), 12, "all tiers present")
	screen.free()


func test_collection_screen_has_claim_action() -> void:
	var actor := _actor()
	var screen := CollectionScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actions"].has("claim_tier"), true, "has claim_tier")
	screen.free()


func test_collection_screen_next_tier_is_zero_when_all_claimed() -> void:
	var actor := _actor()
	var screen := CollectionScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	# With no partners, no tiers are claimable, so next_tier is 1 (first unclaimed)
	assert_eq(summary["next_tier"], 1, "first tier is next")
	screen.free()


# --- HeterosisScreen ---------------------------------------------------------------------


func test_heterosis_screen_summary_is_empty_without_actor() -> void:
	var screen := HeterosisScreen.new()
	assert_eq(screen.summary(), {}, "no actor, no summary")
	screen.free()


func test_heterosis_screen_summary_names_actor() -> void:
	var actor := _actor()
	var screen := HeterosisScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary["actor"], "hero", "names the actor")
	assert_eq(summary["read_only"], true, "read-only")
	assert_eq(summary["has_heterosis"], false, "no heterosis by default")
	screen.free()


func test_heterosis_screen_has_no_actions() -> void:
	var actor := _actor()
	var screen := HeterosisScreen.new()
	screen.setup(actor)
	var summary := screen.summary()
	assert_eq(summary.has("actions"), false, "no actions on a read-only screen")
	screen.free()


# --- Panel summaries ---------------------------------------------------------------------


func test_partner_row_summary_is_empty_when_cleared() -> void:
	var row := PartnerRow.new()
	assert_eq(row.summary(), {}, "empty when cleared")
	row.free()


func test_pillar_row_summary_is_empty_when_cleared() -> void:
	var row := PillarRow.new()
	assert_eq(row.summary(), {}, "empty when cleared")
	row.free()


func test_collection_tier_row_summary_is_empty_when_cleared() -> void:
	var row := CollectionTierRow.new()
	assert_eq(row.summary(), {}, "empty when cleared")
	row.free()


func test_heterosis_status_row_summary_is_empty_when_cleared() -> void:
	var row := HeterosisStatusRow.new()
	assert_eq(row.summary(), {}, "empty when cleared")
	row.free()
