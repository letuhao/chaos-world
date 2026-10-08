class_name QiTraining
extends RefCounted

## Qi-cultivation action layer (ADR 0011/0014/0024): refine the dantian by
## circulating qi, and train a meridian with the realm's elixir.

const _ITEMS := preload("res://src/modules/items/api.gd")

## What one dantian catalyst buys on an overflowing sitting: ONE quality step,
## past the next realm's floor.
##
## A step and not a rate, deliberately. `progress_required` runs 100 -> 2900, so
## an overflow is thousands of qi at the deep realms and a rate would sell the
## whole ladder for one item. `Dantian.set_quality` clamps to 1.0 on top of this,
## which is what keeps `QiChance.MAX_CHANCE` out of reach: quality buys at most
## `QUALITY_TO_CHANCE` of the roll and 1.0 is still only 0.55 (ADR 0051).
const CATALYST_QUALITY_STEP := 0.05

## How far past the standing realm's `channel_refinement_cap` one meridian catalyst
## reaches. One step, so the catalyst is a relief valve on the one boundary the elixir
## cannot cross rather than a replacement for the elixir ladder.
const CATALYST_DEPTH_STEP := 1


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
	# `core/realm_rate.gd`. Same rate, same realm, as body and mind.
	var gain := amount * RealmRate.factor(state.rank_id) * (1.0 + actor.meridians.get_flow_bonus())
	# The sitting's worth in THIS place and for THIS actor: the place's bounded density
	# and the actor's own rate, one shared call — see `core/cultivation_gain.gd`.
	gain = CultivationGain.scale_gain(actor, gain)
	# The room is read BEFORE the fill, because what the reservoir refuses is the
	# quantity this sitting is priced on (ADR 0195).
	var room := maxf(0.0, dantian.effective_capacity() - dantian.current(actor))
	var overflow := maxf(0.0, gain - room)
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
	# THE PRICE of an overflowing sitting. See [method _buy_overflow_quality] and
	# ADR 0195 for why the price is on the overflow and never on the stored qi.
	if overflow > 0.0:
		_buy_overflow_quality(actor, dantian, seed)
	# `progress` is metered from `gain`, NOT from the stored qi: a meter bounded by
	# the reservoir cannot be met while the reservoir is full, and every realm's gate
	# demands a full one, so that would be the deadlock ADR 0195 rules out.
	state.progress += gain
	actor.mark_stats_dirty()
	return true


## One dantian catalyst turns the qi a sitting could NOT store into one step of
## quality PAST the next realm's floor — roll certainty `cultivate` cannot reach,
## because it stops refining at that floor.
##
## ## What the price is, and why it is not a tax
##
## The price is on the OVERFLOW, never on the sitting and never on the stored qi.
## Everything the gate demands stays free and itemless: the reservoir still fills,
## quality still climbs to the gate's own floor with no item in hand, and
## `progress` is metered from `gain` either way. So ADR 0096's objection — that a
## mandatory item in a gate position removes the player's only lever, and replaces
## "did I cultivate well" with "do I hold the item" — cannot apply to this: hold no
## catalyst at all and the whole ladder walks exactly as it did, because
## `test_qi_ruling_q4_cultivate_is_priced.gd` walks R1->R30 on a catalyst-free
## inventory.
##
## ## WHY NOT PRICE THE STORED qi (ADR 0180's rejection, re-measured)
##
## `cultivate` is the SOLE writer of `QiStats.QI`: `Actor._sync_core_resources`
## sizes regen for health and stamina only (`actor.gd:153`), nothing ticks
## `ResourcePool.regen`, and `BreakthroughTransaction` zeroes the pool on every
## ascent (`breakthrough_transaction.gd:154`). A qi-denominated price would charge
## the verb out of the one reservoir the gate demands FULL, and the two demands
## cancel. `tools/cultivation/audit.py` now fails that shape structurally rather
## than trusting this comment.
static func _buy_overflow_quality(actor: Actor, dantian: Dantian, seed: QiRealmSeed) -> bool:
	if seed == null or seed.dantian_catalyst == &"" or dantian == null:
		return false
	# All-or-nothing, like every other price on this path: a catalyst spent at a
	# full-quality dantian buys nothing, so it is not spent.
	if dantian.quality >= 1.0 or not _ITEMS.has_item(actor, seed.dantian_catalyst):
		return false
	if not _ITEMS.consume_item(actor, seed.dantian_catalyst):
		return false
	dantian.set_quality(dantian.quality + CATALYST_QUALITY_STEP)
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


## Undo the damage a qi deviation left behind: heal the dantian scar, repair one
## burned channel, and mend a cracked dao heart (BL-0932). Consumes the realm's
## recovery item, so every realm needs one authored (ADR 0031). All-or-nothing: the
## item is spent only when there is something to repair.
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
	# A cracked dao heart is a THIRD thing a deviation leaves, so it counts toward
	# "something to repair": the elixir that closes the wound closes the crack.
	var cracked := DaoHeart.crack_of(actor) < 0.0
	if not dantian.injured and not channel.injured and not cracked:
		return false
	if not _ITEMS.consume_item(actor, seed.recovery_item):
		return false
	dantian.heal()
	if channel.injured:
		actor.meridians.repair_meridian(meridian_id)
	if cracked:
		DaoHeart.rebuild(actor, -DaoHeart.crack_of(actor))
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
## A BURNED CHANNEL IS NOT TRAINED, IT IS REPAIRED — AND THE REPAIR IS PRICED BY
## `recovery_item`, not by the channel elixir (ADR 0141, which established the
## shape on the mind path; qi is the same ladder). Every realm authors both
## roles: `training_item` walks the ladder, `recovery_item` undoes what a qi
## deviation left behind, which is the scarred dantian AND the burned channel
## (ADR 0031). So the burn is handed to `recover` rather than paid for here.
##
## That is what makes `recovery_item` load-bearing on this path. Charging the
## channel elixir for the repair left `recover` — and `recover_next`, the facade
## verb added for exactly this wound — with no route a player could afford, so
## thirty authored recovery elixirs were demanded by nothing, and the missing
## verb went unnoticed: a burned channel WAS repairable through the facade, just
## by spending the wrong item.
##
## Delegated rather than reimplemented, so there is one repair at one price: a
## second copy of the consume here is exactly how the two prices drifted apart
## the first time. `recover`'s all-or-nothing rule comes with it — nothing is
## spent unless there is something to repair — as does the dantian scar the same
## deviation left behind being healed alongside the channel, which cannot lose
## ground.
##
## A channel with nothing left to learn at this realm's `channel_refinement_cap`
## is REFUSED before the item is spent: the cap is the only thing bounding depth,
## so an elixir consumed past it is an elixir burned for nothing, and a path whose
## training verb silently eats its own currency is a path whose gate stops meaning
## what it says (ADR 0095).
static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null:
		return false
	# Ahead of the seed read and ahead of any consume: a burn has its own price.
	if channel.is_injured():
		return recover(actor, meridian_id)
	var seed := QiRealmSeed.for_realm(state.rank_id)
	# Decide before spending: a channel with nothing left to learn at this realm's
	# cap must refuse, or the elixir is burned for no progress at all.
	if seed == null or not can_train_channel(actor, meridian_id):
		return false
	if not _ITEMS.has_item(actor, seed.training_item):
		return false
	if not _ITEMS.consume_item(actor, seed.training_item):
		return false
	_climb_one_step(actor, channel, seed)
	synchronize(actor)
	return true


## One step of depth PAST the standing realm's `channel_refinement_cap`, paid for
## with the realm's `meridian_catalyst` instead of its channel elixir.
##
## This is the second half of ADR 0096's restored family. The cap is the one thing
## `train_channel` refuses before it spends an elixir (ADR 0095): depth past it cannot
## be bought at any elixir count, by design, so no elixir is burned for nothing. A
## catalyst is what makes that refusal purchasable — and it is the ONLY route past it.
##
## ## WHY THE CAP AND NOT OFF-GATE CHANNELS (measured, and the first answer was wrong)
##
## The obvious second use was one step on a channel the next gate does NOT name, since
## the body holds twenty channels and a gate names four to twelve. Measured on the
## shipped ladder: there is no such work. A gate names every channel the standing realm
## has unlocked at every one of the low tiers (4 unlocked / 4 named at R1-R3, 6 / 8 at
## R4), so `train_off_gate_channel` would have been content with no reachable work —
## the dead family ADR 0096 deleted, in a new coat. The cap is the boundary that
## exists everywhere.
##
## ## What the depth is worth, stated rather than implied
##
## `required_channel_refinement` is the gate, and the gate is reachable inside the cap
## at all 29 boundaries (`qi_gate_demands_more_depth_than_the_realm_below_offers`), so
## this buys no reachability at all. Its one live reader is
## `MeridianNetwork.get_power_bonus`, which scales a strengthened channel's power by
## `1 + REFINE_POWER_STEP * refinement`. So this role is optional depth past the ladder
## for combat power, and it is deliberately NOT in a gate position.
##
## ## The refusals, and why there are two
##
## - **Below the cap is refused.** There the elixir is the price, and this verb would
##   be a cheaper route to a gate — which would make `training_item` meaningless.
## - **An injured channel is refused.** A burn is `recover`'s priced job, priced by
##   `recovery_item` (ADR 0141); two prices for one repair is how they drifted apart.
static func deepen_past_cap(actor: Actor, meridian_id: StringName) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	var channel := actor.meridians.get_meridian(meridian_id)
	if state == null or channel == null or channel.is_injured():
		return false
	# Only a strengthened channel carries depth at all: `refine_meridian` refuses any
	# other state, so asking would spend the catalyst for nothing.
	if channel.state != MeridianState.STRENGTHENED:
		return false
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.meridian_catalyst == &"":
		return false
	if channel.refinement < seed.channel_refinement_cap:
		return false
	if not _ITEMS.has_item(actor, seed.meridian_catalyst):
		return false
	if not _ITEMS.consume_item(actor, seed.meridian_catalyst):
		return false
	actor.meridians.refine_meridian(meridian_id, seed.channel_refinement_cap + CATALYST_DEPTH_STEP)
	synchronize(actor)
	return true


## The one state climb and one depth step both training verbs perform, so the two
## prices cannot disagree about what a step IS.
static func _climb_one_step(actor: Actor, channel: MeridianState, seed: QiRealmSeed) -> void:
	match channel.state:
		MeridianState.CLOSED:
			actor.meridians.open_meridian(channel.id)
		MeridianState.OPEN:
			actor.meridians.expand_meridian(channel.id)
		MeridianState.EXPANDED:
			actor.meridians.strengthen_meridian(channel.id)
		_:
			# Already strengthened: the step deepens it toward the seed cap.
			actor.meridians.refine_meridian(channel.id, seed.channel_refinement_cap)


## The first channel that still owes the gate of the realm AHEAD, trained one step
## through `train_channel`; `&""` when nothing is owed or no elixir is in hand.
##
## `&""` rather than a bool so a screen can name the channel it trained without
## repeating this walk, and so "nothing owed" is distinguishable from "owed, but
## you cannot pay".
##
## The gate read here is the NEXT realm's seed, because that is the one
## `QiBreakthroughCondition` enforces — the standing realm's own gate is already
## behind the actor. What the walk may spend is bounded by the standing realm's
## cap, and `test_the_channel_demand_never_falls_and_the_cap_rises_every_realm`
## is what keeps the next realm's demand inside it.
static func train_next_channel(actor: Actor) -> StringName:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return &""
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	if next_realm == null:
		return &""
	var gate := QiRealmSeed.for_realm(next_realm.id)
	if gate == null:
		return &""
	# Only the channels the gate NAMES are candidates. The body holds twenty and
	# the gate names four, and a verb that deepened the other sixteen would charge
	# the realm's elixir for work the gate never asked for — the walk would cost
	# five times its budget and the screen could not tell why. A player who wants
	# to spend a spare elixir on the rest of the body already has `train_channel`.
	# `for` over the gate's own list, so the walk cannot outlast its candidates.
	for meridian_id in gate.required_meridians:
		if not _owes_the_gate(actor, meridian_id, gate):
			continue
		if can_train_channel(actor, meridian_id) and train_channel(actor, meridian_id):
			return meridian_id
	return &""


## Whether `meridian_id` still owes the gate anything: the whole predicate, depth
## included. `QiRealmSeed.channel_met` is the one definition of that gate
## (ADR 0044), so a selection rule that spelled it out again here would be free to
## drift from the condition that enforces it — which is precisely the defect this
## replaces, where the rule read a state-only `meets()` and stopped.
static func _owes_the_gate(actor: Actor, meridian_id: StringName, gate: QiRealmSeed) -> bool:
	return not gate.channel_met(actor.meridians.get_meridian(meridian_id))


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
