class_name ScreenStack
extends Control

## Ordered screen stack for the UI program. Exactly one screen is live: the top
## one is visible, owns the viewport focus, and is the only screen whose
## unhandled input is processed. Everything below is hidden and inert, so a
## covered screen can never react to the pad or keyboard.
##
## Screens are `.tscn` files pushed in; the stack composes no widgets of its own.
## The lifecycle hooks are duck-typed so a plain `Control` also works:
## `on_screen_shown()`, `on_screen_hidden()`, `focus_initial()`, `summary()`,
## `on_stack_input(event)`.
##
## Contract: `summary()` is the testable surface. Headless tests assert it
## instead of pixels.

signal screen_pushed(screen: Control)
signal screen_popped(screen: Control)

const HOOK_FOCUS := &"focus_initial"
const HOOK_HIDDEN := &"on_screen_hidden"
const HOOK_INPUT := &"on_stack_input"
const HOOK_SHOWN := &"on_screen_shown"

var _screens: Array[Control] = []
var _focus_route: String = ""
## Screens [method pop_to_root] detached but could not free yet, drained on the next
## entry that cannot be inside their own signal. See [method _retire].
var _retired: Array[Control] = []


## Push `screen` on top of the stack and make it the live screen. Returns the
## screen so a caller can keep a typed handle without re-searching.
func push(screen: Control) -> Control:
	if screen == null:
		return null
	if _screens.has(screen):
		push_error(
			(
				(
					"ScreenStack: '%s' is already on the stack at depth %d; pushing it again "
					+ "would leave a freed copy behind"
				)
				% [screen.name, _screens.size()]
			)
		)
	if screen.get_parent() != null:
		screen.get_parent().remove_child(screen)
	add_child(screen)
	_screens.append(screen)
	_activate()
	screen_pushed.emit(screen)
	return screen


## Mount the screen registered under `id` (ADR 0184's `register_screen` seam):
## resolve the scene path through [ScreenRegistry], load and instantiate it exactly
## as a route scene is mounted, and push it. Returns the screen, or null with a
## named `push_error` when the id is unknown or its scene will not load — a
## screen that cannot mount is a reported refusal, never a silent hole.
func push_registered(id: String) -> Control:
	var scene_path := ScreenRegistry.path_of(id)
	if scene_path.is_empty():
		push_error("ScreenStack: no screen registered under '%s'" % id)
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("ScreenStack: screen '%s' has no scene at %s" % [id, scene_path])
		return null
	var screen := packed.instantiate() as Control
	if screen == null:
		push_error("ScreenStack: screen '%s' instantiates to no Control" % id)
		return null
	return push(screen)


## Drop the top screen and hand the live slot back to the one below it. Returns
## the removed screen, or null when the stack was already empty.
##
## Freed IMMEDIATELY, not with `queue_free()`. `queue_free()` defers to the end
## of the frame, and the headless runner drives every test from inside
## `SceneTree._initialize()`, where no frame is ever processed — so a deferred
## free never runs there and every pop leaked a whole screen subtree for the
## life of the process. That is the defect that took a `tests/ui` run to 67 GB
## resident. `free()` is safe in a normal game too: the node is already
## detached from the tree here, so there is nothing left to defer, and every
## signal it holds is disconnected by the free itself.
func pop() -> Control:
	if _screens.is_empty():
		return null
	_drain_retired()
	var screen: Control = _screens.pop_back()
	remove_child(screen)
	screen.free()
	_activate()
	screen_popped.emit(screen)
	return screen


## Unwind to the first screen. No-op when the stack is empty.
##
## The body pops `_screens` ITSELF rather than calling `pop()`, because the drain
## has to be visible in the body: `tests/arch_rules/test_no_unbounded_wait.gd`
## only credits a `pop_*` it can read inside the loop, since a call that shrinks
## the container somewhere else in the file says nothing about this loop.
##
## ## Why each screen is RETIRED here and not freed, unlike [method pop]
##
## This entry point is reached from INSIDE the live screen's own signal:
## `WorldMapButton.pressed` -> the panel's verb -> the app's handler ->
## `navigate_to` -> here. Freeing that screen now deletes a `Control` that is
## mid-emit, and the engine refuses it twice — "Object is locked and can't be
## freed", then "Attempted to free a locked object" — leaving the whole subtree
## standing behind a red console line. `pop()` does not share the hazard: its
## production caller is the engine's input dispatch, where the screen's hook has
## already returned.
##
## A deferred free is not the answer either: the headless runner never processes a
## frame, so `queue_free()` never runs there (`test_no_deferred_free.gd` measures
## exactly that). So a popped screen is detached HERE and held on `_retired` until
## an entry that cannot be inside its emit — the next navigation, or the stack's
## own teardown. At most one screen is ever held: the next `pop_to_root()` drains
## the previous one first, so this cannot accumulate the way the unfreed screens
## did (AGENTS.md, the 67 GB `tests/ui` run).
func pop_to_root() -> void:
	_drain_retired()
	while _screens.size() > 1:
		var screen: Control = _screens.pop_back()
		remove_child(screen)
		_retire(screen)
		_activate()
		screen_popped.emit(screen)


## Detach is done by the caller; hand `screen` to the retired list so a later entry
## frees it outside the emit that retired it. A screen already freed by someone else
## is skipped rather than double-freed.
func _retire(screen: Control) -> void:
	if is_instance_valid(screen):
		_retired.append(screen)


## Free every retired screen. Called only from entries that cannot be inside a
## retired screen's own signal — [method pop], [method pop_to_root], [method
## _exit_tree] — never from [method push], which a navigation reaches while the
## screen it just retired is still locked inside its button's `pressed` emit.
func _drain_retired() -> void:
	for screen in _retired:
		if is_instance_valid(screen):
			screen.free()
	_retired.clear()


## A retired screen is detached, so it is nobody's child: this deletion is the last
## chance to free it. Without it, one screen per stack survives every case that ends
## right after a navigation — the harness builds a fresh stack per test, and the
## headless runner shares one process across every suite.
##
## `NOTIFICATION_PREDELETE` rather than `_exit_tree()`: exit-tree is the hook for
## LEAVING the tree, and the measured behaviour of `free()` on a tree-attached node is
## that it never fires it (`test_a_stack_being_freed_drains_its_retired_screen` went
## red on the exit-tree spelling). Predelete fires on the deletion itself, attached or
## not, which is exactly when this list must be emptied.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_drain_retired()


## The live screen, or null when the stack is empty.
func current() -> Control:
	if _screens.is_empty():
		return null
	return _screens.back()


## How many screens are stacked, bottom first.
func depth() -> int:
	return _screens.size()


## Everything the stack is showing: ordering, visibility, input ownership, which
## screen focus was last routed to, and where the viewport focus actually sits.
## Values are primitives only.
func summary() -> Dictionary:
	return {
		"depth": _screens.size(),
		"names": _names(),
		"visible": _visible_names(),
		"input_names": _input_names(),
		"current": "" if current() == null else String(current().name),
		"focus_route": _focus_route,
		"focus_owner": focus_owner_name(),
	}


## Name of the focused control when it lives inside the live screen, else "".
## Empty until a viewport exists, so a headless run reports the routing decision
## (`focus_route`) rather than a phantom.
func focus_owner_name() -> String:
	var viewport := get_viewport()
	if viewport == null:
		return ""
	var focused := viewport.gui_get_focus_owner()
	if focused == null:
		return ""
	var live := current()
	if live == null or not live.is_ancestor_of(focused):
		return ""
	return String(focused.name)


## Forward an event to the live screen only. `ui_cancel` unwinds one level when
## the live screen does not consume it itself.
##
## The screen's return value decides: `true` means the screen consumed the event
## and the stack must not act on it. Returning early regardless would silently
## kill `ui_cancel` on every screen that implements the hook at all, which is
## every screen built on `UiScreen`.
func on_stack_input(event: InputEvent) -> void:
	var live := current()
	if live == null or event == null:
		return
	if live.has_method(HOOK_INPUT):
		if bool(live.call(HOOK_INPUT, event)):
			return
	if event.is_action_pressed(&"ui_cancel") and _screens.size() > 1:
		pop()


func _unhandled_input(event: InputEvent) -> void:
	on_stack_input(event)


func _activate() -> void:
	for index in _screens.size():
		var screen: Control = _screens[index]
		var live := index == _screens.size() - 1
		screen.visible = live
		screen.set_process_unhandled_input(live)
		var hook: StringName = HOOK_SHOWN if live else HOOK_HIDDEN
		if screen.has_method(hook):
			screen.call(hook)
	_focus_route = ""
	var live_screen := current()
	if live_screen != null and live_screen.has_method(HOOK_FOCUS):
		live_screen.call(HOOK_FOCUS)
		_focus_route = String(live_screen.name)


func _names() -> Array:
	var out: Array = []
	for screen in _screens:
		out.append(String(screen.name))
	return out


func _visible_names() -> Array:
	var out: Array = []
	for screen in _screens:
		if screen.visible:
			out.append(String(screen.name))
	return out


func _input_names() -> Array:
	var out: Array = []
	for screen in _screens:
		if screen.is_processing_unhandled_input():
			out.append(String(screen.name))
	return out
