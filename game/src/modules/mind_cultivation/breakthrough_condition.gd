class_name MindBreakthroughCondition
extends BreakthroughCondition

const _ITEMS := preload("res://src/modules/items/api.gd")


## Entry into realm R requires the *completed* milestones of R-1, not R's own
## training targets. While still in R-1 the sea caps at the R-1 clarity/purity
## targets, so checking R's targets here would be circular (ADR 0013/0016/0024).
## The target profile supplies the breakthrough pill and the progress bar; the
## source profile supplies the training prerequisites that are reachable from
## R-1. High tiers additionally require every shared tier gate and the anchor the
## previous realm committed (ADR 0024).
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
		# MUTATION-BL0161-1

		actor.stats.derived(Stat.COMPREHENSION) >= target_seed.comprehension_required
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


## High tiers require every SHARED tier gate AND the anchor the previous realm
## committed. The two are different clauses and both are owed.
##
## ADR 0024 delegated the ANCHOR clause to `MindAnchor` — the anchor a breakthrough
## commits is that attempt's own outcome, so it cannot also be its precondition — and
## it delegated nothing else: "Tier gates stay in core. Qi and Body call
## `Breakthrough.tier_gates_met`." Reading only `MindAnchor` here deleted
## `inside_world_ok`, `world_ok` and `ascension_ok` from this path, so a mind actor
## entered R29 and R30 having satisfied none of them and never walked the
## Transcendent ascent that body and qi walk. The delegation is kept; the deletion is
## not.
##
## Reading the gates HERE and at the advance is deliberate rather than redundant:
## `start` spends the realm pill on the strength of this condition, so a gate that
## only `try_advance_gated` checked would let the pill be spent on a breakthrough
## that then refuses.
func _anchor_ready(actor: Actor, target: RealmDef) -> bool:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return true
	if not Breakthrough.tier_gates_met(actor, target.index):
		return false
	return MindAnchor.stage_met(actor, MindAnchor.required_stage(target.index))
