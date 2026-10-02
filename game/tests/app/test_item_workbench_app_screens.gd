extends TestCase

## The playable scene mounts every item surface behind one screen stack, so the
## socket forge and the loot encounter are reachable by running the app rather
## than only in a headless test (Wave 5 integration).

const APP_SCENE := "res://scenes/item_workbench/ItemWorkbenchApp.tscn"


func _boot() -> Dictionary:
	var scene: PackedScene = load(APP_SCENE)
	assert_ne(scene, null, "app scene loads")
	var app := scene.instantiate() as Control
	app.call("_ready")
	return {"app": app, "workbench": app.get_node("%Workbench")}


func test_the_app_boots_with_its_actor_and_starter_kit() -> void:
	var booted := _boot()
	var summary: Dictionary = (booted["workbench"] as Control).call("summary")
	assert_eq(bool(summary["has_actor"]), true, "actor built")
	assert_eq(int(summary["row_count"]), 3, "starter kit present")


func test_every_feature_subsystem_is_attached_to_the_actor() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	var actor: Actor = app.get_node("%Workbench").get("_actor")
	assert_ne(actor, null, "actor reachable")
	assert_ne(actor.component(&"socket_ledger"), null, "socket ledger attached")
	assert_ne(actor.get_module_data(&"socket_state"), {}, "socket state keyed for persistence")
	assert_ne(actor.get_module_data(&"loot_state"), {}, "loot state keyed for persistence")
	assert_ne(ItemsApi.inventory(actor), null, "inventory attached")
	assert_ne(actor.resource(&"health"), null, "core resource pools attached")


func test_the_socket_and_loot_screens_are_reachable_from_the_running_app() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	# Every feature screen must be mounted on the stack, not merely constructible.
	var socket_screen: Control = app.call("open_screen", "res://src/ui/screens/socket_forge.tscn")
	assert_ne(socket_screen, null, "socket forge reachable")
	assert_eq(socket_screen.visible, true, "socket forge is the live screen")
	var loot_screen: Control = app.call("open_screen", "res://src/ui/screens/loot_encounter.tscn")
	assert_ne(loot_screen, null, "loot encounter reachable")
	assert_eq(loot_screen.visible, true, "loot encounter is the live screen")


func test_an_unknown_screen_is_reported_not_swallowed() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	assert_eq(app.call("open_screen", "res://src/ui/screens/does_not_exist.tscn"), null, "no scene")
