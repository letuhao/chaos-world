extends TestCase

## ADR 0882: the matrix folds into `ActorStats` as a FLAT bucket before any `_put`, so an
## aptitude contribution enters the same `(base + flat) * (1 + percent) * mult` formula as
## every other source — exactly once. These read the SHIPPED table, so the fold and the
## data cannot disagree about what an edge is worth.


func _stats() -> ActorStats:
	return ActorStats.new({Stat.PHYSIQUE: 10.0})


func _edge_for(channel: StringName, source: StringName) -> AptitudeEdge:
	var table := AptitudeTable.shipped()
	assert_ne(table, null, "the shipped table loads")
	if table == null:
		return null
	for edge in table.to_edges():
		if edge.channel == channel and edge.source == source:
			return edge
	assert_eq(false, true, "the shipped table carries %s -> %s" % [String(source), String(channel)])
	return null


func test_an_actor_with_no_aptitudes_has_no_aptitude_footprint() -> void:
	var stats := _stats()
	var before := stats.derived(Stat.CRIT_CHANCE)
	stats.set_aptitudes({})
	assert_almost_eq(stats.derived(Stat.CRIT_CHANCE), before, "an empty store changes nothing")
	assert_almost_eq(stats.derived(&"parry.rate"), 0.0, "and a module channel stays absent")


func test_a_full_share_grants_the_edge_s_own_coefficient() -> void:
	var edge := _edge_for(Stat.CRIT_CHANCE, &"ferocity")
	var stats := _stats()
	stats.set_aptitude(&"ferocity", 1.0)
	assert_almost_eq(
		stats.derived(Stat.CRIT_CHANCE),
		float(edge.k) * 1.0,
		"one aptitude at full share reads its k"
	)


func test_shares_split_the_read_between_a_spread_build_s_aptitudes() -> void:
	var crit := _edge_for(Stat.CRIT_CHANCE, &"ferocity")
	var stats := _stats()
	stats.set_aptitudes({&"ferocity": 1.0, &"precision": 1.0})
	assert_almost_eq(
		stats.derived(Stat.CRIT_CHANCE), float(crit.k) * 0.5, "half the points, half the read"
	)


func test_the_ladder_scales_a_magnitude_edge_and_not_a_contest_one() -> void:
	var magnitude := _edge_for(&"penetration.rate", &"pierce")
	var contest := _edge_for(&"accuracy", &"precision")
	var stats := _stats()
	stats.set_aptitudes({&"pierce": 1.0, &"precision": 1.0})
	stats.set_aptitude_ladder(10.0)
	assert_almost_eq(
		stats.derived(&"penetration.rate"),
		float(magnitude.k) * 0.5 * 10.0,
		"the ladder multiplies the magnitude read"
	)
	assert_almost_eq(
		stats.derived(&"accuracy"),
		0.005 + float(contest.k) * 0.5,
		"and never reaches a contest one, which keeps its own core baseline"
	)


func test_the_flat_modifier_and_the_aptitude_share_enter_the_same_bucket_once() -> void:
	var edge := _edge_for(Stat.CRIT_CHANCE, &"ferocity")
	var stats := _stats()
	stats.set_aptitude(&"ferocity", 1.0)
	stats.add_modifier(StatModifier.new(Stat.CRIT_CHANCE, Stat.Op.FLAT, 1.0, &"test"))
	assert_almost_eq(
		stats.derived(Stat.CRIT_CHANCE),
		float(edge.k) + 1.0,
		"one bucket: the flat applies to the summed base, not to each source"
	)


func test_set_aptitudes_replaces_wholesale_and_the_cache_sees_it() -> void:
	var stats := _stats()
	stats.set_aptitudes({&"ferocity": 1.0})
	var with_crit := stats.derived(Stat.CRIT_CHANCE)
	assert_ne(with_crit, 0.0, "the aptitude contribution was really there")
	stats.set_aptitudes({&"precision": 1.0})
	assert_almost_eq(stats.derived(Stat.CRIT_CHANCE), 0.0, "and the old aptitude is gone")
