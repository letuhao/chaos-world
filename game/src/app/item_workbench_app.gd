class_name ItemWorkbenchApp
extends Control

## Composition root for the playable item workbench (ADR 0002, 0027, 0033).
##
## The only place that knows concrete module types and the attach order. It
## builds one actor, mounts the UI screen, and injects file-backed persistence —
## the UI program itself never names a module type or touches the filesystem.

const WORKBENCH_SCENE := "res://scenes/item_workbench/item_workbench.tscn"
const STACK_SCENE := "res://src/ui/screens/screen_stack.tscn"
const SOCKET_SCREEN_SCENE := "res://src/ui/screens/socket_forge.tscn"
const SAVE_PATH := "user://item_workbench_state.json"
const LOOT_SCREEN_SCENE := "res://src/ui/screens/loot_encounter.tscn"
## Damage one loot-screen strike deals. Boss vitality is authored content; the
## composition root decides how much of it a strike spends.
const LOOT_STRIKE_DAMAGE := 25.0
## Enough real content to exercise every activation channel on first run.
const STARTER_ITEMS: Array[StringName] = [
	&"armor_iron_helm",
	&"accessory_iron_bangle",
	&"armor_iron_ore",
]

var _actor: Actor = null
var _workbench: Control = null
var _socket_screen: Control = null
var _loot_screen: Control = null
var _stack: Control = null
var _socket_request: int = 0


func _ready() -> void:
	_workbench = get_node_or_null("%Workbench") as Control
	if _workbench == null:
		push_error("ItemWorkbenchApp: no workbench in the scene")
		return
	_actor = _build_actor()
	# The socket ledger lives on the actor, so the subsystem is attached here, in
	# the one place that knows concrete module types (ADR 0027).
	SocketApi.attach(_actor)
	# The loot lifecycle state lives on the actor too, so it is attached here, in
	# the one place that knows concrete module types.
	LootApi.attach(_actor)
	_workbench.call("setup", _actor, Callable(self, "_save_state"), Callable(self, "_load_state"))
	_mount_stack()


## Put every playable surface behind one screen stack, so the socket forge and the
## loot encounter are reachable from the running app instead of existing only as
## headless-callable scenes. The workbench stays the root; the feature screens are
## pushed over it.
func _mount_stack() -> void:
	var scene: PackedScene = load(STACK_SCENE)
	if scene == null:
		push_error("ItemWorkbenchApp: no screen stack at %s" % STACK_SCENE)
		return
	_stack = scene.instantiate() as Control
	add_child(_stack)
	mount_socket_screen(_stack)
	mount_loot_screen(_stack)
	# The stack shows exactly one screen, so hand focus back to the workbench.
	_stack.call("pop")
	_stack.call("pop_to_root")


## Push a screen the workbench opens on request, so every feature surface has a
## reachable entry point rather than being mounted and immediately covered.
func open_screen(scene_path: String) -> Control:
	if _stack == null:
		return null
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("ItemWorkbenchApp: no screen at %s" % scene_path)
		return null
	return _stack.call("push", scene.instantiate()) as Control


## A fresh hero with the core resource pools, the items subsystem attached, and
## a starting kit drawn from the shipped content tree.
func _build_actor() -> Actor:
	var actor := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	ItemsApi.attach(actor)
	var inventory := ItemsApi.inventory(actor)
	for item_id in STARTER_ITEMS:
		var def := _resolve(item_id)
		if def != null:
			inventory.add(def, 1)
	return actor


## Look a definition up by id through the items module's single resolver, so the
## app uses the same lookup as inventory, crafting, the generator and loot.
## Returns null rather than guessing, so a missing starter item never blocks the
## app.
func _resolve(item_id: StringName) -> ItemDef:
	return Crafting.resolve(item_id)


func _save_state(payload: Dictionary) -> String:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return "cannot open %s" % SAVE_PATH
	file.store_string(JSON.stringify(payload))
	file.close()
	return ""


func _load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Mount the socket forge on `stack` and hand it the socket program's read model.
## The screen is a pure view: it never names the socket module, so this is where
## the two are wired together and where every socket action is executed.
func mount_socket_screen(stack: Control) -> Control:
	if stack == null or _actor == null:
		return null
	var scene: PackedScene = load(SOCKET_SCREEN_SCENE)
	if scene == null:
		push_error("ItemWorkbenchApp: socket screen missing at %s" % SOCKET_SCREEN_SCENE)
		return null
	var screen := scene.instantiate() as Control
	screen.call("setup", _actor)
	screen.connect(&"socket_action_requested", Callable(self, "_on_socket_action"))
	_socket_screen = screen
	stack.call("push", screen)
	refresh_socket_screen()
	return screen


## Re-read the socket program's read model for the host the screen is looking at,
## and hand it in. The host id rides the view, so one read serves every widget.
func refresh_socket_screen() -> void:
	if _socket_screen == null:
		return
	_socket_screen.call("bind_view", SocketApi.panel_state(_actor, _socket_host_id()))


## Run one screen intent against the socket program, then repaint from the result.
## A refusal is reported through the message line, never swallowed.
func _on_socket_action(action: StringName, args: Dictionary) -> void:
	var result := _run_socket_action(action, args)
	_socket_screen.call("set_message", _socket_outcome(action, result), _socket_tone(result))
	refresh_socket_screen()


func _run_socket_action(action: StringName, args: Dictionary) -> Dictionary:
	var host := StringName(String(args.get("host_id", _socket_host_id())))
	var reagent := StringName(String(args.get("reagent_id", "")))
	var index := int(args.get("index", 0))
	match action:
		&"create_slot":
			return SocketApi.create_slot(_actor, host, reagent)
		&"impute_slot":
			return SocketApi.impute_slot(_actor, host, index, reagent)
		&"insert_socket":
			return SocketApi.insert_socket(
				_actor, host, index, StringName(String(args.get("gem_instance_id", "")))
			)
		&"extract_socket":
			return SocketApi.extract_socket(_actor, host, index)
		_:
			return SocketApi.commit_enchantment(
				_actor, host, reagent, _next_socket_request_id(), Time.get_ticks_usec()
			)


func _socket_host_id() -> String:
	if _socket_screen != null:
		return String(_socket_screen.call("selected_host"))
	var parent: Dictionary = SocketApi.panel_state(_actor).get("parent", {})
	return String(parent.get("instance_id", ""))


func _next_socket_request_id() -> StringName:
	_socket_request += 1
	return StringName("socket_request_%d" % _socket_request)


func _socket_outcome(action: StringName, result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return "%s committed" % action
	return "Rejected: %s" % result.get("reason", "")


func _socket_tone(result: Dictionary) -> StringName:
	return &"ok" if bool(result.get("ok", false)) else &"error"


## Mount the loot surface on `stack` and hand it the loot program's read model.
## The screen is a pure view of a [LootBridge] of plain callables, so this is the
## only place the two are wired together and the only place a loot action is run.
func mount_loot_screen(stack: Control) -> Control:
	if stack == null or _actor == null:
		return null
	if _loot_screen != null:
		refresh_loot_screen()
		return _loot_screen
	var scene: PackedScene = load(LOOT_SCREEN_SCENE)
	if scene == null:
		push_error("ItemWorkbenchApp: loot screen missing at %s" % LOOT_SCREEN_SCENE)
		return null
	var screen := scene.instantiate() as Control
	screen.call("setup", _actor)
	screen.call("bind_bridge", loot_bridge())
	screen.call("set_strike_damage", LOOT_STRIKE_DAMAGE)
	_loot_screen = screen
	stack.call("push", screen)
	return screen


## The loot program's public surface, as plain callables. The UI program may only
## reach a gameplay module through that module's facade, so the bridge keeps every
## module type on this side of the boundary.
func loot_bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.strike_damage = LOOT_STRIKE_DAMAGE
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.strike = Callable(LootApi, "strike")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


## Re-read the loot program's read model and hand it in. The screen repaints from
## it, so a refusal can never leave the view out of step with the world.
func refresh_loot_screen() -> void:
	if _loot_screen == null:
		return
	_loot_screen.call("bind_bridge", loot_bridge())
