class_name CultivationPathDef
extends Resource

## Data-driven definition of one cultivation path (ADR 0003). Ranks are ordered.

@export var id: StringName = &""
@export var display_name: String = ""
@export var ranks: Array[StringName] = []


func rank_index(rank_id: StringName) -> int:
	return ranks.find(rank_id)


func has_rank(rank_id: StringName) -> bool:
	return ranks.has(rank_id)
