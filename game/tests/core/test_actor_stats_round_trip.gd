extends TestCase

## ADR 0888: the aptitude layer SERIALIZES as a cache and re-derives on restore. The
## cache is what a save carries; `AptitudeGrant.apply` is what wins when a refresh runs.
## These pin the cache half; `tests/app/test_restored_build_refresh.gd` pins the refresh.


func test_stats_carry_aptitudes_and_the_ladder_through_a_round_trip() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	stats.set_aptitudes({&"might": 4.0, &"focus": 2.0})
	stats.set_aptitude_ladder(33.5)
	var revived := ActorStats.new({Stat.PHYSIQUE: 10.0})
	revived.from_dict(stats.to_dict())
	assert_almost_eq(revived.aptitude(&"might"), 4.0, "points restored")
	assert_almost_eq(revived.aptitude(&"focus"), 2.0, "both points restored")
	assert_almost_eq(revived.aptitude_ladder(), 33.5, "and the ladder")


func test_a_missing_or_malformed_payload_is_the_default() -> void:
	var stats := ActorStats.new({})
	stats.from_dict({})
	assert_almost_eq(stats.aptitude_ladder(), 1.0, "no payload, neutral ladder")
	stats.from_dict({"aptitudes": 7, "aptitude_ladder": -3.0})
	assert_eq(stats.aptitude_points().is_empty(), true, "a non-dict points field restores nothing")
	assert_almost_eq(stats.aptitude_ladder(), 1.0, "and a non-positive ladder is neutral")


func test_the_actor_payload_carries_the_stats_cache() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.stats.set_aptitudes({&"might": 3.0})
	actor.stats.set_aptitude_ladder(12.0)
	var restored := Actor.from_dict(actor.to_dict())
	assert_almost_eq(restored.stats.aptitude(&"might"), 3.0, "the actor round trip carries it")
	assert_almost_eq(restored.stats.aptitude_ladder(), 12.0, "and the ladder")
