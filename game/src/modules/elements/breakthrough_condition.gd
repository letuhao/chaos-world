class_name ElementBreakthroughCondition
extends BreakthroughCondition

## The elemental path's gate (ADR 0004): a rung costs MASTERY, not items.
##
## The threshold is the authored labour curve for the realm being entered, read through
## the INJECTED source (`ElementMastery.set_progress_source`) because this module may
## not read another path's seeds. The path has no items and no dantian: its currency is
## the total mastery the actor has earned across every element it can practise — the
## novel shape where the elemental climb is paid in understanding.


func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != ElementMastery.PATH_ID:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var threshold := ElementMastery.threshold_for(target.id)
	if threshold < 0.0:
		return false
	return ElementMastery.total_mastery(actor) >= threshold


func describe() -> String:
	return "Mastery enough for the next elemental rank, against the realm's authored labour"
