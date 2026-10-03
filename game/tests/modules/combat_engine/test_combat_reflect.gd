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
	# mechanism produced. 100 produced, 60 absorbed, 40 overflow, 40% rate x 100% share.
	var target := _thorns(0.4, 1.0)
	target.set_component(CombatSpine.SHIELD_COMPONENT, FakeShield.new(60.0))
	var outcome := _resolve(_attacker(), target, 100.0)
	assert_almost_eq(outcome.absorbed, 60.0, "60 to the shield")
	assert_almost_eq(outcome.overflow, 40.0, "40 to health")
	assert_almost_eq(outcome.reflected, 40.0 * 0.4, "and the bounce reads the overflow")


func test_the_bounce_is_paid_to_the_attacker_and_not_only_recorded() -> void:
	# `outcome.reflected` documents what "bounced back". A number a readout shows a player
	# while no pool is charged is a tax with no effect, and the assertion below was the
	# only place in the suite that could have caught it — every other case read the field
	# and never the attacker's health.
	var target := _thorns(0.4, 1.0)
	var attacker := _attacker()
	var before := attacker.resource(&"health").current
	var outcome := _resolve(attacker, target, 100.0)
	assert_almost_eq(outcome.reflected, 40.0, "40 came back")
	assert_almost_eq(
		attacker.resource(&"health").current, before - 40.0, "and the attacker was charged it"
	)
	assert_almost_eq(outcome.health_delta, -40.0, "S9's own delta is untouched by S10")


func test_the_share_bounds_what_thorns_can_return() -> void:
	# ADR 0068: "`reflect.share` is bounded below 1.0, so thorns can at most tie against
	# an equal-health attacker and never win a trade outright." A share above 1.0 is a
	# content error and is CLAMPED, not honoured.
	var target := _thorns(1.0, 5.0)
	var outcome := _resolve(_attacker(), target, 40.0)
	assert_almost_eq(outcome.reflected, 40.0, "a share of 5.0 is clamped to 1.0 and can only tie")


# --- rate contest ---------------------------------------------------------------


func test_the_bounce_rate_is_linear_from_zero() -> void:
	var none := CombatTestKit.actor(&"thorns")
	var outcome := _resolve(_attacker(), none, 40.0)
	assert_almost_eq(outcome.reflected, 0.0, "no reflect stat, no bounce — not 50% of one")


func test_resist_removes_the_bounce_before_it_is_paid() -> void:
	var target := _thorns(0.5, 1.0)
	# The attacker invests in `reflect.resist.rate` at exactly the thorns' rate, so the
	# contest reads zero and nothing comes back.
	var attacker := _attacker()
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(
			CombatStats.REFLECT_RESIST_RATE, _tuning.rate_scale * 0.5, &"test"
		)
	)
	var outcome := _resolve(attacker, target, 40.0)
	assert_almost_eq(outcome.reflected, 0.0, "parity reads zero, so the bounce is refused")


func test_partial_resist_leaves_part_of_the_bounce() -> void:
	var target := _thorns(0.5, 1.0)
	var attacker := _attacker()
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(
			CombatStats.REFLECT_RESIST_RATE, _tuning.rate_scale * 0.25, &"test"
		)
	)
	var outcome := _resolve(attacker, target, 40.0)
	assert_almost_eq(outcome.reflected, 40.0 * 0.25, "the contest is a subtraction")


# --- the chain ------------------------------------------------------------------


func test_self_reflection_is_never_an_infinite_bounce() -> void:
	# Two actors who both thorn at a full rate, with nothing to stop the exchange. The
	# loop must terminate at the depth limit and must not exceed a bounded total.
	var attacker := _attacker()
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.REFLECT_RATE, _tuning.rate_scale, &"test")
	)
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
		attacker,
		target,
		CombatTestKit.technique(100.0),
		_tuning,
		null,
		Callable(),
		chain_depth
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
	# `reflect.damage` is a share, so a hostile value is clamped. `reflect.rate` is
	# linear-from-zero, so a hostile value saturates at 1.0. Neither can divide by zero.
	var target := _thorns(1.0, 1e9)
	var outcome := _resolve(_attacker(), target, 40.0)
	assert_eq(is_finite(outcome.reflected), true, "finite")
	assert_almost_eq(outcome.reflected, 40.0, "and clamped to a tie")


# --- S11, leech -----------------------------------------------------------------


func test_leech_is_a_separate_packet_paid_after_the_health_write() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.resource(&"health").change(-100.0)
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.LIFESTEAL, _tuning.rate_scale * 0.5, &"test")
	)
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
	assert_almost_eq(outcome.lifesteal, 20.0, "half of what was spent came back")
	assert_almost_eq(
		attacker.resource(&"health").current, attacker_before + 20.0, "as a separate packet"
	)
	assert_almost_eq(outcome.amount, 40.0, "and the incoming hit was NOT reduced by it")


func test_leech_pays_only_on_what_reached_health() -> void:
	# Read from the pool's own movement, so a shield fully absorbing the hit heals
	# nothing and a hit against a nearly-dead target heals only what it actually took.
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	attacker.resource(&"health").change(-100.0)
	attacker.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.LIFESTEAL, _tuning.rate_scale * 0.5, &"test")
	)
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
	assert_almost_eq(dead_outcome.lifesteal, 2.5, "but only 5 actually left the pool")


func test_an_unstatted_attacker_leeches_nothing() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	var outcome := CombatSpine.resolve_hit(
		attacker, CombatTestKit.actor(&"target"), CombatTestKit.technique(100.0), _tuning, null
	)
	assert_almost_eq(outcome.lifesteal, 0.0, "linear-from-zero, so 0.0 leeches 0.0")


# --- internals ------------------------------------------------------------------


func _attacker() -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	return attacker


## A target that reflects at `rate` (as a fraction of `rate_scale`) and returns `share`
## of what it takes.
func _thorns(rate: float, share: float) -> Actor:
	var target := CombatTestKit.actor(&"thorns")
	target.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.REFLECT_RATE, _tuning.rate_scale * rate, &"test")
	)
	target.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_DAMAGE, share, &"test"))
	return target


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
