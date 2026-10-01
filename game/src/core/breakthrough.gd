class_name Breakthrough
extends RefCounted

## Advances a cultivation path one realm along the shared ladder when its
## BreakthroughCondition is met. The core orchestrates and rescales; per-system
## conditions are supplied by modules (ADR 0003/0005).


static func can_advance(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	var state := actor.path(path_id)
	if state == null:
		return false
	if condition != null and not condition.can_breakthrough(actor, state, context):
		return false
	return RealmDefaults.ladder().next(state.rank_id) != null


static func try_advance(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	if not can_advance(actor, path_id, condition, context):
		return false
	var state := actor.path(path_id)
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	state.rank_id = next_realm.id
	state.stage += 1
	state.progress = 0.0
	RealmScaling.apply(actor)
	actor.path_advanced.emit(path_id, next_realm.id)
	return true
