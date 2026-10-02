class_name LootRoutes
extends RefCounted

## Unique drop routes. A unique item declares the one boss that may drop it with
## a `unique_route:<boss_id>` tag on its `ItemDef`; table resolution refuses that
## item for every other source, and the validator reports a route that no table
## can reach.
##
## [constant TAG_PREFIX] is the single owner of the field name, so the authoring
## field can be re-pointed in one place without touching resolution.

const TAG_PREFIX := "unique_route:"


## Boss ids this definition declares as its unique drop route. Empty means the
## item is not route-limited and may drop from any table that lists it.
static func routes(def: Resource) -> Array[String]:
	var out: Array[String] = []
	if def == null:
		return out
	var tags = def.get("tags")
	if not tags is Array:
		return out
	for tag in tags:
		var text := String(tag)
		if text.begins_with(TAG_PREFIX):
			var boss_id := text.substr(TAG_PREFIX.length())
			if not boss_id.is_empty() and not out.has(boss_id):
				out.append(boss_id)
	return out


## Whether `boss_id` is allowed to drop this definition. An item with no route
## declaration is unrestricted; one with a declaration is exclusive to it.
static func permits(def: Resource, boss_id: StringName) -> bool:
	var declared := routes(def)
	if declared.is_empty():
		return true
	return declared.has(String(boss_id))
