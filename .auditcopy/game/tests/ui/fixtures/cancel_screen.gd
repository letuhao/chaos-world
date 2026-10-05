extends Control

## Test double for `ScreenStack` unwinding (ADR 0042). Reports whether it consumes
## `ui_cancel`, so the stack's consume-vs-unwind decision can be asserted.

var consumes_cancel: bool = false


func on_stack_input(event: InputEvent) -> bool:
	if consumes_cancel and event.is_action_pressed(&"ui_cancel"):
		return true
	return false


func summary() -> Dictionary:
	return {"consumes_cancel": consumes_cancel}
