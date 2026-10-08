extends TestCase

## ADR 0001/0005: the highest realm scales an actor's core stats via MULT modifiers.
## ADR 0050: the multiplier is the realm's AUTHORED `RealmDef.power`, so every expected
## value here is read from the ladder. A retune of the power table is a balance change
## and must not require editing this suite.


func _power_of(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power


## The OTHER curated curve (ADR 0933): the authored technique ladder the pools ride on
## top of `realm.power`. Read through the table's own call, never a copied number.
func _ladder_of(realm_id: StringName) -> float:
	return TechniqueMagnitudeTable.factor(realm_id)


func test_no_realm_means_no_scaling() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "unscaled")
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "apply with no realm is a no-op")


## The multiplier is the realm's own number, so the derived stat is base x power. This
## assertion used to paste 165.0 - the old linear `1.0 + 0.1 * index` shape, which the
## ladder migration already invalidated once.
func test_scaling_follows_highest_realm() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "R1 is the unscaled baseline")
	actor.path(&"qi").rank_id = &"foundation"
	RealmScaling.apply(actor)
	assert_eq(_power_of(&"foundation") > 1.0, true, "R2 is authored above 1.0")
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		150.0 * _power_of(&"foundation") * _ladder_of(&"foundation"),
		"R2 applies its own authored power AND the technique ladder on the pool (ADR 0933)"
	)


## One realm, one multiplier for the POWER-ONLY stats — and the pools take the ladder on
## top (ADR 0933). Every stat must be non-zero, or the assertion would be satisfied by
## 0 x anything.
func test_the_power_only_stats_take_the_power_and_the_pools_take_the_ladder_too() -> void:
	var seed := {
		Stat.PHYSIQUE: 10.0,
		Stat.SPIRIT: 8.0,
		Stat.APTITUDE: 6.0,
		Stat.WILL: 4.0,
		Stat.AGILITY: 5.0,
	}
	var actor := Actor.new(&"hero", seed)
	actor.set_path(PathState.new(&"qi", &"spirit_sea"))
	var power := _power_of(&"spirit_sea")
	var ladder := _ladder_of(&"spirit_sea")
	RealmScaling.apply(actor)
	for id in RealmScaling.SCALED_STATS:
		var base := Actor.new(&"probe", seed).stats.derived(id)
		assert_eq(base > 0.0, true, "stat %s has a base to scale" % id)
		assert_almost_eq(
			actor.stats.derived(id), base * power, "stat %s takes R11's power" % id, 1e-4
		)
	for id in RealmScaling.POOL_STATS:
		var base := Actor.new(&"probe", seed).stats.derived(id)
		assert_eq(base > 0.0, true, "pool %s has a base to scale" % id)
		assert_almost_eq(
			actor.stats.derived(id),
			base * power * ladder,
			"pool %s takes R11's power AND the technique ladder" % id,
			1e-4
		)


## ADR 0933's claim as a MEASUREMENT rather than a restatement: the pool's extra factor
## IS the technique ladder, read through the same call `CombatSpine.base_damage` gates a
## technique's magnitude with. If the pool curve and the technique gate ever diverge, the
## sixty-second anchor drifts by exactly their difference and this test fails first.
func test_the_pool_ladder_is_the_technique_gate() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	RealmScaling.apply(actor)
	var at_first := actor.stats.derived(Stat.MAX_HEALTH)
	actor.path(&"qi").rank_id = &"primordial_origin"
	RealmScaling.apply(actor)
	var at_last := actor.stats.derived(Stat.MAX_HEALTH)
	var technique := TechniqueDef.new()
	technique.magnitude = 100.0
	assert_almost_eq(
		at_last / at_first / (_power_of(&"primordial_origin") * _ladder_of(&"primordial_origin")),
		1.0,
		"the pool ratio is exactly power x ladder",
		1e-6
	)
	assert_almost_eq(
		CombatSpine.base_damage(actor, technique) / CombatSpine.base_damage(null, technique),
		_ladder_of(&"primordial_origin"),
		"and the technique gate reads the SAME ladder",
		1e-9
	)


## The highest realm across every path wins, whichever path carried it. A cultivator
## deep in one path is not scaled by a different path's rank.
func test_the_highest_realm_across_all_paths_wins() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"foundation"))
	actor.set_path(PathState.new(&"mind", &"earth_immortal"))
	assert_eq(RealmScaling.highest_realm(actor).id, &"earth_immortal", "highest realm resolved")
	RealmScaling.apply(actor)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		150.0 * _power_of(&"earth_immortal") * _ladder_of(&"earth_immortal"),
		"mind's realm wins, on both curves"
	)


## An actor standing on a realm id that is not on the ladder has no realm to scale by.
## This is the no-realm case: no modifiers, not a 1.0 that merely looks like one.
func test_an_off_ladder_realm_scales_nothing() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"not_a_realm"))
	assert_eq(RealmScaling.highest_realm(actor), null, "no realm on the ladder")
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "off-ladder realm scales nothing")


func test_reapply_replaces_modifiers() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"foundation"))
	RealmScaling.apply(actor)
	RealmScaling.apply(actor)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		150.0 * _power_of(&"foundation") * _ladder_of(&"foundation"),
		"not stacked"
	)
