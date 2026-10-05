class_name NpcRegistry
extends RefCounted

## The live-actor index for npcs present RIGHT NOW (ADR 0077).
##
## **This holds no persistent truth.** The roster ledger in the player actor is the truth;
## this is rebuilt from it and cleared on room unload. Keeping it separate is what lets a
## transient npc exist with no roster entry at all: `present` is a runtime fact about this
## room visit, not a thing that survives the visit.
##
## **Keyed by instance, not by def id.** A room may hold eight drifters minted from one
## `NpcDef`, and "who is here" has to be able to name all eight. The roster keeps its own
## stable `npc_id` for the individuals it remembers; this table uses a `def_id#n`
## instance key so two casts of the same species never collide and evict each other.
##
## It is a module singleton, never `app/` state — `app/` wires, it does not own a table.

static var _shared: NpcRegistry = null

var _live: Dictionary = {}
## Where each live actor was minted, keyed by the same instance key as `_live`.
## NOT part of `_live` itself: `Actor` has no place field, and a tracked npc's place is
## already remembered on its roster entry — this is how the UNTRACKED one (which has no
## roster entry at all) records where it was stood up, so a location read can find it
## (ADR 0092, BL-0715). A row that records no place is invisible to a filtered read.
var _locations: Dictionary = {}
var _instance_counts: Dictionary = {}


static func instance() -> NpcRegistry:
	if _shared == null:
		_shared = NpcRegistry.new()
	return _shared


## A fresh instance key for `def_id`, counting up from 1. Deterministic per room load and
## never unbounded: `release_all` resets the counters with the table.
func next_instance_key(def_id: StringName) -> StringName:
	var count := int(_instance_counts.get(String(def_id), 0)) + 1
	_instance_counts[String(def_id)] = count
	return StringName("%s#%d" % [String(def_id), count])


## `set_present` and the instance key are minted together by `NpcApi.spawn`, so the
## location is a second write rather than a separate verb: a caller that forgot it would
## record a body standing nowhere, which is the shape of BL-0715.
func set_present(instance_key: StringName, actor: Actor, location_id: StringName = &"") -> void:
	_live[String(instance_key)] = actor
	_locations[String(instance_key)] = location_id


## Where the body behind `instance_key` was minted. Empty when it was stood up without
## naming a place, and an empty `location_id` is also what a "everywhere" read asks
## for — so this never rejects an id, it only answers.
func location_of(instance_key: StringName) -> StringName:
	return _locations.get(String(instance_key), &"")


func present(instance_key: StringName) -> Actor:
	return _live.get(String(instance_key))


func is_present(instance_key: StringName) -> bool:
	return _live.has(String(instance_key))


func present_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _live.keys():
		out.append(StringName(key))
	out.sort()
	return out


func present_count() -> int:
	return _live.size()


## Drop an npc from this room. Returns the actor that was released so a caller can free
## the node it owned; an unknown instance key returns null and is not an error.
func release(instance_key: StringName) -> Actor:
	if not _live.has(String(instance_key)):
		return null
	var actor: Actor = _live[String(instance_key)]
	_live.erase(String(instance_key))
	# The place goes with the body. Leaving it behind would grow the table with rows no
	# live actor answers for — an unbounded dict cleaned only by `release_all`.
	_locations.erase(String(instance_key))
	return actor


## Clear every live npc. Called on room unload. Bounded by the live table itself, so this
## is a single pass and not a loop that could fail to terminate.
func release_all() -> int:
	var count := _live.size()
	_live.clear()
	_locations.clear()
	_instance_counts.clear()
	return count


func reset() -> void:
	_live.clear()
	_locations.clear()
	_instance_counts.clear()
