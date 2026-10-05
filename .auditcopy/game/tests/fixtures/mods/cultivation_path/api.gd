class_name FixtureCultivationApi
extends RefCounted

## Minimal cultivation-path facade for the fixture mod (ADR 0184).
## Proves the contract: attach() enrols an actor, panel_state() reads it back.

const PATH_ID := &"fixture_cultivation"


static func attach(actor: Actor) -> void:
	actor.stats.add_provider(FixtureCultivationProvider.new())


static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(PATH_ID)
	if state == null:
		return {}
	return {
		"realm": String(state.rank_id),
		"progress": float(state.progress),
	}
