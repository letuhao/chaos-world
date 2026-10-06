extends TestCase

## S9, the shield gate (ADR 0067 S9, ADR 0068's post-shield reflect).
##
## `CombatShield.absorb(amount, penetration) -> overflow`: it returns what it did NOT
## take. This suite pins
## the gate's four cases and, because ADR 0068 makes reflect read the overflow, the
## fifth thing the gate has to get right — a fully absorbed hit must leave the overflow
## at exactly zero.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the four cases ------------------------------------------------------------


func test_a_shield_over_the_damage_absorbs_all_of_it() -> void:
	var outcome := _hit(&"target", 50.0, 30.0)
	assert_almost_eq(outcome.absorbed, 30.0, "the shield took all 30")
	assert_almost_eq(outcome.overflow, 0.0, "and returned no overflow")


func test_a_shield_under_the_damage_returns_the_difference_as_overflow() -> void:
	# The shield's OWN return is the overflow, so a shield that is NOT over the damage is
	# the only case where the two fields differ. (This case used to be a second copy of the
	# one above with the two expectations swapped -- `_hit(50.0, 30.0)` cannot both "take
	# all 30" and "take nothing" -- so it never asserted what its name said.)
	var outcome := _hit(&"target", 20.0, 30.0)
	assert_almost_eq(
		outcome.overflow, 10.0, "absorb's return IS the overflow, not the amount taken"
	)
	assert_almost_eq(outcome.absorbed, 20.0, "and the shield kept its 20")


func test_a_shield_under_the_damage_returns_the_difference() -> void:
	var outcome := _hit(&"target", 50.0, 80.0)
	assert_almost_eq(outcome.absorbed, 50.0, "the shield took its 50")
	assert_almost_eq(outcome.overflow, 30.0, "and the overflow is the rest")


# The three claims below are the gate's WHOLE contract, and they are deliberately three
# separate tests because one combined assertion passes with two of them broken: `absorbed`
# and `overflow` can both read right while the health write spends the wrong one, and
# `overflow` can read right while S10 reflects `amount` instead of it.


func test_the_health_write_follows_the_overflow_and_not_the_shielded_share() -> void:
	var target := CombatTestKit.actor(&"target")
	target.set_component(CombatSpine.SHIELD_COMPONENT, _FakeShield.new(30.0))
	var before := target.resource(&"health").current
	var outcome := _hit_on(&"target", target, 30.0, 50.0)
	assert_almost_eq(outcome.absorbed, 30.0, "the shield took its 30")
	assert_almost_eq(outcome.overflow, 20.0, "20 reached health")
	assert_almost_eq(
		target.resource(&"health").current,
		before - 20.0,
		"and the pool lost the OVERFLOW, not the shielded 30"
	)
	assert_almost_eq(outcome.health_delta, -20.0, "the one sign flip, on the overflow")


func test_a_fully_absorbed_hit_leaves_the_pool_untouched() -> void:
	var target := CombatTestKit.actor(&"target")
	target.set_component(CombatSpine.SHIELD_COMPONENT, _FakeShield.new(1000.0))
	var before := target.resource(&"health").current
	var outcome := _hit_on(&"target", target, 1000.0, 50.0)
	assert_almost_eq(outcome.absorbed, 50.0, "the shield took all 50")
	assert_almost_eq(outcome.overflow, 0.0, "and nothing overflowed")
	assert_almost_eq(target.resource(&"health").current, before, "so the pool is untouched")
	assert_almost_eq(outcome.health_delta, 0.0, "and no health was spent at all")


func test_no_shield_passes_the_damage_whole() -> void:
	var outcome := _hit(&"target", 0.0, 30.0)
	assert_almost_eq(outcome.absorbed, 0.0, "nothing absorbed")
	assert_almost_eq(outcome.overflow, 30.0, "and the whole amount reached health")


func test_no_shield_component_at_all_still_spends_health() -> void:
	# Not "no shield" — no COMPONENT. An actor nobody ever attached one to must still be
	# hittable, which is the difference between an absent shield and a null one.
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	var target := CombatTestKit.actor(&"target")
	assert_eq(target.component(CombatSpine.SHIELD_COMPONENT), null, "genuinely unbound")
	var outcome := _resolve(attacker, target, 30.0)
	assert_almost_eq(outcome.overflow, 30.0, "the damage passes whole")
	assert_almost_eq(outcome.absorbed, 0.0, "and nothing was absorbed")


func test_an_empty_shield_component_absorbs_nothing_rather_than_crashing() -> void:
	# The slot is duck-typed (see `CombatSpine._absorb`), so a component in the shield
	# slot that is not a shield must degrade to "no shield" and not take the hit down.
	var target := CombatTestKit.actor(&"target")
	target.set_component(CombatSpine.SHIELD_COMPONENT, RefCounted.new())
	var outcome := _hit_on(&"target", target, 50.0, 30.0)
	assert_almost_eq(outcome.absorbed, 0.0, "a non-shield absorbs nothing")
	assert_almost_eq(outcome.overflow, 30.0, "and the hit still lands")


# --- post-shield reads ---------------------------------------------------------


func test_a_fully_absorbed_hit_reflects_nothing() -> void:
	# ADR 0068: "Reflection is POST-shield, so a fully absorbed hit reflects nothing".
	var target := CombatTestKit.actor(&"target")
	target.set_component(CombatSpine.SHIELD_COMPONENT, _FakeShield.new(50.0))
	target.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.REFLECT_RATE, _tuning.rate_scale, &"test")
	)
	target.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_DAMAGE, 1.0, &"test"))
	var attacker := _attacker()
	var before := attacker.resource(&"health").current
	var outcome := _resolve(attacker, target, 30.0)
	assert_almost_eq(outcome.overflow, 0.0, "the shield took it all")
	assert_almost_eq(outcome.reflected, 0.0, "so nothing reflects")
	assert_almost_eq(attacker.resource(&"health").current, before, "and the attacker is untouched")


func test_only_the_overflow_is_reflected() -> void:
	var target := CombatTestKit.actor(&"target")
	target.set_component(CombatSpine.SHIELD_COMPONENT, _FakeShield.new(50.0))
	target.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.REFLECT_RATE, _tuning.rate_scale, &"test")
	)
	target.stats.add_modifier(CombatStats.rate_modifier(CombatStats.REFLECT_DAMAGE, 1.0, &"test"))
	var attacker := _attacker()
	var before := attacker.resource(&"health").current
	# A 100 HP mechanism amount against a 50 shield leaves 50 of overflow; the bounce is
	# read from the 50, not the 100.
	var outcome := _resolve(attacker, target, 100.0)
	assert_almost_eq(outcome.absorbed, 50.0, "the shield took 50")
	assert_almost_eq(outcome.overflow, 50.0, "50 reached health")
	assert_almost_eq(outcome.reflected, 50.0, "and 50 came back")


# --- internals -----------------------------------------------------------------


func _attacker() -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	return attacker


func _hit(id: StringName, capacity: float, amount: float) -> CombatOutcome:
	var target := CombatTestKit.actor(id)
	if capacity > 0.0:
		target.set_component(CombatSpine.SHIELD_COMPONENT, _FakeShield.new(capacity))
	return _hit_on(id, target, capacity, amount)


func _hit_on(_id: StringName, target: Actor, _capacity: float, amount: float) -> CombatOutcome:
	return _resolve(_attacker(), target, amount)


func _resolve(attacker: Actor, target: Actor, amount: float) -> CombatOutcome:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = amount
	MechanismSlot.bind(attacker, mechanism)
	# A null rng: nothing random, every attack lands clean, no crit. S2/S3 are covered by
	# their own suites; this one is about the gate.
	return CombatSpine.resolve_hit(attacker, target, CombatTestKit.technique(100.0), _tuning, null)


## The shield the gate reads: `absorb(amount, penetration) -> overflow`, which is the
## ADR 0879 shape. Duck-typed in the spine, so a double stands in for `CombatShield`
## with no shared type.
class _FakeShield:
	extends RefCounted

	var capacity: float

	func _init(p_capacity: float) -> void:
		capacity = p_capacity

	func absorb(amount: float, _penetration: float = 0.0) -> float:
		var taken := minf(capacity, amount)
		capacity -= taken
		return amount - taken
