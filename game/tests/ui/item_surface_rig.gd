class_name ItemSurfaceRig
extends RefCounted

## Shared rig for the per-surface item control-driven suites: one hero per module,
## the real screen scenes, and helpers that press the controls a player presses.
##
## Nothing here owns a rule and nothing calls an `act_*` on a screen. A suite that
## wants to prove a player can reach something drives the rendered control here and
## then reads the screen's `summary()` or the facade's own state.
##
## ## Why `%Name` resolution needs a subtree fallback
##
## Unique names only resolve through the scene that DECLARED them. The workbench
## scene declares `%InventoryPanel`, but `%UseButton` lives two levels down in
## `action_bar.tscn`, so `workbench.get_node_or_null("%UseButton")` answers null
## while the button the player presses is right there. `find_unique` therefore tries
## the production resolution first and then falls back to a depth-capped name walk,
## so a suite always reaches the control the player sees.
##
## ## Why every screen is recorded
##
## Screens are `Node`s: an unfreed one stays resident for the rest of the process,
## and the runner shares one process across every suite. `release()` is idempotent
## and safe after an aborted test, so a suite calls it from `teardown()`.

const WORKBENCH_SCENE := "res://src/ui/screens/item_workbench.tscn"
const CRAFTING_SCENE := "res://src/ui/screens/crafting_screen.tscn"
const FORGE_SCENE := "res://src/ui/screens/socket_forge.tscn"
const SET_BONUS_SCENE := "res://src/ui/screens/set_bonus_screen.tscn"
const CHARACTER_SCENE := "res://src/ui/screens/character_screen.tscn"
const STACK_SCENE := "res://src/ui/screens/screen_stack.tscn"
## Depth ceiling for the fallback name walk. The workbench nests its action buttons
## three levels down; this is slack, not a tuned number. A walk with no cap is an
## unbounded loop the moment the tree contains a cycle, and the `while`-scanning
## arch rule cannot see a recursive call at all.
const MAX_TREE_WALK := 12

## Every screen or stack this rig instantiated, so `release()` can free it.
var _born: Array[Node] = []


## The in-memory save/load pair the workbench's Save and Load controls need.
##
## A dictionary rather than a file, because the runner shares one process across
## every suite: a file left by one suite is the file the next suite's Load reads,
## and the hero a test sees would depend on which suite ran first. An inner class
## because a `Callable` needs an object with the methods on it.
class Vault:
	extends RefCounted
	var payload: Dictionary = {}

	func save(state: Dictionary) -> String:
		payload = state.duplicate(true)
		return ""

	func load_state() -> Dictionary:
		return payload.duplicate(true)


# --- Heroes. One per module, attached in the order the composition root uses. ---


## A delver with an inventory and the core resources the item verbs act on.
##
## Gear is applied as source-tagged FLAT modifiers rather than through a bag, so a
## fixture never depends on how items are filled or rolled. No cultivation path is
## enrolled, which leaves the authored grade gate open rather than pinning these
## suites to one realm's tier.
func hero(id: StringName = &"surface_hero", capacity: int = 24) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	ItemsApi.attach(actor, capacity)
	return actor


## The same delver with the socket program attached, for the forge surface.
func forge_hero() -> Actor:
	var actor := hero(&"forge_hero")
	SocketApi.attach(actor)
	return actor


## The same delver with the set program attached, for the set surface.
func set_hero() -> Actor:
	var actor := hero(&"set_hero", 48)
	SetBonusApi.attach(actor)
	return actor


# --- Screens. Instantiated, mounted, recorded, freed by `release()`. ---------


## The screen at `scene_path`, mounted under the real root so its controls are the
## ones a player would press, and recorded so `release()` can free it.
func screen(scene_path: String) -> Control:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var view := scene.instantiate() as Control
	if view == null:
		return null
	_born.append(view)
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	return view


## A real `ScreenStack` with the screen at `scene_path` pushed on it, which is how
## a surface is reached in the shipped program: the stack owns visibility, focus
## routing and input forwarding, and a screen pushed this way is reachable only
## through the stack the player navigates.
##
## The screen is pushed from its own scene rather than through `push_registered`,
## because the registry is per-process state the composition root fills and a
## suite must not depend on another session's registration having run.
func stack_with(scene_path: String) -> Dictionary:
	var packed := load(STACK_SCENE) as PackedScene
	if packed == null:
		return {}
	var host := packed.instantiate() as ScreenStack
	if host == null:
		return {}
	_born.append(host)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return {"stack": host, "screen": null}
	var view := host.push(scene.instantiate() as Control)
	return {"stack": host, "screen": view}


## Free every screen and stack this rig instantiated.
##
## Idempotent, so a suite can call it from `teardown()` and be safe even when a
## test aborted mid-way.
func release() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()


# --- Control drivers. Each one presses the control a player presses. ---------


## The control behind `unique_name`, or null.
##
## Production resolution first, then a depth-capped name walk, because a unique
## name declared two scenes down does not resolve from the screen root.
func find_unique(node: Node, unique_name: String) -> Node:
	if node == null:
		return null
	var direct := node.get_node_or_null(unique_name)
	if direct != null:
		return direct
	return _find_named(node, unique_name.trim_prefix("%"), 0)


## Press a real button. False when the control is absent, is not a button, or is
## disabled: a disabled button is one no player can press, so treating it as
## success is how a dead control turns into a green test.
func press(node: Node, unique_name: String) -> bool:
	var button := find_unique(node, unique_name) as Button
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


## The pressed button behind `unique_name`, for asserting what the player can see.
func button(node: Node, unique_name: String) -> Button:
	return find_unique(node, unique_name) as Button


## Pick an entry in a dropdown the way a click does: the engine only emits
## `item_selected` on a real selection, never on a bare `select()`.
func choose(node: Node, unique_name: String, index: int) -> bool:
	var option := find_unique(node, unique_name) as OptionButton
	if option == null or option.disabled:
		return false
	if index < 0 or index >= option.item_count:
		return false
	option.select(index)
	option.item_selected.emit(index)
	return true


## Select an inventory row the way a click does. `ItemList.select()` alone emits
## nothing, so a bare `select()` leaves the detail panel and action bar showing the
## previous row — which would let a suite "equip" something it never picked.
func pick_row(node: Node, index: int) -> bool:
	var list := find_unique(node, "%ItemList") as ItemList
	if list == null or index < 0 or index >= list.item_count:
		return false
	list.select(index)
	list.item_selected.emit(index)
	return true


## The inventory row currently offering `def_id`, or -1. Rows are ordered stacks
## first, then instances, which is the order the workbench's `summary()` reports.
func row_of_def(node: Node, def_id: String) -> int:
	var panel := find_unique(node, "%InventoryPanel") as InventoryPanel
	if panel == null:
		return -1
	var def_ids: Array = (panel.summary() as Dictionary)["row_def_ids"]
	return def_ids.find(def_id)


## Press one of the screen's own action buttons in an `ActionSet` row.
##
## `ActionSet` builds one `Button` per declared action and names it after the id,
## so `create_slot` is `CreateSlotButton`. Asked of the tree rather than through
## `ActionSet.request()`, because `request()` is the panel's own stand-in for a
## press and the claim under test is that the RENDERED button reaches the handler.
func press_action(node: Node, action_id: StringName) -> bool:
	var actions := find_unique(node, "%Actions") as ActionSet
	if actions == null:
		return false
	var name := "%sButton" % String(action_id).to_pascal_case()
	return press(actions, name)


## An action event rather than a key event, so a suite drives a surface's own
## action vocabulary instead of depending on the project's key bindings.
func press_action_key(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


## Every descendant of `node` named `node_name`, in tree order, depth-capped.
func all_named(node: Node, node_name: String) -> Array[Node]:
	return _all_named(node, node_name, 0)


# --- Fixtures the surfaces need ----------------------------------------------


## Stock `quantity` of an AUTHORED definition, so the screen has a real
## `display_name` to read. A fabricated `ItemDef.new()` carries an empty name and
## would make a suite pass for the wrong reason.
func stock_authored(actor: Actor, def_id: StringName, quantity: int = 1) -> bool:
	var def := Crafting.resolve(def_id)
	if def == null:
		return false
	return ItemsApi.inventory(actor).add(def, quantity) == 0


## Mint a realized instance of an authored definition and acquire it, the
## acquisition a claim performs: `generate` routes a non-stackable def through the
## same `add_instance` a loot payout uses.
func acquire(actor: Actor, def_id: StringName, seed_value: int) -> ItemInstance:
	var def := Crafting.resolve(def_id)
	if def == null:
		return null
	return ItemsApi.generate(actor, def, seed_value)


func _find_named(node: Node, node_name: String, depth: int) -> Node:
	if node == null or depth > MAX_TREE_WALK:
		return null
	for child in node.get_children():
		if String(child.name) == node_name:
			return child
		var found := _find_named(child, node_name, depth + 1)
		if found != null:
			return found
	return null


func _all_named(node: Node, node_name: String, depth: int) -> Array[Node]:
	var found: Array[Node] = []
	if node == null or depth > MAX_TREE_WALK:
		return found
	for child in node.get_children():
		if String(child.name) == node_name:
			found.append(child)
		found.append_array(_all_named(child, node_name, depth + 1))
	return found
