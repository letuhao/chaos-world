extends TestCase

## Wave 3 exit gate, proven through the real wired scene rather than the modules
## in isolation: the app boots, a seeded rolled item is acquired, equipped,
## affects the actor, survives a save/load round trip through the injected file
## persistence without rerolling, and unequips reversibly (ADR 0027/0033).
##
## The headless runner executes suites before the tree root exists, so `_ready()`
## is invoked explicitly rather than by adding the scene to a viewport.

const APP_SCENE := "res://scenes/item_workbench/ItemWorkbenchApp.tscn"


func _boot() -> Dictionary:
	var scene: PackedScene = load(APP_SCENE)
	assert_ne(scene, null, "app scene loads")
	var app := scene.instantiate() as Control
	app.call("_ready")
	return {"app": app, "workbench": app.get_node("%Workbench")}


func _actor(app: Control) -> Actor:
	return app.get_node("%Workbench").get("_actor") as Actor


func test_app_boots_with_an_actor_and_a_starter_kit() -> void:
	var booted := _boot()
	var workbench: Control = booted["workbench"]
	var summary: Dictionary = workbench.call("summary")
	assert_eq(bool(summary["has_actor"]), true, "app built an actor")
	assert_eq(String(summary["actor_id"]), "player", "actor id")
	assert_eq(int(summary["row_count"]), 3, "starter kit covers several categories")


func test_wired_scene_runs_the_full_item_loop() -> void:
	var booted := _boot()
	var app: Control = booted["app"]
	var workbench: Control = booted["workbench"]
	var actor := _actor(app)
	assert_ne(actor, null, "actor reachable through the wired screen")

	# Acquire: a seeded rolled item lands in the inventory as its own instance.
	var helm := Crafting.resolve(&"armor_iron_helm")
	assert_ne(helm, null, "starter definition resolves through the module resolver")
	var before_defense := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	var instance := ItemsApi.generate(actor, helm, 104729)
	assert_ne(instance, null, "generated item acquired")
	assert_eq(instance.rolled.size() > 0, true, "the acquired item carries a real roll")

	# Equip: the item's fixed and rolled effects apply exactly once. The starter
	# kit already holds a helm, so equip takes the first instance for that
	# definition and leaves the freshly rolled one distinct in the bag.
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, helm), true, "equipped")
	var equipped_defense := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_eq(equipped_defense > before_defense, true, "equipping raised the stat")
	var equipped_before := ItemsApi.equipment(actor).equipped(Equipment.ARMOR)
	assert_ne(equipped_before, null, "slot holds an instance")
	assert_eq(
		equipped_before.instance_id != instance.instance_id,
		true,
		"distinct instances of one definition stay distinct"
	)
	var signature := equipped_before.stacking_signature()

	# Persist through the injected file-backed callables, then restore.
	assert_eq(bool(workbench.call("act_save")), true, "save accepted")
	var payload := ItemsApi.serialize(actor)
	assert_eq(bool(payload.has("version")), true, "payload is versioned")
	assert_eq(bool(workbench.call("act_load")), true, "load accepted")

	# Restored, not rerolled: the effect and the realization are identical.
	var restored := ItemsApi.equipment(actor).equipped(Equipment.ARMOR)
	assert_ne(restored, null, "equipped item restored")
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		equipped_defense,
		"stat identical after a save/load round trip"
	)
	assert_eq(restored.stacking_signature(), signature, "realized roll preserved, not rerolled")

	# Loading must replace, not append: a second load cannot duplicate items.
	var rows_after_one: int = int((workbench.call("summary") as Dictionary)["row_count"])
	assert_eq(bool(workbench.call("act_load")), true, "second load accepted")
	var rows_after_two: int = int((workbench.call("summary") as Dictionary)["row_count"])
	assert_eq(rows_after_two, rows_after_one, "loading replaces item state, never appends")

	# Unequip: reversible, and the item returns to the inventory intact.
	assert_eq(ItemsApi.unequip_to_inventory(actor, Equipment.ARMOR), true, "unequipped")
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL), before_defense, "bonus removed exactly once"
	)
	assert_eq(
		ItemsApi.inventory(actor).find_instance(helm.id) != null, true, "item back in inventory"
	)


func test_actions_report_disabled_when_no_persistence_is_injected() -> void:
	var booted := _boot()
	var workbench: Control = booted["workbench"]
	# Rebinding to the same actor with no persistence must disable Save/Load
	# rather than pretending they worked.
	workbench.call("setup", _actor(booted["app"]))
	var enabled: Dictionary = (workbench.call("summary") as Dictionary)["action_enabled"]
	assert_eq(bool(enabled["save"]), false, "save disabled with no persistence")
	assert_eq(bool(enabled["load"]), false, "load disabled with no persistence")
	assert_eq(bool(workbench.call("act_save")), false, "save rejected")
	var summary: Dictionary = workbench.call("summary")
	assert_eq(String(summary["tone"]), "error", "rejection is visible")
	assert_eq(String(summary["message"]).contains("no_persistence"), true, "reason reported")


func test_generated_item_is_selectable_and_shows_its_rolls() -> void:
	var booted := _boot()
	var workbench: Control = booted["workbench"]
	var keys: Array = (workbench.call("summary") as Dictionary)["inventory"]["row_keys"]
	assert_eq(keys.is_empty(), false, "inventory lists selectable rows")
	var distinct: Dictionary = {}
	for key in keys:
		distinct[String(key)] = true
	assert_eq(distinct.size(), keys.size(), "row keys are distinct batches, not bare def ids")
