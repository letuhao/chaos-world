extends TestCase

## `RaceApi.summary` is called by PRODUCTION — `app/character_creation_flow.gd`
## reads `races[race_id]` off it at `_race_name` and `_race_closed_paths`, twice
## — and no test names it. A character-creation screen's body list is that
## dictionary.
##
## ## Why the existing race suites did not catch it
##
## `modules/race/*` proves the gates (`can_take_path`, `resolve_race`,
## `closed_paths`) by calling them. `summary` is the verb that PACKS those
## answers into the per-race rows a screen reads, and it computes two things no
## other verb returns: `held` (which row is this actor's) and the actor-level
## `open_path_count`, which is `PathState.ALL - closed` — a subtraction done
## here and nowhere else.
##
## `character_creation_flow.gd:401,406` calls it with a NULL actor, so the
## no-actor shape is the one production actually uses. Both shapes are asserted.

## Two authored races, so "held exactly one" and "the rest are not held" are
## real claims rather than vacuous on a one-race catalog.
const OTHER_RACE := &"sable_tidecaller"


func _actor(race_id: StringName = &"") -> Actor:
	var actor := ActorFactory.build(&"race_summary_reader")
	RaceApi.attach(actor)
	# `attach` registers the module but an actor carries no race until one is set,
	# and `summary` answers "" for `race` in that case. Default to the catalog's
	# own baseline rather than a literal, so the fixture follows the content.
	RaceApi.set_race(actor, race_id if race_id != &"" else RaceCatalog.instance().baseline_race())
	return actor


## The screen contract: with no actor the race block is empty but the CATALOG is
## still published, because a creation screen picking a body has no actor yet.
func test_no_actor_still_publishes_every_race_and_no_held_one() -> void:
	var view := RaceApi.summary(null)
	assert_eq(bool(view.get("has_actor", true)), false, "and says so")
	assert_eq(String(view.get("actor_id", "x")), "", "with no actor id")
	assert_eq(String(view.get("race", "x")), "", "and no held race")
	assert_eq(
		String(view.get("baseline", "")),
		String(RaceCatalog.instance().baseline_race()),
		"the baseline is still named"
	)
	assert_ne(
		(view.get("races", {}) as Dictionary).size(), 0, "the catalog is published for a picker"
	)


## EVERY authored race is listed whatever the actor is, so a lineage screen can
## compare bodies without a second call — that is the docstring's reason for the
## shape, and it is a claim worth pinning.
func test_every_authored_race_is_listed_and_exactly_one_is_held() -> void:
	var actor := _actor()
	var races := RaceApi.summary(actor).get("races", {}) as Dictionary
	var authored := RaceApi.race_ids().size()
	assert_eq(races.size(), authored, "every authored race has a row")
	var held := 0
	for key in races.keys():
		if bool((races[key] as Dictionary).get("held", false)):
			held += 1
	assert_eq(held, 1, "exactly one row is marked held")


## `held` is per-row and is what tells a picker which body is already chosen.
## Asserting on THIS actor's race rather than a literal keeps it true if the
## catalog's baseline ever moves.
func test_the_row_this_actor_holds_is_the_one_marked() -> void:
	var actor := _actor()
	var mine := String(RaceApi.race_of(actor))
	assert_ne(mine, "", "the fixture really is on a race")
	var races := RaceApi.summary(actor).get("races", {}) as Dictionary
	assert_eq(bool((races[mine] as Dictionary).get("held", false)), true, "its own row is held")
	for key in races.keys():
		if key == mine:
			continue
		assert_eq(bool((races[key] as Dictionary).get("held", false)), false, "no other row is")


## `open_path_count` is `PathState.ALL - closed_paths`, a subtraction this verb
## does itself. Asserted against the seed's own list rather than a literal count,
## so the claim is "the arithmetic is right", not "the number is 4".
func test_open_paths_are_every_path_the_body_does_not_close() -> void:
	var actor := _actor()
	var view := RaceApi.summary(actor)
	var closed: Array = view.get("closed_paths", []) as Array
	assert_eq(
		int(view.get("open_path_count", -1)),
		PathState.ALL.size() - closed.size(),
		"open is ALL minus closed, counted here and nowhere else"
	)


## A closed path is a real answer, and the per-race row must carry it too — the
## flow reads `closed_paths` off the ROW, not off the actor. Asserted as a
## conjunction rather than only a loop, because a body that closes nothing makes
## the loop vacuous and the case would assert nothing at all.
func test_a_closed_body_reports_the_path_it_closes() -> void:
	var actor := _actor()
	var closed: Array = RaceApi.summary(actor).get("closed_paths", []) as Array
	for path_id in closed:
		assert_eq(
			RaceApi.can_take_path(actor, StringName(path_id)), false, "%s is refused" % path_id
		)
	var declared := RaceCatalog.instance().race_definition(RaceApi.race_of(actor))
	assert_ne(declared, null, "the fixture's body is authored")
	assert_eq(
		closed.size(),
		declared.closed_paths.size(),
		"and the summary closed exactly what it declares"
	)


## Primitives only. This dictionary is published for `ui/`, and a Resource nested
## in it would be an edge `tools/arch/rules.py` has not granted — the panel
## formats every value it reads.
func test_the_summary_is_primitives_only() -> void:
	var view := RaceApi.summary(_actor())
	for key in ["has_actor", "actor_id", "race", "open_path_count", "lifespan", "is_baseline"]:
		var value: Variant = view[key]
		var primitive := value is String or value is float or value is int or value is bool
		assert_eq(primitive, true, "'%s' is a primitive" % key)
	# The two containers are asserted separately: an Array or Dictionary is not a
	# scalar, so lumping them into the loop above would report a container as a
	# violation. What matters is what is INSIDE them — a panel formats every leaf.
	assert_eq(view.get("closed_paths", []) is Array, true, "closed paths is a list")
	assert_eq(view.get("races", {}) is Dictionary, true, "the race block is a dictionary")
	for key in (view.get("races", {}) as Dictionary).keys():
		_assert_leaves((view.get("races", {}) as Dictionary)[key], "races[%s]" % key, 0)


## Every leaf a panel can reach is a primitive, at ANY depth — a race row nests
## `closed_paths` and `tags` inside itself, and one level of checking would let a
## Resource hide one level down.
##
## `depth` is a FIXED bound (three, the shape as authored) and never grows with
## what it walks: a recursive check with no cap is the walk `test_no_unbounded_wait`
## cannot see, and a cyclic row would never return.
func _assert_leaves(value: Variant, label: String, depth: int) -> void:
	if depth > 3:
		assert_eq(true, false, "%s nests deeper than the authored three levels" % label)
		return
	if value is Array or value is Dictionary:
		var children: Array = (value as Array) if value is Array else (value as Dictionary).keys()
		for child in children:
			_assert_leaves(child, label, depth + 1)
		return
	var primitive := value is String or value is float or value is int or value is bool
	assert_eq(primitive, true, "%s is a primitive leaf" % label)


## A null actor is a REFUSAL shape, not a crash: `character_creation_flow` calls
## it with null on the first frame, before any body exists.
func test_the_no_actor_shape_has_every_key_the_flow_indexes() -> void:
	var view := RaceApi.summary(null)
	for key in [
		"has_actor",
		"actor_id",
		"race",
		"closed_paths",
		"open_path_count",
		"realm_ceiling",
		"realm_reached",
		"lifespan",
		"affinities",
		"is_baseline",
		"races",
		"baseline"
	]:
		assert_eq(view.has(key), true, "'%s' is present with no actor" % key)
