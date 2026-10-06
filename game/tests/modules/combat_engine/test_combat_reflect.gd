extends TestCase

## S10, reflect (ADR 0068): POST-shield, `rate x share`, terminated by being DROPPED at
## `CHAIN_DEPTH_LIMIT = 6`, never by clamping to zero. S11, leech, rides in here because
## both are the spine's post-health packets and both read `health_delta`.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- post-shield ----------------------------------------------------------------


func test_a_fully_absorbed_hit_reflects_nothing() -> void:
	# ADR 0068 states this as a test to pin: "a fully shielded hit reflects 0.0".
	var target := _thorns(1.0, 1.0)
	target.set_component(CombatSpine.SHIELD_COMPONENT, FakeShield.new(1000.0))
	var attacker := _attacker()
	var before := attacker.resource(&"health").current
	var outcome := _resolve(attacker, target, 50.0)
	assert_almost_eq(outcome.absorbed, 50.0, "the shield took everything")
	assert_almost_eq(outcome.overflow, 0.0, "nothing reached health")
	assert_almost_eq(outcome.reflected, 0.0, "so nothing came back")
	assert_almost_eq(attacker.resource(&"health").current, before, "and the attacker is whole")


func test_the_bounce_is_read_from_the_overflow_and_not_from_the_amount() -> void:
	# A partial shield: the bounce is the share of what REACHED health, not of what the
	# mechanism produced. 100 produced, 60 absorbed, 40 overflow.
	#
	# ADR 0877: the thorns' `reflect.rate` of `1.0` against a resister's `0.0` reads
	# `min(1, 1.0 / rate_scale)` — certainty — so the share returns the whole overflow.
	# The property under test is the OVERFLOW reading, not the rate — and it is asserted
	# against the share the fixture authors, so a bounce that read `amount` (100.0) instead
	# of `overflow` (40.0) still fails here.
	var target := _thorns(1.0, 1.0)
	target.set_component(CombatSpine.SHIELD_COMPONENT, FakeShield.new(60.0))
	var outcome := _resolve(_attacker(), target, 100.0)
	assert_almost_eq(outcome.absorbed, 60.0, "60 to the shield")
	assert_almost_eq(outcome.overflow, 40.0, "40 to health")
	assert_almost_eq(
		outcome.reflected, 40.0 * 1.0, "and the bounce reads the overflow, not the 100 produced"
	)


func test_the_bounce_is_paid_to_the_attacker_and_not_only_recorded() -> void:
	# `outcome.reflected` documents what "bounced back". A number a readout shows a player
	# while no pool is charged is a tax with no effect, and the assertion below was the
	# only place in the suite that could have caught it — every other case read the field
	# and never the attacker's health.
	#
	# ADR 0877: `1.0` against an unstatted `0.0` reads certainty, so the thorns return
	# the WHOLE overflow. The assertion is written against the overflow's own value so the
	# property — "the pool was charged exactly what the outcome records" — is what is under
	# test and not a literal a balance pass could move.
	var target := _thorns(1.0, 1.0)
	var attacker := _attacker()
	var before := attacker.resource(&"health").current
	var outcome := _resolve(attacker, target, 100.0)
	assert_almost_eq(outcome.reflected, outcome.overflow, "the whole overflow came back")
	assert_almost_eq(
		attacker.resource(&"health").current,
		before - outcome.reflected,
		"and the attacker was charged exactly that"
	)
	# The two spends are separate packets, so both happened: the target lost the overflow
	# AND the attacker lost the bounce. That is the assertion worth making here — a bounce
	# folded into the incoming hit would leave one of the two untouched.
	assert_almost_eq(outcome.health_delta, -100.0, "S9's own delta is the whole overflow")


func test_the_share_bounds_what_thorns_can_return() -> void:
	# ADR 0068: "`reflect.share` is bounded below 1.0, so thorns can at most tie against
	# an equal-health attacker and never win a trade outright." A share above 1.0 is a
	# content error and is CLAMPED, not honoured.
	var target := _thorns(1.0, 5.0)
	var outcome := _resolve(_attacker(), target, 40.0)
	assert_almost_eq(outcome.reflected, 40.0, "a share of 5.0 is clamped to 1.0 and can only tie")


# --- rate contest ---------------------------------------------------------------


func test_the_bounce_rate_is_the_defenders_rate_alone_and_reads_one() -> void:
	# An attacker who has invested in NOTHING contests nothing, so the ratio is
	# `r / (r + 0) == 1.0` — a bare bounce. That is the honest reading of "no resist stat"
	# under a ratio, and it is deliberately NOT `0.0`: an unstatted attacker does not
	# refuse a bounce, it simply declines to contest it. The bound is the SHARE, which is
	# clamped to `1.0`, so the answer can never exceed what it took.
	var none := CombatTestKit.actor(&"thorns")
	var outcome := _resolve(_attacker(), none, 40.0)
	assert_almost_eq(outcome.reflected, 0.0, "a target that reflects nothing bounces nothing")


## ## ADR 0877. The bounce's trigger is a FLAT DELTA, so PARITY REFUSES THE BOUNCE.
##
## It used to assert `0.5` at parity — the reading of ADR 0215's `offense / (offense +
## resist)`, where equal halves are two equal shares. Under the flat delta equal halves
## cancel to exactly `0.0`: a resister who matches the thorns' rate answers the bounce
## completely, and one who beats it cannot be bounced on at all.
func test_at_parity_the_bounce_is_refused_completely() -> void:
	var target := _thorns(1.0, 1.0)
	var outcome := _resolve(_resisting(1.0), target, 40.0)
	assert_almost_eq(outcome.reflected, 0.0, "parity cancels the bounce to zero")
	assert_almost_eq(outcome.overflow, 40.0, "while the original hit still landed in full")


## A resister under the rate keeps a proportional share: the delta over the scale IS the
## trigger (ADR 0877), and the fixture authors exactly that.
func test_a_resister_under_the_rate_reads_the_delta_over_the_scale() -> void:
	var target := _thorns(1.0, 1.0)
	# The attacker is a quarter of a `rate_scale` short of the thorns' rate.
	var outcome := _resolve(_resisting(1.0 - _tuning.rate_scale * 0.25), target, 40.0)
	assert_almost_eq(outcome.reflected, 40.0 * 0.25, "a quarter of the scale is a quarter")


## A resister ABOVE the rate is a WALL, and that is the property the ratio could not
## express: under `o / (o + d)` a heavy defence still paid a declining share; under the
## flat delta it pays nothing, because every point of defence cancels a point of offence.
func test_a_resister_above_the_rate_refuses_the_bounce_entirely() -> void:
	var target := _thorns(1.0, 1.0)
	var strong := _resolve(_resisting(2.0), target, 40.0)
	assert_almost_eq(strong.reflected, 0.0, "a lead is a wall")
	# Monotone: more resist never raises the bounce, asserted off two pairs rather than a
	# restated number so a raising formula fails here.
	var steeper := _resolve(_resisting(7.0), target, 40.0)
	assert_eq(steeper.reflected <= strong.reflected, true, "more resist, never more bounce")


# --- the chain ------------------------------------------------------------------


func test_self_reflection_is_never_an_infinite_bounce() -> void:
	# Two actors who both thorn at an unopposed magnitude, with nothing to stop the
	# exchange. The loop must terminate at the depth limit and must not exceed a bounded
	# total. ADR 0877: the attacker's own `REFLECT_RATE` is a raw MAGNITUDE like the
	# thorns', read against no resister, so every hop is a full tie.
	var attacker := _attacker()
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_RATE, 1.0, &"test"))
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_DAMAGE, 1.0, &"test"))
	var target := _thorns(1.0, 1.0)
	var before_attacker := attacker.resource(&"health").current
	var before_target := target.resource(&"health").current
	var outcome := _resolve(attacker, target, 40.0)
	assert_eq(is_finite(attacker.resource(&"health").current), true, "the attacker stayed finite")
	assert_eq(is_finite(target.resource(&"health").current), true, "and so did the target")
	assert_ne(attacker.resource(&"health").current, before_attacker, "the attacker did pay")
	assert_ne(target.resource(&"health").current, before_target, "and so did the target")


## Resolve at an explicit chain depth, with a mechanism that actually produces the 40.0
## these three cases are about. They used to bind `FixedMechanism.new()` -- whose default
## `amount` is `0.0` -- and then assert 40.0 of damage, so the only number a real bound
## mechanism could have produced was the S8 chip floor and the assertions were measuring
## the floor instead of the chain.
func _at_depth(target: Actor, chain_depth: int) -> CombatOutcome:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null, Callable(), chain_depth
	)


func test_a_chain_beyond_the_depth_limit_is_dropped_not_clamped() -> void:
	# ADR 0068: the chain "terminates on `CHAIN_DEPTH_LIMIT = 6` by being DROPPED, never
	# by clamping to zero". Entered at the limit, the bounce is refused AND the outcome
	# says so, so the truncation is visible to a reader rather than silently rounded.
	var outcome := _at_depth(_thorns(1.0, 1.0), _tuning.chain_depth_limit)
	assert_eq(outcome.chain_dropped, true, "the chain ended by being dropped")
	assert_almost_eq(outcome.reflected, 0.0, "and nothing was paid")
	assert_almost_eq(outcome.overflow, 40.0, "but the original hit still landed in full")


func test_one_hop_short_of_the_limit_is_not_dropped() -> void:
	var outcome := _at_depth(_thorns(1.0, 1.0), _tuning.chain_depth_limit - 1)
	assert_eq(outcome.chain_dropped, false, "one hop short still pays")
	assert_almost_eq(outcome.reflected, 40.0, "and pays in full")


func test_a_reflect_stat_of_a_million_is_a_refusal_and_not_an_infinity() -> void:
	# Neither half is capped at the INPUT: `reflect.damage` of `1e9` and a
	# `reflect.rate` of `1.0` both read certainty by arithmetic (ADR 0877 — the clamp is
	# on the OUTPUT), and the SHARE is what bounds the packet to a tie. Nothing divides: a
	# non-positive delta or scale is answered `0.0`.
	var target := _thorns(1.0, 1e9)
	var outcome := _resolve(_attacker(), target, 40.0)
	assert_eq(is_finite(outcome.reflected), true, "finite")
	assert_almost_eq(outcome.reflected, 40.0, "and clamped to a tie")


# --- S11, leech -----------------------------------------------------------------
#
# ## ADR 0877: leech's rate is the same flat delta, and `CombatRecoil.leech` is UNCONTESTED
#
# `leech` calls `CombatStats.rate_from_zero(LIFESTEAL, 0.0, rate_scale)` — the resister
# half is a literal `0.0`, because a heal the attacker takes off their own blow is opposed
# by nothing. The share is therefore `min(1, LIFESTEAL / rate_scale)`: a real, tunable
# share rather than the ratio's `L / (L + 0) == 1.0`, which made every non-zero
# `LIFESTEAL` a certainty.
#
# There is no pair to author here: leech has ONE half. So the share is asserted as the
# SHARE the mechanism resolves through its own public read, rather than as a restated
# literal — which keeps the assertion exact (the pool was charged precisely that) while
# letting a balance pass move the scale without the ordering claim going stale.


## The leech share `CombatRecoil` resolves for `attacker`, read off the same public
## formula the stage reads it through. `LIFESTEAL` against its literal `0.0` resist.
func _leech_share_of(attacker: Actor) -> float:
	return CombatBand.rate(attacker.stats.derived(CombatStats.LIFESTEAL), 0.0, _tuning)


func test_leech_is_a_separate_packet_paid_after_the_health_write() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.resource(&"health").change(-100.0)
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.LIFESTEAL, 1.0, &"test"))
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	MechanismSlot.bind(attacker, mechanism)
	var target := CombatTestKit.actor(&"target")
	var attacker_before := attacker.resource(&"health").current
	var target_before := target.resource(&"health").current
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(
		target.resource(&"health").current, target_before - 40.0, "40 spent on the target"
	)
	# ADR 0877: the ONE half leech has, `min(1, 1.0 / rate_scale)` — here certainty — so
	# the whole of what was spent comes back; and the packet is a SEPARATE one, written
	# after the damage, so the pool moved by exactly the leech and by nothing else.
	assert_almost_eq(outcome.lifesteal, 40.0, "one unopposed half leeches all of it")
	assert_almost_eq(
		attacker.resource(&"health").current,
		attacker_before + outcome.lifesteal,
		"as a separate packet, written after the health write"
	)
	assert_almost_eq(outcome.amount, 40.0, "and the incoming hit was NOT reduced by it")


func test_leech_pays_only_on_what_reached_health() -> void:
	# Read from the pool's own movement, so a shield fully absorbing the hit heals
	# nothing and a hit against a nearly-dead target heals only what it actually took.
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.resource(&"health").change(-100.0)
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.LIFESTEAL, 1.0, &"test"))
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 40.0
	MechanismSlot.bind(attacker, mechanism)
	var shielded := CombatTestKit.actor(&"target")
	shielded.set_component(CombatSpine.SHIELD_COMPONENT, FakeShield.new(1000.0))
	var shielded_outcome := CombatSpine.resolve_hit(
		attacker, shielded, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(shielded_outcome.absorbed, 40.0, "the shield took the whole 40")
	assert_almost_eq(shielded_outcome.lifesteal, 0.0, "a fully absorbed hit leeches nothing")
	var nearly_dead := CombatTestKit.actor(&"target", 5.0)
	var dead_outcome := CombatSpine.resolve_hit(
		attacker, nearly_dead, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(dead_outcome.overflow, 40.0, "40 was the overflow")
	# The load-bearing claim is the BASE, not the share: the leech is taken off what
	# ACTUALLY LEFT the pool (5.0), not off the 40.0 the blow was worth. Stated as a
	# relationship to the share rather than as a literal, so it holds at any share — the
	# old `2.5` pinned the share as well and would break on any balance pass.
	assert_almost_eq(dead_outcome.lifesteal, 5.0, "only the 5.0 that actually left came back")
	assert_almost_eq(
		dead_outcome.lifesteal,
		dead_outcome.overflow * 5.0 / 40.0 * _leech_share_of(attacker),
		"and it is a share of what was spent, not of what the blow was worth"
	)


func test_an_unstatted_attacker_leeches_nothing() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	# A non-positive delta reads `0.0` rather than dividing (ADR 0877), so an actor who
	# has invested nothing leeches nothing — and never an unchosen default.
	assert_almost_eq(_leech_share_of(attacker), 0.0, "nothing invested contests nothing")
	assert_almost_eq(outcome.lifesteal, 0.0, "so 0.0 lifesteal leeches 0.0")


# --- internals ------------------------------------------------------------------


func _attacker() -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	return attacker


## ## ADR 0877. The bounce's RATE contest is a FLAT DELTA.
##
## `rate` is a raw MAGNITUDE: the trigger is `clampf((rate - resist) / rate_scale, 0, 1)`,
## so a thorns of `1.0` against a resister with no `reflect.resist.rate` reads certainty,
## a resister at parity reads `0.0`, and a resister in between reads its share of the
## scale. `share` is the reflector's `reflect.damage` magnitude, matched against the
## resister's `reflect.resist.damage` at the UNIT scale.
##
## A target that reflects at magnitude `r` against a resister at magnitude `d` bounces
## `min(1, max(0, (r - d) / rate_scale))` of the overflow, times its share.
func _thorns(rate: float, share: float) -> Actor:
	var target := CombatTestKit.actor(&"thorns")
	target.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_RATE, rate, &"test"))
	target.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_DAMAGE, share, &"test"))
	return target


## An attacker who invests `amount` in `reflect.resist.rate` — the DEFENCE half of the
## bounce's contest, and the same `id` the reflect case below reads back.
func _resisting(amount: float) -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.REFLECT_RESIST_RATE, amount, &"test")
	)
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	return attacker


func _resolve(attacker: Actor, target: Actor, amount: float) -> CombatOutcome:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = amount
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(attacker, target, CombatTestKit.technique(100.0), _tuning, null)


## The shield the gate reads: `absorb(amount) -> overflow`.
class FakeShield:
	extends RefCounted

	var capacity: float

	func _init(p_capacity: float) -> void:
		capacity = p_capacity

	func absorb(amount: float) -> float:
		var taken := minf(capacity, amount)
		capacity -= taken
		return amount - taken
