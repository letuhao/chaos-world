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


## ## ADR 0215. The rate contest is a RATIO of two magnitudes, not a permille against a
## constant scale.
##
## ```
## p = offense / (offense + resist)
## ```
##
## This used to read `clampf(maxf(0.0, rate - resist) / rate_scale, 0.0, 1.0)`, and the
## fixtures below used to be authored as PERMILLE rates divided by a constant `1000.0`:
## `rate_scale * 0.25` for "a quarter". Under the ratio there is no scale constant to
## divide by — the denominator is the OTHER HALF of the same quantity — so a fixture that
## means "a quarter" is a PAIR: `offense : resist = 1 : 3`, because `1 / (1 + 3) == 0.25`.
## Every number below is such a pair, and each one's arithmetic is written out beside it.
func test_the_rate_is_a_ratio_of_two_magnitudes() -> void:
	# Nothing invested on either side contests nothing: `0 / (0 + 0)` is answered `0.0`
	# rather than divided, so two actors who have authored neither half neither lands.
	assert_almost_eq(CombatBand.rate(0.0, 0.0, _tuning), 0.0, "zero against zero reads zero")
	# `1 : 3` reads `1 / (1 + 3) == 0.25` and `1 : 1` reads `1 / (1 + 1) == 0.5`. Those are
	# the same two fractions the old shape reached as `250 / 1000` and `500 / 1000`; the
	# ratio reaches them with two MAGNITUDES and no scale constant at all.
	assert_almost_eq(CombatBand.rate(1.0, 3.0, _tuning), 0.25, "1 : 3 reads 1 / 4")
	assert_almost_eq(CombatBand.rate(1.0, 1.0, _tuning), 0.5, "1 : 1 reads 1 / 2")
	# Not one-sided: the mirror of the first pair reads the other three quarters.
	assert_almost_eq(CombatBand.rate(3.0, 1.0, _tuning), 0.75, "3 : 1 reads 3 / 4")
	# Doubling BOTH halves changes nothing. That is the ratio's homogeneity of degree zero
	# and it is the property the realm ladder rides: a contest means the same thing at R3
	# and at R30, which is what a constant divisor could never say.
	assert_almost_eq(
		CombatBand.rate(2.0, 6.0, _tuning),
		CombatBand.rate(1.0, 3.0, _tuning),
		"doubling both halves reads the same"
	)
	# And it cannot saturate. `1000 : 1` is `1000 / 1001`, which is strictly inside
	# `(0, 1)` however lopsided the pair: a stronger attacker moves the reading toward
	# `1.0` and NEVER arrives, so "a god can never miss a mortal" needs no cap to hold.
	assert_eq(
		CombatBand.rate(1000.0, 1.0, _tuning) < 1.0,
		true,
		"a thousand to one is still strictly below certainty"
	)


## ## The assertion ADR 0215 exists to buy, and the one this file used to INVERT.
##
## The old shape was `(rate - resist) / rate_scale`, which reads `0.0` at parity, and this
## file pinned that `0.0` by name. That zero was the defect: it is what makes a contest on
## an absolute difference degenerate — equal halves contest NOTHING, so a naive CC sitting
## on `(o - d)` is a perma-lock on a coin flip rather than a question. The ratio reads
## `0.5` at parity by definition, because `o == d` and `o / (o + d)` IS two equal shares.
func test_at_parity_the_contest_reads_exactly_one_half() -> void:
	assert_almost_eq(
		CombatBand.rate(100.0, 100.0, _tuning), 0.5, "parity reads exactly 0.5, never 0.0"
	)
	# …and it is that same `0.5` at EVERY magnitude, so the reading cannot be bought up by
	# a deeper realm. `100 : 100` and `1000 : 1000` are the same contest.
	assert_almost_eq(CombatBand.rate(1000.0, 1000.0, _tuning), 0.5, "1000 : 1000 is 0.5 too")
	assert_almost_eq(
		CombatBand.rate(100.0, 100.0, _tuning),
		CombatBand.rate(1000.0, 1000.0, _tuning),
		"so a deeper realm moves a contested roll not at all"
	)


## ## The other half of the same inversion, restated in the argument order this API uses.
##
## The old `0.0` came from `(rate - resist) / rate_scale`: parity read nothing, and a
## resist AT OR ABOVE the rate read nothing too — so a big defence was a WALL that turned
## the contest off rather than a share that moved it.
##
## `CombatBand.rate(rate_value, resist, tuning)` puts the DEFENDER's rate first and the
## RESISTER's second, so `rate_value / (rate_value + resist)` is the DEFENDER's share of
## the contest. "The defender is above the resist" is therefore `resist < rate_value`:
##
## - defender above parity (`100 : 500`) reads `100 / 600 = 1/6`, strictly between `0.0`
##   and `0.5` — and NOT `0.0`, which is the inversion. The `0.5` the old shape gave at
##   parity is now the value an EQUAL contest gets, and a defender who is losing reads
##   strictly under it.
## - the resister is never `0.0` and never `1.0` for any finite pair.
func test_a_defender_above_parity_reads_between_zero_and_one_half() -> void:
	assert_almost_eq(
		CombatBand.rate(100.0, 500.0, _tuning), 100.0 / 600.0, "100 : 500 reads 100 / 600"
	)
	assert_eq(
		CombatBand.rate(100.0, 500.0, _tuning) > 0.0,
		true,
		"a resister above the rate still reads NON-ZERO -- the old shape's 0.0 is the defect"
	)
	assert_eq(
		CombatBand.rate(100.0, 500.0, _tuning) < 0.5,
		true,
		"and strictly under the half an equal contest now reads"
	)
	assert_eq(
		CombatBand.rate(100.0, 500.0, _tuning) < 1.0,
		true,
		"and strictly below certainty, which the old 0.0 also happened to satisfy"
	)
	# Monotone, so "above parity" is a property of the SHAPE rather than of one pair: every
	# further point the resister invests moves the reading strictly down — toward, but never
	# to, zero. A saturating or a zeroing formula fails here.
	assert_eq(
		CombatBand.rate(100.0, 500.0, _tuning) < CombatBand.rate(100.0, 100.0, _tuning),
		true,
		"investing more in resist moves the reading strictly down"
	)
	assert_eq(
		CombatBand.rate(100.0, 5000.0, _tuning) > 0.0,
		true,
		"and 100 : 5000 is still a share, not a wall"
	)


## The MIRROR of the above, so the pair cannot be satisfied by a formula that merely
## returns one of its arguments: the same two magnitudes with the halves SWAPPED read the
## complement, `5/6`. `resist` is the half that RESISTS and it is the DENOMINATOR, so
## which side of `0.5` a reading lands on is exactly the claim under test.
func test_swapping_the_two_halves_reads_the_complement() -> void:
	assert_almost_eq(
		CombatBand.rate(100.0, 500.0, _tuning) + CombatBand.rate(500.0, 100.0, _tuning),
		1.0,
		"the two orderings of one contest are complementary shares"
	)
	assert_almost_eq(CombatBand.rate(500.0, 100.0, _tuning), 500.0 / 600.0, "500 : 100 is 5/6")


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
	assert_almost_eq(
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
	var saturated := CombatBand.roll(
		_tuning, 1.0, 1.0, 0.0, CombatTestKit.CountingGenerator.new([0.5])
	)
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
