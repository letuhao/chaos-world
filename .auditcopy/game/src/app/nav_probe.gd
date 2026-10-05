extends SceneTree

## Reachability proof for the shell (navigation spine). Boots the real
## `run/main_scene` through the engine — no `_ready()` call of my own — then walks
## every route in [ScreenRoutes] twice: once by pressing its digit, once by pressing
## its navigation-bar button. Each pass reports whether that route's screen became
## the live one on the stack.
##
## It is a proof, not an assertion: nothing here reads a flag the app set about
## itself. It presses the control, then reads the stack and the screen. Break a route
## and this reports it broken, with the reason.
##
## Run it through `tools/godot.py` so the engine log lands in `build/` and a hung run
## is killed:
##
##   uv run python -c "from tools import godot, common; \
##     godot.run_godot(['--headless','--path',str(common.GAME_DIR), \
##     '-s','res://src/app/nav_probe.gd'], capture=True)"
##
## Exits non-zero when any route is not reachable, so it can gate a change.

const APP_SCENE := "res://scenes/item_workbench/ItemWorkbenchApp.tscn"
const PREFIX := "NAVJSON "
const EXIT_OK := 0
const EXIT_BROKEN := 1
const VERDICT_REACHABLE := "reachable"

var _app: Node = null
var _nav: Control = null
var _failures: Array[String] = []


## Add the real scene to the tree here and do nothing else: the engine will not
## deliver `_ready()` until the tree is live, and calling it by hand would prove
## nothing about the boot a player gets.
func _initialize() -> void:
	var scene := load(APP_SCENE) as PackedScene
	if scene == null:
		push_error("NavProbe: no app scene at %s" % APP_SCENE)
		quit(EXIT_BROKEN)
		return
	_app = scene.instantiate() as Node
	root.add_child(_app)
	_nav = _app.get_node_or_null("%NavBar") as Control


## The first frame is the first moment the engine has booted the whole shell.
func _process(_delta: float) -> bool:
	_emit({"event": "boot", "boot_state": _boot_state()})
	for route in _app.call("routes"):
		_walk(route, "key")
	for route in _app.call("routes"):
		_walk(route, "button")
	_emit({"event": "crafting", "offer": _crafting_state()})
	_emit(
		{
			"event": "final",
			"route_count": (_app.call("routes") as Array).size(),
			"broken": _failures.duplicate(),
		}
	)
	quit(EXIT_OK if _failures.is_empty() else EXIT_BROKEN)
	return true


## How many authored recipes the crafting route can actually offer this hero. Zero
## offered out of a non-empty tree means the route is reachable but empty, which a
## "did the screen become live" check alone would not notice.
func _crafting_state() -> Dictionary:
	var actor: Variant = _app.get("_actor")
	if actor == null:
		return {"note": "the shell built no actor", "offered": 0, "scanned": 0}
	var offered := RecipeCatalog.offerable(actor as Actor)
	return {"offered": offered.size(), "scanned": RecipeCatalog.scanned_count()}


## What a player sees on the first frame, and whether the shell left anything behind.
##
## `detached` is the boot-time shape of the bug this probe exists to catch: a screen
## the composition root built and then dropped — alive, parented to nothing a player
## can see, and unreachable. Reading it here rather than trusting the app's own report
## is what makes the claim checkable.
func _boot_state() -> Dictionary:
	var stack := _summary().get("stack", {}) as Dictionary
	var live := _live_screen()
	var nav := _summary().get("nav", {}) as Dictionary
	return {
		"stack_depth": int(stack.get("depth", 0)),
		"stack_names": stack.get("names", []),
		"visible": stack.get("visible", []),
		"input_names": stack.get("input_names", []),
		"focus_route": String(stack.get("focus_route", "")),
		"live_node": "" if live == null else String(live.name),
		"live_scene": "" if live == null else String(live.scene_file_path),
		"live_queued_for_deletion": live != null and live.is_queued_for_deletion(),
		"live_actor_id": _bound_actor_id(live),
		"shell_actor_id": _shell_actor_id(),
		"detached": _detached(),
		"nav_active": String(nav.get("active", "")),
		"nav_slots": int(nav.get("slot_count", 0)),
		"route": String(_app.call("current_route")),
	}


## App script variables holding a node the app is not an ancestor of. Empty at boot is
## the claim "nothing is mounted and then dropped".
func _detached() -> Array[String]:
	var out: Array[String] = []
	for property in _app.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = _app.get(String(property.name))
		if value is Node and not _app.is_ancestor_of(value as Node):
			out.append("%s=%s" % [property.name, (value as Node).name])
	return out


## The actor the live screen is bound to. A screen bound to nothing, or to an actor
## other than the shell's own, is a shell rather than a reachable surface.
func _bound_actor_id(screen: Control) -> String:
	if screen == null:
		return ""
	if not screen.has_method(&"actor"):
		return ""
	var actor: Variant = screen.call(&"actor")
	return "" if actor == null else String((actor as Actor).id)


func _shell_actor_id() -> String:
	var actor: Variant = _app.get("_actor")
	return "" if actor == null else String((actor as Actor).id)


func _live_screen() -> Control:
	var shell := _app.get_node_or_null("%ScreenStack") as Control
	if shell == null:
		return null
	return shell.call(&"current") as Control


## One route, one user action, then a read of what the stack is actually showing.
func _walk(route: Dictionary, how: String) -> void:
	var route_id := StringName(route.get("id", ""))
	var pressed := (
		_press_digit(StringName(route.get("action", ""))) if how == "key" else _press_button(route)
	)
	var stack := _summary().get("stack", {}) as Dictionary
	var view := _summary().get("screen", {}) as Dictionary
	var live := String(_app.call("current_route"))
	var verdict := _verdict(route_id, live, stack, view)
	_emit(
		{
			"event": "route",
			"via": how,
			"id": String(route_id),
			"key": String(route.get("key", "")),
			"action": String(route.get("action", "")),
			"action_declared": InputMap.has_action(StringName(route.get("action", ""))),
			"pressed": pressed,
			"expected_node": String(route.get("node", "")),
			"live_route": live,
			"live_node": String(stack.get("current", "")),
			"stack_depth": int(stack.get("depth", 0)),
			"visible": stack.get("visible", []),
			"input_names": stack.get("input_names", []),
			"screen_summary_nonempty": not view.is_empty(),
			"verdict": verdict,
			"reachable": verdict == VERDICT_REACHABLE,
		}
	)
	if verdict != VERDICT_REACHABLE:
		_failures.append("%s via %s (%s)" % [route_id, how, verdict])


## Why a route is or is not reachable, most specific first. Splitting "the navigation
## moved the wrong screen" from "the right screen rendered nothing" matters: the first
## is the hub's fault, the second is whatever stopped the screen binding an actor.
func _verdict(route_id: StringName, live: String, stack: Dictionary, view: Dictionary) -> String:
	if route_id != StringName(live):
		return "did_not_move"
	var expected := String(ScreenRoutes.node_of(route_id))
	if String(stack.get("current", "")) != expected:
		return "wrong_screen"
	if (stack.get("visible", []) as Array) != [expected]:
		return "not_the_only_visible_screen"
	if (stack.get("input_names", []) as Array) != [expected]:
		return "does_not_own_input"
	if view.is_empty():
		return "mounted_but_rendered_nothing"
	return VERDICT_REACHABLE


## Deliver a real key event straight into the viewport, so the nav bar's own handler
## decides — the same path a player's keypress takes.
func _press_digit(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	var digit := String(action).substr(String(ScreenRoutes.ACTION_PREFIX).length())
	var code := digit.unicode_at(0)
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up)
	return true


## Press the route's own navigation-bar button, exactly as a click does.
func _press_button(route: Dictionary) -> bool:
	if _nav == null:
		return false
	var slot := int(ScreenRoutes.index_of(StringName(route.get("id", ""))))
	var button := _nav.get_node_or_null(NavBar.slot_unique_name(slot)) as Button
	if button == null or button.disabled or not button.visible:
		return false
	button.pressed.emit()
	return true


func _summary() -> Dictionary:
	if _app == null or not _app.has_method(&"summary"):
		return {}
	return _app.call(&"summary") as Dictionary


func _emit(payload: Dictionary) -> void:
	print(PREFIX, JSON.stringify(payload))
