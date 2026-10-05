extends "res://tests/modules/doctrine/doctrine_fixture_kit.gd"

## `earn` is the only place two Systems meet, so it is the only place arbitration happens:
## ADR 0267 makes the rule a PROPOSAL and leaves the decision to whoever owns the event, and
## this module is that caller. `join`/`leave` are here because they are what decides whether
## an earn has anyone to pay at all.


func test_an_earn_with_no_systems_applies_nothing() -> void:
	var subject := actor()
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(bool(answer["ok"]), false, "nobody claimed the occurrence")
	assert_eq(String(answer["reason"]), DoctrineRule.NOT_CLAIMED, "so the answer names why")
	assert_eq((answer["applied"] as Array).size(), 0, "and nothing was applied")
	assert_eq(int(answer["candidate_count"]), 0, "because there were no candidates")


func test_an_earn_on_a_null_actor_applies_nothing() -> void:
	register(iron_bell())
	var answer := DoctrineApi.earn(null, {"kind": "defeat"})
	assert_eq(bool(answer["ok"]), false, "no actor, no balance to credit")
	assert_eq(int(answer["candidate_count"]), 0, "and no candidate was even asked")


func test_one_joined_system_earns_its_own_currency() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	var answer := farm(subject, rule, 3)
	assert_eq(bool(answer["ok"]), true, "the System answered its own event")
	assert_eq((answer["applied"] as Array).size(), 1, "and one claim landed")
	assert_eq(balance_of(subject, rule), 3.0, "three occurrences, three insight")
	assert_eq(String((answer["applied"][0] as Dictionary)["pool"]), "insight", "in its own pool")


func test_an_unjoined_system_is_not_a_candidate() -> void:
	var rule := register(iron_bell())
	var subject := actor()
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(int(answer["candidate_count"]), 0, "a System nobody joined has no balance to credit")
	assert_eq(balance_of(subject, rule), 0.0, "and the balance is untouched")


func test_naming_one_system_restricts_the_question() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	DoctrineApi.join(subject, silent.system_id())
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"}, silent.system_id())
	assert_eq(int(answer["candidate_count"]), 1, "only the named System was asked")
	assert_eq(
		String((answer["applied"][0] as Dictionary)["system_id"]),
		String(SILENT_BELL),
		"and it was the one asked"
	)
	assert_eq(balance_of(subject, silent), 3.0, "so only its currency moved")
	assert_eq(balance_of(subject, iron), 0.0, "and the other System's did not")


func test_two_systems_answering_one_occurrence_are_arbitrated_by_the_larger_claim() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	DoctrineApi.join(subject, silent.system_id())
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(int(answer["candidate_count"]), 2, "both Systems answered the same occurrence")
	assert_eq((answer["applied"] as Array).size(), 1, "and exactly one was paid")
	assert_eq(
		String((answer["applied"][0] as Dictionary)["system_id"]),
		String(SILENT_BELL),
		"the larger claim takes the occurrence"
	)
	assert_eq(balance_of(subject, silent), 3.0, "so the larger claim was paid")
	assert_eq(balance_of(subject, iron), 0.0, "and the smaller claim was not")
	assert_eq((answer["declined"] as Array).size(), 1, "the loser is declined, not ignored")
	assert_eq(
		String((answer["declined"][0] as Dictionary)["system_id"]),
		String(IRON_BELL),
		"and it is named so a caller can say whose claim lost"
	)


func test_an_equal_claim_is_won_by_registration_order() -> void:
	var first := register(iron_bell())
	var second := register(silent_bell())
	second.earn_amount = first.earn_amount
	var subject := joined_actor(first)
	DoctrineApi.join(subject, second.system_id())
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(
		String((answer["applied"][0] as Dictionary)["system_id"]),
		String(IRON_BELL),
		"a tie is not a coin flip: the earliest registration takes it"
	)


func test_an_event_no_system_claims_applies_nothing() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	var answer := DoctrineApi.earn(subject, {"kind": "meditate"})
	assert_eq(bool(answer["ok"]), false, "an unclaimed event pays nobody")
	assert_eq(String(answer["reason"]), DoctrineRule.NOT_CLAIMED, "and says so")
	assert_eq((answer["declined"] as Array).size(), 1, "every candidate declined")
	assert_eq(balance_of(subject, rule), 0.0, "and the balance did not move")


func test_a_proposal_naming_an_undeclared_pool_is_refused_and_writes_nothing() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	# A broken System: its board spends `insight`, its earn claims `insigt`.
	rule.earn_pool = &"insigt"
	var before := balance_of(subject, rule)
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(bool(answer["ok"]), false, "a pool the System never declared is a content defect")
	assert_eq(String(answer["reason"]), DoctrineRule.UNDECLARED_POOL, "and it is named as one")
	assert_eq(balance_of(subject, rule), before, "and no currency was invented for the typo")


func test_a_proposal_of_zero_claims_nothing() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	rule.earn_amount = 0.0
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(bool(answer["ok"]), false, "a zero earn is not an earn")
	assert_eq(balance_of(subject, rule), 0.0, "and the balance stayed")


func test_a_leave_stops_the_earnings_and_forfeits_the_progress() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 4)
	assert_eq(balance_of(subject, rule), 4.0, "four occurrences banked four insight")
	var left := DoctrineApi.leave(subject, rule.system_id())
	assert_eq(bool(left["ok"]), true, "the opt-out is honoured")
	assert_eq(balance_of(subject, rule), 0.0, "an unspent coin does not survive the opt-out")
	assert_eq(points_of(subject, rule), 0, "nor does the counter")
	var answer := DoctrineApi.earn(subject, {"kind": "defeat"})
	assert_eq(int(answer["candidate_count"]), 0, "and a System nobody is in is not asked again")


func test_join_is_a_round_trip_and_a_second_join_is_already_maxed() -> void:
	var rule := register(iron_bell())
	var subject := actor()
	var first := DoctrineApi.join(subject, rule.system_id())
	assert_eq(bool(first["ok"]), true, "the opt-in is accepted")
	assert_eq(
		String(first["data_key"]), String(rule.data_key()), "and it reports where it persists"
	)
	assert_eq(_is_joined(subject, rule), true, "the ledger says so")
	var again := DoctrineApi.join(subject, rule.system_id())
	assert_eq(bool(again["ok"]), false, "joining twice is not free progress")
	assert_eq(
		String(again["reason"]),
		DoctrineRule.ALREADY_MAXED,
		"and it is already as joined as it gets"
	)
	var left := DoctrineApi.leave(subject, rule.system_id())
	assert_eq(bool(left["ok"]), true, "and the opt-out is available")
	assert_eq(_is_joined(subject, rule), false, "which clears the ledger")
	assert_eq(
		bool(DoctrineApi.join(subject, rule.system_id())["ok"]),
		true,
		"and rejoining is a fresh start"
	)


func test_leaving_a_system_you_are_not_in_claims_nothing() -> void:
	var rule := register(iron_bell())
	var subject := actor()
	var answer := DoctrineApi.leave(subject, rule.system_id())
	assert_eq(bool(answer["ok"]), false, "there is nothing to leave")
	assert_eq(String(answer["reason"]), DoctrineRule.NOT_CLAIMED, "so nothing is claimed")


func test_two_systems_keep_separate_ledgers() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	DoctrineApi.join(subject, silent.system_id())
	farm(subject, iron, 2)
	assert_eq(balance_of(subject, iron), 2.0, "the first System earned its own")
	assert_eq(balance_of(subject, silent), 0.0, "and the second earned nothing on its own event")
	assert_ne(
		String(iron.data_key()),
		String(silent.data_key()),
		"two Systems persist under two keys, which is the whole point of a derived one"
	)
	var state := DoctrineApi.state(subject)
	assert_eq(
		(state[String(IRON_BELL)] as Dictionary).size() > 0, true, "the first ledger is readable"
	)
	assert_eq((state[String(SILENT_BELL)] as Dictionary).size() > 0, true, "and so is the second")
