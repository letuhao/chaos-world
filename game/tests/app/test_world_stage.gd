extends TestCase

## Tests for `WorldStage`: the mount, the bounds clamp, the interact bridge.
##
## The load-bearing test here is `test_mount_clamps_the_body_into_the_bounds`.
## `PlayerAdapter.set_map_bounds` writes `Camera2D.limit_*` and nothing else, so
## before this file existed a player mounted on a 512x512 map stood at whatever
## the authored spawn said and could then walk to any coordinate in the world.

const BOUNDS := Rect2(0, 0, 512, 512)
const HANDLED := {&"answered": true}

var _stage: WorldStage = null
var _adapter: PlayerAdapter = null
var _calls: Array[Dictionary] = []
var _handler_answer: Dictionary = {}
var _key_presses: int = 0


func setup() -> void:
	_calls = []
	_key_presses = 0
	_handler_answer = HANDLED.duplicate(true)
	_stage = WorldStage.new()
	WorldStage.set_interaction_handler(_note_interaction)


func teardown() -> void:
	# Freed here, not queued. `queue_free()` defers to the end of the frame and
	# the headless runner never processes a frame, so a deferred node stays
	# parented to `root` and outlives the test that made it — which is how a suite
	# accumulates a body per test until the process dies.
	if _adapter != null:
		if _adapter.get_parent() != null:
			_adapter.get_parent().remove_child(_adapter)
		_adapter.free()
		_adapter = null
	_stage = null
	WorldStage.set_interaction_handler(Callable())
	# The mounted stage and body are process-wide statics, so a test that mounted
	# one and did not leave it would publish a freed `PlayerAdapter` to every suite
	# that runs after this one.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()


## Counts handler invocations. `interact()` has its own range gate — a body far
## from the target emits nothing at all — so a bridge test that asserted only on
## emitted signals would pass for the wrong reason.
##
## Named `_note_interaction`, not `_record`: `TestCase` already declares
## `_record(String, Variant, Variant)` and a same-named override with an
## incompatible signature is a parse error, not a shadow.
func _note_interaction(actor: Actor, location_id: StringName, target_name: String) -> Dictionary:
	_key_presses += 1
	_calls.append(
		{"actor_id": String(actor.id), "location_id": String(location_id), "target": target_name}
	)
	return _handler_answer.duplicate(true)


## Reach the nearest interactable through the adapter's own keyboard path, the
## way a player does. `_unhandled_input` needs an event carrying the action, and
## `InputEventAction` reports itself pressed with no `Input` singleton call — so
## no assertion can accidentally be reading the test's own key presses.
func _press_interact(adapter: PlayerAdapter) -> void:
	adapter._unhandled_input(_interact_event())


func _interact_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	return event


## A player standing on a map, attached to the tree so `global_position` is
## meaningful. The bounds are deliberately NOT the adapter's 1024x1024 default,
## so every assertion below is about the rect the stage was given.
func _mounted(bounds: Rect2 = BOUNDS) -> PlayerAdapter:
	var actor := Actor.new(&"player")
	WorldSpawnApi.attach(actor)
	_adapter = PlayerAdapter.new(actor)
	(Engine.get_main_loop() as SceneTree).root.add_child(_adapter)
	var answer := _stage.mount(_adapter, &"mortal_plains", bounds)
	assert_eq(answer["ok"], true, "mount succeeded: %s" % answer.get("reason", ""))
	return _adapter


# --- the bounds bug ----------------------------------------------------------


func test_mount_clamps_the_body_into_the_bounds() -> void:
	var adapter := _mounted()
	assert_eq(adapter.global_position.x >= BOUNDS.position.x, true, "body is inside the left edge")
	assert_eq(adapter.global_position.y >= BOUNDS.position.y, true, "body is inside the top edge")
	assert_eq(adapter.global_position.x <= BOUNDS.end.x, true, "body is inside the right edge")
	assert_eq(adapter.global_position.y <= BOUNDS.end.y, true, "body is inside the bottom edge")


func test_mount_clamps_an_authored_spawn_outside_the_bounds() -> void:
	# A scene may author its SpawnPoint past the edge of its own map. The rect is
	# the world; the marker does not get to veto it.
	var adapter := PlayerAdapter.new(Actor.new(&"player"))
	(Engine.get_main_loop() as SceneTree).root.add_child(adapter)
	_adapter = adapter
	var entry := WorldEntry.new()
	entry.name = "MortalPlains"
	var marker := Marker2D.new()
	marker.name = "SpawnPoint"
	marker.position = Vector2(9000, -400)
	entry.add_child(marker)
	(Engine.get_main_loop() as SceneTree).root.add_child(entry)
	adapter.reparent(entry)
	var answer := _stage.mount(adapter, &"mortal_plains", BOUNDS)
	assert_eq(answer["ok"], true, "mount succeeded")
	assert_eq(
		adapter.global_position, Vector2(512, 0), "clamped to the far edge, not to the marker"
	)
	entry.get_parent().remove_child(entry)
	entry.free()


func test_interaction_pulls_a_drifted_body_back_inside() -> void:
	# `move_and_slide` runs against an empty physics space, so a test cannot walk
	# the body off the map the way a running SceneTree does. Writing the position
	# directly is that walk: the adapter has no answer for it, and the stage does.
	var adapter := _mounted()
	adapter.global_position = Vector2(-5000, 8000)
	var answer := _stage.interact("herb_common")
	assert_eq(answer["ok"], true, "the bridge answered")
	assert_eq(adapter.global_position.x, BOUNDS.position.x, "x pulled back to the left edge")
	assert_eq(adapter.global_position.y, BOUNDS.end.y, "y pulled back to the bottom edge")


func test_mount_records_the_bounds_on_the_adapter() -> void:
	var adapter := _mounted()
	var bounds: Array = adapter.summary()["map_bounds"]
	assert_eq(bounds[2], BOUNDS.size.x, "camera limits follow the stage's rect")
	assert_eq(bounds[3], BOUNDS.size.y, "camera limits follow the stage's rect")


func test_a_zero_sized_rect_falls_back_to_the_default_bounds() -> void:
	var adapter := _mounted(Rect2(0, 0, 0, 0))
	var bounds: Array = _stage.summary()["bounds"]
	assert_eq(bounds[2], WorldStage.DEFAULT_BOUNDS.size.x, "an empty rect is not a playfield")
	assert_eq(bounds[3], WorldStage.DEFAULT_BOUNDS.size.y, "on either axis")


# --- mount -------------------------------------------------------------------


func test_mount_refuses_a_null_player() -> void:
	var answer := _stage.mount(null, &"mortal_plains", BOUNDS)
	assert_eq(answer["ok"], false, "no player refused")
	assert_eq(answer["reason"], "no_player", "refusal is named")


func test_mount_refuses_an_unknown_location() -> void:
	_adapter = PlayerAdapter.new(Actor.new(&"player"))
	(Engine.get_main_loop() as SceneTree).root.add_child(_adapter)
	var answer := _stage.mount(_adapter, &"atlantis", BOUNDS)
	assert_eq(answer["ok"], false, "a location nothing authors is refused")
	assert_eq(answer["reason"], "unknown_location", "refusal is named")
	assert_eq(_stage.summary()["mounted"], false, "nothing was mounted")


func test_mount_refuses_a_player_with_no_actor() -> void:
	_adapter = PlayerAdapter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_adapter)
	var answer := _stage.mount(_adapter, &"mortal_plains", BOUNDS)
	assert_eq(answer["ok"], false, "a body wrapping nothing has no ledger to move")
	assert_eq(answer["reason"], "no_actor", "refusal is named")


func test_mount_places_the_player_and_names_the_place() -> void:
	var answer := _mounted()
	assert_eq(String(answer["location_id"]), "mortal_plains", "mounted the named place")
	assert_eq(String(answer["location_name"]), "Mortal Plains", "with its authored name")
	assert_eq(_stage.summary()["mounted"], true, "the stage reports a body")


func test_mount_writes_the_durable_location() -> void:
	var adapter := _mounted()
	assert_eq(
		WorldSpawnApi.current(adapter.actor())["location_id"], "mortal_plains", "ledger moved"
	)


func test_the_stage_keeps_no_save_payload_of_its_own() -> void:
	# The durable location is `world_spawn`'s ledger and the whole of it. A second
	# writer over a `module_data` key is ADR 0113's failure mode, and it is also
	# what `tools/arch`'s app-state rule would read as a stateful system in the
	# composition root — so the stage writes none.
	var adapter := _mounted()
	var stage: Dictionary = adapter.actor().get_module_data(WorldStage.STAGE_KEY)
	assert_eq(stage.is_empty(), true, "the stage persisted nothing of its own")
	assert_eq(
		WorldSpawnApi.current(adapter.actor())["location_id"],
		"mortal_plains",
		"the ledger is the one answer"
	)


func test_mount_twice_reconnects_the_bridge_exactly_once() -> void:
	# Connecting per mount would fire the handler once per travel. One press must
	# produce one call however many times the player has moved.
	var adapter := _mounted()
	_stage.mount(adapter, &"spirit_peaks", BOUNDS)
	_stage.mount(adapter, &"immortal_court", BOUNDS)
	adapter.global_position = Vector2(100, 100)
	var marker := Node2D.new()
	marker.name = "Herb"
	marker.global_position = Vector2(120, 100)
	adapter.add_interactable(marker)
	_press_interact(adapter)
	assert_eq(_calls.size(), 1, "three mounts, one press, one handler call")
	assert_eq(String(_calls[0]["location_id"]), "immortal_court", "routed to the latest place")
	adapter.remove_interactable(marker)
	marker.free()


func test_mount_rebuilds_the_rows_from_the_new_place() -> void:
	var adapter := _mounted()
	assert_eq(_stage.summary()["location_id"], "mortal_plains", "first place")
	_stage.mount(adapter, &"spirit_peaks", BOUNDS)
	var names: Array = []
	for row in _stage.interactables():
		names.append(String(row["name"]))
	assert_eq(names.has("spirit_stone"), true, "the new place's resources are reported")
	assert_eq(names.has("iron_ore"), false, "the old place's are gone")


# --- interactables -----------------------------------------------------------


func test_interactables_are_primitives_from_the_location_def() -> void:
	_mounted()
	var rows := _stage.interactables()
	assert_eq(rows.is_empty(), false, "the authored place has rows")
	for row in rows:
		assert_eq(row.has("name"), true, "a row names its target")
		assert_eq(row.has("kind"), true, "a row names where it came from")
		assert_eq(row.has("location_id"), true, "a row names its place")
		assert_eq(String(row["location_id"]), "mortal_plains", "every row is from this place")
		assert_eq(_is_primitive(row["name"]), true, "a row name is a string")


func test_interactables_include_resources_and_inhabitants() -> void:
	_mounted()
	var names: Array = []
	for row in _stage.interactables():
		names.append(String(row["name"]))
	assert_eq(names.has("iron_ore"), true, "an authored resource is in reach")
	assert_eq(names.has("herb_common"), true, "and the second one")
	assert_eq(names.has("beast"), true, "and an inhabitant type")


func test_interactables_report_a_registered_npc() -> void:
	_mounted()
	var npc := Actor.new(&"drifter")
	assert_eq(_stage.register_npc(npc)["ok"], true, "npc accepted")
	var kinds: Array = []
	for row in _stage.interactables():
		kinds.append(String(row["kind"]))
	assert_eq(kinds.has(WorldStage.SOURCE_NPC), true, "the npc is a row")
	assert_eq(_stage.summary()["npc_count"], 1, "and is counted")


func test_register_npc_refuses_a_duplicate() -> void:
	_mounted()
	var npc := Actor.new(&"drifter")
	_stage.register_npc(npc)
	var answer := _stage.register_npc(npc)
	assert_eq(answer["ok"], false, "the same npc is not listed twice")
	assert_eq(answer["reason"], "already_registered", "refusal is named")


func test_register_npc_refuses_null() -> void:
	_mounted()
	var answer := _stage.register_npc(null)
	assert_eq(answer["ok"], false, "no npc refused")
	assert_eq(answer["reason"], "no_npc", "refusal is named")


func test_interactables_are_empty_with_no_actor() -> void:
	assert_eq(WorldStage.new().interactables().size(), 0, "an unmounted stage has nothing in reach")


# --- the interact bridge -----------------------------------------------------


func test_interact_routes_through_the_injected_handler() -> void:
	var adapter := _mounted()
	adapter.global_position = Vector2(100, 100)
	var answer := _stage.interact("elder_qi")
	assert_eq(answer["ok"], true, "the handler answered")
	assert_eq(answer["answered"], true, "and its payload came back verbatim")
	assert_eq(_calls.size(), 1, "exactly one call")
	assert_eq(String(_calls[0]["target"]), "elder_qi", "the target name crossed the seam")
	assert_eq(String(_calls[0]["location_id"]), "mortal_plains", "so did the place")
	assert_eq(String(_calls[0]["actor_id"]), "player", "and the actor")


func test_the_adapter_signal_is_consumed_not_just_emitted() -> void:
	# The gap being closed: `interact()` emitted `interacted(name)` and nothing in
	# this repo consumed it. The stage is that consumer.
	var adapter := _mounted()
	adapter.global_position = Vector2(100, 100)
	var marker := Node2D.new()
	marker.name = "Elder"
	marker.global_position = Vector2(120, 100)
	adapter.add_interactable(marker)
	_press_interact(adapter)
	assert_eq(_calls.size(), 1, "a press reached the handler")
	assert_eq(String(_calls[0]["target"]), "Elder", "naming what was pressed")
	assert_eq(_key_presses, 1, "through exactly one bridge, not one per mount")
	adapter.remove_interactable(marker)
	marker.free()


func test_the_bridge_refuses_loudly_with_no_handler_installed() -> void:
	WorldStage.set_interaction_handler(Callable())
	var adapter := _mounted()
	var answer := _stage.interact("elder_qi")
	assert_eq(answer["ok"], false, "no handler, no invented outcome")
	assert_eq(answer["reason"], "no_handler", "and the reason is named")
	assert_eq(answer["target"], "elder_qi", "carrying the target for the caller")


func test_the_bridge_refuses_a_handler_that_answers_nothing() -> void:
	WorldStage.set_interaction_handler(func(_a, _l, _t): return null)
	var adapter := _mounted()
	var answer := _stage.interact("elder_qi")
	assert_eq(answer["ok"], false, "a null answer is not an ok")
	assert_eq(answer["reason"], "handler_returned_nothing", "refusal is named")


func test_interact_refuses_an_empty_target() -> void:
	_mounted()
	var answer := _stage.interact("")
	assert_eq(answer["ok"], false, "an empty name is not a target")
	assert_eq(answer["reason"], "no_target", "refusal is named")


func test_interact_refuses_before_anything_is_mounted() -> void:
	var answer := _stage.interact("elder_qi")
	assert_eq(answer["ok"], false, "nothing is mounted, so nothing answers")
	assert_eq(answer["reason"], "no_actor", "refusal is named")


func test_the_stage_does_not_import_quest_or_event() -> void:
	# The seam exists precisely because those modules may not be loaded.
	#
	# The search runs over CODE, never over the file as written: the stage's
	# docstrings NAME `EventApi` repeatedly, in order to document that `app/`
	# injects it and the stage itself never names it. Searching the raw text
	# fails on the very prose stating the rule — and it would also PASS a stage
	# that really did hard-wire the call, because a docstring alone satisfies a
	# substring search. ADR 0143 is the decision this guards: a bridge of
	# Callables, never a module import.
	var code := ""
	for raw in FileAccess.get_file_as_string("res://src/app/world_stage.gd").split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		code += line + "\n"
	assert_eq(code.contains("QuestApi"), false, "no quest edge from the composition root")
	assert_eq(code.contains("EventApi"), false, "no event edge from the composition root")


# --- enter / leave / summary -------------------------------------------------


func test_enter_reports_the_place_without_a_body() -> void:
	var actor := Actor.new(&"player")
	WorldSpawnApi.attach(actor)
	WorldSpawnApi.selected(actor, &"spirit_peaks")
	var answer := _stage.enter(actor)
	assert_eq(answer["ok"], true, "enter succeeded")
	assert_eq(String(answer["location_id"]), "spirit_peaks", "at the durable location")
	assert_eq(_stage.summary()["mounted"], false, "with no body mounted")
	assert_eq(_stage.summary()["has_actor"], true, "but the stage knows its actor")


func test_enter_refuses_an_actor_that_is_nowhere() -> void:
	var actor := Actor.new(&"player")
	WorldSpawnApi.attach(actor)
	var answer := _stage.enter(actor)
	assert_eq(answer["ok"], false, "nowhere in particular is not a place to enter")
	assert_eq(answer["reason"], "not_located", "refusal is named")


func test_enter_refuses_a_null_actor() -> void:
	var answer := _stage.enter(null)
	assert_eq(answer["ok"], false, "no actor refused")
	assert_eq(answer["reason"], "no_actor", "refusal is named")


func test_leave_clears_the_stage_and_keeps_the_ledger() -> void:
	var adapter := _mounted()
	var answer := _stage.leave()
	assert_eq(answer["ok"], true, "leave succeeded")
	assert_eq(String(answer["location_id"]), "mortal_plains", "and names where it stood")
	assert_eq(_stage.summary()["mounted"], false, "the body is gone")
	assert_eq(_stage.interactables().size(), 0, "and so is everything in reach")
	assert_eq(
		WorldSpawnApi.current(adapter.actor())["location_id"],
		"mortal_plains",
		"the durable location outlives the stage"
	)


func test_summary_is_primitives_only() -> void:
	_mounted()
	for key in _stage.summary().keys():
		assert_eq(
			_is_primitive(_stage.summary()[key]), true, "summary value is primitive: %s" % key
		)


func test_summary_on_an_empty_stage() -> void:
	var s := WorldStage.new().summary()
	assert_eq(s["mounted"], false, "nothing mounted")
	assert_eq(s["location_id"], "", "nowhere")
	assert_eq(s["interactable_count"], 0, "nothing in reach")
	assert_eq(s["handler_installed"], true, "the seam is process-wide, and it is installed")


func _is_primitive(value: Variant) -> bool:
	var kind := typeof(value)
	return (
		kind == TYPE_ARRAY
		or kind == TYPE_FLOAT
		or kind == TYPE_INT
		or kind == TYPE_STRING
		or kind == TYPE_BOOL
	)


# --- the signal-driven seam a screen consumes --------------------------------


func test_mount_publishes_the_stage_and_the_body() -> void:
	# `ui/` may not reference `app/`, so a screen answering its own
	# `location_selected` signal reaches the mount through these two.
	var adapter := _mounted()
	assert_eq(WorldStage.instance(), _stage, "the mounted stage is published")
	assert_eq(WorldStage.player(), adapter, "and the body it is holding")


func test_leave_unpublishes_them() -> void:
	_mounted()
	_stage.leave()
	assert_eq(WorldStage.instance(), null, "no stage, so no screen can travel")
	assert_eq(WorldStage.player(), null, "and no body")


func test_a_refused_mount_publishes_nothing() -> void:
	_adapter = PlayerAdapter.new(Actor.new(&"player"))
	(Engine.get_main_loop() as SceneTree).root.add_child(_adapter)
	_stage.mount(_adapter, &"atlantis", BOUNDS)
	assert_eq(WorldStage.instance(), null, "a refused mount installs no stage")


# --- the selection-to-mount connection ---------------------------------------


## A stand-in for `WorldMapScreen`, which `ui/` will not let this file reach. It
## has the two members the wiring actually touches — the `location_selected`
## signal and `set_message` — and nothing else.
class FakeScreen:
	extends Control

	signal location_selected(location_id: StringName)

	var reported: String = ""

	func set_message(message: String, _tone: StringName = &"") -> void:
		reported = message


func _screen() -> FakeScreen:
	var screen := FakeScreen.new()
	screen.name = "WorldMap"
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


func test_a_screen_selection_mounts_the_stage() -> void:
	var adapter := _mounted()
	var screen := _screen()
	var answer := WorldStage.on_location_selected(screen, &"transcendent_realm", BOUNDS)
	assert_eq(answer["ok"], true, "the selection mounted: %s" % answer.get("reason", ""))
	assert_eq(WorldStage.player(), adapter, "the same body travelled")
	assert_eq(
		WorldSpawnApi.current(adapter.actor())["location_id"],
		"transcendent_realm",
		"the ledger moved"
	)
	assert_eq(screen.reported, "Travelled to Transcendent Realm.", "and the screen was told")
	screen.get_parent().remove_child(screen)
	screen.free()


func test_a_screen_selection_refuses_with_nothing_mounted() -> void:
	# This is the whole point of the refusal: before, selecting a node did
	# nothing at all and said nothing. Now it says what it could not do.
	var screen := _screen()
	var answer := WorldStage.on_location_selected(screen, &"mortal_plains", BOUNDS)
	assert_eq(answer["ok"], false, "nothing to travel with")
	assert_eq(answer["reason"], "no_mounted_stage", "refusal is named")
	screen.get_parent().remove_child(screen)
	screen.free()


func test_a_screen_selection_survives_a_null_screen() -> void:
	_mounted()
	var answer := WorldStage.on_location_selected(null, &"spirit_peaks", BOUNDS)
	assert_eq(answer["ok"], true, "a caller with no screen still mounts")
	assert_eq(_stage.summary()["location_id"], "spirit_peaks", "at the named place")


func test_the_screen_seam_does_not_name_the_map_screen() -> void:
	# The screen keeps its signal; `app/` decides what it means. Reaching for
	# the map screen from here would invert the layer the gate enforces.
	#
	# The search runs over CODE, not the file as written: the docstring above
	# `on_location_selected` NAMES the very call this forbids, in order to say it
	# is never made. Searching the raw text would fail on the prose stating the
	# rule, which is the opposite of what the assertion is for.
	var code := ""
	for raw in FileAccess.get_file_as_string("res://src/app/world_stage.gd").split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		code += line + "\n"
	assert_eq(code.contains("WorldMapScreen.location_selected"), false, "no hard screen binding")
	assert_eq(code.contains("extends "), true, "the stage is its own file, not a screen subclass")
