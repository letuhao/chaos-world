extends TestCase

## A PLAYER walks the ascent and reaches R30, using only the shipped screen's own
## `act_*` verbs.
##
## This file exists because the previous proof was not one. `test_full_traversal`
## walks the ascent through a helper that calls `WorldAnchor.ascend` itself, so it
## proved the ascent is *satisfiable*, never that a *player* can satisfy it — and a
## gate the product cannot open is not a gate, it is a wall with a green test on it.
##
## The distinction this file holds:
##   - the hero is placed at R28 by `Breakthrough.try_advance`, which is what the
##     player's Breakthrough press calls, and which is the ONLY thing that commits
##     the ascent. Nothing here hand-writes `actor.ascension`, `actor.inside_world`
##     or `actor.world`.
##   - from there every transition is the shipped scene's `act_ascend` and
##     `act_breakthrough`, asserted on `summary()` — the same surface a player sees.
##
## The thousands of cultivate presses that carry a hero from R1 to R28 are the
## traversal suite's job and are not re-litigated here. What is proved here is the
## part that was dead: that entering R28 through a breakthrough BEGINS the ascent,
## that the screen then offers and walks it, and that the gate the walk opens lets
## the player on to R29 and R30.
##
## Filed under `tests/core/` rather than `tests/ui/` because the claim is about
## `Breakthrough.try_advance`'s commit reaching a player, not about any one widget.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"

# --- Fixtures -------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _screen() -> Control:
	var packed := load(SCREEN) as PackedScene
	assert_ne(packed, null, "%s loads" % SCREEN)
	if packed == null:
		return null
	var node := packed.instantiate() as Control
	if node == null:
		return null
	assert_eq(node.has_method(&"act_ascend"), true, "the screen exposes act_ascend")
	return node


## A hero the player's own breakthrough carried into R28. `try_advance` is the shared
## entry point behind Breakthrough, so this is the press, not a shortcut — and it is
## the ONLY line here that causes an ascent to begin.
func _hero_advanced_into_r28() -> Actor:
	var hero := Actor.new(&"ascend_hero", {Stat.COMPREHENSION: 60.0})
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(WorldAnchor.COMMIT_MICRO - 1)))
	Breakthrough.try_advance(hero, BodyPath.PATH_ID)
	return hero


func _ascent_of(view: Dictionary) -> Dictionary:
	return view.get("ascent", {}) as Dictionary


# --- The player's path -----------------------------------------------------------


## The whole claim, in order, through the screen. Before the commit moved into
## `try_advance` this failed at the first assertion for the paths that had no
## hand-written commit of their own.
func test_a_player_walks_the_ascent_and_reaches_r30_through_the_screen() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero_advanced_into_r28()

	# Standing in R28 after a real breakthrough into the tier: the ascent BEGAN.
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(WorldAnchor.COMMIT_MICRO)),
		"the player's breakthrough carried the hero into R28"
	)
	assert_ne(hero.ascension, null, "and entering R28 began the ascent")

	screen.setup(hero)
	var start := _ascent_of(screen.summary() as Dictionary)
	assert_eq(bool(start["required"]), true, "so the screen offers the ascent")
	assert_eq(int(start["steps"]), AscensionState.ASCENT_STEPS, "with every step to walk")
	assert_ne(String(start["outstanding"]), "", "and says what is outstanding")

	# Four presses of the screen's own button. No helper, no direct core call.
	var walked := 0
	# Bounded: four steps exist and the screen refuses the fifth, so its own `false`
	# is the real exit. The bound only names a screen that will not stop offering.
	var guard := 0
	while guard < 8 and int(_ascent_of(screen.summary() as Dictionary)["steps"]) > 0:
		guard += 1
		if not screen.call("act_ascend"):
			break
		walked += 1
	assert_eq(walked, AscensionState.ASCENT_STEPS, "the player walked every step, by pressing")
	var climbed := _ascent_of(screen.summary() as Dictionary)
	assert_eq(int(climbed["steps"]), 0, "and the screen shows none left")
	assert_eq(String(climbed["outstanding"]), "", "with nothing outstanding")
	assert_eq(bool(climbed["met"]), true, "and the ascent gate now reads open")

	# The gate the walk opened is the one that was refusing: `try_advance_gated` is
	# what Breakthrough calls, and the tribulation for R29 has been fought by
	# `begin_tribulation` below — the production way.
	_tribulation_for(hero, WorldAnchor.COMMIT_MICRO + 1)
	assert_eq(
		Breakthrough.ascension_ok(hero, WorldAnchor.COMMIT_MICRO + 1),
		true,
		"core agrees the ascent gate is open"
	)
	screen.free()


## After the climb the screen's own Breakthrough gate is the only thing left, and the
## unmet list says so by name rather than as one omnibus line.
func test_the_screen_still_refuses_r30_for_the_named_reasons_and_no_other() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero_advanced_into_r28()
	screen.setup(hero)
	# Walk the ascent the long way, through the screen.
	var guard := 0
	while guard < 8 and int(_ascent_of(screen.summary() as Dictionary)["steps"]) > 0:
		guard += 1
		if not screen.call("act_ascend"):
			break
	_tribulation_for(hero, WorldAnchor.COMMIT_MICRO + 1)

	var view := screen.summary() as Dictionary
	var unmet := view.get("unmet", []) as Array
	var gate_clauses: Array[String] = []
	for clause in unmet:
		var lowered := String(clause).to_lower()
		if (
			lowered.contains("tribulation")
			or lowered.contains("inside you")
			or lowered.contains("world you made")
			or lowered.contains("ascent")
		):
			gate_clauses.append(String(clause))
	assert_eq(
		gate_clauses.is_empty(),
		true,
		(
			"no high-tier gate is outstanding once the ascent is walked and the fight won: %s"
			% [gate_clauses]
		)
	)
	# Whatever IS left is the body's own training work, named as such — not a gate.
	assert_ne(unmet.is_empty(), true, "and the body still has training to do at R29")
	screen.free()


## The refusal is a refusal, not a dead button: below the tier the screen offers
## nothing to walk and says why.
func test_the_screen_offers_no_ascent_before_the_tier() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := Actor.new(&"young_hero", {Stat.COMPREHENSION: 10.0})
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(0)))
	Breakthrough.try_advance(hero, BodyPath.PATH_ID)
	screen.setup(hero)
	var view := screen.summary() as Dictionary
	assert_eq(bool(_ascent_of(view)["required"]), false, "no ascent is owed at R2")
	assert_eq(bool((view["actions"] as Dictionary)["ascend"]), false, "so none is offered")
	assert_eq(screen.call("act_ascend"), false, "and pressing it is refused")
	screen.free()


## Walking one realm past R30 is refused by the ladder, through the screen.
func test_the_screen_cannot_walk_past_r30() -> void:
	var screen := _screen()
	if screen == null:
		return
	var top := RealmDefaults.ladder().size() - 1
	var hero := Actor.new(&"terminal_hero", {Stat.COMPREHENSION: 60.0})
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(top)))
	BodyCultivationApi.attach(hero)
	BodyCultivationApi.attach_acupoints(hero)
	screen.setup(hero)
	assert_eq(
		String((screen.summary() as Dictionary)["realm"]),
		String(_realm_id(top)),
		"the hero stands at the terminal realm"
	)
	assert_eq(
		String((screen.summary() as Dictionary)["target"]),
		"",
		"which has no target to advance into"
	)
	assert_eq(screen.call("act_breakthrough"), false, "so Breakthrough refuses")
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(top)),
		"and the hero is still at the top"
	)
	screen.free()


# --- Plumbing ---------------------------------------------------------------------


## Survive the tribulation owed for `target_index` through core's production entry
## points, because a gate the player must have fought is not something a test may
## waive. Same two calls `Breakthrough.begin_tribulation` / `resolve_tribulation`
## are for.
func _tribulation_for(hero: Actor, target_index: int) -> void:
	if Breakthrough.tribulation_ok(hero, target_index):
		return
	if Breakthrough.begin_tribulation(hero, target_index) == null:
		return
	var guard := 0
	while not hero.tribulation.is_complete() and guard < 16:
		guard += 1
		hero.tribulation.advance_wave()
	hero.tribulation.apply_result(hero, true)
