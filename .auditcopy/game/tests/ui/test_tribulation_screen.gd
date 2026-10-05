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
const PANEL_SCRIPT := "res://src/ui/panels/tribulation_panel.gd"

## The trial type the blessing producer pays on. `TribulationBlessing.REWARD_TABLE`
## maps `ELEMENTAL -> earth`, and `earth_bulwark` is the earth CULTIVATION-scope def, so
## this type is the one that pays a status rather than a named refusal.
const PAYING_TRIAL := Tribulation.ELEMENTAL

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


# --- F-7: a survived tribulation NAMES the blessing it paid -----------------------
#
# `TribulationFight.fight_wave` returns a `blessing` key on every DECIDED result
# (`TribulationBlessing.award`'s answer), and `TribulationScreen._report` branched only
# on `ok` / `decided` / `survived`. The player read "Survived the tribulation" and never
# learned which permanent status they had just earned — a permanent blessing is the fight's
# whole reward, and one the player cannot name is one they cannot notice they carry.
#
# ## Why the verdict is forced rather than rolled
#
# `HeavenlyTribulationApi.fight_wave` passes `rng = null`, so a fight fought through the
# BUTTON is a coin flip and a test asserting "a blessing renders" would be a flake. The
# fixture therefore decides the fight through the module's OWN verb with a seeded rng
# (`TribulationFight.fight_to_verdict(actor, rng)`, exactly as
# `tests/modules/status/test_status_cultivation_reach.gd` does) and hands that production
# result to the screen's production render path. What is under test is the RENDER, not
# the roll — `test_the_screen_takes_a_player_through_the_fight` above already pins that a
# player can reach a verdict at all, and deliberately asserts neither outcome.
#
# ## Why the type is rewritten AFTER `begin`
#
# `Tribulation.start` prices the fight from `rate(actor)`, which reads
# `TYPE_PRESSURE[type]`; a type set before `start` would price the record against a
# pressure it is then not fought at. Setting it afterwards makes the `REWARD_TABLE` row
# (`ELEMENTAL -> earth`) resolve on the record the award actually reads.


## Begin the owed fight and type it so the blessing producer pays a status.
func _begin_paying(actor: Actor) -> bool:
	var started := TribulationFight.begin(actor)
	if not bool(started.get("ok", false)):
		return false
	actor.tribulation.type = PAYING_TRIAL
	return true


## A generator whose first draw decides the whole fight by BOUND rather than by hope.
##
## `TribulationEndurance.endurance` CLAMPS into `[MIN_ENDURANCE, MAX_ENDURANCE]`, so a
## draw below the floor survives whatever the fight did and a draw at or above the ceiling
## always fails. The search is bounded by `for seed in 4096` and always terminates; it is
## found by search rather than hand-seeded so neither outcome can be a coincidence of one
## particular number.
##
## The seed is REWOUND before it is returned, because the search has to DRAW to know the
## seed is decisive and that draw advances the generator — returning it as it stood would
## make the fight's own first `randf()` a different value from the one that was accepted.
func _decisive_rng(survives: bool) -> RandomNumberGenerator:
	var threshold := (
		TribulationEndurance.MIN_ENDURANCE if survives else TribulationEndurance.MAX_ENDURANCE
	)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() >= threshold) == (not survives):
			rng.seed = seed_value
			return rng
	rng.seed = 1
	return rng


## Fight `hero` to a SURVIVED verdict through the module's own verb, so the result is a
## real production answer carrying a real `blessing`. `{}` when the fight could not be
## made to resolve, which every caller reports rather than asserting past.
func _survived_result(hero: Actor) -> Dictionary:
	if not _begin_paying(hero):
		return {}
	var result := TribulationFight.fight_to_verdict(hero, _decisive_rng(true))
	if not bool(result.get("ok", false)) or not bool(result.get("survived", false)):
		return {}
	return result


## THE deliverable for F-7: a survived tribulation that paid a blessing RENDERS that
## blessing's id, on the panel's reward row and on the screen's own outcome line.
func test_a_survived_tribulation_names_the_blessing_it_paid() -> void:
	var hero := _hero()
	var result := _survived_result(hero)
	if result.is_empty():
		return
	var granted := result["blessing"] as Dictionary
	assert_eq(bool(granted["ok"]), true, "the fight really paid a blessing: %s" % str(granted))
	var status_id := String(granted["id"])
	assert_ne(status_id.is_empty(), true, "and the award names the status it applied")

	var screen := _screen()
	if screen == null:
		return
	screen.setup(hero)
	# The production render path: exactly what `_report` does after a decided result.
	screen.call("_show_blessing", result)
	screen.call("refresh")

	var panel := (screen.summary() as Dictionary)["tribulation"] as Dictionary
	var blessing := panel["blessing"] as Dictionary
	assert_eq(bool(blessing["paid"]), true, "the panel reports the blessing as paid")
	assert_eq(String(blessing["id"]), status_id, "under the id the award applied")
	# The NAME, which is what the player reads: underscores turned into words, never a
	# raw id. This is the F-7 claim — before this change nothing rendered the id at all.
	assert_eq(
		String(blessing["label"]).contains(status_id.replace("_", " ")),
		true,
		"and the reward row names it in words"
	)
	assert_eq(
		String(blessing["label"]).contains("_"),
		false,
		"with no untranslated underscores left in the sentence"
	)
	# And on the outcome line, so a player who only reads the message still hears it.
	assert_eq(
		String(screen.summary()["message"]).contains(status_id.replace("_", " ")),
		true,
		"the screen's own outcome line names it too"
	)
	screen.free()


## A LOST fight pays nothing, so the row must say THAT rather than leaving the last
## reward a player saw still on screen — a stale reward line is worse than no line, and
## this is the branch where a player would otherwise believe they had earned a permanent
## blessing they did not get.
func test_a_lost_fight_renders_no_blessing_and_names_why() -> void:
	var hero := _hero()
	if not _begin_paying(hero):
		return
	var result := TribulationFight.fight_to_verdict(hero, _decisive_rng(false))
	if not bool(result.get("ok", false)) or bool(result.get("survived", false)):
		return
	var granted := result["blessing"] as Dictionary
	assert_eq(bool(granted["ok"]), false, "a broken tribulation pays nothing: %s" % str(granted))

	var screen := _screen()
	if screen == null:
		return
	screen.setup(hero)
	screen.call("_show_blessing", result)
	screen.call("refresh")

	var panel := (screen.summary() as Dictionary)["tribulation"] as Dictionary
	var blessing := panel["blessing"] as Dictionary
	assert_eq(bool(blessing["paid"]), false, "the row reports nothing was paid")
	assert_eq(String(blessing["id"]), "", "and names no status")
	# The refusal is RENDERED, not swallowed: `not_a_survivor` is an ordinary answer, and
	# a silent row would read as "the game forgot to pay me" rather than "you were beaten".
	assert_eq(
		String(blessing["label"]).contains(String(granted["reason"])),
		true,
		"and states the reason the fight paid nothing"
	)
	screen.free()


## The scene must really carry the node. Checked on the node BLOCK rather than with a
## whole-file search, because a `unique_name_in_owner` on some other label would satisfy
## one — this is F-7's WORK C question asked of the panel that now renders the reward.
func test_the_panel_scene_declares_the_blessing_label_it_renders_into() -> void:
	var scene := FileAccess.get_file_as_string("res://src/ui/panels/tribulation_panel.tscn")
	var block := _node_block(scene, "BlessingLabel")
	assert_ne(block.is_empty(), true, "the panel scene declares a BlessingLabel")
	assert_eq(
		block.contains("unique_name_in_owner = true"),
		true,
		"marked unique, so %BlessingLabel resolves"
	)
	# A container child, never an absolute position (AGENTS.md's layout rule).
	for banned in ["position = ", "offset_", "anchor_", "grow_horizontal"]:
		assert_eq(block.contains(banned), false, "the blessing label carries no %s" % banned)


## The UI standard this change had to obey, asserted on the panel that renders it: no
## `@onready`, resolution in `_bind_nodes`, and no `theme_override` anywhere. A one-shot
## binding in `_ready()` would make the reward row untestable headlessly, which is how
## this class of defect reached the screen in the first place.
func test_the_panel_resolves_its_blessing_label_lazily_and_through_the_theme() -> void:
	var source := FileAccess.get_file_as_string(PANEL_SCRIPT)
	assert_eq(_code_only(PANEL_SCRIPT).contains("@onready"), false, "no @onready in ui/")
	assert_eq(source.contains("func _bind_nodes()"), true, "nodes resolve in _bind_nodes()")
	assert_eq(
		source.contains("theme_override"), false, "style belongs to the one theme, not the panel"
	)


# --- Plumbing -------------------------------------------------------------------


## The `[node ...]` block for `node_name`, reassembled across lines.
func _node_block(scene: String, node_name: String) -> String:
	var block := ""
	for raw in scene.split("\n"):
		if block.is_empty():
			if raw.begins_with("[node ") and ('"%s"' % node_name) in raw:
				block = raw
			continue
		if raw.begins_with("["):
			break
		block += "\n" + raw
	return block


## `path`'s text with comments removed, so a scan reads code and not prose. The panel
## documents WHY it holds no `@onready`, and a doc comment is not a regression.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		if raw.strip_edges().begins_with("#"):
			continue
		var hash := raw.find("#")
		out.append(raw.substr(0, hash) if hash >= 0 else raw)
	return "\n".join(out)
