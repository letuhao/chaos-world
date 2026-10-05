class_name DlcExampleCultivationApi
extends RefCounted

## Cultivation-path facade for the DLC example mod (ADR 0184).
## Proves the contract: attach() enrols an actor, panel_state() reads it back.

const PATH_ID := &"dlc_example_cultivation"


static func attach(actor: Actor) -> void:
	actor.stats.add_provider(DlcExampleCultivationProvider.new())


static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(PATH_ID)
	if state == null:
		return {}
	return {
		"realm": String(state.rank_id),
		"progress": float(state.progress),
	}
