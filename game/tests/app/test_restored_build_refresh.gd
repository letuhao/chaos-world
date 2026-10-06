extends TestCase

## ADR 0888: one refresh verb re-derives a restored body's BUILD — realm multiplier,
## element halves and aptitude points — and it is the restore path's own tail
## (`ActorFactory.restore_cultivation`). Before it, a loaded body read the eight
## realm-scaled stats at R1 strength and folded its MAGNITUDE aptitude edges at ladder
## 1.0, because nothing on the load path ever called `RealmScaling.apply`.


func _restored(actor: Actor) -> Actor:
	return ActorFactory.restore_cultivation(Actor.from_dict(actor.to_dict()))


func test_a_restored_build_reads_the_same_stats_as_the_live_one() -> void:
	var live := ActorFactory.with_body_cultivation(
		ActorFactory.build(&"hero", {Stat.PHYSIQUE: 10.0})
	)
	live.set_path(PathState.new(PathState.BODY, RealmDefaults.ladder().realms()[5].id))
	ActorFactory.refresh_build(live)
	var before_health := live.stats.derived(Stat.MAX_HEALTH)
	var before_ladder := live.stats.aptitude_ladder()
	var before_might := live.stats.aptitude(&"might")
	assert_eq(before_might > 0.0, true, "the build really has points to lose")
	var revived := _restored(live)
	assert_almost_eq(
		revived.stats.derived(Stat.MAX_HEALTH), before_health, "the realm multiplier is restored"
	)
	assert_almost_eq(
		revived.stats.aptitude_ladder(), before_ladder, "and the ladder rides the same refresh"
	)
	assert_almost_eq(revived.stats.aptitude(&"might"), before_might, "and the build re-derived")


func test_the_refresh_is_idempotent() -> void:
	var actor := ActorFactory.with_body_cultivation(
		ActorFactory.build(&"hero", {Stat.PHYSIQUE: 10.0})
	)
	actor.set_path(PathState.new(PathState.BODY, RealmDefaults.ladder().realms()[3].id))
	ActorFactory.refresh_build(actor)
	var once := actor.stats.derived(Stat.MAX_HEALTH)
	var points := actor.stats.aptitude_points()
	ActorFactory.refresh_build(actor)
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), once, "a second refresh changes nothing")
	assert_eq(actor.stats.aptitude_points(), points, "and the store is the same build")
