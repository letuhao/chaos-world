extends TestCase

## What the **mounted** composition root actually builds, proven through
## `SeamHarness` rather than through a detached instance.
##
## The previous version of this file instantiated `ItemWorkbenchApp.tscn`, called
## `_ready()` by hand and left the scene parented to nothing. A scene nobody can
## reach is not the app a player runs, so every assertion here goes through the
## harness, which parents the real scene under the tree root first.
##
## Screen reachability lives in `test_screen_reachability.gd`; the item loop lives
## in `test_item_pipeline.gd`.


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


func test_the_app_mounts_its_actor_and_starter_kit() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var view := harness.workbench.summary() as Dictionary
	assert_eq(bool(view["has_actor"]), true, "the app built an actor")
	assert_eq(String(view["actor_id"]), "player", "with the app's own id")
	assert_eq(int(view["row_count"]) > 0, true, "and a starter kit across several categories")
	assert_eq(
		harness.bound_actor(harness.workbench), harness.actor, "the mounted screen shows that actor"
	)


func test_the_mounted_screen_is_a_descendant_of_the_mounted_app() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	# The distinction the false proof lost: a screen parented under the running app
	# is mounted; a screen a test instantiated and pushed itself is not.
	assert_eq(
		harness.root.is_ancestor_of(harness.workbench),
		true,
		"the workbench is mounted under the tree root"
	)
	assert_eq(
		harness.root.is_ancestor_of(harness.stack), true, "so is the screen stack the app created"
	)
	assert_eq(
		harness.app.is_ancestor_of(harness.stack),
		true,
		"the stack the app created is inside the app, not a sibling a test pushed"
	)
	assert_eq(harness.stack.depth() > 0, true, "the stack is showing something after boot")
	# The workbench is the stack's root screen now, not a sibling beside it, so the
	# harness resolves it through the mounted tree rather than a unique name.
	assert_eq(
		(
			harness.stack.is_ancestor_of(harness.workbench)
			or harness.app.is_ancestor_of(harness.workbench)
		),
		true,
		"and the workbench is inside the app the harness mounted"
	)


func test_every_feature_subsystem_is_attached_to_the_mounted_actor() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	assert_ne(actor.component(&"socket_ledger"), null, "the socket ledger is attached")
	assert_ne(actor.get_module_data(&"socket_state"), {}, "socket state is keyed for persistence")
	assert_ne(actor.get_module_data(&"loot_state"), {}, "loot state is keyed for persistence")
	assert_ne(ItemsApi.inventory(actor), null, "the inventory is attached")
	assert_ne(actor.resource(&"health"), null, "the core resource pools are attached")
	assert_ne(ItemsApi.equipment(actor), null, "the equipment layer is attached")


func test_persistence_is_injected_so_save_and_load_are_offered() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var enabled: Dictionary = (harness.workbench.summary() as Dictionary)["action_enabled"]
	assert_eq(bool(enabled["save"]), true, "Save is offered with the app's file persistence")
	assert_eq(bool(enabled["load"]), true, "Load is offered too")


func test_save_and_load_are_disabled_when_no_persistence_is_injected() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	# Rebinding to the same actor with no persistence must disable Save/Load rather
	# than pretending they worked.
	harness.workbench.call("setup", harness.actor)
	var enabled: Dictionary = (harness.workbench.summary() as Dictionary)["action_enabled"]
	assert_eq(bool(enabled["save"]), false, "save is disabled with no persistence")
	assert_eq(bool(enabled["load"]), false, "load is disabled with no persistence")
	# A disabled control is the honest outcome: a player cannot press it at all, so
	# there is no rejection message to show.
	assert_eq(
		bool(harness.press(harness.workbench, "%SaveButton")),
		false,
		"and the save control cannot be pressed"
	)
	assert_eq(
		bool(harness.press(harness.workbench, "%LoadButton")), false, "nor can the load control"
	)
	var message: Dictionary = (harness.workbench.summary() as Dictionary)["actions"]
	assert_eq(String(message["message"]), "", "no outcome is claimed for a dead control")


func test_generated_items_are_selectable_and_show_their_own_rolls() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var summary := harness.workbench.summary() as Dictionary
	var keys: Array = (summary["inventory"] as Dictionary)["row_keys"]
	assert_eq(keys.is_empty(), false, "the inventory lists selectable rows")
	var distinct: Dictionary = {}
	for key in keys:
		distinct[String(key)] = true
	assert_eq(distinct.size(), keys.size(), "row keys are distinct batches, not bare def ids")
	assert_eq(
		harness.row_of_def(harness.workbench, "armor_iron_helm") >= 0,
		true,
		"and a def id can be resolved back to its row"
	)


func test_the_stack_keeps_exactly_one_live_screen() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var view := harness.stack.summary()
	assert_eq(int(view["depth"]), int((view["names"] as Array).size()), "depth matches the names")
	assert_eq((view["visible"] as Array).size(), 1, "exactly one screen is visible")
	assert_eq(view["current"], String(harness.live_screen().name), "and it is the reported one")
	assert_eq(view["input_names"], view["visible"], "input follows visibility")
	assert_eq(
		String(view["focus_route"]),
		String(harness.live_screen().name),
		"focus was routed to the live screen"
	)
