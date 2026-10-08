class_name ConsumableLedger
extends RefCounted

## The per-run attrition record, on `actor.module_data` under [constant MODULE_KEY]
## (ADR 0276, ADR 0027). Primitives only, so `Actor.to_dict()` / `from_dict()` carries it
## with no bespoke save path.
##
## ## WHAT THIS LEDGER IS NOT: the levels
##
## The levels live on a `ResourcePool` per resource id, on `actor.resources`, which is
## where ADR 0276 puts them and where `Actor.to_dict()` already serialises them. Copying
## `current` into here as well would be a second answer to "how much food is left" that
## a save could desynchronise from the first — the ADR 0066 failure, in a place where the
## two copies would drift on every room entry. So this record holds only what a pool
## cannot: how deep the run has gone, which room it last paid on, and how many rooms each
## resource has spent at zero. That last one is the fact no pool carries — a full pool and
## a pool that has just been refilled from empty are the same `ResourcePool`, and a screen
## needs to be able to tell them apart.
##
## ## EVERY KEY IS A STRING, at every depth
##
## `Actor.to_dict()` stringifies only the TOP-level `module_data` keys, so a nested
## `StringName` key survives `to_dict()` and then comes back from
## `JSON.parse_string` as a `String`. Reading `empty_rooms` through a `StringName` key
## would therefore work on a fresh actor and read `0` on a restored one — a defect that
## only shows up after a load, which is the worst place to find one. Nested keys are
## written and read as `String` from the start, so both spellings are the same dictionary.
##
## ## Normalised on read, so an older payload loads
##
## [method normalize] is the single place that decides what an unusable value means, the
## rule `DomainRun.normalize` and `DomainFixtures._record_of` already follow: every field
## goes through `int()` / `String()` because a save has no bools and no int/float
## distinction, and a payload written before a field existed loads with that field empty
## rather than failing the load.

## This record's key in `actor.module_data`. A SIBLING of every other module's key rather
## than a nested slot: attrition belongs to the BODY, not to the domain run it happens
## inside, and a hero who leaves a domain with half a ration carries the remainder out.
const MODULE_KEY := &"consumables"

const STATE_VERSION := 1


## A fresh, empty record. Every reader starts here, so "no attrition has run" and "an
## attrition run that has paid nothing" are the same answer rather than a shape three
## call sites each have to interpret.
static func blank() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"rooms": 0,
		"last_room": "",
		"empty_rooms": _zeroed(),
	}


## A usable record from anything `module_data` may hold.
##
## A payload written before `empty_rooms` existed loads with every resource reading zero
## rooms empty — which is the honest reading of a save that predates the field, because a
## run that never recorded an empty resource is a run that had none. `version` is stamped
## on the way out, as `DomainRun.normalize` does, so a reader can tell a normalised
## record from one that was merely absent.
static func normalize(raw: Dictionary) -> Dictionary:
	var run := blank()
	if raw.is_empty():
		return run
	run["rooms"] = maxi(0, int(raw.get("rooms", 0)))
	run["last_room"] = String(raw.get("last_room", ""))
	var empty: Dictionary = {}
	var carried = raw.get("empty_rooms", {})
	if carried is Dictionary:
		empty = carried as Dictionary
	for resource_id in ConsumableResources.IDS:
		# `int()` rather than `bool()`: a save round trip turns a written `0` into `0.0`
		# and a written `true` into `1.0`, and `maxi` clamps a hand-edited negative.
		run["empty_rooms"][String(resource_id)] = maxi(0, int(empty.get(String(resource_id), 0)))
	run["version"] = STATE_VERSION
	return run


## Record that one room was entered and that `room_id` is what it was paid on.
static func note_room(run: Dictionary, room_id: StringName) -> Dictionary:
	run["rooms"] = maxi(0, int(run.get("rooms", 0))) + 1
	run["last_room"] = String(room_id)
	return run


## Record that `resource_id` spent one more room at zero. Only ever called for a resource
## that IS at zero, so the counter is a count of the cost rather than of the depletion.
static func note_empty(run: Dictionary, resource_id: StringName) -> Dictionary:
	run["empty_rooms"][String(resource_id)] = rooms_empty_of(run, resource_id) + 1
	return run


## Record that `resource_id` rose back above zero, so the rooms it spent empty stops
## growing. Called on the RESTORE rather than on the depletion, which is what makes a
## refilled pool and a pool that was never empty indistinguishable in this one field —
## and that is correct, because both mean "the cost is no longer being paid".
static func note_restored(run: Dictionary, resource_id: StringName) -> Dictionary:
	run["empty_rooms"][String(resource_id)] = 0
	return run


## How many rooms `resource_id` has spent at zero in this record. Never negative, so a
## hand-edited save cannot make a screen render a negative count.
static func rooms_empty_of(run: Dictionary, resource_id: StringName) -> int:
	var empty: Dictionary = run.get("empty_rooms", {})
	return maxi(0, int(empty.get(String(resource_id), 0)))


static func _zeroed() -> Dictionary:
	var out := {}
	for resource_id in ConsumableResources.IDS:
		out[String(resource_id)] = 0
	return out
