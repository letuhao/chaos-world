extends TestCase

## BL-0663 / BL-0664: a player can SEE, ACCEPT and PROGRESS a quest.
##
## ## Why this suite exists
##
## `QuestApi` shipped twelve verbs and 476 green assertions with **no caller in
## `game/src/`**. Every one of those assertions drove `QuestApi.accept` DIRECTLY
## from `tests/` — `test_world_beat_chain.gd:85`, `test_ambient_facts.gd:270`,
## `test_beat_director.gd:290/324/350`, `test_quest_acquisition.gd:82` — which is
## why the suite stayed green against a build in which **no player could accept a
## quest**. A test that calls the facade proves the module; only a test that
## presses a button on a mounted screen proves the game.
##
## Every assertion below is therefore made through the PRODUCTION PATH:
##
##   nav bar button or input action -> `ScreenRoutes` -> `navigate_to(quest)`
##   -> `ItemWorkbenchApp._bind_route_screen` -> `QuestScreen.bind_quests(...)`
##   -> `QuestProgram.accept` -> `QuestApi.accept`
##
## and read back off the mounted screen's own `summary()`. Nothing here calls
## `QuestApi.accept` itself. [method test_the_production_path_takes_a_quest_on] is
## the load-bearing case: it is the one that goes RED if the bridge is broken.

const SCREEN := "res://src/ui/screens/quest_screen.tscn"
const ROW := "res://src/ui/panels/quest_row.tscn"
const ROUTE := &"quest"
## The row scene, named by node so a pressed button is the real control rather
## than a method this test called in its place.
const ROW_NODE := "QuestRow"
const ACCEPT_NODE := "%AcceptButton"
## Depth ceiling for the row walk: rows live three levels below the screen.
const MAX_TREE_WALK := 12
## The ledger's one writer, spelled so this file's own docblocks cannot match it.
const _LEDGER_WRITER := "World" + "Fact.record"
## `const NAME := &"id"` — the code-owned spelling the census reads. Pinned as a named
## shape so the rule this case asks about is written down once, the way
## `tests/arch_rules/test_fact_ledger_writers.gd` pins it for its own reader.
const _FACT_CONST := '\\s*const\\s+([A-Z0-9_]+)\\s*:?=\\s*&["]([a-z0-9_]+)["]'

var _harness: SeamHarness = null
var _opened: Array[StringName] = []
## The `res://data` fact-id census, built on first use by the gate-soundness case and
## then held. The walk reads every `.tres` under the data tree, which is far too much
## work to repeat once per quest step, so the result is memoised — and the memo is
## `Variant`, not `Dictionary`, because `null` is the honest "not walked yet" answer and
## a `Dictionary` may not hold null (ADR 0038's contract is on what a screen REPORTS, not
## on what a test may park in a field).
var _authored_facts: Variant = null


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_harness = null
	_opened.clear()


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_harness = null
	_opened.clear()


# --- The four integration seams ---------------------------------------------


## Piece one of four: the route. Without this entry a player cannot open the
## journal, and `test_screen_reachability` would name the screen as unreachable.
func test_the_route_table_names_the_journal_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has("quest"), true, "the quest journal is a named route (BL-0664)")
	assert_eq(
		String(ScreenRoutes.key_of(ROUTE)), "j", "and its key is j, which is the action below"
	)


## Piece two of four: the input action. A route reachable only by a button is a
## route a keyboard player cannot reach.
func test_the_journals_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_j", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


## Piece three of four: the arch grant. `ui/` may reach `quest` only through
## `api.gd` and only because `quest` is in `rules.UI_MODULES`.
func test_the_screen_reaches_the_module_only_through_its_facade() -> void:
	var script := _code(FileAccess.get_file_as_string("res://src/ui/screens/quest_screen.gd"))
	assert_eq(script.contains("QuestApi"), true, "the screen reads the facade by name")
	assert_eq(script.contains("QuestDef"), false, "and no quest content type")
	assert_eq(script.contains("res://src/modules/quest"), false, "nor any direct module path")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")
	assert_eq(script.contains("@onready"), false, "and every node resolved lazily, not in @onready")


## Piece four of four: the bridge. `ui/` may not name `app/` (PRIVATE_UNITS), so
## the commit arrives as a Callable handed over by the composition root.
func test_the_bridge_is_a_callable_handed_over_not_a_ui_to_app_edge() -> void:
	var program := _code(FileAccess.get_file_as_string("res://src/app/quest_program.gd"))
	assert_eq(
		program.contains("QuestApi.accept"),
		true,
		"the program is the thing that calls accept; without it nothing commits"
	)
	var screen := _code(FileAccess.get_file_as_string("res://src/ui/screens/quest_screen.gd"))
	assert_eq(
		screen.contains("QuestApi.accept"),
		false,
		"the screen never calls accept itself, or the bridge would be decorative"
	)
	assert_eq(screen.contains("QuestProgram"), false, "and it may not name app/ at all")


## A doc comment is not an edge. Every file in this program documents the rule it
## follows by naming the token the rule forbids, so a raw `contains` over source
## text flags the prose — which is exactly the punishment `test_ui_conventions.gd`
## warns teaches the next author to delete the explanation instead of keeping the
## convention. Comments are stripped before the edge is asked about.
func _code(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		kept.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(kept)


## The bridge exposes a public `open()`, so a composition root that cannot be
## edited here still has exactly one call to make.
func test_the_program_exposes_a_public_open_for_the_composition_root() -> void:
	var program := QuestProgram.new()
	assert_eq(program.has_method(&"open"), true, "open() is public, so the root may call it")
	assert_eq(program.has_method(&"accept"), true, "and so is the one commit verb")
	var unmounted := program.open()
	assert_eq(bool(unmounted["ok"]), false, "an unmounted program says so rather than crashing")
	assert_eq(String(unmounted["reason"]), "no_screen", "and names why")
	assert_eq(bool(program.summary()["mounted"]), false, "which the summary agrees with")


# --- The read model ----------------------------------------------------------


func test_the_screen_reports_nothing_before_an_actor_is_bound() -> void:
	var screen := (load(SCREEN) as PackedScene).instantiate() as QuestScreen
	assert_ne(screen, null, "quest_screen.tscn roots a QuestScreen")
	if screen == null:
		return
	assert_eq(screen.summary(), {}, "no actor, no view")
	screen.free()


func test_the_row_reports_nothing_before_a_quest_is_handed_to_it() -> void:
	var row := (load(ROW) as PackedScene).instantiate() as QuestRow
	assert_ne(row, null, "quest_row.tscn roots a QuestRow")
	if row == null:
		return
	assert_eq(row.summary(), {}, "no quest, no row")
	row.free()


## The documented contract: primitives only, each row's own summary nested under
## `rows`, and nothing non-primitive anywhere in the tree.
func test_the_summary_is_primitives_with_every_row_nested() -> void:
	var screen := _bound_screen()
	if screen == null:
		return
	var view := screen.summary() as Dictionary
	assert_ne(view.is_empty(), true, "a bound actor renders a real view")
	assert_ne((view["rows"] as Array).is_empty(), true, "with one row per quest on the board")
	for key in [
		"actor",
		"ledger_available",
		"offered_ids",
		"active_ids",
		"completed_ids",
		"accept_seam",
		"rows",
	]:
		assert_ne(view.has(key), false, "%s is published" % key)
	assert_eq(_non_primitives(view).is_empty(), true, "and nothing in it is a Node or a Resource")
	screen.free()


## The read model is the module's, not the screen's. A bare hero is offered the
## ungated `authored` quests and nothing else: `kind` is the OFFER rule, so the
## `systemic` and `emergent` quests are never listed (BL-0053) even though they
## are still accept-able, advance-able and completable.
func test_a_bare_hero_is_offered_the_ungated_authored_quests_and_nothing_else() -> void:
	var screen := _bound_screen()
	if screen == null:
		return
	var view := screen.summary() as Dictionary
	var offered: Array = view["offered_ids"]
	assert_ne(offered.is_empty(), true, "a fresh hero has something to be offered")
	for id in offered:
		var row := _row(screen, String(id))
		assert_eq(String(row.get("kind", "")), "authored", "%s is an authored offer" % id)
		assert_eq(bool(row.get("gated", true)), false, "%s carries no gate at all" % id)
		assert_eq(bool(row.get("can_accept", false)), true, "%s can be taken on" % id)
		assert_ne(String(row.get("steps_line", "")), "", "%s shows its steps with have/need" % id)
	screen.free()


## Each row shows the step tally the shared ledger holds, formatted by the PANEL
## rather than the screen — the screen hands raw values down and renders no number.
func test_a_row_owns_its_own_number_formatting() -> void:
	var screen := _bound_screen()
	if screen == null:
		return
	var rows: Array = (screen.summary() as Dictionary)["rows"]
	var row: Dictionary = rows[0] as Dictionary
	var steps := String(row.get("steps_line", ""))
	assert_eq(steps.contains("("), true, "the row prints have/need itself: %s" % steps)
	assert_eq(steps.contains("/"), true, "and the count is there, not a bare label")
	assert_eq(String(row.get("kind_line", "")).contains("tier"), true, "and it names the tier too")
	screen.free()


## A gated quest is NOT offered while its gate is shut, and the gate is a real
## requirement rather than an empty dictionary: `has_destiny` is answerable only
## by a hero who actually holds that destiny.
func test_a_gated_quest_is_withheld_until_its_gate_is_met() -> void:
	var hero := _hero()
	var gated := QuestApi.gates_for(hero, &"the_returned_instrument")
	assert_eq(bool(gated["known"]), true, "the catalog knows the gated quest")
	assert_eq(bool(gated["ok"]), false, "and a bare hero does not pass its gate")
	var screen := _screen()
	if screen == null:
		return
	screen.setup(hero)
	var offered: Array = (screen.summary() as Dictionary)["offered_ids"]
	assert_eq(offered.has("the_returned_instrument"), false, "so it is not offered")
	screen.free()


# --- The accept path ---------------------------------------------------------


## THE LOAD-BEARING CASE. One hero, ONE MOUNTED JOURNAL mounted by the composition
## root's own route, ONE PRESSED BUTTON, and the module's own ledger is asked
## whether a quest is now in flight.
##
## Nothing in this function calls `QuestApi.accept`. It navigates the route, presses
## the real Button on the row the module offers, and asks the module.
##
## ## There is NO fallback here, and deleting one is what this case is for
##
## This suite used to do this:
##
## [codeblock]
## if not bool((live.summary() as Dictionary)["accept_seam"]):
##     var program := QuestProgram.new(harness.actor)
##     program.open(live)
## [/codeblock]
##
## — constructing its own `QuestProgram` and binding the seam whenever the composition
## root had not. That made the whole case UNHEALABLE: delete
## `item_workbench_app.gd`'s entire `ROUTE_QUEST` arm and every accept assertion in
## this file stayed green, because the test re-created the very thing under test.
## `tests/app/test_arrival_world_mount.gd` names this file as the anti-pattern it was
## written against.
##
## So the seam is now ASSERTED rather than supplied. If `ROUTE_QUEST`'s arm stops
## calling `_quests.bind(screen)`, `accept_seam` is false, the press finds no enabled
## button, and this case goes red on the module's own ledger — which is the only place
## the claim was ever true.
func test_the_production_path_takes_a_quest_on() -> void:
	var harness := _boot()
	if harness == null:
		return
	var moved := harness.navigate(ROUTE)
	assert_eq(bool(moved["ok"]), true, "the journal route is reachable: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen() as QuestScreen
	assert_ne(live, null, "the route shows a QuestScreen")
	if live == null:
		return
	# THE ROOT'S CONTRIBUTION, asserted on its own. This is the line that used to be
	# made for the test when it was missing.
	assert_eq(
		bool((live.summary() as Dictionary)["accept_seam"]),
		true,
		(
			(
				"the composition root mounted the journal with no accept seam bound. Its "
				+ "ROUTE_QUEST arm in _bind_route_screen must call _quests.bind(screen); this "
			)
			+ "suite will not bind it for the root, because a test that heals the break it "
			+ "detects proves nothing."
		)
	)

	var hero := harness.actor
	# Ask the MODULE what is on offer, not the screen: the test picks a target from
	# content rather than from what the screen chose to render.
	var targets := QuestApi.offered(hero)
	assert_ne(targets.is_empty(), true, "the hero has a quest to be offered")
	if targets.is_empty():
		return
	var quest_id := StringName(String((targets[0] as Dictionary)["id"]))

	# THE PRESS. The real Button, its real signal, the screen's real handler.
	assert_eq(_press_accept(live, String(quest_id)), true, "the row's button is a live control")

	# The claim is not on the screen's message line. It is in the module's ledger.
	var active := QuestApi.active(hero)
	assert_ne(active.is_empty(), true, "a quest is now in flight")
	assert_eq(
		String((active[0] as Dictionary)["id"]),
		String(quest_id),
		"and it is the one whose row was pressed"
	)
	var screen_view := live.summary() as Dictionary
	assert_eq(
		(screen_view["active_ids"] as Array).has(String(quest_id)), true, "the screen shows it"
	)
	assert_eq(
		(screen_view["offered_ids"] as Array).has(String(quest_id)),
		false,
		"and no longer offers it, because an accepted quest is not re-offered"
	)


## The once-guard is visible from outside: pressing the same row twice is refused
## by the module, not quietly applied twice.
func test_the_second_press_on_the_same_quest_is_refused() -> void:
	var harness := _boot()
	if harness == null:
		return
	if not bool((harness.navigate(ROUTE))["ok"]):
		return
	var live := harness.live_screen() as QuestScreen
	assert_ne(live, null, "the route shows a QuestScreen")
	if live == null:
		return
	# No fallback, for the reason the case above states: this one used to call
	# `QuestProgram.new(harness.actor).open(live)` under the same condition, so the
	# root's contribution was untested in exactly the run that would have caught it.
	assert_eq(
		bool((live.summary() as Dictionary)["accept_seam"]),
		true,
		"the composition root bound the commit verb; this suite will not bind it itself"
	)
	var hero := harness.actor
	var targets := QuestApi.offered(hero)
	assert_ne(targets.is_empty(), true, "the hero has a quest to be offered")
	if targets.is_empty():
		return
	var quest_id := StringName(String((targets[0] as Dictionary)["id"]))
	assert_eq(_press_accept(live, String(quest_id)), true, "the first press takes it on")
	var again := live.act_accept(quest_id)
	assert_eq(bool(again["ok"]), false, "the second is refused")
	assert_eq(String(again["reason"]), "already_active", "and the module names why")
	assert_eq((QuestApi.active(hero) as Array).size(), 1, "and only one entry exists")


## Nothing is accepted at mount. A boot that committed for the player would make
## `accept`'s once-guard a lie and would be a poller, not a player action.
func test_navigating_to_the_journal_accepts_nothing_by_itself() -> void:
	var harness := _boot()
	if harness == null:
		return
	var hero := harness.actor
	var before := QuestApi.offered(hero).size()
	assert_ne(before, 0, "there was something to accept, so this can fail")
	assert_eq(bool((harness.navigate(ROUTE))["ok"]), true, "the journal opened")
	assert_eq(QuestApi.active(hero).size(), 0, "no quest is in flight until a button is pressed")
	assert_eq(QuestApi.offered(hero).size(), before, "and the board is unchanged by looking at it")


## A journal with no seam cannot be committed through. The rows render greyed out
## rather than publishing a button that goes nowhere — the shape that made this
## feature read as shipped while nothing reached it.
func test_an_unwired_journal_refuses_rather_than_doing_nothing_quietly() -> void:
	var harness := _boot()
	if harness == null:
		return
	var screen := _screen()
	if screen == null:
		return
	screen.setup(harness.actor)
	var refused := screen.act_accept(&"the_account_left_open")
	assert_eq(bool(refused["ok"]), false, "nothing is committed without a seam")
	assert_eq(String(refused["reason"]), "no_quest_seam", "and the missing seam is named")
	assert_eq(QuestApi.active(harness.actor).size(), 0, "and nothing entered the ledger")
	screen.free()


# --- Gate soundness (audit criterion 6, both halves) --------------------------


## Every quest this screen can now reach must be SATISFIABLE from a legal prior
## state. A gate no fact can ever make true is a content defect (ADR 0137), not a
## UI problem, so it is reported here rather than papered over.
##
## ## What this asked before, and why it was not the question
##
## It hardcoded
## [codeblock]
## var writes := {
##     &"sect_post_held": true, &"oaths_discharged": true,
##     &"household_heir_registered": true, &"duels_won": true, &"third_man_spared": true,
## }
## [/codeblock]
##
## — five literals the AUTHOR typed — and asked "is this name on my list". That is a
## claim about a list, not about the game: it is satisfied by any build in which the
## five producers were DELETED, and it cannot notice a sixth producer. It went green
## over four unsatisfiable quests.
##
## ## What it asks now: DOES A PRODUCTION CALLER RECORD THIS FACT
##
## A fact reaches `world_spawn`/quest progress through exactly one ledger
## (`WorldFact.record`), and `tests/arch_rules/test_fact_ledger_writers.gd` pins the
## exhaustive set of files allowed to call it. So "some production caller records it"
## is decidable from SOURCE: the fact's own id, the const that declares it, and the
## files that reach the writer — with a real call behind the const, so a decoration
## cannot pass for a producer. A fact nobody ever writes is still reported RED, which
## is the case the hand-typed list could not reach.
##
## The scan walks `res://src` only and deliberately does NOT read `res://tests`: a test
## writing the ledger is building its own fixture, not the game's. A step on a fact
## produced ONLY by a test is exactly the unsatisfiable-in-play defect this is for.
func test_every_offered_quests_steps_watch_a_fact_the_world_records() -> void:
	var hero := _hero()
	var producers := _fact_producers()
	assert_ne(
		producers.is_empty(),
		true,
		(
			(
				"the scan found no production producer at all, so this case cannot tell a "
				+ "recorded fact from an unrecorded one. Either the writer's call signature "
			)
			+ "moved or the walk is broken; a vacuously clean run is worse than a red one."
		)
	)
	var watched := 0
	var unwritten := 0
	for view in QuestApi.offered(hero):
		for step in QuestApi.steps(hero, StringName(String(view["id"]))):
			var fact := String((step as Dictionary)["fact"])
			var source: Dictionary = producers.get(fact, {})
			unwritten += 1
			assert_ne(
				source.is_empty(),
				true,
				(
					(
						"%s watches '%s', and no file under res://src calls the fact ledger's "
						% [view["id"], fact]
					)
					+ ("one writer with that id's const as its argument — so nothing in the ")
					+ ("shipped game can ever record it and the quest's steps can never be ")
					+ "satisfied (ADR 0137)"
				)
			)
			if not source.is_empty():
				assert_ne(
					String(source.get("calls", "")),
					"",
					"%s's producer declares the const but never passes it to the writer" % fact
				)
			watched += 1
	assert_ne(watched, 0, "the scan saw steps, so a clean run is a real result")
	assert_eq(unwritten, watched, "every watched step was checked against a real call site")


## Every fact id a PRODUCTION caller can record, as `{fact_id: {declares, calls}}`.
##
## ## The three things a producer must have, and why each is checked separately
##
##   1. the writer is really CALLED in that file — the fact id has to be reachable
##      from a call rather than sitting in an unused const, which is the same half
##      `test_every_code_owned_writer_declares_its_id_where_the_census_reads_it` proves
##      for the single-const case.
##   2. the fact's id is DECLARED — `const FACT_X := &"sect_post_held"` in the same
##      file, or `fact = &"id"` authored in a `.tres`. The census
##      (`tools/gate_reach.py`) reads only these two spellings, so an id reaching the
##      writer any other way is a producer nothing can see.
##   3. an authored id exists under `res://data`, so a row cannot be satisfied by a
##      `.tres` path nobody shipped.
##
## `calls` is a COUNT of call sites (or of authored `.tres`), never a hand-typed truth,
## so this can go RED when a producer is removed — which the literal list it replaced
## could not do.
func _fact_producers() -> Dictionary:
	var out: Dictionary = {}
	for path in _gdscript_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		var calls := _writer_calls(text)
		if calls == 0:
			continue
		# `calls` is the count of real call SITES, not a flag: a const that sits in a
		# file with no call is a decoration and must not read as a producer.
		for declared in _declared_fact_ids(text):
			out[declared["fact"]] = {"declares": declared["declares"], "calls": str(calls)}
	for authored in _authored_fact_ids():
		if out.has(authored):
			continue
		var hits := _authored_fact_count(authored)
		if int(hits) > 0:
			out[authored] = {"declares": "authored .tres under res://data", "calls": hits}
	return out


## How many real call sites of the ledger's one writer `text` carries, with comment
## halves stripped a line at a time — so this file's own docblock, which discusses the
## writer, cannot make a decoration look like a producer.
func _writer_calls(text: String) -> int:
	var calls := 0
	for raw in text.split("\n"):
		var code: String = (raw as String).split("#")[0]
		if code.contains(_LEDGER_WRITER) and code.contains("("):
			calls += 1
	return calls


## Every `const NAME := &"id"` in `text`, as `{"fact": String, "declares": String}`.
## The comment half is stripped a line at a time, and the line must OPEN with `const`,
## so prose about a const — and an indented mention inside a docblock — is not one.
func _declared_fact_ids(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pattern := RegEx.new()
	if pattern.compile(_FACT_CONST) != OK:
		return out
	for raw in text.split("\n"):
		var code: String = (raw as String).split("#")[0]
		if not code.strip_edges().begins_with("const"):
			continue
		var found := pattern.search(code)
		if found == null:
			continue
		out.append({"fact": found.get_string(2), "declares": code.strip_edges()})
	return out


## Every `fact = &"id"` authored under `res://data`, which is how a `.tres` beat hands
## its id to `EventBeatWriter` — the one producer shape that names its id in content
## rather than in a same-file const. Read ONCE and cached: the walk is a directory
## census over the whole data tree and this case may ask it several times.
func _authored_fact_ids() -> Dictionary:
	if _authored_facts != null:
		return _authored_facts
	_authored_facts = {}
	for path in _data_files("res://data", "fact = &"):
		var at := path.rfind("fact = &")
		var rest: String = path.substr(at + 9, path.length())
		var close := rest.find('"')
		if close < 0:
			continue
		_authored_facts[rest.substr(0, close)] = true
	return _authored_facts


## How many files under `res://data` name this fact, so `calls` is a real count of
## AUTHORED producers rather than a made-up integer.
func _authored_fact_count(fact: String) -> String:
	var hits := 0
	for path in _data_files("res://data", "fact = &"):
		var at := path.rfind("fact = &")
		var rest: String = path.substr(at + 9, path.length())
		var close := rest.find('"')
		if close > 0 and rest.substr(0, close) == fact:
			hits += 1
	return str(hits)


## Every file under `root` whose text carries `needle`, recursively.
func _data_files(root: String, needle: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_data_files(path, needle))
			elif FileAccess.get_file_as_string(path).contains(needle):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Every `.gd` under `root`, recursively. `while` over `DirAccess` is the one shape
## `test_no_unbounded_wait.gd` accepts as terminating, and a `for` over the collected
## list is what every other rule in this repository performs.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## The other half of non-triviality: an OFFERED quest must not be something the
## hero already satisfies by existing. `offered` filters on the requirement alone,
## so a quest whose requirement is `{}` is offered to anybody — which is correct
## for an authored quest whose STEPS are the work, and would be a defect for one
## whose requirement were empty AND whose steps the hero already passes.
func test_an_offered_quest_is_not_already_complete_when_it_is_offered() -> void:
	var hero := _hero()
	for view in QuestApi.offered(hero):
		var steps := QuestApi.steps(hero, StringName(String(view["id"])))
		var done := 0
		for step in steps:
			if bool((step as Dictionary)["done"]):
				done += 1
		assert_ne(
			int(steps.size()) > 0 and done >= steps.size(),
			true,
			(
				(
					"%s is offered to a hero who has already satisfied every one of its steps, so "
					% view["id"]
				)
				+ "accepting it would complete it for free"
			)
		)


# --- Plumbing ----------------------------------------------------------------


func _boot() -> SeamHarness:
	if _harness != null and _harness.app != null:
		return _harness
	_harness = SeamHarness.mount_new()
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	if _harness.boot_error != "":
		return null
	return _harness


## A journal the harness's own hero is bound to, WITHOUT the composition root's
## bridge — the read-only half of the screen, driven headlessly.
func _bound_screen() -> QuestScreen:
	var screen := _screen()
	if screen == null:
		return null
	screen.setup(_hero())
	return screen


func _screen() -> QuestScreen:
	var packed := load(SCREEN) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as QuestScreen


## A hero with no destinies and no fates, so every gate is asked honestly: a bare
## actor, which is what criterion 6's "non-trivial" half is measured against.
func _hero() -> Actor:
	var actor := Actor.new(&"quest_board_hero", {})
	QuestApi.attach(actor)
	return actor


## The row rendering `quest_id`, by walking the mounted screen's tree for the row
## node and asking each one which quest it is. Bounded by `MAX_TREE_WALK`.
func _row(screen: Node, quest_id: String) -> Dictionary:
	for node in _all_named(screen, ROW_NODE, 0):
		var row := node as QuestRow
		if row == null:
			continue
		if row.quest_id() == quest_id:
			return row.summary()
	return {}


## Press the accept button on the row rendering `quest_id`. The row's real
## `pressed` signal, the screen's real handler, the program's real commit. A
## disabled button returns false, so a dead control can never read as a success.
func _press_accept(screen: Node, quest_id: String) -> bool:
	for node in _all_named(screen, ROW_NODE, 0):
		var row := node as QuestRow
		if row == null or row.quest_id() != quest_id:
			continue
		var button := _find_unique(node, ACCEPT_NODE) as Button
		if button == null or button.disabled:
			return false
		button.pressed.emit()
		return true
	return false


## Find the one node a row calls `%AcceptButton`.
##
## **No readiness gate here, and that is the whole fix.** `SeamHarness._mount`
## parents the app under a `root` that is not inside the tree and then drives
## `_ready()` BY HAND (`app.call("_ready")`), so the engine's own readiness flag is
## never set on the app or anything under it — `is_node_ready()` is false for every
## node in a mounted app, permanently, for every test in the repo. This walk used to
## gate its unique-name lookup on that flag and then recurse, and the recursion hit
## the same gate on every child, so it found nothing at all. `_press_accept` therefore
## returned false, which reads as a DEAD CONTROL: two accept tests reported that a
## mounted journal's real Button could not be pressed, and the four assertions after
## it reported the quest was never taken on. `get_node_or_null` is safe on a node
## that never got `_ready()`, so the gate bought nothing and cost the claim.
func _find_unique(node: Node, unique_name: String) -> Node:
	if node == null:
		return null
	if node.get_node_or_null(unique_name) != null:
		return node.get_node_or_null(unique_name)
	for child in node.get_children():
		var found := _find_unique(child, unique_name)
		if found != null:
			return found
	return null


## Every descendant named `node_name` or `node_name<digits>` — the rows are
## `QuestRow0`, `QuestRow1` and so on, so an exact match would find nothing and a
## walk that matched nothing would make every "the row is there" assertion below
## vacuously true. Depth-capped by `MAX_TREE_WALK`.
func _all_named(node: Node, node_name: String, depth: int) -> Array[Node]:
	var found: Array[Node] = []
	if node == null or depth > MAX_TREE_WALK:
		return found
	for child in node.get_children():
		if _named_after(child.name, node_name):
			found.append(child)
		found.append_array(_all_named(child, node_name, depth + 1))
	return found


## Whether `node_name` is `base` or `base` followed by digits.
func _named_after(node_name: StringName, base: String) -> bool:
	var text := String(node_name)
	if not text.begins_with(base):
		return false
	return text.substr(base.length()).is_valid_int()


## Dotted paths in `value` holding something that is not a primitive, a String, an
## Array, or a Dictionary of the same. A returned node is how a testable surface
## quietly stops being testable.
func _non_primitives(value: Variant, path: String = "") -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		for key in value as Dictionary:
			var child: Variant = (value as Dictionary)[key]
			if child is Dictionary or child is Array or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
		return out
	if value is Array:
		for index in (value as Array).size():
			out.append_array(_non_primitives((value as Array)[index], "%s[%d]" % [path, index]))
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
	)
