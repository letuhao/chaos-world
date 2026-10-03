extends TestCase

## A requirement the module cannot read must **refuse closed and name itself**, never
## open a door it cannot interpret. Refuse-with-cause is the house rule: malformed
## content is a content bug, not a player being told no, so a refusal is distinct from an
## ordinary unmet and carries its own `reason`.
##
## Also the open verbs, so the refusal tests below are known to be refusing a *closed*
## set rather than the only set.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"

const UNMET_KEYS := ["kind", "id", "required", "actual", "label"]


func setup() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE), ClanFixtureCatalog.open(RIVAL)])


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _member(standing: int = 40) -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, 0.5)
	ClanApi.join(actor, HOUSE, standing)
	return actor


func _grant_rank(actor: Actor, rank: StringName) -> void:
	var ledger := ClanApi.state(actor)
	ledger["rank"] = String(rank)
	actor.set_module_data(ClanApi.MODULE_KEY, ledger)
	ClanProjection.apply(actor, ledger)


func _unmet_entry(verdict: Dictionary, index: int) -> Dictionary:
	return (verdict["unmet"] as Array)[index]


# --- The seven verbs ---------------------------------------------------------


func test_is_clan_matches_the_clan_the_actor_belongs_to() -> void:
	var actor := _member()
	assert_eq(bool(ClanApi.unmet(actor, {"verb": &"is_clan", "id": "t_house"})["ok"]), true, "yes")
	assert_eq(bool(ClanApi.unmet(actor, {"verb": &"is_clan", "id": "t_rival"})["ok"]), false, "no")


func test_has_rank_matches_the_position_the_actor_holds() -> void:
	var actor := _member()
	assert_eq(bool(ClanApi.unmet(actor, {"verb": &"has_rank", "id": "outer"})["ok"]), true, "outer")
	assert_eq(bool(ClanApi.unmet(actor, {"verb": &"has_rank", "id": "head"})["ok"]), false, "head")
	_grant_rank(actor, &"core")
	assert_eq(bool(ClanApi.unmet(actor, {"verb": &"has_rank", "id": "core"})["ok"]), true, "core")
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"has_rank", "id": "outer"})["ok"]), false, "not outer"
	)


func test_standing_at_least_is_inclusive_at_the_published_bar() -> void:
	var actor := _member(40)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"standing_at_least", "at": 40})["ok"]),
		true,
		"exactly at the bar is enough"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"standing_at_least", "at": 41})["ok"]),
		false,
		"one over"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"standing_at_least", "at": 0})["ok"]), true, "zero"
	)


func test_a_negative_standing_bar_is_read_as_zero_rather_than_as_a_refusal() -> void:
	var actor := _member(0)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"standing_at_least", "at": -5})["ok"]),
		true,
		"clamped, and therefore satisfiable by anybody"
	)


func test_has_trait_reads_the_projected_mirror() -> void:
	var actor := _member()
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"has_trait", "id": "clan:t_house"})["ok"]),
		true,
		"clan mirror"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"has_trait", "id": "clan_rank:outer"})["ok"]),
		true,
		"rank mirror"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"has_trait", "id": "clan:t_rival"})["ok"]),
		false,
		"rival mirror"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"has_trait", "id": "standing"})["ok"]),
		false,
		"a bare stat id"
	)


func test_all_of_any_of_and_none_of_compose_as_the_sibling_modules_do() -> void:
	var actor := _member(40)
	var both := {
		"verb": &"all_of",
		"of": [{"verb": &"is_clan", "id": "t_house"}, {"verb": &"standing_at_least", "at": 40}],
	}
	var either := {
		"verb": &"any_of",
		"of": [{"verb": &"is_clan", "id": "t_rival"}, {"verb": &"standing_at_least", "at": 10}],
	}
	var neither := {
		"verb": &"none_of",
		"of": [{"verb": &"is_clan", "id": "t_rival"}, {"verb": &"has_rank", "id": "head"}],
	}
	var both_fail := {
		"verb": &"all_of",
		"of": [{"verb": &"is_clan", "id": "t_rival"}, {"verb": &"standing_at_least", "at": 10}],
	}
	assert_eq(bool(ClanApi.unmet(actor, both)["ok"]), true, "all_of satisfied")
	assert_eq(bool(ClanApi.unmet(actor, either)["ok"]), true, "any_of satisfied")
	assert_eq(bool(ClanApi.unmet(actor, neither)["ok"]), true, "none_of satisfied")
	assert_eq((ClanApi.unmet(actor, both_fail)["unmet"] as Array).size(), 1, "one complaint")
	assert_eq(
		bool(
			(
				ClanApi
				. unmet(
					actor,
					{
						"verb": &"none_of",
						"of":
						[
							{"verb": &"is_clan", "id": "t_rival"},
							{"verb": &"is_clan", "id": "t_house"}
						],
					}
				)["ok"]
			)
		),
		false,
		"none_of refuses when one child matches"
	)


# --- An unknown verb ---------------------------------------------------------


func test_an_unknown_verb_refuses_closed_and_names_itself() -> void:
	for verb in [&"is_favourite_clan", &"is", &"all_of_all", &"IS_CLAN"]:
		var verdict := ClanApi.unmet(_member(), {"verb": verb, "id": "t_house"})
		assert_eq(bool(verdict["ok"]), false, "'%s' never opens a door" % verb)
		assert_eq(String(verdict["reason"]), "unknown_verb", "'%s' is refused as unknown" % verb)
		assert_eq(String(_unmet_entry(verdict, 0)["kind"]), "gate", "a refusal is about the gate")
		assert_eq(
			String(_unmet_entry(verdict, 0)["label"]).contains(String(verb)),
			true,
			"and names the verb it read"
		)


func test_a_sibling_modules_verb_is_refused_rather_than_obeyed() -> void:
	# `purity_at_least` is `BloodlineGate`'s verb, not this module's. Reading it here
	# would be a module reaching past its own vocabulary.
	var verdict := ClanApi.unmet(
		_member(), {"verb": &"purity_at_least", "id": "hearthborn", "at": 0.5}
	)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unknown_verb", "as unknown, not as malformed")


func test_an_unknown_verb_is_refused_even_with_nothing_else_to_go_on() -> void:
	var verdict := ClanApi.unmet(_member(), {"verb": &"not_a_verb"})
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unknown_verb", "as unknown")


# --- A malformed requirement -------------------------------------------------


func test_a_requirement_with_no_verb_refuses_closed() -> void:
	for requirement in [{"id": "t_house"}, {"of": []}, {"kind": "clan"}]:
		var verdict := ClanApi.unmet(_member(), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")
		assert_eq(
			String(_unmet_entry(verdict, 0)["label"]),
			"A gate names no verb.",
			"with the reason in the label"
		)


func test_a_verb_that_names_nothing_it_needs_refuses_rather_than_matching_empty() -> void:
	for requirement in [
		{"verb": &"is_clan"},
		{"verb": &"is_clan", "id": ""},
		{"verb": &"has_rank"},
		{"verb": &"has_trait"},
	]:
		var verdict := ClanApi.unmet(_member(), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


func test_a_standing_gate_with_no_numeric_bar_refuses() -> void:
	for requirement in [
		{"verb": &"standing_at_least"},
		{"verb": &"standing_at_least", "at": "high"},
		{"verb": &"standing_at_least", "at": null},
	]:
		var verdict := ClanApi.unmet(_member(), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


func test_a_malformed_child_poisons_the_whole_composite() -> void:
	var poisoned := {
		"verb": &"all_of",
		"of": [{"verb": &"is_clan", "id": "t_house"}, {"id": "t_rival"}],
	}
	var verdict := ClanApi.unmet(_member(), poisoned)
	assert_eq(bool(verdict["ok"]), false, "the unreadable child fails the composite")
	assert_eq(String(verdict["reason"]), "malformed", "and the cause survives the nesting")


func test_an_unknown_child_poisons_an_any_of_too() -> void:
	var poisoned := {
		"verb": &"any_of",
		"of": [{"verb": &"is_clan", "id": "t_house"}, {"verb": &"is_clanish", "id": "t_rival"}],
	}
	var verdict := ClanApi.unmet(_member(), poisoned)
	assert_eq(bool(verdict["ok"]), false, "a sibling that passed never satisfies it")
	assert_eq(String(verdict["reason"]), "unknown_verb", "and the cause survives the nesting")


func test_a_composite_with_no_children_refuses_rather_than_defaulting_open() -> void:
	for requirement in [
		{"verb": &"all_of"},
		{"verb": &"all_of", "of": []},
		{"verb": &"any_of", "of": "not an array"},
		{"verb": &"none_of", "of": []},
	]:
		var verdict := ClanApi.unmet(_member(), requirement)
		assert_eq(bool(verdict["ok"]), false, "childless composite %s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")


# --- The verdict shape -------------------------------------------------------


func test_a_verdict_is_always_ok_reason_unmet_and_the_facade_adds_nothing() -> void:
	var actor := _member(40)
	for requirement in [
		{},
		{"verb": &"is_clan", "id": "t_house"},
		{"verb": &"is_clan", "id": "t_rival"},
		{"verb": &"standing_at_least", "at": 90},
		{"verb": &"teleported"},
		{"id": "t_house"},
	]:
		var verdict := ClanGate.evaluate(actor, requirement)
		assert_eq(verdict.has("ok"), true, "ok is present for %s" % [requirement])
		assert_eq(verdict.has("reason"), true, "reason is present for %s" % [requirement])
		assert_eq(verdict.has("unmet"), true, "unmet is present for %s" % [requirement])
		assert_eq(
			(verdict["unmet"] as Array).is_empty(),
			bool(verdict["ok"]),
			"a closed gate reports, an open one does not"
		)
		assert_eq(ClanApi.unmet(actor, requirement), verdict, "the facade adds nothing")


func test_an_ungated_requirement_is_always_open() -> void:
	for actor in [null, _member()]:
		assert_eq(bool(ClanApi.unmet(actor, {})["ok"]), true, "an empty gate is ungated")


func test_every_unmet_entry_has_exactly_the_five_keys_a_panel_needs() -> void:
	var actor := _member(40)
	for requirement in [
		{"verb": &"is_clan", "id": "t_rival"},
		{"verb": &"standing_at_least", "at": 90},
		{"verb": &"has_trait", "id": "clan:t_rival"},
		{"verb": &"teleported"},
		{"id": "t_house"},
		{"verb": &"all_of", "of": []},
	]:
		var unmet := ClanGate.evaluate(actor, requirement)["unmet"] as Array
		assert_eq(unmet.is_empty(), false, "%s reports something" % [requirement])
		for entry in unmet:
			assert_eq(entry.keys().size(), UNMET_KEYS.size(), "%s has no extra key" % [requirement])
			for key in UNMET_KEYS:
				assert_eq(entry.has(key), true, "%s carries '%s'" % [requirement, key])
			assert_ne(String(entry["label"]), "", "and every label has text to render")


func test_a_closed_gate_never_reports_an_empty_unmet_list() -> void:
	var actor := _member(40)
	for requirement in [
		{"verb": &"is_clan", "id": "t_rival"},
		{"verb": &"has_rank", "id": "head"},
		{"verb": &"standing_at_least", "at": 90},
		{"verb": &"teleported"},
	]:
		var verdict := ClanApi.unmet(actor, requirement)
		assert_eq(bool(verdict["ok"]), false, "%s is closed" % [requirement])
		assert_eq((verdict["unmet"] as Array).is_empty(), false, "and says why")


func test_a_gate_never_refuses_a_null_actor_rather_than_crashing_on_one() -> void:
	assert_eq(bool(ClanApi.unmet(null, {"verb": &"is_clan", "id": "t_house"})["ok"]), false, "no")
	assert_eq(
		String(ClanApi.unmet(null, {"verb": &"is_clan", "id": "t_house"})["reason"]),
		"unmet",
		"as unmet rather than as a refusal"
	)
	assert_eq(ClanApi.admission_unmet(null, HOUSE), [], "and admission has no opinion on null")
