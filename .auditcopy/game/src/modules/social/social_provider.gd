class_name SocialProvider
extends StatProvider

## Contributes this module's three social stats from the ledger on the actor (ADR 0076).
##
## **Module-owned ids only.** It never emits a core id, because a provider's contribution
## *replaces* the baseline of the stat it names (ADR 0026) — emitting `dao_heart` here
## would silently overwrite whatever the mind path derived.
##
## **It is a pure read of one snapshot component**, never a re-derivation, so the same
## percentage is never counted twice by both a projection and the provider.

## The `actor.components` slot holding the ledger this provider reads.
const STATE_COMPONENT := &"social_state"

var _state: SocialState = null


func _init(p_state: SocialState = null) -> void:
	_state = p_state


func contribute(context: StatContext) -> Dictionary:
	var state := _state
	if state == null:
		state = context.component(STATE_COMPONENT) as SocialState
	if state == null:
		return {}
	var standings: Array[float] = []
	var trusts: Array[float] = []
	var reach := 0.0
	for partner_id in state.partner_ids():
		var bond := state.bond(partner_id)
		if bond == null:
			continue
		standings.append(bond.standing)
		trusts.append(bond.trust)
		if SocialBondClass.at_least(bond.bond_class(), SocialBondClass.FRIEND):
			reach += 1.0
	return {
		SocialStats.REPUTATION: _mean(standings),
		SocialStats.TRUST: _mean(trusts),
		SocialStats.REACH: reach,
	}


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())
