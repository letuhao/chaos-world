extends TestCase

## THE WORLD'S CLOCK, REACHABLE FROM A PLAYER.
##
## Measured before this suite existed: `rg 'advance_one_period|world_summary' game/src/ui`
## returned NOTHING. `WorldPulse.pull` ran on every frame of the running build and no
## surface read it — the tick existed, and no player could advance the world, see its
## news, or observe that time had passed. These tests are the receipt for the fix, and
## each one names the defect it would let back in.
##
## Three claims, in order of how badly a failure would hurt:
##
##  1. **The panel owns presentation and nothing leaks.** A readout that rebuilds its
##     rows with `queue_free()` accumulates one row set per repaint forever, and the
##     headless runner never processes a frame to drain them.
##  2. **The screen derives, it does not decide.** `recorded` is read per fact out of
##     the actor's ledger. The pulse publishes a COUNT of how much of its roster the
##     world has heard; a count cannot say WHICH, so a screen that read the count and
##     marked every row heard would render a world that knows more than it does.
##  3. **No second copy of the pulse's numbers.** `PERIOD_FACT` and `PERIOD_SECONDS`
##     live in `app/`, which `ui/` may not reference. A literal here would be a private
##     copy that stays numerically identical and silently wrong the day the cadence is
##     retuned — the failure `tests/core/test_realm_rate.gd` was written to catch.
##
## The final test drives the REAL `ItemWorkbenchApp` through the REAL `ScreenStack`. It
## is the acceptance claim for criteria 1 and 2, and it is RED until the composition
## root binds a `WorldPulseBridge` into the world route.

const PANEL_SCENE := "res://src/ui/panels/world_pulse_panel.tscn"
const SCREEN_SCENE := "res://src/ui/screens/world_map_screen.tscn"
const UI_ROOT := "res://src/ui"
## The roster `WorldAmbient.ROSTER` names. Spelled here rather than read from `app/`,
## which is the point of claims 3: this suite is allowed to know the ids, the UI
## program is not.
const ROSTER: Array[String] = [
	"storm_front_sighted",
	"void_seam_sounded",
	"tournament_called",
	"sect_war_called",
]
## What the panel says when nobody wired a clock. Asserted as a literal rather than
## read from the panel's own constant, so renaming the constant without changing what
## a player reads is a failure here.
const UNWIRED_CLOCK := "No world clock is wired to this screen."
const UNWIRED_CADENCE := "The world's cadence is not published here."

## The period ledger's count, standing in for the pulse's own. Only the SCREEN may not
## hardcode it; a test may, because a test is allowed to state the expectation.
const PERIOD_FACT := &"world_period_elapsed"

## Depth ceiling for the control walk. The panel sits three levels below the screen, so
## this is slack rather than a tuned number.
const MAX_TREE_WALK := 12

var _born: Array[Node] = []

## The fake world a test drives the screen against. Hand-built rather than mounted, so
## every assertion is about the UI program's own arithmetic and not about a pulse's.
var _world_periods: int = 0
var _advance_calls: int = 0
var _advance_result: Dictionary = {"ok": true, "reason": ""}
var _roster: Array[String] = []

# --- Panel: presentation, and nothing that accumulates ------------------------


func test_panel_reports_a_shaped_view_before_anything_is_shown() -> void:
	# A panel has no actor to bind, so its empty summary is a SHAPED view rather than
	# `{}` — `test_ui_conventions.gd` guards that distinction. Every key is present and
	# every value primitive, so a test never has to guess which key a repaint omitted.
	var panel := _panel()
	var view := panel.summary()
	assert_ne(view.is_empty(), true, "the panel reports a shaped view with nothing shown")
	assert_eq(view.get("wired", true), false, "nothing has been shown yet")
	assert_eq(view.get("can_advance", true), false, "a panel nobody asked cannot advance")
	assert_eq(view.get("wait_enabled", true), false, "the wait control starts unavailable")
	assert_primitives(view)
	_free_all()


func test_panel_says_out_loud_that_no_clock_is_wired() -> void:
	# An unwired clock reading as zero rows and an enabled-looking button is how a
	# missing seam stays invisible. The panel must NAME it.
	var panel := _panel()
	panel.show_world({})
	var view := panel.summary()
	assert_eq(view.get("clock_text", ""), UNWIRED_CLOCK, "the missing clock is named, not blank")
	assert_eq(view.get("cadence_text", ""), UNWIRED_CADENCE, "the missing cadence is named too")
	assert_eq(view.get("wait_enabled", true), false, "and the control is disabled")
	assert_eq(view.get("wait_label", ""), "Wait a season (unavailable)", "the label says why")
	_free_all()


func test_panel_owns_the_period_format() -> void:
	var panel := _panel()
	panel.show_world({"wired": true, "periods": 7, "period_count": 7})
	var view := panel.summary()
	assert_eq(
		view.get("clock_text", ""),
		"Period 7 passed - 7 recorded in the world's memory",
		"the screen passed two raw counts and the panel worded both"
	)
	_free_all()


func test_panel_owns_the_cadence_format() -> void:
	# 120 seconds is the pulse's authored period. The panel is the only place allowed
	# to turn it into something a player can use, and it must not hardcode it either.
	var panel := _panel()
	panel.show_world({"wired": true, "period_seconds": 120.0})
	assert_eq(
		panel.summary().get("cadence_text", ""),
		"One period every 2m 00s",
		"seconds became minutes, in the panel"
	)
	_free_all()


func test_panel_news_headline_counts_only_what_the_world_heard() -> void:
	var panel := _panel()
	panel.show_world({"wired": true, "news": _rows(2)})
	var view := panel.summary()
	assert_eq(
		view.get("news_title", ""),
		"The world's news (2/4 heard)",
		"the headline counts the recorded rows, not the roster length"
	)
	assert_eq(view.get("heard_count", 0), 2, "two of the four are heard")
	_free_all()


func test_panel_rebuilds_its_news_rows_without_accumulating() -> void:
	# THE LEAK GUARD. `queue_free()` defers to the end of the frame and the headless
	# runner never processes one, so a deferred row stays parented forever and every
	# repaint stacks another copy on top. Four repaints of a four-row list must leave
	# exactly four children, not sixteen.
	var panel := _panel()
	for pass_index in 3:
		panel.show_world({"wired": true, "news": _rows(2)})
	assert_eq(
		_news_box(panel).get_child_count(), 4, "three repaints of a four-row list leave four rows"
	)
	assert_eq(panel.summary().get("news_count", 0), 4, "the reported list did not grow either")
	_free_all()


func test_panel_enables_wait_only_when_the_caller_allows_it() -> void:
	var panel := _panel()
	panel.show_world({"wired": true, "can_advance": false})
	assert_eq(
		panel.summary().get("wait_enabled", true), false, "a clock that cannot be asked is disabled"
	)
	panel.show_world({"wired": true, "can_advance": true})
	assert_eq(panel.summary().get("wait_enabled", false), true, "and enabled once it can")
	assert_eq(panel.summary().get("wait_label", ""), "Wait a season", "the label drops the excuse")
	_free_all()


func test_panel_emits_a_request_and_never_advances_anything_itself() -> void:
	# The panel has no clock and no ledger, so pressing its button must be a REQUEST.
	# A panel that advanced the world would be a second dispatcher for one moment.
	var panel := _panel()
	var requests: Array[int] = []
	panel.advance_requested.connect(func() -> void: requests.append(1))
	panel.show_world({"wired": true, "can_advance": true})
	_harness_press(panel, "%WaitButton")
	assert_eq(requests.size(), 1, "the button asked exactly once")
	_free_all()


# --- Screen: the clock, with and without the bridge ---------------------------


func test_screen_reports_no_clock_until_the_bridge_is_bound() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var world := _world_of(screen)
	assert_eq(world.get("wired", true), false, "no bridge, no clock")
	assert_eq(world.get("can_advance", true), false, "so the wait control is not offered")
	assert_eq(world.get("clock_text", ""), UNWIRED_CLOCK, "and the readout says so")
	_free_all()


func test_screen_reads_the_news_out_of_the_ledger_with_no_bridge() -> void:
	# The world's MEMORY is on the actor and `WorldFact` is `core/`, so the news is
	# readable with nothing wired at all. That is the half of the gap a player could
	# be shown today, and it must not depend on the composition root.
	var actor := _actor()
	WorldFact.record(actor, StringName(ROSTER[0]), 1)
	WorldFact.record(actor, PERIOD_FACT, 3)
	var screen := _screen()
	screen.setup(actor)
	var news := _news_of(screen)
	assert_eq(news.size(), 2, "both remembered facts are listed")
	assert_eq(
		_news_has(news, ROSTER[0]),
		true,
		"a fact the world heard is listed from the ledger, not from a roster it has"
	)
	_free_all()


func test_pressing_wait_without_a_bridge_refuses_and_names_the_missing_seam() -> void:
	var screen := _screen()
	screen.setup(_actor())
	assert_eq(screen.act_wait_season(), false, "an unwired clock cannot advance")
	var world := _world_of(screen)
	assert_eq(world.get("tone", ""), "error", "the refusal is an error, not a silence")
	assert_eq(
		world.get("message_text", ""),
		"This screen is not wired to the world clock",
		"the message names the seam, so an unreachable tick is never mistaken for a quiet one"
	)
	_free_all()


func test_pressing_wait_advances_the_world_when_a_bridge_is_bound() -> void:
	# The whole point, driven the way a player drives it: press the real control, on
	# the mounted scene, and watch the period count move.
	var actor := _actor()
	var screen := _screen()
	screen.setup(actor)
	screen.bind_world(_bridge())
	var before := int(_world_of(screen).get("periods", 0))
	assert_eq(_harness_press(screen, "%WaitButton"), true, "the wait control is live")
	var after := int(_world_of(screen).get("periods", 0))
	assert_eq(_advance_calls, 1, "the bridge was asked exactly once")
	assert_eq(after, before + 1, "and the world moved one period")
	_free_all()


func test_pressing_wait_reports_a_refusal_the_pulse_returned() -> void:
	# `EventApi.advance` refuses `periods <= 0` by design, and a pulse with no actor or
	# no director refuses too. A refusal must reach the player in the pulse's own
	# vocabulary rather than being swallowed into a cheerful "A season passes".
	_advance_result = {"ok": false, "reason": "no_director"}
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	assert_eq(screen.act_wait_season(), false, "a refusal is not an advance")
	var world := _world_of(screen)
	assert_eq(world.get("tone", ""), "error", "and it is reported as one")
	assert_eq(
		world.get("message_text", ""),
		"No one is listening for what happens",
		"in the wording the panel owns"
	)
	_free_all()


func test_the_recorded_flag_comes_from_the_ledger_not_from_the_roster_count() -> void:
	# THE DERIVATION CLAIM. The pulse publishes `ambient_recorded`, a COUNT of how much
	# of its roster the world has heard. A count cannot say WHICH. A screen that read
	# the count and marked every row heard would render a world that remembers four
	# things when it remembers one — and the headline "4/4 heard" would agree with the
	# rows and be wrong about the world. The ledger is the world's memory, so this is
	# read per fact.
	var actor := _actor()
	WorldFact.record(actor, StringName(ROSTER[0]), 1)
	_roster = ROSTER.duplicate() as Array[String]
	var screen := _screen()
	screen.setup(actor)
	screen.bind_world(_bridge())
	var news := _news_of(screen)
	assert_eq(news.size(), 4, "the whole roster is listed, heard or not")
	assert_eq(_heard_count(news), 1, "exactly the one fact in the ledger is marked heard")
	assert_eq(
		_world_of(screen).get("news_title", ""),
		"The world's news (1/4 heard)",
		"the headline follows the ledger, not the roster"
	)
	_free_all()


# --- Structural guards: no second copy, no `app/` reach, and no orphan panel ----


func test_no_ui_file_carries_a_second_copy_of_the_pulse_period_fact() -> void:
	# `WorldPulse.PERIOD_FACT` is `app/`'s, and `app` is a private unit, so the UI
	# program must never learn the id. A literal here would be numerically identical
	# and silently wrong the day the constant is retuned — the private-copy failure
	# `tests/core/test_realm_rate.gd` exists to catch, in a second place.
	var files := _ui_files("gd")
	_assert_scan_is_real(files, "world_pulse_panel.gd")
	for entry in files:
		assert_eq(
			_code_only(entry["text"] as String).contains(String(PERIOD_FACT)),
			false,
			(
				"%s restates the pulse's period fact id; read it through the bridge instead"
				% entry["path"]
			)
		)


func test_no_ui_file_names_a_world_type_from_app() -> void:
	# `WorldPulse`, `WorldAmbient` and `EventApi` are all unreachable from `ui/` by
	# rule. Reaching for one anyway is how a second dispatcher for a world period gets
	# written, and the arch checker sees it only as a private-unit reference.
	var files := _ui_files("gd")
	_assert_scan_is_real(files, "world_pulse_bridge.gd")
	for entry in files:
		var code := _code_only(entry["text"] as String)
		for banned in ["WorldPulse.", "WorldAmbient.", "EventApi.", "res://src/app/"]:
			assert_eq(
				code.contains(banned),
				false,
				"%s reaches %s, which `ui/` may not name; use the bridge" % [entry["path"], banned]
			)


func test_the_world_pulse_panel_is_mounted_by_a_screen_a_route_can_open() -> void:
	# A panel no routed screen instances is the exact defect this work exists to end,
	# one layer down: shipped, reachable only by a test. Discovered from the filesystem
	# and asked of the shipped route table, so this cannot be satisfied by naming the
	# scene in a test.
	var screens := _ui_files("tscn", "screens")
	_assert_scan_is_real(screens, "world_map_screen.tscn")
	var mounted := false
	for entry in screens:
		if (entry["text"] as String).contains("world_pulse_panel.tscn"):
			mounted = true
			assert_ne(
				ScreenRoutes.id_for_scene(entry["path"]),
				"",
				"%s instances the world pulse panel and is routed" % entry["path"]
			)
	assert_eq(mounted, true, "a shipped screen instances world_pulse_panel.tscn")


## THE PRECONDITION ON EVERY SOURCE GUARD ABOVE.
##
## A walk that visits nothing reports every file as clean, and a filter that matches
## nothing is the same number as a tree with nothing to report — so a guard over
## `res://src/ui` can look perfect in the tally while reading zero files. Assert the
## walk found a file it was supposed to find BEFORE trusting its verdict, or the guard
## is decoration. `test_ui_conventions.gd` carries the same argument for its own scan,
## after a suffix filter that rejected the whole tree went unnoticed for a long time.
func _assert_scan_is_real(files: Array[Dictionary], must_contain: String) -> void:
	assert_ne(files.is_empty(), true, "the UI program walk visited files, so its verdict is real")
	var found := false
	for entry in files:
		if String(entry["path"]).ends_with(must_contain):
			found = true
	assert_eq(found, true, "the walk visited %s, so it can see the files it guards" % must_contain)


# --- The production seam: the running build -----------------------------------


func test_the_running_build_lets_a_player_advance_the_world_from_the_world_route() -> void:
	# Drives the real `ItemWorkbenchApp` through the real `ScreenStack`, the way a
	# player does: navigate to the route, press the control. This is the acceptance
	# claim for "a player can reach it" and "reachable by pressing something".
	#
	# RED until `ItemWorkbenchApp._bind_route_screen` binds the world bridge. The fix
	# is two lines and lives in `app/`, which this task does not own:
	#
	#     ROUTE_WORLD_MAP:
	#         screen.call("setup", _actor)
	#         screen.call("bind_world", _world_bridge())
	#
	# with `_world_bridge()` returning a `WorldPulseBridge` whose `read_state` is
	# `Callable(self, "world_summary")` and whose `advance` is
	# `Callable(self, "advance_one_period")` — the two methods
	# `ItemWorkbenchApp` already publishes.
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(&"world_map")
	assert_eq(bool(moved["ok"]), true, "the world route is reachable: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen()
	assert_ne(live, null, "the world route left a live screen")
	if live == null:
		return
	var world := (live.call(&"summary") as Dictionary).get("world", {}) as Dictionary
	assert_eq(
		world.get("can_advance", false),
		true,
		(
			"MISSING SEAM: the world route shows a clock no player can move. The composition "
			+ "root binds no WorldPulseBridge into world_map_screen, so the button is dead. "
			+ 'Add `screen.call("bind_world", _world_bridge())` to '
			+ "ItemWorkbenchApp._bind_route_screen's ROUTE_WORLD_MAP arm."
		)
	)
	var before := int(world.get("periods", 0))
	assert_eq(harness.press(live, "%WaitButton"), true, "the player can press 'Wait a season'")
	var after := int(
		((live.call(&"summary") as Dictionary).get("world", {}) as Dictionary).get("periods", 0)
	)
	assert_eq(after, before + 1, "and the world's period count moved by one")


func teardown() -> void:
	# Everything this suite instantiated is freed here, not at each call site: an
	# early return in a test would otherwise skip its own cleanup, and the runner
	# shares one process across every suite.
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_free_all()


# --- Fixtures ----------------------------------------------------------------


func _panel() -> WorldPulsePanel:
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as WorldPulsePanel
	_born.append(panel)
	return panel


func _screen() -> WorldMapScreen:
	var screen := (load(SCREEN_SCENE) as PackedScene).instantiate() as WorldMapScreen
	_born.append(screen)
	return screen


## An actor the world map can render. `WorldApi.locations` is the screen's other
## dependency and it answers for any actor, so nothing extra is attached here — the
## world's own state comes from the bridge and the ledger, which is the claim.
func _actor() -> Actor:
	return Actor.new(&"world_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})


## A bridge whose clock is this suite's own counter, so an assertion about the world
## moving is an assertion about the UI program calling the seam rather than about a
## pulse's arithmetic.
func _bridge() -> WorldPulseBridge:
	var bridge := WorldPulseBridge.new()
	bridge.read_state = Callable(self, "_fake_state")
	bridge.advance = Callable(self, "_fake_advance")
	return bridge


func _fake_state() -> Dictionary:
	return {
		"periods": _world_periods,
		"period_count": _world_periods,
		"period_seconds": 120.0,
		"offered": _world_periods * 3,
		"claimed": _world_periods * 2,
		"opened": mini(_world_periods, 2),
		"institution_acted": 0,
		"institution_refused": 0,
		"sinks": ["QuestBeatHandler", "EventBeatSink"],
		"period_fact": String(PERIOD_FACT),
		"ambient_facts": _roster,
		"ambient_recorded": _world_periods,
		"world_period": 0,
		"active_events": mini(_world_periods, 1),
		"available_events": 2,
	}


func _fake_advance() -> Dictionary:
	_advance_calls += 1
	if not bool(_advance_result.get("ok", false)):
		return _advance_result.duplicate()
	_world_periods += 1
	return {"ok": true, "reason": "", "periods": _world_periods}


## `heard` rows of the four-fact roster, in roster order.
func _rows(heard: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in ROSTER.size():
		out.append({"fact": ROSTER[index], "recorded": index < heard})
	return out


func _news_box(panel: WorldPulsePanel) -> Node:
	return panel.get_node_or_null("%NewsBox")


## Press a unique-named control the way `SeamHarness.press` does, and report whether
## it was possible at all. A disabled control is not a successful press.
##
## The unique name first, then a depth-capped name search: `%WaitButton` is declared
## by the panel's OWN scene, so a unique name resolved from the screen does not reach
## it and only the fallback finds the control the player sees.
func _harness_press(node: Node, unique_name: String) -> bool:
	var target := node.get_node_or_null(unique_name) as Button
	if target == null:
		target = _find_button(node, unique_name.trim_prefix("%"), 0)
	if target == null or target.disabled:
		return false
	target.pressed.emit()
	return true


## The first `Button` named `node_name` anywhere under `node`. Depth-capped because a
## walk with no cap is the recursive-loop shape `test_no_unbounded_wait.gd` cannot see.
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


func _news_of(screen: Node) -> Array:
	return _world_of(screen).get("news", []) as Array


func _news_has(news: Array, fact: String) -> bool:
	for entry in news:
		if String((entry as Dictionary).get("fact", "")) == fact:
			return true
	return false


func _heard_count(news: Array) -> int:
	var count := 0
	for entry in news:
		if bool((entry as Dictionary).get("recorded", false)):
			count += 1
	return count


## Every file under the UI program, filtered by extension and directory. Iterative, not
## recursive: `test_ui_conventions.gd` measured that a recursive `DirAccess` walk
## silently returns nothing under this runner, which would make every guard above pass
## vacuously — the exact false green these guards exist to prevent.
func _ui_files(extension: String, under: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[String] = [UI_ROOT]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path := current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif path.get_extension() == extension and (under.is_empty() or path.contains(under)):
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
## failed by it. `test_ui_conventions.gd` carries the longer version of this argument.
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


## Every value reachable from `value` is a primitive, a String, an array, or a
## dictionary of those. A `Node`, `Resource` or `Object` in a summary is how a
## testable surface quietly stops being testable.
func assert_primitives(value: Variant) -> void:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return
		TYPE_DICTIONARY:
			for key in value as Dictionary:
				assert_primitives(key)
				assert_primitives((value as Dictionary)[key])
			return
		TYPE_ARRAY:
			for item in value as Array:
				assert_primitives(item)
			return
		_:
			assert_eq(true, false, "non-primitive value in summary(): %s" % typeof(value))


## Free everything this suite instantiated. Detached before freed, because a node
## still parented does not release. Never `queue_free()`: the headless runner drives
## every test from `SceneTree._initialize()`, which returns before the first frame, so
## a deferred free never runs and the node leaks into the next suite.
func _free_all() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
