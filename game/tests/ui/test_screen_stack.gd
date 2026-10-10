extends TestCase

## The screen stack owns focus and input: exactly one screen is live and it is
## the top one. Headless tests assert `summary()`, never pixels.

const STACK_SCENE := "res://src/ui/screens/screen_stack.tscn"
const WORKBENCH_SCENE := "res://src/ui/screens/item_workbench.tscn"


func _stack() -> ScreenStack:
	var stack: ScreenStack = load(STACK_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	return stack


func _screen(node_name: String) -> Control:
	var screen := Control.new()
	screen.name = node_name
	screen.size = Vector2(480.0, 320.0)
	return screen


func _workbench() -> ItemWorkbench:
	var screen: ItemWorkbench = load(WORKBENCH_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


# --- Ordering --------------------------------------------------------------


func test_push_makes_the_pushed_screen_the_live_one() -> void:
	var stack := _stack()
	var screen := _screen("FirstScreen")
	assert_eq(stack.push(screen) == screen, true, "push hands back the screen")
	assert_eq(stack.depth(), 1, "one screen on the stack")
	assert_eq(stack.current() == screen, true, "the pushed screen is current")
	var view := stack.summary()
	assert_eq(view["depth"], 1, "summary depth")
	assert_eq(view["current"], "FirstScreen", "summary current")
	assert_eq(view["names"], ["FirstScreen"], "names read bottom first")
	assert_eq(view["visible"], ["FirstScreen"], "the live screen is visible")
	assert_eq(view["input_names"], ["FirstScreen"], "input follows the top")
	stack.free()


func test_push_order_and_pop_return_the_top_screen() -> void:
	var stack := _stack()
	var first := _screen("FirstScreen")
	var second := _screen("SecondScreen")
	stack.push(first)
	stack.push(second)
	var pushed := stack.summary()
	assert_eq(pushed["names"], ["FirstScreen", "SecondScreen"], "push order, bottom first")
	assert_eq(pushed["current"], "SecondScreen", "the newest screen is current")
	assert_eq(pushed["visible"], ["SecondScreen"], "a covered screen is hidden")
	assert_eq(pushed["input_names"], ["SecondScreen"], "a covered screen gets no input")
	assert_eq(stack.pop() == second, true, "pop hands back the top screen")
	# Freed immediately, not queued: the headless runner never processes a frame,
	# so a deferred free would never run and every pop would leak a screen subtree
	# for the life of the process.
	assert_eq(is_instance_valid(second), false, "the popped screen is freed")
	assert_eq(stack.depth(), 1, "back to one screen")
	var popped := stack.summary()
	assert_eq(popped["current"], "FirstScreen", "the uncovered screen is live again")
	assert_eq(popped["visible"], ["FirstScreen"], "and visible again")
	assert_eq(popped["input_names"], ["FirstScreen"], "and owns input again")
	stack.free()


func test_pop_on_an_empty_stack_returns_null() -> void:
	var stack := _stack()
	assert_eq(stack.pop(), null, "nothing to pop")
	assert_eq(stack.depth(), 0, "still empty")
	assert_eq(stack.current(), null, "no live screen")
	assert_eq(stack.focus_owner_name(), "", "nothing owns focus")
	stack.free()


func test_pop_to_root_keeps_only_the_first_screen() -> void:
	var stack := _stack()
	stack.push(_screen("FirstScreen"))
	stack.push(_screen("SecondScreen"))
	stack.push(_screen("ThirdScreen"))
	assert_eq(stack.depth(), 3, "three screens")
	stack.pop_to_root()
	assert_eq(stack.depth(), 1, "unwound to the root")
	assert_eq(stack.summary()["current"], "FirstScreen", "the root screen is live")
	stack.free()


# --- Retired screens: the emit lock ----------------------------------------


## A navigation triggered by the LIVE screen's own button: `pressed` -> the app-style
## handler -> `pop_to_root()`. Freeing the screen there deletes a `Control` that is
## mid-emit, which the engine refuses ("Object is locked and can't be freed", then
## "Attempted to free a locked object") and the subtree stands behind a red console
## line. This pins both halves of the fix: the emit completes with the stack unwound,
## and the retired screen is freed by the NEXT entry instead of inside its own signal.
func test_pop_to_root_from_inside_a_screens_own_signal_retires_it() -> void:
	var stack := _stack()
	var root_screen := _screen("RootScreen")
	stack.push(root_screen)
	var visitor := _screen("VisitorScreen")
	var button := Button.new()
	button.name = "NavigateAway"
	visitor.add_child(button)
	var navigations := {"count": 0}
	button.pressed.connect(
		func() -> void:
			navigations["count"] += 1
			stack.pop_to_root()
	)
	stack.push(visitor)
	# The write is inside the `while` test on purpose: the body shrinks `_screens`, so a
	# bound read after the loop would be the loop-bounded-by-what-it-grows shape.
	assert_eq(stack.depth(), 2, "two screens before the press")
	button.pressed.emit()
	assert_eq(navigations["count"], 1, "the handler ran inside the emit")
	assert_eq(stack.depth(), 1, "the emit completed and the stack unwound")
	assert_eq(stack.current() == root_screen, true, "the root screen is live")
	assert_eq(is_instance_valid(visitor), true, "a screen retired mid-emit survives it")
	# The next entry is a fresh emit chain, so the drain there cannot hit the lock.
	stack.pop_to_root()
	assert_eq(is_instance_valid(visitor), false, "and the next entry frees it")
	stack.free()


## The teardown half: a stack deleted while one screen is still retired must free it.
## The harness builds a fresh stack per case and the headless runner shares one
## process across every suite, so a screen left retired at teardown leaks for the life
## of the run — the shape the 67 GB `tests/ui` incident was made of.
func test_a_stack_being_freed_drains_its_retired_screen() -> void:
	var stack := _stack()
	stack.push(_screen("RootScreen"))
	var visitor := _screen("VisitorScreen")
	stack.push(visitor)
	stack.pop_to_root()
	assert_eq(is_instance_valid(visitor), true, "retired rather than freed in the emit")
	stack.free()
	assert_eq(is_instance_valid(visitor), false, "the stack's own teardown frees it")


# --- Focus and input routing ----------------------------------------------


func test_focus_routes_to_the_top_screen() -> void:
	var stack := _stack()
	var bottom := _screen("BottomScreen")
	var bottom_button := Button.new()
	bottom_button.name = "BottomFocus"
	bottom_button.focus_mode = Control.FOCUS_ALL
	bottom.add_child(bottom_button)
	stack.push(bottom)
	assert_eq(stack.summary()["focus_route"], "", "a bare Control has no focus hook")
	var top := _workbench()
	stack.push(top)
	var view := stack.summary()
	# The invariant is identity: the stack made the screen it was handed the live
	# one, and `summary()` names that same screen. Godot auto-renames a node that
	# collides with a sibling, so the name is checked against the live node
	# rather than against a literal.
	assert_eq(stack.current(), top, "the workbench is live")
	assert_eq(view["current"], String(top.name), "summary names the live screen")
	assert_eq(view["focus_route"], String(top.name), "focus routed to the top screen")
	# With no actor bound the screen reports `{}`, so the stack's routing
	# decision is the observable signal; a bound screen adds its own target.
	assert_eq(top.summary(), {}, "an unbound screen reports an empty summary")
	var actor := ActorFactory.build(&"router", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	top.setup(actor)
	assert_eq(String(top.summary()["focus_target"]), "ItemList", "its own focus target")
	assert_eq(bottom.visible, false, "the covered screen is hidden")
	stack.free()


func test_the_screen_stack_sets_the_initial_focus_for_a_pushed_screen() -> void:
	var stack := _stack()
	var workbench := _workbench()
	var actor := ActorFactory.build(&"focuser", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	workbench.setup(actor)
	stack.push(workbench)
	assert_eq(
		stack.summary()["focus_route"], String(workbench.name), "the stack routed focus to it"
	)
	var view := workbench.summary()
	assert_eq(String(view["focus_target"]), "ItemList", "one initial focus control")
	assert_eq(String(view["actions"]["focus_target"]), "", "the action bar did not steal focus")
	stack.free()


func test_ui_cancel_unwinds_one_level_instead_of_reaching_a_covered_screen() -> void:
	var stack := _stack()
	stack.push(_screen("FirstScreen"))
	stack.push(_screen("SecondScreen"))
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	stack.on_stack_input(cancel)
	assert_eq(stack.depth(), 1, "ui_cancel unwound one level")
	assert_eq(stack.summary()["current"], "FirstScreen", "the screen below is live")
	stack.free()
