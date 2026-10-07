class_name UiScreen
extends Control

## Base for every screen in the UI program. Encodes the screen contract once so
## no individual screen has to re-derive it:
##
##   - nodes resolve lazily in `_bind_nodes()`, never `@onready`, so a screen is
##     drivable headlessly before a scene tree exists
##   - `summary()` is the testable surface: primitives only, `{}` with no actor,
##     child panel summaries nested under the child's key
##   - the four `ScreenStack` hooks exist and are safe to call at any time
##   - `focus_initial()` records the target first, then grabs focus only when the
##     screen is actually inside a viewport
##
## A subclass supplies its own `_summary()` and may override `_bind_nodes()`,
## but must call `super()` so the base keeps its bindings.

const TONE_ERROR := &"error"
const TONE_OK := &"ok"

var _actor: Actor = null
var _message: String = ""
var _tone: StringName = &""
var _focus_target: String = ""


## Inject the actor this screen renders. Safe to call repeatedly; the screen
## re-reads the facade on each call.
func setup(actor: Actor) -> void:
	_actor = actor
	refresh()


## The actor this screen is bound to, or null.
func actor() -> Actor:
	return _actor


## Re-read state and repaint. Every action ends here; subclasses override
## `_refresh_view()` rather than this.
func refresh() -> void:
	_bind_nodes()
	_refresh_view()
	_render()


## Everything the screen shows, as primitives. The headless tests and the LLM
## CLI read this instead of pixels.
func summary() -> Dictionary:
	var view := _summary()
	if view.is_empty():
		return {}
	view["message"] = _message
	view["tone"] = String(_tone)
	view["focus_target"] = _focus_target
	return view


## Report the outcome of an action through the shared message line.
func set_message(message: String, tone: StringName = &"") -> void:
	_message = message
	_tone = tone


# --- ScreenStack hooks ------------------------------------------------------


func on_screen_shown() -> void:
	refresh()


func on_screen_hidden() -> void:
	pass


## Give the keyboard and pad a landing spot. The base records the first focusable
## control it finds; a screen with a specific entry point overrides this.
func focus_initial() -> void:
	_bind_nodes()
	var target := _first_focusable()
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.grab_focus()


## Return true to consume the event. The base leaves `ui_cancel` alone so
## `ScreenStack` can pop.
func on_stack_input(_event: InputEvent) -> bool:
	return false


# --- For subclasses ---------------------------------------------------------


## Build the screen's view state. Return `{}` when there is no actor. Overridden
## by every screen; the base does not implement it.
func _summary() -> Dictionary:
	return {}


## Repaint from state. The base has no widgets of its own, so it does nothing.
func _refresh_view() -> void:
	pass


## Repaint widgets. Same contract as `_refresh_view`; kept separate so a screen
## that only re-reads state does not have to define an empty render.
func _render() -> void:
	pass


## Resolve scene nodes. Idempotent; override but always call `super()`.
func _bind_nodes() -> void:
	# A scene's literal text is a KEY with no call site, so the screen resolves its own subtree
	# here: before any `summary()` reads a label, and before `_render()` overwrites dynamic text.
	L.localize_tree(self)


## The first enabled focusable control, or null. Depth-first so a screen's own
## controls beat a nested panel's.
func _first_focusable() -> Control:
	for child in get_children():
		var found := _find_focusable(child)
		if found != null:
			return found
	return null


func _find_focusable(node: Node) -> Control:
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and not control.disabled:
			return control
	for child in node.get_children():
		var found := _find_focusable(child)
		if found != null:
			return found
	return null
