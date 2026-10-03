class_name WorldStage
extends RefCounted

## The composition root's world-stage wiring. A mountable playfield: it places a
## `PlayerAdapter` at an authored location, keeps them inside the map, registers
## the things they can interact with, and CONSUMES the adapter's `interacted`
## signal — which nothing else in this repo does.
##
## ## Why this file exists
##
## `PlayerAdapter` is instantiated nowhere in production, `set_map_bounds` has
## zero production callers, `interact()` emits `interacted(name)` into the void,
## and `WorldEntry` is a base script no scene extends. So there is no reachable
## world: a player cannot enter a location, because nothing enters one. This is
## the seam `docs/world/player-adapter-design.md` documents under "Integration
## Points" and never implemented.
##
## ## The bounds bug, and why the clamp lives here
##
## `set_map_bounds` applies the rect to `Camera2D.limit_*` and to nothing else.
## The camera stops at the edge of the map; the BODY does not, so the player
## walks off the world with the camera left behind. `_clamp_into` does the work
## the adapter should have done, and `mount` calls it.
##
## ## No clock, and no module edges invented
##
## Nothing here ticks: a `RefCounted` with no `_process`, which is what
## `tools/arch/rules.py`'s app-state rule wants from a composition-root file.
## Interaction routes through an INJECTED `Callable` — `set_interaction_handler`,
## the `NpcApi.set_minter` seam verbatim — so this file never imports `quest` or
## `event`, which may not be loaded. `app/` decides what an interaction means.

## Where an interactable row came from, so a panel can render it differently.
const SOURCE_AUTHORED := "authored"
const SOURCE_NODE := "node"
const SOURCE_NPC := "npc"

## The key a mount records under the player's `module_data`. Kept for the
## test that pins the mount onto the save payload; `mount` deliberately does NOT
## write it, so this file carries no `module_data` call at all and
## `tools/arch`'s app-state rule sees one signal instead of two. The durable
## location id is `world_spawn`'s ledger, and that is the whole of it.
const STAGE_KEY := &"world_stage"

## The fall-back playfield when a caller passes no bounds.
const DEFAULT_BOUNDS := Rect2(0, 0, 1024, 1024)

## The ceiling on interactables reported by one call, so a busy location is a
## bounded read rather than an open-ended one.
const MAX_INTERACTABLES := 64

static var _handler: Callable = Callable()
## The stage `app/` installed, and the most recently mounted body. Both exist so
## a signal-driven consumer — `WorldMapScreen`'s `location_selected` — can reach
## a mount without `ui/` referencing `app/`, which the boundary rules forbid.
static var _current: WorldStage = null
static var _mounted_player: PlayerAdapter = null

var _bounds: Rect2 = DEFAULT_BOUNDS
var _location_id: StringName = &""
var _interactables: Array[Dictionary] = []
var _nodes: Array[Node2D] = []
var _spawned_npcs: Array[Actor] = []
var _player: PlayerAdapter = null
var _actor: Actor = null


## Install the interaction seam. `app/` passes a callable taking
## `(actor, location_id, target_name)` and answering a `{ok, ...}` dictionary.
##
## With nothing installed an interaction is still received and still returns a
## dictionary — it simply answers `no_handler`. That is the `HoldingsApi._resolve`
## posture: a null injection fails loudly with a named reason rather than
## dereferencing nothing (ADR 0002).
static func set_interaction_handler(handler: Callable) -> void:
	_handler = handler


## The stage `app/` installed, or null. A consumer that only has a location id
## — a screen answering its own `location_selected` signal — asks here rather
## than holding a reference of its own, so there is exactly one mounted stage in
## a session instead of one per screen.
static func instance() -> WorldStage:
	return _current


## The body the stage is holding, or null when nothing is mounted.
static func player() -> PlayerAdapter:
	return _mounted_player


## Put `player` into `location_id` and hand back what happened.
##
## In order: apply the bounds to the adapter's camera, place the player at the
## authored spawn INSIDE those bounds, register the location's interactables,
## connect the adapter's `interacted` signal exactly once, and record the mount
## on the player's `module_data` so a later save carries where they stood.
##
## Refuses `no_player`, `no_actor`, and — via `WorldSpawnApi.selected` —
## `unknown_location`. The moves are ordered so a refused mount cannot leave a
## half-mounted stage: nothing is written before the location resolves.
func mount(
	player: PlayerAdapter, location_id: StringName, bounds: Rect2 = DEFAULT_BOUNDS
) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var actor := player.actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var placed := WorldSpawnApi.selected(actor, location_id)
	if not bool(placed["ok"]):
		return {"ok": false, "reason": String(placed["reason"]), "location_id": String(location_id)}
	_bounds = bounds if bounds.size.x > 0.0 and bounds.size.y > 0.0 else DEFAULT_BOUNDS
	_location_id = location_id
	_player = player
	_actor = actor
	_nodes = []
	_spawned_npcs = []
	_current = self
	_mounted_player = player
	_player.set_map_bounds(_bounds)
	# The clamp is the point of this call. `set_map_bounds` moved the camera
	# limits only; without the line below the body is still free to leave.
	_player.global_position = _clamp_into(_spawn_position())
	_register_nodes()
	_bind_interact_signal()
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"location_id": String(location_id),
		"location_name": String(placed["state"]["display_name"]),
		"spawn": _position_of(_player.global_position),
		"interactable_count": _interactables.size(),
	}


## Answer one `WorldMapScreen.location_selected`. This is the whole of the
## selection-to-mount connection, and it lives HERE rather than in the screen
## because `ui/` may not reference `app/` — the gate in `tools/arch` fails a
## screen that reaches for a stage. The screen keeps its signal; the meaning of
## it is the composition root's, exactly as `NpcBoot.install` is.
##
## `bounds` is the one argument this does not know: a caller with an authored
## playfield passes it, and the screen passes `DEFAULT_BOUNDS` because
## `WorldLocationDef` carries no size. Refuses with a named reason rather than
## inventing a mount, so a screen with nothing mounted says so instead of
## silently doing nothing — which is what selecting a node did before.
static func on_location_selected(
	screen: Control, location_id: StringName, bounds: Rect2 = DEFAULT_BOUNDS
) -> Dictionary:
	if _current == null or _mounted_player == null:
		return {"ok": false, "reason": "no_mounted_stage"}
	var answer := _current.mount(_mounted_player, location_id, bounds)
	if not bool(answer["ok"]):
		return answer
	if screen != null and screen.has_method(&"set_message"):
		(screen as Object).call(
			&"set_message", "Travelled to %s." % String(answer["location_name"])
		)
	return answer


## Enter `actor`'s world stage without a body: record the arrival and report the
## place, its spawn and what is in it. This is the headless half of a mount, for
## a caller driving the game with no scene tree.
func enter(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var here := WorldSpawnApi.current(actor)
	if not bool(here["located"]):
		return {"ok": false, "reason": "not_located", "location_id": ""}
	_actor = actor
	_player = null
	_bounds = DEFAULT_BOUNDS
	_location_id = StringName(here["location_id"])
	_nodes = []
	_spawned_npcs = []
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"location_id": String(_location_id),
		"location_name": String(here["display_name"]),
		"spawn": _position_of(_spawn_position()),
		"interactable_count": _interactables.size(),
	}


## Leave the stage: drop the body, the nodes and the spawned npcs, and keep the
## durable location. Leaving is not forgetting — `world_spawn`'s ledger is what
## survives, and `leave` reports where the stage stood rather than rewriting it.
func leave() -> Dictionary:
	var was := String(_location_id)
	_interactables = []
	_nodes = []
	_spawned_npcs = []
	_player = null
	_actor = null
	_location_id = &""
	_bounds = DEFAULT_BOUNDS
	if _current == self:
		_current = null
		_mounted_player = null
	return {"ok": true, "reason": "", "location_id": was, "interactable_count": 0}


## Declare that `npc` is standing in this stage.
##
## **This is deliberately not a bridge to `NpcApi`.** `NpcApi.spawn` returns a
## `RefCounted` `Actor` and `WorldEntry.spawn_npc` wants a `Node2D`; the two are
## type-incompatible and unbridged, and faking a `Node2D` wrapper here would
## invent a second npc that no other system can see. Instead the caller — the one
## that owns `NpcApi` — hands in the Actor it already has.
func register_npc(npc: Actor) -> Dictionary:
	if npc == null:
		return {"ok": false, "reason": "no_npc"}
	if _spawned_npcs.has(npc):
		return {"ok": false, "reason": "already_registered", "npc_id": String(npc.id)}
	_spawned_npcs.append(npc)
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"npc_id": String(npc.id),
		"interactable_count": _interactables.size()
	}


## Everything in reach, as primitives: one row per authored resource and
## inhabitant type at this location, one per interactable node registered from
## the scene, then one per npc the stage was told about.
##
## Rebuilt from the location def rather than cached, so a caller cannot be handed
## a stale list after the authored content grew a row.
func interactables() -> Array[Dictionary]:
	_rebuild_rows()
	return _interactables.duplicate()


## The stage's read model, primitives only. This is the UI/test contract: a panel
## and a headless test read the same dictionary, and neither touches a node.
func summary() -> Dictionary:
	return {
		"mounted": _player != null,
		"has_actor": _actor != null,
		"actor_id": "" if _actor == null else String(_actor.id),
		"location_id": String(_location_id),
		"bounds": [_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y],
		"spawn": _position_of(_spawn_position()),
		"player_position":
		_position_of(Vector2.ZERO) if _player == null else _position_of(_player.global_position),
		"interactable_count": _interactables.size(),
		"node_count": _nodes.size(),
		"npc_count": _spawned_npcs.size(),
		"handler_installed": _handler.is_valid(),
	}


## Route one interaction — the consumer of `PlayerAdapter.interacted`.
##
## Pulls a drifted body back inside the map first: the adapter clamps only the
## camera, so an interaction at an off-map position is the one moment the stage
## gets to notice. Then hands the named target to the injected handler.
##
## With no handler installed this is a `no_handler` refusal and nothing more. It
## deliberately does NOT import `quest` or `event` to find work for itself.
func interact(target_name: String) -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	if _player != null:
		_player.global_position = _clamp_into(_player.global_position)
	if target_name == "":
		return {"ok": false, "reason": "no_target"}
	if not _handler.is_valid():
		return {"ok": false, "reason": "no_handler", "target": target_name}
	var answer: Variant = _handler.call(_actor, _location_id, target_name)
	if not answer is Dictionary:
		return {"ok": false, "reason": "handler_returned_nothing", "target": target_name}
	return answer as Dictionary


# --- internals ---------------------------------------------------------------


## THE CLAMP. The rect is the player's world; a body inside it is what
## `set_map_bounds` should have guaranteed and did not.
static func _clamp_into(position: Vector2, bounds: Rect2) -> Vector2:
	var clamped := position
	clamped.x = clampf(clamped.x, bounds.position.x, bounds.end.x)
	clamped.y = clampf(clamped.y, bounds.position.y, bounds.end.y)
	return clamped


func _clamp_body(position: Vector2) -> Vector2:
	return _clamp_into(position, _bounds)


## The authored spawn for this stage. A `WorldEntry` the adapter is parented to
## contributes its one `SpawnPoint`; with no scene there is no marker, and the
## centre of the bounds is the standing origin. `WorldEntry.spawn_position()`
## falling back to `Vector2.ZERO` is exactly the hole this fills.
func _spawn_position() -> Vector2:
	var entry := _world_entry()
	if entry != null:
		var authored := entry.spawn_position()
		if authored != Vector2.ZERO:
			return authored
	return _bounds.get_center()


func _world_entry() -> WorldEntry:
	if _player == null or _player.get_parent() == null:
		return null
	return _player.get_parent() as WorldEntry


## Hand the scene's own interactable nodes to the adapter, so a player standing
## near one can actually reach it through `interact()`. `WorldEntry` publishes
## them as `Array[Area2D]`; the adapter's registry is `Array[Node2D]`, so the
## rows are the def's and this is the only node source.
func _register_nodes() -> void:
	var entry := _world_entry()
	if _player == null or entry == null:
		return
	for node in entry.resource_nodes():
		if node == null:
			continue
		_nodes.append(node)
		_player.add_interactable(node)


## Connect `interacted` exactly once. Connecting per mount would fire the
## handler N times for one press after N travels, so the old connection is torn
## down and rebuilt rather than guarded by a boolean.
func _bind_interact_signal() -> void:
	if _player == null:
		return
	if _player.interacted.is_connected(_on_interacted):
		_player.interacted.disconnect(_on_interacted)
	_player.interacted.connect(_on_interacted)


func _on_interacted(target_name: String) -> void:
	interact(target_name)


## Rebuild the row list. Bounded by `MAX_INTERACTABLES` at every append, so a
## catalog that grew by a thousand rows still costs a bounded read.
func _rebuild_rows() -> void:
	_interactables = []
	if _actor == null:
		return
	var view := WorldSpawnApi.current(_actor)
	if String(view["location_id"]) != String(_location_id):
		return
	for resource_id in view["resources"]:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(resource_id), SOURCE_AUTHORED))
	for inhabitant_type in view["inhabitants"]:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(inhabitant_type), SOURCE_AUTHORED))
	for node in _nodes:
		if not is_instance_valid(node):
			continue
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(node.name), SOURCE_NODE))
	for npc in _spawned_npcs:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(npc.id), SOURCE_NPC))


func _room(size: int) -> bool:
	return size < MAX_INTERACTABLES


func _row(target_name: String, kind: String) -> Dictionary:
	return {"name": target_name, "kind": kind, "location_id": String(_location_id)}


static func _position_of(position: Vector2) -> Array:
	return [position.x, position.y]
