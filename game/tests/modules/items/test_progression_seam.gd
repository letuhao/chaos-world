extends TestCase

## BL-0110 at the SEAM: the defect as a player meets it, through the mounted app.
##
## Everything else in this module's suite calls `ItemsApi.use_item` directly, which
## proves the rule but not the button. This file mounts the real composition root,
## presses the real `%UseButton` on a real authored pill, and reads the real
## validation line — because the reported defect is a press, and a rule only a test
## can reach is not a fix.
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

var _harness: SeamHarness = null
var _workbench: ItemWorkbench = null


func setup() -> void:
	_harness = null
	_workbench = null


func teardown() -> void:
	# One mount per test and one teardown, always paired. `SeamHarness.live` is
	# process-wide and the runner shares one process across every suite, so a mount
	# left behind leaks into the next test.
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	SeamHarness.live = null
	_harness = null
	_workbench = null


## Mount the real app and open the workbench the way a player reaches it. Records
## the failure and returns false rather than skipping, because a broken composition
## root is a red run and never a neutral observation.
func _open() -> bool:
	_harness = SeamHarness.mount_new()
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	if _harness.boot_error != "":
		return false
	var moved := _harness.navigate(SeamHarness.route_for_scene(WORKBENCH_SCENE))
	assert_eq(moved["ok"], true, "the workbench route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return false
	_workbench = _harness.mounted(WORKBENCH_SCENE) as ItemWorkbench
	assert_ne(_workbench, null, "the mounted workbench is the screen on the stack")
	return _workbench != null


## Acquire `def_id` through the facade's own verb, so the item arrives the way a
## drop or a craft would rather than by being handed to the bag.
func _acquire(def_id: StringName, seed_value: int) -> bool:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "%s resolves from the shipped content tree" % def_id)
	if def == null:
		return false
	assert_ne(
		ItemsApi.generate(_harness.actor, def, seed_value),
		null,
		"%s was acquired through ItemsApi.generate" % def_id
	)
	return true


func test_pressing_use_on_a_progression_pill_keeps_it_and_says_why() -> void:
	if not _open():
		return
	if not _acquire(PILL, 4117):
		return
	var row := _harness.row_of_def(_workbench, String(PILL))
	assert_ne(row, -1, "the acquired pill is an inventory row a player can select")
	assert_eq(_harness.pick_row(_workbench, row), true, "and is picked")
	# Wounded first, so "nothing was applied" is a claim about a pool that could have
	# risen rather than about a pool already sitting at its cap.
	_harness.actor.resource(&"health").change(-40.0)
	var wounded := _harness.actor.resource(&"health").current
	assert_ne(_harness.button(_workbench, "%UseButton"), null, "Use is a real control")
	assert_eq(
		bool((_workbench.summary() as Dictionary)["action_enabled"]["use"]),
		true,
		"and it is live -- the press reaches the facade, so this is not a dead control"
	)
	assert_eq(_harness.press(_workbench, "%UseButton"), true, "Use is pressed")
	var after: Dictionary = _workbench.summary()
	assert_eq(String(after["message"]), "Rejected: progression_input", "the line names the refusal")
	assert_eq(String(after["tone"]), "error", "reported as a rejection, not a success")
	assert_eq(
		ItemsApi.inventory(_harness.actor).count(PILL), 1, "the pill is still in the bag afterwards"
	)
	assert_almost_eq(
		_harness.actor.resource(&"health").current, wounded, "and no pool moved for it"
	)


func test_pressing_use_on_a_gathered_draught_still_spends_it() -> void:
	if not _open():
		return
	if not _acquire(DRAUGHT, 5221):
		return
	_harness.actor.resource(&"health").change(-40.0)
	var wounded := _harness.actor.resource(&"health").current
	var row := _harness.row_of_def(_workbench, String(DRAUGHT))
	assert_ne(row, -1, "the acquired draught is an inventory row")
	assert_eq(_harness.pick_row(_workbench, row), true, "and is picked")
	assert_eq(_harness.press(_workbench, "%UseButton"), true, "Use is pressed")
	var after: Dictionary = _workbench.summary()
	assert_eq(String(after["tone"]), "ok", "accepted rather than rejected")
	assert_eq(
		String(after["message"]).begins_with("Used "), true, "and the bar names the item used"
	)
	assert_eq(ItemsApi.inventory(_harness.actor).count(DRAUGHT), 0, "exactly one unit was consumed")
	assert_eq(
		_harness.actor.resource(&"health").current > wounded, true, "and a pool actually rose"
	)
