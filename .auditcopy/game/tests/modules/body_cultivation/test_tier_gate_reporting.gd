extends TestCase

## The high-tier gates are NAMED, not summarised (BL-0134 follow-on).
##
## `WorldAnchor.ascend` is implemented, proven and had zero production callers: the
## body path reported one omnibus unmet string — "Immortal tier gates not met
## (tribulation, inside world, ascension)" — which names three gates a player earns
## in three different places and can act on none of. The ascent in particular is
## WALKED, one step at a time, and nothing said so.
##
## These assertions are about legibility, not about the gate: the gate is core's and
## `Breakthrough.tier_gates_met` is the authority. What is pinned here is that a
## screen can read WHICH gate is shut and WHAT is outstanding, without restating a
## rule — and that the report can never drift from the gate, because every verdict in
## it is core's own predicate.

# --- Fixtures ------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## Ladder index of the first realm the high-tier gates apply to.
func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


func _hero(index: int) -> Actor:
	var realm_id := _realm_id(index)
	var actor := Actor.new(&"gate_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	return actor


## The unmet list `describe_unmet` produces for a hero standing at `index`. The
## condition, not the facade: the list is the contract under test.
func _unmet(index: int) -> Array[String]:
	return BodyBreakthroughCondition.new().describe_unmet(
		_hero(index), _hero(index).path(BodyPath.PATH_ID)
	)


## The clauses that are about the high-tier gates, so a test is not counting the
## body's own training conditions.
func _gate_clauses(index: int) -> Array[String]:
	var out: Array[String] = []
	for clause in _unmet(index):
		if _is_gate_clause(clause):
			out.append(clause)
	return out


func _is_gate_clause(clause: String) -> bool:
	var lowered := clause.to_lower()
	return (
		lowered.contains("tribulation")
		or lowered.contains("inside you")
		or lowered.contains("world you made")
		or lowered.contains("ascent")
	)


## A hero standing at `index` with a survived tribulation for the realm it is trying
## to enter, so the tribulation clause drops out and the later gates become visible.
func _hero_with_survivor(index: int) -> Actor:
	var actor := _hero(index)
	var target: int = index + 1
	if Breakthrough.begin_tribulation(actor, target) != null:
		var guard := 0
		while not actor.tribulation.is_complete() and guard < 16:
			guard += 1
			actor.tribulation.advance_wave()
		actor.tribulation.apply_result(actor, true)
	return actor


## Ladder index of the first realm whose gate reads the ASCENSION. Not the tribulation
## threshold: `Breakthrough.ascension_ok` returns true for any target at or below
## `COMMIT_MICRO`, so the ascent only becomes a gate above the Transcendent tier. A
## test that picked the Immortal band would be reading a gate that is not there —
## the exact false alarm BL-0313 records.
func _ascent_gate() -> int:
	return WorldAnchor.COMMIT_MICRO


## A hero standing at the lowest realm that owes the ascension, with the ascent begun
## by core's own commit and the tribulation for that realm survived. This is the hero
## the production path actually produces there: entering the Transcendent tier
## committed the created world and BEGAN the ascent.
func _hero_at_the_ascent_gate() -> Actor:
	var index := _ascent_gate()
	var begun := _hero(index)
	WorldAnchor.commit(begun, index)
	# Reuse the committed hero rather than building a second one: the ascent lives on
	# the actor, and a hero that never entered the tier has nothing to walk.
	var survivor := _hero_with_survivor(index)
	survivor.ascension = begun.ascension
	return survivor


# --- Below the gate -------------------------------------------------------------


## A mortal or spirit hero owes none of this, and the report must be silent rather
## than list four gates that are not theirs.
func test_no_gate_clause_is_reported_below_the_immortal_gate() -> void:
	for index in [0, 4, _gate() - 2]:
		assert_eq(_gate_clauses(index).is_empty(), true, "realm %d owes no high-tier gate" % index)


# --- The tribulation gate, named ------------------------------------------------


## One gate shut, one clause, naming the tribulation. The old omnibus line listed
## all three gates for a hero who owed exactly one.
func test_an_unfought_tribulation_is_named_on_its_own() -> void:
	var clauses := _gate_clauses(_gate() - 1)
	assert_eq(clauses.size(), 1, "exactly one gate is shut, and it says so: %s" % [clauses])
	assert_ne(
		String(clauses[0]).to_lower().contains("tribulation"), false, "and it is the tribulation"
	)
	assert_eq(
		String(clauses[0]).contains("inside you"),
		false,
		"and not an inside world the hero owes none of"
	)
	assert_eq(String(clauses[0]).contains("world you made"), false, "nor a world they owe none of")


## The clause is a real, actionable statement rather than a restatement of the gate's
## existence: it says what to DO.
func test_the_tribulation_clause_says_what_to_do() -> void:
	var clause := String(_gate_clauses(_gate() - 1)[0]).to_lower()
	assert_ne(clause.contains("survive"), false, "the clause names the action: %s" % clause)


# --- The ascent, named and countable --------------------------------------------


## The whole point of this slice. A hero who has survived and is now refused only by
## the ascent must be told THAT, with core's own wording and its step count — not
## lumped in with two gates that are already open.
func test_the_ascent_is_named_on_its_own_once_the_earlier_gates_are_open() -> void:
	var index := _ascent_gate()
	var hero := _hero_at_the_ascent_gate()
	var target: int = index + 1
	assert_eq(Breakthrough.tribulation_ok(hero, target), true, "the tribulation is behind us")
	var state := hero.path(BodyPath.PATH_ID)
	var clauses := BodyBreakthroughCondition.new().describe_unmet(hero, state)
	var ascent_clauses: Array[String] = []
	for clause in clauses:
		if clause.to_lower().contains("ascent"):
			ascent_clauses.append(clause)
	assert_ne(
		ascent_clauses.is_empty(),
		true,
		"the ascent is the gate left and it is named: %s" % [clauses]
	)
	assert_eq(
		ascent_clauses[0],
		WorldAnchor.ascension_unmet(hero),
		"in core's own wording, so the report cannot drift from the rule (ADR 0034)"
	)


## The wording says HOW MANY steps are left, which is what makes the gate walkable
## rather than merely visible.
func test_the_ascent_clause_counts_the_steps_left_to_walk() -> void:
	var hero := _hero_at_the_ascent_gate()
	var outstanding := WorldAnchor.ascension_unmet(hero)
	assert_ne(outstanding.contains(str(hero.ascension.steps_remaining())), false, outstanding)


## Walking the ascent shrinks the clause, so a player can see their own progress on
## the one gate that takes several deliberate acts.
func test_walking_the_ascent_shrinks_what_is_outstanding() -> void:
	var hero := _hero_at_the_ascent_gate()
	var target: int = _ascent_gate() + 1
	var before := hero.ascension.steps_remaining()
	var walked := 0
	# Bounded: `ascend` refuses on the step past the caps, so its own `false` is the
	# real exit. The bound only names an ascent that will not finish.
	var guard := 0
	while guard < 8 and not Breakthrough.ascension_ok(hero, target):
		guard += 1
		if not WorldAnchor.ascend(hero):
			break
		walked += 1
	assert_eq(walked > 0, true, "a step was walked through core's own entry point")
	assert_eq(hero.ascension.steps_remaining() < before, true, "and less is left to walk")
	# The loop ran until the gate opened, so there is nothing left to name. That is
	# the point: an empty outstanding clause is how a screen knows to stop offering
	# the ascent, and it must arrive by walking, not by being waived.
	assert_eq(
		Breakthrough.ascension_ok(hero, target),
		true,
		"and walking every step opens the gate the body refused on"
	)
	assert_eq(WorldAnchor.ascension_unmet(hero), "", "with nothing left to report")


## Every clause the body reports about a gate is one core would also report. The
## report is a naming of the gate, never a second gate.
func test_the_body_reports_no_clause_core_would_not() -> void:
	for index in [_gate() - 2, _gate() - 1, _gate(), _gate() + 3]:
		var hero := _hero(index)
		var target: int = index + 1
		var clauses := _gate_clauses(index)
		var core_agrees := Breakthrough.tier_gates_met(hero, target)
		assert_eq(
			clauses.is_empty(),
			core_agrees,
			(
				"realm %d: %d clauses reported, core says the gates are %s"
				% [index, clauses.size(), "met" if core_agrees else "shut"]
			)
		)


# --- The facade publishes the gates as data --------------------------------------


## A screen must be able to mark WHICH gate is shut without restating any rule. Four
## booleans, not one `ready`, because the four are earned in four different places.
func test_the_facade_publishes_each_gate_separately() -> void:
	var hero := _hero(_gate() - 1)
	var panel := BodyCultivationApi.panel_state(hero)
	var gates := panel["tier_gates"] as Dictionary
	for key in ["tribulation", "inside_world", "world", "ascent"]:
		assert_ne(gates.has(key), false, "%s is published" % key)
	assert_eq(bool(gates["tribulation"]), false, "the tribulation is shut")
	assert_eq(
		bool(gates["tribulation"]),
		Breakthrough.tribulation_ok(hero, _gate()),
		"and it is core's own verdict, not the module's"
	)


## The published gates must never disagree with the gate that actually refuses,
## because that is the difference between a screen that offers the right action and
## one that offers a dead button.
func test_the_published_gates_agree_with_core_on_a_survivor() -> void:
	var hero := _hero_with_survivor(_gate() - 1)
	var gates := BodyCultivationApi.panel_state(hero)["tier_gates"] as Dictionary
	for key in ["tribulation", "inside_world", "world", "ascent"]:
		assert_eq(bool(gates[key]), true, "%s is open for a hero who survived it" % key)


## The ascent is published as a PROGRESS, not a boolean: it takes several deliberate
## acts, and a screen cannot render "four steps to walk" from a `false`.
func test_the_facade_publishes_how_much_of_the_ascent_is_left() -> void:
	var hero := _hero_at_the_ascent_gate()
	var ascent := BodyCultivationApi.panel_state(hero)["ascent"] as Dictionary
	assert_eq(int(ascent["steps_total"]), AscensionState.ASCENT_STEPS, "core's own step count")
	assert_eq(bool(ascent["required"]), true, "and the ascent is this hero's gate")
	assert_eq(
		String(ascent["outstanding"]),
		WorldAnchor.ascension_unmet(hero),
		"with core's wording, never a restatement here (ADR 0034)"
	)
	assert_eq(
		int(ascent["steps"]),
		hero.ascension.steps_remaining(),
		"and the steps left, which only core's state knows"
	)


## Below the gate the ascent is not this actor's business, and the read says so
## rather than reporting zero of four for a hero who has no ascent at all.
func test_the_ascent_is_not_required_below_the_gate() -> void:
	var ascent := BodyCultivationApi.panel_state(_hero(_gate() - 2))["ascent"] as Dictionary
	assert_eq(bool(ascent["required"]), false, "no ascent is owed this far down")
	assert_eq(bool(ascent["met"]), true, "and the gate reads open")


## At the top of the ladder there is no realm ahead, so there is no gate to publish
## and the read says nothing rather than inventing one.
func test_no_gate_is_published_at_the_top_of_the_ladder() -> void:
	var top := RealmDefaults.ladder().size() - 1
	var panel := BodyCultivationApi.panel_state(_hero(top))
	assert_eq(
		(panel["tier_gates"] as Dictionary).is_empty(), true, "no target realm, no gates to report"
	)
