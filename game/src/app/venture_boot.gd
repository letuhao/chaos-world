class_name VentureBoot
extends RefCounted

## Composition-side host for the venture route: the demo graph, its configs,
## and the verbs a screen reaches only as Callables.
##
## ## Why the screen never names this file's types
##
## `ui/` may not name `app/` (a private unit) nor any worldmap type except
## through the module facade — and the scene itself is not the facade. So the
## screen holds Callables and plain `Node` handles, and every verb below takes
## the screen as its first argument. The one exception is the return values:
## plain Dictionaries of primitives, never the scene.
##
## ## Why nothing here is remembered
##
## No member, no static: the scene is found by name under the screen that
## shows it (`WORLD_NODE` below), the graph and configs are rebuilt per call
## from constants, and freeing the screen frees the world with it. A second
## reference would be a second thing that can outlive the visit.
##
## The demo is the same three nodes the headless streaming suite walks, so a
## green suite and a played session describe one place: an overworld with a
## doorway into a nested authored cave and a portal to a differently-sized
## far universe.

const WORLD_NODE := "VentureWorld"
const HOLDER_NAME := "WorldHolder"

const NODES: Array[String] = ["overworld", "cave", "far"]
const ENV := "mortal_greenwood"


## Open `node_id` under the screen's holder, freeing whatever stood there.
## Refuses an unknown node by name; a half-opened node is reported, never shown.
## A saved position for the node resumes it (falling back to the entry when
## the ground moved), and saved mutations import before anything renders.
static func open(screen: Control, node_id: String) -> Dictionary:
	if screen == null:
		return {"ok": false, "reason": "no_surface"}
	if not NODES.has(node_id):
		return {"ok": false, "reason": "unknown_node", "node": node_id}
	var holder := screen.get_node_or_null("%" + HOLDER_NAME)
	if holder == null:
		return {"ok": false, "reason": "no_surface"}
	close(screen)
	var graph := _demo_graph()
	var configs := _demo_configs()
	var scene := WorldmapScene.new()
	scene.name = WORLD_NODE
	holder.add_child(scene)
	var outcome := scene.open(graph, node_id, configs)
	if not bool(outcome.get("ok", false)):
		scene.free()
		return outcome
	_restore(scene, node_id)
	return {"ok": true, "reason": "", "node": node_id}


## Free the world under the screen. Mutations ride out to the ledger first:
## closing is the last verb that sees them. Idempotent: closing nothing
## reports `{"ok": true, "freed": 0}` rather than failing a teardown that
## calls twice.
static func close(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": true, "reason": "", "freed": 0}
	_persist(scene)
	scene.free()
	return {"ok": true, "reason": "", "freed": 1}


## Step the player one cell. Records the resume point afterwards: a step is
## the one verb that always moves it. Unopened reads as refused, not a crash.
## A step onto an encounter marker rolls the encounter module (location is
## the node id; the marker says WHERE, the module decides WHAT): the outcome
## carries an `encounter` block (`{id, fates}`) or `{}` when the wild stays
## quiet. Rolls use a per-cell deterministic seed, so the same cell offers
## the same encounter on every visit — farmable only as far as the module's
## seen/cooldown ledgers allow (all three authored defs are unique: once ever
## each).
static func step(screen: Control, dx: int, dy: int) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"moved": false, "traveled": false, "reason": "unopened"}
	var outcome := scene.step(dx, dy)
	if bool(outcome.get("moved", false)):
		_record_position(scene)
	if bool(outcome.get("moved", false)) and not bool(outcome.get("traveled", false)):
		outcome["encounter"] = _maybe_encounter(screen, scene)
	else:
		outcome["encounter"] = {}
	return outcome


## Roll an encounter when the player's cell carries a marker. Returns `{}` or
## `{id, fates}` with fate ids as Strings. No actor, no marker, no roll:
## each refusal is silent, because an empty cell owes no explanation.
static func _maybe_encounter(screen: Control, scene: WorldmapScene) -> Dictionary:
	var actor := screen.call("actor") as Actor
	if actor == null:
		return {}
	var summary := scene.debug_summary()
	if not (summary.get("domain", {}) as Dictionary).is_empty():
		return {}
	var node := String(summary.get("node", ""))
	var cell := scene.player_cell()
	if not _marked(scene, node, cell):
		return {}
	EncounterApi.attach(actor)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d,%d" % [node, cell.x, cell.y])
	var rolled := EncounterApi.trigger_encounter(actor, StringName(node), 0, rng)
	if not bool(rolled.get("triggered", false)):
		return {}
	var fates: Array = []
	for fate in rolled.get("fate_choices", []) as Array:
		fates.append(String(fate))
	return {"id": String(rolled.get("encounter_id", "")), "fates": fates}


## Whether the map cell carries an encounter marker. Reads the metadata POIs
## of the player's chunk from the data cache — generating nothing, since a
## stood-on chunk is always cached.
static func _marked(scene: WorldmapScene, node: String, cell: Vector2i) -> bool:
	var streamer := scene.streamer()
	if streamer == null:
		return false
	var size := int(scene.debug_summary().get("chunk_size", 8))
	var cc := Vector2i(floori(float(cell.x) / size), floori(float(cell.y) / size))
	var chunk := streamer.chunk_data(
		node, cc.x, cc.y, size, int(scene.debug_summary().get("seed", 0))
	)
	var meta := chunk.layers.get("metadata", {}) as Dictionary
	for poi in meta.get("pois", []) as Array:
		var row := poi as Dictionary
		if String(row.get("kind", "")) != "encounter":
			continue
		var at := row.get("cell", []) as Array
		if int(at[0]) == cell.x - cc.x * size and int(at[1]) == cell.y - cc.y * size:
			return true
	return false


## Answer a pending encounter with a fate choice, or walk away from it.
## Returns the module's own verdict; clearing the pending offer is the
## screen's half, which is why this answers rather than stores.
static func answer_fate(screen: Control, encounter_id: String, fate_index: int) -> Dictionary:
	var actor := screen.call("actor") as Actor
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return EncounterApi.resolve_encounter(actor, StringName(encounter_id), fate_index)


## Walk away from a pending encounter without choosing. The module records
## the dismissal; a unique encounter will not offer again.
static func dismiss_encounter(screen: Control, encounter_id: String) -> Dictionary:
	var actor := screen.call("actor") as Actor
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return EncounterApi.dismiss_encounter(actor, StringName(encounter_id))


## Destroy whatever the player's cell masks. Mutations ride out to the ledger
## at once: a hole is the one change a quit must never lose. Unopened refuses
## by the same name.
static func destroy(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened", "freed": 0}
	var outcome := scene.destroy_at(scene.player_cell())
	if bool(outcome.get("ok", false)):
		_persist(scene)
	return outcome


## Raise a blocker where the player stands. The overlay rides out to the
## ledger at once, like a hole: what is built must outlive the visit.
## Unopened refuses by the same name.
static func build(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	var outcome := scene.build_at(scene.player_cell())
	if bool(outcome.get("ok", false)):
		_persist(scene)
		_record_position(scene)
	return outcome


## Leave the domain node and stand back on the exact cell left from.
## Records the resume point: the return is a move. Unopened refuses by the
## same name; above ground refuses `not_inside`.
static func return_from_domain(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	var outcome := scene.return_from_domain()
	if bool(outcome.get("ok", false)):
		_record_position(scene)
	return outcome


## Trade one blow with the live boss through the production exchange. The
## seed derives from the player's cell, so the same cell is the same fight
## and two cells are not handed the same roll. Unopened refuses by the same
## name; outside a band the module names why.
static func strike(screen: Control) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	var actor := screen.call("actor") as Actor
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var cell := scene.player_cell()
	return CombatApi.exchange(actor, hash("%d,%d" % [cell.x, cell.y]))


## Take every claimable drop of a defeated boss. The encounter id arrives
## from the strike that felled it; the screen holds it, this only spends it.
## Unopened refuses by the same name.
static func take(screen: Control, encounter_id: String) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	var actor := screen.call("actor") as Actor
	if actor == null:
		return {"ok": false, "status": "refused", "reason": "no_actor"}
	return LootApi.pickup_all(actor, StringName(encounter_id))


## Show or hide the debug painting on the world under the screen. Unopened
## refuses by the same name as every other verb here.
static func set_debug(screen: Control, enabled: bool) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	return scene.set_debug(enabled)


## The venture read model, primitives only: demo nodes, open state, and the
## live world's own debug summary trimmed to strings and arrays. `{}`
## answers nothing: an unopened screen reports its nodes and `open: false`.
static func read(screen: Control) -> Dictionary:
	var view := {"nodes": NODES.duplicate(), "open": false}
	var scene := _scene_of(screen)
	if scene == null:
		return view
	view["open"] = true
	var summary := scene.debug_summary()
	view["node"] = String(summary.get("node", ""))
	view["player_cell"] = (summary.get("player_cell", [0, 0]) as Array).duplicate()
	view["holders"] = (summary.get("holders", []) as Array).duplicate()
	var edges: Array = []
	for edge in summary.get("edges", []) as Array:
		var row := edge as Dictionary
		var from_cell := row.get("from_cell", Vector2i(-1, -1)) as Vector2i
		var to_cell := row.get("to_cell", Vector2i(-1, -1)) as Vector2i
		(
			edges
			. append(
				{
					"to": String(row.get("to", "")),
					"kind": String(row.get("kind", "")),
					"hook": String(row.get("hook", "")),
					"from_cell": [from_cell.x, from_cell.y],
					"to_cell": [to_cell.x, to_cell.y],
				}
			)
		)
	view["edges"] = edges
	view["seed"] = int(summary.get("seed", 0))
	view["passes"] = (summary.get("passes", []) as Array).duplicate()
	view["pois"] = (summary.get("pois", []) as Array).duplicate(true)
	view["debug"] = bool(summary.get("debug_borders", false))
	view["simulated"] = (
		((summary.get("streamer", {}) as Dictionary).get("simulated", []) as Array).duplicate()
	)
	view["ranges"] = {
		"data": int((summary.get("streamer", {}) as Dictionary).get("data_radius", 0)),
		"sim": int((summary.get("streamer", {}) as Dictionary).get("sim_radius", 0)),
		"scene": int((summary.get("streamer", {}) as Dictionary).get("scene_radius", 0)),
		"render": int((summary.get("streamer", {}) as Dictionary).get("render_radius", 0)),
	}
	view["loaded"] = (
		((summary.get("streamer", {}) as Dictionary).get("loaded", []) as Array).duplicate()
	)
	view["domain"] = (summary.get("domain", {}) as Dictionary).duplicate(true)
	return view


## Drive a non-seamless arrival through the loading screen: mount the real
## loading scene as an overlay, hang its art, then stream the arrival data
## neighborhood with the bar telling the truth about chunks done of total.
## Synchronous by necessity — travel resolves inside one step call, and
## navigating the stack mid-step is the freed-button hazard, so the cutscene
## plays here instead of on the loading route. Returns `{ok}` when the far
## side is fully generated; the overlay is always freed, arrived or refused.
static func transition(
	screen: Control, from_node: String, to_node: String, edge: Dictionary
) -> Dictionary:
	var scene := _scene_of(screen)
	if scene == null:
		return {"ok": false, "reason": "unopened"}
	var packed := load("res://src/ui/screens/loading_screen.tscn") as PackedScene
	if packed == null:
		return {"ok": false, "reason": "no_loading_scene"}
	var overlay := packed.instantiate() as Control
	if overlay == null:
		return {"ok": false, "reason": "no_loading_scene"}
	overlay.name = "VentureTransition"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(overlay)
	overlay.call(
		"set_layers",
		"res://assets/loading/loading_wallpaper.png",
		"res://assets/loading/fairy.png",
		"res://assets/loading/sword.png"
	)
	var configs := _demo_configs()
	if not configs.has(to_node):
		overlay.free()
		return {"ok": false, "reason": "unknown_node"}
	var arrival := configs[to_node] as Dictionary
	var to_cell := (edge as Dictionary).get("to_cell", Vector2i.ZERO) as Vector2i
	var size := maxi(2, int(arrival.get("chunk_size", 8)))
	var focus := Vector2i(floori(float(to_cell.x) / size), floori(float(to_cell.y) / size))
	var radius := maxi(0, int(arrival.get("data_radius", 1)))
	var streamer := scene.streamer()
	var bar := overlay.get_node_or_null("%LoadBar") as ProgressBar
	var status := overlay.get_node_or_null("%StatusLabel") as Label
	var targets: Array = []
	for offset in streamer.neighborhood(focus.x, focus.y, radius):
		targets.append(offset)
	if bar != null:
		bar.max_value = maxi(1, targets.size())
		bar.value = 0
	var done := 0
	for coord in targets:
		var at := coord as Vector2i
		streamer.chunk_data(to_node, at.x, at.y, size, int(arrival.get("seed", 0)))
		done += 1
		if bar != null:
			bar.value = done
		if status != null:
			status.text = "Crossing to %s… %d of %d." % [to_node, done, targets.size()]
	overlay.free()
	return {"ok": true, "reason": "", "from": from_node, "to": to_node, "chunks": done}


static func _scene_of(screen: Control) -> WorldmapScene:
	if screen == null:
		return null
	var holder := screen.get_node_or_null("%" + HOLDER_NAME)
	if holder == null:
		return null
	return holder.get_node_or_null(NodePath(WORLD_NODE)) as WorldmapScene


## The installed worldmap ledger, or null when nobody installed one (a
## headless probe driving the boot directly). Missing is skipped, never
## fabricated: writing a resume into nothing is how a position is believed
## saved and is not.
static func _ledger() -> WorldmapLedger:
	return SaveApi.store_for(WorldmapLedger.WORLD_KEY) as WorldmapLedger


## Copy the scene's overlay and resume point into the ledger. Mutations and
## position ride the next autosave from there; this only stages them.
static func _persist(scene: WorldmapScene) -> void:
	var ledger := _ledger()
	if ledger == null:
		return
	var overlay := scene.streamer().export_mutations()
	var cell := scene.player_cell()
	var stored := ledger.read_ledger()
	stored["mutations"] = overlay
	stored["position"] = {"node": scene.debug_summary().get("node", ""), "cell": [cell.x, cell.y]}
	ledger.write_ledger(stored)


## Record the resume point alone. Steps and returns move it; the overlay only
## moves on destruction, so this stays cheap enough to run per step.
static func _record_position(scene: WorldmapScene) -> void:
	var ledger := _ledger()
	if ledger == null:
		return
	var stored := ledger.read_ledger()
	var cell := scene.player_cell()
	stored["position"] = {"node": scene.debug_summary().get("node", ""), "cell": [cell.x, cell.y]}
	ledger.write_ledger(stored)


## Restore a saved session into a freshly opened scene: mutations first (so
## the ground renders broken), then the resume point for the opened node.
## Anything absent restores nothing; a stale cell falls back to the entry.
static func _restore(scene: WorldmapScene, node_id: String) -> void:
	var ledger := _ledger()
	if ledger == null:
		return
	var stored := ledger.read_ledger()
	scene.streamer().import_mutations(stored.get("mutations", {}) as Dictionary)
	var position := stored.get("position", {}) as Dictionary
	if String(position.get("node", "")) != node_id:
		return
	var cell := position.get("cell", []) as Array
	if cell.size() != 2:
		return
	scene.warp(Vector2i(int(cell[0]), int(cell[1])))


## The demo graph. Rebuilt per call from constants: places change rarely and
## are read by every verb, and a shared graph would be shared mutable state.
static func _demo_graph() -> WorldmapGraph:
	var graph := WorldmapGraph.new()
	graph.add_node({"id": "overworld", "kind": &"wilderness", "parent": ""})
	graph.add_node({"id": "cave", "kind": &"dungeon", "parent": "overworld"})
	graph.add_node({"id": "far", "kind": &"universe", "parent": ""})
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "cave",
				"kind": &"doorway",
				"from_cell": Vector2i(3, 1),
				"to_cell": Vector2i(1, 1),
			}
		)
	)
	(
		graph
		. add_edge(
			{
				"from": "overworld",
				"to": "far",
				"kind": &"portal",
				"from_cell": Vector2i(5, 5),
				"to_cell": Vector2i(2, 1),
				"hook": "toll_bridge",
				"toll": {"amount": 5},
			}
		)
	)
	# The way back: portals are round trips at the same pads, so no walk can
	# strand the player on the far side with no way home.
	(
		graph
		. add_edge(
			{
				"from": "far",
				"to": "overworld",
				"kind": &"portal",
				"from_cell": Vector2i(2, 1),
				"to_cell": Vector2i(5, 5),
			}
		)
	)
	return graph


static func _demo_configs() -> Dictionary:
	return {
		"overworld":
		{
			"environment": ENV,
			"chunk_size": 8,
			"seed": 1234,
			"entry_row": 1,
			"data_radius": 2,
			"scene_radius": 1,
			"scatter":
			[
				{"archetype": "flora.shrub", "density": 0.05, "blocking": true},
				{"archetype": "flora.flower_cluster", "density": 0.08, "blocking": false},
			],
			# Wild ground: markers the step answers with real encounter rolls.
			"encounter_tables": [{"id": "wilds", "weight": 1.0}],
			"encounter_density": 0.25,
		},
		"cave":
		{
			"environment": ENV,
			"chunk_size": 6,
			"seed": 99,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"water": false,
			"authored_terrain": _flat_ground(6),
			"scatter":
			[
				{"archetype": "stone_and_ore.small_rock", "density": 0.3, "blocking": true},
			],
			# Slice 3: the cave is a REAL run, not painted ground. Arriving
			# here descends through the installed seam into this template at
			# this seed; the chunks above stay the threshold a direct open shows.
			# Boss runtime: the same descent enters the storm-phoenix band at
			# tier 1, so the cave holds a fight that pays.
			"domain_template": "ember_grotto",
			"domain_seed": 20261003,
			"loot_domain": "amulet_storm_phoenix_domain",
			"loot_tier": 1,
		},
		"far":
		# A second environment across the portal: the far side renders
		# plains ground under the same pipeline, so the demo proves one
		# graph spanning two looks, two chunk sizes and two seeds. The
		# arrival is NOT seamless: crossing plays the loading screen
		{
			# through the installed transition hook (DEF-0374).
			"environment": "mortal_plains",
			"seamless": false,
			"chunk_size": 12,
			"seed": 7,
			"entry_row": 1,
			"data_radius": 1,
			"scene_radius": 1,
			"scatter": [],
		},
	}


static func _flat_ground(size: int) -> Array:
	var rows: Array = []
	for _y in size:
		var row: Array = []
		for _x in size:
			row.append("ground_tile.base_ground")
		rows.append(row)
	return rows
