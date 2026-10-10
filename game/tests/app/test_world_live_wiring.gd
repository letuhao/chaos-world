extends TestCase

## The two one-line wires the audit found missing, proved through the COMPOSITION
## ROOT and not through a stage this suite built.
##
## ## Why this file exists and cannot heal itself
##
## The previous finding was that a player had a body, in an authored place, with the
## event module told about it — and that the body was INERT:
##
##   - `WorldStage.set_interaction_handler` had **zero production callers**, so every
##     press answered `{"ok": false, "reason": "no_handler"}`.
##   - `WorldMapScreen.location_selected` was **emitted and never connected**, so the
##     arrival's random draw among four authored locations pinned the player to one of
##     them for the rest of the session and the events authored for the other three
##     (`spirit_peaks`, `transcendent_realm`, `immortal_court`) stayed filtered out of
##     `EventApi.available` in every real run.
##
## Both were reachable only from `app/`, and `tests/app/test_world_stage.gd` calls
## `WorldStage.on_location_selected` directly — so that suite was green over a game
## that could not travel. The anti-pattern is the one
## `tests/app/test_arrival_world_mount.gd` is written against: **a test must never
## install, connect or bind the thing it is asking whether production installed,
## connected or bound.** Every case below goes through `SeamHarness` → the real
## `ItemWorkbenchApp` scene → `_ready()` → the real screens.
##
## ## What makes each case go RED
##
## Delete `_install_interaction_handler()`'s body, or `ROUTE_WORLD_MAP`'s connect arm,
## or the whole `ROUTE_WORLD_MAP` arm, and the corresponding case below fails on the
## MODULE's own state — the stage's installed seam, `world_spawn`'s ledger,
## `EventApi.state`. None of them is a restatement of a line of source.

## The hero this suite commits. `CharacterCreationFlow`'s first candidate, so nothing
## here has to know a destiny id to reach a real arrival.
const FIRST_ORIGIN := &"the_one_who_stayed"
## Every authored location the arrival draw can land on. Read from the pool rather than
## typed, so an added `.tres` is included and a removed one does not break the scan.
const MAX_PLACES := 8

var _harness: SeamHarness = null
var _app: ItemWorkbenchApp = null


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp


func teardown() -> void:
	# `WorldStage`'s mounted stage and body are PROCESS-WIDE statics, and this suite
	# travels between places, so a mount left behind would publish a freed
	# `PlayerAdapter` to every suite after it.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- Gap 1: the interaction seam ----------------------------------------------


## The boot wire, on its own so a RED below names WHICH end broke: a press means
## something because the composition root installed the callable, and `app/` is the
## only layer that may.
func test_the_composition_root_installs_the_interaction_seam() -> void:
	assert_eq(
		WorldStage.has_interaction_handler(),
		true,
		(
			"no handler is installed, so every press in the game answers no_handler. "
			+ "ItemWorkbenchApp must call WorldStage.set_interaction_handler during boot"
		)
	)


## A press with nothing mounted is still refused BY NAME, not by crashing: the handler
## reads the stage's actor and the seam is what turns a bare name into a decision.
##
## And the refusal is FILED: `interact`'s own contract is "every exit is recorded,
## including the refusals", because a press whose answer nobody can read is the inert
## body the audit found. This case used to assert the opposite (`last_interaction()`
## empty after a refusal), which contradicted the two assertions above it — a refusal
## was returned AND nothing was allegedly filed.
func test_a_press_on_an_unmounted_stage_names_its_refusal() -> void:
	var stage := WorldStage.new()
	var answer := stage.interact("quest_board")
	assert_eq(bool(answer["ok"]), false, "there is no body to press with")
	assert_eq(String(answer["reason"]), "no_actor", "and the refusal is named")
	assert_eq(
		stage.last_interaction(),
		{"ok": false, "reason": "no_actor", "target": "quest_board", "location_id": ""},
		"and the refusal is the row that was filed, place stamped from the stage's ledger"
	)


## THE PRESS. Committed arrival → the stage's own `interact`, which is what
## `PlayerAdapter.interacted` calls → the handler the root installed.
##
## Asserted on the ANSWER, never on the seam's presence: `no_handler` is a refusal
## with a real shape, so asserting only that a handler exists would go green over a
## handler that refuses everything.
func test_a_press_in_the_world_answers_something_other_than_no_handler() -> void:
	if not _commit():
		return
	var stage := WorldStage.instance()
	assert_ne(stage, null, "the arrival mounted a stage")
	if stage == null:
		return
	var answer := stage.interact("quest_board")
	assert_ne(
		String(answer.get("reason", "")),
		"no_handler",
		(
			("the press still answers no_handler, so the body is inert: %s. The root's " % answer)
			+ "_install_interaction_handler() must be called during _ready."
		)
	)
	assert_ne(
		String(answer.get("reason", "")),
		"not_a_quest_board",
		(
			("the root's handler does not recognise the press target 'quest_board', which ")
			+ "is an authored inhabited type. _QUEST_BOARD_ALIASES is where a press's "
			+ "vocabulary is declared."
		)
	)
	assert_ne(
		String(answer.get("location_id", "")),
		"",
		"and the answer says WHERE the press happened, which the handler alone cannot know"
	)


## The press must not have committed anything. ADR 0113's owner-of-the-moment: a press
## may change what a player is OFFERED and may not take a commitment on their behalf,
## so `QuestApi.active` stays empty and the journal remains the only place `accept` is
## reachable. This is the assertion that keeps "wiring a handler" from quietly becoming
## "auto-accepting quests".
func test_a_press_accepts_nothing() -> void:
	if not _commit():
		return
	var stage := WorldStage.instance()
	if stage == null:
		return
	stage.interact("quest_board")
	var offered := QuestApi.offered(_app.actor())
	var targets: Array[String] = []
	for view in offered:
		targets.append(String(view.get("id", "")))
	for quest_id in targets:
		stage.interact(quest_id)
	assert_eq(
		QuestApi.active(_app.actor()).size(),
		0,
		"no press took a quest on; only the player's own button in the journal may"
	)


## Every exit is filed, refusals included — that log is what makes a press observable
## at all, and its absence is the inert body the audit found. Two presses, two rows:
## the count is also the cheapest way to see an unguarded connection firing twice.
func test_every_routed_press_is_recorded_and_one_press_is_one_row() -> void:
	if not _commit():
		return
	var stage := WorldStage.instance()
	if stage == null:
		return
	stage.interact("quest_board")
	stage.interact("herb_common")
	var rows := stage.interactions()
	assert_eq(rows.size(), 2, "two presses, two filed answers: %s" % [rows])
	assert_eq(
		String((rows[1] as Dictionary)["target"]),
		"herb_common",
		"and the second row is the second press, in order"
	)
	assert_eq(
		String((stage.last_interaction() as Dictionary)["target"]),
		"herb_common",
		"with the last answer on the read model"
	)
	assert_eq(
		String(stage.summary()["last_interaction_target"]),
		"herb_common",
		(
			"and published there too, so a screen can read a press without calling in — "
			+ "FLATTENED, per the summary's own contract: a nested row reads as null "
			+ "through ADR 0038's primitives-only rule, which is why the last press is "
			+ "four scalars rather than the accessor's dictionary"
		)
	)


## A log is bounded. An unbounded history on a composition-root object is a leak, and
## this walks to the ceiling rather than trusting the bound to exist.
##
## The ceiling is [WorldStageInteractionLog]'s since the log was extracted out of
## `WorldStage` (it is that class's `MAX_ROWS`); the stage publishes no copy of the
## number, so naming the stage's old constant is what kept this suite from loading.
func test_the_routed_press_log_is_bounded() -> void:
	if not _commit():
		return
	var stage := WorldStage.instance()
	if stage == null:
		return
	for _i in WorldStageInteractionLog.MAX_ROWS * 3:
		stage.interact("quest_board")
	assert_eq(
		stage.interactions().size(),
		WorldStageInteractionLog.MAX_ROWS,
		"the log stops growing at its declared ceiling"
	)


# --- Gap 2: travel ------------------------------------------------------------


## THE JOURNEY, pressed the way a player presses it: open the route the nav bar opens,
## find the node the SCREEN chose for a place this hero has never been, and press that
## node's real button.
##
## Asserted on `world_spawn`'s durable ledger — not on the stage, not on the screen —
## so what is being claimed is "the hero travelled", which is the only claim that makes
## the other three authored places reachable.
func test_pressing_a_map_node_travels_the_hero() -> void:
	if not _commit():
		return
	var moved := _harness.navigate(ItemWorkbenchApp.ROUTE_WORLD_MAP)
	assert_eq(bool(moved["ok"]), true, "the world map is a route: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var screen := _harness.live_screen()
	assert_ne(screen, null, "the route shows a screen")
	if screen == null:
		return
	var before := String(WorldSpawnApi.current(_app.actor()).get("location_id", ""))
	assert_ne(before, "", "the hero arrived somewhere before travelling")
	var elsewhere := _a_place_the_hero_is_not(before)
	# `assert_ne(is_empty(), false)` PASSES when the catalog is empty and fails when a
	# place exists — the comparison was inverted, so the case was red exactly when the
	# world had somewhere to travel to. Four places are authored under
	# `game/data/world/locations/`, so the honest assertion is the other one.
	assert_eq(
		elsewhere.is_empty(), false, "an authored place this hero is not already standing in exists"
	)
	if elsewhere.is_empty():
		return
	var pressed := _press_node_for(screen, String(elsewhere["display_name"]))
	assert_eq(pressed, true, "the map has a pressable node for '%s'" % elsewhere["display_name"])
	if not pressed:
		return
	var after := String(WorldSpawnApi.current(_app.actor()).get("location_id", ""))
	assert_eq(
		after,
		String(elsewhere["location_id"]),
		(
			(
				"the hero is still at '%s' after the map announced '%s'. WorldMapScreen's "
				% [after, elsewhere["location_id"]]
			)
			+ ("location_selected is emitted and nothing connects it: ItemWorkbenchApp's ")
			+ "ROUTE_WORLD_MAP arm must connect it to WorldStage.on_location_selected."
		)
	)


## The journey's HALF is telling the EVENT module. `mount` republishes through the
## seam the root installed at boot, so the four authored events that were filtered out
## of every run become reachable the moment the player walks to their place — which is
## the whole point of the wire, and the only part a stage built by a test could fake.
func test_travelling_tells_the_event_module_where_the_player_is() -> void:
	if not _commit():
		return
	var moved := _harness.navigate(ItemWorkbenchApp.ROUTE_WORLD_MAP)
	if not bool(moved["ok"]):
		return
	var screen := _harness.live_screen()
	if screen == null:
		return
	var elsewhere := _a_place_the_hero_is_not(
		String(WorldSpawnApi.current(_app.actor()).get("location_id", ""))
	)
	if elsewhere.is_empty():
		return
	if not _press_node_for(screen, String(elsewhere["display_name"])):
		return
	var told := String(EventApi.state(_app.actor()).get("location_id", ""))
	assert_eq(
		told,
		String(elsewhere["location_id"]),
		(
			(
				"the event ledger still reads '%s' while the hero stands in '%s', so every "
				% [told, elsewhere["location_id"]]
			)
			+ "event authored for the new place is filtered out before its trigger is read"
		)
	)


## A journey is a mount, so the SAME body re-stands there rather than a second one
## appearing: a new adapter per travel would leave two players in one session.
func test_the_body_is_remounted_rather_than_telecopied() -> void:
	if not _commit():
		return
	var body := WorldStage.player()
	assert_ne(body, null, "the arrival mounted a body")
	if body == null:
		return
	var moved := _harness.navigate(ItemWorkbenchApp.ROUTE_WORLD_MAP)
	if not bool(moved["ok"]):
		return
	var screen := _harness.live_screen()
	if screen == null:
		return
	var elsewhere := _a_place_the_hero_is_not(
		String(WorldSpawnApi.current(_app.actor()).get("location_id", ""))
	)
	if elsewhere.is_empty() or not _press_node_for(screen, String(elsewhere["display_name"])):
		return
	assert_eq(WorldStage.player(), body, "the SAME body travelled; a new adapter is a 2nd player")
	assert_eq(
		String(WorldStage.instance().summary().get("location_id", "")),
		String(elsewhere["location_id"]),
		"and the stage the root owns reports where it now stands"
	)


## The control: with nothing mounted there is no body to travel, and the stage says so
## BY NAME. Before the wire a click did nothing at all and said nothing; a refusal is
## the honest version of that, and this keeps the refusal from being mistaken for a
## working journey.
func test_a_journey_with_nothing_mounted_is_refused_by_name() -> void:
	var moved := _harness.navigate(ItemWorkbenchApp.ROUTE_WORLD_MAP)
	assert_eq(bool(moved["ok"]), true, "the map opens even with no hero committed")
	if not bool(moved["ok"]):
		return
	var answer := WorldStage.on_location_selected(_harness.live_screen(), &"mortal_plains")
	assert_eq(bool(answer["ok"]), false, "there is nothing to travel with")
	assert_eq(String(answer["reason"]), "no_mounted_stage", "and the refusal is named")


# --- The layer rule this had to keep ------------------------------------------


## `ui/` may not name `app/`, so the screen keeps its signal and `app/` decides what it
## means. Read over CODE rather than the file as written: the docblock above
## `_on_node_pressed` names the very call this forbids, in order to say it is never
## made, and searching raw text would fail on the prose stating the rule.
func test_the_map_screen_reaches_no_stage_and_the_root_never_names_the_screen() -> void:
	assert_eq(
		_code(FileAccess.get_file_as_string("res://src/ui/screens/world_map_screen.gd")).contains(
			"WorldStage"
		),
		false,
		"the screen names no app/ stage, or the layering the gate enforces is inverted"
	)
	var root := _code(FileAccess.get_file_as_string("res://src/app/item_workbench_app.gd"))
	assert_eq(
		root.contains("WorldMapScreen"),
		false,
		(
			(
				"the root names the screen class rather than its signal, so a renamed screen "
				+ "would break the wire. It must connect location_selected through "
			)
			+ "has_signal/is_connected and hand the Control to WorldStage.on_location_selected."
		)
	)


# --- Internals ----------------------------------------------------------------


## Commit through the mounted arrival screen. Never a program this suite constructed:
## that is the self-healing mistake this file is written against.
func _commit() -> bool:
	var live := _harness.live_screen()
	if live == null:
		return false
	var outcome := live.call("act_commit", FIRST_ORIGIN) as Dictionary
	assert_eq(
		bool(outcome.get("ok", false)),
		true,
		"the arrival committed: %s" % outcome.get("reason", "")
	)
	return bool(outcome.get("ok", false))


## One authored place the hero is not already standing in, or `&""` when the shipped
## pool holds only the one. Read from `WorldSpawnApi`'s own catalog through a probe
## actor, so the case cannot pass by naming a place the content does not ship. Returns
## `{location_id, display_name}` because the map names its node buttons for the place's
## DISPLAY name, and matching on that is what proves the button belongs to this place.
func _a_place_the_hero_is_not(here: String) -> Dictionary:
	var probe := Actor.new(&"journey_probe", {})
	WorldSpawnApi.attach(probe)
	for row in WorldSpawnApi.catalog(probe):
		var id := String(row.get("location_id", ""))
		if not id.is_empty() and id != here:
			return {"location_id": id, "display_name": String(row.get("display_name", ""))}
	return {}


## Press the node button the map built for `location_id`: the real Button, its real
## `pressed` signal, the screen's real handler and then the root's real connection.
##
## The button is found by walking the graph rather than by asking the screen, because a
## screen that publishes no control would then make the case vacuous. The `pressed`
## array carries the watch because a GDScript lambda captures by VALUE — a bare local
## `bool` would be copied into the closure and read back as `false` forever.
##
## `display_name` is the locale KEY the catalog publishes (the catalog's rows carry
## `LOC_WORLD_*`), and the node's TEXT is the resolved label — `WorldMapScreen` sets
## `button.name = display_name` and `button.text = L.t(display_name)`. So the comparison
## resolves too, exactly as `test_world_map_screen.gd` documents for the same pair.
func _press_node_for(screen: Node, display_name: String) -> bool:
	var watched := [false]
	var watch := func(_watched_id: StringName) -> void: watched[0] = true
	if screen.is_connected(&"location_selected", watch):
		screen.disconnect(&"location_selected", watch)
	screen.connect(&"location_selected", watch)
	for button in _node_buttons(screen, 0):
		if String(button.name) != display_name and String(button.text) != L.t(display_name):
			continue
		button.pressed.emit()
		return bool(watched[0])
	return false


## Every Button the map built for a node, depth-capped so a malformed tree cannot make
## this case run away. The node buttons are named for their DISPLAY name, and a screen
## that drew none makes every journey case below vacuously true rather than green.
func _node_buttons(node: Node, depth: int) -> Array[Button]:
	var found: Array[Button] = []
	if node == null or depth > 12:
		return found
	for child in node.get_children():
		if child is Button:
			found.append(child as Button)
		found.append_array(_node_buttons(child, depth + 1))
	return found


## Source with every comment half stripped, so prose stating a rule cannot fail it.
func _code(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		kept.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(kept)
