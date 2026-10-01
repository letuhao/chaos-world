class_name CultivationPathDef
extends Resource

## Data-driven definition of one cultivation path (ADR 0003). Every path advances
## along the shared realm ladder (ADR 0005); `PathState.rank_id` is a realm id.

@export var id: StringName = &""
@export var display_name: String = ""


func has_rank(rank_id: StringName) -> bool:
	return RealmDefaults.ladder().has(rank_id)


func rank_index(rank_id: StringName) -> int:
	return RealmDefaults.ladder().index_of(rank_id)
