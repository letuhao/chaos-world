class_name RelationshipsProvider
extends StatProvider

## Contributes this module's four relationship stats from the log on the actor (ADR 0123).
##
## **Module-owned ids only.** It never emits a core id, because a provider's contribution
## replaces the baseline of the stat it names (ADR 0026).
##
## **It is a pure read of one snapshot component**, never a re-derivation, so the same
## percentage is never counted twice by both a projection and the provider.

const STATE_COMPONENT := &"relationship_state"

var _state: RelationshipState = null


func _init(p_state: RelationshipState = null) -> void:
	_state = p_state


func contribute(context: StatContext) -> Dictionary:
	var state := _state
	if state == null:
		state = context.component(STATE_COMPONENT) as RelationshipState
	if state == null:
		return {}
	return {
		RelationshipsStats.EMOTIONAL_ENERGY: state.emotional_energy(),
		RelationshipsStats.ACTIVE_RELATIONSHIPS: state.active_entries().size(),
		RelationshipsStats.DC_PARTNER_COUNT: state.active_dc_partner_count(),
		RelationshipsStats.HIGHEST_TIER: state.highest_tier(),
	}
