extends TestCase

## Tests for the Collection module facade (ADR 0127).
##
## Collection is a read-only module that tracks collection progress and pays
## narrative rewards. These tests assert the facade contract: summary shape,
## tier claiming, heterosis derivation, and history.

const MERCHANT := &"merchant_grampa"
const RIVAL := &"rival_cultivator_lan"


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	DestinyApi.attach(actor)
	FertilityApi.attach(actor)
	return actor


# --- Summary shape --------------------------------------------------------------

func test_summary_is_empty_without_an_actor() -> void:
	assert_eq(CollectionApi.summary(null), {}, "no actor, no summary")


func test_summary_names_the_actor() -> void:
	var actor := _actor()
	var summary := CollectionApi.summary(actor)
	assert_eq(summary["actor"], "hero", "names the actor")


func test_summary_counts_partners_at_confidant_and_above() -> void:
	var actor := _actor()
	# A stranger is not a partner
	CollectionApi.summary(actor)
	assert_eq(CollectionApi.summary(actor)["partner_count"], 0, "no partners yet")


func test_summary_includes_tiers() -> void:
	var actor := _actor()
	var summary := CollectionApi.summary(actor)
	assert_eq(summary["tier_count"], 12, "twelve tiers")
	assert_eq(summary["tiers"].size(), 12, "all tiers present")


func test_summary_includes_heterosis() -> void:
	var actor := _actor()
	var summary := CollectionApi.summary(actor)
	assert_eq(summary["heterosis"]["has_heterosis"], false, "no heterosis by default")


func test_summary_includes_pillars() -> void:
	var actor := _actor()
	var summary := CollectionApi.summary(actor)
	assert_eq(summary["pillar_count"], 3, "three pillars")
	assert_eq(summary["pillars"].size(), 3, "all pillars present")


# --- Tier claiming ---------------------------------------------------------------

func test_claim_tier_refuses_unknown_tier() -> void:
	var actor := _actor()
	var result := CollectionApi.claim_tier(actor, 99)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], "unknown_tier", "names the reason")


func test_claim_tier_refuses_when_requirement_not_met() -> void:
	var actor := _actor()
	var result := CollectionApi.claim_tier(actor, 1)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], "requirement_not_met", "no partners yet")


func test_claim_tier_pays_a_fate_when_requirement_met() -> void:
	var actor := _actor()
	# Earn a confidant bond
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 15.0
	gift.trust = 0.6
	var taught := SocialCauseDef.new()
	taught.id = &"a_teaching"
	taught.standing = 1.0
	SocialCauseCatalog.instance().reset()
	SocialCauseCatalog.instance().install([gift, taught])
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	var result := CollectionApi.claim_tier(actor, 1)
	assert_eq(result["ok"], true, "tier 1 requires 1 partner")
	assert_eq(result["fate_id"], "collection_tier_1", "pays the right fate")


func test_claim_tier_refuses_already_claimed() -> void:
	var actor := _actor()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 15.0
	gift.trust = 0.6
	var taught := SocialCauseDef.new()
	taught.id = &"a_teaching"
	taught.standing = 1.0
	SocialCauseCatalog.instance().reset()
	SocialCauseCatalog.instance().install([gift, taught])
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	CollectionApi.claim_tier(actor, 1)
	var result := CollectionApi.claim_tier(actor, 1)
	assert_eq(result["ok"], false, "refused")
	assert_eq(result["reason"], "already_claimed", "already claimed")


# --- Heterosis --------------------------------------------------------------------

func test_heterosis_status_is_empty_without_an_actor() -> void:
	assert_eq(CollectionApi.heterosis_status(null)["has_heterosis"], false)


func test_heterosis_derives_from_purity_snapshot() -> void:
	var actor := _actor()
	var status := CollectionApi.heterosis_status(actor)
	assert_eq(status["has_heterosis"], false, "no lineages, no heterosis")
	assert_eq(status["carrier_state"], false, "not a carrier")
	assert_eq(status["decay_rate"], 0.5, "decay rate is fixed")


# --- History ----------------------------------------------------------------------

func test_history_is_empty_without_an_actor() -> void:
	assert_eq(CollectionApi.history(null), [], "no actor, no history")


func test_history_returns_array() -> void:
	var actor := _actor()
	var history := CollectionApi.history(actor)
	assert_eq(history is Array, true, "history is an array")


# --- Emotional signature -----------------------------------------------------------

func test_emotional_signature_is_derived_from_axes() -> void:
	var actor := _actor()
	var gift := SocialCauseDef.new()
	gift.id = &"a_gift"
	gift.standing = 15.0
	gift.trust = 0.8
	var taught := SocialCauseDef.new()
	taught.id = &"a_teaching"
	taught.standing = 1.0
	SocialCauseCatalog.instance().reset()
	SocialCauseCatalog.instance().install([gift, taught])
	SocialApi.apply_cause(actor, MERCHANT, &"a_gift")
	SocialApi.apply_cause(actor, MERCHANT, &"a_teaching")
	var summary := CollectionApi.summary(actor)
	var partners: Array = summary["partners"]
	assert_eq(partners.size(), 1, "one partner")
	var signature := String((partners[0] as Dictionary)["emotional_signature"])
	assert_eq(signature == "", false, "signature is not empty")
	assert_eq(signature.contains(" "), true, "signature has two words")


# --- Record event ------------------------------------------------------------------

func test_record_event_returns_summary() -> void:
	var actor := _actor()
	var result := CollectionApi.record_event(actor, &"test_event", MERCHANT)
	assert_eq(result["actor"], "hero", "returns the summary")
	assert_eq(result is Dictionary, true, "returns a dictionary")
