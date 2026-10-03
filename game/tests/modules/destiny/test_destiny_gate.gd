extends TestCase

## A gate requirement is authored data, never code: an empty dictionary, or a map
## naming exactly one of six verbs. These assert each verb passes and fails
## correctly on its own, that the three composites nest and report every unmet
## child, and that a requirement the module cannot read refuses closed and names
## itself — including one nested inside a composite, which poisons the whole thing.

const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const CHOSEN := &"t_chosen_one"
const RISE := &"t_rise_of_the_revenants"
const DUELS := &"duels_won"
const OATHS := &"oaths_taken"

## The one shape an unmet entry may have: enough for a panel to render a reason it
## did not have to invent.
const UNMET_KEYS := ["kind", "id", "required", "actual", "label"]


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
			],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				DestinyFixtureCatalog.plain_destiny(RISE),
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


## An actor holding one fate, one destiny and a counter of three, so every verb
## has both a passing and a failing question to ask.
func _holder() -> Actor:
	var actor := Actor.new(&"holder", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.record(actor, DUELS, 3)
	return actor


func _verdict(actor: Actor, requirement: Dictionary) -> Dictionary:
	return DestinyApi.gate(actor, requirement)


# --- Ungated -----------------------------------------------------------------


func test_an_empty_requirement_is_ungated_and_always_open() -> void:
	for actor in [_holder(), null]:
		var verdict := _verdict(actor, {})
		assert_eq(bool(verdict["ok"]), true, "empty means open")
		assert_eq(String(verdict["reason"]), "", "with nothing to report")
		assert_eq(verdict["unmet"] as Array, [], "and no unmet entry")


# --- The six verbs, in isolation ---------------------------------------------


func test_has_fate_passes_for_a_held_fate_and_fails_for_one_that_is_not() -> void:
	var actor := _holder()
	var held := _verdict(actor, {"verb": &"has_fate", "id": String(OATH)})
	assert_eq(bool(held["ok"]), true, "held passes")
	var missed := _verdict(actor, {"verb": &"has_fate", "id": String(PLEDGE)})
	assert_eq(bool(missed["ok"]), false, "not held fails")
	assert_eq(String(missed["reason"]), "unmet", "and is an ordinary unmet, not a refusal")
	var entry := _unmet_entry(missed, 0)
	assert_eq(String(entry["kind"]), "fate", "the entry names the kind")
	assert_eq(String(entry["id"]), String(PLEDGE), "and the id")
	assert_eq(bool(entry["required"]), true, "it is required")
	assert_eq(bool(entry["actual"]), false, "and not held")
	assert_eq(
		String(entry["label"]), "Requires the fate 't_blood_pledge'", "with a renderable label"
	)


func test_has_destiny_passes_for_a_held_destiny_and_fails_for_one_that_is_not() -> void:
	var actor := _holder()
	var held := _verdict(actor, {"verb": &"has_destiny", "id": String(CHOSEN)})
	assert_eq(bool(held["ok"]), true, "held passes")
	var missed := _verdict(actor, {"verb": &"has_destiny", "id": String(RISE)})
	assert_eq(bool(missed["ok"]), false, "not held fails")
	var entry := _unmet_entry(missed, 0)
	assert_eq(String(entry["kind"]), "destiny", "the entry names the kind")
	assert_eq(
		String(entry["label"]), "Requires the destiny 't_rise_of_the_revenants'", "with a label"
	)


func test_a_counter_gate_passes_only_once_the_recorded_value_reaches_the_need() -> void:
	var actor := _holder()
	assert_eq(
		bool(_verdict(actor, {"verb": &"counter", "id": String(DUELS), "need": 1})["ok"]),
		true,
		"met"
	)
	assert_eq(
		bool(_verdict(actor, {"verb": &"counter", "id": String(DUELS), "need": 3})["ok"]),
		true,
		"exactly met"
	)
	var missed := _verdict(actor, {"verb": &"counter", "id": String(DUELS), "need": 4})
	assert_eq(bool(missed["ok"]), false, "one short of the need")
	var entry := _unmet_entry(missed, 0)
	assert_eq(String(entry["kind"]), "counter", "the entry names the kind")
	assert_eq(int(entry["required"]), 4, "required is the need")
	assert_eq(int(entry["actual"]), 3, "actual is the recorded value")
	assert_eq(String(entry["label"]), "'duels_won' 3 of 4", "the label says both numbers")
	assert_eq(
		bool(_verdict(actor, {"verb": &"counter", "id": String(OATHS), "need": 1})["ok"]),
		false,
		"a counter that was never recorded is zero"
	)


func test_a_gate_reads_only_the_ledger_and_never_a_stat_or_a_trait() -> void:
	var actor := _holder()
	# The fate is on the actor's trait mirror and moved its derived stat, and
	# neither is a gate condition: only holding counts.
	assert_eq(actor.traits.has(DestinyState.trait_for(OATH)), true, "the fate is mirrored")
	var verdict := _verdict(actor, {"verb": &"has_fate", "id": String(&"destiny:t_oath_breaker")})
	assert_eq(bool(verdict["ok"]), false, "a namespaced source id is not a fate id")
	assert_eq(
		bool(_verdict(null, {"verb": &"has_fate", "id": String(OATH)})["ok"]),
		false,
		"no actor holds nothing"
	)


# --- The composites ----------------------------------------------------------


func test_all_of_requires_every_child() -> void:
	var actor := _holder()
	var all_held := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"has_fate", "id": String(OATH)},
			{"verb": &"has_destiny", "id": String(CHOSEN)},
		]
	}
	assert_eq(bool(_verdict(actor, all_held)["ok"]), true, "both held")
	all_held["of"].append({"verb": &"has_fate", "id": String(PLEDGE)})
	var missed := _verdict(actor, all_held)
	assert_eq(bool(missed["ok"]), false, "one unmet child fails the whole")
	assert_eq((missed["unmet"] as Array).size(), 1, "and the unmet list is exactly that child")
	assert_eq(String(_unmet_entry(missed, 0)["id"]), String(PLEDGE), "named")


func test_any_of_requires_one_child_and_lists_only_the_children_that_failed() -> void:
	var actor := _holder()
	var one_held := {
		"verb": &"any_of",
		"of":
		[
			{"verb": &"has_fate", "id": String(PLEDGE)},
			{"verb": &"has_destiny", "id": String(CHOSEN)},
		]
	}
	assert_eq(bool(_verdict(actor, one_held)["ok"]), true, "one held child is enough")
	assert_eq(
		(_verdict(actor, one_held)["unmet"] as Array).size(), 0, "and nothing is reported unmet"
	)
	var none_held := {
		"verb": &"any_of",
		"of":
		[
			{"verb": &"has_fate", "id": String(PLEDGE)},
			{"verb": &"has_destiny", "id": String(RISE)},
		]
	}
	var missed := _verdict(actor, none_held)
	assert_eq(bool(missed["ok"]), false, "no held child fails the whole")
	assert_eq((missed["unmet"] as Array).size(), 2, "both children are reported unmet")


func test_none_of_requires_that_no_child_is_held() -> void:
	var actor := _holder()
	var none_held := {
		"verb": &"none_of",
		"of": [{"verb": &"has_destiny", "id": String(RISE)}],
	}
	assert_eq(bool(_verdict(actor, none_held)["ok"]), true, "an unmet child satisfies none_of")
	var one_held := {
		"verb": &"none_of",
		"of":
		[
			{"verb": &"has_destiny", "id": String(CHOSEN)},
			{"verb": &"has_destiny", "id": String(RISE)},
		]
	}
	assert_eq(bool(_verdict(actor, one_held)["ok"]), false, "a single held child fails none_of")


func test_the_composites_nest_to_any_depth() -> void:
	var actor := _holder()
	var nested := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"has_fate", "id": String(OATH)},
			{
				"verb": &"any_of",
				"of":
				[
					{
						"verb": &"all_of",
						"of":
						[
							{"verb": &"counter", "id": String(DUELS), "need": 3},
							{
								"verb": &"none_of",
								"of": [{"verb": &"has_destiny", "id": String(RISE)}]
							},
						]
					},
					{"verb": &"has_destiny", "id": String(RISE)},
				]
			},
		]
	}
	assert_eq(bool(_verdict(actor, nested)["ok"]), true, "the deep branch passes")
	# The same tree with the inner counter one short: the failure propagates all
	# the way out, naming the leaf that could not be satisfied. The enclosing
	# `any_of` also reports the branch it could not use, so the root carries BOTH
	# leaves that failed — a panel shows everything still outstanding rather than
	# stopping at the first.
	nested["of"][1]["of"][0]["of"][0]["need"] = 4
	var missed := _verdict(actor, nested)
	assert_eq(bool(missed["ok"]), false, "the leaf failure fails the root")
	assert_eq((missed["unmet"] as Array).size(), 2, "both failing leaves are reported")
	var entry := _unmet_entry(missed, 0)
	assert_eq(String(entry["kind"]), "counter", "reported from the leaf")
	assert_eq(int(entry["required"]), 4, "with the need it wanted")
	assert_eq(int(entry["actual"]), 3, "and what it had")
	assert_eq(
		String(_unmet_entry(missed, 1)["id"]),
		String(RISE),
		"the unusable any_of branch is named as well"
	)


# --- Refusal: a requirement the module cannot read ---------------------------


func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	for verb in [&"has_fate_but_modified", &"has", &"all_of_all", &"ANY_OF"]:
		var verdict := _verdict(_holder(), {"verb": verb, "id": String(OATH)})
		assert_eq(bool(verdict["ok"]), false, "'%s' never opens a door" % verb)
		assert_eq(String(verdict["reason"]), "unknown_verb", "'%s' is refused as unknown" % verb)
		var entry := _unmet_entry(verdict, 0)
		assert_eq(String(entry["kind"]), "gate", "a refusal is about the gate itself")
		assert_eq(String(entry["label"]).contains(String(verb)), true, "and names the verb it read")
	assert_eq(
		bool(_verdict(_holder(), {"verb": &"not_a_verb"})["ok"]),
		false,
		"an unknown verb is refused even with nothing else to go on"
	)


func test_a_requirement_with_no_verb_refuses_closed() -> void:
	for requirement in [
		{"id": String(OATH)},
		{"of": []},
		{"kind": "fate", "id": String(OATH)},
	]:
		var verdict := _verdict(_holder(), requirement)
		assert_eq(bool(verdict["ok"]), false, "verb-less requirement %s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")
		assert_eq(
			String(_unmet_entry(verdict, 0)["label"]),
			"A gate names no verb.",
			"with the reason in the label"
		)


func test_a_verb_that_names_no_id_refuses_rather_than_matching_nothing() -> void:
	for requirement in [{"verb": &"has_fate"}, {"verb": &"has_destiny"}, {"verb": &"counter"}]:
		var verdict := _verdict(_holder(), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")
	var no_need := _verdict(_holder(), {"verb": &"counter", "id": String(DUELS), "need": 0})
	assert_eq(String(no_need["reason"]), "malformed", "a counter gate needs a positive need")
	assert_eq(
		bool(_verdict(_holder(), {"verb": &"counter", "id": String(DUELS), "need": -1})["ok"]),
		false,
		"so does a negative one"
	)


func test_a_malformed_child_poisons_the_whole_composite() -> void:
	var actor := _holder()
	var poisoned := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"has_fate", "id": String(OATH)},
			{"id": String(PLEDGE)},
		],
	}
	var verdict := _verdict(actor, poisoned)
	# A nested gate that cannot be read is never treated as satisfied, so it is
	# never silently satisfied by a sibling that was.
	assert_eq(bool(verdict["ok"]), false, "the unreadable child fails the composite")
	assert_eq(String(verdict["reason"]), "malformed", "and the cause survives the nesting")
	var unknown_child := {
		"verb": &"any_of",
		"of":
		[
			{"verb": &"has_destiny", "id": String(CHOSEN)},
			{"verb": &"has_fateish", "id": String(OATH)}
		],
	}
	var unknown := _verdict(actor, unknown_child)
	assert_eq(bool(unknown["ok"]), false, "an unknown verb poisons an any_of too")
	assert_eq(String(unknown["reason"]), "unknown_verb", "with its own cause")


func test_a_composite_with_no_children_refuses_rather_than_defaulting_open() -> void:
	for requirement in [
		{"verb": &"all_of"},
		{"verb": &"all_of", "of": []},
		{"verb": &"any_of", "of": "not an array"},
		{"verb": &"none_of", "of": []},
	]:
		var verdict := _verdict(_holder(), requirement)
		assert_eq(bool(verdict["ok"]), false, "childless composite %s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


# --- The verdict and the unmet entry shapes -----------------------------------


func test_a_verdict_is_always_ok_reason_unmet() -> void:
	var cases := [
		{},
		{"verb": &"has_fate", "id": String(OATH)},
		{"verb": &"has_fate", "id": String(PLEDGE)},
		{"verb": &"counter", "id": String(DUELS), "need": 4},
		{"verb": &"none_of", "of": [{"verb": &"has_fate", "id": String(PLEDGE)}]},
		{"verb": &"teleported"},
		{"id": String(OATH)},
	]
	var actor := _holder()
	for requirement in cases:
		var verdict := DestinyGate.evaluate(actor, requirement)
		assert_eq(verdict.has("ok"), true, "ok is present for %s" % [requirement])
		assert_eq(verdict.has("reason"), true, "reason is present for %s" % [requirement])
		assert_eq(verdict.has("unmet"), true, "unmet is present for %s" % [requirement])
		var unmet := verdict["unmet"] as Array
		# The two halves of a verdict agree: a gate is either open with nothing to
		# report, or closed with at least one entry a panel can render. There is
		# no third state, so a caller never has to guess which half to believe.
		var ok := bool(verdict["ok"])
		assert_eq(
			unmet.is_empty(),
			ok,
			(
				"a closed gate always has something to report, and an open one nothing to (%s)"
				% [requirement]
			)
		)
		if ok:
			assert_eq(String(verdict["reason"]), "", "an open gate reports no reason")
		else:
			assert_ne(String(verdict["reason"]), "", "a closed gate always names a reason")
		# The facade reports exactly what the gate decided.
		assert_eq(
			DestinyApi.gate(actor, requirement),
			verdict,
			"the facade adds nothing to %s" % [requirement]
		)


func test_every_unmet_entry_has_exactly_the_five_keys_a_panel_needs() -> void:
	var actor := _holder()
	var cases := [
		{"verb": &"has_fate", "id": String(PLEDGE)},
		{"verb": &"has_destiny", "id": String(RISE)},
		{"verb": &"counter", "id": String(DUELS), "need": 4},
		{"verb": &"teleported", "id": String(OATH)},
		{"id": String(OATH)},
		{"verb": &"all_of", "of": []},
	]
	for requirement in cases:
		var unmet := DestinyGate.evaluate(actor, requirement)["unmet"] as Array
		assert_eq(unmet.is_empty(), false, "%s reports something" % [requirement])
		for entry in unmet:
			assert_eq(entry.keys().size(), UNMET_KEYS.size(), "%s has no extra key" % [requirement])
			for key in UNMET_KEYS:
				assert_eq(entry.has(key), true, "%s carries '%s'" % [requirement, key])
			assert_ne(String(entry["label"]), "", "and every label has text to render")


## The nth unmet entry of a verdict.
func _unmet_entry(verdict: Dictionary, index: int) -> Dictionary:
	return (verdict["unmet"] as Array)[index]
