extends TestCase

## The shared claim vocabulary every institution speaks (ADR 0083).
##
## These are contract tests for `InstitutionClaim`, and they exist because the
## claim is the one type three tiers construct and three `.tres` types serialize.
## A divergence here is a duplicated promotion rule discovered late, which is the
## ADR 0066 failure mode in a new place.

const STANDING_CAP := 100


## A claim round-trips through the JSON hop that a file-backed save makes, and
## the outer key conversion `Actor.to_dict` performs is reproduced here by hand:
## inner keys must already be `String`, because core converts only the outer
## `module_data` key.
func test_a_claim_survives_a_json_round_trip() -> void:
	var claim := InstitutionClaim.new()
	claim.position = &"elder"
	claim.standing = 42
	claim.standing_cap = STANDING_CAP
	claim.owe(&"dues_outer", 3)
	claim.owe(&"manual_reading", 1)
	var restored := InstitutionClaim.from_dict(JSON.parse_string(JSON.stringify(claim.to_dict())))
	assert_eq(restored.position, &"elder", "the position came back verbatim")
	assert_eq(restored.standing, 42, "so did the standing")
	assert_eq(restored.standing_cap, STANDING_CAP, "and the cap")
	assert_eq(restored.obligation.get("dues_outer", 0), 3, "the owed periods came back")
	assert_eq(restored.obligation.get("manual_reading", 0), 1, "on every line")
	for key in restored.obligation.keys():
		assert_eq(typeof(key), TYPE_STRING, "and every inner key is a String")


## Standing is earned and can fall, but clamps at zero rather than going
## negative — a member with nothing left has nothing left to lose, which is what
## makes a demotion cost something.
func test_standing_clamps_at_zero_and_never_goes_negative() -> void:
	var claim := InstitutionClaim.new()
	claim.standing = 5
	var applied := claim.move_standing(-40)
	assert_eq(applied, -5, "the applied amount is only what actually landed")
	assert_eq(claim.standing, 0, "and standing rests at zero, never below")


## The cap is a real ceiling: a huge gain is bounded by the institution's own
## authored cap, so no amount of standing can run away.
func test_standing_clamps_at_the_institutions_cap() -> void:
	var claim := InstitutionClaim.new()
	claim.standing_cap = STANDING_CAP
	claim.standing = STANDING_CAP
	var applied := claim.move_standing(10_000)
	assert_eq(applied, 0, "a claim already at its cap gains nothing")
	assert_eq(claim.standing, STANDING_CAP, "so it never exceeds it")


## The recognition a claim projects is a bounded PERCENT and nothing else
## (ADR 0084). A percent rides the member's own growth, so an institution is the
## same strength at R5 as at R30; a flat would not be.
func test_recognition_is_a_bounded_percent_and_never_a_flat_grant() -> void:
	var at_cap := InstitutionClaim.standing_percent(STANDING_CAP)
	assert_almost_eq(at_cap, 0.10, "a full claim recognises ten percent")
	var at_zero := InstitutionClaim.standing_percent(0)
	assert_almost_eq(at_zero, 0.0, "and an empty claim recognises nothing")
	var negative := InstitutionClaim.standing_percent(-50)
	assert_almost_eq(negative, 0.0, "a negative standing is not a negative bonus")
	assert_almost_eq(
		InstitutionClaim.standing_percent(10_000), 0.10, "and no amount of standing exceeds the cap"
	)
	assert_almost_eq(
		InstitutionClaim.STANDING_PERCENT_CAP,
		0.10,
		"the cap is the authored constant, not a literal"
	)


## The two halves of the claim are independent, which is the whole politics layer
## (ADR 0064 carried forward). Neither a position nor a standing may be derived
## from the other, so the type simply never computes one from the other.
func test_position_and_standing_are_independent() -> void:
	var claim := InstitutionClaim.new()
	claim.standing_cap = STANDING_CAP
	claim.standing = 50
	claim.move_standing(25)
	assert_eq(claim.standing, 75, "standing moved")
	assert_eq(claim.position, &"", "and the position is untouched by it")
	claim.position = &"elder"
	claim.move_standing(-75)
	assert_eq(claim.position, &"elder", "the position survives a standing change")


## An obligation is settled in counts and reports how much it actually paid, so a
## caller can refuse to settle a line it holds no ledger for rather than silently
## paying a debt it does not have.
func test_an_obligation_settles_by_count_and_reports_what_it_paid() -> void:
	var claim := InstitutionClaim.new()
	assert_eq(claim.settled(), true, "a fresh claim owes nothing")
	claim.owe(&"dues_outer", 3)
	assert_eq(claim.settled(), false, "so it is not settled")
	assert_eq(claim.settle(&"dues_outer", 2), 2, "two of three periods paid")
	assert_eq(claim.settle(&"dues_outer", 9), 1, "and the third, no more than is owed")
	assert_eq(claim.settle(&"dues_outer", 1), 0, "settling a cleared line pays nothing")
	assert_eq(claim.settle(&"no_such_term", 5), 0, "nor does a line never opened")
	assert_eq(claim.settled(), true, "so the claim is settled")


## A corrupt save cannot inject a wrong type or a negative balance. The cap is
## repaired rather than persisted at zero, because a claim whose cap cannot be
## computed would report a zero ratio and read as a member nobody respects.
func test_a_corrupt_claim_is_repaired_rather_than_persisted() -> void:
	var claim := InstitutionClaim.from_dict(
		{"position": "elder", "standing": -40, "standing_cap": 0, "obligation": {"dues": -3}}
	)
	assert_eq(claim.standing, 0, "a negative standing reads as zero")
	assert_eq(claim.standing_cap, 1, "a zero cap is repaired to something computable")
	assert_eq(claim.obligation.size(), 0, "and a negative owed count is dropped")
	assert_eq(claim.normalized(), 0.0, "so it reports an empty ratio rather than dividing by zero")
