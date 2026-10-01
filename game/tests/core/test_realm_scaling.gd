extends TestCase

## ADR 0001/0005: the highest realm scales an actor's core stats via MULT modifiers.


func test_no_realm_means_no_scaling() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "unscaled")


func test_scaling_follows_highest_realm() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 150.0, "rank 0 = 1.0x")
	actor.path(&"qi").rank_id = &"foundation"
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 165.0, "rank 1 = 1.1x")


func test_reapply_replaces_modifiers() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"foundation"))
	RealmScaling.apply(actor)
	RealmScaling.apply(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 165.0, "not stacked")
