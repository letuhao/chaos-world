extends TestCase

## A qi PLAYER walks the Transcendent ascent, by pressing the shipped screen.
##
## The audit behind this (BL-0693) traced the qi ladder to R28 and no further.
## `Breakthrough.ascension_ok` (`breakthrough.gd:244`) demands a WALKED ascent for
## every target above `WorldAnchor.COMMIT_MICRO`, and the only thing in the product
## that produces one is `WorldAnchor.ascend` — a core entry point `ui/` may call
## directly (ADR 0041). Body and mind each had a screen action for it. The qi screen
## had none: `WorldAnchor.ascend` was implemented, proven by a dozen suites, and had
## no production caller on this path. So `actor.ascension` stayed at the zero steps
## that entering R28 commits, and R29 and R30 were unreachable by play while every
## ladder-walking suite stayed green — each of those walked the ascent through a test
## helper, which proves the ascent is SATISFIABLE, never that a player can satisfy
## it. A gate the product cannot open is a wall with a green test on it.
##
## What is proved here is the part that was dead: the screen OFFERS the ascent after
## a real breakthrough into the tier, pressing it walks the whole walk, and the gate
## the walk opens is open for BOTH realms above. The traversal that then carries a
## hero across those gates is `test_qi_screen_traverses_to_r30.gd`; the thousands of
## presses that carry a hero from R1 to R28 are the traversal suite's job and are not
## re-litigated in either file, which is the split `test_player_walks_to_r30.gd`
## established for the body path.

## Not a suite: the runner only collects `test_*.gd`.
const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"

const PATH := QiPath.PATH_ID

## Presses spent walking the ascent. `ASCENT_STEPS` is the real condition and the
## screen refuses the step past it, so its own `false` is the exit; the bound only
## names a screen that will not stop offering.
const ASCENT_BOUND := 8


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _ascent_of(view: Dictionary) -> Dictionary:
	return view.get("ascent", {}) as Dictionary


## Whether the screen's own ActionSet reports `action` live. The action set's
## summary nests its per-action flags under `enabled`, so this reads the shipped
## shape rather than assuming one.
func _enabled(view: Dictionary, action: String) -> bool:
	var row := view.get("actions", {}) as Dictionary
	return bool((row.get("enabled", {}) as Dictionary).get(action, false))


## A qi hero the player's own breakthrough carried into R28.
##
## `Breakthrough.try_advance` is the shared entry point behind the Breakthrough
## press, and it is the ONLY line here that causes an ascent to begin — nothing
## hand-writes `actor.ascension`, `actor.inside_world` or `actor.world`.
func _hero_advanced_into_r28() -> Actor:
	var realms := RealmDefaults.ladder().realms()
	var hero := Actor.new(
		&"qi_ascend_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	hero.set_path(PathState.new(PATH, realms[WorldAnchor.COMMIT_MICRO - 1].id))
	QiCultivationApi.attach(hero)
	ItemsApi.attach(hero, 512)
	assert_eq(QiCultivationApi.cultivate(hero, 1.0), true, "cultivate drives synchronization")
	Breakthrough.try_advance(hero, PATH)
	return hero


## Walk the ascent by pressing the screen's own button until it reports none left.
## Returns how many steps the PLAYER walked.
func _walk_by_pressing(screen: QiCultivationScreen) -> int:
	var walked := 0
	# Bounded by a FIXED count; the loop reads the screen's own steps-to-walk, and
	# the screen refuses the step past ASCENT_STEPS, so `act_ascend` returning false
	# is the real exit.
	var guard := 0
	while guard < ASCENT_BOUND and int(_ascent_of(screen.summary() as Dictionary)["steps"]) > 0:
		guard += 1
		if not screen.act_ascend():
			break
		walked += 1
	return walked


# --- The claim -------------------------------------------------------------------


## THE test, in order, through the screen. Everything before the ascent is placed by
## a real breakthrough; the ascent itself is a press and nothing else.
##
## Before the fix there was no `ascend` action on this screen at all, so `required`
## was absent, the control did not exist, and the walk below had nothing to walk:
## the ascension gate stayed shut and both realms above it were unreachable.
func test_a_player_walks_the_ascent_the_screen_offers_and_it_opens_both_gates() -> void:
	var screen := _screen()
	var hero := _hero_advanced_into_r28()
	var realms := RealmDefaults.ladder().realms()

	# Entering R28 through a real breakthrough BEGAN the ascent, and did not walk it.
	assert_eq(
		String(hero.path(PATH).rank_id),
		String(realms[WorldAnchor.COMMIT_MICRO].id),
		"the player's breakthrough carried the hero into R28"
	)
	assert_ne(hero.ascension, null, "and entering R28 began the ascent")
	assert_eq(hero.ascension.steps, 0, "without walking a step of it")
	assert_eq(
		Breakthrough.ascension_ok(hero, WorldAnchor.COMMIT_MICRO + 1),
		false,
		"so R29's ascent gate is shut before the walk"
	)

	# So the screen must offer it.
	screen.setup(hero)
	var view := screen.summary() as Dictionary
	var offered := _ascent_of(view)
	assert_eq(bool(offered["required"]), true, "so the screen offers the ascent")
	assert_eq(int(offered["steps"]), AscensionState.ASCENT_STEPS, "with every step to walk")
	assert_ne(String(offered["outstanding"]), "", "and says what is outstanding")
	assert_eq(bool(_enabled(view, "ascend")), true, "and the control is live")

	# Four presses of the screen's own button. No helper, no direct core call.
	assert_eq(
		_walk_by_pressing(screen), AscensionState.ASCENT_STEPS, "the player walked every step"
	)
	var climbed := _ascent_of(screen.summary() as Dictionary)
	assert_eq(int(climbed["steps"]), 0, "and the screen shows none left")
	assert_eq(String(climbed["outstanding"]), "", "with nothing outstanding")
	assert_eq(bool(climbed["met"]), true, "and the ascent gate now reads open")

	# The gate the walk opened is the one that was refusing, for BOTH realms above.
	# This is the claim the audit turned on: `ascension_ok` is what R29's and R30's
	# entries read, and it is shut for want of a walk no qi player could perform.
	assert_eq(
		Breakthrough.ascension_ok(hero, WorldAnchor.COMMIT_MICRO + 1),
		true,
		"core agrees R29's ascent gate is open"
	)
	assert_eq(Breakthrough.ascension_ok(hero, WorldAnchor.COMMIT_MICRO + 2), true, "and R30's")
	screen.free()


## The walk terminates on the state, not on the player pressing forever: four steps
## exist, the fifth is refused, and the button goes dead. A control that never stops
## offering is a control with no exit condition.
func test_the_walk_terminates_and_the_button_goes_dead() -> void:
	var screen := _screen()
	var hero := _hero_advanced_into_r28()
	screen.setup(hero)
	_walk_by_pressing(screen)
	assert_eq(screen.act_ascend(), false, "a finished ascent takes no further step")
	assert_eq(
		hero.ascension.steps, AscensionState.ASCENT_STEPS, "and the walk stayed at its own length"
	)
	var view := screen.summary() as Dictionary
	assert_eq(bool(_ascent_of(view)["required"]), false, "the gate is met")
	assert_eq(bool(_enabled(view, "ascend")), false, "so the control is dead")
	screen.free()


## Below the Transcendent tier the ascent is not this actor's gate, so the control
## is a dead button that would only invite a press. The refusal is a refusal, and it
## says why rather than silently doing nothing.
func test_the_screen_offers_no_ascent_before_the_tier() -> void:
	var screen := _screen()
	var realms := RealmDefaults.ladder().realms()
	var hero := Actor.new(
		&"qi_young_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	hero.set_path(PathState.new(PATH, realms[0].id))
	QiCultivationApi.attach(hero)
	ItemsApi.attach(hero, 64)
	Breakthrough.try_advance(hero, PATH)
	screen.setup(hero)
	var view := screen.summary() as Dictionary
	assert_eq(bool(_ascent_of(view)["required"]), false, "no ascent is owed at R2")
	assert_eq(bool(_enabled(view, "ascend")), false, "so none is offered")
	assert_eq(screen.act_ascend(), false, "and pressing it is refused")
	assert_ne(
		String(screen.summary().get("message", "")),
		"",
		"with the refusal explained rather than silent"
	)
	screen.free()


## After the walk, the screen's own unmet list no longer names the ascent. That is
## the gate's verdict reaching the player through the shipped read model rather than
## through core, and it is what a player reads to know what is left.
func test_the_unmet_list_stops_naming_the_ascent_once_it_is_walked() -> void:
	var screen := _screen()
	var hero := _hero_advanced_into_r28()
	screen.setup(hero)
	_walk_by_pressing(screen)
	var unmet := (screen.summary() as Dictionary).get("unmet", []) as Array
	var names_ascent := false
	# Bounded by `unmet`, which this loop only reads and never appends to.
	for clause in unmet:
		if String(clause).to_lower().contains("ascent"):
			names_ascent = true
	assert_eq(names_ascent, false, "the ascent is no longer outstanding: %s" % [unmet])
	screen.free()
