class_name NpcStageDef
extends Resource

## One authored stage an individual npc passes through (ADR 0077).
##
## **A stage is authored and addressed by id, never by index.** A gate names the stage it
## requires the way a gate should name it — `&"elder_taught"` — so reordering the ladder
## cannot silently shift what an old save satisfies.
##
## **A stage grants magnitudes, authored once.** `stat_multipliers` is an entity's own
## scale, exactly like a realm seed's `integrity_maximum`: it is applied once, under the
## `npc_stage:` source, and is never derived from the realm power curve. A boss is a
## bigger number plus a tier tag, not a second stat pipeline (ADR 0074).

## The authored stage id. This is what a gate names.
@export var stage_id: StringName = &""

## The author's display order within this npc's ladder. Strictly increasing; used to walk
## forward, never to compare what a requirement meant.
@export var index: int = 0

@export var display_name: String = ""

## `stat_id -> magnitude`, applied once on entering this stage. Authored, not derived.
@export var stat_multipliers: Dictionary = {}

## Tags mirrored onto `Actor.traits` as `npc_stage:<stage_id>` while the stage is current,
## so combat and quest content can read the stage without importing this module.
@export var tags: Array[StringName] = []

## How many tally hits of a named verb move this npc on. Zero means the stage is advanced
## only by an explicit call from the system that owns the story beat.
@export var advance_after: int = 0

## A retired stage. The npc spawns here no more, and the roster entry becomes a trace.
@export var terminal: bool = false


func tag_id() -> StringName:
	return StringName("npc_stage:%s" % String(stage_id))


func to_dict() -> Dictionary:
	return {
		"stage_id": String(stage_id),
		"index": index,
		"display_name": display_name,
		"stat_multipliers": stat_multipliers.duplicate(),
		"tags": _strings(tags),
		"advance_after": advance_after,
		"terminal": terminal,
	}


func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
