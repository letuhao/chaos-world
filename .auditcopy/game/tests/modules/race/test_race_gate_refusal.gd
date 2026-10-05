extends TestCase

## A requirement the module cannot read must **refuse closed and name itself**, never
## open a door it cannot interpret. Refuse-with-cause is the house rule: malformed
## content is a content bug, not a player being told no, so a refusal is distinct from an
## ordinary unmet and carries its own `reason`.

const STONE := &"t_stone"
const TIDE := &"t_tide"
const BASE := &"t_base"

const UNMET_KEYS := ["kind", "id", "required", "actual", "label"]


func setup() -> void:
	(
		RaceFixtureCatalog
		. install(
			[
				RaceFixtureCatalog.capped(STONE, &"mind_cultivation", 8, Stat.PHYSIQUE),
				RaceFixtureCatalog.closed(TIDE, &"body_cultivation", 0.6),
				RaceFixtureCatalog.closed(BASE, &"mind_cultivation", 0.2),
			],
			BASE
		)
	)


func teardown() -> void:
	RaceFixtureCatalog.teardown()


func _born(race_id: StringName, rank_id: StringName = &"") -> Actor:
	var actor := Actor.new(&"body", {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	if rank_id != &"":
		actor.set_path(PathState.new(PathState.BODY, rank_id))
	return actor


func _unmet_entry(verdict: Dictionary, index: int) -> Dictionary:
	return (verdict["unmet"] as Array)[index]


# --- An unknown verb ---------------------------------------------------------


func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	for verb in [&"is_favourite_race", &"is", &"all_of_all", &"IS_RACE"]:
		var verdict := RaceApi.unmet(_born(STONE), {"verb": verb, "id": String(STONE)})
		assert_eq(bool(verdict["ok"]), false, "'%s' never opens a door" % str(verb))
		assert_eq(
			String(verdict["reason"]), "unknown_verb", "'%s' is refused as unknown" % str(verb)
		)
		assert_eq(String(_unmet_entry(verdict, 0)["kind"]), "gate", "a refusal is about the gate")
		assert_eq(
			String(_unmet_entry(verdict, 0)["label"]).contains(String(verb)),
			true,
			"and names the verb it read"
		)


func test_an_unknown_verb_is_refused_even_with_nothing_else_to_go_on() -> void:
	var verdict := RaceApi.unmet(_born(STONE), {"verb": &"not_a_verb"})
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unknown_verb", "as unknown")


# --- A malformed requirement -------------------------------------------------


func test_a_requirement_with_no_verb_refuses_closed() -> void:
	for requirement in [{"id": String(STONE)}, {"of": []}, {"kind": "race"}]:
		var verdict := RaceApi.unmet(_born(STONE), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")
		assert_eq(
			String(_unmet_entry(verdict, 0)["label"]),
			"A gate names no verb.",
			"with the reason in the label"
		)


func test_a_verb_that_names_no_id_refuses_rather_than_matching_nothing() -> void:
	for requirement in [
		{"verb": &"is_race"},
		{"verb": &"race_allows_path"},
		{"verb": &"has_trait"},
	]:
		var verdict := RaceApi.unmet(_born(STONE), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


func test_a_negative_ceiling_ordinal_refuses() -> void:
	var verdict := RaceApi.unmet(_born(STONE), {"verb": &"realm_ceiling", "at": -1})
	assert_eq(String(verdict["reason"]), "malformed", "a ceiling needs a non-negative ordinal")


func test_a_malformed_child_poisons_the_whole_composite() -> void:
	var poisoned := {
		"verb": &"all_of",
		"of": [{"verb": &"is_race", "id": String(STONE)}, {"id": String(TIDE)}],
	}
	var verdict := RaceApi.unmet(_born(STONE), poisoned)
	assert_eq(bool(verdict["ok"]), false, "the unreadable child fails the composite")
	assert_eq(String(verdict["reason"]), "malformed", "and the cause survives the nesting")


func test_an_unknown_child_poisons_an_any_of_too() -> void:
	var poisoned := {
		"verb": &"any_of",
		"of":
		[
			{"verb": &"is_race", "id": String(STONE)},
			{"verb": &"is_raceish", "id": String(TIDE)},
		],
	}
	var verdict := RaceApi.unmet(_born(STONE), poisoned)
	assert_eq(bool(verdict["ok"]), false, "a sibling that passed never satisfies it")
	assert_eq(String(verdict["reason"]), "unknown_verb", "and the cause survives the nesting")


func test_a_composite_with_no_children_refuses_rather_than_defaulting_open() -> void:
	for requirement in [
		{"verb": &"all_of"},
		{"verb": &"all_of", "of": []},
		{"verb": &"any_of", "of": "not an array"},
		{"verb": &"none_of", "of": []},
	]:
		var verdict := RaceApi.unmet(_born(STONE), requirement)
		assert_eq(bool(verdict["ok"]), false, "childless composite %s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


# --- The verdict shape -------------------------------------------------------


func test_a_verdict_is_always_ok_reason_unmet_and_the_facade_adds_nothing() -> void:
	var actor := _born(STONE, &"primordial_origin")
	var cases := [
		{},
		{"verb": &"is_race", "id": String(STONE)},
		{"verb": &"is_race", "id": String(TIDE)},
		{"verb": &"race_allows_path", "id": String(PathState.MIND)},
		{"verb": &"realm_ceiling", "at": 4},
		{"verb": &"teleported"},
		{"id": String(STONE)},
	]
	for requirement in cases:
		var verdict := RaceGate.evaluate(actor, requirement)
		assert_eq(verdict.has("ok"), true, "ok is present for %s" % [requirement])
		assert_eq(verdict.has("reason"), true, "reason is present for %s" % [requirement])
		assert_eq(verdict.has("unmet"), true, "unmet is present for %s" % [requirement])
		var ok := bool(verdict["ok"])
		assert_eq(
			(verdict["unmet"] as Array).is_empty(),
			ok,
			"a closed gate reports, an open one does not"
		)
		assert_eq(RaceApi.unmet(actor, requirement), verdict, "the facade adds nothing")


func test_every_unmet_entry_has_exactly_the_five_keys_a_panel_needs() -> void:
	var actor := _born(STONE, &"primordial_origin")
	var cases := [
		{"verb": &"is_race", "id": String(TIDE)},
		{"verb": &"race_allows_path", "id": String(PathState.MIND)},
		{"verb": &"has_trait", "id": String(&"race:t_tide")},
		{"verb": &"realm_ceiling", "at": 4},
		{"verb": &"teleported"},
		{"id": String(STONE)},
		{"verb": &"all_of", "of": []},
	]
	for requirement in cases:
		var unmet := RaceGate.evaluate(actor, requirement)["unmet"] as Array
		assert_eq(unmet.is_empty(), false, "%s reports something" % [requirement])
		for entry in unmet:
			assert_eq(entry.keys().size(), UNMET_KEYS.size(), "%s has no extra key" % [requirement])
			for key in UNMET_KEYS:
				assert_eq(entry.has(key), true, "%s carries '%s'" % [requirement, key])
			assert_ne(String(entry["label"]), "", "and every label has text to render")


func test_a_closed_gate_never_reports_an_empty_unmet_list() -> void:
	var actor := _born(STONE, &"primordial_origin")
	for requirement in [
		{"verb": &"is_race", "id": String(TIDE)},
		{"verb": &"race_allows_path", "id": String(PathState.MIND)},
		{"verb": &"realm_ceiling", "at": 2},
		{"verb": &"teleported"},
	]:
		var verdict := RaceApi.unmet(actor, requirement)
		assert_eq(bool(verdict["ok"]), false, "%s is closed" % [requirement])
		assert_eq((verdict["unmet"] as Array).is_empty(), false, "and says why")
