extends "res://tests/modules/base_grant/base_grant_fixture_kit.gd"

## The GATES `BaseGrantApi` enforces, one body each.
##
## Every refusal here asserts that the actor's FULL base dictionary is unchanged, not that
## one attribute looks right: the module's claim is that a refused grant leaves the actor
## untouched, and a claim asserted on one of seven attributes is not the claim.
##
## The read model and the structural pins live in `test_base_grant_shape.gd`; this file
## answers "what does the verb do", that one answers "what does it promise".


func setup() -> void:
	# Every body below must clear this many assertions or the runner charges it a failure,
	# so a body that dies on its first line cannot be reported green.
	expect_assertions(1)


func _request(overrides: Dictionary = {}) -> Dictionary:
	var base := {"source": "doctrine/water_margin/row_1", "gains": {"physique": 1.0}}
	# `keys()` is snapshotted by the `for` and the body writes to `base`, never to the map
	# it walks (INC-0002).
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


# --- the grant applies exactly what was authored ----------------------------


func test_a_paid_grant_applies_exactly_the_authored_amount() -> void:
	var actor := hero()
	# A transfer first, because it costs nothing and therefore tests the ARITHMETIC
	# rather than the gate.
	var moved := BaseGrantApi.grant(
		actor, {"source": "t/1", "gains": {"physique": 1.0}, "costs": {"spirit": 1.0}}
	)
	assert_eq(bool(moved["ok"]), true, "a net-zero transfer is granted")
	assert_eq(bool(moved["applied"]), true, "and it was applied, not merely approved")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 11.0, "physique rose by the authored 1.0")
	assert_eq(actor.stats.get_base(Stat.SPIRIT), 7.0, "spirit fell by the authored 1.0")
	assert_eq(
		float((moved["granted"] as Dictionary)["physique"]), 1.0, "the signed delta is reported"
	)
	assert_eq(
		float((moved["granted"] as Dictionary)["spirit"]), -1.0, "both halves, signed, in one map"
	)


func test_a_purchase_debits_the_named_pool_by_the_authored_amount() -> void:
	var actor := hero()
	var merit := pool(actor, &"merit", 10.0)
	var answer := BaseGrantApi.grant(
		actor,
		{"source": "t/2", "gains": {"physique": 2.0}, "cost_pool": "merit", "cost_amount": 2.0}
	)
	assert_eq(bool(answer["ok"]), true, "a paid gain is granted")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 12.0, "the gain landed in full")
	assert_eq(merit.current, 8.0, "and the pool paid the authored 2.0")


# --- the yin-yang gate -------------------------------------------------------


func test_a_one_sided_gain_is_refused_as_unpaid_and_touches_nothing() -> void:
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request())
	assert_eq(bool(answer["ok"]), false, "a '+1 physique' with no counterpart is refused")
	assert_eq(
		String(answer["reason"]),
		BaseGrantApi.REASON_UNPAID,
		"and it names the yin-yang gate rather than a generic failure"
	)
	assert_eq(base_snapshot(actor), before, "a refused grant left every base attribute alone")


func test_a_gain_paid_less_than_it_is_also_unpaid() -> void:
	# The loophole a partial payment opens: two presses of "+1 for 0.5" are "+2 for 1",
	# so paying under `net` must be refused rather than treated as a discount.
	var actor := hero()
	var merit := pool(actor, &"merit", 10.0)
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(
		actor,
		{"source": "t/3", "gains": {"physique": 1.0}, "cost_pool": "merit", "cost_amount": 0.5}
	)
	assert_eq(String(answer["reason"]), BaseGrantApi.REASON_UNPAID, "underpaying is not a discount")
	assert_eq(base_snapshot(actor), before, "and it moved nothing")
	assert_eq(merit.current, 10.0, "and it charged nothing")


func test_a_costs_map_cannot_launder_a_gain() -> void:
	# The counter to "just make `costs` required": `removed` is subtracted BEFORE the
	# yin-yang comparison, so a token cost does not buy a large one.
	var actor := hero()
	pool(actor, &"merit", 100.0)
	var answer := (
		BaseGrantApi
		. grant(
			actor,
			{
				"source": "t/4",
				"gains": {"physique": 99.0},
				"costs": {"spirit": 1.0},
				"cost_pool": "merit",
				"cost_amount": 1.0,
			}
		)
	)
	assert_eq(
		String(answer["reason"]),
		BaseGrantApi.REASON_UNPAID,
		"net is 98 after the cost, so a 1.0 payment does not cover it"
	)
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 10.0, "and nothing moved")


func test_a_costs_only_request_is_a_pure_cost_and_is_still_granted() -> void:
	# The mirror of the gate: a request that only lowers an attribute creates no
	# advantage, so there is nothing to answer and the yin-yang rule does not bite.
	var actor := hero()
	var answer := BaseGrantApi.grant(
		actor, {"source": "t/5", "gains": {"physique": 1.0}, "costs": {"spirit": 2.0}}
	)
	assert_eq(bool(answer["ok"]), true, "net -1 is a cost, not an unearned gain")
	assert_eq(actor.stats.get_base(Stat.SPIRIT), 6.0, "and the cost landed")
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), 11.0, "alongside the authored gain")


# --- refusals leave the actor untouched --------------------------------------


func test_an_unknown_stat_id_is_refused_by_name() -> void:
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request({"gains": {"mystery": 1.0}}))
	assert_eq(
		String(answer["reason"]), BaseGrantApi.REASON_UNKNOWN_ATTRIBUTE, "an unknown id is refused"
	)
	assert_eq(
		String(answer.get(BaseGrantApi.REASON_UNKNOWN_ATTRIBUTE, "")),
		"mystery",
		"and the refusal NAMES it, because a silent 0.0 for a typo is the failure this removes"
	)
	assert_eq(base_snapshot(actor), before, "and nothing moved")


func test_an_unknown_cost_id_is_refused_by_name_too() -> void:
	# The counterpart path is a second spelling of the same gate; leaving it unchecked
	# would make `costs` a place a typo hides.
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request({"costs": {"not_a_stat": 1.0}}))
	assert_eq(
		String(answer["reason"]),
		BaseGrantApi.REASON_UNKNOWN_ATTRIBUTE,
		"the cost map is checked too"
	)
	assert_eq(
		String(answer.get(BaseGrantApi.REASON_UNKNOWN_ATTRIBUTE, "")), "not_a_stat", "and names it"
	)
	assert_eq(base_snapshot(actor), before, "and nothing moved")


func test_a_derived_stat_is_not_a_base_attribute_and_is_refused() -> void:
	# `Stat.MAX_HEALTH` is derived, so a request to raise it directly is the ADR 0001
	# violation `set_base` invites — caught at the gate rather than by convention.
	var actor := hero()
	var before := actor.stats.derived(Stat.MAX_HEALTH)
	var answer := BaseGrantApi.grant(actor, _request({"gains": {Stat.MAX_HEALTH: 50.0}}))
	assert_eq(
		String(answer["reason"]),
		BaseGrantApi.REASON_UNKNOWN_ATTRIBUTE,
		"derived stats are not base attributes"
	)
	assert_eq(actor.stats.derived(Stat.MAX_HEALTH), before, "and the derived pipeline is untouched")


func test_a_zero_gain_is_refused_rather_than_granted() -> void:
	# BL-0110: `ok` on a grant that moves nothing is the verb consuming a press and
	# changing no actor.
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request({"gains": {"physique": 0.0}}))
	assert_eq(String(answer["reason"]), BaseGrantApi.REASON_BAD_AMOUNT, "a zero gain is refused")
	assert_eq(base_snapshot(actor), before, "and nothing moved")


func test_a_net_zero_request_is_refused_as_nothing_to_grant() -> void:
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(
		actor, _request({"gains": {"physique": 2.0}, "costs": {"physique": 2.0}})
	)
	assert_eq(String(answer["reason"]), BaseGrantApi.REASON_NO_GAIN, "+2 will/-2 will is a no-op")
	assert_eq(base_snapshot(actor), before, "and nothing moved")


func test_an_empty_gains_map_is_refused() -> void:
	var actor := hero()
	var answer := BaseGrantApi.grant(actor, _request({"gains": {}}))
	assert_eq(String(answer["reason"]), BaseGrantApi.REASON_NO_GAIN, "there is nothing to grant")


func test_an_unsourced_grant_is_refused() -> void:
	# The press counter is keyed by `source`, so an anonymous grant is not a grant with a
	# default source — it is a permanent base write that cannot be budgeted or explained.
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request({"source": ""}))
	assert_eq(
		String(answer["reason"]), BaseGrantApi.REASON_UNSOURCED, "an unnamed grant is refused"
	)
	assert_eq(base_snapshot(actor), before, "and nothing moved")


func test_an_unknown_cost_pool_is_not_reported_as_a_broke_actor() -> void:
	# ADR 0067's refuse-don't-repair ordering: a typo is a different defect from an empty
	# balance and must not be reported as one.
	var actor := hero()
	var merit := pool(actor, &"merit", 10.0)
	var answer := BaseGrantApi.grant(actor, _request({"cost_pool": "mreit", "cost_amount": 1.0}))
	assert_eq(
		String(answer["reason"]), BaseGrantApi.REASON_UNKNOWN_POOL, "the typo is named as a typo"
	)
	assert_eq(merit.current, 10.0, "and the real pool was not charged")


func test_an_insufficient_pool_refuses_and_charges_nothing() -> void:
	var actor := hero()
	var merit := pool(actor, &"merit", 1.0)
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(actor, _request({"cost_pool": "merit", "cost_amount": 3.0}))
	assert_eq(String(answer["reason"]), BaseGrantApi.REASON_INSUFFICIENT, "the pool is short")
	assert_eq(merit.current, 1.0, "and the clamp never ran")
	assert_eq(base_snapshot(actor), before, "and nothing moved")


# --- the transfer floor ------------------------------------------------------


func test_a_transfer_cannot_drive_an_attribute_below_zero() -> void:
	# Nothing else in this tree subtracts from a base stat, so this is the half with no
	# precedent and the one most likely to go negative by arithmetic.
	var actor := hero()
	var before := base_snapshot(actor)
	var answer := BaseGrantApi.grant(
		actor, _request({"gains": {"physique": 1.0}, "costs": {"agility": 99.0}})
	)
	assert_eq(
		String(answer["reason"]), BaseGrantApi.REASON_BELOW_FLOOR, "the floor refuses the transfer"
	)
	assert_eq(
		String(answer.get(BaseGrantApi.REASON_BELOW_FLOOR, "")),
		"agility",
		"and names the attribute"
	)
	assert_eq(base_snapshot(actor), before, "and nothing moved — not even the gain half")
	assert_eq(actor.stats.get_base(Stat.AGILITY), 4.0, "agility is exactly where it was")


func test_a_transfer_landing_exactly_on_zero_is_allowed() -> void:
	# The floor is `>= 0.0`, not `> 0.0`: refusing a transfer that spends the last point
	# would make the zero case a special case nobody authored.
	var actor := hero()
	var answer := BaseGrantApi.grant(
		actor, _request({"gains": {"physique": 1.0}, "costs": {"agility": 4.0}})
	)
	assert_eq(bool(answer["ok"]), true, "spending an attribute down to zero is legal")
	assert_eq(actor.stats.get_base(Stat.AGILITY), 0.0, "and it landed on the floor exactly")


# --- the rate bound ----------------------------------------------------------


func test_the_rate_bound_refuses_after_max_presses_and_names_itself() -> void:
	var actor := hero()
	# A POOL large enough for every press, so the rate bound is the only gate that can
	# bite. Buying rather than transferring keeps the `0.0` floor from becoming the
	# binding constraint eight presses in, which would test the floor under a bound's name.
	var merit := pool(actor, &"merit", float(BaseGrantApi.MAX_GRANTS_PER_SOURCE) * 4.0)
	var press := {"gains": {"physique": 1.0}, "cost_pool": "merit", "cost_amount": 1.0}
	# A FIXED count, snapshotted by the `for` itself; the body grants and nothing widens
	# the bound, so the walk terminates on the constant (INC-0002).
	for index in BaseGrantApi.MAX_GRANTS_PER_SOURCE:
		var request := press.duplicate()
		request["source"] = "t/pump"
		assert_eq(
			bool(BaseGrantApi.grant(actor, request)["ok"]),
			true,
			"press %d of %d is inside the bound" % [index, BaseGrantApi.MAX_GRANTS_PER_SOURCE]
		)
	var spent := actor.stats.get_base(Stat.PHYSIQUE)
	var over_request := press.duplicate()
	over_request["source"] = "t/pump"
	var over := BaseGrantApi.grant(actor, over_request)
	assert_eq(
		String(over["reason"]),
		BaseGrantApi.REASON_BUDGET_SPENT,
		"the next press is over the rate bound"
	)
	assert_eq(actor.stats.get_base(Stat.PHYSIQUE), spent, "and it moved nothing")
	assert_eq(
		merit.current,
		merit.maximum - float(BaseGrantApi.MAX_GRANTS_PER_SOURCE),
		"and charged nothing"
	)
	assert_eq(int(over["grants_left"]), 0, "and the answer says the budget is gone")


func test_the_rate_bound_is_per_source_not_global() -> void:
	# A bound that every source shared would be a global power cap wearing a per-source
	# name — the ladder's problem, not this module's.
	var actor := hero()
	pool(actor, &"merit", float(BaseGrantApi.MAX_GRANTS_PER_SOURCE) * 4.0)
	var press := {"gains": {"physique": 1.0}, "cost_pool": "merit", "cost_amount": 1.0}
	for index in BaseGrantApi.MAX_GRANTS_PER_SOURCE:
		var request := press.duplicate()
		request["source"] = "t/a"
		BaseGrantApi.grant(actor, request)
	var other_request := press.duplicate()
	other_request["source"] = "t/b"
	var other := BaseGrantApi.grant(actor, other_request)
	assert_eq(bool(other["ok"]), true, "a different source still has its own budget")
	assert_eq(
		int(other["grants_used"]), 0, "and it starts from zero, not from the other source's total"
	)
