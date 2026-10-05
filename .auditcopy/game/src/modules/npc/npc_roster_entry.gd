class_name NpcRosterEntry
extends RefCounted

## One tracked npc's remembered state (ADR 0077).
##
## **This is a record, not an actor.** It holds the tier, the stage and — while the npc is
## off-stage — the last `Actor.to_dict()` payload as primitives. Restoring the individual
## on demand is what lets a world hold hundreds of cast members without a live actor for
## each (ADR 0074).

## Bounded table size. A save that grows without limit is a disk hazard, so the cap
## refuses the write loudly instead of trimming or looping (repo rule).
const MAX_TALLY_KEYS := 16

## The stable id from `NpcDef.npc_id`.
var npc_id: StringName = &""
## Which def this was spawned from. The id survives even if the def is re-authored.
var def_id: StringName = &""
var tier: StringName = NpcTier.MINOR
var stage_id: StringName = &""
var presence: StringName = NpcPresence.UNKNOWN

## Where they were last met. Content-facing, never used to compute distance — the room
## owns distance (ADR 0072).
var location_id: StringName = &""

## Bounded computed-progression counters. `MAX_TALLY_KEYS` stops a runaway verb from
## growing a save forever.
var tally: Dictionary = {}

## The last `Actor.to_dict()`, kept only while the individual is off-stage. Dropped the
## moment they are live again, so a save never holds two copies of the same actor.
var payload: Dictionary = {}


func _init(p_npc_id: StringName = &"", p_def_id: StringName = &"") -> void:
	npc_id = p_npc_id
	def_id = p_def_id


func tracked() -> bool:
	return NpcTier.is_tracked(NpcTier.normalize(tier))


func stage_index() -> int:
	return int(tally.get(&"__stage_index", 0))


## The monotonic stage ordinal. Stored separately from `stage_id` so advancement can
## refuse a regression without consulting the catalog, and so an authored reorder cannot
## make a save walk backwards.
func set_stage_index(value: int) -> void:
	tally[&"__stage_index"] = value


## Bump a computed-progression counter. Returns false once the table is full, so a caller
## that ignores the result has still not grown an unbounded save.
func bump_tally(verb: StringName, amount: int = 1) -> bool:
	if verb == &"":
		return false
	if not tally.has(verb) and tally.size() >= MAX_TALLY_KEYS:
		return false
	tally[verb] = int(tally.get(verb, 0)) + amount
	return true


func tally_of(verb: StringName) -> int:
	return int(tally.get(verb, 0))


## The tally as String-keyed primitives, so the payload is JSON-safe: a `StringName` key
## survives a JSON round trip as itself, while a save written by another tool would
## stringify it and then fail to find the verb again.
func _string_keyed(values: Dictionary) -> Dictionary:
	var out := {}
	for key in values.keys():
		out[String(key)] = int(values[key])
	return out


func to_dict() -> Dictionary:
	return {
		"npc_id": String(npc_id),
		"def_id": String(def_id),
		"tier": String(tier),
		"stage_id": String(stage_id),
		"presence": String(presence),
		"location_id": String(location_id),
		"tally": _string_keyed(tally),
		"payload": payload.duplicate(true),
	}


static func from_dict(data: Dictionary) -> NpcRosterEntry:
	var entry := NpcRosterEntry.new(
		StringName(data.get("npc_id", "")), StringName(data.get("def_id", ""))
	)
	entry.tier = NpcTier.normalize(StringName(data.get("tier", NpcTier.MINOR)))
	entry.stage_id = StringName(data.get("stage_id", ""))
	entry.presence = NpcPresence.normalize(StringName(data.get("presence", NpcPresence.UNKNOWN)))
	entry.location_id = StringName(data.get("location_id", ""))
	entry.payload = (data.get("payload", {}) as Dictionary).duplicate(true)
	for key in data.get("tally", {}).keys():
		entry.tally[StringName(key)] = int(data["tally"][key])
	return entry


static func empty() -> Dictionary:
	return {"version": 1, "entries": {}}
