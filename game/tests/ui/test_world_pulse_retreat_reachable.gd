extends TestCase

## ADR 0167's SEASON-SCALE CLASS, REACHABLE FROM A PLAYER.
##
## ## Why this file exists, and what it refuses to prove
##
## Measured before this suite existed: `grep retreat game/src/ui` returned ZERO hits.
## `ItemWorkbenchPlay.retreat` was complete, correct, cost nothing to expose — and no
## player could reach it, because the one legal seam between `ui/` and `app/`
## ([WorldPulseBridge]) carried exactly `{"state", "advance"}` and the only player-
## reachable world-time verb paid a single period. The audit's word for that is UNWIRED,
## and it is not the same defect as a broken verb: everything the retreat needs already
## existed and every player-facing piece of it was missing.
##
## **Nothing here calls `retreat()` on the play half.** `tests/app/
## test_retreat_costs_world_time.gd` already proves the verb pays a declared span, prices
## it per period and hands the crossed magnitudes to a consumer that acts on them. A test
## that calls it again would re-prove arithmetic and still pass on a build where no player
## could reach it — which is precisely the false green this file is written against.
##
## ## What IS claimed here, in order of how badly a failure would hurt
##
##  1. **The seam advertises the action.** A bridge slot nobody reads is a line the
##     composition root maintains for nothing; a slot nobody FILLS is the original defect.
##  2. **The panel exposes the control**, disabled when unwired — so a missing seam is
##     visible rather than a dropdown that silently does nothing.
##  3. **The screen answers the chosen length**, priced BEFORE the press, in the clock's
##     own authored magnitudes and never in a duration this file invented.
##  4. **The offered lengths are spans the chunk plan accepts**, so every choice on the
##     selector is a price the clock can actually quote rather than one it must refuse.
##
## Cases 1–4 need no mounted composition root, which is deliberate: the mount is one
## `item_workbench_app.gd` parse error away, and a reachability suite that can go red for
## a peer's in-flight split proves nothing about reachability.

const PANEL_SCENE := "res://src/ui/panels/world_pulse_panel.tscn"
const SCREEN_SCENE := "res://src/ui/screens/world_map_screen.tscn"
const BRIDGE_SOURCE := "res://src/ui/screens/world_pulse_bridge.gd"
const PLAY_SOURCE := "res://src/app/item_workbench_play.gd"
const BODY_SOURCE := "res://src/app/item_workbench_body.gd"

## What the screen calls the panel's request with, and what the panel must therefore
## publish. Spelled here rather than read from either file, so a rename that broke the
## pairing would fail rather than quietly agree with itself.
const RETREAT_SLOT := "retreat"

## Depth ceiling for the control walk. The panel sits three levels below the screen, so
## this is slack rather than a tuned number.
const MAX_TREE_WALK := 12
## The per-call ceiling the chunk plan is handed. Spelled here because `ui/` and a test
## may reach `core/` but NOT `app/` — reading `WorldPulse.MAX_PERIODS_PER_PULL` would be
## the private-unit reach `test_no_ui_file_names_the_app_half_the_bridge_exists_to_hide`
## refuses, and restating the plan the pulse uses in a test would be a second place for
## it to be wrong. What IS claimed is the shape: every offered span is covered exactly.
const MAX_PERIODS_PER_PULL := 8

var _born: Array[Node] = []
## Period counts the suite drove through the bridge, and the spans it was asked for, so
## every assertion about "the player chose a duration" is a statement about a CALL and
## not about the UI program's own arithmetic.
var _retreat_calls: Array[int] = []
var _retreat_answer: Dictionary = {"ok": true, "reason": ""}
var _world_periods: int = 0

# --- 1. The seam advertises the action ---------------------------------------


## THE FIRST LINK, and the claim the audit measured as zero. The bridge is the ONLY legal
## edge from `ui/` to `app/` (`app` is a `PRIVATE_UNIT` in `tools/arch/rules.py`), so a
## verb that is not a slot here cannot be called by a screen at all — there is no second
## way in.
func test_the_bridge_advertises_a_retreat_action() -> void:
	var bridge := _bridge()
	assert_eq(
		bridge.has(&"retreat"),
		true,
		(
			"MISSING SEAM: WorldPulseBridge carries state and advance but no retreat, so "
			+ "ADR 0167's season-scale class has nowhere to land and no player can reach it."
		)
	)
	assert_eq(bridge.has(&"advance"), true, "and the one-period verb is still advertised beside it")
	assert_eq(bridge.has(&"state"), true, "as is the readout, which the panel prices from")


## The two other slots must still ANSWER. A bridge whose `_actions` table quietly lost a
## row would keep `has()` green for the slots it kept, so this asks the whole table rather
## than the new entry alone.
func test_the_retreat_slot_answers_a_dictionary() -> void:
	var bridge := _bridge()
	var answer := bridge.call_action(&"retreat", [360])
	assert_eq(answer.get("declared", 0), 360, "the chosen period count reached the verb")
	assert_eq(answer.get("paid", 0), 360, "and the report says what was PAID for it, not the ask")
	assert_eq(
		_retreat_calls,
		[360],
		"the bridge carried the player's own count, so the argument really is the cost"
	)


## An unwired slot reads as unavailable rather than as a working action, which is what
## lets a screen disable a control instead of pretending the verb ran.
func test_an_unwired_retreat_reads_as_unavailable() -> void:
	var bridge := WorldPulseBridge.new()
	assert_eq(bridge.has(&"retreat"), false, "a bridge nobody filled carries no retreat")
	assert_eq(
		bridge.call_action(&"retreat", [12]),
		{},
		"and calling it is an empty answer, never a crash and never a false success"
	)


# --- 2. The PANEL exposes the control ----------------------------------------


## THE CONTROL EXISTS. A panel that published a `retreat` signal and no widget would be
## the same unwired defect one layer down — shipped, drivable from a test, invisible to a
## player — so the selector and the button are looked up by the unique names the scene
## declares rather than inferred from a method list.
func test_the_panel_exposes_a_length_choice_and_a_sit_button() -> void:
	var panel := _panel()
	var option := panel.get_node_or_null("%RetreatLength") as OptionButton
	var button := panel.get_node_or_null("%RetreatButton") as Button
	assert_ne(option, null, "the panel ships a selector a player chooses a length in")
	assert_ne(button, null, "and a button that asks for it")
	assert_eq(
		button.disabled,
		true,
		"and it starts unavailable: nothing has been wired, and an unreachable control must read so"
	)
	_free_all()


## Both halves of the ADR are offered at once: the one-period wait that already existed,
## and the chosen duration that did not. A retreat the player cannot choose the length of
## is a longer wait button, which is the defect this work exists to end.
func test_the_panel_offers_a_short_and_a_long_sit_beside_the_wait() -> void:
	var panel := _panel()
	panel.show_world(_view())
	var summary := panel.summary()
	assert_eq(summary.get("retreat_span_count", 0) >= 2, true, "at least a short and a long option")
	assert_eq(summary.get("can_advance", false), true, "and the one-period wait is still there")
	var spans := summary.get("retreat_spans", []) as Array
	if spans.size() < 2:
		_free_all()
		return
	var widest := 0
	for entry in spans:
		widest = maxi(widest, int((entry as Dictionary).get("periods", 0)))
	assert_eq(
		int(summary.get("retreat_declared_periods", 0)),
		int((spans[0] as Dictionary).get("periods", 0)),
		"the shortest offered length is what a player is shown first, so the default is one"
	)
	assert_eq(
		widest > int((spans[0] as Dictionary).get("periods", 0)),
		true,
		"and the list spans more than one magnitude, so the choice is a real one"
	)
	_free_all()


## ## Every offered length is a span the clock's chunk plan ACCEPTS
##
## ADR 0173 refuses to truncate: a span `TimeLadder.chunks_for` cannot cover comes back
## as `unplannable_span` with nothing paid. So an option the plan refuses is an option
## that renders, reads as a price and then refuses — which is why the check is made here,
## against the plan the pulse itself uses, rather than against a hand-picked list.
func test_every_offered_length_is_a_span_the_chunk_plan_accepts() -> void:
	var reader := WorldPulseReader.new()
	var spans := reader.retreat_spans()
	assert_eq(spans.is_empty(), false, "the clock publishes at least one sit length")
	for entry in spans:
		var periods := int((entry as Dictionary).get("periods", 0))
		var plan := TimeLadder.chunks_for(periods, MAX_PERIODS_PER_PULL)
		assert_eq(
			plan.is_empty(),
			false,
			(
				(
					"a %d-period sit must be plannable: an option the clock can only refuse "
					% periods
				)
				+ "is a price nobody could pay"
			)
		)
		assert_eq(
			TimeLadder.covered_periods(plan),
			periods,
			"and the plan covers exactly the span, so nothing is truncated on the way in"
		)
		assert_eq(plan.size() <= TimeLadder.MAX_CHUNKS, true, "within the authored chunk cap")


## The lengths are the LADDER'S OWN rows, so a retune of the authored `.tres` moves the
## selector with it. Asserted by reading the SSOT rather than by spelling numbers here: a
## literal in this file would be a second calendar that stays correct until the day it is
## not.
func test_the_offered_lengths_are_the_ladder_s_own_rows() -> void:
	var spans := WorldPulseReader.new().retreat_spans()
	var authored: Dictionary = {}
	for row in TimeLadder.magnitudes():
		authored[String(str(row.get("name", "")))] = int(row.get("ratio_periods", 0))
	for entry in spans:
		var row := entry as Dictionary
		var magnitude := String(row.get("magnitude", ""))
		assert_eq(
			int(row.get("periods", 0)),
			int(authored.get(magnitude, 0)),
			(
				(
					"%s is offered at the ladder's authored ratio, read through the SSOT rather "
					% magnitude
				)
				+ "than a number this suite or the UI program wrote"
			)
		)
	assert_eq(
		authored.has(String(TimeLadder.BASE)),
		true,
		"and the base row is left out: one period is the wait button's job, already named"
	)


## ## The cost is shown BEFORE it is paid, in the clock's own units
##
## The panel owns the wording (AGENTS.md: a screen passes raw values, a panel owns every
## `%d`), so the claim is about the sentence a player reads: a period count, and the
## magnitudes that span crosses. A duration in seconds — "10 days" for a month — is the
## private copy ADR 0050 and ADR 0116 exist to prevent, and no assertion here accepts one.
func test_the_panel_prices_the_chosen_sit_before_the_press() -> void:
	var panel := _panel()
	panel.show_world(_view())
	var summary := panel.summary()
	var text := String(summary.get("retreat_cost_label", ""))
	assert_eq(text.begins_with("This sit costs "), true, "a player is told what the press buys")
	assert_eq(
		text.contains("%d periods" % int(summary.get("retreat_declared_periods", 0))),
		true,
		"in periods, the clock's own unit"
	)
	var crossed := summary.get("retreat_crossed", {}) as Dictionary
	for magnitude in crossed:
		assert_eq(
			text.contains("%s x%d" % [String(magnitude), int(crossed[magnitude])]),
			true,
			(
				(
					"%s is one of the magnitudes the span crosses, and the panel names it with "
					% magnitude
				)
				+ "its count rather than inventing a duration"
			)
		)
	_free_all()


## The crossed figures in `summary()` are the LADDER'S OWN division, taken over the
## declared span — which is what makes the preview a forecast of the same calendar the
## paid report reads, not a second estimate of it.
func test_the_declared_cost_reports_the_ladders_own_division() -> void:
	var panel := _panel()
	panel.show_world(_view())
	var summary := panel.summary()
	var declared := int(summary.get("retreat_declared_periods", 0))
	assert_eq(
		String(summary.get("retreat_declared_magnitude", "")),
		_first_span_magnitude(),
		"and the declared span is named by the ladder's own row, not by a word this suite wrote"
	)
	assert_eq(
		summary.get("retreat_crossed", {}),
		_crossed_of(declared),
		"the preview crosses exactly what TimeLadder.magnitudes_crossed crosses, over the span"
	)
	_free_all()


## `summary()` is the contract every panel in this program publishes (AGENTS.md), and a
## screen nests it under its own key. A `Node`, a `Resource` or a `Signal` in here is how
## a testable surface quietly stops being testable, so the whole payload is walked.
func test_the_panel_summary_is_primitives_only() -> void:
	var panel := _panel()
	panel.show_world(_view())
	_assert_primitives(panel.summary())
	_free_all()


## With nothing wired the whole retreat row reads as unavailable, including the cost
## line — an empty price under a live dropdown reads as "free", which is the one reading
## this control must never give.
func test_an_unwired_clock_names_the_missing_seam_instead_of_pricing_a_free_sit() -> void:
	var panel := _panel()
	panel.show_world({})
	var summary := panel.summary()
	assert_eq(summary.get("can_retreat", true), false, "an unwired clock cannot be asked to sit")
	assert_eq(summary.get("retreat_button_enabled", true), false, "so the control is disabled")
	assert_eq(
		summary.get("retreat_button_label", ""),
		"Sit for this long (unavailable)",
		"and the label says why, so a missing seam is never mistaken for a quiet world"
	)
	assert_eq(
		String(summary.get("retreat_cost_label", "")).contains("costs"),
		false,
		"and nothing is priced, because nothing can be bought here"
	)
	_free_all()


# --- 3. The SCREEN answers the chosen length ----------------------------------


## The verb, driven the way a player drives it: press the real control on the mounted
## scene and watch what the bridge was asked for. **A `periods` count of more than one is
## the assertion** — the wait button pays exactly one, so a screen that routed the sit
## through the same verb would be indistinguishable from it here, and the whole ADR 0167
## class would still be unreachable in any sense a player could feel.
func test_pressing_the_sit_button_asks_the_bridge_for_the_chosen_length() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	var declared := int(world.get("retreat_declared_periods", 0))
	assert_eq(declared > 1, true, "the chosen sit is longer than the one-period wait")
	assert_eq(_harness_press(screen, "%RetreatButton"), true, "the control is live when wired")

	assert_eq(_retreat_calls, [declared], "the bridge was asked for exactly the chosen length")
	assert_eq(
		_world_periods,
		declared,
		"and the world moved that many periods, which is the cost the player was shown"
	)
	_free_all()


## An unwired bridge must refuse in the panel's own vocabulary rather than pay nothing
## quietly, because a retreat that fails and says nothing is indistinguishable from one
## the player is still sitting through.
func test_pressing_the_sit_without_a_bridge_refuses_and_names_the_missing_seam() -> void:
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(screen.act_retreat_periods(), false, "an unwired clock cannot be asked to sit")
	var world := _world_of(screen)
	assert_eq(world.get("tone", ""), "error", "the refusal is an error, not a silence")
	assert_eq(
		world.get("message_text", ""),
		"This screen cannot ask for a longer sit",
		"in the wording the panel owns"
	)
	_free_all()


## The reported cost is PAID, not declared. ADR 0167 makes gain proportional to the
## periods actually paid, so a screen that echoed the ask would report a cost the player
## never bore — and the interruption it exists to make legible would be invisible.
func test_the_screen_reports_what_a_retreat_paid_rather_than_what_it_asked() -> void:
	_retreat_answer = {"ok": true, "reason": "", "declared": 360, "paid": 120, "unpaid": 240}
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	assert_eq(screen.act_retreat_periods(360), true, "a partial retreat is still a retreat")
	assert_eq(
		_world_of(screen).get("message_text", ""),
		"You sat 120 of the 360 periods you chose - 240 were not paid for.",
		"the interruption is in the sentence a player reads, not only in a payload"
	)
	_free_all()


## The driver convention: a screen's `act_*` verb is what `tools ui drive --cmd <verb>`
## calls, so this is the whole of the drivable surface. Asserted by name against the
## mounted screen, not against a source scan, so a method that exists but cannot be
## reached is not what passes here.
func test_the_screen_publishes_a_retreat_verb_the_ui_driver_can_call() -> void:
	var screen := _screen()
	assert_eq(
		screen.has_method(&"act_retreat_periods"),
		true,
		"tools ui drive --cmd retreat resolves to act_retreat_periods; a verb no command line can reach is not offered"
	)
	screen.setup(_actor())
	screen.bind_world(_bridge())
	assert_eq(
		screen.act_retreat_periods(), true, "and it runs with no argument, reading the selector"
	)
	assert_eq(
		_retreat_calls.size(), 1, "paying the selected length once, with no argument invented"
	)
	_free_all()


# --- Structural guards: the wiring, read as text ------------------------------


## The composition root is what FILLS the slot, and it is the only place that may: a
## bridge whose `retreat` is wired to nothing is the original defect with a field added.
## Read as source because mounting the root is one parse error away, and a reachability
## suite that can go red for a peer's in-flight split proves nothing.
func test_the_composition_root_wires_the_retreat_slot_to_the_verb() -> void:
	var body := _read(BODY_SOURCE)
	assert_ne(body.is_empty(), true, "%s is readable" % BODY_SOURCE)
	assert_eq(
		body.contains('bridge.retreat = Callable(self, "retreat")'),
		true,
		(
			"MISSING SEAM: _world_bridge() fills state and advance but not retreat, so the "
			+ "verb exists and no player can reach it"
		)
	)
	var play := _read(PLAY_SOURCE)
	assert_eq(
		play.contains("func retreat(periods: int) -> Dictionary:"),
		true,
		"and the callable it names is the play half's own season-scale verb"
	)


## ## The SEAM, not a side door
##
## `ui/` may reach `app/` only through the bridge, so a screen that could name the verb
## some other way would be a second path to one period and the rule `PRIVATE_UNITS`
## exists for would be decorative. Read with comments stripped, because the files
## document this rule in prose and a guard that fires on its own documentation is a guard
## nobody trusts (`tests/modules/save/test_save_envelope.gd:281-297`).
func test_no_ui_file_names_the_app_half_the_bridge_exists_to_hide() -> void:
	var files := _ui_files("gd")
	assert_eq(files.is_empty(), false, "the UI walk visited files, so this verdict is real")
	for entry in files:
		var code := _code_only(entry["text"] as String)
		for banned in ["ItemWorkbench", "res://src/app/", "WorldPulse."]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s names %s; the clock arrives through WorldPulseBridge or not at all"
					% [entry["path"], banned]
				)
			)


## `ui/` holds no wall clock of its own (ADR 0089 / DEF-0111), and a cadence copied into
## a panel is a second definition that stays numerically identical until the day it is
## not — `tests/core/test_time_ladder_single_source.gd` is why that has to be a scan and
## not a value assertion.
func test_no_ui_file_reads_the_wall_clock() -> void:
	for entry in _ui_files("gd"):
		assert_eq(
			_code_only(entry["text"] as String).contains("Time.get_ticks"),
			false,
			(
				"%s reads the wall clock; world time is the clock's, not the UI program's"
				% entry["path"]
			)
		)


## The affordance is only real if some file in the UI program NAMES it. A grep is the
## measurement the audit took and found empty, so the measurement itself is pinned here:
## `retreat` must be reachable from `game/src/ui`, not merely callable from a test.
func test_the_word_retreat_appears_in_the_ui_program() -> void:
	var files := _ui_files("gd")
	var named: Array[String] = []
	for entry in files:
		if (entry["text"] as String).contains("retreat"):
			named.append(String(entry["path"]))
	assert_eq(
		named.is_empty(), false, "grep retreat game/src/ui finds nothing: the affordance is UNWIRED"
	)
	for path in ["world_pulse_bridge.gd", "world_pulse_panel.gd", "world_pulse_reader.gd"]:
		var found := false
		for entry in files:
			if (
				String(entry["path"]).ends_with(path)
				and (entry["text"] as String).contains("retreat")
			):
				found = true
		assert_eq(found, true, "%s is one of the three files the affordance lives in" % path)


# --- Fixtures -----------------------------------------------------------------


func _panel() -> WorldPulsePanel:
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as WorldPulsePanel
	_born.append(panel)
	return panel


func _screen() -> WorldMapScreen:
	var screen := (load(SCREEN_SCENE) as PackedScene).instantiate() as WorldMapScreen
	_born.append(screen)
	return screen


## An actor the world map can render, as `test_world_pulse.gd`'s own fixture does: the
## screen's other dependency answers for any actor, and the clock arrives by bridge.
func _actor() -> Actor:
	return Actor.new(&"retreat_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})


## A bridge whose clock is this suite's own counter, so an assertion about a retreat is an
## assertion about the UI PROGRAM calling the seam rather than about a pulse's
## arithmetic. The `retreat` callable is this suite's, and it answers the same three keys
## `ItemWorkbenchPlay.retreat` answers, which is the contract the slot is wired on.
func _bridge() -> WorldPulseBridge:
	var bridge := WorldPulseBridge.new()
	bridge.read_state = Callable(self, "_fake_state")
	bridge.advance = Callable(self, "_fake_advance")
	bridge.retreat = Callable(self, "_fake_retreat")
	return bridge


func _fake_state() -> Dictionary:
	return {
		"periods": _world_periods,
		"period_count": _world_periods,
		"period_seconds": 120.0,
		"offered": _world_periods * 3,
		"claimed": _world_periods * 2,
		"opened": mini(_world_periods, 2),
		"active_events": 0,
		"available_events": 2,
		"ambient_facts": [],
	}


func _fake_advance() -> Dictionary:
	_world_periods += 1
	return {"ok": true, "reason": "", "periods": _world_periods}


func _fake_retreat(periods: int) -> Dictionary:
	_retreat_calls.append(periods)
	var answer := _retreat_answer.duplicate()
	if not bool(answer.get("ok", false)):
		return answer
	# The fold pays the declared span in full and reports what MOVED, exactly as
	# `ItemWorkbenchPlay.retreat` reads it: a measurement, not a restatement of the ask.
	_world_periods += int(answer.get("declared", periods))
	answer["declared"] = int(answer.get("declared", periods))
	answer["paid"] = int(answer.get("paid", answer["declared"]))
	answer["unpaid"] = maxi(0, int(answer["declared"]) - int(answer["paid"]))
	answer["periods"] = _world_periods
	return answer


## The view a screen hands the panel, built from the SAME reader the production route
## uses, so the fixture and the shipped path cannot describe different clocks.
func _view() -> Dictionary:
	var reader := WorldPulseReader.new()
	reader.bind(_bridge())
	return reader.view(_actor())


func _first_span_magnitude() -> String:
	var spans := WorldPulseReader.new().retreat_spans()
	return "" if spans.is_empty() else String(spans[0].get("magnitude", ""))


func _crossed_of(span_periods: int) -> Dictionary:
	var out: Dictionary = {}
	var crossed := TimeLadder.magnitudes_crossed(span_periods)
	for entry in crossed:
		var count := int(crossed[entry])
		if count > 0:
			out[String(str(entry))] = count
	return out


## Press a unique-named control the way `SeamHarness.press` does, and report whether it
## was possible at all: a disabled control is not a successful press. The unique name
## first, then a depth-capped name search, because `%RetreatButton` is declared by the
## panel's OWN scene and a unique name resolved from the screen does not reach it.
func _harness_press(node: Node, unique_name: String) -> bool:
	var target := node.get_node_or_null(unique_name) as Button
	if target == null:
		target = _find_button(node, unique_name.trim_prefix("%"), 0)
	if target == null or target.disabled:
		return false
	target.pressed.emit()
	return true


## Depth-capped because a walk with no cap is the recursive-loop shape
## `test_no_unbounded_wait.gd` cannot see.
func _find_button(node: Node, node_name: String, depth: int) -> Button:
	if depth > MAX_TREE_WALK:
		return null
	for child in node.get_children():
		if String(child.name) == node_name and child is Button:
			return child as Button
		var found := _find_button(child, node_name, depth + 1)
		if found != null:
			return found
	return null


func _world_of(screen: Node) -> Dictionary:
	return (screen.summary() as Dictionary).get("world", {}) as Dictionary


## Every `.gd` under `res://src/ui`, as `{path, text}`. Iterative, not recursive:
## `test_ui_conventions.gd` measured that a recursive `DirAccess` walk silently returns
## nothing under this runner, which would make every guard above pass vacuously.
func _ui_files(extension: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[String] = ["res://src/ui"]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif path.get_extension() == extension:
				out.append({"path": path, "text": _read(path)})
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["path"] < b["path"])
	return out


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Source with comments stripped, so a file that DOCUMENTS the rule it follows is not
## failed by it.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var out := ""
		var quoted := false
		for i in line.length():
			var ch := line[i]
			if ch == '"':
				quoted = not quoted
			elif ch == "#" and not quoted:
				break
			out += ch
		kept.append(out)
	return "\n".join(kept)


## Every value reachable from `value` is a primitive, an array, or a dictionary of those.
func _assert_primitives(value: Variant) -> void:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return
		TYPE_DICTIONARY:
			for key in value as Dictionary:
				_assert_primitives(key)
				_assert_primitives((value as Dictionary)[key])
			return
		TYPE_ARRAY:
			for item in value as Array:
				_assert_primitives(item)
			return
		_:
			assert_eq(true, false, "non-primitive value in summary(): %s" % typeof(value))


## Everything this suite instantiated is freed here rather than at each call site: an
## early return in a test would otherwise skip its own cleanup, and the runner shares one
## process across every suite. Detached before freed, because a node still parented does
## not release, and never `queue_free()` — the runner never processes a frame.
func _free_all() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	_retreat_calls.clear()
