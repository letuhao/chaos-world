extends "res://tests/modules/doctrine/doctrine_fixture_kit.gd"

## The board: a catalogue read, a live quote, and one press that spends and grants. Plus the
## two questions the counter exists to answer — that a tier is DERIVED from one int and never
## from a realm, and that the counter may run past anything the world can reach.


func test_the_board_is_readable_before_joining_and_priced_only_after() -> void:
	var rule := register(iron_bell())
	var subject := actor()
	assert_eq(
		DoctrineApi.boards(subject, rule.system_id()).size(),
		3,
		"a join screen has to draw what joining would offer"
	)
	var unjoined := DoctrineApi.price(subject, rule.system_id(), ROW_OPEN)
	assert_eq(bool(unjoined["ok"]), false, "a quote for a System you are not in is not a price")
	assert_eq(String(unjoined["reason"]), DoctrineRule.NOT_CLAIMED, "and it says which one it is")
	assert_eq(
		bool(unjoined["affordable"]), false, "affordable means nothing for a System you are not in"
	)
	DoctrineApi.join(subject, rule.system_id())
	var joined := DoctrineApi.price(subject, rule.system_id(), ROW_OPEN)
	assert_eq(
		String(joined["reason"]),
		String(DoctrineRule.INSUFFICIENT),
		"now it answers about the wallet"
	)
	assert_eq(int(joined["owned"]), 0, "and the row has not been bought")


func test_a_row_that_does_not_exist_is_not_a_refusal() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	assert_eq(
		DoctrineApi.price(subject, rule.system_id(), &"no_such_row"),
		{},
		"does-not-exist is {} and not a refusal (ADR 0083)"
	)
	assert_eq(
		DoctrineApi.redeem(subject, rule.system_id(), &"no_such_row"),
		{},
		"and a panel must not draw a refusal on a row that was never there"
	)


func test_a_redeem_spends_the_framework_money_and_grants_through_the_universal_verb() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 10)
	assert_eq(balance_of(subject, rule), 10.0, "ten occurrences banked ten insight")
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_OPEN)
	assert_eq(bool(answer["ok"]), true, "the press is honoured")
	assert_eq(float(answer["spent"]), 5.0, "and it reports what it spent")
	assert_eq(balance_of(subject, rule), 5.0, "the ledger moved by the row's own price")
	assert_eq((answer["granted"] as Array).size(), 1, "one grant landed")
	assert_eq(
		subject.has_status(StringName("doctrine_open_form")), true, "through Actor.add_status"
	)


func test_a_redeem_with_an_insufficient_balance_changes_nothing() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 1)
	var quoted := DoctrineApi.price(subject, rule.system_id(), ROW_SEALED)
	assert_eq(
		bool(quoted["affordable"]), false, "twenty insight is more than one occurrence banked"
	)
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_SEALED)
	assert_eq(bool(answer["ok"]), false, "so the press is refused")
	assert_eq(
		String(answer["reason"]), DoctrineRule.INSUFFICIENT, "with the reason a panel can compare"
	)
	assert_eq(float(answer["spent"]), 0.0, "and nothing was charged")
	assert_eq(balance_of(subject, rule), 1.0, "the balance is intact")
	assert_eq(subject.has_status(StringName("doctrine_sealed_form")), false, "and no grant landed")


func test_a_row_above_the_counter_tier_is_locked_before_the_wallet_is_read() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 5)
	assert_eq(tier_of(subject, rule), 0, "five points is below the first band's ten")
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_SEALED)
	assert_eq(
		String(answer["reason"]), DoctrineRule.TIER_LOCKED, "the band is the gate, not the purse"
	)
	assert_eq(balance_of(subject, rule), 5.0, "and a locked row costs nothing")


func test_a_non_repeatable_row_is_refused_the_second_time() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 10)
	seed_points(subject, rule, 10)
	farm(subject, rule, 20)
	assert_eq(
		bool(DoctrineApi.redeem(subject, rule.system_id(), ROW_SEALED)["ok"]), true, "bought once"
	)
	var again := DoctrineApi.redeem(subject, rule.system_id(), ROW_SEALED)
	assert_eq(bool(again["ok"]), false, "a second press is refused")
	assert_eq(String(again["reason"]), DoctrineRule.ALREADY_MAXED, "and the ledger says which")
	var price_after := DoctrineApi.price(subject, rule.system_id(), ROW_SEALED)
	assert_eq(int(price_after["owned"]), 1, "and the quote reports what is held")


func test_a_free_row_needs_no_pool_and_still_counts_as_a_redemption() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	seed_points(subject, rule, 25)
	assert_eq(tier_of(subject, rule), 2, "twenty-five points reaches the top band")
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_TRANSCENDENT)
	assert_eq(bool(answer["ok"]), true, "the top row is reachable at the top tier")
	assert_eq(float(answer["spent"]), 0.0, "and it costs nothing")
	assert_eq(balance_of(subject, rule), 0.0, "which is a balance of nothing, not a missing one")
	var ledger := DoctrineLedger.normalize(subject.get_module_data(rule.data_key()))
	assert_eq(int(ledger[DoctrineLedger.KEY_REDEMPTIONS]), 1, "a free row still consumed a press")


func test_an_undeclared_pool_on_a_row_is_diagnosed_before_affordability() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	# Registered while the row was honest, then broken — the shape a mod ships.
	seed_points(subject, rule, 10)
	rule.rows[1]["pool"] = &"insigt"
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_SEALED)
	assert_eq(
		String(answer["reason"]),
		DoctrineRule.UNDECLARED_POOL,
		"a defect is not a broke actor, and this row costs more than the wallet holds"
	)
	assert_eq(float(answer["spent"]), 0.0, "and nothing was charged for the broken row")


func test_the_tier_is_derived_from_the_counter_and_from_nothing_else() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	var seen: Array[int] = []
	for points in [0, 9, 10, 19, 20, 29]:
		seed_points(subject, rule, points)
		seen.append(tier_of(subject, rule))
	assert_eq(
		str(seen), str([0, 0, 1, 1, 2, 2]), "a band is ten points, derived from the counter alone"
	)
	var tiers := rule.tier_for(subject)
	assert_eq(int(tiers[&"tiers"]), 3, "three bands are authored")
	assert_eq(int(tiers[&"next_tier_points"]), 0, "and the top band has nothing after it")


func test_a_million_points_produce_a_sane_tier_and_a_sane_balance() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	seed_points(subject, rule, 1_000_000)
	assert_eq(
		tier_of(subject, rule), 2, "a million points is the top band, not an index off the end"
	)
	assert_eq(int(rule.tier_for(subject)[&"tiers"]), 3, "and the System still authored three")
	assert_eq(String(rule.tier_for(subject)[&"tier_name"]), "embodied", "the top band has its name")
	assert_eq(
		bool(rule.boards(subject)[2].get("repeatable", true)), false, "and the board still renders"
	)
	farm(subject, rule, 4)
	assert_eq(balance_of(subject, rule), 4.0, "a counter that far out has not broken the money")
	var summary := DoctrineApi.summary(subject)
	var systems: Dictionary = summary["systems"]
	var view: Dictionary = systems[String(IRON_BELL)]
	assert_eq(int(view["points"]), 1000000, "and the read model carries it")
	assert_eq(
		DoctrineRule.is_primitive_payload(summary),
		true,
		"a million-level counter is still primitives-only"
	)


func test_a_named_system_has_a_save_key_and_an_unnamed_one_has_none() -> void:
	var named := iron_bell()
	assert_eq(
		String(named.data_key()),
		"doctrine/way_of_the_iron_bell",
		"one spelling, derived from the id"
	)
	var unnamed := iron_bell()
	unnamed.id = &""
	assert_eq(
		String(unnamed.data_key()), "", "an unnamed System has no key, so two cannot share one"
	)
	assert_eq(
		bool(DoctrineApi.attach(unnamed)["ok"]),
		false,
		"and an unnamed System is refused rather than persisted somewhere arbitrary"
	)


func test_two_named_systems_never_share_a_dictionary() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	DoctrineApi.join(subject, silent.system_id())
	farm(subject, iron, 3)
	var state := DoctrineApi.state(subject)
	var iron_ledger: Dictionary = state[String(IRON_BELL)]
	var silent_ledger: Dictionary = state[String(SILENT_BELL)]
	assert_ne(str(iron_ledger), str(silent_ledger), "two Systems, two ledgers, one save")
	assert_eq(
		float(silent_ledger[DoctrineLedger.KEY_BALANCE]),
		0.0,
		"and earning into one left the other alone"
	)


func test_the_read_models_are_primitives_only_and_empty_without_an_actor() -> void:
	var rule := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(rule)
	DoctrineApi.join(subject, silent.system_id())
	farm(subject, rule, 2)
	assert_eq(DoctrineRule.is_primitive_payload(DoctrineApi.summary(subject)), true, "summary")
	assert_eq(DoctrineRule.is_primitive_payload(DoctrineApi.state(subject)), true, "state")
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineApi.available(subject)[0]),
		true,
		"one available row"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineApi.rules()[0]), true, "one declared rule row"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineApi.boards(subject, rule.system_id())[0]),
		true,
		"one board row"
	)
	assert_eq(DoctrineApi.summary(null), {}, "and the read model is {} with no actor")


func test_summary_counts_systems_and_joins_and_publishes_the_pool_vocabulary() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	var summary := DoctrineApi.summary(subject)
	assert_eq(int(summary["system_count"]), 2, "both Systems are registered")
	assert_eq(int(summary["joined_count"]), 1, "and only one is joined")
	assert_eq(
		str(summary["pools"]), str(["insight", "rage"]), "the declared pools ride the read model"
	)
	assert_eq(String(summary["actor_id"]), String(subject.id), "and the actor it is about")


func test_available_reports_every_system_and_whether_it_was_joined() -> void:
	var iron := register(iron_bell())
	var silent := register(silent_bell())
	var subject := joined_actor(iron)
	var rows := DoctrineApi.available(subject)
	assert_eq(rows.size(), 2, "a join screen draws the whole shelf")
	assert_eq(bool(rows[0]["joined"]), true, "the joined System says so")
	assert_eq(bool(rows[1]["joined"]), false, "and the other does not")
	assert_eq(int(rows[0]["row_count"]), 3, "with the row count it would offer")
	assert_eq(
		String(rows[0]["data_key"]), String(iron.data_key()), "and the key its state lives under"
	)
	assert_eq(String(silent.display_name()), "Way of the Silent Bell", "and its name")


func test_a_saved_ledger_round_trips_through_the_actor_save_path() -> void:
	var rule := register(iron_bell())
	var subject := joined_actor(rule)
	farm(subject, rule, 7)
	# The SHIPPED save path, because it is the one that re-derives the `StringName` outer key
	# a JSON round trip flattens to a `String` — which is exactly the hazard the ledger's
	# String-key rule exists for.
	var restored := Actor.from_dict(subject.to_dict())
	assert_eq(balance_of(restored, rule), 7.0, "the balance survives a save and a load")
	assert_eq(_is_joined(restored, rule), true, "and so does the opt-in")
	assert_eq(
		DoctrineLedger.balance(restored.get_module_data(rule.data_key()), INSIGHT),
		7.0,
		"and the per-pool map agrees, because both are keyed the same way"
	)
	assert_eq(
		int(DoctrineApi.summary(restored)["joined_count"]), 1, "the read model reads a loaded actor"
	)
