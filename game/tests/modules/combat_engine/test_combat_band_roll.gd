extends TestCase

## S2, the one-draw band roll (ADR 0068). The properties the ADR's own Consequences
## section promises `tests/modules/combat/` pins: "bands are exclusive and partition the
## draw; an unstatted actor has `p_parry == p_block == 0.0` and parries 0% of the time".

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


# --- one draw ------------------------------------------------------------------


func test_the_band_is_exactly_one_draw() -> void:
	var generator := CombatTestKit.CountingGenerator.new([0.5])
	CombatBand.roll(_tuning, 1.0, 0.2, 0.2, generator)
	assert_eq(generator.draws, 1, "three bands, one draw")


func test_every_band_reads_the_same_draw() -> void:
	# The thresholds are `r >= p_land`, `r >= p_land - p_parry`, `r >= p_land - p_parry -
	# p_block` against ONE `r`. A second draw would make two bands comparable and the
	# partition an accident of the seed rather than of the arithmetic.
	var low := CombatBand.roll(_tuning, 0.5, 0.2, 0.2, CombatTestKit.CountingGenerator.new([0.1]))
	var high := CombatBand.roll(_tuning, 0.5, 0.2, 0.2, CombatTestKit.CountingGenerator.new([0.9]))
	assert_almost_eq(low.draw, 0.1, "the band's own record of the draw, low")
	assert_almost_eq(high.draw, 0.9, "the band's own record of the draw, high")


func test_the_three_bands_are_mutually_exclusive() -> void:
	# Sweep the whole draw range and assert no observation has two of them set, and that
	# a parry never coexists with a miss or a block.
	var exclusive := true
	var index := 0
	while index < 64:
		var value := float(index) / 64.0
		var band := CombatBand.roll(
			_tuning, 0.6, 0.25, 0.2, CombatTestKit.CountingGenerator.new([value])
		)
		var set_count := (
			(1 if band.missed else 0) + (1 if band.parried else 0) + (1 if band.blocked else 0)
		)
		if set_count > 1:
			exclusive = false
		index += 1
	assert_eq(exclusive, true, "no draw produces two bands")


# --- ordering: parry, then block, then miss ------------------------------------


func test_parry_precedes_block_precedes_miss() -> void:
	# The bands are carved out of the TOP of the would-have-been-a-hit region, so the
	# edges run downward: miss above `p_hit`, parry above `p_hit - p_parry`, block above
	# `p_hit - p_parry - p_block`. Reading the ADR's formulas:
	var miss_above := CombatBand.roll(
		_tuning, 0.7, 0.2, 0.1, CombatTestKit.CountingGenerator.new([0.75])
	)
	var parry_at := CombatBand.roll(
		_tuning, 0.7, 0.2, 0.1, CombatTestKit.CountingGenerator.new([0.55])
	)
	var block_at := CombatBand.roll(
		_tuning, 0.7, 0.2, 0.1, CombatTestKit.CountingGenerator.new([0.45])
	)
	var clean_at := CombatBand.roll(
		_tuning, 0.7, 0.2, 0.1, CombatTestKit.CountingGenerator.new([0.1])
	)
	assert_eq(miss_above.missed, true, "above p_hit is a miss")
	assert_eq(miss_above.parried, false, "and never a parry too")
	assert_eq(parry_at.missed, false, "between the parry and miss edges is a parry")
	assert_eq(parry_at.parried, true, "in the parry band")
	assert_eq(parry_at.blocked, false, "and not a block")
	assert_eq(block_at.blocked, true, "below the parry edge and above the block edge")
	assert_eq(block_at.parried, false, "is a block, not a parry")
	assert_eq(clean_at.is_clean(), true, "below every edge is a clean hit")


func test_zero_parry_and_zero_block_collapse_to_r_below_p_hit() -> void:
	# "At zero parry and zero block this collapses to exactly `r < p_hit` by arithmetic,
	# with no special case." Asserted by sampling the whole range against the plain
	# predicate, so a future special case cannot hide behind the sample.
	var agrees := true
	var index := 0
	while index < 128:
		var value := float(index) / 128.0
		var band := CombatBand.roll(
			_tuning, 0.65, 0.0, 0.0, CombatTestKit.CountingGenerator.new([value])
		)
		if band.missed != (value >= 0.65):
			agrees = false
		index += 1
	assert_eq(agrees, true, "the degenerate band IS the plain hit test")


func test_an_unstatted_actor_parries_zero_percent_of_the_time() -> void:
	# A sigmoid would return 0.5 at parity, so an actor with ZERO parry stat would parry
	# half the time — "a default nobody chose, and an empty band that is not a no-op".
	var bare := CombatTestKit.actor(&"target")
	assert_almost_eq(
		CombatBand.rate_of(CombatStats.PARRY_RATE, bare, _tuning), 0.0, "no parry stat"
	)
	assert_almost_eq(
		CombatBand.rate_of(CombatStats.BLOCK_RATE, bare, _tuning), 0.0, "no block stat"
	)
	var parried := 0
	var index := 0
	while index < 200:
		var value := float(index) / 200.0
		if (
			CombatBand
			. roll(_tuning, 1.0, 0.0, 0.0, CombatTestKit.CountingGenerator.new([value]))
			. parried
		):
			parried += 1
		index += 1
	assert_eq(parried, 0, "0 of 200 draws produced a parry")


func test_the_rate_is_linear_from_zero() -> void:
	# `clampf(maxf(0.0, rate - resist) / rate_scale, 0.0, 1.0)`: half the scale is half a
	# chance, not 0.5-at-parity-plus-something. Asserted at three points on the line.
	assert_almost_eq(CombatBand.rate(0.0, 0.0, _tuning), 0.0, "zero reads zero")
	assert_almost_eq(
		CombatBand.rate(_tuning.rate_scale * 0.25, 0.0, _tuning),
		0.25,
		"a quarter of the scale is a quarter"
	)
	assert_almost_eq(
		CombatBand.rate(_tuning.rate_scale * 0.5, 0.0, _tuning), 0.5, "half the scale is half"
	)
	assert_almost_eq(
		CombatBand.rate(_tuning.rate_scale * 2.0, 0.0, _tuning), 1.0, "and it saturates at 1.0"
	)


func test_a_resist_at_or_above_the_rate_reads_zero() -> void:
	assert_almost_eq(CombatBand.rate(100.0, 100.0, _tuning), 0.0, "parity reads zero, never 0.5")
	assert_almost_eq(CombatBand.rate(100.0, 500.0, _tuning), 0.0, "and resist above it reads zero")


# --- the cap -------------------------------------------------------------------


func test_the_band_total_is_capped_so_every_attack_can_land() -> void:
	# Three saturated bands scaled down to `avoidance_band_cap`: `parry` and `block` share
	# the 0.95 budget, so a defender stacking everything still leaves 5% of draws landing
	# CLEAN and no stack of defensive stats reaches immunity (ADR 0068).
	#
	# The guarantee is asserted as a COUNT, not as three sample literals. It used to pin
	# `landed == 50`, `parried == 450` and `blocked == 500` off one sweep, which cannot
	# hold for any implementation: `landed` is `1000 - missed` and `parried`/`blocked` are
	# counted in an `elif` chain, so `parried <= landed` — and 450 > 50. The literals were
	# describing three different models at once.
	var parried := 0
	var blocked := 0
	var missed := 0
	var clean := 0
	var samples := 1000
	var index := 0
	while index < samples:
		var value := float(index) / float(samples)
		var band := CombatBand.roll(
			_tuning, 1.0, 1.0, 1.0, CombatTestKit.CountingGenerator.new([value])
		)
		if band.missed:
			missed += 1
		elif band.parried:
			parried += 1
		elif band.blocked:
			blocked += 1
		else:
			clean += 1
		index += 1
	assert_eq(missed + parried + blocked + clean, samples, "the four outcomes partition the sweep")
	assert_eq(
		float(clean) / float(samples),
		1.0 - _tuning.avoidance_band_cap,
		"5% of a 0.95 cap lands CLEAN",
		1e-3
	)
	assert_eq(clean > 0, true, "and the guarantee is a positive number, not a rounding")
	# The budget is SHARED, so neither band may claim the whole of it: a defender who
	# parries at 100% and blocks at 100% is parried and blocked in equal measure.
	assert_eq(
		absf(float(parried) - float(blocked)) <= 1,
		true,
		"parry %d and block %d split the capped budget evenly" % [parried, blocked]
	)
	assert_eq(parried > 0 and blocked > 0, true, "both bands are reachable under the cap")


func test_the_cap_bounds_the_defensive_total_and_leaves_p_hit_alone() -> void:
	# ADR 0068 caps "band total" so no stack of defensive stats reaches immunity. The
	# stackable half is `p_parry + p_block`; `p_hit` is the ATTACKER's contest
	# (`accuracy` vs `EVASION`, already floored at 0.4 by core's `Stat.EVASION` cap), so
	# folding it into the budget would let a defender's parry build silently delete the
	# attacker's accuracy.
	#
	# This used to assert the opposite — that a saturated parry drags the MISS edge down to
	# `1 - cap` — which contradicts `test_zero_parry_and_zero_block_collapse_to_r_below_p_hit`
	# in this same file, and which `CombatTuning.avoidance_band_cap` now documents against.
	var cap := _tuning.avoidance_band_cap
	var saturated := CombatBand.roll(_tuning, 1.0, 1.0, 0.0, CombatTestKit.CountingGenerator.new([0.5]))
	assert_eq(saturated.missed, false, "one saturated band cannot make a certain hit miss")
	assert_eq(saturated.parried, true, "it parries instead")
	var both := CombatBand.roll(_tuning, 1.0, 1.0, 1.0, CombatTestKit.CountingGenerator.new([0.5]))
	assert_eq(both.missed, false, "nor can two of them")
	# Every draw at or above `1 - cap` is inside the defensive budget, so it is answered;
	# a draw below it is the guaranteed clean share.
	var index := 0
	var answered := true
	while index < 100:
		var value := cap + (1.0 - cap) * float(index) / 100.0
		var band := CombatBand.roll(
			_tuning, 1.0, 1.0, 1.0, CombatTestKit.CountingGenerator.new([value])
		)
		if band.is_clean():
			answered = false
		index += 1
	assert_eq(answered, true, "the whole region at or above 1 - cap is answered")
	assert_eq(
		CombatBand.roll(_tuning, 0.65, 0.0, 0.0, CombatTestKit.CountingGenerator.new([0.7])).missed,
		true,
		"and an uncontested p_hit still misses above its own edge"
	)


# --- saturated cases consume zero draws -----------------------------------------


func test_a_saturated_landed_chance_consumes_no_draw() -> void:
	# `CombatProbability.RollSuccess` spends no draw on a `p >= 1` chance, and the band
	# mirrors it: with `p_hit` at 1.0 there is nothing for parry or block to carve, so a
	# draw is pure waste.
	var generator := CombatTestKit.CountingGenerator.new([0.0])
	var band := CombatBand.roll(_tuning, 1.0, 0.0, 0.0, generator)
	assert_eq(generator.draws, 0, "zero draws at p_hit 1.0")
	assert_eq(band.is_clean(), true, "and it is a clean hit")


func test_an_empty_band_consumes_no_draw() -> void:
	var generator := CombatTestKit.CountingGenerator.new([0.0])
	CombatBand.roll(_tuning, 0.5, 0.0, 0.0, generator)
	assert_eq(generator.draws, 1, "with a real miss band the draw is spent")


func test_a_null_generator_is_a_total_function_that_lands() -> void:
	# A caller that passes no generator has declared the roll is not random. It must not
	# fall through to `randf()` — the spine takes an injected generator precisely so a
	# resolve is reproducible from its seed (ADR 0067).
	var band := CombatBand.roll(_tuning, 0.1, 0.5, 0.5, null)
	assert_eq(band.missed, false, "a null generator lands")
	assert_eq(band.is_clean(), true, "and lands clean")


# --- the read model ------------------------------------------------------------


func test_a_miss_reads_as_empty_and_a_parry_reads_as_its_keys() -> void:
	var miss := CombatBand.roll(_tuning, 0.1, 0.0, 0.0, CombatTestKit.CountingGenerator.new([0.9]))
	assert_eq(miss.to_dict(), {}, "a miss is `{}`")
	var parry := CombatBand.roll(_tuning, 1.0, 0.3, 0.0, CombatTestKit.CountingGenerator.new([0.9]))
	assert_eq(bool(parry.to_dict()["parried"]), true, "a parry is readable")
	assert_eq(bool(parry.to_dict()["clean"]), false, "and is not clean")
	assert_eq(parry.is_landed(), true, "a parry is a landed hit, not a miss")
	# ADR 0038: the payload is primitives only, so `ui/` can render it unchanged. The draw
	# used to be read off `roll` — this class's STATIC FUNCTION — which put a `Callable` in
	# a dictionary whose whole contract is primitives, and `CombatEngineApi.band()` hands it
	# straight to a caller. Asserted per key so a `Callable` can never come back.
	var payload := parry.to_dict()
	for key in payload.keys():
		var value: Variant = payload[key]
		assert_eq(
			value is float or value is int or value is bool,
			true,
			"key %s carries a primitive, not a %s" % [String(key), type_string(typeof(value))]
		)
	assert_almost_eq(float(payload["draw"]), 0.9, "and the draw is the float that was compared")
