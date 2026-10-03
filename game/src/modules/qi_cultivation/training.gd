class_name QiTraining
extends RefCounted

## Qi-cultivation action layer (ADR 0011/0014/0024): refine the dantian by
## circulating qi, and train a meridian with the realm's elixir.

const _ITEMS := preload("res://src/modules/items/api.gd")


static func synchronize(actor: Actor) -> void:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return
	actor.meridians.unlock_for_realm(state.rank_id)
	var seed := QiRealmSeed.for_realm(state.rank_id)
	var dantian := QiAccess.dantian(actor)
	if seed == null or dantian == null:
		return
	# Capacity comes from the seed, scaled by the meridian network's capacity
	# bonus so channel investment visibly widens the dantian.
	dantian.set_structural_capacity(
		seed.dantian_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	)
	dantian.set_tier(seed.dantian_tier)
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.set_maximum(dantian.effective_capacity())
	actor.mark_stats_dirty()


static func cultivate(actor: Actor, amount: float) -> bool:
	var dantian := QiAccess.dantian(actor)
	var state := actor.path(QiPath.PATH_ID)
	if dantian == null or state == null or amount <= 0.0 or not is_finite(amount):
		return false
	synchronize(actor)
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	# Meridian flow bonus speeds circulation; the realm RATE values one unit of
	# work. A bounded per-realm number, not the realm's magnitude — see
	# `realm_profile.gd`. Same rate, same realm, as body and mind.
	var gain := (
		amount * QiRealmProfile.factor(state.rank_id) * (1.0 + actor.meridians.get_flow_bonus())
	)
	# A full dantian stops *storing* qi, not *training*: refusing the whole action
	# deadlocked the path, because the entry gate demands both a full reservoir
	# and a met progress floor, and the reservoir fills first. `fill` clamps, so
	# the surplus is simply not kept — the same contract as
	# `BodyTraining.cultivate` over the shared body pool.
	dantian.fill(actor, gain)
	# Quality is refined toward the *next* realm's floor, not this realm's. The
	# floor rises every realm, so capping at the current realm's own requirement
	# made every gate from R3 on permanently unreachable (ADR 0028's "reachable
	# gates" rule, which Body honours via a separate `quality_target`).
	var ceiling := _quality_ceiling(state.rank_id)
	if ceiling > 0.0:
		dantian.set_quality(maxf(dantian.quality, minf(ceiling, dantian.quality + gain / 1000.0)))
	state.progress += gain
	actor.mark_stats_dirty()
	return true


## The dantian quality the next realm demands, or the current realm's own floor at
## the top of the ladder. 0.0 when either realm has no profile.
static func _quality_ceiling(rank_id: StringName) -> float:
	var ladder := RealmDefaults.ladder()
	var next := ladder.next(rank_id)
	if next != null:
		var next_seed := QiRealmSeed.for_realm(next.id)
		if next_seed != null:
			return next_seed.dantian_quality_required
	var seed := QiRealmSeed.for_realm(rank_id)
	return 0.0 if seed == null else seed.dantian_quality_required


## Undo the damage a qi deviation left behind: heal the dantian scar and repair
## one burned channel. Consumes the realm's recovery item, so every realm needs
## one authored (ADR 0031). All-or-nothing: the item is spent only when there is
## something to repair.
static func recover(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var dantian := QiAccess.dantian(actor)
	if state == null or dantian == null:
		return false
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.recovery_item == &"":
		return false
	actor.meridians.unlock_for_realm(state.rank_id)
	var channel := actor.meridians.get_meridian(meridian_id)
	if channel == null:
		return false
	if not dantian.injured and not channel.injured:
		return false
	if not _ITEMS.consume_item(actor, seed.recovery_item):
		return false
	dantian.heal()
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	synchronize(actor)
	actor.mark_stats_dirty()
	return true


## Raise comprehension, the only route to a realm's `comprehension_required`
## floor. Circulating qi refines the dantian but never teaches, so without this
## the gate is unreachable and the path dead-ends partway up the ladder — the
## realm rewards grant `spirit`, not comprehension. Mirrors `BodyTraining.
## meditate` (ADR 0024).
static func meditate(actor: Actor, amount: float) -> bool:
	if amount <= 0.0 or not is_finite(amount):
		return false
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return false
	var gain := amount * actor.stats.derived(Stat.INSIGHT_GAIN)
	actor.stats.set_base(Stat.COMPREHENSION, actor.stats.get_base(Stat.COMPREHENSION) + gain)
	actor.mark_stats_dirty()
	return true


## One elixir: climb the channel one state, or one step of depth once it is
## already strengthened, and spend the realm's `training_item`.
##
## A channel that is injured is repaired instead of trained, because `meets`
## fails on the injury flag alone. A channel with nothing left to learn at this
## realm's `channel_refinement_cap` is REFUSED before the item is spent: the cap
## is the only thing bounding depth, so an elixir consumed past it is an elixir
## burned for nothing, and a path whose training verb silently eats its own
## currency is a path whose gate stops meaning what it says (ADR 0095).
static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	var seed := QiRealmSeed.for_realm(state.rank_id)
	# Decide before spending: a channel with nothing left to learn at this realm's
	# cap must refuse, or the elixir is burned for no progress at all.
	if seed == null or not can_train_channel(actor, meridian_id):
		return false
	if not _ITEMS.has_item(actor, seed.training_item):
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
				# Already strengthened: the elixir deepens it toward the seed cap.
				actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap)
	synchronize(actor)
	return true


## Whether `meridian_id` has anything left to learn while standing in this realm:
## an injured channel still has its repair, a climbable one its next state, and a
## strengthened one its remaining depth under the realm's cap. The decision is
## made BEFORE the item is spent, so a refusal costs the actor nothing.
static func can_train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return false
	if channel.is_injured():
		return true
	if channel.state != MeridianState.STRENGTHENED:
		return true
	return channel.refinement < seed.channel_refinement_cap


## How many elixirs one channel still needs to reach `target`: the state climb
## plus the outstanding depth. Read, not spent — a caller that wants the number for
## a screen or a budget takes it from here rather than counting itself.
##
## Both halves are counted unconditionally, because both are still owed. Depth only
## accrues on a channel already at `strengthened`, so gating the depth term on the
## climb having happened made a fresh channel's budget the climb alone — and a
## caller bounding a walk by this number then gave up the moment the channel
## reached the state, one step before the depth the gate also demands.
static func elixirs_to_gate(actor: Actor, meridian_id: StringName, target: QiRealmSeed) -> int:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null or target == null:
		return 0
	var wanted := int(MeridianState.STATE_ORDER.get(target.required_channel_state, 0))
	var climb := maxi(0, wanted - channel.state_rank())
	var depth := maxi(0, target.required_channel_refinement - channel.refinement)
	return climb + depth
