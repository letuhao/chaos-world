extends TestCase

## BL-0951 / ADR 0939, S13: the dual-cultivation aid — the actor's scarred realm is mended
## by EXACTLY what the partner's perfection there loses.
##
## The equal transfer is the whole avenue, so it is asserted from both ledgers, not
## described: the actor's gain and the partner's loss are the same number, and that number
## is bounded on BOTH sides (the actor's headroom under `MEND_CAP`, the partner's reserve
## above zero) so neither is pushed past its own bound.
##
## Every loop is a bounded `for`; there is no `while`.

const REALM := &"qi_refining"
const OTHER_REALM := &"spirit_condensation"


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	DualCultivationApi.attach(actor)
	return actor


func _seed(actor: Actor, realm_id: StringName, perfection: float) -> void:
	assert_eq(
		bool(FoundationApi.snapshot(actor, realm_id, perfection).get("ok", false)),
		true,
		"seed snapshot %s at %f" % [String(realm_id), perfection]
	)


func test_aid_transfers_equally() -> void:
	var actor := _hero()
	var partner := _hero()
	_seed(actor, REALM, 0.1)
	_seed(partner, REALM, 1.0)
	var essence_before: float = actor.resource(DualCultivationStats.ESSENCE).current
	var age_before: float = actor.age_years
	var result := DualCultivationApi.dual_aid(actor, partner, REALM)
	assert_eq(bool(result.get("ok", false)), true, "the aid resolves: %s" % str(result))
	assert_eq(String(result.get("reason", "")), DualCultivationAid.OK_AIDED, "named")
	var transfer := float(result.get("transfer", -1.0))
	assert_almost_eq(transfer, DualCultivationAid.AID_STEP, "the authored step")
	var gained := FoundationApi.snapshot_for(actor, REALM) - 0.1
	var lost := 1.0 - FoundationApi.snapshot_for(partner, REALM)
	assert_almost_eq(gained, transfer, "the actor gains the transfer")
	assert_almost_eq(lost, transfer, "and the partner loses the same")
	assert_almost_eq(
		actor.resource(DualCultivationStats.ESSENCE).current,
		essence_before - DualCultivationAid.AID_ESSENCE,
		"the ritual spends its essence"
	)
	assert_eq(actor.age_years > age_before, true, "and the actor spends time")


## The transfer is bounded by the actor's headroom: a near-perfect actor gains only what is
## left under the cap, and the partner loses exactly that — never more.
func test_the_transfer_is_bounded_by_the_actors_headroom() -> void:
	var actor := _hero()
	var partner := _hero()
	_seed(actor, REALM, 0.45)
	_seed(partner, REALM, 1.0)
	var result := DualCultivationApi.dual_aid(actor, partner, REALM)
	assert_almost_eq(
		float(result.get("transfer", -1.0)),
		FoundationApi.MEND_CAP - 0.45,
		"only the headroom moves"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, REALM),
		FoundationApi.MEND_CAP,
		"the actor reaches the cap"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(partner, REALM),
		1.0 - (FoundationApi.MEND_CAP - 0.45),
		"and the partner loses exactly that"
	)


## The transfer is bounded by the partner's reserve too: a nearly-spent partner gives only
## what is left, and the actor gains exactly that — never more.
func test_a_partner_with_less_gives_all_of_it() -> void:
	var actor := _hero()
	var partner := _hero()
	_seed(actor, REALM, 0.1)
	_seed(partner, REALM, 0.05)
	var result := DualCultivationApi.dual_aid(actor, partner, REALM)
	assert_almost_eq(float(result.get("transfer", -1.0)), 0.05, "only the partner's reserve moves")
	assert_almost_eq(FoundationApi.snapshot_for(partner, REALM), 0.0, "the partner is spent")
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, REALM), 0.15, "and the actor gains exactly that"
	)


func test_a_body_with_no_essence_cannot_work_the_exchange() -> void:
	var actor := Actor.new(&"mortal", {Stat.PHYSIQUE: 10.0})
	_seed(actor, REALM, 0.1)
	var partner := _hero()
	_seed(partner, REALM, 1.0)
	var result := DualCultivationApi.dual_aid(actor, partner, REALM)
	assert_eq(bool(result.get("ok", true)), false, "no essence, no exchange")
	assert_eq(String(result.get("reason", "")), DualCultivationAid.R_NO_ESSENCE, "refused by name")


## Every refusal is named, and a refusal costs nothing (ADR 0044).
func test_refusals_are_named() -> void:
	var actor := _hero()
	var partner := _hero()
	var essence_before: float = actor.resource(DualCultivationStats.ESSENCE).current
	assert_eq(
		String(DualCultivationApi.dual_aid(null, partner, REALM).get("reason", "")),
		DualCultivationAid.R_NO_ACTOR,
		"a null actor is named"
	)
	assert_eq(
		String(DualCultivationApi.dual_aid(actor, null, REALM).get("reason", "")),
		DualCultivationAid.R_NO_PARTNER,
		"a null partner is named"
	)
	assert_eq(
		String(DualCultivationApi.dual_aid(actor, actor, REALM).get("reason", "")),
		DualCultivationAid.R_SAME_ACTOR,
		"an actor cannot exchange with themselves"
	)
	# A partner who never left the named realm has nothing to give.
	_seed(actor, REALM, 0.1)
	assert_eq(
		String(DualCultivationApi.dual_aid(actor, partner, REALM).get("reason", "")),
		DualCultivationAid.R_PARTNER_NO_SNAPSHOT,
		"a partner who never left the realm is refused by name"
	)
	# A realm the actor never left has nothing to mend.
	_seed(partner, REALM, 1.0)
	assert_eq(
		String(DualCultivationApi.dual_aid(actor, partner, OTHER_REALM).get("reason", "")),
		DualCultivationAid.R_NO_SNAPSHOT,
		"a realm the actor never left is refused by name"
	)
	assert_almost_eq(
		actor.resource(DualCultivationStats.ESSENCE).current, essence_before, "and nothing is spent"
	)


func test_a_realm_at_the_cap_is_refused() -> void:
	var actor := _hero()
	var partner := _hero()
	_seed(actor, REALM, 0.6)
	_seed(partner, REALM, 1.0)
	var result := DualCultivationApi.dual_aid(actor, partner, REALM)
	assert_eq(bool(result.get("ok", true)), false, "a realm at the ceiling has nothing to mend")
	assert_eq(String(result.get("reason", "")), DualCultivationAid.R_MEND_CAPPED, "named")
	assert_almost_eq(
		FoundationApi.snapshot_for(partner, REALM), 1.0, "and the partner is untouched"
	)


func test_defaults_to_the_weakest_scar() -> void:
	var actor := _hero()
	var partner := _hero()
	_seed(actor, REALM, 0.4)
	_seed(actor, OTHER_REALM, 0.2)
	_seed(partner, REALM, 1.0)
	_seed(partner, OTHER_REALM, 1.0)
	var result := DualCultivationApi.dual_aid(actor, partner)
	assert_eq(bool(result.get("ok", false)), true, "the aid resolves")
	assert_eq(String(result.get("realm", "")), String(OTHER_REALM), "on the weakest scar")
	assert_almost_eq(
		FoundationApi.snapshot_for(actor, OTHER_REALM),
		0.2 + DualCultivationAid.AID_STEP,
		"the weakest is lifted"
	)
	assert_almost_eq(
		FoundationApi.snapshot_for(partner, OTHER_REALM),
		1.0 - DualCultivationAid.AID_STEP,
		"and the partner loses there"
	)
	assert_almost_eq(FoundationApi.snapshot_for(actor, REALM), 0.4, "the untouched realm stays put")
