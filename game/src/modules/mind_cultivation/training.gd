class_name MindTraining
extends RefCounted

## Mind-cultivation action layer (ADR 0013/0016/0024): fill the sea of
## consciousness, meditate to calm turbulence, train a meridian, and strengthen
## the sea's structure with its catalyst.

const _ITEMS := preload("res://src/modules/items/api.gd")

## Comprehension earned per unit of cultivation work, BEFORE the shared insight
## rate. Sized so the highest authored comprehension floor stays reachable without
## a second Mind path (ADR 0013/0024). This is the mind path's own coefficient on
## CULTIVATION WORK; the rate itself is core's `Stat.INSIGHT_GAIN`, read below —
## see `_grant_insight`.
const INSIGHT_RATE := 0.05


static func synchronize(actor: Actor) -> void:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	var seed := MindRealmSeed.for_realm(state.rank_id)
	var sea := MindCultivationApi.sea(actor)
	if seed == null or sea == null:
		return
	sea.set_structural_capacity(seed.sea_capacity * (1.0 + actor.meridians.get_capacity_bonus()))
	sea.set_tier(seed.sea_tier)
	var pool := actor.resource(MindStats.MIND_POWER)
	if pool != null:
		# set_maximum clamps current downward and never grants energy, so a
		# capacity change preserves stored mind power (ADR 0016).
		pool.set_maximum(sea.structural_capacity)
	actor.mark_stats_dirty()


## One sitting of cultivation. A full sea stops *storing* mind power, it does not
## stop *training*: refusing the whole action deadlocked this path, and the
## refusal has been reintroduced more than once. Do not put it back.
##
## The entry gate demands BOTH a filled reservoir (`sea_fill_required`) and a met
## progress floor, and the reservoir fills first, so a refusal leaves the actor
## holding a full sea with no way to earn the progress the same gate demands. A
## deviation makes that permanent — it halves progress and clouds the sea without
## draining it, and `cultivate` is the only source of either, so a failed attempt
## left a state the player could never leave. Every wait for "the sea is full"
## became unreachable, and an unreachable wait is what filled the user's disk with
## a 1 GB/s Godot log.
##
## `fill` clamps, so the surplus is simply not kept. Same contract as
## `QiTraining.cultivate` and `BodyTraining.cultivate` over the shared body pool.
## `test_mind_deviation_recovery.gd` fails if the refusal returns.
static func cultivate(actor: Actor, amount: float) -> bool:
	var sea := MindCultivationApi.sea(actor)
	var state := actor.path(MindPath.PATH_ID)
	if sea == null or state == null or amount <= 0.0 or not is_finite(amount):
		return false
	synchronize(actor)
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	# One unit of cultivation work is worth the realm's RATE, and only the rate. A
	# bounded per-realm number — see `core/realm_rate.gd`. Same rate, same realm,
	# as body and qi.
	var gain := amount * RealmRate.factor(state.rank_id) * (1.0 + actor.meridians.get_flow_bonus())
	sea.fill(actor, gain)
	# Deep meditation sharpens clarity and purity toward the seed's targets.
	sea.set_clarity(minf(seed.clarity_required, sea.clarity + gain / 1000.0))
	sea.set_purity(minf(seed.purity_required, sea.purity + gain / 1200.0))
	state.progress += gain
	_grant_insight(actor, gain)
	actor.mark_stats_dirty()
	return true


## Insight is the Mind path's only comprehension source, and cultivation work is
## what earns it. Every profile gates entry on a comprehension floor, so this
## rate must be able to reach the highest authored floor — a threshold with no
## attainable source would be an invalid gate (ADR 0013/0024).
##
## ## It is priced by core's `Stat.INSIGHT_GAIN`, exactly as body and qi price
## theirs (`BodyTraining.meditate`, `QiTraining.meditate`).
##
## Comprehension is a SHARED base attribute: sect offices grant `insight_gain`
## percentages, races and items carry the stat, and all three cultivation paths
## add to the same number. A flat `INSIGHT_RATE` alone meant every one of those
## sources did nothing for the mind path — a granted insight bonus silently did
## not apply to the one path whose gate is comprehension — and since
## comprehension IS this path's binding entry gate (BL-0153), the missing
## multiplier was the gate's own rate, not a cosmetic one.
##
## The read happens BEFORE `set_base`: that call invalidates the derived cache,
## so reading the rate inline in the expression would price this sitting at the
## rate the comprehension it is about to add implies. `INSIGHT_RATE` stays as the
## coefficient on cultivation work; the multiplier is core's, which is why there
## is exactly one insight rate in the game and it is not this file's.
static func _grant_insight(actor: Actor, gain: float) -> void:
	var insight_gain := actor.stats.derived(Stat.INSIGHT_GAIN)
	var current := actor.stats.get_base(Stat.COMPREHENSION)
	actor.stats.set_base(Stat.COMPREHENSION, current + gain * INSIGHT_RATE * insight_gain)


## Calm turbulence. This is the mind system's unique recovery (ADR 0016).
static func meditate(actor: Actor, amount: float) -> bool:
	var sea := MindCultivationApi.sea(actor)
	if sea == null or amount <= 0.0 or not is_finite(amount):
		return false
	if sea.turbulence <= 0.0:
		return false
	sea.calm(amount)
	actor.mark_stats_dirty()
	return true


## Undo the damage a mind deviation left behind: calm the clouded sea and
## repair the burned channel in one action. Consumes the realm's recovery item,
## so every realm authors one (ADR 0031). All-or-nothing: the item is spent only
## when there is something to repair.
##
## `meditate` can calm turbulence on its own, but it never touches a channel, and
## the sea's clarity gate is unreachable while one is burned.
static func recover(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	var sea := MindCultivationApi.sea(actor)
	if state == null or sea == null:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.recovery_item == &"":
		return false
	actor.meridians.unlock_for_realm(state.rank_id)
	var channel := actor.meridians.get_meridian(meridian_id)
	if channel == null:
		return false
	if sea.turbulence <= 0.0 and not channel.injured:
		return false
	if not _ITEMS.consume_item(actor, seed.recovery_item):
		return false
	sea.calm(sea.turbulence)
	# The deviation also halved clarity; restore it to the realm's floor so the
	# next gate is reachable again.
	sea.set_clarity(maxf(sea.clarity, seed.clarity_required))
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	synchronize(actor)
	actor.mark_stats_dirty()
	return true


static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or not _ITEMS.has_item(actor, seed.training_item):
		return false
	if not _ITEMS.consume_item(actor, seed.training_item):
		return false
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	else:
		match channel.state:
			MeridianState.CLOSED:
				actor.meridians.open_meridian(meridian_id)
			MeridianState.OPEN:
				actor.meridians.expand_meridian(meridian_id)
			MeridianState.EXPANDED:
				actor.meridians.strengthen_meridian(meridian_id)
			_:
				actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap)
	synchronize(actor)
	return true


## Strengthen the sea's structure with the realm's sea catalyst. This is the
## Thức Hải milestone: it raises clarity and purity to the realm's targets.
static func strengthen_sea(actor: Actor) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.sea_catalyst.is_empty():
		return false
	if not _ITEMS.has_item(actor, seed.sea_catalyst):
		return false
	if not _ITEMS.consume_item(actor, seed.sea_catalyst):
		return false
	var sea := MindCultivationApi.sea(actor)
	if sea == null:
		return false
	sea.set_clarity(maxf(sea.clarity, seed.clarity_required))
	sea.set_purity(maxf(sea.purity, seed.purity_required))
	sea.trained_stage = maxi(sea.trained_stage, 1)
	synchronize(actor)
	return true


## Resonance milestone for realms 19-30 (ADR 0024). Consumes the realm's
## channel catalyst to reinforce the anchor committed by an earlier high-tier
## breakthrough. Below the Immortal tier there is no anchor, so this is a no-op.
static func strengthen_anchor(actor: Actor) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return false
	var ladder := RealmDefaults.ladder()
	var realm_index := ladder.index_of(state.rank_id)
	if realm_index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return false
	# Validate before spending: at R19 there is no anchor yet, so the milestone
	# is a legitimate no-op and must not destroy the realm's channel elixir.
	var world := actor.inside_world
	if world == null or not world.anchor_created:
		return false
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null or not _ITEMS.has_item(actor, seed.training_item):
		return false
	if not _ITEMS.consume_item(actor, seed.training_item):
		return false
	world.strengthen_anchor()
	actor.mark_stats_dirty()
	return true
