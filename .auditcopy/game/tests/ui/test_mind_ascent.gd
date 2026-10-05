extends TestCase

## A MIND PLAYER CAN WALK THE TRANSCENDENT ASCENT (ADR 0021, ADR 0041).
##
## `test_full_traversal.gd` proves the mind ladder is gated on the ascent, and
## `test_mind_cultivation_screen.gd` proves the screen renders what the gate owes.
## Neither proves the gate can be SATISFIED from the screen, and the shape that
## leaves is a soft-lock rather than a difficulty: the conditions line rendered
## `Walk the ascent: 4 of 4 steps to walk` against a disabled Breakthrough button
## while no control anywhere on the screen walked it. This file drives the shipped
## screen and its button instead, and it is written as the mirror of
## `test_body_ascent.gd` because it is the same action: one verb, one enabled
## condition, one pair of refusal sentences.
##
## Nothing here invents the ascent. `WorldAnchor.commit(actor, COMMIT_MICRO)` is
## what the breakthrough into R28 does and the only thing that creates an
## `AscensionState`; the screen then reads its own facade and calls core's entry
## point. No facade verb is added — the ascent belongs to no single path, so the
## `mind_cultivation` facade stays at its 12-method cap and `ui` may call `core`
## directly (ADR 0041).
##
## Two traps this file is written around, both measured rather than assumed:
##
##  - The ascent only gates ABOVE the Transcendent tier. `ascension_ok` returns
##    true for any target at or below `WorldAnchor.COMMIT_MICRO` (27), so
##    asserting an ascent is owed at R27 asserts the opposite of the truth.
##  - Nothing here may branch on the outcome of a random roll. The ascent is
##    deterministic — `AscensionState.ascend` refuses only at the caps — so no
##    seed sweep is needed and none is used.

const SCREEN := "res://src/ui/screens/mind_cultivation_screen.tscn"
const BODY_SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"
const MIND_ROUTE := &"mind_cultivation"
## The first Transcendent realm. Entering it is what commits the milestone, and
## therefore what BEGINS the ascent; nothing before it produces one.
const TRANSCENDENT_INDEX := WorldAnchor.COMMIT_MICRO
## The last Immortal realm: still deep in the gated tier, and still owed nothing,
## because the ascent is a gate on the tier ABOVE it.
const IMMORTAL_INDEX := WorldAnchor.COMMIT_MICRO - 1
## Enough for four steps plus headroom, and it names the condition rather than
## hiding it: an ascent that had not converged in this many presses has not
## converged at all, and `WorldAnchor.ascend` refusing is the loop's real exit.
const WALK_GUARD := 8


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _screen() -> MindCultivationScreen:
	var screen := (load(SCREEN) as PackedScene).instantiate() as MindCultivationScreen
	assert_ne(screen, null, "mind_cultivation_screen.tscn roots a MindCultivationScreen")
	return screen


func _hero() -> Actor:
	var actor := Actor.new(&"mind_ascent_hero", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(actor, 64)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	return actor


## A mind hero standing in the first Transcendent realm, with the milestone that
## realm's breakthrough commits already applied — so the ascent exists and owes its
## whole walk. This is the state a player reaches after R28, not a shortcut past it.
func _transcendent() -> Actor:
	var actor := _hero()
	actor.path(MindPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_MICRO)
	MindTraining.synchronize(actor)
	assert_ne(actor.ascension, null, "the R28 milestone produced an ascent to walk")
	assert_eq(
		actor.ascension.steps,
		0,
		"and it is unwalked: the milestone BEGINS the ritual, it does not finish it"
	)
	return actor


## An Immortal-tier mind hero: past every other tier gate, and still owed no ascent.
func _immortal() -> Actor:
	var actor := _hero()
	actor.path(MindPath.PATH_ID).rank_id = _realm_at(IMMORTAL_INDEX)
	return actor


## Walk the whole ascent, one step per call, until core itself refuses.
func _walk(actor: Actor) -> void:
	var guard := 0
	while not actor.ascension.is_complete() and guard < WALK_GUARD:
		guard += 1
		WorldAnchor.ascend(actor)


func _realm_at(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _ascent(screen: MindCultivationScreen) -> Dictionary:
	return screen.summary().get("ascent", {}) as Dictionary


func _unmet(screen: MindCultivationScreen) -> Array:
	return screen.summary().get("unmet", []) as Array


func _live(screen: MindCultivationScreen) -> Dictionary:
	return (screen.summary().get("actions", {}) as Dictionary).get("enabled", {}) as Dictionary


## The `%AscendButton` a player sees. `ActionSet` creates one button per declared
## action and names it by the action id, so this node is not in the scene file and
## has to be found. Iterative with an explicit worklist, because a recursive walk of
## a node tree is one more unbounded walk to police.
func _ascend_button(screen: Node) -> Button:
	var pending: Array[Node] = [screen]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Button and String(node.name) == "AscendButton":
			return node as Button
		for child in node.get_children():
			pending.append(child as Node)
	return null


# --- The control is offered exactly when there is something to walk -----------


## A dead control is the failure this guards, in both directions: a player who
## cannot press it, and a button live for a hero with no ascent to walk. All three
## states are read off the facade's own read model, never off the screen's opinion.
func test_the_ascend_button_is_offered_only_while_an_ascent_is_owed() -> void:
	var fresh := _screen()
	fresh.setup(_hero())
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

	var spent := _transcendent()
	_walk(spent)
	var done := _screen()
	done.setup(spent)
	var after := _ascent(done)
	assert_eq(bool(after.get("met", false)), true, "the ascent is met once every step is walked")
	assert_eq(int(after.get("steps", 0)), 0, "and nothing is left to walk")
	assert_eq(
		bool(after.get("offered", true)),
		false,
		"so the control is retired, not left live on a spent gate"
	)
	done.free()


## The same claim about the actual Button, not about the screen's own bookkeeping: a
## screen that reports `offered` while leaving the control disabled has still built
## a control no player can press. `ActionSet.request` is the panel's own "as though
## its button were pressed" entry point and refuses a disabled action, so it is used
## as the second half of the claim — it is what the headless CLI drives.
func test_the_ascend_button_is_pressable_exactly_when_the_ascent_is_offered() -> void:
	var screen := _screen()
	screen.setup(_hero())
	var button := _ascend_button(screen)
	assert_ne(button, null, "the action row carries the ascend control")
	if button == null:
		screen.free()
		return
	assert_eq(button.disabled, true, "a hero with no ascent owed cannot press it")
	assert_eq(_actions(screen).request(&"ascend"), false, "and the press is refused")
	screen.setup(_transcendent())
	assert_eq(
		button.disabled, false, "a hero who owes an ascent CAN press it, so the walk is reachable"
	)
	assert_eq(_actions(screen).request(&"ascend"), true, "and the press is honoured")
	assert_eq(int(_ascent(screen).get("steps", 0)), 3, "which walked one step of the whole walk")
	screen.free()


## The trap, pinned: `ascension_ok` is true for every target at or below
## `COMMIT_MICRO`, so an Immortal-tier hero owes nothing and must be offered nothing.
## Asserting an ascent is owed here would assert the opposite of the truth, which is
## why it is written down rather than left to a reader.
func test_no_ascent_is_owed_at_the_immortal_tier() -> void:
	var screen := _screen()
	screen.setup(_immortal())
	var ascent := _ascent(screen)
	assert_eq(
		bool(ascent.get("required", true)),
		false,
		"one realm below the Transcendent tier, no ascent is owed"
	)
	assert_eq(bool(ascent.get("offered", true)), false, "so none is offered")
	assert_eq(bool(_live(screen).get("ascend", true)), false, "and the control is dead")
	screen.free()


# --- Pressing it walks the ascent --------------------------------------------


## THE END-TO-END CLAIM, on the app the player runs. A real press through the
## mounted app's own action row, bound to the app's own hero: the actor's
## `AscensionState` loses a step, the facade's read model reports it, and the
## conditions line the player is looking at changes. Nothing here builds an actor
## or calls the core entry point itself — only the button does.
func test_a_player_can_walk_one_step_of_the_ascent_from_the_running_app() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(MIND_ROUTE)
	assert_eq(bool(moved["ok"]), true, "the mind route opens: %s" % moved["note"])
	var screen := harness.live_screen()
	assert_ne(screen, null, "a live screen is on the stack")
	if screen == null:
		return
	var mind_screen := screen as MindCultivationScreen
	assert_ne(mind_screen, null, "and it is the mind screen")
	if mind_screen == null:
		return
	assert_eq(harness.bound_actor(mind_screen), harness.actor, "bound to the app's own hero")

	# The composition root builds the player on the body path, so the mind screen
	# mounts against a hero it cannot read. Enrol him the way `ActorFactory` enrols
	# anyone, then stand him in the state a player reaches after R28.
	var hero := harness.actor
	ActorFactory.with_mind_cultivation(hero, _realm_at(TRANSCENDENT_INDEX))
	MindCultivationApi.attach_sea(hero)
	WorldAnchor.commit(hero, WorldAnchor.COMMIT_MICRO)
	MindTraining.synchronize(hero)
	mind_screen.call("refresh")

	var before := mind_screen.summary().get("ascent", {}) as Dictionary
	assert_eq(int(before.get("steps", 0)), 4, "the ascent starts with four steps to walk")
	assert_eq(harness.action(mind_screen, &"ascend"), true, "and a player can press it")

	assert_eq(
		hero.ascension.steps,
		1,
		"the press walked a step on the app's own hero, not on a copy of it"
	)
	var after := mind_screen.summary().get("ascent", {}) as Dictionary
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
## the loop's real exit, exactly as `test_body_ascent.gd` does it.
func test_walking_every_step_completes_the_ascent_and_retires_the_control() -> void:
	var screen := _screen()
	var actor := _transcendent()
	screen.setup(actor)
	var guard := 0
	while not Breakthrough.ascension_ok(actor, TRANSCENDENT_INDEX + 1) and guard < WALK_GUARD:
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
	assert_eq(bool(_live(screen).get("ascend", true)), false, "and the row agrees it is dead")
	assert_eq(
		_unmet(screen).has(WorldAnchor.ascension_unmet(actor)),
		false,
		(
			"and the gate the control satisfied is no longer named as unmet, because core "
			+ "has nothing left to state"
		)
	)
	var button := _ascend_button(screen)
	assert_ne(button, null, "the control still exists")
	if button != null:
		assert_eq(button.disabled, true, "and a player cannot press a finished ritual")
	screen.free()


## A refusal has to be legible. An `act_ascend` that returned false and said
## nothing would be indistinguishable from a button wired to nothing at all
## (ADR 0043).
func test_ascending_with_nothing_owed_is_refused_and_says_why() -> void:
	var screen := _screen()
	screen.setup(_hero())
	assert_eq(screen.act_ascend(), false, "no ascent is owed, so nothing is walked")
	var view := screen.summary()
	assert_eq(String(view.get("tone", "")), "error", "the refusal is reported as one")
	assert_ne(String(view.get("message", "")), "", "with a message, not silence")
	screen.free()


# --- The gate the screen shows is the gate the screen can open ----------------


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
	screen.free()


## THE SOFT-LOCK THIS FILE EXISTS FOR. Before the verb, the conditions line named
## the ascent while the only control that could satisfy it was absent: a gate the
## player could read and never pay. Asserted as a pair, because either half alone
## passes on the broken screen — the clause was already rendered, and a button that
## walks an ascent nobody owes is also not a soft-lock.
func test_every_ascent_clause_the_conditions_line_names_is_one_the_button_can_pay() -> void:
	var actor := _transcendent()
	var screen := _screen()
	screen.setup(actor)
	var clause := WorldAnchor.ascension_unmet(actor)
	assert_eq(
		_unmet(screen).has(clause),
		true,
		"precondition: the conditions line names the ascent as outstanding"
	)
	assert_eq(
		bool(_live(screen).get("ascend", false)),
		true,
		"and the screen offers a control that can satisfy it, so the gate is not a dead end"
	)
	assert_eq(
		bool(_live(screen).get("breakthrough", true)),
		false,
		"while the breakthrough it blocks stays refused — the ascent is the way through"
	)
	assert_eq(screen.act_ascend(), true, "the control pays it")
	# The clause does not VANISH — three steps are still owed — it counts down, and
	# the new count is core's own sentence re-read after the press.
	var paid := WorldAnchor.ascension_unmet(actor)
	assert_ne(paid, clause, "so the clause the line named changed rather than lying still")
	assert_eq(
		_unmet(screen).has(paid),
		true,
		"and the line carries core's new wording, not the one it was showing"
	)
	screen.free()


## The same claim in the other direction: a control live for an actor owed nothing
## invites a press that does nothing, which is the dead control this program keeps
## shipping from the other side.
func test_no_ascent_clause_is_named_while_the_control_is_dead() -> void:
	for label in ["first_realm", "immortal", "walked"]:
		var actor: Actor = _hero()
		if label == "immortal":
			actor = _immortal()
		elif label == "walked":
			actor = _transcendent()
			_walk(actor)
		var screen := _screen()
		screen.setup(actor)
		assert_eq(
			_unmet(screen).has(WorldAnchor.ascension_unmet(actor)),
			false,
			"%s: no walkable ascent is named as unmet" % label
		)
		assert_eq(
			bool(_live(screen).get("ascend", true)), false, "%s: and no control is live" % label
		)
		screen.free()


## `WorldAnchor.NO_ASCENT` is core declining to state a requirement, not a
## requirement: `ascension_unmet` returns it whenever the actor has no
## `AscensionState` yet, which is true at the top realm too until the R28
## breakthrough commits one. The checklist may still name it — it is one more unmet
## item there — but no screen may offer a control for it, because there is nothing
## to walk. Body asserts the matching half; this is the same state read from the
## mind side.
func test_the_no_ascent_sentinel_is_never_offered_as_a_control() -> void:
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
		String(ascent.get("outstanding", "")),
		WorldAnchor.NO_ASCENT,
		"the raw view is published unchanged; only the control is withheld"
	)
	assert_eq(bool(ascent.get("offered", true)), false, "so the control is not offered")
	assert_eq(bool(_live(screen).get("ascend", true)), false, "and the row agrees it is dead")
	assert_eq(screen.act_ascend(), false, "and pressing it walks nothing")
	screen.free()


# --- Focus -------------------------------------------------------------------


## Focus follows the only thing left to do. Meditation is the landing spot
## normally; once a tier gate has opened an ascent it is the ascent.
func test_focus_lands_on_the_ascent_once_one_is_owed() -> void:
	var screen := _screen()
	screen.setup(_hero())
	screen.focus_initial()
	assert_eq(
		String(screen.summary().get("focus_target", "")),
		"MeditateButton",
		"meditation is first while nothing is owed"
	)
	screen.setup(_transcendent())
	screen.focus_initial()
	assert_eq(
		String(screen.summary().get("focus_target", "")),
		"AscendButton",
		"and the ascent is first once the gate has opened it"
	)
	screen.free()


# --- Body and mind must not disagree -----------------------------------------


## One action, one answer. Both screens are handed the SAME state by the SAME two
## core calls — `WorldAnchor.commit` and `WorldAnchor.ascend` — so any disagreement
## about whether an ascent is owed, and what is left of it, belongs to the screens
## and not to the fixture. Three states, because the three are the only ones the
## conjunction can distinguish.
func test_mind_and_body_agree_about_the_same_ascent() -> void:
	for state in ["immortal", "owed", "walked"]:
		var pair := _pair(state)
		var mind := pair["mind_view"] as Dictionary
		var body := pair["body_view"] as Dictionary
		assert_eq(
			bool(mind.get("offered", true)),
			bool(body.get("offered", true)),
			"%s: both screens offer the control, or neither does" % state
		)
		assert_eq(
			int(mind.get("steps", -1)),
			int(body.get("steps", -1)),
			"%s: both screens count the same walk still to do" % state
		)
		assert_eq(
			String(mind.get("outstanding", "")),
			String(body.get("outstanding", "")),
			"%s: both screens publish core's own wording, so the sentences cannot drift" % state
		)
		assert_eq(
			bool(mind.get("met", false)),
			bool(body.get("met", false)),
			"%s: both screens agree the gate is satisfied" % state
		)
		_free_pair(pair)


## The same agreement, read off the two screens' refusal sentences. The verbs are
## the same action, so a player who has learned what body says when it refuses has
## learned what mind says — asserted as string EQUALITY against body itself rather
## than against a literal, so a reworded body sentence cannot leave this green
## against a mind screen that has drifted from it.
func test_mind_and_body_refuse_the_ascent_in_the_same_words() -> void:
	var pair := _pair("nothing_owed")
	var mind_screen := pair["mind_screen"] as MindCultivationScreen
	var body_screen := pair["body_screen"] as BodyCultivationPanel
	assert_eq(mind_screen.act_ascend(), false, "mind refuses an ascent it does not owe")
	assert_eq(body_screen.act_ascend(), false, "and so does body")
	assert_eq(
		String(mind_screen.summary().get("message", "")),
		String(body_screen.summary().get("message", "")),
		"in the same sentence, so the two screens teach one vocabulary"
	)
	assert_eq(
		String(mind_screen.summary().get("tone", "")),
		String(body_screen.summary().get("tone", "")),
		"and report it as the same kind of outcome"
	)
	_free_pair(pair)


## Both screens bound to the same shared state, and their ascent read models. Both
## screens are handed back so the CALLER frees them from one place: a screen freed
## at the point of construction is skipped by any branch that returns early, and the
## runner shares one process across every suite, so a leaked screen outlives the
## test that made it.
func _pair(state: String) -> Dictionary:
	var mind := _hero()
	var body := ActorFactory.with_body_cultivation(
		Actor.new(&"mind_ascent_body", {Stat.PHYSIQUE: 20.0})
	)
	ItemsApi.attach(body)
	BodyTraining.synchronize(body)
	if state == "immortal":
		mind.path(MindPath.PATH_ID).rank_id = _realm_at(IMMORTAL_INDEX)
		body.path(BodyPath.PATH_ID).rank_id = _realm_at(IMMORTAL_INDEX)
	elif state == "owed" or state == "walked":
		mind.path(MindPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
		body.path(BodyPath.PATH_ID).rank_id = _realm_at(TRANSCENDENT_INDEX)
		WorldAnchor.commit(mind, WorldAnchor.COMMIT_MICRO)
		WorldAnchor.commit(body, WorldAnchor.COMMIT_MICRO)
		MindTraining.synchronize(mind)
		BodyTraining.synchronize(body)
		if state == "walked":
			_walk(mind)
			_walk(body)
	var mind_screen := _screen()
	mind_screen.setup(mind)
	var body_screen := (load(BODY_SCREEN) as PackedScene).instantiate() as BodyCultivationPanel
	assert_ne(body_screen, null, "body_cultivation_panel.tscn roots a BodyCultivationPanel")
	var pair := {
		"mind_screen": mind_screen, "body_screen": body_screen, "mind_view": {}, "body_view": {}
	}
	if body_screen == null:
		return pair
	body_screen.setup(body)
	pair["mind_view"] = mind_screen.summary().get("ascent", {})
	pair["body_view"] = body_screen.summary().get("ascent", {})
	return pair


## Free both screens of a pair. One place, so a caller that returns early above
## cannot leak one of them.
func _free_pair(pair: Dictionary) -> void:
	for key in ["mind_screen", "body_screen"]:
		var node := pair.get(key) as Node
		if node != null and is_instance_valid(node):
			node.free()


func _actions(screen: MindCultivationScreen) -> ActionSet:
	return screen.get_node_or_null("%Actions") as ActionSet
