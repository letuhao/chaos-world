class_name MindBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


## Entry into realm R requires the *completed* milestones of R-1, not R's own
## training targets. While still in R-1 the sea caps at the R-1 clarity/purity
## targets, so checking R's targets here would be circular (ADR 0013/0016/0024).
## The target profile supplies the breakthrough pill and the progress bar; the
## source profile supplies the training prerequisites that are reachable from
## R-1. High tiers additionally require their previously committed anchor and a
## survived tribulation (ADR 0024).
func can_breakthrough(actor: Actor, state: PathState, _context: Dictionary) -> bool:
	if state.path_id != MindPath.PATH_ID:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	var sea := MindCultivationApi.sea(actor)
	if target_seed == null or source_seed == null or sea == null:
		return false
	return (
		state.progress >= target_seed.progress_required
		and actor.stats.derived(Stat.COMPREHENSION) >= target_seed.comprehension_required
		and sea.turbulence <= 0.0
		and sea.clarity >= source_seed.clarity_required
		and sea.purity >= source_seed.purity_required
		and sea.ratio(actor) >= target_seed.sea_fill_required
		and _ITEMS.has_item(actor, target_seed.breakthrough_item)
		and _channels_ready(actor, source_seed)
		and _anchor_ready(actor, target)
	)


func describe() -> String:
	return (
		"Sea full and calm, R-1 clarity/purity milestones met, source channels trained,"
		+ " comprehension, realm pill, and prior anchors"
	)


func _channels_ready(actor: Actor, source_seed: MindRealmSeed) -> bool:
	for id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(id)
		if channel == null or not channel.meets(source_seed.required_channel_state):
			return false
	return true


## High tiers require a survived tribulation and the anchor the previous realm
## committed. The anchor this realm creates is never a prerequisite here.
func _anchor_ready(actor: Actor, target: RealmDef) -> bool:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return true
	if not Breakthrough.tribulation_ok(actor, target.index):
		return false
	return MindAnchor.stage_met(actor, MindAnchor.required_stage(target.index))
