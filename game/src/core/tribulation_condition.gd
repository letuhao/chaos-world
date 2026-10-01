class_name TribulationCondition
extends BreakthroughCondition

## Condition that requires a Heavenly Tribulation for Immortal/Transcendent
## breakthroughs (ADR 0020). Returns true when the actor is prepared for
## tribulation (realm 19+ only).


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(state.rank_id)
	# Tribulation required only for Immortal+ (realm index >= 18)
	if realm_index < Tribulation.TRIBULATION_REALM_THRESHOLD:
		return true
	# Check if actor has preparation (formation, pill, or artifact)
	if actor.tribulation == null:
		return false
	var prep: Dictionary = actor.tribulation.preparation
	return prep.has("formation") or prep.has("pill") or prep.has("artifact")


func describe() -> String:
	return "tribulation required"
