extends TestCase

## Race × path must be a **partition, not a tier list** (ADR 0062): a race is legible
## without opening a stat sheet, because the questions it answers are *can this body
## cultivate this path at all* and *what realm can it never pass*. These assert both, and
## assert the gate refuses a requirement it cannot read rather than opening a door.

const STONE := &"t_stone"
const TIDE := &"t_tide"
const BASE := &"t_base"

## Ordinal 8 on the 30-step ladder, and two well below and well above it.
const CEILING := 8
const UNDER := &"void_refinement"
const AT := &"body_integration"
const OVER := &"primordial_origin"


func setup() -> void:
	(
		RaceFixtureCatalog
		. install(
			[
				RaceFixtureCatalog.capped(STONE, &"mind_cultivation", CEILING, Stat.PHYSIQUE),
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


## One entry of a verdict's `unmet` array. The array is the reason a panel can render
## a refusal it did not have to invent, so it is read by index rather than reshaped.
func _unmet_entry(verdict: Dictionary, index: int) -> Dictionary:
	return (verdict["unmet"] as Array)[index]


func test_the_verdicts_carry_only_ok_reason_and_unmet() -> void:
	var actor := _born(STONE, OVER)
	var cases := [
		{},
		{"verb": &"is_race", "id": String(TIDE)},
		{"verb": &"race_allows_path", "id": String(PathState.MIND)},
		{"verb": &"realm_ceiling", "at": 4},
		{"verb": &"teleported"},
	]
	for requirement in cases:
		var verdict := RaceGate.evaluate(actor, requirement)
		assert_eq(verdict.keys().size(), 3, "exactly three keys for %s" % [requirement])
		assert_eq(verdict.has("ok"), true, "ok is present for %s" % [requirement])
		assert_eq(verdict.has("reason"), true, "reason is present for %s" % [requirement])
		assert_eq(verdict.has("unmet"), true, "unmet is present for %s" % [requirement])
		assert_eq(RaceApi.unmet(actor, requirement), verdict, "the facade adds nothing")
		assert_eq((verdict["unmet"] as Array).is_empty(), bool(verdict["ok"]), "ok and unmet agree")


# --- The path partition ------------------------------------------------------


func test_a_closed_path_is_refused_and_names_itself() -> void:
	var stone := _born(STONE)
	assert_eq(
		RaceApi.can_take_path(stone, PathState.MIND), false, "stoneborn cannot cultivate mind"
	)
	assert_eq(RaceApi.can_take_path(stone, PathState.BODY), true, "but body stays open")
	assert_eq(RaceApi.can_take_path(stone, PathState.QI), true, "and so does qi")
	var problems := RaceGate.path_unmet(stone, PathState.MIND)
	assert_eq(problems.size(), 1, "one complaint")
	var entry := problems[0]
	assert_eq(String(entry["kind"]), "path", "the entry names the kind")
	assert_eq(String(entry["id"]), String(PathState.MIND), "and the path")
	assert_eq(bool(entry["required"]), true, "it is required")
	assert_eq(bool(entry["actual"]), false, "and not held")
	assert_ne(String(entry["label"]), "", "with a renderable label")
	assert_eq(RaceGate.path_unmet(stone, PathState.BODY), [], "an open path reports nothing")


func test_each_race_closes_a_different_path_so_the_three_are_a_partition() -> void:
	assert_eq(RaceGate.closed_paths(_born(STONE)), [PathState.MIND], "stoneborn closes mind")
	assert_eq(RaceGate.closed_paths(_born(TIDE)), [PathState.BODY], "tidecaller closes body")
	# The baseline closes mind too, which is a deliberate authoring statement: it is the
	# body that reaches, not the body that perceives. What makes the set a partition is
	# that no actor is ever offered all three at once and every race answers differently.
	assert_eq(RaceGate.allows_path(_born(STONE), PathState.QI), true, "stoneborn still takes qi")
	assert_eq(RaceGate.allows_path(_born(TIDE), PathState.QI), true, "tidecaller still takes qi")
	assert_eq(RaceGate.allows_path(_born(BASE), PathState.QI), true, "and so does the baseline")


func test_an_actor_with_no_race_takes_no_path_restriction_at_all() -> void:
	var bare := Actor.new(&"bare")
	RaceApi.attach(bare)
	for path_id in PathState.ALL:
		assert_eq(RaceApi.can_take_path(bare, path_id), true, "%s is ungated" % path_id)
	assert_eq(RaceGate.path_unmet(null, PathState.MIND), [], "and so for a null actor")


func test_path_unmet_ignores_a_gate_naming_no_path() -> void:
	assert_eq(RaceGate.path_unmet(_born(STONE), &""), [], "an empty path id is not a complaint")


# --- The realm ceiling -------------------------------------------------------


func test_the_realm_ceiling_blocks_a_body_that_has_passed_it() -> void:
	var past := _born(STONE, OVER)
	var problems := RaceGate.realm_ceiling_unmet(past)
	assert_eq(problems.size(), 1, "one complaint")
	var entry := problems[0]
	assert_eq(String(entry["kind"]), "realm_ceiling", "the entry names the kind")
	assert_eq(String(entry["id"]), String(STONE), "and the race that stops it")
	assert_eq(int(entry["required"]), CEILING, "required is the ceiling")
	assert_eq(int(entry["actual"]), 29, "actual is where the actor stands")
	assert_ne(String(entry["label"]), "", "with a renderable label")


func test_the_realm_ceiling_is_exactly_satisfied_at_the_ceiling_and_below_it() -> void:
	assert_eq(RaceGate.realm_ceiling_unmet(_born(STONE, UNDER)), [], "below the ceiling")
	assert_eq(RaceGate.realm_ceiling_unmet(_born(STONE, AT)), [], "exactly at it")
	assert_ne(RealmDefaults.ladder().index_of(AT), CEILING, "and that is not the ceiling ordinal")


func test_a_race_with_no_ceiling_is_never_blocked_wherever_it_stands() -> void:
	var far := _born(TIDE, OVER)
	assert_eq(RaceGate.realm_ceiling_unmet(far), [], "0 means no ceiling")
	assert_eq(
		RaceGate.realm_ceiling_unmet(_born(BASE)), [], "or an actor who has never broken through"
	)
	assert_eq(RaceGate.realm_ceiling_unmet(null), [], "or an actor with no race at all")


func test_the_ceiling_reads_the_actors_best_path_not_whichever_comes_first() -> void:
	var actor := Actor.new(&"body", {Stat.PHYSIQUE: 10.0})
	RaceApi.attach(actor)
	RaceApi.set_race(actor, STONE)
	actor.set_path(PathState.new(PathState.MIND, &"qi_refining"))
	actor.set_path(PathState.new(PathState.BODY, OVER))
	assert_eq(
		RaceGate.realm_ceiling_unmet(actor).size(), 1, "the body path is the one past the bar"
	)
	assert_eq(int((RaceGate.realm_ceiling_unmet(actor)[0] as Dictionary)["actual"]), 29, "at 29")
	assert_eq(RaceGate.actor_realm_index(actor), 29, "and that is the actor's best ordinal")


# --- The verbs ---------------------------------------------------------------


func test_an_empty_requirement_is_ungated_and_always_open() -> void:
	for actor in [_born(STONE), null]:
		var verdict := RaceApi.unmet(actor, {})
		assert_eq(bool(verdict["ok"]), true, "empty means open")
		assert_eq(String(verdict["reason"]), "", "with nothing to report")
		assert_eq(verdict["unmet"] as Array, [], "and no unmet entry")


func test_is_race_passes_only_for_the_race_the_actor_actually_is() -> void:
	var stone := _born(STONE)
	assert_eq(
		bool(RaceApi.unmet(stone, {"verb": &"is_race", "id": String(STONE)})["ok"]),
		true,
		"held passes"
	)
	var missed := RaceApi.unmet(stone, {"verb": &"is_race", "id": String(TIDE)})
	assert_eq(bool(missed["ok"]), false, "a race it is not fails")
	assert_eq(String(missed["reason"]), "unmet", "as an ordinary unmet, not a refusal")
	var entry := _unmet_entry(missed, 0)
	assert_eq(String(entry["kind"]), "race", "the entry names the kind")
	assert_eq(String(entry["id"]), String(TIDE), "and the race it wanted")
	assert_eq(String(entry["label"]), "Requires the race 't_tide'", "with a renderable label")


func test_race_allows_path_is_the_verb_form_of_the_partition_question() -> void:
	var stone := _born(STONE)
	assert_eq(
		bool(
			RaceApi.unmet(stone, {"verb": &"race_allows_path", "id": String(PathState.BODY)})["ok"]
		),
		true,
		"an open path passes"
	)
	var closed := RaceApi.unmet(stone, {"verb": &"race_allows_path", "id": String(PathState.MIND)})
	assert_eq(bool(closed["ok"]), false, "a closed path fails")
	assert_eq(String(_unmet_entry(closed, 0)["kind"]), "path", "as a path complaint")


func test_has_trait_reads_the_mirror_and_nothing_else() -> void:
	var stone := _born(STONE)
	var trait_id := RaceState.trait_for(STONE)
	assert_eq(
		bool(RaceApi.unmet(stone, {"verb": &"has_trait", "id": str(trait_id)})["ok"]),
		true,
		"the mirrored race passes"
	)
	assert_eq(
		bool(RaceApi.unmet(stone, {"verb": &"has_trait", "id": String(STONE)})["ok"]),
		false,
		"a bare race id is not a trait id"
	)
	assert_eq(
		bool(RaceApi.unmet(stone, {"verb": &"has_trait", "id": String(&"destiny:oath")})["ok"]),
		false,
		"and a sibling's namespace is not ours to answer"
	)


func test_the_realm_ceiling_verb_asks_whether_the_body_still_has_headroom() -> void:
	var past := _born(STONE, OVER)
	var verdict := RaceApi.unmet(past, {"verb": &"realm_ceiling", "at": 20})
	assert_eq(bool(verdict["ok"]), false, "a body past its ceiling has no headroom")
	var entry := _unmet_entry(verdict, 0)
	assert_eq(int(entry["required"]), 20, "required is what the gate asked for")
	assert_eq(
		bool(RaceApi.unmet(_born(STONE, AT), {"verb": &"realm_ceiling", "at": 20})["ok"]),
		true,
		"a body still climbing has headroom"
	)


func test_the_composites_nest_and_report_every_unmet_child() -> void:
	var stone := _born(STONE)
	var nested := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"is_race", "id": String(STONE)},
			{
				"verb": &"any_of",
				"of":
				[
					{"verb": &"race_allows_path", "id": String(PathState.BODY)},
					{"verb": &"race_allows_path", "id": String(PathState.MIND)},
				]
			},
		]
	}
	assert_eq(bool(RaceApi.unmet(stone, nested)["ok"]), true, "the deep branch passes")
	# `any_of` passes when ANY child passes, so adding a leaf that fails does not
	# fail the branch — one open path is enough. To make the branch genuinely fail
	# every child has to fail, which is what the next case does.
	nested["of"][1]["of"] = [{"verb": &"is_race", "id": String(TIDE)}]
	var missed := RaceApi.unmet(stone, nested)
	assert_eq(bool(missed["ok"]), false, "the leaf failure fails the root")
	# One leaf failed, so exactly one complaint is reported: `any_of` collapses its
	# children into the branch verdict, and the branch reports the failing child once.
	assert_eq((missed["unmet"] as Array).size(), 1, "and the failing leaf is reported once")
	var none := RaceApi.unmet(
		stone, {"verb": &"none_of", "of": [{"verb": &"is_race", "id": String(TIDE)}]}
	)
	assert_eq(bool(none["ok"]), true, "an unmet child satisfies none_of")
