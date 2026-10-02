extends TestCase

## ADR 0001/0005: the highest realm scales an actor's core stats via MULT modifiers.
## ADR 0050: the multiplier is the realm's AUTHORED `RealmDef.power`, so every expected
## value here is read from the ladder. A retune of the power table is a balance change
## and must not require editing this suite.


func _power_of(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power


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
		150.0 * _power_of(&"foundation"),
		"R2 applies its own authored power"
	)


## One realm, one multiplier, seven stats - and every one of them non-zero, or the
## assertion would be satisfied by 0 x anything.
func test_every_scaled_stat_takes_the_same_multiplier() -> void:
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
	RealmScaling.apply(actor)
	for id in RealmScaling.SCALED_STATS:
		var base := Actor.new(&"probe", seed).stats.derived(id)
		assert_eq(base > 0.0, true, "stat %s has a base to scale" % id)
		assert_almost_eq(
			actor.stats.derived(id), base * power, "stat %s takes R11's power" % id, 1e-4
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
		150.0 * _power_of(&"earth_immortal"),
		"mind's realm wins"
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
		actor.stats.derived(Stat.MAX_HEALTH), 150.0 * _power_of(&"foundation"), "not stacked"
	)
