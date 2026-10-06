extends TestCase

## ADR 0879, the shield's other half: `CombatShield` is the shipped binding of the four
## `CombatStats.SHIELD_*` ids — a capacity pool the spine drains, cut by the attacker's
## `SHIELD_PEN` before the blow, scaled by `SHIELD_TOUGHNESS`, refilled by `SHIELD_REGEN`
## through `tick` and never inside a resolve.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- the pool math -----------------------------------------------------------------


func test_a_pool_takes_what_it_can_and_returns_the_rest() -> void:
	var spent := _bound(30.0)
	assert_almost_eq(spent.absorb(50.0), 20.0, "a 30-pool returns 20 of a 50 blow")
	assert_almost_eq(spent.current, 0.0, "and is spent")
	var whole := _bound(80.0)
	assert_almost_eq(whole.absorb(50.0), 0.0, "an 80-pool takes a 50 blow whole")
	assert_almost_eq(whole.current, 30.0, "and keeps the remainder")


func test_penetration_is_spent_off_the_pool_before_the_blow() -> void:
	var shield := _bound(30.0)
	assert_almost_eq(shield.absorb(50.0, 10.0), 30.0, "a 10 cut leaves only 20 of the pool")
	assert_almost_eq(shield.current, 0.0, "and the cut is spent, not banked")


func test_toughness_scales_the_damage_the_pool_is_good_for() -> void:
	var plain := _bound(30.0)
	assert_almost_eq(plain.absorb(50.0), 20.0, "neutral toughness: a 30-pool returns 20")
	assert_almost_eq(plain.current, 0.0, "and is spent")
	var tough := _bound(30.0, 2.0)
	assert_almost_eq(tough.absorb(50.0), 0.0, "double toughness absorbs the whole blow")
	assert_almost_eq(tough.current, 0.0, "from the same 30-point pool")


# --- regen, which the spine never reads --------------------------------------------


func test_regen_refills_on_tick_and_caps_at_the_ceiling() -> void:
	var shield := _bound(100.0, 1.0, 5.0)
	shield.absorb(40.0)
	assert_almost_eq(shield.current, 60.0, "spent")
	shield.tick(4.0)
	assert_almost_eq(shield.current, 80.0, "5 per second over 4 seconds")
	shield.tick(100.0)
	assert_almost_eq(shield.current, 100.0, "capped at the authored ceiling")
	shield.tick(-1.0)
	assert_almost_eq(shield.current, 100.0, "and a non-positive delta is a no-op")


# --- binding and refresh -----------------------------------------------------------


func test_refresh_pulls_the_owners_numbers_without_refilling() -> void:
	var owner := CombatTestKit.actor(&"shielded")
	owner.stats.add_modifier(CombatStats.rate_modifier(CombatStats.SHIELD_CAPACITY, 30.0, &"test"))
	owner.stats.add_modifier(CombatStats.rate_modifier(CombatStats.SHIELD_TOUGHNESS, 0.25, &"test"))
	owner.stats.add_modifier(CombatStats.rate_modifier(CombatStats.SHIELD_REGEN, 2.0, &"test"))
	var shield := CombatShield.attach(owner)
	assert_almost_eq(shield.capacity_max, 30.0, "capacity pulled")
	assert_almost_eq(shield.toughness, 1.25, "toughness pulled onto its 1.0 neutral")
	assert_almost_eq(shield.regen, 2.0, "regen pulled")
	assert_almost_eq(shield.current, 30.0, "attach binds full")
	shield.absorb(10.0)
	shield.refresh(owner)
	assert_almost_eq(shield.current, 20.0, "and refresh never refills")


func test_the_summary_is_primitives_only() -> void:
	var shield := _bound(30.0)
	var view := shield.summary()
	for key in view.keys():
		var value: Variant = view[key]
		assert_eq(
			value is float or value is int or value is bool,
			true,
			"key %s carries a primitive" % String(key)
		)


# --- through the spine --------------------------------------------------------------


func test_the_spine_drains_the_bound_shield() -> void:
	var outcome := _harm(30.0, 0.0)
	assert_almost_eq(outcome.absorbed, 30.0, "the bound shield took its capacity")
	assert_almost_eq(outcome.overflow, 20.0, "and the rest reached health")


func test_the_attackers_pen_shreds_the_pool_through_the_spine() -> void:
	var outcome := _harm(30.0, 10.0)
	assert_almost_eq(outcome.absorbed, 20.0, "the cut is spent before the blow")
	assert_almost_eq(outcome.overflow, 30.0, "so more reaches health")


# --- internals ---------------------------------------------------------------------


## A standalone shield bound full, with its stats authored as FLAT modifiers on an actor
## (the only form a `0.0`-baseline id can take, ADR 0022). `toughness` is authored as its
## delta ABOVE the neutral, because a stat channel floors at zero: a shield can be made
## tougher than neutral, never softer.
func _bound(capacity: float, toughness: float = 1.0, regen: float = 0.0) -> CombatShield:
	return _bind(CombatTestKit.actor(&"shielded"), capacity, toughness, regen)


func _bind(
	owner: Actor, capacity: float, toughness: float = 1.0, regen: float = 0.0
) -> CombatShield:
	owner.stats.add_modifier(
		CombatStats.rate_modifier(CombatStats.SHIELD_CAPACITY, capacity, &"test")
	)
	if toughness != 1.0:
		owner.stats.add_modifier(
			CombatStats.rate_modifier(CombatStats.SHIELD_TOUGHNESS, toughness - 1.0, &"test")
		)
	if regen != 0.0:
		owner.stats.add_modifier(
			CombatStats.rate_modifier(CombatStats.SHIELD_REGEN, regen, &"test")
		)
	var shield := CombatShield.attach(owner)
	owner.set_component(CombatSpine.SHIELD_COMPONENT, shield)
	return shield


## One clean 50 blow through the spine against a target whose shield holds `capacity`,
## from an attacker carrying `pen`.
func _harm(capacity: float, pen: float) -> CombatOutcome:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	if pen != 0.0:
		attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.SHIELD_PEN, pen, &"test"))
	var target := CombatTestKit.actor(&"target")
	_bind(target, capacity)
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 50.0
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(attacker, target, CombatTestKit.technique(100.0), _tuning, null)
