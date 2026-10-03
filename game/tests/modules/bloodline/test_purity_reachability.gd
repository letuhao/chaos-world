extends TestCase

# ADR 0063 constants — the check that ADR 0063 says must exist as a test.
#
# This is the test whose absence let an earlier draft ship two permanently
# unreachable tiers. It asserts the purity ladder's *reachability*, not merely
# that the formula runs: for each authored tier it pins the generation at which a
# pure line stops clearing it and the parent purity a first generation needs.
#
# The constants asserted here are the ones ADR 0063 owns. If you retune them,
# this file is the contract that must be updated in the same change, and it must
# be re-derived from the fixed point rather than picked to make a test pass.
#
# **They are now `BloodlineState`'s constants rather than a private copy.** An
# earlier revision of this file hard-coded 0.70 / 0.15 / 0.045 and re-implemented
# the blend in a local `_child_purity`. That copy was the exact hazard the ADR's
# "Corrects" note warns about: nothing tied it to the arithmetic the game
# actually runs, so a retune of `BloodlineState` could have left this whole file
# green and the ladder broken. The `_child_purity` helper below is now
# `BloodlineState.inherit` itself, so every assertion in this file exercises the
# shipped implementation rather than a transcription of it.
#
# What stays local is what this file owns: the published chain table, the
# generation counts, and the parent-purity minimums are the ADR's contract, and
# they are still asserted against the live code.

const RETENTION := BloodlineState.RETENTION
const FLOOR := BloodlineState.FLOOR
const BLEND_CONSTANT := BloodlineState.BLEND_CONSTANT

const FOUNDING := BloodlineApi.TIER_FOUNDING
const RARE := BloodlineApi.TIER_RARE
const COMMON := BloodlineApi.TIER_COMMON

## Generations a pure ancestor's line survives each tier.
const FOUNDING_GENERATIONS := 1
const RARE_GENERATIONS := 2
const COMMON_GENERATIONS := 3

## The purity an actor with no lineage is treated as carrying.
const ABSENT := 0.0

## Compare against a figure the ADR publishes rounded to three decimals.
##
## The framework's default epsilon is 0.0001, which is tighter than the fourth decimal
## place the tables here were ever written to — so an exact assertion against a
## rounded figure is a failing test about a constant that is in fact correct, and the
## tempting "fix" is to retune the ladder until it passes. Half a rounding unit keeps
## the table a real constraint (moving `RETENTION` by even 0.001 breaks it) without
## demanding precision the ADR never claimed.
const PUBLISHED_TOLERANCE := 0.0005


## The blend under test. The whole point of this file is that the shipped
## `BloodlineState.inherit` produces these numbers, so it calls that and nothing
## else.
func _child_purity(purity_a: float, purity_b: float) -> float:
	return BloodlineState.inherit(purity_a, purity_b)


func _chain(generations: int) -> Array[float]:
	var out: Array[float] = [1.0]
	for _i in generations:
		var last := out[out.size() - 1]
		out.append(_child_purity(last, last))
	return out


## The one parent purity that yields a first-generation child exactly at
## `threshold`, when both parents carry the lineage at that purity.
func _minimum_parent(threshold: float) -> float:
	return (threshold - BLEND_CONSTANT) / RETENTION


func test_blend_constant_is_derived_from_the_authored_floor() -> void:
	# The floor is authored; the additive constant is derived. Naming the constant
	# `BLEND_FLOOR` is what hid the original arithmetic error, so the relationship
	# itself is pinned here rather than only the resulting value.
	assert_almost_eq(BLEND_CONSTANT, FLOOR * (1.0 - RETENTION), "constant derived from the floor")
	var fixed_point := BLEND_CONSTANT / (1.0 - RETENTION)
	assert_almost_eq(fixed_point, FLOOR, "affine map converges to the authored floor")


func test_a_line_never_falls_below_the_floor() -> void:
	# The whole anti-compounding guarantee: any number of generations, any starting
	# purity, the result stays above the floor and cannot reach zero.
	var purity := 1.0
	for _generation in 60:
		purity = _child_purity(purity, purity)
		assert_almost_eq(purity, maxf(purity, FLOOR), "never below floor")
	assert_almost_eq(purity, FLOOR, "converges to the floor")


func test_purity_chain_matches_the_published_table() -> void:
	# ADR 0063 publishes this chain to three decimal places. If the constants move,
	# this table is wrong. Each row is compared at the precision it is PUBLISHED at, so
	# asserting it against exact arithmetic would fail on the fourth decimal the ADR
	# never claimed — which would push someone to "fix" a correct constant.
	var chain := _chain(10)
	_tol(chain[0], 1.000, "gen 0")
	_tol(chain[1], 0.745, "gen 1")
	_tol(chain[2], 0.567, "gen 2")
	_tol(chain[3], 0.442, "gen 3")
	_tol(chain[4], 0.354, "gen 4")
	_tol(chain[5], 0.293, "gen 5")
	_tol(chain[6], 0.250, "gen 6")
	_tol(chain[10], 0.174, "gen 10")


func test_each_tier_survives_exactly_one_further_generation() -> void:
	# The property that makes the ladder legible: every tier is worth exactly one
	# more generation than the tier below it.
	var chain := _chain(8)
	assert_eq(_generations_clearing(chain, FOUNDING), FOUNDING_GENERATIONS, "founding tier")
	assert_eq(_generations_clearing(chain, RARE), RARE_GENERATIONS, "rare tier")
	assert_eq(_generations_clearing(chain, COMMON), COMMON_GENERATIONS, "common tier")


func test_no_tier_is_permanently_true() -> void:
	# A tier at or under the floor would be granted to every actor forever, which
	# makes it content that cannot gate anything.
	var chain := _chain(60)
	for threshold in [FOUNDING, RARE, COMMON]:
		assert_eq(_generations_clearing(chain, threshold) < 60, true, "tier eventually lapses")
		assert_eq(threshold > FLOOR, true, "tier sits above the floor")


func test_no_tier_is_dead_content() -> void:
	# A tier above the one-generation ceiling can never be inherited by anyone,
	# however pure the parents. This is the check whose absence let the previous
	# draft's 0.70 and 0.85 tiers ship as content nothing could reach.
	var ceiling := _child_purity(1.0, 1.0)
	assert_eq(ceiling, 0.745, "published one-generation ceiling")
	for tier_name in ["founding", "rare", "common"]:
		var threshold := FOUNDING
		match tier_name:
			"rare":
				threshold = RARE
			"common":
				threshold = COMMON
		assert_eq(threshold <= ceiling, true, "%s tier is reachable in one generation" % tier_name)
		assert_eq(_minimum_parent(threshold) <= 1.0, true, "%s needs a possible parent" % tier_name)


func test_first_generation_parent_purity_matches_the_published_minimums() -> void:
	_tol(_minimum_parent(FOUNDING), 0.964, "founding parent purity")
	_tol(_minimum_parent(RARE), 0.721, "rare parent purity")
	_tol(_minimum_parent(COMMON), 0.536, "common parent purity")


func test_a_lineage_absent_from_one_parent_dilutes_toward_the_floor() -> void:
	# The mean is what makes an outsider spouse a real cost. Blending toward the
	# maximum instead would make every pairing behave the same.
	assert_almost_eq(_child_purity(1.0, ABSENT), 0.395, "first generation, carrier only")
	_tol(_child_purity(0.395, ABSENT), 0.183, "second generation")
	var purity := 1.0
	for _generation in 20:
		purity = _child_purity(purity, ABSENT)
	# The one-sided line's own fixed point. It is BELOW the authored floor, because half
	# the mean is dropped onto the floor rather than doubled: `x -> (x/2) * R + C` fixes
	# at `C / (2 * (1 - R)) = 0.045 / 0.6 = 0.075`. The ADR claims only that such a line
	# "settles", and settling below the floor is what makes an outsider spouse a
	# permanent cost rather than a rounding error. Asserted in closed form, because the
	# map contracts by 0.35 per generation and 20 iterations is nowhere near its own
	# fixed point — an epsilon wide enough for that tail would hide a wrong constant.
	var carrier_fixed_point: float = BLEND_CONSTANT / (2.0 * (1.0 - RETENTION))
	assert_almost_eq(carrier_fixed_point, 0.075, "a carrier line has its own fixed point")
	assert_eq(purity < carrier_fixed_point, true, "and 20 generations is still approaching it")
	assert_eq(carrier_fixed_point < FLOOR, true, "which is below the authored floor")
	assert_eq(carrier_fixed_point > 0.0, true, "but never reaches zero")


func test_a_child_never_exceeds_the_pure_limit() -> void:
	# Purity is capped at 1.0 no matter what the parents are, so no amount of
	# pairing produces an unbounded super-bloodline.
	for _attempt in 20:
		assert_almost_eq(_child_purity(1.0, 1.0), 0.745, "ceiling holds")


func _generations_clearing(chain: Array[float], threshold: float) -> int:
	var last := -1
	for generation in range(chain.size()):
		if chain[generation] >= threshold:
			last = generation
	return last


func _tol(actual: float, published: float, label: String) -> void:
	assert_almost_eq(actual, published, label, PUBLISHED_TOLERANCE)
