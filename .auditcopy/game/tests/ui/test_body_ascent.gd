extends TestCase

## A PLAYER CAN WALK THE TRANSCENDENT ASCENT (ADR 0021, ADR 0041).
##
## `test_full_traversal.gd` proves R1 -> R30 is traversable, but it proves it
## through its own `_walk_ascent` helper, which calls `WorldAnchor.ascend`
## directly. A player cannot press anything: the ladder was traversable and
## unreachable, which is the exact shape of defect BL-0119 all over again. This
## file drives the shipped screen and its buttons instead.
##
## Nothing here invents the ascent. `WorldAnchor.commit(actor, COMMIT_MICRO)` is
## what the breakthrough into R28 does, and it is the only thing that creates an
## `AscensionState`; the screen then reads its state and calls core's own entry
## point. No facade verb is added: the ascent belongs to no single path, so
## `body_cultivation`'s facade stays at its 12-method cap.
##
## Two traps this file is written around, both measured rather than assumed:
##
##  - The ascent only gates ABOVE the Transcendent tier. `ascension_ok` returns
##    true for any target at or below `WorldAnchor.COMMIT_MICRO` (27), so
##    asserting an ascent is owed at R18 asserts the opposite of the truth.
##  - Nothing here may branch on the outcome of a random roll. The ascent is
##    deterministic — `AscensionState.ascend` refuses only at the caps — so no
##    seed sweep is needed and none is used.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const BODY_ROUTE := &"body_cultivation"
## The first Transcendent realm. Entering it is what commits the milestone, and
## therefore what BEGINS the ascent; nothing before it produces one.
const TRANSCENDENT_INDEX := WorldAnchor.COMMIT_MICRO


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _screen() -> BodyCultivationPanel:
	var screen := (load(SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(screen, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	return screen


func _actor() -> Actor:
	var actor := ActorFactory.with_body_cultivation(
		Actor.new(&"ascent_hero", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


## A body hero standing in the first Transcendent realm, with the milestone that
## realm's breakthrough commits already applied — so the ascent exists and owes
## its whole walk. This is the state a player reaches after R28, not a shortcut
## past it.
func _transcendent() -> Actor:
	var actor := _actor()
	actor.path(BodyPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	BodyTraining.synchronize(actor)
	assert_ne(actor.ascension, null, "the R28 milestone produced an ascent to walk")
	assert_eq(
		actor.ascension.steps,
		0,
		"and it is unwalked: the milestone BEGINS the ritual, it does not finish it"
	)
	return actor


func _realm_at(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _ascent(screen: BodyCultivationPanel) -> Dictionary:
	return screen.summary().get("ascent", {}) as Dictionary


# --- The control is offered exactly when there is something to walk -----------


## A dead control is the failure this guards, in both directions: a player who
## cannot press it, and a button live for a hero with no ascent to walk. Both are
## read off the facade's own read model, never off the screen's opinion of it.
func test_the_ascend_button_is_offered_only_while_an_ascent_is_owed() -> void:
	var fresh := _screen()
	fresh.setup(_actor())
	var at_start := _ascent(fresh)
	assert_eq(
		bool(at_start.get("offered", true)),
		false,
		"a hero at the first realm is offered no ascent: nothing is owed yet"
	)
	assert_eq(bool(at_start.get("required", true)), false, "and the facade agrees nothing is owed")
	fresh.free()

	var owed := _screen()
	owed.setup(_transcendent())
	var late := _ascent(owed)
	assert_eq(bool(late.get("required", false)), true, "an R28 hero owes the whole walk")
	assert_eq(int(late.get("steps", 0)), 4, "which is four steps of it")
	assert_eq(bool(late.get("offered", false)), true, "so the screen offers the control")
	owed.free()


## The same claim about the actual Button, not about the screen's own bookkeeping:
## a screen that reports `offered` while leaving `%AscendButton` disabled has
## still built a control no player can press.
func test_the_ascend_button_node_is_enabled_exactly_when_the_ascent_is_offered() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var button := screen.get_node_or_null("%AscendButton") as Button
	assert_ne(button, null, "the scene declares %AscendButton")
	if button == null:
		screen.free()
		return
	assert_eq(button.disabled, true, "a hero with no ascent owed cannot press it")
	screen.setup(_transcendent())
	assert_eq(
		button.disabled, false, "a hero who owes an ascent CAN press it, so the walk is reachable"
	)
	screen.free()


## The trap, pinned: `ascension_ok` is true for every target at or below
## `COMMIT_MICRO`, so an Immortal-tier hero owes nothing and must be offered
## nothing. Asserting an ascent is owed here would assert the opposite of the
## truth, which is why it is written down rather than left to a reader.
func test_no_ascent_is_owed_at_the_immortal_tier() -> void:
	var actor := _actor()
	actor.path(BodyPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX - 10)
	var screen := _screen()
	screen.setup(actor)
	var ascent := _ascent(screen)
	assert_eq(
		bool(ascent.get("required", true)),
		false,
		"ten realms below the Transcendent tier, no ascent is owed"
	)
	assert_eq(bool(ascent.get("offered", true)), false, "so none is offered")
	assert_eq(ascent.get("row", {}), {}, "and the screen draws no ascent row at all")
	screen.free()


# --- Pressing it walks the ascent --------------------------------------------


## THE END-TO-END CLAIM, on the app the player runs. A real `Button.pressed` on the
## screen the composition root mounted, bound to the app's own hero: the actor's
## `AscensionState` loses a step, the facade's read model reports it, and the row
## the player is looking at changes. Nothing here builds an actor or calls the
## core entry point itself — only the button does.
func test_a_player_can_walk_one_step_of_the_ascent_from_the_running_app() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(BODY_ROUTE)
	assert_eq(bool(moved["ok"]), true, "the body route opens: %s" % moved["note"])
	var screen := harness.live_screen()
	assert_ne(screen, null, "a live screen is on the stack")
	if screen == null:
		return
	assert_eq(harness.bound_actor(screen), harness.actor, "bound to the app's own hero")

	var hero := harness.actor
	hero.path(BodyPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
	WorldAnchor.commit(hero, WorldAnchor.COMMIT_MICRO)
	screen.call("refresh")

	var before := _ascent(screen)
	assert_eq(int(before.get("steps", 0)), 4, "the ascent starts with four steps to walk")
	var button := harness.button(screen, "%AscendButton")
	assert_ne(button, null, "the screen exposes the ascend control")
	if button == null:
		return
	assert_eq(harness.press(screen, "%AscendButton"), true, "and a player can press it")

	assert_eq(
		hero.ascension.steps,
		1,
		"the press walked a step on the app's own hero, not on a copy of it"
	)
	var after := _ascent(screen)
	assert_eq(int(after.get("steps", 0)), 3, "the screen shows three steps left")
	assert_eq(
		String(after.get("outstanding", "")),
		WorldAnchor.ascension_unmet(hero),
		"and the wording it shows is core's own, re-read after the press"
	)
	assert_ne(
		String(after.get("outstanding", "")),
		String(before.get("outstanding", "")),
		"so the player's own line changed: the walk is observable, not just recorded"
	)


## Walking the whole ascent, one press per step, until core itself refuses. The
## bound names a walk that would not finish; `WorldAnchor.ascend`'s own refusal is
## the loop's real exit, exactly as `test_full_traversal` does it.
func test_walking_every_step_completes_the_ascent_and_retires_the_control() -> void:
	var screen := _screen()
	var actor := _transcendent()
	screen.setup(actor)
	var guard := 0
	while not Breakthrough.ascension_ok(actor, TRANSCENDENT_INDEX + 1) and guard < 8:
		guard += 1
		assert_eq(screen.act_ascend(), true, "step %d of the walk was taken" % guard)
	var done := _ascent(screen)
	assert_eq(bool(done.get("met", false)), true, "the ascent is met once every step is walked")
	assert_eq(
		String(done.get("outstanding", "x")), "", "and core has nothing outstanding left to state"
	)
	assert_eq(
		bool(done.get("offered", true)),
		false,
		"so the control is retired rather than left live on a spent gate"
	)
	var button := screen.get_node_or_null("%AscendButton") as Button
	assert_ne(button, null, "the control still exists")
	if button != null:
		assert_eq(button.disabled, true, "and a player cannot press a finished ritual")
	var row := done.get("row", {}) as Dictionary
	assert_eq(
		String(row.get("name", "")),
		"The ascent is walked",
		"the row reports the finished state instead of vanishing"
	)
	screen.free()


## A refusal has to be legible. An `act_ascend` that returned false and said
## nothing would be indistinguishable from a button wired to nothing at all
## (ADR 0043).
func test_ascending_with_nothing_owed_is_refused_and_says_why() -> void:
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(screen.act_ascend(), false, "no ascent is owed, so nothing is walked")
	var view := screen.summary()
	assert_eq(String(view.get("tone", "")), "error", "the refusal is reported as one")
	assert_ne(String(view.get("message", "")), "", "with a message, not silence")


# --- The bar, and the wording -------------------------------------------------


## The bar counts the steps STILL TO WALK, which is the quantity core's own wording
## names, so the label, the number and the bar can never disagree. A progress bar
## that filled as the ritual advanced would contradict both.
func test_the_ascent_bar_counts_the_steps_still_to_walk() -> void:
	var screen := _screen()
	screen.setup(_transcendent())
	var ascent := _ascent(screen)
	var row := ascent.get("row", {}) as Dictionary
	assert_eq(row.is_empty(), false, "the ascent row is bound and drawn")
	assert_eq(
		int(row.get("current", -1)), int(ascent.get("steps", 0)), "the bar counts what is left"
	)
	assert_eq(
		int(row.get("maximum", -1)), int(ascent.get("steps_total", 0)), "out of the whole walk"
	)
	assert_eq(bool(row.get("bar_visible", false)), true, "and it is drawn as a bar")
	assert_almost_eq(
		float(row.get("bar_ratio", -1.0)),
		float(ascent.get("steps", 0)) / float(ascent.get("steps_total", 1)),
		"the bar's fill is the fraction of the walk remaining"
	)
	assert_eq(screen.act_ascend(), true, "one step walked")
	var after := _ascent(screen).get("row", {}) as Dictionary
	assert_eq(
		int(after.get("current", -1)),
		int(_ascent(screen).get("steps", 0)),
		"and the bar drained by exactly the step taken"
	)
	screen.free()


## ADR 0034: the screen reports the rule `Breakthrough.ascension_ok` enforces
## instead of restating the requirement. Asserted as string EQUALITY against core's
## own call, so a reworded requirement cannot drift away from the wording on screen.
func test_the_outstanding_wording_is_cores_own_verbatim() -> void:
	var actor := _transcendent()
	var screen := _screen()
	screen.setup(actor)
	var ascent := _ascent(screen)
	assert_ne(
		String(ascent.get("outstanding", "")), "", "core states a requirement while steps remain"
	)
	assert_eq(
		String(ascent.get("outstanding", "")),
		WorldAnchor.ascension_unmet(actor),
		"the screen publishes core's wording, not a paraphrase"
	)
	assert_eq(
		String((ascent.get("row", {}) as Dictionary).get("name", "")),
		WorldAnchor.ascension_unmet(actor),
		"and the row LABEL is that same string, never a restatement of the rule"
	)
	screen.free()


## `WorldAnchor.NO_ASCENT` is core declining to state a requirement, not a
## requirement. Driven at `realm:transcendent` + `commit:27` the row printed it as
## its label, with `required: true`, `offered: false` and a `0/4` bar beside it — so
## the player was shown an ascent that did not exist yet and a control they could
## not press. The guard used to suppress the sentinel only below the Transcendent
## tier, which is not where the condition that produces it stops applying.
func test_the_no_ascent_sentinel_is_never_rendered_as_a_requirement() -> void:
	var actor := _transcendent()
	# No `AscensionState` on this actor, so core has nothing to state.
	actor.ascension = null
	var screen := _screen()
	screen.setup(actor)
	assert_eq(
		WorldAnchor.ascension_unmet(actor),
		WorldAnchor.NO_ASCENT,
		"precondition: core declines to state a requirement"
	)
	var ascent := _ascent(screen)
	assert_eq(
		String((ascent.get("row", {}) as Dictionary).get("name", "")),
		"",
		"so the row takes no space rather than advertising a gate"
	)
	assert_eq(String(ascent.get("shown", "x")), "", "and reports that it showed nothing")
	# The facade's own value is still published untouched: the screen suppresses a
	# SENTENCE, it does not filter the data a caller reads.
	assert_eq(
		String(ascent.get("outstanding", "")),
		WorldAnchor.NO_ASCENT,
		"the raw view is unchanged; only the wording on screen is withheld"
	)
	screen.free()


## Focus follows the only thing left to do. Cultivate is the landing spot
## normally; once a tier gate has opened an ascent it is the ascent.
func test_focus_lands_on_the_ascent_once_one_is_owed() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.focus_initial()
	assert_eq(
		String(screen.summary().get("focus_target", "")),
		"CultivateButton",
		"training is first while nothing is owed"
	)
	screen.setup(_transcendent())
	screen.focus_initial()
	assert_eq(
		String(screen.summary().get("focus_target", "")),
		"AscendButton",
		"and the ascent is first once the gate has opened it"
	)
	screen.free()


## The four high-tier gates are published as four booleans so a screen can say
## WHICH is shut; this asserts the screen passes all four through rather than
## collapsing them into one `ready`.
func test_every_tier_gate_is_reported_individually() -> void:
	var screen := _screen()
	screen.setup(_transcendent())
	var gates := screen.summary().get("tier_gates", {}) as Dictionary
	for gate in ["tribulation", "inside_world", "world", "ascent"]:
		assert_eq(gates.has(gate), true, "the %s gate is reported in its own right" % gate)
		assert_eq(
			gates[gate] is bool, true, "and it is a boolean, not a restatement of the whole gate"
		)
	assert_eq(
		bool(gates.get("ascent", true)),
		false,
		"an unwalked ascent leaves the ascent gate shut, which is the whole point"
	)
	screen.free()
