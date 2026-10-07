extends TestCase

## ADR 0902 (P9/BL-0925): the first candidate SUPPLIER. `FightLoop._strike` offers every
## live status the attacker carries to the other fighter through `spread_status`, and the
## module filters to contagions (a non-contagion has no authored config and no-ops).
## Driven through the helper with its seeded roll, so the pair below is deterministic.


func test_a_plague_the_attacker_carries_reaches_the_defender() -> void:
	var hero := ActorFactory.build(&"plague_hero", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	var foe := ActorFactory.build(&"plague_foe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	assert_eq(
		bool(StatusApi.apply_cultivation(hero, &"plague", 1.0).get("ok", false)),
		true,
		"the hero carries the plague"
	)
	# The window opens at ARRIVAL: wait out the def's own ICD (2 x its tick_interval).
	StatusApi.tick_statuses(hero, 4.0)
	var loop := FightLoop.new(hero, foe)
	loop.call("_spread_contagion", hero, foe)
	assert_eq(foe.has_status(&"plague"), true, "the defender catches what the attacker carries")
	assert_eq(StatusSpread.hop_of(foe.statuses[0]), 1, "as a hop-1 instance")
