extends TestCase

## ADR 0887: a shield is granted by the BUILD — a resolved `shield.capacity` above zero
## binds a real `CombatShield` where the build is first consumed — and its regen rides the
## composition root's frame clock. An unbuilt body never gains a component.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _pooled(capacity: float, toughness: float = 1.0, regen: float = 0.0) -> Actor:
	var actor := CombatTestKit.actor(&"shielded")
	actor.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.SHIELD_CAPACITY, capacity, &"test")
	)
	if toughness != 1.0:
		actor.stats.add_modifier(
			CombatStats.rate_modifier(CombatStats.SHIELD_TOUGHNESS, toughness - 1.0, &"test")
		)
	if regen != 0.0:
		actor.stats.add_modifier(
			CombatStats.rate_modifier(CombatStats.SHIELD_REGEN, regen, &"test")
		)
	return actor


func test_ensure_binds_exactly_when_the_build_grants_capacity() -> void:
	var bare := CombatTestKit.actor(&"bare")
	assert_eq(CombatShield.ensure(bare), null, "no capacity, no shield")
	assert_eq(bare.component(CombatSpine.SHIELD_COMPONENT), null, "and no component either")
	var built := _pooled(30.0)
	var shield := CombatShield.ensure(built)
	assert_ne(shield, null, "a build with capacity binds a pool")
	assert_almost_eq(
		built.stats.derived(CombatStats.SHIELD_CAPACITY), 30.0, "read from the resolved stat"
	)
	assert_almost_eq((shield as CombatShield).current, 30.0, "bound full")


func test_ensure_is_idempotent_and_respects_a_bound_double() -> void:
	var built := _pooled(30.0)
	var first := CombatShield.ensure(built)
	assert_eq(CombatShield.ensure(built), first, "a second ensure returns the same pool")
	var doubled := _pooled(30.0)
	var double := _Double.new(12.0)
	doubled.set_component(CombatSpine.SHIELD_COMPONENT, double)
	assert_eq(CombatShield.ensure(doubled), double, "a bound double is respected as bound")


func test_the_spine_binds_and_drains_the_build_s_pool() -> void:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 50.0
	MechanismSlot.bind(attacker, mechanism)
	var target := _pooled(30.0)
	var outcome := CombatSpine.resolve_hit(
		attacker, target, CombatTestKit.technique(100.0), _tuning, null
	)
	assert_ne(CombatShield.ensure(target), null, "the spine bound the pool on first use")
	assert_almost_eq(outcome.absorbed, 30.0, "and the pool took its capacity")
	assert_almost_eq(outcome.overflow, 20.0, "with the rest reaching health")


func test_the_frame_clock_refills_the_pool_through_the_facade() -> void:
	var built := _pooled(100.0, 1.0, 5.0)
	var shield := CombatShield.ensure(built) as CombatShield
	assert_ne(shield, null, "the pool bound")
	shield.absorb(40.0)
	assert_almost_eq(shield.current, 60.0, "drained")
	CombatEngineApi.tick_shields(built, 4.0)
	assert_almost_eq(shield.current, 80.0, "5 per second over 4 seconds")
	CombatEngineApi.tick_shields(built, 1000.0)
	assert_almost_eq(shield.current, 100.0, "capped at the authored ceiling")


func test_an_unbuilt_body_ticks_nothing_and_stays_unbuilt() -> void:
	var bare := CombatTestKit.actor(&"bare")
	CombatEngineApi.tick_shields(bare, 10.0)
	assert_eq(bare.component(CombatSpine.SHIELD_COMPONENT), null, "still no shield")


## A stand-in for a test's own shield: `ensure` must never replace a component another
## caller bound, whatever class it is.
class _Double:
	extends RefCounted

	var capacity: float

	func _init(p_capacity: float) -> void:
		capacity = p_capacity

	func absorb(amount: float, _penetration: float = 0.0) -> float:
		var taken := minf(capacity, amount)
		capacity -= taken
		return amount - taken
