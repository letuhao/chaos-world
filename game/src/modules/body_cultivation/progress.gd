class_name BodyProgress
extends RefCounted

## Tracks which realms have completed their target strengthening (ADR 0023).
## Each realm's strengthening is a once-only improvement; this component
## records completion so it is not replayed on load.

var completed: Array[StringName] = []


func is_complete(realm_id: StringName) -> bool:
	return completed.has(realm_id)


func mark_complete(realm_id: StringName) -> void:
	if not completed.has(realm_id):
		completed.append(realm_id)


func to_dict() -> Dictionary:
	return {"completed": completed.duplicate()}


static func from_dict(data: Dictionary) -> BodyProgress:
	var progress := BodyProgress.new()
	for realm_id in data.get("completed", []):
		progress.completed.append(StringName(realm_id))
	return progress
