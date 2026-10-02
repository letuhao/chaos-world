extends TestCase

## `ScreenStack` unwinding (ADR 0043). The stack used to `return` after calling
## `on_stack_input` regardless of what the screen returned, which silently killed
## `ui_cancel` on every screen built on `UiScreen`. These lock the unwinding down.

const STACK := "res://src/ui/screens/screen_stack.tscn"


func _stack() -> ScreenStack:
	return (load(STACK) as PackedScene).instantiate() as ScreenStack


func _screen(id: StringName, consumed: bool) -> Control:
	var screen := Control.new()
	screen.name = String(id)
	screen.set_script(load("res://tests/ui/fixtures/cancel_screen.gd") as GDScript)
	screen.set("consumes_cancel", consumed)
	return screen


func test_cancel_unwinds_when_the_screen_does_not_consume_it() -> void:
	var stack := _stack()
	stack.push(_screen(&"Lower", false))
	stack.push(_screen(&"Upper", false))
	assert_eq(stack.depth(), 2, "two screens stacked")
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	stack.on_stack_input(event)
	assert_eq(stack.depth(), 1, "an unconsumed cancel pops one level")
	assert_eq(String(stack.current().name), "Lower", "the one below becomes live")
	stack.free()


func test_a_screen_that_consumes_cancel_keeps_the_stack() -> void:
	var stack := _stack()
	stack.push(_screen(&"Lower", false))
	stack.push(_screen(&"Upper", true))
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	stack.on_stack_input(event)
	assert_eq(stack.depth(), 2, "a consumed cancel does not pop")
	stack.free()


func test_cancel_on_a_single_screen_does_nothing() -> void:
	var stack := _stack()
	stack.push(_screen(&"Only", false))
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	stack.on_stack_input(event)
	assert_eq(stack.depth(), 1, "the root screen cannot be popped away")
	stack.free()


func test_every_screen_declares_a_bool_returning_input_hook() -> void:
	## A `void` hook cannot express "consumed", so it would silently re-break the
	## unwind. The signature is part of the contract, so it is asserted.
	for path in [
		"res://src/ui/screens/ui_screen.gd",
		"res://src/ui/screens/item_workbench.gd",
		"res://src/ui/screens/set_bonus_screen.gd",
	]:
		var script: GDScript = load(path)
		assert_ne(script, null, "%s loads" % path)
		if script == null:
			continue
		var text := FileAccess.get_file_as_string(path)
		var signature := text.substr(text.find("func on_stack_input"))
		signature = signature.substr(0, signature.find("\n"))
		assert_eq(
			signature.contains("-> bool"),
			true,
			"%s: on_stack_input must return bool, got '%s'" % [path, signature.strip_edges()]
		)
