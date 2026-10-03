extends TestCase

## The socket forge wired through the real composition root: the app attaches the
## socket subsystem, the forge is a route a player can open, and every screen intent
## runs against the socket program and repaints from the result. Proves the UI
## program and the gameplay program meet at exactly one place.
##
## Reached through `SeamHarness` and `navigate_to`, never through
## `ItemWorkbenchApp.mount_socket_screen()`. That method pushes a screen without
## binding the socket read model to it, so a caller using it gets a forge that shows
## nothing and refuses everything with `no_view`; the door is also public with no
## caller in `src/` (BL-0121). `test_screen_reachability.gd` reports both.

const FORGE_SCENE := "res://src/ui/screens/socket_forge.tscn"
## Enough content to exercise every socket transaction on first run.
const CONTENT: Array[StringName] = [
	&"socket_host_rare_blade",
	&"socket_rune_mortal_offense",
	&"socket_reagent_mortal_slot_offense",
	&"socket_reagent_mortal_imputation",
]


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## The mounted forge, opened by route. Null when the route or the app refuses.
func _forge(harness: SeamHarness) -> Control:
	var moved := harness.navigate(SeamHarness.route_for_scene(FORGE_SCENE))
	assert_eq(moved["ok"], true, "the forge route opens: %s" % moved["note"])
	return harness.live_screen() if bool(moved["ok"]) else null


## Acquire socket content through the two facades that own it, then repaint. `count`
## is how many of `CONTENT` to take, so a test can stock a host without the reagent
## that makes an action possible.
func _stock(harness: SeamHarness, seed: int, count: int = CONTENT.size()) -> void:
	for offset in count:
		var item_id: StringName = CONTENT[offset]
		var def := SocketApi.resolve_content(item_id)
		assert_ne(def, null, "%s resolves through the socket facade" % item_id)
		if def == null:
			continue
		assert_ne(
			ItemsApi.generate(harness.actor, def, seed + offset),
			null,
			"%s was acquired through ItemsApi.generate" % item_id
		)


func test_the_app_attaches_the_socket_subsystem_to_its_actor() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	assert_ne(actor.component(SocketApi.LEDGER_COMPONENT), null, "the socket ledger is attached")
	assert_eq(SocketApi.socket_state(actor)["version"], SocketLedger.VERSION, "and it is versioned")
	assert_ne(actor.get_module_data(&"socket_state"), {}, "its state is keyed for persistence")


func test_opening_the_forge_route_gives_the_mounted_screen_a_readable_view() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _forge(harness)
	assert_ne(screen, null, "the forge mounted and is live")
	if screen == null:
		return
	assert_eq(harness.live_screen(), screen, "it is the screen the stack is showing")
	assert_eq(screen.scene_file_path, FORGE_SCENE, "and it is the forge scene")
	var view := screen.summary() as Dictionary
	assert_eq(view.is_empty(), false, "the screen reads the socket program")
	assert_eq(String(view["actor_id"]), "player", "for the app's own actor")
	assert_ne(String(view["host_instance_id"]), "", "it names the host it is showing")


func test_a_screen_intent_runs_against_the_program_and_repaints() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _forge(harness)
	if screen == null:
		return
	_stock(harness, 6100)
	harness.app.call("refresh_socket_screen")

	# The host the screen is looking at is the one the program acts on.
	var target := String((screen.summary() as Dictionary)["host_instance_id"])
	assert_ne(target, "", "the screen names a host")
	assert_eq(harness.action(screen, &"create_slot"), true, "the player opened a socket")
	harness.app.call("refresh_socket_screen")
	assert_eq(
		SocketApi.socket_state(harness.actor)["parents"].has(target),
		true,
		"and the program recorded it"
	)
	assert_eq(harness.action(screen, &"impute_slot"), true, "the player imprinted it")
	harness.app.call("refresh_socket_screen")
	assert_eq(harness.action(screen, &"insert_socket"), true, "the player seated a socket item")
	harness.app.call("refresh_socket_screen")
	var view := screen.summary() as Dictionary
	assert_eq(int(view["slot_count"]), 1, "the screen shows the slot")
	assert_eq(bool(view["slot_occupied"]), true, "and that it is occupied")
	assert_eq(
		int(((view["slots"] as Dictionary)["0"] as Dictionary)["imputed_count"]) > 0,
		true,
		"with its own modifiers"
	)
	assert_eq(String(screen.summary()["tone"]), "ok", "the outcome is reported")


func test_a_refused_intent_is_reported_and_changes_nothing() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _forge(harness)
	if screen == null:
		return
	# Only a host and its socket item, no reagent: the action is unavailable, so the
	# control is dead and the reason is reported rather than the action attempted.
	_stock(harness, 6300, 1)
	harness.app.call("refresh_socket_screen")
	var actor := harness.actor
	var before := SocketApi.socket_state(actor)
	var view := screen.summary() as Dictionary
	assert_eq(
		bool((view["actions"] as Dictionary)["enabled"]["create_slot"]),
		false,
		"the forge marks Open socket unavailable"
	)
	assert_eq(
		String((view["reasons"] as Array)[0]),
		"missing_cost",
		"and names the gameplay reason it is unavailable"
	)
	assert_eq(harness.action(screen, &"create_slot"), false, "so the player cannot press it")
	assert_eq(SocketApi.socket_state(actor), before, "and nothing changed")

	# Asking the screen to act anyway must still be refused, with the reason shown:
	# an unavailable control must not be a silent one.
	assert_eq(bool(screen.call(&"act_create_slot")), false, "the screen refuses the intent")
	assert_eq(String(screen.summary()["message"]), "Rejected: missing_cost", "reason is shown")
	assert_eq(String(screen.summary()["tone"]), "error", "reported as a rejection")
	assert_eq(SocketApi.socket_state(actor), before, "and still nothing changed")


func test_the_screen_never_names_the_socket_module() -> void:
	var text := FileAccess.get_file_as_string(FORGE_SCENE)
	assert_eq(text.contains("SocketApi"), false, "the scene names no module type")
	var script := FileAccess.get_file_as_string("res://src/ui/screens/socket_forge.gd")
	assert_eq(script.contains("SocketApi"), false, "nor does the script")
	assert_eq(script.contains("ItemDef"), false, "nor any item type")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")
