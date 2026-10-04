extends TestCase

## ADR 0152 / BL-0651: the AWARENESS reserve has a writer, and a player can see it move.
##
## ## What was wrong
##
## `MindCultivationApi.attach` minted `awareness` EMPTY (`api.gd:210`, `_add_pool(...,
## full = false)`) and nothing in `res://src` ever wrote it, so `awareness_ratio` was a
## constant `0.0`. Three shipped things were dead at once: `coh = 1 - COHERENCE_DAMP *
## awareness_ratio` was permanently `1.0` so the shipped `coherence_damp = 0.5`
## (`combat_damage.tres:23`) halved nothing, ADR 0071:20's "1.0 -> 0.5 at full awareness"
## was unreachable, and erosion `Kind.ATTEND` drained nothing.
##
## ## How this file reaches it
##
## Through the FACADE ONLY -- `MindCultivationApi.cultivate` / `.meditate` / `.sea` -- on an
## actor built by `ActorFactory.with_mind_cultivation`, which is the enrolment
## `app/actor_factory.gd:151` performs in production. No `MindTraining`, no `MindRealmSeed`,
## no `MindProvider.contribute`, no direct `pool.change`. The strike numbers come from the
## mechanism the COMPOSITION ROOT bound (`CombatBoot.bind_mechanisms`) read through
## `breakdown`, which is pure, so nothing here mutates a pool as a side effect of measuring.
##
## ## What each assertion is FOR
##
## Differences and bounds, never a restated formula. The only published number relied on is
## the reserve's OWN `maximum`, read off the pool: "a sitting restores a share of the
## maximum" is the contract, and the share itself is not restated anywhere below. A sitting
## that granted the whole reserve, restored pool-units instead of a share, or scaled itself
## with the realm each fail a distinct assertion here rather than one number changing.

## The bottom of the shared ladder, and the realm `ActorFactory.with_mind_cultivation`
## enrols by default.
const RANK := &"qi_refining"

## Sittings allowed for the re-arm walk. The refill is ten facade sittings
## (`AWARENESS_RATE 0.01` x `CULTIVATE_STEP 10.0`), so this is ~2.4x the honest answer:
## loose enough that float noise cannot fail it, tight enough that a refill restoring
## pool-units instead of a share of the maximum (needing ~1000) cannot pass it.
##
## SNAPSHOTTED BEFORE THE LOOP, never read off the pool the loop grows: the loop walks a
## fixed number of steps and breaks on arrival, so the bound cannot chase the thing it
## measures.
const REARM_BOUND := 24

## `ATTEND` strikes allowed to spend a full reserve. The drain is
## `awareness_ratio * erosion` (`mind_damage.gd:585`), which is GEOMETRIC in the ratio, so a
## reserve approaches zero without ever arriving: this bound is generous because the
## top-of-ladder drain per strike is roughly a tenth of the bottom's.
##
## SNAPSHOTTED BEFORE THE LOOP, never read off the pool the loop drains: the loop walks a
## fixed number of strikes and breaks on arrival, so the bound cannot shrink toward what it
## is measuring.
const SPEND_BOUND := 64

## What counts as SPENT. Below this ratio `coherence` is within `coherence_damp * 0.01` of
## its empty value, so the lever has stopped moving the strike and the reserve is spent for
## every purpose a player can observe. An exact `0.0` is unreachable by construction and a
## test that waited for one would walk the whole bound every time.
const SPENT_FLOOR := 0.01

## The share an `ATTEND` erosion takes of the reserve, as a fraction of what is held. Only
## used to assert a real FALL, never as the expected value: the production applier computed
## the delta and this file asserts the pool moved, rather than asserting its own arithmetic.
const SPEND_PROBE := 0.5


## A mind actor built exactly the way the game builds one: `ActorFactory.build`, then the
## mind enrolment. `PERCEPTION` and `MENTAL_CLARITY` are non-zero because `mental_attack` is
## built from them, so a fixture without them has `erosion == 0.0` and every comparison
## below would pass against a mechanism that read nothing at all.
func _actor(rank_id: StringName = RANK) -> Actor:
	var actor := ActorFactory.build(
		&"mind_reserve", {MindStats.PERCEPTION: 40.0, MindStats.MENTAL_CLARITY: 30.0}
	)
	return ActorFactory.with_mind_cultivation(actor, rank_id)


## The reserve the facade mints, read off the actor's public resource bag through the
## facade's own published id rather than the module constant behind it.
func _reserve(actor: Actor) -> ResourcePool:
	return actor.resource(MindCultivationApi.AWARENESS) as ResourcePool


## The mechanism the COMPOSITION ROOT bound to this actor. Bound once per actor: calling
## `bind_mechanisms` twice would register two slots, and this file asks for the strike's
## numbers on both sides of a comparison.
## TYPED, not `-> Variant`: `mechanism_of` answers a `DamageMechanism`, and a `Variant` here
## would make every `var x := _bound(...)` below an INFERRED-from-Variant assignment, which
## this project treats as a warning and therefore as an error.
func _bound(actor: Actor) -> DamageMechanism:
	if not CombatEngineApi.has_mechanism(actor):
		CombatBoot.bind_mechanisms(actor)
	return CombatEngineApi.mechanism_of(actor)


## An `AttackContext` for one strike, with the strike KIND staged the way production
## stages it (`MindDamage.builder`, ADR 0067's own injection point). Self-duel: an
## `AttackContext` takes one `Actor` per side and reads the live derived cache, so
## attacker and target being the same actor needs no second fixture and no hand-copied
## stat. `rng` stays null, which ADR 0067 makes the deterministic answer, so
## `mind_focus_chance` and `mind_avoidance` are exercised at their READ rather than at a
## dice outcome.
func _context(actor: Actor, kind_value: MindDamage.Kind) -> AttackContext:
	var mechanism := _bound(actor)
	if mechanism == null:
		return null
	var ctx := AttackContext.new(actor, actor)
	MindDamage.builder(kind_value, MindCultivationApi.sea(actor)).call(ctx)
	return ctx


## Every primitive ADR 0071's mind formula computed for one strike, as the mechanism the
## composition root bound reports it. Pure: measuring never mutates the actor.
func _parts(actor: Actor, kind_value: MindDamage.Kind = MindDamage.Kind.DISRUPT) -> Dictionary:
	var mechanism := _bound(actor)
	var ctx := _context(actor, kind_value)
	if mechanism == null or ctx == null:
		return {}
	return mechanism.breakdown(ctx)


## Land one strike's erosion through the PRODUCTION applier, reached through the module's
## own facade (`CombatEngineApi.apply_effects`, `combat_engine/api.gd:97`) rather than
## `CombatEffectApply` by name, so what this file asserts afterwards is the pool a player
## would see move rather than a hand-applied copy of `effect_apply.gd`'s arithmetic.
func _land(actor: Actor, kind_value: MindDamage.Kind) -> void:
	var mechanism := _bound(actor)
	var ctx := _context(actor, kind_value)
	if mechanism == null or ctx == null:
		return
	CombatEngineApi.apply_effects(actor, mechanism.resolve(ctx).effects, CombatTuning.shipped())


## An actor whose reserve the FACADE has carried to full, by sittings only. The bound is
## the constant above, walked with a `for` and broken on arrival -- no `while`, and nothing
## inside the loop grows the bound.
func _rearmed(rank_id: StringName = RANK) -> Actor:
	var actor := _actor(rank_id)
	var pool := _reserve(actor)
	if pool == null:
		return actor
	_sittings_to_full(actor, pool)
	return actor


## Facade sittings until the reserve reads full, counted. `REARM_BOUND` is a CONSTANT read
## here, before the `for` that walks it; the loop breaks on arrival and never reads a size it
## grew, so the bound cannot chase the pool it is filling.
func _sittings_to_full(actor: Actor, pool: ResourcePool) -> int:
	var sittings := 0
	for _step in REARM_BOUND:
		if pool.ratio() >= 1.0:
			break
		assert_eq(MindCultivationApi.cultivate(actor), true, "the sitting applied")
		sittings += 1
	return sittings


## `ATTEND` strikes, landed through the production applier, until the reserve reads spent.
## Same guard as above: `SPEND_BOUND` is a constant, the loop is a `for`, and it breaks on
## arrival.
##
## The sea's turbulence climbs through these, but `_capacity_of` (`mind_damage.gd:632`)
## reads `structural_capacity` and NOT `effective_capacity`, and the sea's `clarity` is not
## the `mental_clarity` base attribute `mental_defense` derives from -- so the erosion, and
## therefore the spend rate, does not feed back on itself across the walk.
func _strikes_to_spent(actor: Actor, pool: ResourcePool) -> int:
	var strikes := 0
	for _step in SPEND_BOUND:
		if pool.ratio() <= SPENT_FLOOR:
			break
		_land(actor, MindDamage.Kind.ATTEND)
		strikes += 1
	return strikes


# --- the writer ---------------------------------------------------------------------


## The load-bearing one. The reserve is minted EMPTY by the facade, so a rise after one
## facade sitting can only be a writer, and there is no other candidate: the delta is read
## off the actor's own pool and every verb below this one is a facade call.
func test_one_sitting_of_cultivation_restores_the_awareness_reserve() -> void:
	var actor := _actor()
	var pool := _reserve(actor)
	assert_ne(pool, null, "the facade mints the reserve")
	if pool == null:
		return
	assert_almost_eq(pool.current, 0.0, "and it is minted EMPTY, so any rise is a writer")
	assert_eq(MindCultivationApi.cultivate(actor), true, "the facade sitting applied")
	assert_eq(pool.current > 0.0, true, "one sitting moved the reserve: %f" % pool.current)
	assert_eq(pool.current <= pool.maximum, true, "and never past its own maximum")


## A sitting is a SHARE of the reserve, not a grant of it. Without this a writer that
## simply filled the pool passes the test above and makes ADR 0071's coherence lever a
## permanent stat rather than something a player re-arms by cultivating.
func test_one_sitting_restores_a_share_of_the_reserve_rather_than_all_of_it() -> void:
	var actor := _actor()
	var pool := _reserve(actor)
	assert_ne(pool, null, "the facade mints the reserve")
	if pool == null:
		return
	assert_eq(MindCultivationApi.cultivate(actor), true, "the facade sitting applied")
	assert_eq(
		pool.current < pool.maximum,
		true,
		(
			"one sitting restored %f of a %f reserve, not the whole thing"
			% [pool.current, pool.maximum]
		)
	)


## ADR 0071:20 promises coherence "1.0 -> 0.5 at full awareness". That needs a FULL
## reserve, so a refill a player could not finish would leave the promise unreachable in
## play rather than merely unstated. A refill restoring pool-units instead of a share of
## the maximum needs ~1000 sittings and fails here.
func test_the_reserve_reaches_a_full_ratio_within_a_bounded_number_of_sittings() -> void:
	var actor := _actor()
	var pool := _reserve(actor)
	assert_ne(pool, null, "the facade mints the reserve")
	if pool == null:
		return
	var sittings := _sittings_to_full(actor, pool)
	assert_almost_eq(pool.ratio(), 1.0, "so ADR 0071's 'at full awareness' is reachable")
	assert_eq(sittings > 0, true, "and reaching it took sittings rather than starting full")
	assert_eq(sittings <= REARM_BOUND, true, "inside the bound, not past it")


## The rate/magnitude guard, as a DIFFERENCE rather than a reading of source.
##
## The reserve's maximum is authored flat at pool creation and `synchronize` never rescales
## it, so a sitting that restores a share of it must restore the same POINTS at both ends of
## the ladder. A refill scaled by `RealmRate.factor` or by the meridian flow bonus would give
## the top of the ladder a permanently held lever while R1 fights bare -- a rate tracking a
## magnitude, which AGENTS.md forbids and which `tests/core/test_realm_rate.gd` exists to
## stop. Both realms are reached through the same facade call.
func test_one_sitting_restores_the_same_at_the_bottom_and_the_top_of_the_ladder() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(realms.size() > 1, true, "the shared ladder has more than one realm")
	if realms.size() < 2:
		return
	var low := _actor(realms[0].id)
	var high := _actor(realms[realms.size() - 1].id)
	var low_pool := _reserve(low)
	var high_pool := _reserve(high)
	assert_ne(low_pool, null, "the bottom of the ladder carries a reserve")
	assert_ne(high_pool, null, "and so does the top")
	if low_pool == null or high_pool == null:
		return
	assert_eq(MindCultivationApi.cultivate(low), true, "a sitting at the bottom applied")
	assert_eq(MindCultivationApi.cultivate(high), true, "a sitting at the top applied")
	# NOT VACUOUS: two reserves restored by nothing are also equal to each other, so without
	# this the equality below would pass on the very tree that broke BL-0651. A guard that
	# cannot tell "the same at both ends" from "absent at both ends" is not a guard.
	assert_eq(
		low_pool.current > 0.0, true, "so the bottom end restored something there is to compare"
	)
	assert_almost_eq(
		low_pool.maximum, high_pool.maximum, "the reserve's own scale is realm-invariant"
	)
	assert_almost_eq(
		low_pool.current,
		high_pool.current,
		"so one sitting restores the same points at both ends of the ladder"
	)


# --- across every realm boundary ------------------------------------------------------


## ## The realm question, measured at BOTH ends rather than derived
##
## ADR 0152's refill is realm-INDEPENDENT (`AWARENESS_RATE` is a share of a reserve whose
## maximum `api.gd:216` authors flat at `100.0`, and nothing rescales it). That is only
## safe if the lever is LIVE at both ends of the ladder. Two failure modes would relocate
## BL-0651 instead of closing it:
##
## - **Trivially unreachable** at one end -- a reserve no sitting can fill is decorative
##   again, which is the old bug with a writer attached.
## - **Trivially maxed** at one end -- a reserve nothing can spend makes `coherence` a
##   standing discount rather than a budget, and `coherence_damp` stops being a thing a
##   player spends.
##
## So both ends are walked and FOUR numbers are read per realm: the CEILING, the SITTINGS to
## reach it, the coherence at empty and at full, and the `ATTEND` STRIKES it takes to spend a
## full reserve. The assertions are the properties that must hold at EVERY realm -- the
## ceiling is positive and equal across realms, a full reserve costs more than one sitting
## and is reachable inside the bound, coherence falls strictly below 1.0 when funded and
## lands on the shipped floor, and a full reserve takes more than one strike to spend.
##
## The realm-DEPENDENT asymmetry this measures is ADR 0071's own, not the refill's:
## `erosion = base * coherence / sea.structural_capacity` (`mind_damage.gd:238`), and
## `sea_capacity` runs `100.0` at `qi_refining` to `825.0` at `primordial_origin` (the ladder's
## two ends, read off the seeds) while `mental_attack` carries only the bounded `RealmRate`
## factor, under 2x. So the drain per strike SHRINKS by roughly 4x across the ladder, and a
## flat refill buys proportionally more strikes at the top. That is not fixable from
## `training.gd` -- a realm-dependent rate against a flat ceiling would mean "deep realms
## refill faster for no authored reason" -- and ADR 0152 records it as measured.
func test_the_lever_is_live_at_both_ends_of_the_realm_ladder() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(realms.size() > 1, true, "the shared ladder has more than one realm")
	if realms.size() < 2:
		return
	var ceilings: Array[float] = []
	var sittings: Array[int] = []
	var strikes: Array[int] = []
	# The two ends are an `Array[int]` CONSTANT snapshotted BEFORE the walk, so the loop below
	# cannot grow the set of realms it is measured over. Typed rather than an array literal so
	# `index` is an int and `realms[index]` is a checked index rather than a Variant one.
	var ends: Array[int] = [0, realms.size() - 1]
	for index in ends:
		var rank_id: StringName = realms[index].id
		# (a) THE CEILING, and what stops the refill: `ResourcePool.change` clamps
		# (`resource_pool.gd:29`), so the maximum is the only thing that can stop it.
		var actor := _actor(rank_id)
		var pool := _reserve(actor)
		assert_ne(pool, null, "%s: the facade mints the reserve" % rank_id)
		if pool == null:
			continue
		assert_eq(pool.maximum > 0.0, true, "%s: the ceiling is positive" % rank_id)
		ceilings.append(pool.maximum)
		# (b) REACHABLE, and not in one sitting.
		var sittings_to_full := _sittings_to_full(actor, pool)
		sittings.append(sittings_to_full)
		assert_almost_eq(pool.ratio(), 1.0, "%s: a full ratio is reachable by sitting" % rank_id)
		assert_eq(
			sittings_to_full > 1,
			true,
			(
				"%s: and it costs %d sittings, so the refill is a share and not a grant"
				% [rank_id, sittings_to_full]
			)
		)
		# (c) THE FLOOR ADR 0071:20 promises. Read against the shipped damp rather than a
		# literal, so a balance retune is one edit in `combat_damage.tres` and not a
		# restated number in a test; the literal `0.5` is pinned by
		# `tests/modules/combat_engine/test_mind_damage.gd`, which owns the mechanism.
		var damp := float(CombatTuning.shipped().coherence_damp)
		var funded_coherence := float(_parts(actor).get("coherence", -1.0))
		assert_almost_eq(
			funded_coherence,
			1.0 - damp,
			"%s: a full reserve lands on the shipped coherence floor ADR 0071 promises" % rank_id,
			0.0001
		)
		# (d) SPENDABLE, and the spend is observable: coherence climbs back once the reserve
		# is gone, which is what makes this a budget rather than a standing discount.
		var strikes_to_spent := _strikes_to_spent(actor, pool)
		strikes.append(strikes_to_spent)
		assert_eq(
			strikes_to_spent > 1,
			true,
			(
				"%s: one ATTEND does not spend a full reserve (%d strikes did)"
				% [rank_id, strikes_to_spent]
			)
		)
		assert_eq(
			strikes_to_spent <= SPEND_BOUND,
			true,
			"%s: and it IS spent inside the bound, or the drain went with the writer" % rank_id
		)
		var spent_coherence := float(_parts(actor).get("coherence", -1.0))
		assert_eq(
			spent_coherence > funded_coherence,
			true,
			(
				"%s: so an emptied reserve takes the next strike HARDER (%.4f -> %.4f)"
				% [rank_id, funded_coherence, spent_coherence]
			)
		)
	if ceilings.size() < 2 or sittings.size() < 2 or strikes.size() < 2:
		return
	# The refill and the ceiling are both realm-invariant, asserted as differences so neither
	# restates a value: a rate scaled by `RealmRate.factor` would fail this and pass every
	# behavioural assertion above, because it would still move the number.
	assert_almost_eq(
		ceilings[0], ceilings[1], "the reserve's ceiling is the same at both ends of the ladder"
	)
	assert_eq(
		sittings[0],
		sittings[1],
		"and so is the cost of filling it, so the rate never tracks the realm"
	)


# --- the player-visible consequence -------------------------------------------------


## The consequence ADR 0071:35 sells awareness as lever (1) of four: a funded reserve HALVES
## the coherence of the next mind strike, and erosion is linear in coherence, so the strike
## costs half as much of the sea.
##
## Asserted as two RATIOS rather than as the shipped `0.5`: `coherence_damp` is authored on
## `combat_damage.tres` and retuning it is not this file's business, but a funded reserve
## that did not move the coherence is precisely the defect, so `coherence < 1.0` is the
## mutation target and the erosion ratio is what a player pays.
func test_a_reserve_the_facade_funded_halves_what_the_next_mind_strike_lands() -> void:
	var bare_parts := _parts(_actor())
	assert_almost_eq(
		float(bare_parts.get("awareness_ratio", -1.0)), 0.0, "an unfunded reserve reads 0.0"
	)
	assert_almost_eq(
		float(bare_parts.get("coherence", 0.0)), 1.0, "so an empty reserve costs nothing"
	)
	var bare_erosion := float(bare_parts.get("erosion", 0.0))
	assert_eq(bare_erosion > 0.0, true, "and the strike lands, so the halves below compare")

	var held := _rearmed()
	var held_parts := _parts(held)
	assert_almost_eq(
		float(held_parts.get("awareness_ratio", 0.0)), 1.0, "a facade-funded reserve reads FULL"
	)
	var held_coherence := float(held_parts.get("coherence", 1.0))
	var held_erosion := float(held_parts.get("erosion", 0.0))
	assert_eq(held_coherence < 1.0, true, "so the shipped COHERENCE_DAMP is live at last")
	assert_eq(held_erosion < bare_erosion, true, "and the strike lands softer for it")
	assert_almost_eq(
		held_erosion / bare_erosion,
		held_coherence / float(bare_parts.get("coherence", 1.0)),
		"by exactly the coherence it removed, because erosion is linear in coherence",
		0.0001
	)


## And the reserve is a COMBAT resource, not a standing stat: an `ATTEND` erosion spends
## what the facade funded, through the production applier, and the empty reserve has nothing
## to spend -- which is the half of the drain that was inert before (BL-0651's third
## consequence).
func test_an_attend_erosion_spends_a_reserve_the_facade_funded() -> void:
	var held := _rearmed()
	var pool := _reserve(held)
	assert_ne(pool, null, "the funded actor carries the reserve")
	if pool == null:
		return
	var empty_parts := _parts(_actor(), MindDamage.Kind.ATTEND)
	assert_almost_eq(
		float(empty_parts.get("awareness_delta", -1.0)),
		0.0,
		"an empty reserve reports no drain to spend"
	)
	var before := pool.current
	_land(held, MindDamage.Kind.ATTEND)
	assert_eq(pool.current < before, true, "ATTEND spent it: %f -> %f" % [before, pool.current])
	assert_eq(pool.current >= 0.0, true, "and can empty it without inverting it")


## The whole loop a player actually performs, end to end and through the facade: fund the
## reserve by sitting, have a mind duel spend it, then sit again and get it back. The refund
## is asserted as a RETURN TO THE MEASURED PEAK rather than to a stated rate, so this test
## does not restate how much one sitting restores -- that is the previous test's subject.
func test_a_duel_that_spends_the_reserve_leaves_it_re_armable_by_sitting() -> void:
	var actor := _rearmed()
	var pool := _reserve(actor)
	assert_ne(pool, null, "the funded actor carries the reserve")
	if pool == null:
		return
	var peak := pool.current
	_land(actor, MindDamage.Kind.ATTEND)
	var spent := pool.current
	assert_eq(spent < peak, true, "the duel spent the reserve: %f -> %f" % [peak, spent])
	# The bound is snapshotted HERE, before the loop, and the loop walks a fixed number of
	# sittings: it never reads a size the loop itself grows.
	for _step in REARM_BOUND:
		if pool.current >= peak:
			break
		assert_eq(MindCultivationApi.cultivate(actor), true, "the re-arm sitting applied")
	assert_eq(pool.current >= peak, true, "and sitting put it back: %f" % pool.current)
	assert_eq(
		pool.current <= peak, true, "without exceeding it, because `change` clamps at maximum"
	)


## One writer. `meditate` is ADR 0071:35's lever (2) and is deliberately NOT lever (1):
## fusing them would make a single verb own two of the four defensive levers, and
## `meditate` is refused outright when there is no turbulence to calm, so it could not
## re-arm a reserve a clean duel emptied in the first place.
##
## FUNDED FIRST, and that is the point: an empty reserve cannot be "re-armed by nothing", so
## meditating against one would pass on the very tree that broke BL-0651. The reserve is
## carried to full through the facade before meditation, so the only way this fails is if
## `meditate` writes it.
func test_meditating_re_arms_nothing() -> void:
	var actor := _rearmed()
	var sea := MindCultivationApi.sea(actor)
	assert_ne(sea, null, "the actor carries a sea")
	var pool := _reserve(actor)
	if sea == null or pool == null:
		return
	sea.add_turbulence(SPEND_PROBE)
	var held := pool.current
	assert_eq(held > 0.0, true, "the reserve is FUNDED, so 'unchanged' is a real claim")
	assert_eq(MindCultivationApi.meditate(actor), true, "meditation applied against turbulence")
	assert_almost_eq(
		sea.turbulence, SPEND_PROBE - MindCultivationApi.MEDITATE_STEP, "and it calmed the sea"
	)
	assert_almost_eq(pool.current, held, "while re-arming no part of the awareness reserve")
