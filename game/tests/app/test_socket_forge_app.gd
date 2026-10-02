extends TestCase

## The socket forge wired through the real composition root: the app attaches the
## socket subsystem, mounts the screen on a `ScreenStack`, and every screen intent
## runs against the socket program and repaints from the result. Proves the UI
## program and the gameplay program meet at exactly one place.

const APP_SCENE := "res://scenes/item_workbench/ItemWorkbenchApp.tscn"


func _boot() -> Dictionary:
	var scene: PackedScene = load(APP_SCENE)
	assert_ne(scene, null, "app scene loads")
	var app := scene.instantiate() as Control
	app.call("_ready")
	return {"app": app, "actor": app.get("_actor") as Actor}


func test_the_app_attaches_the_socket_subsystem_to_its_actor() -> void:
	var booted := _boot()
	var actor: Actor = booted["actor"]
	assert_ne(actor, null, "the app built an actor")
	assert_ne(actor.component(SocketApi.LEDGER_COMPONENT), null, "the socket ledger is attached")
	assert_eq(SocketApi.socket_state(actor)["version"], SocketLedger.VERSION, "and it is versioned")


func test_mounting_the_forge_gives_the_screen_a_readable_view() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	var stack := ScreenStack.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	var screen: Control = app.call("mount_socket_screen", stack)
	assert_ne(screen, null, "the forge mounted")
	assert_eq(stack.depth(), 1, "on the stack")
	assert_eq(String(stack.current().name), "SocketForgeScreen", "as the live screen")
	var view: Dictionary = screen.call("summary")
	assert_eq(bool(view.is_empty()), false, "the screen reads the socket program")
	assert_eq(String(view["actor_id"]), "player", "for the app's own actor")


func test_a_screen_intent_runs_against_the_program_and_repaints() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	var actor: Actor = booted["actor"]
	var stack := ScreenStack.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	var screen: Control = app.call("mount_socket_screen", stack)

	# Give the actor something to socket and something to socket with, through the
	# normal content path, then take the whole loop from the screen.
	var host := ItemsApi.generate(actor, SocketApi.resolve_content(&"socket_host_rare_blade"), 61)
	assert_ne(host, null, "a socket host is owned")
	var gem := ItemsApi.generate(
		actor, SocketApi.resolve_content(&"socket_rune_mortal_offense"), 62
	)
	ItemsApi.inventory(actor).add(
		SocketApi.resolve_content(&"socket_reagent_mortal_slot_offense"), 2
	)
	ItemsApi.inventory(actor).add(SocketApi.resolve_content(&"socket_reagent_mortal_imputation"), 2)
	app.call("refresh_socket_screen")

	# The host the screen is looking at is the one the program acts on.
	var target := String((screen.call("summary") as Dictionary)["host_instance_id"])
	assert_ne(target, "", "the screen names a host")
	assert_eq(bool(screen.call("act_create_slot")), true, "the screen opened a socket")
	assert_eq(
		SocketApi.socket_state(actor)["parents"].has(target), true, "and the program recorded it"
	)
	assert_eq(bool(screen.call("act_impute_slot")), true, "the screen imprinted it")
	assert_eq(bool(screen.call("act_insert_socket")), true, "the screen seated a socket item")
	var view: Dictionary = screen.call("summary")
	assert_eq(int(view["slot_count"]), 1, "the screen shows the slot")
	assert_eq(bool(view["slot_occupied"]), true, "and that it is occupied")
	assert_eq(int((view["slots"]["0"] as Dictionary)["imputed_count"]), 2, "with its own modifiers")
	assert_ne(gem, null, "the socket item came from the content path")
	assert_eq(String(screen.summary()["tone"]), "ok", "the outcome is reported")


func test_a_refused_intent_is_reported_and_changes_nothing() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	var actor: Actor = booted["actor"]
	var stack := ScreenStack.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	var screen: Control = app.call("mount_socket_screen", stack)
	ItemsApi.generate(actor, SocketApi.resolve_content(&"socket_host_rare_blade"), 63)
	app.call("refresh_socket_screen")
	var before := SocketApi.socket_state(actor)
	# No reagent is carried, so the intent is refused before it reaches the program.
	assert_eq(bool(screen.call("act_create_slot")), false, "the screen refused")
	var view: Dictionary = screen.call("summary")
	assert_eq(String(view["message"]), "Rejected: missing_cost", "the gameplay reason is shown")
	assert_eq(String(view["tone"]), "error", "reported as a rejection")
	assert_eq(SocketApi.socket_state(actor), before, "and nothing changed")
