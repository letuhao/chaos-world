extends TestCase

## The matrix arithmetic (ADR 0881), ported from Keepverse's `AptitudeReadFunctions`:
## `value = k * share^gamma * span`, shares normalised over the actor's own counted
## points, one channel fed by many edges and summing. These tests build edges in
## memory — the shipped table is data and lands with its own table test.


func _edge(
	channel: StringName, source: StringName, k: float, mode: int = AptitudeEdge.Mode.MAGNITUDE
) -> AptitudeEdge:
	var edge := AptitudeEdge.new()
	edge.channel = channel
	edge.source = source
	edge.k = k
	edge.mode = mode
	return edge


func test_shares_normalise_over_the_actor_s_own_points() -> void:
	var share := AptitudeMatrix.shares({&"might": 3.0, &"agility": 1.0})
	assert_almost_eq(float(share[&"might"]), 0.75, "three of four")
	assert_almost_eq(float(share[&"agility"]), 0.25, "one of four")
	assert_eq(AptitudeMatrix.shares({}).is_empty(), true, "no points, no shares")
	assert_eq(
		AptitudeMatrix.shares({&"might": 0.0}).is_empty(), true, "zero points are not a share"
	)


func test_a_non_aptitude_key_neither_grants_nor_dilutes() -> void:
	var share := AptitudeMatrix.shares({&"might": 1.0, &"garbage": 9.0})
	assert_almost_eq(float(share[&"might"]), 1.0, "the stray key is not a denominator")
	assert_eq(share.has(&"garbage"), false, "and it never becomes a share")


func test_a_magnitude_edge_reads_the_ladder_and_a_contest_edge_does_not() -> void:
	var magnitude := _edge(&"shield.capacity", &"vigor", 2.0, AptitudeEdge.Mode.MAGNITUDE)
	var contest := _edge(&"evasion", &"agility", 3.0, AptitudeEdge.Mode.CONTEST)
	var edges: Array[AptitudeEdge] = [magnitude, contest]

	var solo := AptitudeMatrix.resolve(edges, {&"vigor": 1.0}, 1.0, 4.0, 10.0)
	assert_almost_eq(float(solo[&"shield.capacity"]), 2.0 * 1.0 * 10.0, "k * share * ladder")
	assert_eq(solo.has(&"evasion"), false, "a source with no points contributes nothing")

	var both := AptitudeMatrix.resolve(edges, {&"vigor": 1.0, &"agility": 1.0}, 1.0, 4.0, 10.0)
	assert_almost_eq(
		float(both[&"shield.capacity"]), 2.0 * 0.5 * 10.0, "half the points, half the read"
	)
	assert_almost_eq(
		float(both[&"evasion"]), 3.0 * 0.5 * 4.0, "the contest reads its own span, never the ladder"
	)


func test_the_share_exponent_curves_the_read() -> void:
	var edge := _edge(&"crit_chance", &"ferocity", 1.0)
	var edges: Array[AptitudeEdge] = [edge]
	var points := {&"ferocity": 3.0, &"might": 1.0}
	var linear := AptitudeMatrix.resolve(edges, points, 1.0, 1.0, 1.0)
	var squared := AptitudeMatrix.resolve(edges, points, 2.0, 1.0, 1.0)
	assert_almost_eq(float(linear[&"crit_chance"]), 0.75, "gamma 1 is linear")
	assert_almost_eq(float(squared[&"crit_chance"]), 0.75 * 0.75, "gamma 2 squares the share")


func test_edges_sum_onto_one_channel() -> void:
	var first := _edge(&"penetration", &"pierce", 1.0)
	var second := _edge(&"penetration", &"might", 2.0)
	var edges: Array[AptitudeEdge] = [first, second]
	var out := AptitudeMatrix.resolve(edges, {&"pierce": 1.0, &"might": 1.0}, 1.0, 1.0, 1.0)
	assert_almost_eq(float(out[&"penetration"]), 0.5 + 1.0, "two edges, one channel, summed")


func test_an_empty_or_zeroed_allocation_resolves_to_nothing_at_all() -> void:
	var edges: Array[AptitudeEdge] = [_edge(&"evasion", &"agility", 5.0)]
	assert_eq(
		AptitudeMatrix.resolve(edges, {}, 1.0, 1.0, 1.0).is_empty(), true, "no points, no channels"
	)
	assert_eq(
		AptitudeMatrix.resolve(edges, {&"agility": -3.0}, 1.0, 1.0, 1.0).is_empty(),
		true,
		"a negative grant is not counted"
	)


func test_an_unknown_source_contributes_nothing_and_validate_says_so() -> void:
	var typo := _edge(&"evasion", &"agilty", 1.0)
	var typo_edges: Array[AptitudeEdge] = [typo]
	assert_eq(
		AptitudeMatrix.resolve(typo_edges, {&"agilty": 1.0}, 1.0, 1.0, 1.0).is_empty(),
		true,
		"the share of a non-aptitude never resolves"
	)
	var bad: Array[AptitudeEdge] = [
		typo,
		_edge(&"evasion", &"agility", -1.0),
		_edge(&"", &"agility", 1.0),
	]
	var problems := AptitudeMatrix.validate(bad)
	assert_eq(problems.size(), 3, "unknown source, negative k and an empty channel are each named")
	assert_eq(AptitudeMatrix.validate(bad).is_empty(), false, "and a sound table reports nothing")
	var sound: Array[AptitudeEdge] = [_edge(&"evasion", &"agility", 1.0)]
	assert_eq(AptitudeMatrix.validate(sound).is_empty(), true, "one real edge validates clean")
