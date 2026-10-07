class_name WorldmapScene
extends Node2D

## The runtime view of one spatial node: generated chunks as sprites, a grid
## stepper for a player, portals as data, and a debug read model. Everything
## builds synchronously in `open()` — no tree, no frame — so headless runs
## verify the same scene a player walks.
##
## ## Data moves, pictures follow
##
## Movement reads `WorldChunk.standable`, never a sprite or a collider: there
## are no physics bodies here at all. A collider nobody queries is decoration,
## and the POC already proved the data contract in a browser. What the scene
## adds over the POC is Godot-native rendering (y-sorted sprites from real
## catalog art), chunk streaming ranges, portals between nodes, and
## unload/reload that keeps mutations.
##
## ## Coordinates, stated once
##
## Player and portal cells are MAP cells (chunk grid times chunk size, local
## to the node — unrelated worlds never share a plane). Chunk `(cx, cy)` is
## the floor division of a map cell by the node's chunk size; chunk-local is
## the positive remainder. Sizes are per-node, so two nodes may disagree.

const CELL_PX := 128

## Region holders are keyed apart from chunk holders so the streaming sweep
## never frees a merged region as if it were one stale chunk.
const REGION_PREFIX := "region:"

var _graph: WorldmapGraph = null
var _node_id: String = ""
var _node_configs: Dictionary = {}
var _config: Dictionary = {}
var _size: int = 16
var _seed: int = 0
var _streamer: WorldmapStreamer = null
var _player_cell := Vector2i.ZERO
var _player: Node2D = null
var _holders: Dictionary = {}
var _textures: Dictionary = {}
var _debug_borders := false
## Return cells for domain descents, outermost first. Non-empty means the
## player stands inside a domain node: the one flag both `step` and
## `destroy_at` read, so there is no second "am I inside" to disagree.
var _returns: Array = []


## Open a node: build the streamer, generate the entry chunk, render the
## scene range around it, and stand the player at the node's entry cell.
## Returns `{ok, reason}` naming the first failure; a half-opened node is
## reported, never shown.
func open(graph: WorldmapGraph, node_id: String, node_configs: Dictionary) -> Dictionary:
	_graph = graph
	_node_id = node_id
	_node_configs = (node_configs as Dictionary).duplicate(true)
	if not _node_configs.has(node_id):
		return {"ok": false, "reason": "unknown_node", "node": node_id}
	_config = (_node_configs[node_id] as Dictionary).duplicate(true)
	_size = maxi(2, int(_config.get("chunk_size", 16)))
	_seed = int(_config.get("seed", 0))
	_streamer = WorldmapStreamer.new()
	_streamer.configure(WorldmapApi.default_generator(), _config)
	y_sort_enabled = true
	var entry := Vector2i(0, int(_config.get("entry_row", 1)))
	_player_cell = entry
	_player = Node2D.new()
	_player.name = "WorldmapPlayer"
	var marker := ColorRect.new()
	marker.color = Color(0.97, 0.91, 0.78)
	marker.size = Vector2(32, 32)
	marker.position = Vector2(-16, -16)
	_player.add_child(marker)
	add_child(_player)
	_place_player()
	refresh_around(_chunk_of(_player_cell))
	return {"ok": true, "reason": "", "node": _node_id}


## The streamer behind this scene, for tests and debug reads.
func streamer() -> WorldmapStreamer:
	return _streamer


## The player's map cell.
func player_cell() -> Vector2i:
	return _player_cell


## Step one cell. Moves only onto standable ground; a portal edge on the
## destination cell travels instead of staying. Returns `{moved, traveled}`
## plus `reason` naming a refused gate (empty otherwise). Inside a domain
## node the feet stay still: rooms are walked on the domain's own surface,
## so a step here refuses `inside_domain` rather than striding through walls
## the scene cannot see.
func step(dx: int, dy: int) -> Dictionary:
	if not _returns.is_empty():
		return {"moved": false, "traveled": false, "reason": "inside_domain"}
	var target := _player_cell + Vector2i(dx, dy)
	var cc := _chunk_coords(target)
	_streamer.chunk_data(_node_id, cc.x, cc.y, _size, _seed)
	if not _standable(target):
		return {"moved": false, "traveled": false, "reason": ""}
	_player_cell = target
	refresh_around(_chunk_of(target))
	_place_player()
	# Predict along the step just taken: the chunks ahead generate now, as
	# data, so arriving reads cache instead of generating underfoot.
	_streamer.preload_toward(dx, dy, 2)
	var edge := _portal_at(target)
	if not edge.is_empty():
		# Spelled out rather than `merged()`: merge keeps the receiver's
		# keys and only adds the crossing's, so the report would always read
		# `traveled: false` on top of a crossing that happened.
		var sailed := _travel(edge)
		return {
			"moved": true,
			"traveled": bool(sailed.get("traveled", false)),
			"reason": String(sailed.get("reason", "")),
		}
	return {"moved": true, "traveled": false, "reason": ""}


## Destroy whatever the given map cell masks: records a mutation, so leaving
## and returning keeps it. Returns how many cells were freed. Inside a domain
## node there is no chunk to break: rooms keep their own state on the run.
func destroy_at(cell: Vector2i) -> Dictionary:
	if not _returns.is_empty():
		return {"ok": false, "freed": 0, "reason": "inside_domain"}
	var cc := _chunk_coords(cell)
	var local := _local_of(cell)
	var chunk := _streamer.chunk_data(_node_id, cc.x, cc.y, _size, _seed)
	var freed := 0
	for prop in chunk.props:
		var placement := prop as Dictionary
		var base := placement.get("cell", Vector2i.ZERO) as Vector2i
		var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
		if (
			local.x >= base.x
			and local.y >= base.y
			and local.x < base.x + fp.x
			and local.y < base.y + fp.y
		):
			# Only cells this prop actually sealed count as freed: its canopy
			# cells were walkable before and after, so counting them would
			# credit the axe for ground it never blocked.
			for dy in fp.y:
				for dx in fp.x:
					var wx: int = base.x + dx
					var wy: int = base.y + dy
					if not chunk.standable(wx, wy):
						_streamer.mutate(_node_id, cc.x, cc.y, wx, wy, false)
						freed += 1
	refresh_chunk(_chunk_id_of(cell))
	return {"ok": freed > 0, "freed": freed}


## Render every chunk in the scene range, drop holders outside it, and hide
## holders outside the render range. Data range is wider and stays cached:
## unloading forgets nodes, never knowledge. A hidden holder costs nodes but
## no pixels: the render range is what the eye gets, the scene range is what
## the tree gets, and the two stop pretending to be one thing.
func refresh_around(focus: Vector2i) -> void:
	_streamer.set_focus(focus)
	var want := {}
	for offset in _streamer.neighborhood(focus.x, focus.y, _streamer.scene_radius):
		var id := "%s:%d,%d" % [_node_id, offset.x, offset.y]
		want[id] = Vector2i(offset.x, offset.y)
		if not _holders.has(id):
			_render_chunk(offset.x, offset.y)
	for id in _holders.keys():
		if String(id).begins_with(REGION_PREFIX):
			continue
		if not want.has(id):
			(_holders[id] as Node).free()
			_holders.erase(id)
			_streamer.unload(id)
			continue
		var cc := _coords_of_id(String(id))
		var near := maxi(abs(cc.x - focus.x), abs(cc.y - focus.y))
		(_holders[id] as Node2D).visible = near <= _streamer.render_radius
	queue_redraw()


## Re-render one chunk (after mutations). No-op when it was never loaded.
func refresh_chunk(chunk_id: String) -> void:
	if not _holders.has(chunk_id):
		return
	var holder := _holders[chunk_id] as Node
	var cc := _coords_of_id(chunk_id)
	holder.free()
	_holders.erase(chunk_id)
	_render_chunk(cc.x, cc.y)
	queue_redraw()


## Render a merged region: the listed chunks under ONE holder, so several
## neighbors behave as one runtime region for streaming or simulation.
func render_region(region_id: String, coords: Array) -> Dictionary:
	var key := REGION_PREFIX + region_id
	if _holders.has(key):
		return {"ok": false, "reason": "duplicate_region"}
	var holder := Node2D.new()
	holder.name = "Region_%s" % region_id
	add_child(holder)
	for coord in coords:
		var cc := coord as Vector2i
		_render_chunk_into(holder, cc.x, cc.y)
		_streamer.mark_loaded("%s:%d,%d" % [_node_id, cc.x, cc.y])
	_holders[key] = holder
	queue_redraw()
	return {"ok": true, "reason": "", "chunks": coords.size()}


## Primitives only: player, loaded holders with seeds and mutation counts,
## streamer state, this node's travel edges, generation passes, POIs, and the
## domain descent (empty above ground). The descent block is the scene's own
## record — template, return node and cell — never the run, which lives on
## the actor.
func debug_summary() -> Dictionary:
	var holders: Array = []
	for id in _holders.keys():
		holders.append(String(id))
	holders.sort()
	var domain := {}
	if not _returns.is_empty():
		var back := _returns[_returns.size() - 1] as Dictionary
		var cell := back.get("cell", Vector2i.ZERO) as Vector2i
		domain = {
			"template": String(_config.get("domain_template", "")),
			"return_node": String(back.get("node", "")),
			"return_cell": [cell.x, cell.y],
		}
	var passes: Array = []
	for layer in WorldmapApi.default_generator().layers():
		passes.append(String(layer))
	return {
		"node": _node_id,
		"player_cell": [_player_cell.x, _player_cell.y],
		"chunk_size": _size,
		"seed": _seed,
		"holders": holders,
		"streamer": _streamer.summary() if _streamer != null else {},
		"edges": _graph.edges_from(_node_id) if _graph != null else [],
		"passes": passes,
		"pois": _loaded_pois(),
		"debug_borders": _debug_borders,
		"domain": domain,
	}


## POIs of every loaded chunk in map cells, primitives only. Reads the data
## cache behind loaded holders — generating nothing, since a rendered chunk
## is always cached.
func _loaded_pois() -> Array:
	var out: Array = []
	if _streamer == null:
		return out
	for id in _holders.keys():
		if String(id).begins_with(REGION_PREFIX):
			continue
		var cc := _coords_of_id(String(id))
		var chunk := _streamer.chunk_data(_node_id, cc.x, cc.y, _size, _seed)
		var meta := chunk.layers.get("metadata", {}) as Dictionary
		for poi in meta.get("pois", []) as Array:
			var row := (poi as Dictionary).duplicate()
			var cell := row.get("cell", [0, 0]) as Array
			row["cell"] = [cc.x * _size + int(cell[0]), cc.y * _size + int(cell[1])]
			row["chunk"] = String(id)
			out.append(row)
	return out


## Show or hide the debug painting (chunk boundaries + ids). Answers what
## changed so a driver can assert the toggle rather than pixels.
func set_debug(enabled: bool) -> Dictionary:
	_debug_borders = enabled
	queue_redraw()
	return {"ok": true, "reason": "", "debug": _debug_borders}


func _draw() -> void:
	if not _debug_borders:
		return
	var font := ThemeDB.fallback_font
	for id in _holders.keys():
		if String(id).begins_with(REGION_PREFIX):
			continue
		var cc := _coords_of_id(String(id))
		var origin := Vector2(cc.x * _size, cc.y * _size) * CELL_PX
		draw_rect(
			Rect2(origin, Vector2(_size, _size) * CELL_PX), Color(0.55, 0.84, 0.76, 0.8), false, 3.0
		)
		draw_string(
			font,
			origin + Vector2(8, 28),
			String(id),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			22,
			Color(0.55, 0.84, 0.76, 0.9)
		)


func _unhandled_input(event: InputEvent) -> void:
	var dir := Vector2i.ZERO
	if event.is_action_pressed("move_up"):
		dir = Vector2i(0, -1)
	elif event.is_action_pressed("move_down"):
		dir = Vector2i(0, 1)
	elif event.is_action_pressed("move_left"):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("move_right"):
		dir = Vector2i(1, 0)
	if dir != Vector2i.ZERO:
		step(dir.x, dir.y)
		get_viewport().set_input_as_handled()


## Whether a unit can stand on a map cell. Public so tests and probes ask
## the same question the stepper asks, instead of reaching into privates.
func is_standable(cell: Vector2i) -> bool:
	return _standable(cell)


func _standable(cell: Vector2i) -> bool:
	var cc := _chunk_coords(cell)
	var local := _local_of(cell)
	var chunk := _streamer.chunk_data(_node_id, cc.x, cc.y, _size, _seed)
	return chunk.standable(local.x, local.y)


func _portal_at(cell: Vector2i) -> Dictionary:
	if _graph == null:
		return {}
	for edge in _graph.edges_from(_node_id):
		var from_cell := edge.get("from_cell", Vector2i(-1, -1)) as Vector2i
		if from_cell == cell:
			return edge
	return {}


## Travel an edge: switch node, stand on its far cell, stream around it.
## Works for a door in the same world, a portal to another universe, and a
## descent into a nested domain — the scene never asks which, because the
## edge already said. The gate is asked FIRST, then the transition hook for
## non-seamless arrivals, all before any state moves: a refused crossing
## leaves the player exactly where they stood.
func _travel(edge: Dictionary) -> Dictionary:
	var gate := WorldmapApi.can_traverse(edge)
	if not bool(gate.get("ok", false)):
		return {"traveled": false, "reason": String(gate.get("reason", ""))}
	var to_node := String(edge.get("to", ""))
	if _graph == null or _graph.node(to_node).is_empty():
		return {"traveled": false, "reason": "unknown_node"}
	if not _node_configs.has(to_node):
		return {"traveled": false, "reason": "unknown_node"}
	var target_config := (_node_configs[to_node] as Dictionary).duplicate(true)
	if not bool(target_config.get("seamless", true)):
		var passage := WorldmapApi.run_transition(_node_id, to_node, edge)
		if not bool(passage.get("ok", false)):
			return {"traveled": false, "reason": String(passage.get("reason", ""))}
	var template_id := String(target_config.get("domain_template", ""))
	if not template_id.is_empty():
		return _descend(edge, to_node, target_config, template_id)
	_node_id = to_node
	_player_cell = edge.get("to_cell", Vector2i.ZERO) as Vector2i
	_config = target_config
	_size = maxi(2, int(_config.get("chunk_size", _size)))
	_seed = int(_config.get("seed", _seed))
	_streamer.configure(WorldmapApi.default_generator(), _config)
	_clear_holders()
	refresh_around(_chunk_of(_player_cell))
	_place_player()
	return {"traveled": true, "reason": ""}


## Descend into a domain node: enter a REAL run through the installed seam,
## remember the exact cell to return to, and stand on the far side with no
## chunks rendered — rooms are walked on the domain's own surface. The run
## starts before any scene state moves, so a refused entry leaves the player
## where they stood; the return is pushed only once the run exists.
func _descend(
	edge: Dictionary, to_node: String, target_config: Dictionary, template_id: String
) -> Dictionary:
	var entered := WorldmapApi.enter_domain_run(
		template_id, int(target_config.get("domain_seed", 0))
	)
	if not bool(entered.get("ok", false)):
		return {"traveled": false, "reason": String(entered.get("reason", ""))}
	_returns.append({"node": _node_id, "cell": _player_cell})
	_node_id = to_node
	_player_cell = edge.get("to_cell", Vector2i.ZERO) as Vector2i
	_config = target_config
	_clear_holders()
	_place_player()
	return {"traveled": true, "reason": ""}


## Leave the domain node and stand back on the exact cell left from. The
## overworld was never unloaded — only unrendered — so its mutations, cache
## and rendered range are exactly as the descent found them. Refuses
## `not_inside` above ground and passes a refused leave through untouched.
func return_from_domain() -> Dictionary:
	if _returns.is_empty():
		return {"ok": false, "reason": "not_inside"}
	var left := WorldmapApi.leave_domain_run()
	if not bool(left.get("ok", false)):
		return {"ok": false, "reason": String(left.get("reason", ""))}
	var back := _returns.pop_back() as Dictionary
	_node_id = String(back.get("node", ""))
	_player_cell = back.get("cell", Vector2i.ZERO) as Vector2i
	_config = (_node_configs.get(_node_id, {}) as Dictionary).duplicate(true)
	_size = maxi(2, int(_config.get("chunk_size", _size)))
	_seed = int(_config.get("seed", _seed))
	_streamer.configure(WorldmapApi.default_generator(), _config)
	refresh_around(_chunk_of(_player_cell))
	_place_player()
	return {"ok": true, "reason": ""}


func _clear_holders() -> void:
	for id in _holders.keys():
		(_holders[id] as Node).free()
	_holders.clear()


func _place_player() -> void:
	if _player != null:
		_player.position = (Vector2(_player_cell) + Vector2(0.5, 0.5)) * CELL_PX


func _chunk_coords(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / _size), floori(float(cell.y) / _size))


func _local_of(cell: Vector2i) -> Vector2i:
	var cc := _chunk_coords(cell)
	return Vector2i(cell.x - cc.x * _size, cell.y - cc.y)


func _chunk_of(cell: Vector2i) -> Vector2i:
	return _chunk_coords(cell)


func _chunk_id_of(cell: Vector2i) -> String:
	var cc := _chunk_coords(cell)
	return "%s:%d,%d" % [_node_id, cc.x, cc.y]


func _coords_of_id(chunk_id: String) -> Vector2i:
	var parts := String(chunk_id).split(":")
	if parts.size() < 2:
		return Vector2i.ZERO
	var pair := parts[1].split(",")
	if pair.size() < 2:
		return Vector2i.ZERO
	return Vector2i(pair[0].to_int(), pair[1].to_int())


func _render_chunk(cx: int, cy: int) -> void:
	var holder := Node2D.new()
	holder.name = "chunk_%d_%d" % [cx, cy]
	add_child(holder)
	_render_chunk_into(holder, cx, cy)
	var id := "%s:%d,%d" % [_node_id, cx, cy]
	_holders[id] = holder
	_streamer.mark_loaded(id)


func _render_chunk_into(holder: Node2D, cx: int, cy: int) -> void:
	var chunk := _streamer.chunk_data(_node_id, cx, cy, _size, _seed)
	var origin := Vector2(cx * _size, cy * _size) * CELL_PX
	for y in chunk.size:
		for x in chunk.size:
			var arch := String((chunk.terrain[y] as Array)[x])
			var tile := _tile_texture(arch)
			if tile == null:
				continue
			var sprite := Sprite2D.new()
			sprite.texture = tile
			sprite.centered = false
			sprite.position = origin + Vector2(x, y) * CELL_PX
			sprite.scale = Vector2(CELL_PX, CELL_PX) / tile.get_size()
			holder.add_child(sprite)
	for prop in chunk.props:
		_render_prop(holder, origin, prop as Dictionary)


func _render_prop(holder: Node2D, origin: Vector2, placement: Dictionary) -> void:
	var asset_id := String(placement.get("asset", ""))
	var texture := _prop_texture(asset_id)
	if texture == null:
		return
	var cell := placement.get("cell", Vector2i.ZERO) as Vector2i
	var fp := placement.get("footprint", Vector2i.ONE) as Vector2i
	var sprite := Sprite2D.new()
	sprite.texture = texture
	var target := Vector2(fp) * CELL_PX
	sprite.scale = target / texture.get_size()
	sprite.position = origin + Vector2(cell) * CELL_PX + Vector2(target.x / 2.0, target.y)
	sprite.offset = Vector2(0, -target.y / 2.0)
	holder.add_child(sprite)


func _tile_texture(arch: String) -> Texture2D:
	if arch.is_empty():
		return null
	if _textures.has("tile:" + arch):
		return _textures["tile:" + arch] as Texture2D
	# By archetype across categories: water cells name `water_feature.*`,
	# which a ground-only lookup would render as holes.
	var matches := WorldmapAssets.by_archetype(String(_config.get("environment", "")), arch)
	if matches.is_empty():
		return null
	var texture := load(String((matches[0] as Dictionary).get("path", ""))) as Texture2D
	_textures["tile:" + arch] = texture
	return texture


func _prop_texture(asset_id: String) -> Texture2D:
	if asset_id.is_empty():
		return null
	if _textures.has("prop:" + asset_id):
		return _textures["prop:" + asset_id] as Texture2D
	for entry in WorldmapAssets.for_environment(String(_config.get("environment", ""))):
		if String((entry as Dictionary).get("id", "")) == asset_id:
			var texture := load(String((entry as Dictionary).get("path", ""))) as Texture2D
			_textures["prop:" + asset_id] = texture
			return texture
	return null
