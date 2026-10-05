extends "res://tests/modules/doctrine/doctrine_fixture_kit.gd"

## The registration gate. ADR 0267 makes a System arrive from outside this repo's review,
## so the questions worth asking are the ones a System can get WRONG: an unnamed one whose
## state has nowhere to live, a row missing a key a panel draws from, a currency nothing
## spends, a pool that is core's, and a payload carrying a type the save cannot round trip.


func test_an_empty_registry_answers_every_read_without_crashing() -> void:
	assert_eq(DoctrineApi.rules().size(), 0, "no Systems is a state, not an error")
	assert_eq(DoctrineApi.available(actor()).size(), 0, "an empty registry offers nothing")
	assert_eq(DoctrineApi.available(null).size(), 0, "a null actor offers nothing")
	assert_eq(DoctrineApi.state(actor()).size(), 0, "no Systems, no ledgers")
	assert_eq(DoctrineApi.summary(null), {}, "the read model is {} for no actor")
	assert_eq(
		DoctrineApi.summary(actor()).get("system_count", -1), 0, "an empty registry counts zero"
	)
	assert_eq(DoctrineApi.boards(actor(), IRON_BELL).size(), 0, "an unknown System has no board")
	assert_eq(DoctrineApi.price(actor(), IRON_BELL, ROW_OPEN), {}, "an unknown System has no price")
	assert_eq(
		DoctrineApi.redeem(actor(), IRON_BELL, ROW_OPEN), {}, "an unknown System cannot be spent on"
	)
	assert_eq(DoctrineApi.join(actor(), IRON_BELL), {}, "an unknown System cannot be joined")
	assert_eq(DoctrineApi.leave(actor(), IRON_BELL), {}, "an unknown System cannot be left")


func test_an_unnamed_system_is_refused_because_it_has_no_data_key() -> void:
	var rule := iron_bell()
	rule.id = &""
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "an unnamed System is not registrable")
	assert_eq(String(verdict["reason"]), DoctrineRule.NOT_CLAIMED, "and it is refused by name")
	assert_eq(DoctrineRegistry.count(), 0, "and nothing entered the registry")


func test_a_second_attach_of_the_same_id_is_refused() -> void:
	register(iron_bell())
	var verdict := DoctrineApi.attach(iron_bell())
	assert_eq(bool(verdict["ok"]), false, "a System swapped under a live board is not a re-attach")
	assert_eq(DoctrineRegistry.count(), 1, "and the registry still holds exactly one")


func test_a_row_missing_a_declared_key_is_refused() -> void:
	var rule := iron_bell()
	rule.row_omits = [&"amount"]
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a panel cannot draw a row with no amount")
	assert_eq(DoctrineRegistry.count(), 0, "nothing entered the registry")


func test_a_row_spending_an_undeclared_pool_is_refused() -> void:
	var rule := iron_bell()
	rule.rows[0]["pool"] = &"insigt"
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a typo'd pool is a content defect, not a wallet")
	assert_eq(String(verdict["reason"]), DoctrineRule.UNDECLARED_POOL, "and it is named as one")


func test_a_declared_pool_no_row_spends_is_refused() -> void:
	var rule := iron_bell()
	rule.pools = [INSIGHT, RAGE]
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a currency with no sink is an accumulating debt")
	assert_eq(String(verdict["reason"]), DoctrineRule.UNDECLARED_POOL, "and it is named as one")
	assert_eq(
		String(verdict["detail"]).contains("rage"), true, "and the detail names the offending pool"
	)


func test_a_pool_core_reserves_is_refused() -> void:
	var rule := iron_bell()
	rule.pools = [INSIGHT, &"health"]
	rule.rows[0]["pool"] = &"health"
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a capped stat is not a currency")
	assert_eq(String(verdict["reason"]), DoctrineRule.UNDECLARED_POOL, "and it is named as one")


func test_a_pool_declared_twice_is_refused() -> void:
	var rule := iron_bell()
	rule.pools = [INSIGHT, INSIGHT]
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "two declarations of one id is one too many")


func test_a_row_that_names_no_pool_but_costs_is_refused() -> void:
	var rule := iron_bell()
	rule.rows[0]["pool"] = &""
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a cost with no pool to charge is unpayable money")


func test_a_row_that_can_never_be_bought_is_refused() -> void:
	var rule := iron_bell()
	rule.rows[0]["repeatable"] = false
	rule.rows[0]["max_count"] = 0
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "not repeatable with no cap is permanently maxed")
	assert_eq(String(verdict["reason"]), DoctrineRule.ALREADY_MAXED, "and it says so by that name")


func test_a_negative_cost_is_refused() -> void:
	var rule := iron_bell()
	rule.rows[0]["amount"] = -5.0
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a negative cost is a spend wearing the wrong name")


func test_a_payload_missing_a_declared_key_is_refused() -> void:
	for omission in [&"owned", &"affordable"]:
		DoctrineRegistry.clear()
		var rule := iron_bell()
		rule.price_omits = [omission]
		var verdict := DoctrineApi.attach(rule)
		assert_eq(bool(verdict["ok"]), false, "price without %s cannot be drawn" % String(omission))
		assert_eq(DoctrineRegistry.count(), 0, "and nothing entered the registry")


func test_an_earn_that_drops_a_declared_key_is_refused() -> void:
	var rule := iron_bell()
	rule.earn_omits = [&"amount"]
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "a proposal without an amount has no claim in it")


func test_a_progress_or_tier_that_drops_a_declared_key_is_refused() -> void:
	var rule := iron_bell()
	rule.progress_omits = [&"points_max"]
	assert_eq(bool(DoctrineApi.attach(rule)["ok"]), false, "progress must carry points_max")
	DoctrineRegistry.clear()
	var second := iron_bell()
	second.tier_omits = [&"next_tier_points"]
	assert_eq(bool(DoctrineApi.attach(second)["ok"]), false, "tier_for must carry next_tier_points")


func test_a_row_smuggling_a_type_is_refused() -> void:
	var rule := iron_bell()
	# Four levels below the row is one past `MAX_PAYLOAD_DEPTH`, so this is refused for
	# being unverifiable rather than for being a Dictionary: a depth cap is a bound, not a
	# ban on detail keys, which the contract explicitly permits.
	rule.rows[0]["blurb"] = {"a": {"b": {"c": {"d": 1}}}}
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict["ok"]), false, "payloads travel into saves, so the gate checks them")
	# A row shallow enough to verify is accepted: the check is a depth budget, not a ban on
	# detail keys.
	DoctrineRegistry.clear()
	var shallow := iron_bell()
	shallow.rows[0]["blurb"] = "a sentence"
	shallow.rows[0]["tags"] = ["body", "form"]
	assert_eq(bool(DoctrineApi.attach(shallow)["ok"]), true, "primitives-only detail keys pass")


func test_an_empty_system_with_no_rows_registers_and_stays_inert() -> void:
	var rule := register(empty_system(&"way_of_the_unwritten"))
	var subject := actor()
	assert_eq(DoctrineApi.boards(subject, rule.system_id()).size(), 0, "no rows is an empty board")
	assert_eq(DoctrineApi.price(subject, rule.system_id(), ROW_OPEN), {}, "and no price")
	assert_eq(
		DoctrineApi.price(subject, rule.system_id(), ROW_OPEN).size(),
		0,
		"which is {} not a refusal"
	)
	var summary := DoctrineApi.summary(subject)
	assert_eq(
		str(summary["reasons"]), str(DoctrineRule.REASONS), "the closed reason set is published"
	)


func test_a_registered_system_reports_its_declaration() -> void:
	var rule := register(iron_bell())
	var rows := DoctrineApi.rules()
	assert_eq(rows.size(), 1, "one System is one row")
	assert_eq(String(rows[0]["system_id"]), String(IRON_BELL), "the id is the row's key")
	assert_eq(
		String(rows[0]["data_key"]), String(rule.data_key()), "and the save key rides with it"
	)
	assert_eq(String(rows[0]["pool_count"]), "1", "one currency is one pool")


func test_registration_order_is_what_ids_reports() -> void:
	register(iron_bell())
	register(silent_bell())
	register(empty_system(&"way_of_the_third"))
	var ids := DoctrineRegistry.ids()
	assert_eq(ids.size(), 3, "three Systems, three ids")
	assert_eq(String(ids[0]), String(IRON_BELL), "the first is the first registered")
	assert_eq(String(ids[1]), String(SILENT_BELL), "the second is the second registered")
	assert_eq(String(ids[2]), "way_of_the_third", "and the third is the third")
	ids.append(&"way_of_the_injected")
	assert_eq(DoctrineRegistry.count(), 3, "and the caller cannot write through the copy")
