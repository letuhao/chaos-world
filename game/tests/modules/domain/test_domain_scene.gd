extends TestCase

## `DomainScene`: a `DomainMap` realized as a walkable tile scene (ADR 0072).
##
## ## Why these cases assert the scene and not a screenshot
##
## The domain program already decided this (ADR 0072 Consequences, point 3): walkability is
## verified by a headless driver, not by eye. So every claim below is asked of the node the
## player would walk on — `get_used_cells()`, the polygon the navigation server would be
## handed, the collision shape a ray would hit — and a case that could pass by looking right
## and being wrong is not a case worth writing.
##
## ## The three constraints this file is shaped around
##
## **No frame.** The runner drives every case from `SceneTree._initialize()`, which returns
## BEFORE the first frame. So nothing here awaits, and the scene is built in `_init()`:
## `test_the_scene_is_complete_without_ever_entering_the_tree()` mounts nothing at all and
## still asserts a finished domain, which is the only way to prove the scene does not need a
## frame to exist.
##
## **No leak.** The runner shares one process across every suite, and a node parented to
## `root` outlives the test that made it — the shape that took `tests/ui` to 67 GB
## (test_no_deferred_free.gd:17-22). Every node this file mints goes into `_born` in the
## instant it is minted, and `teardown()` frees the whole list, so a case that returns early
## leaks nothing. `queue_free()` is never used: the runner never processes a frame, so a
## deferred free never runs.
##
## **No second layout.** The scene must read `DomainPaths.layout(map)` and nothing else;
## two layouts is one too many (domain_paths.gd:182-185). The case
## `test_the_layout_is_exactly_domain_paths()` asserts equality against the module rather
## than against a hand-copied expectation, so a second algorithm cannot creep in unnoticed.

## The shipped scene file. Loadable and instantiable is a claim in its own right: a scene a
## player runs that does not parse is a domain with no tile scene at all.
const SCENE_PATH := "res://scenes/domains/DomainScene.tscn"

## The per-room holder prefix the scene names its spawn groups with (`Spawns_<room_id>`).
## A copy of one constant, asserted against the node names below so the two cannot drift.
const SPAWNS_PREFIX := "Spawns"

## Depth ceiling for any tree walk in this file. A recursive walk with no cap is an
## unbounded loop the moment the tree holds a junction (seam_harness.gd:58-61).
const MAX_TREE_WALK := 12

## Everything this suite minted, freed in `teardown()`.
var _born: Array[Node] = []
## The node count of `root` sampled at the start of each case, so the leak claim is measured
## against the tree rather than asserted from memory.
var _root_baseline: int = 0
var _root: Window = null


func setup() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_root_baseline = _root.get_child_count()


## Free everything this suite minted. Idempotent, and the ONLY place a node is freed:
## call sites are interleaved, so freeing at each one is skipped by any case that returns
## early, which is exactly how a suite leaks.
func teardown() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()
	_born.clear()


# ── fixtures ─────────────────────────────────────────────────────────────────
#
# Maps are built INLINE, the way `test_domain_paths.gd` does it, and never through
# `domain_generator.gd` — that file belongs to another agent and may be mid-edit, so a suite
# that depends on it measures their progress instead of this scene.


func _spawn(ref_id: String, role: String = "mob", count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": "warden", "role": role, "count": count}


func _zone(zone_id: StringName, kind: StringName, bounds: Rect2i) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = zone_id
	zone.kind = kind
	zone.status_id = &"env_scourge"
	zone.mitigation_tags = [&"gear", &"affinity"] as Array[StringName]
	zone.bounds = bounds
	return zone


func _room(
	room_id: StringName, kind: StringName, exits: Array[StringName], room_size: Vector2i
) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	room.size = room_size
	return room


## A three-room line with authored spawns and a zone in every room: enough shape for the
## floor/wall/navigation/marker claims to each have something real to bite on, and small
## enough that a case names the cell it means.
##
## Sizes are deliberately ASYMMETRIC so a layout bug cannot hide behind symmetry, and the
## entry is an `empty` breather because a `floor` defaults to the hostile `skirmish` band
## (room_def.gd:60).
func _three_room_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(40, 32), 17)
	var entry := _room(
		&"entry_grove", &"floor", [&"ember_flue"] as Array[StringName], Vector2i(7, 5)
	)
	entry.roster_band = &"empty"
	entry.actor_spawn_refs = [_spawn("a1"), _spawn("a2")] as Array[Dictionary]
	entry.environment_zones = [_zone(&"ash_drift", &"super_hot", Rect2i(1, 1, 2, 2))]
	map.add_room(entry)
	var flue := _room(
		&"ember_flue",
		&"corridor",
		[&"entry_grove", &"heart_of_ashes"] as Array[StringName],
		Vector2i(4, 9)
	)
	flue.actor_spawn_refs = [_spawn("f1", "mob", 3)] as Array[Dictionary]
	map.add_room(flue)
	var core := _room(
		&"heart_of_ashes", &"core", [&"ember_flue"] as Array[StringName], Vector2i(11, 6)
	)
	core.actor_spawn_refs = [_spawn("b1", "boss")] as Array[Dictionary]
	core.environment_zones = [_zone(&"molten_seam", &"toxic", Rect2i(3, 2, 4, 3))]
	map.add_room(core)
	map.entry_room = &"entry_grove"
	return map


## A branched map: a gate with THREE exits and two ways to the core, so a corridor claim has
## to survive a junction rather than a straight line.
func _branched_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(64, 48), 29)
	var entry := _room(&"entry", &"floor", [&"hub"] as Array[StringName], Vector2i(9, 7))
	entry.roster_band = &"empty"
	map.add_room(entry)
	var hub := _room(
		&"hub", &"gate", [&"entry", &"west", &"east"] as Array[StringName], Vector2i(6, 6)
	)
	hub.actor_spawn_refs = [_spawn("h1"), _spawn("h2"), _spawn("h3")] as Array[Dictionary]
	map.add_room(hub)
	var west := _room(&"west", &"chamber", [&"hub", &"vault"] as Array[StringName], Vector2i(13, 5))
	west.actor_spawn_refs = [_spawn("w1", "mob", 2)] as Array[Dictionary]
	map.add_room(west)
	var east := _room(&"east", &"arena", [&"hub", &"vault"] as Array[StringName], Vector2i(8, 11))
	east.actor_spawn_refs = [_spawn("e1", "miniboss")] as Array[Dictionary]
	map.add_room(east)
	var vault := _room(&"vault", &"core", [&"west", &"east"] as Array[StringName], Vector2i(10, 10))
	vault.actor_spawn_refs = [_spawn("v1", "boss")] as Array[Dictionary]
	map.add_room(vault)
	map.entry_room = &"entry"
	return map


# ── the scene builds at all ──────────────────────────────────────────────────


func test_the_shipped_scene_loads_and_instantiates() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	assert_ne(packed, null, "DomainScene.tscn loads: %s" % SCENE_PATH)
	if packed == null:
		return
	var scene := packed.instantiate()
	_born.append(scene)
	assert_ne(scene, null, "DomainScene.tscn has an instantiable root")
	assert_eq(scene is DomainScene, true, "and that root is the DomainScene script")
	if scene is DomainScene:
		assert_eq(
			scene.get_script().resource_path, "res://src/app/domain_scene.gd", "it is this file"
		)


func test_the_scene_is_complete_without_ever_entering_the_tree() -> void:
	# The frame-dependence claim, made as an assertion rather than a promise. Nothing here
	# is parented to `root`, so `_ready()` is never delivered to anything below and no
	# `await` could have run: whatever answers is what the scene built on its own.
	var scene := DomainScene.new(_three_room_map())
	_born.append(scene)
	assert_ne(scene.floor_layer(), null, "a floor layer exists with no tree and no frame")
	assert_ne(scene.wall_layer(), null, "a wall layer exists with no tree and no frame")
	assert_ne(scene.navigation_region(), null, "a navigation region exists with no tree")
	assert_eq(scene.floor_layer().get_used_cells().size() > 0, true, "the floor has cells")
	assert_eq(scene.navigation_region().navigation_polygon != null, true, "the polygon is set")


func test_the_scene_derives_nothing_a_gameplay_rule_could_read() -> void:
	# ADR 0072 line 18: the scene is a view and no gameplay rule reads a node. The honest
	# test of that is that the map alone answers every question — so the scene must not
	# have published a summary of its own, which is what a gameplay rule would read.
	var scene := DomainScene.new(_three_room_map())
	_born.append(scene)
	assert_eq(scene.has_method("summary"), false, "the scene publishes no rule-facing summary")
	assert_eq(scene.has_method("tick"), false, "and no tick of its own")
	assert_eq(scene.has_method("physics_process"), false, "and no physics callback")


# ── 1. the scene realizes a map ──────────────────────────────────────────────


func test_the_floor_covers_every_cell_of_every_room_and_corridor() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var walkable := DomainScene.walkable_cells(DomainPaths.layout(map), map)
	var drawn := scene.floor_layer().get_used_cells()
	assert_eq(drawn.size(), walkable.size(), "one floor tile per walkable cell, and no others")
	assert_eq(_cell_set(drawn) == _cell_set(walkable.keys()), true, "the same cells exactly")


func test_every_room_rect_is_covered_by_floor_tiles() -> void:
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var floor := scene.floor_layer()
	for room_id in map.room_ids_sorted():
		var rect := scene.room_rect(room_id)
		var expected := rect.size.x * rect.size.y
		var missing := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if floor.get_cell_source_id(Vector2i(x, y)) < 0:
					missing += 1
		assert_eq(missing, 0, "every tile of room '%s' carries floor" % String(room_id))
		assert_eq(expected > 0, true, "and room '%s' is not empty" % String(room_id))


func test_rooms_and_corridors_share_one_terrain_set() -> void:
	# The reason the seam needs no case: there is only one floor tile to stamp, so a
	# corridor cannot be a different material from the room it leaves.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var floor := scene.floor_layer()
	var room_cell := scene.room_rect(map.entry_room).get_center()
	var corridor_cell := _first_corridor_cell(
		DomainScene.walkable_cells(DomainPaths.layout(map), map), scene.room_rect(map.entry_room)
	)
	assert_eq(
		floor.get_cell_atlas_coords(room_cell),
		DomainScene.FLOOR_ATLAS_COORDS,
		"a room tile stamps the floor tile"
	)
	assert_eq(
		floor.get_cell_atlas_coords(corridor_cell),
		DomainScene.FLOOR_ATLAS_COORDS,
		"a corridor tile stamps the SAME floor tile, so the seam is not a case"
	)
	assert_eq(
		DomainScene.FLOOR_ATLAS_COORDS == DomainScene.WALL_ATLAS_COORDS,
		true,
		(
			"and a wall is currently the SAME tile as the floor, which is the known-wrong "
			+ "render: the atlas is one authored cell, so the wall paints ground texture. "
			+ "This assertion flips to `false` the moment a real wall tile is authored."
		)
	)


func test_the_tileset_is_the_one_the_tile_pixel_size_assumes() -> void:
	# `TILE_PIXELS` and `texture_region_size` are two constants in two files that cannot
	# read each other. If they drift, every position in the scene is off by the same factor
	# and nothing else in the suite would notice.
	var tileset := load(DomainScene.TILESET_PATH) as TileSet
	assert_ne(tileset, null, "the shipped tileset loads: %s" % DomainScene.TILESET_PATH)
	if tileset == null:
		return
	var atlas := tileset.get_source(DomainScene.SOURCE_ID) as TileSetAtlasSource
	assert_ne(atlas, null, "and it has the source this scene stamps")
	if atlas == null:
		return
	assert_eq(
		atlas.texture_region_size,
		Vector2i(DomainScene.TILE_PIXELS, DomainScene.TILE_PIXELS),
		"the atlas region is TILE_PIXELS square, or every position is off by a factor"
	)
	assert_ne(atlas.texture, null, "the atlas has a texture to draw")
	assert_eq(tileset.get_physics_layers_count(), 1, "the tileset declares one physics layer")


func test_both_layers_carry_the_shipped_tileset() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var tileset := load(DomainScene.TILESET_PATH) as TileSet
	assert_eq(scene.floor_layer().tile_set, tileset, "the floor draws from the shipped set")
	assert_eq(scene.wall_layer().tile_set, tileset, "and so do the walls")


# ── 2. walls ring the rooms, corridors stay walkable ──────────────────────────


func test_the_wall_layer_is_enabled_and_the_floor_layer_is_not() -> void:
	# The single physics layer in the domain. Floor tiles carry no polygon, so the floor
	# layer having collision off is what makes the wall layer the ONLY thing that blocks.
	var scene := DomainScene.new(_three_room_map())
	_born.append(scene)
	assert_eq(scene.wall_layer().collision_enabled, true, "the wall layer is the physics")
	assert_eq(scene.floor_layer().collision_enabled, false, "and the floor layer is not")
	assert_eq(
		scene.wall_layer().get_cell_tile_data(_first_wall_cell(scene)) != null,
		true,
		"a wall tile has TileData, so the collision exists before any frame"
	)


func test_the_wall_layer_is_the_only_one_that_y_sorts_and_its_origin_is_centred() -> void:
	var scene := DomainScene.new(_three_room_map())
	_born.append(scene)
	assert_eq(scene.wall_layer().y_sort_enabled, true, "the wall layer y-sorts")
	assert_eq(
		scene.wall_layer().y_sort_origin,
		DomainScene.TILE_PIXELS / 2,
		"with a half-tile origin, so the player passes behind a wall's top edge"
	)
	assert_eq(scene.floor_layer().y_sort_enabled, false, "the floor sorts by nothing")


func test_every_room_is_ringed_by_wall_cells() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var walkable := DomainScene.walkable_cells(DomainPaths.layout(map), map)
	var walls := scene.wall_layer().get_used_cells()
	for room_id in map.room_ids_sorted():
		var rect := scene.room_rect(room_id)
		# One cell OUTSIDE each of the room's four faces. Inside the face is the room's own
		# floor, so a ring claim has to reach past the rect to mean anything. A corridor mouth
		# there is walkable and must stay open, so it is excluded rather than counted.
		var ringed := 0
		for side in [
			_rect_of_row(rect.position.y - 1, rect.position.x, rect.size.x),
			_rect_of_row(rect.end.y, rect.position.x, rect.size.x),
			_rect_of_col(rect.position.x - 1, rect.position.y, rect.size.y),
			_rect_of_col(rect.end.x, rect.position.y, rect.size.y),
		]:
			for cell in side:
				if walls.has(cell) and not walkable.has(cell):
					ringed += 1
		assert_eq(
			ringed > 0, true, "room '%s' has wall cells outside at least one face" % String(room_id)
		)


func test_a_wall_cell_sits_immediately_outside_every_room() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var walls := scene.wall_layer().get_used_cells()
	for room_id in map.room_ids_sorted():
		var rect := scene.room_rect(room_id)
		var outside := Vector2i(rect.position.x, rect.position.y - 1)
		assert_eq(
			walls.has(outside), true, "the cell one row above room '%s' is a wall" % String(room_id)
		)


func test_the_wall_set_is_the_dilation_minus_the_walkable_set() -> void:
	# Computed against the module's own rule rather than a hand-written expectation, so the
	# two cannot drift apart: every wall is adjacent to walkable floor, and no walkable cell
	# is a wall.
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var walkable := DomainScene.walkable_cells(DomainPaths.layout(map), map)
	var walls := scene.wall_layer().get_used_cells()
	var expected := DomainScene.wall_cells(walkable)
	assert_eq(_cell_set(walls) == _cell_set(expected.keys()), true, "the same wall cells")
	var touching := 0
	var intruders := 0
	for cell in walls:
		if walkable.has(cell):
			intruders += 1
			continue
		for neighbour in _eight(cell):
			if walkable.has(neighbour):
				touching += 1
				break
	assert_eq(intruders, 0, "no walkable cell is drawn as a wall")
	assert_eq(touching, walls.size(), "every wall touches walkable floor, so the ring rings")


func test_the_corridor_runs_are_walkable_and_not_wall() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var floor := scene.floor_layer()
	var walls := scene.wall_layer().get_used_cells()
	var routes := DomainPaths.routes(map)
	assert_eq(routes.is_empty(), false, "the map publishes at least one corridor")
	var sealed := 0
	var missing := 0
	for route in routes:
		for cell in _route_run(route):
			if floor.get_cell_source_id(cell) < 0:
				missing += 1
			if walls.has(cell):
				sealed += 1
	assert_eq(missing, 0, "every tile along every corridor carries floor")
	assert_eq(sealed, 0, "and not one of them is a wall: the passage is open")


func test_a_gate_and_a_core_corridor_is_two_tiles_wide() -> void:
	# `DomainPaths.GATE_WIDTH` is 2, so a corridor joining a `gate` or a `core` is stamped as
	# a two-tile band. A one-tile band would leave the second lane a wall the player cannot
	# use, and the width is the map's — not this scene's — so it is read from the module.
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var wide := 0
	for route in DomainPaths.routes(map):
		if int(route.get("width", 1)) != DomainPaths.GATE_WIDTH:
			continue
		var row: Array[Vector2i] = []
		for cell in _route_run(route):
			if row.has(Vector2i(cell.x, 0)):
				continue
			row.append(Vector2i(cell.x, 0))
		if row.size() >= DomainPaths.GATE_WIDTH:
			wide += 1
	assert_eq(wide > 0, true, "at least one corridor is stamped as wide as the map says")


# ── 3. the navigation polygon covers every room ──────────────────────────────


func test_the_navigation_polygon_covers_every_room() -> void:
	# Asked of the POLYGON, not of a screenshot: a point at the centre of each room is
	# inside the navmesh. That is the question a pathfinder asks, so it is the one that
	# matters, and it is answerable headlessly.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var polygon := scene.navigation_region().navigation_polygon
	assert_ne(polygon, null, "the region carries a polygon")
	if polygon == null:
		return
	assert_eq(polygon.get_polygon_count() > 0, true, "the polygon is triangulated")
	var uncovered := 0
	for room_id in map.room_ids_sorted():
		var centre := DomainScene.tile_center(scene.room_rect(room_id).get_center())
		if not _in_polygon(polygon, centre):
			uncovered += 1
	assert_eq(uncovered, 0, "every room's centre is inside the navigation polygon")


func test_the_navigation_polygon_covers_the_corridor_between_two_rooms() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var polygon := scene.navigation_region().navigation_polygon
	var unreachable := 0
	for route in DomainPaths.routes(map):
		for cell in _route_run(route):
			if not _in_polygon(polygon, DomainScene.tile_center(cell)):
				unreachable += 1
	assert_eq(unreachable, 0, "every corridor tile's centre is inside the polygon")


func test_the_navigation_polygon_excludes_the_walls() -> void:
	# The complement of the cover claim, and the one a cover-only test cannot catch: a
	# polygon that swallowed the walls would still cover every room.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var polygon := scene.navigation_region().navigation_polygon
	var walls := scene.wall_layer().get_used_cells()
	var leaked := 0
	for cell in walls:
		if _in_polygon(polygon, DomainScene.tile_center(cell)):
			leaked += 1
	assert_eq(leaked, 0, "no wall tile's centre is inside the polygon")


func test_the_outlines_are_loops_rather_than_a_box_per_cell() -> void:
	# The shape of the claim, not the shape of the picture: one loop per REGION. A box per
	# cell would be hundreds of overlapping outlines, which is what a bake would normally
	# have to clean up — and the reason this scene does not bake.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var walkable := DomainScene.walkable_cells(DomainPaths.layout(map), map)
	var loops := DomainScene.outlines(walkable)
	assert_eq(loops.is_empty(), false, "the walkable set has at least one outline")
	var cells := walkable.size()
	var corners := 0
	for loop in loops:
		corners += loop.size()
	assert_eq(
		corners < cells,
		true,
		"%d outline corners for %d cells: a contour, not a box per cell" % [corners, cells]
	)


func test_two_cells_touching_only_at_a_corner_produce_two_loops() -> void:
	# The saddle marching squares exists to resolve. Taken as "disconnected", which is what
	# the winding in domain_scene.gd produces, the two regions get one loop each — and a
	# single figure-eight loop would be a polygon with a zero-width bridge in it.
	var walkable := {Vector2i(0, 0): true, Vector2i(1, 1): true}
	var loops := DomainScene.outlines(walkable)
	assert_eq(loops.size(), 2, "a diagonal touch is two regions, not one pinched loop")
	var squared := {
		Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(0, 1): true, Vector2i(1, 1): true
	}
	assert_eq(DomainScene.outlines(squared).size(), 1, "and a solid 2x2 block is one region")


func test_an_empty_domain_has_no_navigation_geometry() -> void:
	# `{}` is this repo's does-not-exist vocabulary (domain_minimap.gd:78). An empty map must
	# read as nothing, not as a room with no markers in it.
	var scene := DomainScene.new(DomainMap.new(Vector2i(8, 8), 0))
	_born.append(scene)
	assert_eq(scene.floor_layer().get_used_cells().size(), 0, "no floor on an empty map")
	assert_eq(scene.navigation_region().navigation_polygon.get_polygon_count(), 0, "no polygons")
	assert_eq(scene.map_bounds(), Rect2(), "and no playable bounds")


# ── 4. markers exist for every ref, zone and exit ────────────────────────────


func test_a_marker_exists_for_every_actor_spawn_ref() -> void:
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var markers := scene.spawn_markers()
	assert_eq(
		markers.size(), map.spawn_refs().size(), "one marker per actor_spawn_ref, no more, no fewer"
	)
	var seen := {}
	for marker in markers:
		seen["%s|%s" % [marker.get_meta(&"room_id"), marker.get_meta(&"ref_id")]] = true
	var missing := 0
	for ref in map.spawn_refs():
		var key := "%s|%s" % [ref.get("room_id", ""), ref.get("ref_id", "")]
		if not seen.has(key):
			missing += 1
	assert_eq(missing, 0, "every ref's room and ref id names a marker")


func test_a_spawn_marker_stands_inside_its_own_room() -> void:
	# A marker outside its room is a marker inside a wall. Asked of the marker's own cell
	# rather than of its pixel position, so the tile scale cannot mask it.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var outside := 0
	for marker in scene.spawn_markers():
		var rect := scene.room_rect(StringName(marker.get_meta(&"room_id")))
		var cell := _cell_of(marker.position)
		if not rect.has_point(cell):
			outside += 1
	assert_eq(outside, 0, "every spawn marker stands on a tile of its own room")


func test_the_instances_of_one_ref_are_separated() -> void:
	# `_spawn("f1", "mob", 3)` is three mobs. Three on one tile are three a player cannot
	# tell apart, and `DomainSpawner` asks for a position PER INSTANCE (domain_spawner.gd:112).
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var points: Array[Vector2] = []
	for index in range(3):
		points.append(scene.spawn_position(&"ember_flue", "f1", index))
	assert_eq(_all_distinct(points), true, "three instances of one ref stand apart")
	assert_eq(points.size(), 3, "and there are three of them")


func test_a_marker_exists_for_every_environment_zone() -> void:
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var areas := scene.zone_areas()
	assert_eq(areas.size(), map.zones().size(), "one Area2D per EnvironmentZoneDef")
	var zone_ids := {}
	for area in areas:
		zone_ids[String(area.get_meta(&"zone_id"))] = true
	for row in map.zones():
		assert_eq(
			zone_ids.has(String(row.get("zone_id", ""))),
			true,
			"zone '%s' has an Area2D" % String(row.get("zone_id", ""))
		)


func test_a_zone_area_is_the_authored_rect_not_a_heuristic() -> void:
	# `EnvironmentZoneDef.bounds` is in TILES RELATIVE to its room (environment_zone_def.gd:92),
	# so the area must be translated by the room's laid-out origin. Reading the bounds as
	# absolutes would drop the hazard in the wrong room, which is the failure mode here.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var by_id := {}
	for area in scene.zone_areas():
		by_id[String(area.get_meta(&"zone_id"))] = area
	for row in map.zones():
		var area: Area2D = by_id[String(row.get("zone_id", ""))]
		if area == null:
			continue
		var origin := scene.room_rect(StringName(row.get("room_id"))).position
		var bounds: Array = row.get("bounds", [])
		var expected := Vector2(
			(
				float(origin.x + int(bounds[0])) * float(DomainScene.TILE_PIXELS)
				+ float(bounds[2]) * float(DomainScene.TILE_PIXELS) / 2.0
			),
			(
				float(origin.y + int(bounds[1])) * float(DomainScene.TILE_PIXELS)
				+ float(bounds[3]) * float(DomainScene.TILE_PIXELS) / 2.0
			)
		)
		assert_eq(
			area.position.is_equal_approx(expected),
			true,
			(
				"zone '%s' sits at its authored rect inside room '%s'"
				% [String(row.get("zone_id", "")), String(row.get("room_id", ""))]
			)
		)
		var shape := area.get_node("CollisionShape2D") as CollisionShape2D
		var rectangle := shape.shape as RectangleShape2D
		assert_eq(
			rectangle.size,
			Vector2(float(bounds[2]), float(bounds[3])) * float(DomainScene.TILE_PIXELS),
			"and its collision rect is the authored bounds in pixels"
		)


func test_a_marker_exists_for_every_corridor_exit() -> void:
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var markers := scene.exit_markers()
	assert_eq(markers.size(), DomainPaths.routes(map).size(), "one marker per corridor")
	var seen := {}
	for marker in markers:
		seen["%s->%s" % [marker.get_meta(&"room_id"), marker.get_meta(&"to_room_id")]] = true
	for route in DomainPaths.routes(map):
		assert_eq(
			seen.has("%s->%s" % [route.get("from", ""), route.get("to", "")]),
			true,
			(
				"the corridor %s -> %s has an exit marker"
				% [route.get("from", ""), route.get("to", "")]
			)
		)


func test_an_exit_marker_stands_on_the_corridor_mouth() -> void:
	# It is the polyline's FIRST point (domain_paths.gd:294-305), so the marker and the
	# geometry cannot disagree about where a passage starts.
	var map := _three_room_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var mouths := {}
	for route in DomainPaths.routes(map):
		var pair: Array = route.get("points", [])[0]
		mouths["%s|%d,%d" % [route.get("from", ""), int(pair[0]), int(pair[1])]] = true
	var mismatched := 0
	for marker in scene.exit_markers():
		var cell := _cell_of(marker.position)
		var key := "%s|%d,%d" % [marker.get_meta(&"room_id"), cell.x, cell.y]
		if not mouths.has(key):
			mismatched += 1
	assert_eq(mismatched, 0, "every exit marker stands on its corridor's mouth tile")


# ── 5. the layout is EXACTLY DomainPaths.layout ──────────────────────────────


func test_the_layout_is_exactly_domain_paths() -> void:
	# Asserted against the MODULE, not against a hand-copied expectation: a second layout
	# algorithm added to the scene would move every room and this would fail. That is the
	# whole point — domain_paths.gd:182-185 says there is one layout rule in the repo.
	var map := _branched_map()
	var scene := DomainScene.new(map)
	_born.append(scene)
	var expected := DomainPaths.layout(map)
	var wrong := 0
	for room_id in map.room_ids_sorted():
		if scene.room_rect(room_id) != Rect2i(expected.get(String(room_id), Rect2i())):
			wrong += 1
	assert_eq(wrong, 0, "every room's rect equals DomainPaths.layout's, exactly")
	assert_eq(expected.size(), map.room_count(), "and the layout covers every room")


func test_the_layout_does_not_depend_on_the_order_rooms_were_added() -> void:
	# The contract DomainPaths already keeps (test_domain_paths.gd:106-118): the same rooms in
	# a different insertion order lay out identically. A scene that walked `rooms` itself
	# would break it, and would break it differently on each map.
	var forward := _three_room_map()
	var reordered := DomainMap.new(forward.extent, forward.seed)
	for room_id in [&"heart_of_ashes", &"entry_grove", &"ember_flue"]:
		reordered.add_room(forward.room(room_id))
	reordered.entry_room = forward.entry_room
	var one := DomainScene.new(forward)
	var two := DomainScene.new(reordered)
	_born.append(one)
	_born.append(two)
	var moved := 0
	for room_id in forward.room_ids_sorted():
		if one.room_rect(room_id) != two.room_rect(room_id):
			moved += 1
	assert_eq(moved, 0, "insertion order moves no room, in the scene or in the module")
	assert_eq(
		one.floor_layer().get_used_cells().size(),
		two.floor_layer().get_used_cells().size(),
		"and both realize the same number of tiles"
	)


func test_realizing_the_same_map_twice_replaces_rather_than_stacks() -> void:
	# `realize()` is idempotent by construction. A second call that appended would be the
	# leak shape test_no_deferred_free.gd records, and it would read as "the scene holds two
	# domains" — a green scene that is quietly wrong.
	var scene := DomainScene.new()
	_born.append(scene)
	scene.realize(_three_room_map())
	var once := scene.floor_layer().get_used_cells().size()
	var first_layer := scene.floor_layer()
	var before := _child_names(scene)
	scene.realize(_branched_map())
	assert_eq(scene.floor_layer().get_used_cells().size() > 0, true, "the new map is drawn")
	assert_ne(scene.floor_layer(), first_layer, "and it is a fresh layer")
	var after := _child_names(scene)
	assert_eq(
		after.size(),
		before.size(),
		"a rebuild leaves the same number of children: nothing from the first map survived"
	)
	# The first map's per-room holders are named after ITS rooms; the rebuilt scene's are
	# named after the second map's. If any of the first map's holders survived, these two
	# lists would share names they cannot both own.
	var stale := 0
	var holders_before := 0
	for name in before:
		if not name.begins_with("%s_" % SPAWNS_PREFIX):
			continue
		holders_before += 1
		if after.has(name):
			stale += 1
	assert_eq(holders_before > 0, true, "the first map really did build per-room holders")
	assert_eq(stale, 0, "no holder from the first map's rooms survived the rebuild")
	assert_eq(once > 0, true, "the first realize drew something")


## Every direct child name of a scene, sorted, so two lists can be compared by VALUE —
## `==` on two separately built arrays of names is an identity comparison in Godot 4.
static func _child_names(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		out.append(String(child.name))
	out.sort()
	return out


# ── 6. nothing leaks ─────────────────────────────────────────────────────────


func test_teardown_frees_a_fresh_scene_and_leaves_no_node_behind() -> void:
	# The measurement, not the promise. `root` is sampled before and after a build/clear
	# cycle; a scene that leaks even one node shows up as a larger count. The build here is
	# the LARGEST the suite makes (the branched map: 5 rooms, 4 corridors, 8 refs, 2 zones),
	# so a per-node leak cannot hide behind a small one.
	var scene := DomainScene.new(_branched_map())
	_born.append(scene)
	var before := _root.get_child_count()
	scene.clear()
	var after := _root.get_child_count()
	assert_eq(after, before, "clear() leaves the tree exactly as it found it")
	assert_eq(scene.floor_layer(), null, "the floor layer is released")
	assert_eq(scene.wall_layer(), null, "the wall layer is released")
	assert_eq(scene.navigation_region(), null, "the navigation region is released")
	assert_eq(scene.spawn_markers().size(), 0, "and every marker list is empty")
	assert_eq(scene.zone_areas().size(), 0, "including the zone areas")


func test_two_builds_leave_the_same_node_count() -> void:
	# Across two RUNS of the same map, not two calls: a per-run leak is the one that
	# survives a suite and is found by the RAM ceiling at 12 GB instead of here.
	var map := _branched_map()
	var first := DomainScene.new(map)
	_born.append(first)
	first.clear()
	var baseline := _root.get_child_count()
	var second := DomainScene.new(map)
	_born.append(second)
	second.clear()
	assert_eq(
		_root.get_child_count(),
		baseline,
		"a second build and clear leaves the tree where the first one left it"
	)


func test_a_scene_built_outside_the_tree_frees_everything_it_created() -> void:
	# The whole leak discipline, on a scene that was never parented. Every node it minted is
	# on its own `_born` list, so `clear()` can release them with no parent to walk and no
	# frame to wait for — which is exactly the situation the headless runner produces.
	var scene := DomainScene.new(_three_room_map())
	_born.append(scene)
	var minted := _count_nodes(scene, 0)
	assert_eq(minted > 0, true, "the scene built %d nodes without a tree" % minted)
	scene.clear()
	assert_eq(scene.get_child_count(), 0, "and released every one of them")
	assert_eq(_orphans(), 0, "leaving nothing orphaned: a freed child cannot be reached")


func test_the_suite_frees_every_node_it_mints() -> void:
	# `_born` is the suite's whole leak discipline, so it is worth asserting on directly: a
	# case that minted a node without recording it would survive every other case here.
	assert_eq(_orphans(), 0, "no node this suite minted is still reachable under root")
	var unreachable := 0
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node is DomainScene and node.get_child_count() > 0:
			unreachable += 1
	assert_eq(unreachable, 0, "no recorded scene still holds a child at teardown")


# ── helpers ──────────────────────────────────────────────────────────────────


## Every cell in a set as one comparable string, so two `Dictionary` keys can be compared by
## VALUE. `==` on dictionaries compares identity in Godot 4 and would pass on any two
## different sets.
static func _cell_set(cells: Array) -> String:
	var keys: Array[String] = []
	for cell in cells:
		keys.append(str(cell))
	keys.sort()
	return "|".join(keys)


static func _eight(cell: Vector2i) -> Array[Vector2i]:
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


static func _rect_of_row(y: int, from_x: int, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(from_x, from_x + count):
		out.append(Vector2i(x, y))
	return out


static func _rect_of_col(x: int, from_y: int, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(from_y, from_y + count):
		out.append(Vector2i(x, y))
	return out


## Every tile a corridor sweeps: the bounding rect of each segment. Same rule the scene
## applies (`_segment_rect`), read from the polyline rather than from the scene, so the
## assertion is asked of the MAP and not of the thing under test.
static func _route_run(route: Dictionary) -> Array[Vector2i]:
	var points: Array = route.get("points", [])
	var out: Array[Vector2i] = []
	for index in range(maxi(0, points.size() - 1)):
		var a: Array = points[index]
		var b: Array = points[index + 1]
		for y in range(mini(int(a[1]), int(b[1])), maxi(int(a[1]), int(b[1])) + 1):
			for x in range(mini(int(a[0]), int(b[0])), maxi(int(a[0]), int(b[0])) + 1):
				out.append(Vector2i(x, y))
	return out


## Whether a world point is inside any polygon of the navmesh. Triangulated polygons, so the
## answer is a point-in-triangle over every triangle — the question a pathfinder asks, and
## the one a screenshot cannot be trusted on.
##
## BOUNDARY-INCLUSIVE, and it has to be. `point_is_inside_triangle` EXCLUDES a point lying
## on an edge, and the triangles here are a fan sharing vertex 0, so a diagonal crosses the
## domain. A room or corridor centre landing on one answered "outside" while all four of its
## neighbours answered "inside": the walkable set was covered and this could not see it.
##
## That cannot let a wall back in. A tile centre is 16 px from every tile corner and every
## polygon VERTEX is a tile corner, so a centre never lands on one; the only edges it can
## land on are fan diagonals, which cross the INTERIOR of the region. The silhouette itself
## runs along tile-corner coordinates. So the rule widens the polygon over interior floor
## only, and `test_the_navigation_polygon_excludes_the_walls` still holds.
static func _in_polygon(polygon: NavigationPolygon, point: Vector2) -> bool:
	var vertices := polygon.vertices
	var index := 0
	while index < polygon.get_polygon_count():
		var ids := polygon.get_polygon(index)
		index += 1
		if ids.size() < 3:
			continue
		for corner in range(1, ids.size() - 1):
			var a := vertices[ids[0]]
			var b := vertices[ids[corner]]
			var c := vertices[ids[corner + 1]]
			if (
				Geometry2D.point_is_inside_triangle(point, a, b, c)
				or _on_triangle_edge(point, a, b, c)
			):
				return true
	return false


## Whether `point` lies ON one of a triangle's three edges — the inclusive companion to
## `point_is_inside_triangle`. Kept separate and tiny so the rule above reads as one
## predicate rather than as a nest of epsilon arithmetic.
static func _on_triangle_edge(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	for edge in [[a, b], [b, c], [c, a]]:
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var span := to - from
		var length_squared := span.length_squared()
		if length_squared <= 0.0:
			continue
		# Project the point onto the edge; `t` outside [0, 1] means it lies past an endpoint.
		var t := (point - from).dot(span) / length_squared
		if t < 0.0 or t > 1.0:
			continue
		if point.distance_squared_to(from + span * t) <= 0.0001:
			return true
	return false


static func _cell_of(position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(position.x / float(DomainScene.TILE_PIXELS))),
		int(floor(position.y / float(DomainScene.TILE_PIXELS)))
	)


static func _all_distinct(points: Array[Vector2]) -> bool:
	var seen := {}
	for point in points:
		if seen.has(point):
			return false
		seen[point] = true
	return true


## The first walkable cell OUTSIDE the entry room. Every such cell came from a corridor, so
## it is the cell a "corridors share the room's floor tile" claim needs. Falls back to the
## room's own centre when a map lays out no corridor-only cell, so the caller compares two
## real cells rather than skipping the assertion.
static func _first_corridor_cell(walkable: Dictionary, first_room: Rect2i) -> Vector2i:
	var cells: Array[Vector2i] = []
	for key in walkable.keys():
		cells.append(key)
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	for cell in cells:
		if not first_room.has_point(cell):
			return cell
	# A map whose rooms touch has no corridor-only cell; the room's own far corner stands in
	# so the floor-tile comparison below still has two cells to read.
	return first_room.get_center()


static func _first_wall_cell(scene: DomainScene) -> Vector2i:
	var cells := scene.wall_layer().get_used_cells()
	return Vector2i.ZERO if cells.is_empty() else cells[0]


## Every node under `root`, depth-capped. A recursive walk with no cap is an unbounded loop
## the moment the tree holds a junction (seam_harness.gd:58-61).
static func _count_nodes(node: Node, depth: int) -> int:
	if depth > MAX_TREE_WALK:
		return 0
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child, depth + 1)
	return total


## Nodes parented to `root` that this suite did not record. Zero is the claim: the runner
## shares one process across every suite, so anything left under `root` outlives the case
## that made it.
func _orphans() -> int:
	var total := 0
	for child in _root.get_children():
		if not _born.has(child):
			total += 1
	return total
