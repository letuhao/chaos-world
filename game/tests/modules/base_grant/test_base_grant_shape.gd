extends "res://tests/modules/base_grant/base_grant_fixture_kit.gd"

## What `base_grant` PROMISES: the read model, the closed vocabularies, and the three
## structural pins. The gates themselves are in `test_base_grant.gd` — this file answers
## "what does the module declare", that one answers "what does the verb do".
##
## The pins are source scans because `tools/arch` cannot see a call it does not parse and
## no value assertion can see a copy. That is the same reason `test_sect_no_power.gd` pins
## a base write structurally, and the same reason `tests/core/test_realm_rate.gd` reads
## source rather than values.


func setup() -> void:
	expect_assertions(1)


func _request(overrides: Dictionary = {}) -> Dictionary:
	var base := {"source": "doctrine/water_margin/row_1", "gains": {"physique": 1.0}}
	# `keys()` is snapshotted by the `for` and the body writes to `base`, never to the map
	# it walks (INC-0002).
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


# --- preview, state, summary -------------------------------------------------


func test_preview_answers_the_same_gate_and_writes_nothing() -> void:
	var actor := hero()
	var merit := pool(actor, &"merit", 10.0)
	var before := base_snapshot(actor)
	var paid := BaseGrantApi.preview(actor, _request({"cost_pool": "merit", "cost_amount": 1.0}))
	assert_eq(bool(paid["ok"]), true, "a payable grant previews as payable")
	assert_eq(bool(paid["applied"]), false, "and preview never applies")
	assert_eq(base_snapshot(actor), before, "and it wrote nothing to the actor")
	assert_eq(merit.current, 10.0, "and charged nothing")
	var short := BaseGrantApi.preview(actor, _request({"cost_pool": "merit", "cost_amount": 99.0}))
	assert_eq(
		String(short["reason"]),
		BaseGrantApi.REASON_INSUFFICIENT,
		"preview refuses what grant would refuse"
	)
	assert_eq(bool(short["applied"]), false, "and reports no application")


func test_preview_and_grant_never_disagree_because_there_is_one_gate() -> void:
	# Not a style claim: a caller that greys out a row must be greying out the row that
	# would actually be refused. This is the split dev cycle's read side, and it holds only
	# because both verbs are one `BaseGrantRequest.evaluate`.
	var actor := hero()
	pool(actor, &"merit", 5.0)
	var cases: Array[Dictionary] = [
		_request(),
		_request({"gains": {"nope": 1.0}}),
		_request({"cost_pool": "merit", "cost_amount": 1.0}),
		_request({"cost_pool": "merit", "cost_amount": 50.0}),
		_request({"gains": {"physique": 1.0}, "costs": {"agility": 99.0}}),
	]
	for case in cases:
		var previewed := BaseGrantApi.preview(actor, case)
		var granted := BaseGrantApi.grant(actor, case)
		var label := JSON.stringify(case["gains"])
		assert_eq(bool(granted["ok"]), bool(previewed["ok"]), "same verdict for %s" % [label])
		assert_eq(
			String(granted["reason"]), String(previewed["reason"]), "same reason for %s" % [label]
		)


func test_state_and_summary_are_the_read_model_and_empty_for_no_actor() -> void:
	var actor := hero()
	assert_eq(BaseGrantApi.state(null), {}, "no actor is 'does not exist', not a failure")
	assert_eq(BaseGrantApi.summary(null), {}, "and the same for the read model")
	pool(actor, &"merit", 10.0)
	BaseGrantApi.grant(actor, _request({"costs": {"spirit": 1.0}}))
	var read := BaseGrantApi.summary(actor)
	assert_eq(int(read["grants_max"]), BaseGrantApi.MAX_GRANTS_PER_SOURCE, "the bound is published")
	assert_eq(
		int((read["grants_spent"] as Dictionary)["doctrine/water_margin/row_1"]),
		1,
		"one press is recorded under its source"
	)
	assert_eq(
		(read["reasons"] as Array).size(),
		BaseGrantApi.REASONS.size(),
		"and the closed reason set rides along so a panel validates against one copy"
	)


func test_the_press_count_survives_a_save_round_trip() -> void:
	# The rate bound is only a bound if it survives a reload; a counter recomputed from
	# nothing is theatre a save/load cycle walks straight through.
	var actor := hero()
	pool(actor, &"merit", float(BaseGrantApi.MAX_GRANTS_PER_SOURCE) * 4.0)
	var press := {"gains": {"physique": 1.0}, "cost_pool": "merit", "cost_amount": 1.0}
	for index in BaseGrantApi.MAX_GRANTS_PER_SOURCE:
		var request := press.duplicate()
		request["source"] = "t/save"
		BaseGrantApi.grant(actor, request)
	var reloaded := Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())))
	var restored := BaseGrantApi.summary(reloaded)
	assert_eq(
		int((restored["grants_spent"] as Dictionary)["t/save"]),
		BaseGrantApi.MAX_GRANTS_PER_SOURCE,
		"every press came back, keyed by source"
	)
	var over_request := press.duplicate()
	over_request["source"] = "t/save"
	assert_eq(
		String(BaseGrantApi.grant(reloaded, over_request)["reason"]),
		BaseGrantApi.REASON_BUDGET_SPENT,
		"so a reloaded save still cannot pump one source"
	)


func test_every_refusal_carries_every_answer_key() -> void:
	# One payload shape for the case a caller cares about: a screen reading
	# `answer["applied"]` on a refusal must not read a missing key.
	var actor := hero()
	pool(actor, &"merit", 1.0)
	var cases: Array[Dictionary] = [
		{},
		_request(),
		_request({"source": ""}),
		_request({"gains": {"nope": 1.0}}),
		_request({"gains": {"physique": 0.0}}),
		_request({"gains": {"physique": 1.0}, "costs": {"agility": 99.0}}),
		_request({"cost_pool": "mreit", "cost_amount": 1.0}),
		_request({"cost_pool": "merit", "cost_amount": 50.0}),
	]
	for case in cases:
		var answer := BaseGrantApi.grant(actor, case)
		assert_eq(bool(answer["ok"]), false, "this case refuses: %s" % [JSON.stringify(case)])
		for key in BaseGrantApi.ANSWER_KEYS:
			assert_eq(
				answer.has(key),
				true,
				"refusal %s carries %s" % [String(answer["reason"]), String(key)]
			)
		assert_eq(answer.has("plan"), false, "and a refusal carries no write plan to apply")


func test_the_request_vocabulary_is_exactly_what_is_documented() -> void:
	# A key a caller may speak that the module does not read is a silent no-op, which is
	# the failure `ItemUse._refuse_read_only` exists to prevent on the other side.
	assert_eq(
		BaseGrantApi.REQUEST_KEYS,
		[&"source", &"gains", &"costs", &"cost_pool", &"cost_amount"] as Array[StringName],
		"the request vocabulary is closed"
	)
	# The closed reason set is what a panel validates against, so two reasons sharing a
	# string would make one of them unroutable. Nothing forces uniqueness but this.
	var unique := {}
	# `REASONS` is snapshotted by the `for` and the body writes to `unique`, never to the
	# array it walks (INC-0002).
	for reason in BaseGrantApi.REASONS:
		unique[reason] = true
	assert_eq(
		unique.size(),
		BaseGrantApi.REASONS.size(),
		"every reason is a distinct string, so none of them is unroutable"
	)
	for reason in BaseGrantApi.REASONS:
		assert_ne(reason, "", "no reason is the empty string — 'refused' is never ''")


# --- the structural pins -----------------------------------------------------


func test_the_module_owns_no_clock_and_no_scene_tree() -> void:
	# DEF-0111: a System or a board is exactly the thing that wants a tick, and an
	# institution that owns one accrues on wall time. A grant is one caller-initiated press.
	var code := _module_code()
	for forbidden in ["Time.get_ticks", "_process(", "get_tree(", "Engine."]:
		assert_eq(
			code.contains(forbidden),
			false,
			"base_grant must not reach for %s (DEF-0111)" % forbidden
		)


func test_the_module_declares_no_magnitude() -> void:
	# ADR 0273: no method may take a realm id and return a multiplier, because there is
	# nowhere to put a fourth magnitude table. ADR 0050's rule that a rate must never
	# track a magnitude rules out the shared rate curve here too.
	var code := _module_code()
	for forbidden in ["RealmRate", "RealmDefaults", "RealmScaling", "realm_power", "pow("]:
		assert_eq(
			code.contains(forbidden),
			false,
			"base_grant must not compute a rate from a realm (%s)" % forbidden
		)
	assert_eq(
		BaseGrantApi.REQUEST_KEYS.has(&"realm"),
		false,
		"and the request vocabulary has no realm key to put one in"
	)


func test_the_module_writes_a_base_attribute_only_through_core() -> void:
	# The one write this module may make, pinned as a COUNT rather than an absence so a
	# second writer added later is a visible change to the number, not a silent one.
	assert_eq(
		_module_code().count("set_base("),
		1,
		"exactly one set_base call site, inside _apply — a second writer is a second place to gate"
	)


func test_the_module_owns_no_second_claim_shape() -> void:
	# ADR 0066's failure mode is a second copy of a shape, and the ledger is the only
	# persisted state here — so it must have exactly one normaliser.
	var code := _module_code()
	assert_eq(
		code.count("static func normalize("),
		1,
		"one normaliser, in the ledger; a second would be a second claim on the key"
	)


## The CODE of every file in this module, comments stripped.
##
## Comments are stripped because a scan that matches its own documentation is blind: these
## modules' docblocks NAME `Time.get_ticks*`, `_process` and `get_tree()` in order to say
## they call none of them, so a raw-text scan fails on the very prose that records the
## rule. Same trap `test_no_stranded_mutation.gd` is built around, and the same fix —
## match the shape you mean, not the string you typed.
func _module_code() -> String:
	var out := ""
	# A fixed list of the module's own three files, snapshotted by the `for` itself and
	# never appended to, so the walk terminates on the constant (INC-0002).
	for file_name in ["api.gd", "base_grant_request.gd", "base_grant_ledger.gd"]:
		var handle := FileAccess.open(
			"res://src/modules/base_grant/%s" % file_name, FileAccess.READ
		)
		if handle == null:
			continue
		for line in handle.get_as_text().split("\n"):
			if not line.strip_edges().begins_with("#"):
				out += line + "\n"
		handle.close()
	return out
