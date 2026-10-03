extends TestCase

## The tribulation is reachable by a PLAYER, not only by a module test (BL-0122).
##
## A green module suite proves the fight exists. It does not prove a screen offers
## it, so every assertion here is made against the shipped scene, driven through
## the same public `act_*` verbs the buttons call and asserted on `summary()` —
## never on pixels. Nothing here reaches a module internal to move state: every
## transition is a verb on the screen the player presses.
##
## The end-to-end claim is `test_the_screen_takes_a_player_through_the_fight`.
##
## No realm is named by position. Every index is derived from
## `Breakthrough.IMMORTAL_REALM_THRESHOLD`, because the ladder is append-only and
## an inserted realm shifts every index below it.

const SCREEN := "res://src/ui/screens/tribulation_screen.tscn"
const PANEL := "res://src/ui/panels/tribulation_panel.tscn"

# --- Fixtures -------------------------------------------------------------------


func _screen() -> TribulationScreen:
	var screen := (load(SCREEN) as PackedScene).instantiate() as TribulationScreen
	# Guard: a scene whose root script is unattached instantiates as a bare
	# Control, every cast below silently yields null, and each test then passes
	# against `{}`. Assert the wiring instead of trusting the cast.
	assert_ne(screen, null, "tribulation_screen.tscn roots a TribulationScreen")
	return screen


## Ladder index of the first realm the tribulation gate applies to.
func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## An actor standing at `index`, or immediately under the gate when `-1`, with a
## dao heart and a laid-out meridian network — a player who has been cultivating,
## not a stub.
func _hero(index: int = -1) -> Actor:
	var at := _gate() - 1 if index < 0 else index
	var realm_id := _realm_id(at)
	var actor := Actor.new(&"tribulation_ui_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	ItemsApi.attach(actor)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	return actor


# --- The screen contract ---------------------------------------------------------


## The documented contract: nothing, not keys, when no actor is bound. A screen
## that reports its widgets before it has an actor is a half-initialised read model
## a test can mistake for a real view.
func test_the_screen_reports_nothing_before_an_actor_is_bound() -> void:
	var screen := _screen()
	assert_ne(screen, null, "the scene loads")
	if screen == null:
		return
	assert_eq(screen.summary(), {}, "no actor, no view")
	screen.free()


func test_the_panel_reports_nothing_before_a_state_is_handed_to_it() -> void:
	var panel := (load(PANEL) as PackedScene).instantiate() as TribulationPanel
	assert_ne(panel, null, "tribulation_panel.tscn roots a TribulationPanel")
	if panel == null:
		return
	assert_eq(panel.summary(), {}, "no state, no row")
	panel.free()


## The panel's contract is "render whatever state it is handed", which makes each
## branch of the fight a deterministic rendering assertion here — the fight's roll
## is real, so this is where the two outcomes are pinned rather than in the screen
## test above. Both verdicts must read differently, or a player who lost cannot
## tell that they lost.
func test_the_panel_renders_both_verdicts_differently() -> void:
	var panel := (load(PANEL) as PackedScene).instantiate() as TribulationPanel
	assert_ne(panel, null, "the panel loads")
	if panel == null:
		return
	var won := _verdict_panel(panel, Tribulation.OUTCOME_SURVIVED, true)
	assert_eq(String(won["outcome"]), String(Tribulation.OUTCOME_SURVIVED), "a survived record")
	assert_eq(bool(won["gate_open"]), true, "shows the gate open")
	var lost := _verdict_panel(panel, Tribulation.OUTCOME_FAILED, false)
	assert_eq(String(lost["outcome"]), String(Tribulation.OUTCOME_FAILED), "a failed record")
	assert_eq(bool(lost["gate_open"]), false, "shows the gate shut")
	assert_ne(
		String(won["verdict"]), String(lost["verdict"]), "and the two read differently to a player"
	)
	panel.free()


## Below the gate the row must say so rather than render an empty fight, which is
## what a player standing at R3 would otherwise see.
func test_the_panel_says_when_no_tribulation_is_owed() -> void:
	var panel := (load(PANEL) as PackedScene).instantiate() as TribulationPanel
	assert_ne(panel, null, "the panel loads")
	if panel == null:
		return
	panel.set_state({"owed": false, "gate_open": true})
	var row := panel.summary() as Dictionary
	assert_eq(bool(row["owed"]), false, "nothing owed")
	assert_ne(String(row["verdict"]), "", "and the row still says something about it")
	assert_eq(String(row["verdict"]), _verdict_text(panel), "the verdict line matches")
	panel.free()


## Hand the panel a decided record of a given outcome and read its verdict line
## back, so a rendering assertion needs no scene tree and no roll.
func _verdict_panel(panel: TribulationPanel, outcome: StringName, gate_open: bool) -> Dictionary:
	(
		panel
		. set_state(
			{
				"owed": true,
				"target": _realm_id(_gate()),
				"target_name": "Earth Immortal",
				"max_waves": 7,
				"difficulty": 5.0,
				"chance": 0.5,
				"outcome": String(outcome),
				"gate_open": gate_open,
			}
		)
	)
	var row := panel.summary() as Dictionary
	row["verdict"] = _verdict_text(panel)
	return row


## The text of the panel's verdict label, or "" when the scene has no tree to
## resolve it against — which is the headless case, and the reason the two
## branches are asserted on `outcome` and `gate_open` above.
func _verdict_text(panel: TribulationPanel) -> String:
	var label := panel.get_node_or_null("%VerdictLabel") as Label
	return "" if label == null else label.text


func test_the_summary_is_primitives_with_the_panel_nested_under_its_own_key() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero())
	var view := screen.summary() as Dictionary
	assert_ne(view.is_empty(), true, "a bound actor renders a real view")
	assert_ne((view["tribulation"] as Dictionary).is_empty(), true, "with the panel's row nested")
	for key in ["owed", "target", "wave", "max_waves", "chance", "outcome", "gate_open"]:
		assert_ne(view.has(key), false, "%s is published" % key)
	screen.free()


# --- Below the gate ---------------------------------------------------------------


## The gate is legible in both directions: nothing is owed below the Immortal
## tier, the gate reads open, and no fight control is offered.
func test_below_the_gate_nothing_is_owed_and_no_fight_is_offered() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero(_gate() - 3))
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["owed"]), false, "no tribulation is owed this far down")
	assert_eq(bool(view["gate_open"]), true, "and the gate is open")
	var actions := view["actions"] as Dictionary
	assert_eq(bool(actions["begin"]), false, "no fight to face")
	assert_eq(bool(actions["fight"]), false, "no fight to wave-fight")
	screen.free()


# --- At the gate ------------------------------------------------------------------


func test_at_the_gate_the_fight_is_offered_and_the_gate_is_shut() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero())
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["owed"]), true, "a tribulation is owed")
	assert_eq(String(view["target"]), String(_realm_id(_gate())), "for the gate's realm")
	assert_eq(bool(view["gate_open"]), false, "and the gate is shut")
	assert_eq(bool((view["actions"] as Dictionary)["begin"]), true, "so the fight is offered")
	assert_eq(bool((view["actions"] as Dictionary)["fight"]), false, "before it has begun")
	screen.free()


func test_pressing_begin_puts_a_bound_fight_on_screen() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)
	assert_eq(screen.act_begin(), true, "the player faced the tribulation")
	assert_ne(hero.tribulation, null, "a record exists")
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["active"]), true, "the fight is in the air")
	assert_eq(
		String(view["bound"]),
		String(_realm_id(_gate())),
		"bound to the gate's realm, which the screen publishes"
	)
	assert_eq(bool((view["actions"] as Dictionary)["fight"]), true, "so the waves can be fought")
	assert_eq(bool((view["actions"] as Dictionary)["begin"]), false, "and it cannot be restarted")
	assert_eq(String(view["message"]), "The tribulation gathers", "and the outcome is reported")
	screen.free()


func test_pressing_begin_below_the_gate_is_refused_and_says_why() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero(0))
	assert_eq(screen.act_begin(), false, "nothing to face")
	var view := screen.summary() as Dictionary
	assert_eq(String(view["tone"]), "error", "reported as a refusal")
	assert_ne(String(view["message"]), "", "with a message, not silence")
	screen.free()


## Every wave is a real, observable step: the fight is a progression the player
## watches, not one opaque click.
##
## The wave counter does NOT rise on every press, and the test does not pretend it
## does: `Tribulation.advance_wave` holds the counter at `max_waves` and moves the
## PHASE to climax instead. What must hold is that the fight never goes backwards,
## never runs past its own wave count, and genuinely moved.
func test_fighting_waves_moves_the_record_and_keeps_it_on_screen() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero())
	screen.act_begin()
	var first := screen.summary() as Dictionary
	assert_eq(int(first["max_waves"]) > 1, true, "a fight is worth several waves")
	assert_eq(int(first["wave"]), 0, "and has not thrown one yet")
	var advanced := 0
	var guard := 0
	while guard < TribulationFight.WAVE_GUARD:
		guard += 1
		var before := screen.summary() as Dictionary
		if not bool((before["actions"] as Dictionary)["fight"]):
			break
		if not screen.act_fight_wave():
			break
		var after := screen.summary() as Dictionary
		if bool(after["decided"]):
			break
		if int(after["wave"]) > int(before["wave"]):
			advanced += 1
		assert_eq(
			int(after["wave"]) >= int(before["wave"]), true, "the wave counter never goes backwards"
		)
		assert_eq(
			int(after["wave"]) <= int(after["max_waves"]),
			true,
			"and never runs past the fight's own wave count"
		)
	assert_ne(advanced, 0, "the fight threw real waves, not one opaque click")
	assert_eq(advanced > 1, true, "and more than one")
	screen.free()


## Withdrawing is a real, visible choice: the record is gone and the gate is
## still shut.
func test_withdrawing_clears_the_fight_and_keeps_the_gate_shut() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)
	screen.act_begin()
	screen.act_fight_wave()
	assert_eq(screen.act_withdraw(), true, "the player walked away")
	assert_eq(hero.tribulation, null, "the record is gone")
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["has_record"]), false, "and the screen says so")
	assert_eq(bool(view["gate_open"]), false, "while the gate stays shut")
	assert_eq(
		bool((view["actions"] as Dictionary)["begin"]), true, "so the fight can be faced again"
	)
	screen.free()


# --- The end-to-end claim -----------------------------------------------------------


## THE DELIVERABLE. One screen, one hero, pressed verbs only: the gate is shut, the
## player faces the tribulation, fights it wave by wave to a verdict, and the
## screen reports a decided record whose outcome is one of the two the fight can
## produce — and the gate is open only when it was survived.
##
## The roll is real, so this deliberately does not assert WHICH outcome occurred.
## It asserts that a verdict is reached, that the outcome is one core's own
## vocabulary, and that the gate follows the outcome. The module suite pins each
## branch by fixing the roll; this pins that a player can reach the decision at all.
func test_the_screen_takes_a_player_through_the_fight() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)
	assert_eq(bool((screen.summary() as Dictionary)["gate_open"]), false, "shut to begin with")
	assert_eq(screen.act_begin(), true, "the player faced it")
	assert_eq(screen.act_fight_to_verdict(), true, "and fought it to a verdict")
	var view := screen.summary() as Dictionary
	assert_eq(bool(view["decided"]), true, "the screen shows the fight was decided")
	var survived := String(view["outcome"]) == String(Tribulation.OUTCOME_SURVIVED)
	assert_eq(
		survived or String(view["outcome"]) == String(Tribulation.OUTCOME_FAILED),
		true,
		"and the outcome is one of the two the fight can produce, not 'unresolved'"
	)
	# The load-bearing claim: what the player is told about the gate IS the fight's
	# own outcome, read back through core's predicate — not the screen's optimism.
	assert_eq(
		bool(view["gate_open"]), survived, "the gate reads open exactly when the fight was survived"
	)
	assert_eq(
		Breakthrough.tribulation_ok(hero, _gate()),
		survived,
		"and core agrees with what the screen is showing"
	)
	assert_eq(
		bool((view["actions"] as Dictionary)["begin"]),
		true,
		"and either way the next fight can be faced, so a loss is recoverable"
	)
	assert_ne(String(view["message"]), "", "and the outcome was reported, not left silent")
	screen.free()


## Focus follows the fight, and it is recorded even with no scene tree, so a
## headless caller can assert where a player would land.
func test_focus_records_a_target_without_a_scene_tree() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero())
	screen.focus_initial()
	assert_eq(
		String((screen.summary() as Dictionary)["focus_target"]), "BeginButton", "begin first"
	)
	assert_eq(screen.act_begin(), true, "the fight begins")
	screen.focus_initial()
	assert_eq(
		String((screen.summary() as Dictionary)["focus_target"]), "FightButton", "then the waves"
	)
	screen.free()


## The screen must never let a stray key press abandon a fight: `ui_cancel` belongs
## to the stack, which pops, and popping is not a decision to forfeit.
func test_a_keypress_cannot_forfeit_the_fight() -> void:
	var screen := _screen()
	if screen == null:
		return
	screen.setup(_hero())
	screen.act_begin()
	assert_eq(screen.on_stack_input(null), false, "the stack keeps ui_cancel")
	assert_ne(screen.actor().tribulation, null, "and the fight is still in the air")
	screen.free()
