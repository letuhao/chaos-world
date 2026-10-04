class_name DomainWorld
extends RefCounted

## The REALIZED WORLD: the `Node2D` subtree `DomainBoot.realize_world` stands up
## under a screen, and the four verbs that build, free and read it.
##
## ## Why this is a SIBLING and not part of `DomainScene`
##
## Extracted from `domain_scene.gd` because that file passed the thousand-line
## ceiling. The cut is the one the file's own tail banner already declared:
## everything from that banner down is `static` and touches only the tree, never an
## instance's fields. `DomainScene` is the VIEW of one `DomainMap` — it builds tiles,
## markers and a navigation polygon for the map it holds. This file is the world
## CONTAINING such a view, plus one body per inhabitant and one player.
##
## It is a `RefCounted` helper rather than a base of `DomainScene` on purpose: the
## five verbs below are `static` and are called through [LootDomainBoot] and through
## `app/`, never on a scene instance. Nothing here reads or writes a
## `DomainScene`'s private fields, so there is no state to inherit and no reason for a
## scene to BE one of these.
##
## ## The NAMES below are `DomainScene`'s, unchanged, and that is the point
##
## `DomainBoot.realize_world` / `release_world` / `world_realized` /
## `world_summary` / `place_inhabitants` / `place_player` reach these bodies, and
## `DomainScene` keeps its own statics as one-line forwards so both spellings work.
## **No public method was renamed and no caller had to change:** the documented entry
## point for the four world verbs remains `DomainBoot`, and `DomainScene.<name>(...)`
## still resolves because the forward is declared on the class the name names.
##
## That last part is the reason the statics are re-declared rather than moved. GDScript
## has no way to alias a static from one script onto another, so the only shapes that keep
## `DomainScene.release_world(...)` compiling are (a) leaving each body on
## `DomainScene`, or (b) a one-line forward from it. (b) is chosen because it also keeps
## the ~40 lines of rationale next to the code it explains, and takes the bodies out of
## the view class. A one-line forward is not a behaviour change: same arguments, same
## return dictionary, same free path.
##
## ## Why `WORLD_BORN` and friends are declared HERE and not shared
##
## The names a realized world publishes (`DomainWorld`, `DomainScene`, `DomainPlayer`,
## `DomainInhabitants`) are the CONTRACT between the three parties that meet in the
## tree: this file builds them, `DomainBoot` never names them, and a probe reads them
## back through [method world_summary]. They are engine strings, so declaring them once
## here and once on `DomainScene` (a sibling may not reference this file's constants)
## is the same mirror-with-the-same-values arrangement `LootContent` uses for
## `BOSS_DIR` and friends.

## The realized world, by name. [method realize_world] builds a `Node2D` under a parent
## the CALLER chose, so the composition root owns the node that draws the world and the
## world goes away with it; these four names are how anyone finds it afterwards.
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

# ── the realized world. Built here, parented by the caller, freed by the caller ──
#
# Everything below is `static` on this class rather than on `DomainBoot`, because it is the
# ENGINE side of a `DomainMap` and this is the engine file: `DomainScene` already owns "where
# is this map in pixels", and a world that had to ask a different class where its own tiles
# are has split one question in two. It is also here so the run's STATE stays out of `app/`:
# `app_state_signals` fires on two of {persistence, tick-loop, state-table} in a file under
# `app/`, and `DomainBoot` already carries `persistence`. The roster arrives here as an
# ARGUMENT, so this file has no `module_data` call, no `Array` member and no tick — it cannot
# become a second thing that knows what is standing where. And no `_ready`, no `await`, no
# deferred work: the adapter is configured by EXPLICIT setters.


## REALIZE `map` as a walkable world under `parent` — the production call that makes this
## class reachable at all. Three things, in order: a `DomainScene` built from the map
## itself; ONE body per inhabitant in `inhabitants`, at the position
## [method DomainSpawner.placement] ALREADY recorded on that `Actor`; and a `PlayerAdapter`
## at the entry centre, bounded to the drawn cells by [method DomainScene.map_bounds].
##
## Named `realize_world`, NOT `realize`: the instance `DomainScene.realize` already owns that
## word for the map-only build `_init()` calls, and GDScript rejects a redefined function
## outright — so the overload would have cost that file its `class_name`.
##
## ## Why the placements are REUSED and never re-derived
##
## The spawner resolved each slot and wrote it into `actor.module_data`, which round-trips
## through `Actor.to_dict()`. Reading it back is what makes the drawn world and the saved
## world the same world; a second placement rule would produce two answers that agree until a
## load, and then only one of them.
##
## Refuses `no_parent`, `no_map` and `no_actor` BY NAME and writes NOTHING before all three
## resolve, so a refusal leaves the caller's tree exactly as it found it. A second call frees
## the previous world first ([method release_world]), so re-entering cannot stack a second
## set of floor tiles under a second set of inhabitants.
static func realize_world(
	parent: Node, map: DomainMap, player: Actor, inhabitants: Array
) -> Dictionary:
	if parent == null:
		return {"ok": false, "reason": "no_parent"}
	if map == null:
		return {"ok": false, "reason": "no_map"}
	if player == null:
		return {"ok": false, "reason": "no_actor"}
	release_world(parent)
	var world := Node2D.new()
	world.name = WORLD_NODE
	parent.add_child(world)
	var scene := DomainScene.new(map)
	scene.name = WORLD_SCENE_NODE
	world.add_child(scene)
	var bodies := place_inhabitants(world, inhabitants)
	place_player(world, player, scene)
	return {
		"ok": true,
		"reason": "",
		"world": world,
		"scene": scene,
		"player": world.get_node_or_null(NodePath(WORLD_PLAYER_NODE)) as PlayerAdapter,
		"bounds": scene.map_bounds(),
		"entry": [scene.entry_position().x, scene.entry_position().y],
		"inhabitants_placed": bodies,
	}


## One body per inhabitant in `inhabitants`, at the placement the spawner recorded on it,
## carrying that same `Actor` plus the room and role the spawner stamped.
##
## A bare `Node2D` and not a sprite, a `CharacterBody2D` or a physics body: what a caller
## needs is a node that EXISTS at the recorded point and names who stands there, and a body
## that could be collided or damaged would be a second inhabitant simulation — a shape the
## `domain` module owns and this file does not.
static func place_inhabitants(world: Node2D, inhabitants: Array) -> int:
	if world == null or inhabitants.is_empty():
		return 0
	var holder := world.get_node_or_null(NodePath(WORLD_INHABITANTS_NODE)) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = WORLD_INHABITANTS_NODE
		world.add_child(holder)
	var placed := 0
	for inhabitant in inhabitants:
		var actor := inhabitant as Actor
		if actor == null:
			continue
		var body := Node2D.new()
		body.name = "Inhabitant_%s" % String(actor.id)
		body.position = DomainSpawner.placement(actor)
		body.set_meta(&"actor", actor)
		body.set_meta(&"room_id", String(DomainSpawner.room_of(actor)))
		body.set_meta(&"role", String(DomainSpawner.role_of(actor)))
		holder.add_child(body)
		placed += 1
	return placed


## Put a `PlayerAdapter` for `player` into `world` at the entry centre, bounded to the
## cells the floor actually drew.
##
## `set_map_bounds` is the seam [method DomainScene.map_bounds] exists for, applied through
## the EXPLICIT setter rather than by relying on `_ready()` — which the runner never delivers
## to a node under `root`, so an adapter that bound itself there would stand up in a running
## game and never in a test. Idempotent: an adapter already standing is returned, not doubled.
static func place_player(world: Node2D, player: Actor, scene: DomainScene) -> PlayerAdapter:
	if world == null or player == null:
		return null
	var existing := world.get_node_or_null(NodePath(WORLD_PLAYER_NODE)) as PlayerAdapter
	if existing != null:
		return existing
	var body := PlayerAdapter.new(player)
	body.name = WORLD_PLAYER_NODE
	world.add_child(body)
	if scene != null:
		body.set_map_bounds(scene.map_bounds())
		body.global_position = scene.entry_position()
	return body


## FREE the realized world under `parent`. Idempotent, and a no-op when nothing was ever
## realized, so a `teardown()` may call it without asking first.
##
## `remove_child()` then `free()`, NEVER `queue_free()`: the runner never processes a frame,
## so a deferred free leaks for the life of the process — the shape that took a run to 67 GB
## and forced a power-cycle (INC-0004/0005), and what
## `tests/arch_rules/test_no_deferred_free.gd` rejects in `res://src`. Every node created
## here is named in [constant WORLD_BORN], so the free is bounded AND self-describing: the
## root goes last, and `stranded` reports any child that was NOT in that list.
static func release_world(parent: Node) -> Dictionary:
	if parent == null:
		return {"ok": false, "reason": "no_parent", "freed": 0}
	var world := parent.get_node_or_null(NodePath(WORLD_NODE))
	if world == null:
		return {"ok": true, "reason": "", "freed": 0, "present": false}
	var freed := 0
	for child_name in WORLD_BORN:
		var child := world.get_node_or_null(NodePath(child_name))
		if child == null:
			continue
		world.remove_child(child)
		child.free()
		freed += 1
	var stranded := world.get_child_count()
	parent.remove_child(world)
	world.free()
	return {"ok": true, "reason": "", "freed": freed, "stranded": stranded, "present": true}


## Whether a world is currently realized under `parent` — the one question a caller and a
## test both ask, asked of the name this file publishes rather than of a tree walk neither
## can describe.
static func world_realized(parent: Node) -> bool:
	return parent != null and parent.get_node_or_null(NodePath(WORLD_NODE)) != null


## The realized world's read model, primitives only: what is drawn, who is standing in it,
## where, and whether a player is in it. Every value is coerced because a `summary()` holding
## a `Node2D` or a `Rect2` is a testable surface that quietly stops being testable.
##
## `{}` when nothing is realized — the repo's does-not-exist vocabulary, so "no world" can
## never read like "a world with no inhabitants in it".
static func world_summary(parent: Node) -> Dictionary:
	if not world_realized(parent):
		return {}
	var world := parent.get_node_or_null(NodePath(WORLD_NODE))
	if world == null:
		return {}
	var scene := world.get_node_or_null(NodePath(WORLD_SCENE_NODE)) as DomainScene
	var player := world.get_node_or_null(NodePath(WORLD_PLAYER_NODE)) as PlayerAdapter
	var bodies := 0
	var placed: Array = []
	var holder := world.get_node_or_null(NodePath(WORLD_INHABITANTS_NODE))
	if holder != null:
		for body in holder.get_children():
			if not body is Node2D:
				continue
			bodies += 1
			var point := (body as Node2D).position
			placed.append([point.x, point.y])
	var bounds := Rect2()
	var entry := Vector2.ZERO
	if scene != null:
		bounds = scene.map_bounds()
		entry = scene.entry_position()
	var stand := Vector2.ZERO
	if player != null:
		stand = player.global_position
	return {
		"realized": true,
		"floor_cells": scene.floor_layer().get_used_cells().size() if scene != null else 0,
		"wall_cells": scene.wall_layer().get_used_cells().size() if scene != null else 0,
		"spawn_markers": scene.spawn_markers().size() if scene != null else 0,
		"zone_areas": scene.zone_areas().size() if scene != null else 0,
		"has_navigation": scene != null and scene.navigation_region() != null,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"entry": [entry.x, entry.y],
		"has_player": player != null,
		"player_position": [stand.x, stand.y],
		"inhabitant_bodies": bodies,
		"inhabitant_positions": placed,
	}
