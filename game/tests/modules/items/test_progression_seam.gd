extends TestCase

## BL-0110 at the SEAM: the defect as a player meets it, through the mounted app.
##
## Everything else in this module's suite calls `ItemsApi.use_item` directly, which
## proves the rule but not the button. This file mounts the real composition root,
## presses the real `%UseButton` on a real authored pill, and reads the real
## validation line — because the reported defect is a press, and a rule that only a
## test can reach is not a fix.
##
## Both halves are here on purpose:
##
##   - the REFUSAL. The pill a realm seed names survives the press, the line names
##     the path it serves, and no pool moves.
##   - the ALLOWANCE. A gathered draught acquired the same way, pressed the same way,
##     is spent and a pool rises — so the gate is a gate and not a wall.
##
## Acquisition goes through the facade's own `generate` verb, the same route
## `tests/app/test_item_pipeline.gd` uses for socket content. Handing the pill to the
## bag directly would prove the bag, not acquisition.

const PILL := &"mind_core_formation_breakthrough_pill"
const DRAUGHT := &"F46_mortal_grainery_attack_speed_evasion_fortune"
const WORKBENCH_SCENE := "res://src/ui/screens/item_workbench.tscn"


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	SeamHarness.live = null


## The mounted app, opened on the workbench the way a player reaches it. Returns
## null after recording the failure, so a broken composition root is a red run and
## not a silent skip.
func _open_workbench() -> ItemWorkbench:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	if harness.boot_error != "":
		return null
	var moved := harness.navigate(SeamHarness.route_for_scene(WORKBENCH_SCENE))
	assert_eq(moved["ok"], true, "the workbench route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return null
	return harness.mounted(WORKBENCH_SCENE) as ItemWorkbench


## Acquire `def_id` through the facade's own verb, so the item arrives the way a
## drop or a craft would rather than by being handed to the bag.
func _acquire(harness: SeamHarness, def_id: StringName, seed_value: int) -> ItemDef:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "%s resolves from the shipped content tree" % def_id)
	if def == null:
		return null
	var held := ItemsApi.generate(harness.actor, def, seed_value)
	assert_ne(held, null, "%s was acquired through ItemsApi.generate" % def_id)
	return def


func test_pressing_use_on_a_progression_pill_keeps_it_and_says_why() -> void:
	var harness := SeamHarness.mount_new()
	var workbench := _open_workbench()
	if workbench == null:
		return
	var def := _acquire(harness, PILL, 4117)
	if def == null:
		return
	var row := harness.row_of_def(workbench, String(PILL))
	assert_ne(row, -1, "the acquired pill is an inventory row a player can select")
	assert_eq(harness.pick_row(workbench, row), true, "and is picked")
	# Wounded first, so "nothing was applied" is a claim about a pool that could have
	# risen rather than about a pool already at its cap.
	harness.actor.resource(&"health").change(-40.0)
	var wounded := harness.actor.resource(&"health").current
	assert_eq(harness.button(workbench, "%UseButton") != null, true, "Use is a real control")
	assert_eq(
		bool((workbench.summary() as Dictionary)["action_enabled"]["use"]),
		true,
		"and it is live -- the press reaches the facade, so this is not a dead control"
	)
	assert_eq(harness.press(workbench, "%UseButton"), true, "Use is pressed")
	var after: Dictionary = workbench.summary()
	assert_eq(String(after["message"]), "Rejected: progression_input", "the line names the refusal")
	assert_eq(String(after["tone"]), "error", "reported as a rejection, not a success")
	assert_eq(
		ItemsApi.inventory(harness.actor).count(PILL), 1, "the pill is still in the bag afterwards"
	)
	assert_almost_eq(harness.actor.resource(&"health").current, wounded, "and no pool moved for it")


func test_pressing_use_on_a_gathered_draught_still_spends_it() -> void:
	var harness := SeamHarness.mount_new()
	var workbench := _open_workbench()
	if workbench == null:
		return
	var def := _acquire(harness, DRAUGHT, 5221)
	if def == null:
		return
	harness.actor.resource(&"health").change(-40.0)
	var wounded := harness.actor.resource(&"health").current
	var row := harness.row_of_def(workbench, String(DRAUGHT))
	assert_ne(row, -1, "the acquired draught is an inventory row")
	assert_eq(harness.pick_row(workbench, row), true, "and is picked")
	assert_eq(harness.press(workbench, "%UseButton"), true, "Use is pressed")
	var after: Dictionary = workbench.summary()
	assert_eq(String(after["tone"]), "ok", "accepted rather than rejected")
	assert_eq(
		String(after["message"]).begins_with("Used "), true, "and the bar names the item used"
	)
	assert_eq(ItemsApi.inventory(harness.actor).count(DRAUGHT), 0, "exactly one unit was consumed")
	assert_eq(harness.actor.resource(&"health").current > wounded, true, "and a pool actually rose")
