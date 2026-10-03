class_name SeamHarness
extends RefCounted

## One reusable harness for every proof in `tests/app/` and `tests/ui/`.
##
## It exists because the runner executes suites inside `SceneTree._initialize()`,
## where `root` is not yet inside the tree: `get_viewport()` is null, and the engine
## never fires `_ready()` or `@onready` for anything parented to `root`. That is a
## fact about the runner, not a bug to route around per test, so it is handled here
## once — `mount()` parents the **real** `ItemWorkbenchApp.tscn` under `root` and
## then drives `_ready()` exactly once, the way the engine would.
##
## Two rules this harness exists to enforce:
##
##  - Assert on the **mounted** scene. A test that instantiates its own copy of a
##    screen proves the scene file parses; it proves nothing about the app a player
##    runs. `mounted()` and `live_screen()` only ever hand back nodes that live
##    under `root`, i.e. nodes the composition root itself parented.
##  - A missing seam must be a **counted failure**, never a `call()` on a method
##    that does not exist. `call()` on an absent method is a script error, the
##    function aborts, and the suite still reports its other assertions — a green
##    run that silently skipped the claim. `routes()`/`navigate()`/`current_route()`
##    therefore check `has_method()` first and return a note naming the missing seam,
##    so the caller records a real failure and can stop.

const APP_SCENE := "res://scenes/item_workbench/ItemWorkbenchApp.tscn"
const SCREENS_DIR := "res://src/ui/screens"
## The stack is the container, not a screen: it is never a navigation destination.
const STACK_SCENE := "res://src/ui/screens/screen_stack.tscn"
## Where the composition root's file-backed persistence writes. Cleared before every
## mount, because the runner shares one process across every suite: a save left by an
## earlier suite is loaded by the next one's `Load`, so the hero a test sees would
## depend on which suite ran first.
const SAVE_PATH := "user://item_workbench_state.json"

## What each missing navigation seam means, phrased once so every assertion that
## hits it reports the same cause and cites the backlog entry.
const NAV_MISSING_ROUTES := (
	"MISSING SEAM: the composition root publishes no routes(); no player action can "
	+ "reach any screen, so screen reachability is unproven (BL-0118)"
)
const NAV_MISSING_NAVIGATE := (
	"MISSING SEAM: the composition root has no navigate_to(route_id); nothing in src/ "
	+ "can move the player from one screen to another (BL-0121)"
)
const NAV_MISSING_CURRENT_ROUTE := (
	"MISSING SEAM: the composition root has no current_route(); a navigation call "
	+ "cannot be checked against the route it claims to have reached"
)

## The one harness currently holding a mounted scene. `teardown()` is idempotent and
## a suite calls it from `setup()`, so a test that aborted mid-function cannot leak a
## second mounted app into the next test. The runner shares one process across every
## suite, so a leak here is a leak everywhere.
## The reward row scene and its own action control, by node name: the rows are
## instantiated, so no single owner holds them and a unique name will not resolve.
const DROP_ROW_NODE := "LootDropRow"
const DROP_ACTION_NODE := "%DropAction"
## Depth ceiling for the row walk. The reward list is three levels deep, so this is
## slack rather than a tuned number.
const MAX_TREE_WALK := 12

static var live: SeamHarness = null

var root: Window = null
var app: Control = null
var stack: ScreenStack = null
var actor: Actor = null
var workbench: ItemWorkbench = null
## "" when the app booted; otherwise the reason, already phrased for a failure label.
var boot_error: String = ""
## Screens the composition root created but did not leave mounted under `root`.
var detached: Array[Node] = []


## Mount the real app scene and boot it. Always paired with `teardown()`.
static func mount_new() -> SeamHarness:
	if live != null:
		live.teardown()
	clear_save()
	var harness := SeamHarness.new()
	harness._mount()
	live = harness
	return harness


## Delete the composition root's save file, so a mount always starts from the shipped
## starter kit rather than from whatever a previous suite persisted.
static func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _mount() -> void:
	root = (Engine.get_main_loop() as SceneTree).root
	var scene := load(APP_SCENE) as PackedScene
	if scene == null:
		boot_error = "MISSING SEAM: %s does not load" % APP_SCENE
		return
	app = scene.instantiate() as Control
	if app == null:
		boot_error = "MISSING SEAM: %s has no instantiable root" % APP_SCENE
		return
	root.add_child(app)
	# The runner gives us a `root` that is not yet inside the tree, so the engine
	# will not deliver `_ready()`. Drive it once, here, and nowhere else.
	app.call("_ready")
	# Resolved the way the composition root resolves its own widgets: by unique name.
	# Class-name search is the fallback because a scene root is a plain `Control`
	# until its script is registered.
	stack = _resolve(app, "%ScreenStack", "ScreenStack") as ScreenStack
	workbench = _resolve(app, "%Workbench", "ItemWorkbench") as ItemWorkbench
	if stack == null:
		boot_error = "MISSING SEAM: %s mounts no ScreenStack" % APP_SCENE
		return
	if workbench == null:
		boot_error = "MISSING SEAM: %s mounts no workbench screen" % APP_SCENE
		return
	if stack.depth() == 0:
		boot_error = ("MISSING SEAM: the app mounted no screen at boot; its _ready() did not finish")
		return
	# The composition root owns the actor, not the workbench: the root route is bound
	# with `setup(actor, save, load)` and the actor is a field on the root. Reading it
	# from the root is what makes this the app's real hero rather than a guess.
	actor = app.get("_actor") as Actor
	if actor == null and workbench != null:
		actor = workbench.get("_actor") as Actor
	if actor == null:
		boot_error = "MISSING SEAM: the composition root built no actor for its screens"
		return
	_collect_detached()


## Screens the app built and then detached. They are alive, owned by nothing the
## player can see, and unreachable — the shape a "green but unreachable" feature
## takes. Reported, and freed on teardown.
##
## Read from the app's script variables, and only from the ones declared to hold a
## `Node`: touching every property would read values the app has not built yet.
func _collect_detached() -> void:
	detached.clear()
	for property in app.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if int(property.get("type", 0)) != TYPE_OBJECT:
			continue
		var value: Variant = app.get(property.name)
		if value is Node and not root.is_ancestor_of(value as Node):
			detached.append(value as Node)


## Free everything this harness mounted. Safe to call twice, and safe to call after
## an aborted test: `mount_new()` also calls it on whatever was left behind.
func teardown() -> void:
	for node in detached:
		if is_instance_valid(node):
			node.free()
	detached.clear()
	if app != null and is_instance_valid(app):
		if app.get_parent() != null:
			app.get_parent().remove_child(app)
		app.free()
	app = null
	stack = null
	actor = null
	workbench = null
	if live == self:
		live = null
	clear_save()


# --- The mounted tree --------------------------------------------------------


## The screen the stack is currently showing, or null.
func live_screen() -> Control:
	return null if stack == null else stack.current()


## The mounted node for `scene_path`, or null when nothing under the app was
## instantiated from that scene. Searches the mounted tree only, so a screen a test
## instantiated itself can never be mistaken for a mounted one.
func mounted(scene_path: String) -> Control:
	if app == null:
		return null
	if app.scene_file_path == scene_path:
		return app
	return _descendant_from_scene(app, scene_path)


## The actor a mounted screen is bound to, or null. `UiScreen` publishes `actor()`;
## the two screens that predate it hold `_actor`. A mounted screen bound to nothing
## (or to some other actor) is a shell, not a reachable surface.
func bound_actor(screen: Node) -> Actor:
	if screen == null:
		return null
	if screen.has_method(&"actor"):
		return screen.call(&"actor") as Actor
	return screen.get("_actor") as Actor


## Every screen scene the UI program ships, sorted, excluding the stack itself.
## Discovered from the filesystem rather than declared here, so a screen nobody
## routed still shows up — that is the whole point of the reachability suite.
static func screen_scene_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SCREENS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tscn"):
			var path := "%s/%s" % [SCREENS_DIR, entry]
			if path != STACK_SCENE:
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## The route the composition root publishes for `scene_path`, or "" when the route
## table does not name it. Asked of the shipped table rather than restated here, so
## this harness cannot hold a second, disagreeing copy of it.
static func route_for_scene(scene_path: String) -> StringName:
	return StringName(ScreenRoutes.id_for_scene(scene_path))


## `scene_path -> route id` for every shipped screen the route table names.
static func shipped_routes() -> Dictionary:
	var out: Dictionary = {}
	for scene_path in screen_scene_paths():
		var route_id := route_for_scene(scene_path)
		if not route_id.is_empty():
			out[scene_path] = route_id
	return out


# --- Navigation: the hub seam -----------------------------------------------


## The routes the composition root publishes. Returns `[]` plus a note when the
## seam is absent, so the caller records a failure instead of aborting.
func routes() -> Dictionary:
	if app == null:
		return {"routes": [], "note": boot_error}
	if not app.has_method(&"routes"):
		return {"routes": [], "note": NAV_MISSING_ROUTES}
	var listed: Variant = app.call(&"routes")
	return {"routes": listed, "note": ""}


## Drive one route the way a player would: navigate to it, then report what the
## stack is actually showing. Returns `{"ok": bool, "note": String}`.
func navigate(route_id: StringName) -> Dictionary:
	if app == null:
		return {"ok": false, "note": boot_error}
	if not app.has_method(&"navigate_to"):
		return {"ok": false, "note": NAV_MISSING_NAVIGATE}
	if not bool(app.call(&"navigate_to", route_id)):
		return {
			"ok": false,
			"note": "MISSING SEAM: navigate_to('%s') was refused by the route table" % route_id,
		}
	if not app.has_method(&"current_route"):
		return {"ok": false, "note": NAV_MISSING_CURRENT_ROUTE}
	var now: Variant = app.call(&"current_route")
	if String(now) != String(route_id):
		return {
			"ok": false,
			"note":
			"MISSING SEAM: navigate_to('%s') left current_route() at '%s'" % [route_id, now],
		}
	return {"ok": true, "note": ""}


## The route the app reports as current, or "" when the seam is absent.
func current_route() -> Dictionary:
	if app == null or not app.has_method(&"current_route"):
		return {"route": "", "note": NAV_MISSING_CURRENT_ROUTE}
	return {"route": String(app.call(&"current_route")), "note": ""}


# --- Driving controls the way a player does ----------------------------------


## Press a real button. Returns false when the button is absent, is not a button, or
## is disabled — a disabled button is one no player can press, so treating it as
## success is how a dead control turns into a green test.
func press(node: Node, unique_name: String) -> bool:
	var button := _find_unique(node, unique_name) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


## Pick an entry in a dropdown, the way a player clicking the list does: the engine
## only emits `item_selected` on a real selection, never on a bare `select()`.
func choose(node: Node, unique_name: String, index: int) -> bool:
	var option := _find_unique(node, unique_name) as OptionButton
	if option == null or option.disabled:
		return false
	if index < 0 or index >= option.item_count:
		return false
	option.select(index)
	option.item_selected.emit(index)
	return true


## Press an action in a screen's `ActionSet` row. `ActionSet.request()` is that
## panel's own "as though its button were pressed" entry point and refuses an action
## the player could not press, so a disabled control cannot be mistaken for a working
## one.
func action(screen: Node, action_id: StringName) -> bool:
	var actions := _find_unique(screen, "%Actions") as ActionSet
	if actions == null:
		return false
	return actions.request(action_id)


## Select an inventory row the way a click does. `ItemList.select()` alone emits
## nothing, so a bare `select()` leaves the detail panel and action bar showing the
## previous row — which would let a test "equip" something it never actually picked.
func pick_row(node: Node, index: int) -> bool:
	var panel := _find_unique(node, "%InventoryPanel") as InventoryPanel
	if panel == null:
		return false
	var list := _find_unique(panel, "%ItemList") as ItemList
	if list == null or index < 0 or index >= list.item_count:
		return false
	list.select(index)
	list.item_selected.emit(index)
	return true


## The inventory row currently offering `def_id`, or -1. Rows are ordered stacks
## first, then instances, which is the order the workbench's `summary()` reports.
func row_of_def(node: Node, def_id: String) -> int:
	var panel := _find_unique(node, "%InventoryPanel") as InventoryPanel
	if panel == null:
		return -1
	var def_ids: Array = (panel.summary() as Dictionary)["row_def_ids"]
	return def_ids.find(def_id)


## The pressed button behind `unique_name`, for asserting what the player can see.
func button(node: Node, unique_name: String) -> Button:
	return _find_unique(node, unique_name) as Button


# --- Plumbing ----------------------------------------------------------------


## `%Name` resolution the way every panel in `src/ui/` does it, with a subtree search
## as the fallback. Unique names only resolve through the scene that declared them:
## the workbench resolves `%InventoryPanel` (declared in `item_workbench.tscn`) but
## not `%GenerateButton`, which is declared two levels down in `action_bar.tscn`.
## Falling back to a name search finds the same control the player sees.
## Press a reward row's own action control — "Pick up" on a claimable drop.
##
## The rows are instantiated from `loot_drop_row.tscn`, so no single owner holds them
## and `%DropAction` cannot be reached from the screen directly; this walks the list
## for the nth row and returns its control. Returns false when there is no such row or
## the control is disabled, so a dead control can never read as a successful pickup.
func press_drop_action(screen: Node, index: int = 0) -> bool:
	if screen == null:
		return false
	var list := _find_unique(screen, "%RewardList")
	if list == null:
		return false
	var rows := _all_named(list, DROP_ROW_NODE, 0)
	if index < 0 or index >= rows.size():
		return false
	var button := _find_unique(rows[index], DROP_ACTION_NODE) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


## Every descendant named `node_name`, in tree order.
##
## Depth-capped for the same reason the arch rule requires it of any recursive walk: a
## traversal with no cap is an unbounded loop the moment the tree contains a cycle, and
## the `while`-scanning rules cannot see a recursive call at all.
func _all_named(node: Node, node_name: String, depth: int) -> Array[Node]:
	var found: Array[Node] = []
	if depth > MAX_TREE_WALK:
		return found
	for child in node.get_children():
		if String(child.name) == node_name:
			found.append(child)
		found.append_array(_all_named(child, node_name, depth + 1))
	return found


func _find_unique(node: Node, unique_name: String) -> Node:
	if node == null:
		return null
	var direct := node.get_node_or_null(unique_name)
	if direct != null:
		return direct
	return _find_named(node, unique_name.trim_prefix("%"))


func _find_named(node: Node, node_name: String) -> Node:
	for child in node.get_children():
		if String(child.name) == node_name:
			return child
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null


func _find_child_of_class(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.is_class(type_name) or _script_class_is(child, type_name):
			return child
		var found := _find_child_of_class(child, type_name)
		if found != null:
			return found
	return null


## A node by unique name, falling back to a class-name search. A scene root reports
## its native class (`Control`), so a script's `class_name` has to be consulted too —
## but only after the resolution production itself uses has been tried.
func _resolve(node: Node, unique_name: String, type_name: String) -> Node:
	if node == null:
		return null
	var direct := node.get_node_or_null(unique_name)
	if direct != null:
		return direct
	return _find_child_of_class(node, type_name)


func _script_class_is(node: Node, type_name: String) -> bool:
	var script: Variant = node.get_script()
	return script != null and String((script as GDScript).get_global_name()) == type_name


func _descendant_from_scene(node: Node, scene_path: String) -> Control:
	for child in node.get_children():
		if child.scene_file_path == scene_path:
			return child as Control
		var found := _descendant_from_scene(child, scene_path)
		if found != null:
			return found
	return null
