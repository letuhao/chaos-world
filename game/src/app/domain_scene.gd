class_name DomainScene
extends Node2D

## A `DomainMap` REALIZED as a walkable top-down tile scene (ADR 0072).
##
## The map is the source of truth and this file is a VIEW of it. Nothing here derives a
## gameplay rule, nothing gameplay reads comes back off a node, and `DomainMap` stays
## engine-agnostic (domain_map.gd:4-8) precisely because the engine lives over here rather
## than inside the data.
##
## ## WHO BUILDS THIS IN PRODUCTION
##
## [method realize_world], via `DomainBoot.realize_world` — which the composition root
## installs as a `Callable` seam (`DomainBoot.set_world_observer`) and `DomainBoot.enter_domain`
## fires the moment a run exists. It parents this scene under the mounted domain SCREEN, places
## one inhabitant body per minted `Actor` at `DomainSpawner.placement`, adds a `PlayerAdapter`
## bounded to [method map_bounds], and is undone by [method release_world] on `leave_domain`, on
## a route change, and in `ItemWorkbenchApp.teardown()`.
##
## That is the whole production path. **What is NOT built: an avatar that MOVES.**
## `PlayerAdapter` is placed and bounded, and `move_to` / `step_movement` work headlessly, but
## nothing in the shipped program drives its `_physics_process` from a real frame and no screen
## exposes a movement control. A player can ENTER a domain and SEE its floor, its walls and the
## creatures standing on it, but cannot yet walk across it. That is the remaining half, recorded
## here rather than implied by this file's existence.
##
## ## Why this is a new class and not a `WorldEntry`
##
## `world_entry.gd` is pinned as a source shape by `tests/arch_rules/test_arch_rules.gd:111`, and
## ADR 0072:31-32 explicitly left its fate undecided. Reviving it would be a real edit to a
## frozen shape. It is also a HANDCRAFTED-scene base — it binds authored markers by name
## (`SpawnPoint`, `NPCSpawnPoints`) and has no notion of a map built from data. So this is a
## sibling, not a subclass.
##
## ## One terrain set, so the corridor/room seam is not a case
##
## Rooms and corridors stamp the SAME atlas tile ([constant FLOOR_ATLAS_COORDS]). A corridor
## cannot have a different floor from the room it leaves, because there is no second tile for it
## to be. The seam is absent rather than special-cased.
##
## ## Walls are the one-cell dilation MINUS the walkable set
##
## `DomainPaths.TILE_GAP` is 2 (domain_paths.gd:58), so the dilation of one room lands in the
## clearance and never reaches the next — except along a corridor, where the corridor's own cells
## ARE walkable and the dilation would otherwise brick the passage. So the wall set is
## `walkable.dilate().minus(walkable)` over the union, never per room. Every wall is then adjacent
## to something walkable, which is what bounds the set and what makes the ring ring rather than
## tile the empty space around a domain.
##
## ## The navigation polygon is COMPUTED. Do not add a bake.
##
## `bake_navigation_polygon()` rasterizes SOURCE GEOMETRY — a `Node2D` subtree full of colliders
## — into a navmesh, and there is no source geometry here: the walkable cell set IS the answer.
## Baking it would find nothing to bake, or bake the wall tiles as obstacles against a polygon
## that does not exist yet, and a baked navmesh would be a second, disagreeing description of the
## same walkable set. So the outline is extracted from the grid by marching squares and
## triangulated by `Geometry2D` into ONE `NavigationPolygon` as explicit vertices and polygon
## indices. `make_polygons_from_outlines()` is the same trap: deprecated, and it routes through
## the navigation SERVER, which this scene must not need.
##
## ## No frame is required and none is waited on
##
## The headless runner drives every test from `SceneTree._initialize()`, which returns before the
## first frame: `_ready()` is never delivered to a node parented to `root` and a deferred free
## never runs (AGENTS.md's memory rule; INC-0004/INC-0005 destroyed every session on the
## machine). So everything is built in `_init()` — no tree, no frame — and [method realize] covers
## the case where the map is only known afterwards. There is no `_process`, no `await get_tree()`
## and no deferred work anywhere in this file.
##
## ## It holds no state of its own
##
## `app/` is the composition root and wires, and the rule that keeps that honest is
## `app_state_signals` (tools/arch/enforce.py:287-316): a member `Array` with no element type, or
## one typed by a class THIS repo defines, counts as a `state-table` signal, and two signals flag
## the file. So every collection below is either an engine-typed node list (`Array[Marker2D]`),
## which the rule excludes and `test_arch_rules.gd:417-429` pins, or a local computed by a
## `static` function and never stored. `map` is the only field, and it is the thing being viewed,
## not a table the scene maintains.

## One tile is 32 px. This is the ONLY thing turning the map's `Vector2i` TILE coordinates into
## pixels, and it must equal `texture_region_size` in the tileset `.tres`. The two files cannot
## read each other, so `test_domain_scene.gd` asserts the equality rather than trusting it.
const TILE_PIXELS := 32

## The source id in the tileset. Constant rather than a field a caller can point elsewhere: a
## scene whose floor depends on the caller's atlas is not a view of the map.
const SOURCE_ID := 0

## The floor tile. Rooms AND corridors stamp this one tile — see the class docstring.
const FLOOR_ATLAS_COORDS := Vector2i(0, 0)

## The wall tile: the same atlas source, so both layers share one terrain set and one physics
## layer and neither layer has to declare a private one.
const WALL_ATLAS_COORDS := Vector2i(2, 0)

## Where the tileset lives. One path declared once: `realize()` and the test that loads the file
## by hand both read it, and two copies of a path are two copies that can disagree.
const TILESET_PATH := "res://src/data/tilesets/chaos_world_domain.tres"

const FLOOR_NODE := "FloorLayer"
const WALL_NODE := "WallLayer"
const NAVIGATION_NODE := "Navigation"
const SPAWNS_NODE := "Spawns"
const EXITS_NODE := "Exits"
const ZONES_NODE := "Zones"

## The realized world, by name. [method realize] builds a `Node2D` under a parent the CALLER
## chose, so the composition root owns the node that draws the world and the world goes away
## with it; these four names are how anyone finds it afterwards. Declared among the other
## constants rather than beside the world section because `class-definitions-order` puts every
## `const` before every `func`.
const WORLD_NODE := "DomainWorld"
const WORLD_SCENE_NODE := "DomainScene"
const WORLD_PLAYER_NODE := "DomainPlayer"
const WORLD_INHABITANTS_NODE := "DomainInhabitants"

## Every node a realized world creates, so [method release_world] frees the subtree by NAME
## rather than by walking it — bounded, and self-describing: anything under the world that is
## not in this list was created by somebody else and is reported as `stranded`. An engine
## element type (`StringName`), never a repo type, which is what keeps this off the `app/`
## state-table heuristic.
const WORLD_BORN: Array[StringName] = [
	WORLD_PLAYER_NODE,
	WORLD_INHABITANTS_NODE,
	WORLD_SCENE_NODE,
]

## Every position is a tile's CENTRE, never its corner. `Rect2i.get_center()` is the same
## convention (domain_paths.gd:163), and a marker half a tile from where its room is drawn
## is a marker a reader cannot place.
const CENTER_OFFSET := Vector2(0.5, 0.5)

## Ceiling on the contour chain. It is finite by construction — one directed edge per open
## side of a cell, four per cell at most, and every step consumes one — so this is slack.
## It names the condition: a loop failed to close.
const MAX_OUTLINE_STEPS := 1 << 22

## The map this scene is a view of, or null before one is realized.
var map: DomainMap = null

var _floor: TileMapLayer = null
var _walls: TileMapLayer = null
var _navigation: NavigationRegion2D = null

## Bound node lists, never a feature's state table: `tools/arch/rules.py:177-187` reads
## `Array[Marker2D]` / `Array[Area2D]` as wiring, and test_arch_rules.gd:417-429 pins it.
var _spawns: Array[Marker2D] = []
var _exits: Array[Marker2D] = []
var _zones: Array[Area2D] = []
## Everything this scene created, so `clear()` frees the whole subtree by name rather than
## by walking it — and so a caller can see exactly what the scene owes the process.
var _born: Array[Node] = []


## Build the whole domain. Runs in `_init()`, not `_ready()`.
##
## ## Why it cannot be `_ready()`
##
## The headless runner returns from `SceneTree._initialize()` before the first frame, so
## `_ready()` is never delivered to a node parented to `root` (`seam_harness.gd:8-11` hits
## the same wall and works around it by calling `_ready()` by hand). A scene that only exists
## after `_ready()` is a scene that cannot be verified headlessly at all. `_init()` needs
## neither a tree nor a frame, so a caller that parents this gets a finished domain.
func _init(domain_map: DomainMap = null) -> void:
	if domain_map != null:
		realize(domain_map)


## Build `domain_map` into this scene, replacing anything built before.
##
## Idempotent by construction: a second call clears the previous layers rather than stacking
## a second set on top, which is exactly the leak shape
## `tests/arch_rules/test_no_deferred_free.gd:17-22` records.
func realize(domain_map: DomainMap) -> void:
	clear()
	map = domain_map
	if domain_map == null:
		push_error("DomainScene.realize: no DomainMap; an empty domain is not a domain")
		return
	# ONE layout read, reused by the tiles, the markers and the public `room_rect()`. A
	# second layout computation elsewhere would be a second layout algorithm, and
	# domain_paths.gd:182-185 says there is exactly one in this repo.
	var rects := DomainPaths.layout(domain_map)
	var walkable := walkable_cells(rects, domain_map)
	_floor = _build_layer(FLOOR_NODE, false)
	_walls = _build_layer(WALL_NODE, true)
	for key in walkable.keys():
		_floor.set_cell(key, SOURCE_ID, FLOOR_ATLAS_COORDS, 0)
	var walls := wall_cells(walkable)
	for key in walls.keys():
		_walls.set_cell(key, SOURCE_ID, WALL_ATLAS_COORDS, 0)
	# `update_internals()` forces each layer to build its physics and rendering NOW.
	# Without it TileMapLayer batches to the end of a frame the headless runner never
	# reaches, so `get_cell_tile_data()` answers null and a collision query sees nothing.
	_floor.update_internals()
	_walls.update_internals()
	_navigation = _build_navigation(_polygon_from(walkable))
	_place_spawns()
	_place_exits()
	_place_zones()


## Detach and free everything this scene built. Idempotent, and safe after an aborted test.
##
## `queue_free()` is BANNED in `res://src` (tests/arch_rules/test_no_deferred_free.gd:40-67)
## because the headless runner never processes a frame, so a deferred free leaks for the life
## of the process — the shape that took `tests/ui` to 67 GB and forced a power-cycle.
## `remove_child()` first, so there is nothing left to defer.
func clear() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()
	_born.clear()
	_spawns.clear()
	_exits.clear()
	_zones.clear()
	_floor = null
	_walls = null
	_navigation = null
	map = null


func floor_layer() -> TileMapLayer:
	return _floor


func wall_layer() -> TileMapLayer:
	return _walls


func navigation_region() -> NavigationRegion2D:
	return _navigation


## The laid-out rect of a room, exactly as `DomainPaths.layout` produced it. A caller reads
## the same rect the tiles were stamped from rather than a second opinion of it.
func room_rect(room_id: StringName) -> Rect2i:
	if map == null or not map.has_room(room_id):
		return Rect2i()
	return DomainPaths.layout(map).get(String(room_id), Rect2i())


## One `Marker2D` per `actor_spawn_ref`, in `DomainMap.spawn_refs()` canonical order.
## A ref's `count` is deliberately NOT expanded here: `DomainSpawner.spawn_map` mints every
## instance of one ref through `position_of(room, ref, index)`
## (domain_spawner.gd:116-178), so a ref names a PLACE and `spawn_position` is what
## separates the instances inside it.
func spawn_markers() -> Array[Marker2D]:
	return _spawns.duplicate()


## One `Marker2D` per room exit, standing on the mouth the corridor leaves through. It is
## the tile the polyline's first point already names (domain_paths.gd:294-305), so the two
## cannot disagree about where a passage starts.
func exit_markers() -> Array[Marker2D]:
	return _exits.duplicate()


## One `Area2D` per `EnvironmentZoneDef`, placed from the zone's authored `bounds` in
## TILES relative to its room — so a hazard sits where it was authored, never where a
## heuristic about the room's size puts it.
func zone_areas() -> Array[Area2D]:
	return _zones.duplicate()


## The playable bounds in pixels, for `PlayerAdapter.set_map_bounds(Rect2)`
## (player_adapter.gd:197). Sized from the DRAWN cells rather than from `DomainMap.extent`,
## which is the generator's grid and is `Vector2i.ZERO` on a handcrafted map
## (domain_minimap.gd:215-217 says exactly this).
func map_bounds() -> Rect2:
	return pixel_rect(occupied_rect(walkable_cells(DomainPaths.layout(map), map)))


## Where a player enters: the entry room's centre, or `Vector2.ZERO` when the map names no
## entry (an unenterable domain, domain_map.gd:28).
func entry_position() -> Vector2:
	if map == null or map.entry_room == &"":
		return Vector2.ZERO
	return tile_center(room_rect(map.entry_room).get_center())


## Where `DomainSpawner` should put instance `index` of `room_id`/`ref_id`.
##
## Refs are spread along their room's MAJOR axis by canonical slot and instances of one ref
## step ACROSS the minor axis. Three mobs on one tile are three mobs a player cannot tell
## apart, and a mob outside its room is a mob inside a wall.
func spawn_position(room_id: StringName, ref_id: String, index: int = 0) -> Vector2:
	var rect := room_rect(room_id)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Vector2.ZERO
	var refs := _refs_of(room_id)
	var slot := maxi(0, refs.find(ref_id))
	return tile_center(_slot_cell(rect, slot, maxi(1, refs.size())) + _instance_offset(rect, index))


## The pixel rect a cell range occupies. Exposed because `map_bounds()` is one caller and a
## test asks this of a single room rather than of the whole map.
func pixel_rect(cells: Rect2i) -> Rect2:
	return Rect2(
		Vector2(cells.position) * float(TILE_PIXELS), Vector2(cells.size) * float(TILE_PIXELS)
	)


## A cell's centre in pixels — the convention every position in this scene uses.
static func tile_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + CENTER_OFFSET) * float(TILE_PIXELS)


## Every walkable cell: the union of the room rects and the corridor runs. This is the one
## answer to "where can a player stand", and the floor layer, the wall set and the
## navigation polygon are all derived from it — three consumers, one derivation.
##
## ## Why corridors are stamped and not left to the rooms
##
## `DomainPaths._polyline` builds an L between two rects and `_mouth` picks the tile each
## room is entered through (domain_paths.gd:294-324), so the first and last points are
## already inside the rooms. The ELBOW is not. Rooms alone therefore do not connect, and a
## corridor the map says exists would be a passage on the minimap and a wall in the world.
static func walkable_cells(rects: Dictionary, domain_map: DomainMap) -> Dictionary:
	var out := {}
	for key in rects.keys():
		_fill_rect(out, rects[key])
	for route in DomainPaths.routes(domain_map):
		for cell in _route_cells(route.get("points", []), int(route.get("width", 1))):
			out[cell] = true
	return out


## Every wall cell: the one-cell dilation of the walkable set MINUS the walkable set.
##
## Both halves matter. The dilation alone would fence a domain that has no outer wall, and
## subtracting the walkable set is what keeps a corridor's own cells passable and stops the
## ring from being drawn across the inside of a room.
static func wall_cells(walkable: Dictionary) -> Dictionary:
	var out := {}
	for key in walkable.keys():
		var cell: Vector2i = key
		for neighbour in _ring(cell):
			if not walkable.has(neighbour):
				out[neighbour] = true
	return out


## The closed outlines of the walkable set, in PIXELS, for the navigation polygon.
##
## Marching squares, not one box per cell: a box per cell hands the navigation server
## hundreds of overlapping outlines for a single room, and de-overlapping them is exactly what
## a bake would normally do — the thing being avoided here. One loop per region hands over the
## silhouette a player would describe rather than the grid it was drawn on.
##
## The formulation is about SIDES. Every walkable cell emits a directed edge for each of its
## four sides whose neighbour is NOT walkable, wound so walkable material is always on the
## traveler's RIGHT. Chaining those edges head-to-tail is then unambiguous except at a SADDLE
## — two cells meeting only at a corner — and the winding resolves it without a special case:
## the two diagonal cells are not connected through the corner, so the chain consumes one
## edge, closes, and the other is traced as its own loop on the next pass. That is the honest
## reading of a region genuinely not connected there; a loop threading the zero-width bridge
## instead is a polygon the server would triangulate into overlapping geometry.
##
## Every choice is a rule rather than a hash-order accident — the edge taken at a saddle is
## the lowest corner, and the loop started is the lowest untraced corner — because ADR 0072's
## determinism claim covers this scene too, and an outline that came out differently on two
## machines would break it.
static func outlines(walkable: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var edges := _boundary_edges(walkable)
	# Bounded on WORK CONSUMED, not on passes. A pass that traces a real contour removes at
	# least one edge, so the loop is O(edges); `_chain` can legitimately return a short loop
	# while consuming nothing, and a count on ITERATIONS would then spin forever re-picking
	# the same start — 4.2M iterations once held `godot.lock` and blocked every test run on
	# the machine. Counting consumed edges makes every iteration provably shrink the problem,
	# and makes a genuine no-progress case terminate in ONE pass.
	var consumed := 0
	var total := _edge_count(edges)
	while consumed < total:
		var starts := _open_corners(edges)
		if starts.is_empty():
			break
		var loop := _chain(edges, starts[0])
		if loop.size() < 4:
			# Fewer than four corners is a degenerate figure, not a room. Named rather than
			# emitted: a polygon the server cannot triangulate is worse than no polygon. The
			# start corner is DISCARDED so `_open_corners` cannot re-pick it — nothing about
			# it would change, which is the spin this loop's bound has to hide.
			push_error(
				"DomainScene.outlines: a contour closed after %d corner(s); skipped" % loop.size()
			)
			_drop_corner(edges, starts[0])
			consumed += 1
			continue
		var points := PackedVector2Array()
		for cell in loop:
			points.append(Vector2(cell) * float(TILE_PIXELS))
		out.append(points)
		consumed += 1
	var untraced := 0
	for key in edges.keys():
		var pending: Array = edges[key]
		if not pending.is_empty():
			untraced += 1
	if untraced > 0:
		push_error(
			(
				(
					"DomainScene.outlines: the contour chain hit its %d-step ceiling with %d "
					+ "untraced corner(s); the navigation polygon is incomplete"
				)
				% [MAX_OUTLINE_STEPS, untraced]
			)
		)
	return out


## The bounding rect of every cell in a set, or an empty rect when the set is empty.
static func occupied_rect(cells: Dictionary) -> Rect2i:
	var out := Rect2i()
	var seeded := false
	for key in cells.keys():
		var cell: Vector2i = key
		if not seeded:
			out = Rect2i(cell, Vector2i.ONE)
			seeded = true
			continue
		out = out.expand(cell)
		out = out.expand(cell + Vector2i.ONE)
	return out


# ── internals ────────────────────────────────────────────────────────────────


## The eight neighbours of a cell, clockwise from north. Fixed order because the ring is a
## SET: the order cannot change which cells are walls, only the order they are listed in.
static func _ring(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i(0, -1),
		cell + Vector2i(1, -1),
		cell + Vector2i(1, 0),
		cell + Vector2i(1, 1),
		cell + Vector2i(0, 1),
		cell + Vector2i(-1, 1),
		cell + Vector2i(-1, 0),
		cell + Vector2i(-1, -1),
	]


static func _fill_rect(out: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out[Vector2i(x, y)] = true


## The cells a corridor polyline sweeps, widened to its `width`.
##
## Each segment is stamped as a RECTANGLE, not as a one-pixel line: the diagonal leg of an
## L stamped as a line is walkable on its pixels only, and the player falls through the
## gaps.
##
## `width` is EXACT and asymmetric. A `gate`/`core` corridor is `DomainPaths.GATE_WIDTH` = 2
## (domain_paths.gd:73), and a symmetric `grow = (width - 1) / 2` used INTEGER division, so
## width 2 grew by 0 and a corridor the map called two tiles wide was rasterised ONE tile
## wide — its second lane a wall the player could not use. `Rect2i.grow` is symmetric and
## cannot hit an even count alone, so the extra cell goes on ONE side: `low` on the `-`
## faces, `high` on the `+`, `low + high == width - 1`. Width 1 is (0,0), width 2 is (0,1).
## The lane lands on the positive side, next to the mouth `_mouth` chose.
static func _route_cells(points: Array, width: int) -> Dictionary:
	var out := {}
	var path: Array[Vector2i] = []
	for point in points:
		var pair := point as Array
		if pair.size() == 2:
			path.append(Vector2i(int(pair[0]), int(pair[1])))
	if path.size() < 2:
		for cell in path:
			out[cell] = true
		return out
	var extra := maxi(0, maxi(1, width) - 1)
	var high := extra - extra / 2
	var low := extra - high
	for index in range(path.size() - 1):
		_fill_rect(out, _widen(_segment_rect(path[index], path[index + 1]), low, high))
	return out


## A segment rect grown by `low` on its low faces and `high` on its high faces, so a segment
## of thickness 1 comes out exactly `1 + low + high` thick even when that is an even number.
static func _widen(rect: Rect2i, low: int, high: int) -> Rect2i:
	return Rect2i(
		Vector2i(rect.position.x - low, rect.position.y - low),
		Vector2i(rect.size.x + low + high, rect.size.y + low + high)
	)


## The rectangle a straight run between two tiles covers, inclusive of both ends.
static func _segment_rect(from_cell: Vector2i, to_cell: Vector2i) -> Rect2i:
	return Rect2i(
		Vector2i(mini(from_cell.x, to_cell.x), mini(from_cell.y, to_cell.y)),
		Vector2i(absi(to_cell.x - from_cell.x) + 1, absi(to_cell.y - from_cell.y) + 1)
	)


## Every boundary edge of the walkable set, keyed by the cell corner it LEAVES.
##
## Winding, derived rather than assumed: a traveller's right is their heading rotated a
## quarter turn clockwise on screen, and each of the four directions below keeps the
## emitting cell on that side. A north edge therefore runs `+x`, an east edge runs `+y`, a
## south edge runs `-x` and a west edge runs `-y`.
static func _boundary_edges(walkable: Dictionary) -> Dictionary:
	var edges := {}
	for key in walkable.keys():
		var cell: Vector2i = key
		if not walkable.has(cell + Vector2i(0, -1)):
			_add_edge(edges, cell, cell + Vector2i(1, 0))
		if not walkable.has(cell + Vector2i(1, 0)):
			_add_edge(edges, cell + Vector2i(1, 0), cell + Vector2i(1, 1))
		if not walkable.has(cell + Vector2i(0, 1)):
			# Bottom-right -> BOTTOM-left, i.e. two corners that SHARE a row. Ending at the
			# top-left closed every contour after a zigzag. The winding is +x along the top,
			# +y down the right, -x along the bottom, -y up the left.
			_add_edge(edges, cell + Vector2i(1, 1), cell + Vector2i(0, 1))
		if not walkable.has(cell + Vector2i(-1, 0)):
			# Bottom-left -> TOP-left, the `-y` the docstring above names. Emitting
			# `cell -> cell + (0, 1)` instead ran the west edge `+y`, against that winding: the
			# `-y` edge that ought to ARRIVE at a corner went the other way, so every contour
			# closed after one side instead of all four.
			_add_edge(edges, cell + Vector2i(0, 1), cell)
	return edges


static func _add_edge(edges: Dictionary, from_corner: Vector2i, to_corner: Vector2i) -> void:
	if not edges.has(from_corner):
		edges[from_corner] = [] as Array[Vector2i]
	edges[from_corner].append(to_corner)


## Every corner still carrying an untraced edge, lowest first, or `[]` when the silhouette
## is complete.
##
## Sorted, because an unsorted `keys()` order is stable within one run but is not a
## promise, and a silhouette that came out differently on two machines would break the
## determinism the design rests on. An empty ARRAY rather than a null sentinel: `null` here
## would be a `Variant`, and an inferred `Variant` is a compile error in this repo.
static func _open_corners(edges: Dictionary) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	for key in edges.keys():
		var pending: Array = edges[key]
		if not pending.is_empty():
			open.append(key)
	open.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return open


## Every directed edge currently in the walk, counted. The termination bound for
## [method outlines]: each contour traced consumes at least one, so this is also the
## maximum number of contours that can exist.
static func _edge_count(edges: Dictionary) -> int:
	var total := 0
	for key in edges.keys():
		var pending: Variant = edges[key]
		if pending is Array:
			total += (pending as Array).size()
	return total


## Discard a corner that produced a degenerate contour, consuming whatever edges it still
## holds. Returns how many edges were removed, so the caller's progress counter reflects real
## work even when the corner held none — which is the case that used to spin. The corner is
## REMOVED from the dictionary outright rather than emptied, so `_open_corners` cannot hand
## it back on the next pass.
static func _drop_corner(edges: Dictionary, corner: Vector2i) -> int:
	if not edges.has(corner):
		return 0
	var pending: Variant = edges[corner]
	var removed := (pending as Array).size() if pending is Array else 0
	edges.erase(corner)
	return removed


## Follow directed edges from `start` until the loop closes, CONSUMING each edge it takes.
## The returned corners INCLUDE the start: a polygon's first and last vertices are distinct,
## and dropping the start would turn every rectangle into a triangle.
##
## Consuming is what makes the walk finite and what resolves the saddle: at a corner where two
## walkable cells meet diagonally there are two outgoing edges, one is taken, the loop closes,
## and the other is traced as its own region on the next pass. The edge taken is the lowest
## corner, so the choice is a function of the data and not of hash order.
static func _chain(edges: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var loop: Array[Vector2i] = [start]
	var cursor := start
	var steps := 0
	while steps < MAX_OUTLINE_STEPS:
		steps += 1
		# Read through the DICTIONARY, not through a local. `var pending: Array =
		# edges.get(...)` COPIES in Godot 4 — arrays are value types there — so an `erase`
		# against it mutated a temporary, every edge stayed available, and the walk took the
		# same edge twice and closed every contour after 2 corners. Writing back through
		# `edges` is what makes consumption real.
		if edges.get(cursor, [] as Array[Vector2i]).is_empty():
			break
		var next_corner := _lowest(edges[cursor])
		(edges[cursor] as Array[Vector2i]).erase(next_corner)
		if next_corner == start:
			# Closed. The start corner is already the first entry, so returning now leaves
			# the loop with every corner exactly once and the polygon open at both ends.
			return loop
		loop.append(next_corner)
		cursor = next_corner
	return loop


## ONE `NavigationPolygon` over the computed outlines: explicit vertices and explicit
## polygon indices, triangulated here rather than by the navigation server. Never baked —
## see the class docstring for why a bake call here would be a bug and not an improvement.
static func _polygon_from(walkable: Dictionary) -> NavigationPolygon:
	var polygon := NavigationPolygon.new()
	var vertices := PackedVector2Array()
	for loop in outlines(walkable):
		var triangles := Geometry2D.triangulate_polygon(loop)
		if triangles.is_empty():
			push_error("DomainScene: a %d-corner outline produced no triangles" % loop.size())
			continue
		var offset := vertices.size()
		vertices.append_array(loop)
		var index := 0
		while index + 2 < triangles.size():
			(
				polygon
				. add_polygon(
					PackedInt32Array(
						[
							triangles[index] + offset,
							triangles[index + 1] + offset,
							triangles[index + 2] + offset,
						]
					)
				)
			)
			index += 3
	polygon.vertices = vertices
	return polygon


## The lowest of a set of corners, by x then y. One total order for the whole file: the
## loop start, the saddle choice and the spawn slot all need "lowest, and lowest again on
## the tie", and three copies of that comparator would drift.
static func _lowest(corners: Array) -> Vector2i:
	var out: Vector2i = corners[0]
	for corner in corners:
		if corner.x < out.x or (corner.x == out.x and corner.y < out.y):
			out = corner
	return out


func _build_layer(node_name: String, colliding: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = node_name
	layer.tile_set = load(TILESET_PATH) as TileSet
	# Floor tiles carry no collision polygon in the tileset, so enabling the layer on the
	# floor costs nothing and the WALL layer becomes the only thing here that can block.
	layer.collision_enabled = colliding
	layer.navigation_enabled = false
	# Y-sort with the origin raised half a tile. A tile's draw key is its own bottom edge
	# PLUS this offset, so a wall at the top of the screen sorts behind a player standing
	# one row below it; without the offset the player would vanish into it.
	layer.y_sort_enabled = colliding
	layer.y_sort_origin = TILE_PIXELS / 2
	_born.append(layer)
	add_child(layer)
	return layer


func _build_navigation(polygon: NavigationPolygon) -> NavigationRegion2D:
	var region := NavigationRegion2D.new()
	region.name = NAVIGATION_NODE
	region.navigation_polygon = polygon
	_born.append(region)
	add_child(region)
	return region


func _place_spawns() -> void:
	_spawns.clear()
	for ref in map.spawn_refs():
		var room_id := StringName(ref.get("room_id", ""))
		var ref_id := String(ref.get("ref_id", ""))
		var holder := _holder("%s_%s" % [SPAWNS_NODE, ref.get("room_id", "")])
		var marker := Marker2D.new()
		marker.name = "Spawn_%s" % ref_id
		marker.position = spawn_position(room_id, ref_id)
		# Readable back without the caller holding the map: which room and which ref this
		# point stands for, from the same row the marker was built from.
		marker.set_meta(&"room_id", String(room_id))
		marker.set_meta(&"ref_id", ref_id)
		holder.add_child(marker)
		_born.append(marker)
		_spawns.append(marker)


func _place_exits() -> void:
	_exits.clear()
	for route in DomainPaths.routes(map):
		var points: Array = route.get("points", [])
		if points.is_empty():
			continue
		var pair := points[0] as Array
		if pair.size() != 2:
			continue
		var marker := Marker2D.new()
		marker.name = "Exit_%s_%s" % [route.get("from", ""), route.get("to", "")]
		marker.position = tile_center(Vector2i(int(pair[0]), int(pair[1])))
		marker.set_meta(&"room_id", String(route.get("from", "")))
		marker.set_meta(&"to_room_id", String(route.get("to", "")))
		_holder(EXITS_NODE).add_child(marker)
		_born.append(marker)
		_exits.append(marker)


func _place_zones() -> void:
	_zones.clear()
	for row in map.zones():
		var room_id := StringName(row.get("room_id", ""))
		var origin := room_rect(room_id).position
		var authored := _box_of(row.get("bounds", [] as Array))
		# A zone's bounds are relative to ITS room (environment_zone_def.gd:92), so they are
		# translated by the room's laid-out origin rather than used as absolutes.
		var bounds := Rect2i(
			origin.x + authored.position.x,
			origin.y + authored.position.y,
			authored.size.x,
			authored.size.y
		)
		var area := Area2D.new()
		area.name = "Zone_%s" % row.get("zone_id", "")
		area.position = Vector2(bounds.position) * float(TILE_PIXELS)
		area.position += Vector2(bounds.size) * (float(TILE_PIXELS) / 2.0)
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(bounds.size) * float(TILE_PIXELS)
		shape.shape = rectangle
		area.add_child(shape)
		area.set_meta(&"zone_id", String(row.get("zone_id", "")))
		area.set_meta(&"room_id", String(room_id))
		area.set_meta(&"kind", String(row.get("kind", "")))
		_holder(ZONES_NODE).add_child(area)
		_born.append(area)
		_zones.append(area)


## A named container, created on first use. Grouping markers under per-room holders is what
## makes `Spawns_<room>/Spawn_<ref>` addressable by name without a search, and it follows
## the authored-group convention of world_entry.gd:32-39.
func _holder(node_name: String) -> Node2D:
	var existing := get_node_or_null(NodePath(node_name))
	if existing != null:
		return existing as Node2D
	var holder := Node2D.new()
	holder.name = node_name
	_born.append(holder)
	add_child(holder)
	return holder


## A room's spawn refs, sorted by `ref_id` — the canonical order `DomainMap.spawn_refs()`
## publishes (domain_map.gd:118-126), so a room's refs get the same slots on every run.
func _refs_of(room_id: StringName) -> Array[String]:
	var out: Array[String] = []
	var room_def := map.room(room_id)
	if room_def == null:
		return out
	for ref in room_def.actor_spawn_refs:
		out.append(String(ref.get("ref_id", "")))
	out.sort()
	return out


## The cell ref `slot` of `total` sits on, spread along the room's major axis with the ends
## kept clear.
##
## Clamped into the room rather than wrapped: a wrap puts two refs outside the walls they
## belong to, and a room smaller than its ref count overlaps instead of spilling.
func _slot_cell(rect: Rect2i, slot: int, total: int) -> Vector2i:
	var along_x := rect.size.x >= rect.size.y
	var span := (rect.size.x if along_x else rect.size.y) - 1
	var at := 0
	if total > 1 and span > 0:
		at = clampi(int(round(float((slot + 1) * span) / float(total + 1))), 0, span)
	var middle := rect.get_center()
	if along_x:
		return Vector2i(rect.position.x + at, middle.y)
	return Vector2i(middle.x, rect.position.y + at)


## Instance `index` of a ref steps ACROSS the room's minor axis, so the instances of one ref
## stand side by side rather than stacked, and none of them leaves the room.
##
## Returned as an OFFSET from `_slot_cell`, and it is built from the room's own extent so the
## sum stays inside the rect wherever the layout put it. Index 0 is deliberately `ZERO` — the
## slot IS instance 0's cell, since `spawn_map` numbers instances from 0 — and the fold below
## uses a LOCAL coordinate: an absolute one mod a LENGTH only agrees with a local one while
## the rect starts at 0, and on the flue at `Rect2i(9, 0, 4, 9)` the absolute form read
## `(11 + 1) % 4 == 0`, putting instance 1 back on instance 0.
##
## The symmetry is about the room's minor MIDDLE and is then folded back into the rect, so
## `middle + off` is always a cell the room owns: a room too small for the count wraps and
## overlaps honestly rather than walking a mob into the wall past its own edge.
func _instance_offset(rect: Rect2i, index: int) -> Vector2i:
	if index <= 0 or rect.size.x <= 0 or rect.size.y <= 0:
		return Vector2i.ZERO
	var along_x := rect.size.x >= rect.size.y
	var minor_size := rect.size.x if along_x else rect.size.y
	var minor_origin := rect.position.x if along_x else rect.position.y
	var minor_middle := rect.get_center().x if along_x else rect.get_center().y
	# Symmetric about the middle, so index 0 is the slot itself and every later index moves
	# off it rather than onto it: 1 down, 1 up, 2 down, 2 up ...
	var step := (index + 1) / 2
	if (index + 1) % 2 == 0:
		step = -step
	var folded := (minor_middle - minor_origin + step) % minor_size
	if folded < 0:
		folded += minor_size
	var spread := minor_origin + folded - minor_middle
	if along_x:
		return Vector2i(0, spread)
	return Vector2i(spread, 0)


## A `[x, y, w, h]` payload as a rect, or an empty rect when the shape is wrong.
## `DomainMap.zones()` flattens `EnvironmentZoneDef.to_dict()`, whose `bounds` is an Array
## precisely so it survives the JSON hop (environment_zone_def.gd:158).
static func _box_of(value: Array) -> Rect2i:
	if value.size() != 4:
		return Rect2i()
	return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))


# ── the realized world ───────────────────────────────────────────────────────
#
# The four verbs below and the two placement helpers used to be declared HERE,
# at the bottom of this file, under the banner "# ── the realized world. Built here,
# parented by the caller, freed by the caller ──". They pushed this file past the
# thousand-line ceiling, and they are not this class's job: `DomainScene` is the VIEW of
# one `DomainMap`, while the world that CONTAINS that view — plus one body per
# inhabitant and one player — is a separate concern that never touches a field of this
# one. `DomainWorld` now holds those bodies; these six are the FORWARDS that keep every
# existing spelling working.
#
# ## Why forwards rather than a move
#
# GDScript cannot alias a static from one script onto another, so a caller writing
# `DomainScene.release_world(parent)` — which `DomainBoot` does, and which any probe may
# — has to keep resolving. Each forward is one line, passes its arguments through
# unchanged, and returns the delegate's dictionary verbatim, so the return SHAPE and the
# free path (`remove_child()` then `free()`, never `queue_free()`) are the originals. The
# bodies, their comments and their ~40 lines of rationale moved verbatim into
# `domain_world.gd`; nothing else in either file changed.


## REALIZE `map` as a walkable world under `parent`. See [method DomainWorld.realize_world]
## for the placement rule, the three named refusals and why a second call frees the first.
static func realize_world(
	parent: Node, map: DomainMap, player: Actor, inhabitants: Array
) -> Dictionary:
	return DomainWorld.realize_world(parent, map, player, inhabitants)


## One body per inhabitant in `inhabitants`, at the placement the spawner recorded on it.
static func place_inhabitants(world: Node2D, inhabitants: Array) -> int:
	return DomainWorld.place_inhabitants(world, inhabitants)


## Put a `PlayerAdapter` for `player` into `world` at the entry centre.
static func place_player(world: Node2D, player: Actor, scene: DomainScene) -> PlayerAdapter:
	return DomainWorld.place_player(world, player, scene)


## FREE the realized world under `parent`. Idempotent, and a no-op when nothing was ever
## realized, so a `teardown()` may call it without asking first.
static func release_world(parent: Node) -> Dictionary:
	return DomainWorld.release_world(parent)


## Whether a world is currently realized under `parent`.
static func world_realized(parent: Node) -> bool:
	return DomainWorld.world_realized(parent)


## The realized world's read model, primitives only, or `{}` when nothing is realized.
static func world_summary(parent: Node) -> Dictionary:
	return DomainWorld.world_summary(parent)
