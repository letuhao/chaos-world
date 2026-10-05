extends TestCase

## The SET BONUS surface, driven through the controls it actually has.
##
## This screen ships NO buttons. Its entire control surface is the pair of input
## actions it consumes through `ScreenStack` — `ui_left` / `ui_right` cycle the
## authored sets, and `ui_cancel` is declined so the stack pops. So "control-driven"
## here means driving a real `ScreenStack` with a real `InputEventAction` and
## reading the screen's `summary()` afterwards.
##
## `test_set_bonus_screen.gd` calls `screen.on_stack_input(...)` on the screen
## directly. That proves the handler works; it proves nothing about the path a
## player's keypress actually takes — the stack's own input forwarding, its
## "only the live screen is told" rule, or the fact that the screen is reachable
## at all. A screen that implemented the hook but was never pushed would stay
## green forever.
##
## So every case here mounts a real `ScreenStack`, pushes the surface onto it the
## way navigation does, and sends the event to the STACK.

const SET_ID := &"ironhide_vigil"
const BAND := &"set_ironhide_vigil_band"
const PLATE := &"set_ironhide_vigil_wardplate"
const BLADE := &"set_ironhide_vigil_greatblade"

var _rig: ItemSurfaceRig = null
var _stack: ScreenStack = null
var _actor: Actor = null


func setup() -> void:
	expect_assertions(2)
	_rig = ItemSurfaceRig.new()


func teardown() -> void:
	_rig.release()
	_stack = null
	_actor = null


## A hero in the set program, plus the set surface pushed on a real stack with the
## facade's own snapshot bound in — the two seams the composition root wires.
func _open() -> SetBonusScreen:
	_actor = _rig.set_hero()
	var mounted := _rig.stack_with(ItemSurfaceRig.SET_BONUS_SCENE)
	_stack = mounted.get("stack") as ScreenStack
	var screen := mounted.get("screen") as SetBonusScreen
	if screen == null:
		return null
	screen.setup(_actor)
	screen.apply_snapshot(SetBonusApi.inspect(_actor))
	return screen


## Wear one authored set member, through the facade, so the set reports itself
## active for a reason a player produced, then republish the snapshot — which is
## what the composition root does whenever the set state moves under the screen.
## Without the republish the sheet would still be showing the snapshot it was
## handed before the member was worn, and every count below would read zero.
func _wear(slot: StringName, def_id: StringName) -> void:
	var def := SetBonusApi.definition(def_id)
	assert_ne(def, null, "'%s' resolves through the set facade" % String(def_id))
	ItemsApi.inventory(_actor).add(def, 1)
	assert_eq(ItemsApi.equip_item(_actor, slot, def), true, "'%s' is equipped" % String(def_id))
	_open_screen().apply_snapshot(SetBonusApi.inspect(_actor))


## The surface currently on the stack, typed.
func _open_screen() -> SetBonusScreen:
	return _stack.current() as SetBonusScreen


## The action event a keypress produces. An `InputEventAction` rather than a key
## event, so the case drives the surface's own vocabulary and does not depend on
## the project's key bindings.
func _key(action: StringName) -> InputEventAction:
	return _rig.press_action_key(action)


# --- The surface is reachable at all -----------------------------------------


## The screen exists, is the live one, and is the only one told about input. A
## screen nobody can push is the exact defect this slice exists for.
func test_the_surface_is_reachable_and_is_the_stack_live_screen() -> void:
	var screen := _open()
	assert_ne(screen, null, "the set bonus surface mounts on a real stack")
	assert_ne(_stack, null, "and the stack is mounted")
	assert_eq(_stack.current(), screen, "it is the live screen")
	assert_eq(int(_stack.depth()), 1, "at the only depth")
	assert_eq(
		_stack.summary()["input_names"] as Array,
		[String(screen.name)],
		"and it is the only screen the stack forwards input to"
	)


# --- Cycling, through the stack's own input forwarding ------------------------


## The control the surface is for. `ui_right` is sent to the STACK, not to the
## screen, so the whole path is under test: forwarding, the live-screen rule, the
## screen's consumption, and the repaint.
func test_ui_right_pressed_on_the_stack_cycles_to_the_next_set() -> void:
	var screen := _open()
	var ids: Array = screen.summary()["available_sets"]
	assert_eq(ids.size() >= 2, true, "there is more than one authored set to cycle")
	var before := String(screen.summary()["selected_set"])
	_stack.on_stack_input(_key(&"ui_right"))
	assert_eq(
		String(screen.summary()["selected_set"]),
		String(ids[1]),
		"the observable outcome: the pressed action moved the shown set"
	)
	assert_ne(String(screen.summary()["selected_set"]), before, "and it was not already there")
	_stack.on_stack_input(_key(&"ui_left"))
	assert_eq(String(screen.summary()["selected_set"]), before, "and left comes back")


## Wrapping. A cycle that stopped at an end would leave the far set unreachable,
## which is precisely a "cannot be reached" defect — so the wrap is asserted from
## the first set in the direction that crosses it.
func test_the_cycle_wraps_past_both_ends() -> void:
	var screen := _open()
	var ids: Array = screen.summary()["available_sets"]
	assert_eq(int(ids.size()) >= 2, true, "there is more than one set to wrap between")
	var steps := ids.size()
	_stack.on_stack_input(_key(&"ui_left"))
	assert_eq(
		String(screen.summary()["selected_set"]),
		String(ids[steps - 1]),
		"left from the first set wraps to the last rather than refusing to move"
	)
	for step in steps:
		_stack.on_stack_input(_key(&"ui_right"))
	assert_eq(
		String(screen.summary()["selected_set"]),
		String(ids[steps - 1]),
		"and one full lap of right presses is a lap: it returns where it started"
	)


## The set the player is LOOKING AT is not decoration: the thresholds and the
## membership it reports belong to the set the cycle moved to. Cycling onto a
## different set must change what the panel shows, or the control moves nothing a
## player can read.
func test_cycling_changes_which_set_the_panel_reports() -> void:
	var screen := _open()
	_wear(&"accessory_a", BAND)
	_wear(&"armor", PLATE)
	var ids: Array = screen.summary()["available_sets"]
	var first := screen.summary()["panel"] as Dictionary
	_stack.on_stack_input(_key(&"ui_right"))
	var second := screen.summary()["panel"] as Dictionary
	assert_ne(
		String(second["set_id"]),
		String(first["set_id"]),
		"the panel now reports the set the cycle moved to"
	)
	assert_ne(
		(second["member_lines"] as Array).size(),
		(first["member_lines"] as Array).size(),
		"and its membership is the new set's, not the previous one's"
	)
	assert_eq(int(ids.size()) > 1, true, "there was a second set to move to")


# --- What the cycled set reports ---------------------------------------------


## The reason the surface is worth cycling to: a worn set reads as active with
## its thresholds met, and the count of active thresholds is what the player
## reads. Read AFTER cycling onto the set, so the cycle is part of the path.
func test_cycling_onto_a_worn_set_reports_its_active_thresholds() -> void:
	var screen := _open()
	_wear(&"accessory_a", BAND)
	_wear(&"armor", PLATE)
	_wear(&"weapon", BLADE)
	# Walk the cycle to the worn set by name rather than hardcoding an ordinal: the
	# order is the catalog's, and an inserted set would silently move every index.
	var ids: Array = screen.summary()["available_sets"]
	var presses := 0
	var found := false
	while presses < ids.size():
		if String(screen.summary()["selected_set"]) == String(SET_ID):
			found = true
			break
		_stack.on_stack_input(_key(&"ui_right"))
		presses += 1
	# `ids.size()` is read BEFORE the loop and the loop only ever presses, so the
	# bound cannot grow with the body: a screen whose cycle did nothing would end
	# this loop, not spin it.
	assert_eq(found, true, "the cycle reached the worn set")
	assert_eq(screen.summary()["active_sets"] as Array, [String(SET_ID)], "it reports active")
	assert_eq(
		int(screen.summary()["active_threshold_count"]) > 0,
		true,
		"the observable outcome: its thresholds are met and the surface says so"
	)
	var panel: Dictionary = screen.summary()["panel"]
	assert_eq(int(panel["equipped_count"]), 3, "and the panel counts the three worn members")


## The stack's other half: `ui_cancel` is declined by the screen so the STACK pops.
## A screen that consumed cancel would trap the player on a read-only sheet with
## no way back.
func test_ui_cancel_is_declined_so_the_stack_pops() -> void:
	var screen := _open()
	var root := _rig.screen(ItemSurfaceRig.CHARACTER_SCENE)
	_stack.push(root)
	assert_eq(int(_stack.depth()), 2, "two screens are stacked")
	_stack.on_stack_input(_key(&"ui_cancel"))
	assert_eq(
		int(_stack.depth()),
		1,
		"the observable outcome: the stack popped, because the set screen declined cancel"
	)
	assert_eq(_stack.current(), screen, "and the sheet below is live again")
