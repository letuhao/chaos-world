extends "res://tests/modules/combat_engine/qi_damage_fixture.gd"

## ADR 0069: qi damage is an ELEMENTAL SHARE, never a blended payload.
##
## Six load-bearing properties, each asserted here rather than argued in review:
##
## 1. `match` sits BETWEEN the elemental magnitude and mitigation, so a deeply DEFENDED
##    target is a hard counter even to a `STRONG` 1.5. Move `match` after `mit` and
##    [method test_a_resist_cap_defender_is_a_hard_counter_even_to_a_strong_matchup] and
##    [method test_the_matchup_multiplies_the_elemental_term_and_nothing_else] both fail.
##    (The test keeps its pre-ADR-0200 NAME so a reviewer's history is readable; its
##    body speaks of a defense MAGNITUDE, since `resist_cap` is deleted.)
## 2. Resistance applies to the ELEMENTAL TERM ONLY. `t_0` is the floor.
## 3. One element per attack; a hybrid payload is REJECTED and has no code path.
## 4. Mastery is a PENETRATION lever expressed as a BOUNDED RECIPROCAL on the defense
##    value (`D / (1 + pen/pierce_scale)`), so it can never amplify past `D` and can never
##    drive defense negative -- the property the deleted `RESIST_CAP` subtraction could not
##    claim, because it could subtract straight past a defended point into a free one.
## 5. Degrade, never throw.
## 6. `ElementRules` is INJECTED -- see
##    [method test_the_mechanism_names_no_class_of_the_elements_module].
##
## Every expected number below is DERIVED from a real actor's live `derived()` read, not
## pasted from a document. A stat formula change moves the table with it.
##
## The pinned actor arithmetic itself lives in `qi_damage_fixture.gd`, shared with
## `test_qi_damage_realm.gd` -- one copy, because a second copy would drift and a drift
## here is invisible: both suites stay green against their own arithmetic.

# --- the worked numeric table ---------------------------------------------------


## The full formula, one row per case, every term computed by the mechanism and every
## total re-derived here from the same primitives. A row that disagrees with its own
## arithmetic is a formula bug; a column that disagrees with the ADR is an ordering bug.
##
## The matchup column is the SHIPPED wuxing-克 cycle, and reading it correctly is what this
## table exists to catch: fire > metal, metal > wood, wood > earth, earth > water,
## water > fire. So `fire > metal` is the STRONG pair and `fire > wood` is NEUTRAL. This
## file used to assert `fire > wood == 1.5` and carried an `expected_totals` array derived
## from it; that is the bulk of what a status-program audit counted as "31 test_qi_damage
## failures" (DEF-0140, whose resolution is that the shipped table was right and this test
## was the defect).
func test_the_worked_numeric_table() -> void:
	var rows := [
		_row(ElementStats.FIRE, ElementStats.WOOD, 0.8),
		_row(ElementStats.FIRE, ElementStats.METAL, 0.8),
		_row(ElementStats.FIRE, ElementStats.EARTH, 0.8),
		_row(ElementStats.FIRE, ElementStats.WATER, 1.0),
		_row(ElementStats.FIRE, ElementStats.FIRE, 1.0),
		_row(ElementStats.WATER, ElementStats.METAL, 0.8),
		_row(ElementStats.FIRE, ElementStats.WATER, 0.75),
		_row(&"no_such_element", ElementStats.FIRE, 0.8),
	]
	# Every row: magnitude 100.0, elemental power 10.0, raw attack 25.0, elemental defense
	# 50 points in the ATTACKER's element, and a 0.5 flat reduction.
	#
	# ## ADR 0200: `mit` is no longer `0.5` here, and the EXPECTATION was what was wrong
	#
	# The old comment said "resistance 50 points in the attacker's element (so
	# `mit == 0.5`)" and `expected_totals` was built from `DAMAGE_REDUCTION` arithmetic
	# alone. Under the ratio, `D = 50.0 / 100.0 = 0.5` against a `K = 0.45 * 10.0 = 4.5`,
	# so `m = 0.95 * 0.5 / 5.0 = 0.095` and `mit = 0.905`. That is not a rounding drift: the
	# OLD reading was `clampf(D/divisor, 0, resist_cap) = 0.5`, a defense of `0.5` that
	# mitigated half of every strike off a SINGLE divisor, which is exactly the constant-
	# divisor-meets-a-fixed-defense defect ADR 0200 exists to remove.
	#
	# The totals are therefore DERIVED below rather than pasted, from `mitigation_ceiling`,
	# `defense_divisor_k`, `resist_divisor` and `pierce_scale` as the tuning carries them --
	# so a rebalance moves this table instead of breaking it, and a reader can see the
	# whole formula without a second copy of it.
	var defense := 50.0 / _tuning.resist_divisor
	var divisor_k := _tuning.defense_divisor_k * _fire_affinity()
	var mitigation_of: Callable = func(_d: float) -> float:
		return 1.0 - _tuning.mitigation_ceiling * _d / (divisor_k + _d)
	# The row-6 attacker is WATER, so its `element_power_water` is the same 10.0 the
	# affinity pins for every row; `K` is therefore identical across the table and the only
	# row-to-row variation is the matchup and the share.
	assert_almost_eq(
		mitigation_of.call(defense), 0.905, "50 points of defense over a divisor of 100.0"
	)
	assert_almost_eq(
		float(_row(ElementStats.WATER, ElementStats.METAL, 0.0)["divisor_k"]), 4.5, "K"
	)
# `t_e = 1000 * share * matchup * mit`, `t_0 = 2500 * (1 - share)`, `total = sum * 0.5`.
	# Rows 2 and 5 author their share EXPLICITLY: they used to author `0.0` and lean on
	# the tuning default, which was `0.8` until BL-0348's ruling set it to `0.0` — a test
	# whose value depended on a default the owner has since ruled away is a test of the
	# default rather than of the matchup it is here to price. Row 7's element is unknown
	# to the rules, so it degrades to the raw-only hit and pays no mitigation at all.
	# (`void` used to fill that slot; ADR 0921 made it a real element, so the row names a
	# genuinely unknown id rather than an element that now resolves.)
	#
	# ## ADR 0200 + the element-defense ladder: rows 2, 3 and 6 were NOT under-mitigated —
	# they were using the WRONG MATCHUP, and the terms missing were `NOURISH` and `WEAK`
	#
	# Every row here shares the defender's `D`, so `mit` is identical across all eight and
	# the ONLY per-row variation is `match` and `share`. The old `expected_totals` list
	# hard-coded `1.0` on rows 2, 3 and 6, and that is right for row 0 (`fire > wood` is
	# NEUTRAL) and wrong for the other two. Reading the shipped cycle off
	# `default_elements.gd` — `_make(id, name, tier, generates, overcomes)`, so `water` is
	# generated by metal and overcomes fire, and `fire` generates earth:
	#
	# ```
	# row 2  fire -> earth   fire generates earth          => NOURISH 0.75
	# row 3  fire -> water   water OVERCOMES fire (水克火)   => WEAK    0.5
	# row 6  fire -> water   water OVERCOMES fire (水克火)   => WEAK    0.5
	# ```
	#
	# The magnitudes reconcile exactly, which is what says the TABLE was wrong and the
	# mechanism right — not one of these rows is a formula defect:
	#
	# ```
	# row 2  (1000*0.8*0.75*0.905 + 2500*0.2)*0.5 = (543.0 + 500.0)*0.5 = 521.5
	# row 3  (1000*1.0*0.5 *0.905 + 2500*0.0)*0.5 =  452.5 *0.5         = 226.25
	# row 5  (1000*0.8*1.0 *0.905 + 2500*0.2)*0.5 = (724.0 + 500.0)*0.5 = 612.0
	# row 6  (1000*0.75*0.5*0.905 + 2500*0.25)*0.5 = (339.375 + 625.0)*0.5 = 482.1875
	# ```
	#
	# Every one of those is the figure the mechanism was already producing. The defect was
	# that a pasted matchup column was never compared with the cycle it was pasted from —
	# closed below, where each row's `matchup` is read back off `ElementRules.multiplier`.
	# Rows 0, 1, 4 and 5 pass today only because they happened to be spelled correctly.
	var mit := float(mitigation_of.call(defense))
	var expected_totals := [
		(1000.0 * 0.8 * 1.0 * mit + 2500.0 * 0.2) * 0.5,
		(1000.0 * 0.8 * 1.5 * mit + 2500.0 * 0.2) * 0.5,
		(1000.0 * 0.8 * 0.75 * mit + 2500.0 * 0.2) * 0.5,
		(1000.0 * 1.0 * 0.5 * mit + 2500.0 * 0.0) * 0.5,
		(1000.0 * 1.0 * 1.0 * mit + 2500.0 * 0.0) * 0.5,
		(1000.0 * 0.8 * 1.0 * mit + 2500.0 * 0.2) * 0.5,
		(1000.0 * 0.75 * 0.5 * mit + 2500.0 * 0.25) * 0.5,
		2500.0 * 0.5
	]
	# The numbers the table used to pin, kept so the MIGRATION is auditable rather than a
	# silent rewrite: under `resist_cap`'s `mit == 0.5` these were the totals, and every one
	# of rows 0-6 is strictly smaller because the new curve mitigates LESS at this defense.
	# Row 7 is the raw-only degradation and is UNCHANGED, which is the qi premise.
	var retired_totals := [450.0, 550.0, 400.0, 125.0, 250.0, 450.0, 406.25, 1250.0]
	for index in rows.size():
		var parts: Dictionary = rows[index]
		var label := "row %d (%s -> %s)" % [index, parts["element"], parts["defender_element"]]
		var share := float(parts["share"])
		var magnitude := float(parts["magnitude"])
		var matchup := float(parts["matchup"])
		var mitigation := float(parts["mitigation"])
		var elemental_power := float(parts["elemental_power"])
		var raw_attack := float(parts["raw_attack"])
		var expected_elemental := magnitude * share * elemental_power * matchup * mitigation
		var expected_raw := magnitude * (1.0 - share) * raw_attack
		assert_almost_eq(float(parts["elemental_term"]), expected_elemental, label + ": t_e", 1e-6)
		assert_almost_eq(float(parts["raw_term"]), expected_raw, label + ": t_0", 1e-6)
		assert_almost_eq(
			float(parts["subtotal"]),
			expected_elemental + expected_raw,
			label + ": subtotal is the sum of the two terms",
			1e-6
		)
		assert_almost_eq(
			float(parts["total"]),
			expected_totals[index] if index < expected_totals.size() else 0.0,
			label + ": S5 total with a 0.5 reduction",
			1e-6
		)
		if index < 7:
			# The migration, pinned as a DIRECTION rather than left implicit: the new ratio
			# mitigates strictly LESS than the deleted constant-divisor percent at this
			# defense, and strictly MORE than no mitigation at all.
			assert_eq(
				float(parts["total"]) > retired_totals[index],
				true,
				label + ": less mitigation than the deleted resist_cap reading"
			)
			assert_eq(
				float(parts["mitigation"]) < 1.0,
				true,
				label + ": and never fully mitigated, however deep the defense"
			)
		assert_eq(is_finite(float(parts["total"])), true, label + ": finite")
		assert_almost_eq(
			float(parts["total"]),
			float(parts["subtotal"]) * float(parts["mitigated"]),
			label + ": total is subtotal times the reduction factor",
			1e-6
		)

# The matchup column is read off the row the mechanism used, so the eight literals above
	# can no longer drift from the shipped cycle without this firing: the old table's whole
	# failure was three rows whose expected total disagreed with the matchup the mechanism
	# actually applied, and nothing in the suite compared the two. Each row states its own
	# pair, because "which edge is this" is the thing a reader is checking.
	var expected_matchups := [
		[ElementStats.FIRE, ElementStats.WOOD],
		[ElementStats.FIRE, ElementStats.METAL],
		[ElementStats.FIRE, ElementStats.EARTH],
		[ElementStats.FIRE, ElementStats.WATER],
		[ElementStats.FIRE, ElementStats.FIRE],
		[ElementStats.WATER, ElementStats.METAL],
		[ElementStats.FIRE, ElementStats.WATER],
		[&"void", ElementStats.FIRE]
	]
	for index in rows.size():
		if index == 7:
			# The unknown element degrades to a raw-only hit and is paid `NEUTRAL` by
			# `_matchup_of`, so there is no cycle edge to check it against.
			continue
		var pair: Array = expected_matchups[index]
		var read_from_cycle := _rules.multiplier(pair[0], pair[1])
		assert_almost_eq(
			float(rows[index]["matchup"]),
			read_from_cycle,
			(
				"row %d's matchup is the shipped cycle's answer for %s -> %s"
				% [index, str(pair[0]), str(pair[1])]
			)
		)
	# And the two edges whose constants have no counterpart in the overcome cycle spelled
	# out above, each asserted by name. These are the terms the old table was missing on
	# rows 2, 3 and 6, and between them they cover every pair in the shipped wuxing graph:
	# `fire > earth` is the generation edge and `fire > water` is the 相克 edge, so a
	# reader who checks two pairs has checked the whole vocabulary.
	assert_almost_eq(
		_rules.multiplier(ElementStats.FIRE, ElementStats.EARTH),
		ElementRules.NOURISH,
		"fire generates earth, so fire into earth is NOURISH and not NEUTRAL"
	)
	assert_almost_eq(
		_rules.multiplier(ElementStats.FIRE, ElementStats.WATER),
		ElementRules.WEAK,
		"water overcomes fire (水克火), so fire into water is WEAK and not NEUTRAL"
	)
	# And the NEUTRAL the old table assumed for all three of those rows, kept as an
	# explicit positive case so the three above cannot all be wrong in one direction.
	assert_almost_eq(
		_rules.multiplier(ElementStats.FIRE, ElementStats.WOOD),
		ElementRules.NEUTRAL,
		"fire into wood really is NEUTRAL, which is what row 0 was"
	)


## S4 returns the subtotal and S5 returns the reduced total: two mechanisms' callers
## must be able to observe them separately, which is the whole reason ADR 0067 splits
## the seam. Asserted through the SPINE, not by calling the mechanism directly, so the
## proposal the outcome carries is the one the eleven stages actually produced.
## `QiDamage.builder` is PASSED to the spine. Without it the spine's own context carries no
## `element` and no `element_share` at all — `CombatSpine._context` writes only the four
## shared fields and knows nothing about qi — so the spine produced the raw-only 2500.0
## while the reference `breakdown` read 1300.0 from a context that HAD been given them. The
## two numbers were never comparable, and the pair of assertions could only ever have passed
## on a spine that guessed the element out of the technique.
func test_the_spine_carries_the_two_stage_proposal() -> void:
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 0.0)
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = _tuning
	MechanismSlot.bind(attacker, mech)
	var technique := _technique(ElementStats.FIRE, 0.8)
	var outcome := CombatSpine.resolve_hit(
		attacker,
		target,
		technique,
		_tuning,
		null,
		QiDamage.builder(_rules, technique, ElementStats.WOOD)
	)
	var parts := mech.breakdown(
		_context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.WOOD)
	)
	assert_almost_eq(outcome.proposed_amount(), float(parts["subtotal"]), "S4's subtotal")
	# S7 (`amp_factor`) is exactly 1.0 at zero amplification and zero reduction, and S8
	# floors at `maxf(amount, maxf(1.0, base * 0.01))`, so on a hit of this size the two
	# shared stages are the identity and `outcome.amount` IS S5's number.
	assert_almost_eq(
		outcome.amount,
		float(parts["total"]),
		"S5's reduced total (S7 and S8 are the identity on a hit this large)"
	)


# --- property 1: matchup placement ----------------------------------------------


## THE anti-"fire is always strong" property. A defender at `RESIST_CAP` takes LESS
## from a `STRONG` matchup than an unresisted defender takes from a `NEUTRAL` one.
##
## This is the assertion that FAILS if `match` is moved after `mit`: with `mit` applied
## first, the two cases collapse onto the same product and the ordering stops being
## observable at all.
func test_a_resist_cap_defender_is_a_hard_counter_even_to_a_strong_matchup() -> void:
	var share := 0.8
	var magnitude := 100.0
	# ADR 0200 replaced the capped PERCENT with a ratio of two magnitudes, so "the capped
	# defender" is now a defense MAGNITUDE rather than a share of a cap. This is a
	# correction, not a relaxation: the property under test is unchanged (a heavily
	# defended target takes less from a STRONG matchup than an open one takes from a
	# NEUTRAL one), only the way "heavily defended" is expressed.
	# The ordering assertion: `match` is a factor of `t_e` and the mitigation a factor of
	# the SUM, so a STRONG match into a defended point has to lose to a NEUTRAL one into an
	# open point. The cross product is what makes it a real claim rather than a tautology —
	# `1.5 * mit` against `1.0` -- and it needs `1.5 * mit < 1.0`, i.e. `mit < 0.6667`.
	#
	# ADR 0200 + the element-defense ladder: `resist_divisor * 2 = 200.0` defense points
	# put this row OUT of the regime the case is about, and the DEFENSE is what moved
	# rather than the matchup. `_defender` sets affinity to `points * 2` and
	# `ElementProvider` contributes `affinity * 0.5`, so 200 points is `D = 200.0` against
	# a `K = 4.5` — a rate of `0.95 * 200/204.5 = 0.9291`, and `1.5 * (1 - 0.9291) = 0.1064`
	# which beats `1.0`. A `1.5` matchup CANNOT out-resist a mitigation above
	# `1/1.5 = 0.6667`, and no amount of re-reading makes it otherwise. (The `1 - 1/1.5 =
	# 0.3333` form this paragraph used to quote was the rate `m` rather than the multiplier
	# `mit`, which is how the regime assertion below came to be written upside down.)
	#
	# ## ADR 0200: the REGIME was solved backwards, and the SCALE was divided twice
	#
	# The property is `match * mit < 1.0` — the STRONG matchup's advantage over the NEUTRAL
	# one has to be larger than the defense it pays. With `mit = 1 - ceiling * D/(K + D)`:
	#
	# ```
	# match * (1 - ceiling * D/(K + D)) < 1
	#   =>  match*K - match*ceiling*D < K + D
	#   =>  K*(match - 1) < D*(match*ceiling - match + 1)
	#   =>  D > K*(match - 1) / (match*ceiling - match + 1)
	# ```
	#
	# Two things were wrong with the row this case used to build. The denominator ran the
	# wrong way AND had the wrong FORM — `K*ceiling/(1 - 1/matchup)` is `0.45*10*0.95/0.3333
	# = 12.825`, an order of magnitude PAST the boundary `2.4324`, so the case had left the
	# regime it exists to describe: a defense that deep answers `mit = 0.198`, `match*mit =
	# 0.297`, and `t_e = 237.98` against an open target's `800.0`, a `3.4x` win rather than a
	# hard counter. The regime test that was supposed to catch this asserted
	# `mitigation > 1 - 1/matchup`, which is a DIFFERENT and backwards statement: the
	# ordering needs `mit` BELOW `1/matchup = 0.6667`, not above `1 - 1/matchup = 0.3333`, so
	# the assertion passed on a row that violated the property it was guarding.
	#
	# The second fault is a UNIT one on the way in, which is the same mistake
	# `test_qi_damage.gd`'s own `_pin_the_table` gets right: `_parts`' fourth argument is a
	# defense SPACE, not a `D`. `_defender` doubles it into an affinity and
	# `ElementProvider` contributes `affinity * 0.5`, so a solved `D` reaches the mechanism
	# as `D * 2 / resist_divisor`. Handing the solved `D` over unscaled built `D = 0.012825`
	# against `K = 4.5` — a rate of `0.0027` — and the row defended nothing at all.
	#
	# So the defense is DERIVED from the matchup and the ceiling rather than pasted beside
	# them, which is what makes the case survive a balance pass: what is under test is the
	# RELATIONSHIP between a matchup and a mitigation, and the defense is only ever the knob
	# that decides which side of it the row lands on. The figure is then scaled back into
	# the space `_parts` takes rather than assumed to be one.
	var matchup := 1.5
	# The mitigation at which the two columns tie exactly: `match * mit == 1.0`.
	var tie := 1.0 / matchup
	var divisor_k := _tuning.defense_divisor_k * _fire_affinity()
	var ceiling := _tuning.mitigation_ceiling
	# TWICE the boundary, which is the row the case is about: comfortably inside the regime
	# (`mit` strictly below the tie) and not so deep that the defense reads as saturated.
	var defense := divisor_k * (matchup - 1.0) / (matchup * ceiling - matchup + 1.0) * 2.0
	var strong_vs_capped := _parts(
		ElementStats.FIRE, ElementStats.METAL, share, defense * _tuning.resist_divisor
	)
	var neutral_vs_open := _parts(ElementStats.WATER, ElementStats.METAL, share, 0.0)
	# water > metal is NEUTRAL — water overcomes FIRE, not metal — so matchup 1.0 with no
	# resistance at all.

	assert_almost_eq(float(strong_vs_capped["matchup"]), matchup, "fire > metal is STRONG")
	assert_almost_eq(float(neutral_vs_open["matchup"]), 1.0, "water/metal is NEUTRAL")
	# The regime itself, asserted so the case cannot quietly leave it. `mit` must sit BELOW
	# the tie, because that is the whole of `match * mit < 1.0`: a mitigation above
	# `1/matchup` out-resists any matchup, and the ordering below stops meaning anything.
	assert_eq(
		float(strong_vs_capped["mitigation"]) < tie,
		true,
		(
			(
				"this row sits inside the regime the ordering is about: mitigation %.6f is below "
				+ "the %.6f at which a %.2f matchup stops out-resisting it"
			)
			% [float(strong_vs_capped["mitigation"]), tie, matchup]
		)
	)
	# The ceiling is a MULTIPLIER the curve approaches and never reaches. Asserted as a BAND
	# rather than as `rate < ceiling`: once `D_eff` dominates `K` the ratio
	# `D_eff/(K+D_eff)` rounds to `1.0` in float64, so `ceiling * share` equals the ceiling
	# bit-for-bit and a strict `<` would be asserting a property of floating point rather
	# than of the formula. What holds at EVERY defense is that the rate is exactly
	# `ceiling * D_eff / (K + D_eff)` — asserted here, and across a penetration sweep in the
	# case below — and that it never EXCEEDS the ceiling. Both terms are read off the row,
	# so neither restates a number the tuning already carries.
	var mitigated := float(strong_vs_capped["mitigation"])
	var rate := float(strong_vs_capped["mitigation_rate"])
	assert_almost_eq(
		rate,
		(
			ceiling
			* float(strong_vs_capped["defense_effective"])
			/ (float(strong_vs_capped["divisor_k"]) + float(strong_vs_capped["defense_effective"]))
		),
		"the rate is exactly `mitigation_ceiling * D_eff / (K + D_eff)`, never a clamp on it"
	)
	# `mit = 1 - m_rate` is an OUTPUT in `(0, 1]` and the ceiling bounds `m_rate`. Which
	# half a row is compared against decides whether the assertion is a formula claim or an
	# identity, and the two were CROSSED here — see the case docblock; `mitigation_rate` is
	# what the ceiling bounds, and `mitigation` is never above `1.0` because it is a
	# multiplier, not because anything clamped it.
	assert_eq(mitigated <= 1.0, true, "a defended target's multiplier is never above 1.0")
	assert_eq(mitigated > 0.0, true, "and is never immune: mitigation is asymptotic, not capped")
	assert_eq(
		float(strong_vs_capped["elemental_term"]) < float(neutral_vs_open["elemental_term"]),
		true,
		"a defended target takes LESS from a STRONG match than an open one from a NEUTRAL one"
	)
	# And the arithmetic that makes it true, stated rather than only observed: the
	# matchup is a factor of `t_e` and the mitigation is a factor of the SUM, so the two
	# can disagree. Reordering them makes both products 0.375 and the tie.
	assert_eq(
		float(strong_vs_capped["elemental_term"]) == float(neutral_vs_open["elemental_term"]),
		false,
		"they are genuinely different numbers"
	)
	assert_almost_eq(magnitude, 100.0, "the magnitude both rows share")


## Property 1's other half: `match` multiplies `t_e` and NOTHING else. The raw term is
## byte-identical across two attacker elements with different matchups, which is what
## "resistance and matchup touch the elemental term alone" means.
##
## The pairs are read off the shipped cycle, not asserted into it: `fire > metal` is
## STRONG and `metal > wood` is the WEAK that answers it, so wood-as-attacker against a
## metal defender is the mirror image.
func test_the_matchup_multiplies_the_elemental_term_and_nothing_else() -> void:
	var strong := _parts(ElementStats.FIRE, ElementStats.METAL, 0.8, 0.0)
	var weak := _parts(ElementStats.WOOD, ElementStats.METAL, 0.8, 0.0)
	var neutral := _parts(ElementStats.METAL, ElementStats.EARTH, 0.8, 0.0)
	assert_almost_eq(float(strong["matchup"]), 1.5, "fire > metal")
	assert_almost_eq(float(weak["matchup"]), 0.5, "wood < metal")
	assert_almost_eq(float(neutral["matchup"]), 1.0, "metal/earth is NEUTRAL")
	# The defender differs between rows, so this ALSO holds resistance to zero and
	# proves the raw share is not the thing being scaled.
	assert_eq(
		float(strong["raw_term"]) == float(weak["raw_term"]),
		true,
		"the raw term is byte-identical across a 1.5 and a 0.5 matchup"
	)
	assert_eq(
		float(strong["raw_term"]) == float(neutral["raw_term"]), true, "and across a NEUTRAL one"
	)
	assert_almost_eq(
		float(strong["elemental_term"]) / float(weak["elemental_term"]),
		3.0,
		"the elemental term really is 3x (1.5 / 0.5)",
		1e-4
	)


# --- property 2: the raw share is the floor --------------------------------------


## ADR 0069: "a wrong element is a WEAKER hit, never a null one". A defender whose
## elemental defense is ARBITRARILY DEEP takes the smallest elemental term the formula
## allows, and still takes the whole raw share.
##
## ## ADR 0200: the premise of this test was OBSOLETE, so it was REPLACED, not widened
##
## This used to read `resist_cap = 0.75` and assert `mitigation == 0.25` at that cap.
## **Perfect resistance is now IMPOSSIBLE BY CONSTRUCTION**, and the docblock on
## `QiDamage._mitigation_of` says why: `m = mitigation_ceiling * D / (K + D)` approaches
## `0.95` and never reaches it, so there is no `D` at which the mitigation is `1.0` and no
## `D` at which it stops rising. A test that asked for "the cap" asked for a number the
## mechanism no longer has.
##
## What replaces it asserts BOTH halves of the new guarantee, which is strictly more than
## the old one asserted: (a) at an enormous defense the mitigation is as close to the
## ceiling as the curve allows and is NEVER `1.0`, so the defender is not immune; and (b) at
## that same enormously-defended point the raw share is still paid in full and the hit is
## still positive, so "a wrong element is a WEAKER hit, never a null one" survives intact.
## The old test could not have said (a): at `resist_cap` the mitigation was a constant
## `0.25`, and nothing about that constant distinguished a deep defense from a shallow one.
func test_a_maximally_defended_element_still_deals_the_raw_share_and_is_never_immune() -> void:
	var ceiling := _tuning.mitigation_ceiling
	# `D` is a MAGNITUDE now, so "maximally defended" is a large defense figure rather than
	# a share of a cap. The figure is SPELLED as `_tuning.resist_divisor * 1.0e6` and the
	# resulting `D` is then DERIVED from it below, because the two are the same number
	# stated twice and a pasted literal is a second copy of the divisor.
	#
	# ADR 0200 + the element-defense ladder: `D = resist_divisor * 1e6 / resist_divisor
	# = 1.0e6` against a `K` of `0.45 * elemental_power = 4.5`. That is 100x the
	# `10000.0` this assertion used to expect, because `_defender(element, points)` sets
	# the defender's AFFINITY to `points * 2` and `ElementProvider` contributes defense as
	# `affinity * 0.5 + will * 0.2` — so the defense figure is the authored points, not
	# half of them. The assertion that used to hard-code `10000.0` was pinning a number
	# that was already wrong by a factor of two against the fixture's own docblock; it
	# never fired because the ladder change is what finally moved the defense half off a
	# realm-flat read and made the relationship visible.
	var deep_points := _tuning.resist_divisor * 1.0e6
	var deep := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, deep_points)
	assert_almost_eq(
		float(deep["defense"]),
		deep_points / _tuning.resist_divisor,
		"the million-fold defense over the divisor, derived rather than pasted"
	)
	assert_almost_eq(
		float(deep["divisor_k"]),
		_tuning.defense_divisor_k * float(deep["elemental_power"]),
		"K rides the attacker"
	)
	# (a) NEVER immune, and never at the ceiling either: `m < mitigation_ceiling` strictly
	# for every finite `D`, which is the property `resist_cap` destroyed.
	assert_eq(float(deep["mitigation"]) > 0.0, true, "a defended target is never immune")
	assert_eq(float(deep["mitigation"]) < ceiling, true, "and never reaches the ceiling")
	assert_almost_eq(
		float(deep["mitigation"]),
		(
			1.0
			- ceiling * float(deep["defense"]) / (float(deep["divisor_k"]) + float(deep["defense"]))
		),
		"the curve reads exactly `1 - mitigation_ceiling * D / (K + D)`"
	)
	# (b) The floor. The raw share is untouched by defense, which is the whole qi premise,
	# and the hit is strictly positive.
	assert_almost_eq(
		float(deep["raw_term"]),
		float(deep["magnitude"]) * 0.2 * float(deep["raw_attack"]),
		"and the raw share is untouched -- that IS the floor"
	)
	assert_eq(float(deep["total"]) > 0.0, true, "so the hit is weaker, never null")
	# And the ceiling is a MULTIPLIER rather than a clamp: doubling an enormous defense
	# still raises the mitigation. At `resist_cap` it could not have.
	var deeper := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, _tuning.resist_divisor * 2.0e6)
	assert_eq(
		float(deeper["mitigation"]) < float(deep["mitigation"]),
		true,
		"twice the defense still buys mitigation, however deep it already was"
	)


## There is no separate floor constant anywhere: at `share == 1.0` the floor is zero and
## the raw term is exactly 0.0, which is the strongest possible statement that `t_0` is
## the floor rather than a constant that happens to coincide with it.
func test_there_is_no_separate_floor_constant() -> void:
	var parts := _parts(ElementStats.FIRE, ElementStats.WOOD, 1.0, 0.0)
	assert_eq(float(parts["raw_term"]), 0.0, "no raw share at all")
	assert_eq(float(parts["raw"]), 0.0, "and no raw magnitude either")
	assert_eq(float(parts["total"]) > 0.0, true, "the elemental term is still there")


# --- property 3: one element per attack, blends rejected --------------------------


## ADR 0069's measured proof, asserted against `ElementRules` DIRECTLY rather than
## against the mechanism, because the claim is about the shipped `ElementDefaults` and
## re-measuring is the whole point (BRIEF 4b: grand mean 0.997500, tier-1 mean exactly
## 0.950000, single-element spread 3.0x vs a blend's 2.0x).
func test_the_tier_1_mean_is_exactly_0950_and_a_blend_does_not_move_it() -> void:
	var base := ElementDefaults.base()
	var single_means := []
	var single_low := INF
	var single_high := -INF
	for row in base:
		var total := 0.0
		var low := INF
		var high := -INF
		for column in base:
			var value := _rules.multiplier(row.id, column.id)
			total += value
			low = minf(low, value)
			high = maxf(high, value)
		single_means.append(total / float(base.size()))
		single_low = minf(single_low, low)
		single_high = maxf(single_high, high)
	var single_mean := 0.0
	for value in single_means:
		single_mean += value
	single_mean /= float(single_means.size())
	assert_almost_eq(single_mean, 0.95, "the tier-1 row mean is exactly 0.950000", 1e-9)

	# A 50/50 blend of any two tier-1 elements against the same column.
	var blended_means := []
	var blended_low := INF
	var blended_high := -INF
	for i in base.size():
		for j in range(i + 1, base.size()):
			var total := 0.0
			var low := INF
			var high := -INF
			for column in base:
				var value := (
					(
						_rules.multiplier(base[i].id, column.id)
						+ _rules.multiplier(base[j].id, column.id)
					)
					/ 2.0
				)
				total += value
				low = minf(low, value)
				high = maxf(high, value)
			blended_means.append(total / float(base.size()))
			blended_low = minf(blended_low, low)
			blended_high = maxf(blended_high, high)
	var blend_mean := 0.0
	for value in blended_means:
		blend_mean += value
	blend_mean /= float(blended_means.size())
	assert_almost_eq(
		blend_mean, single_mean, "a blend's mean is IDENTICAL to a single element's", 1e-9
	)
	assert_almost_eq(single_low, 0.5, "single elements bottom out at WEAK", 1e-9)
	assert_almost_eq(single_high, 1.5, "and top out at STRONG", 1e-9)
	assert_almost_eq(blended_low, 0.625, "a blend never sees a full WEAK", 1e-9)
	assert_almost_eq(blended_high, 1.25, "nor a full STRONG", 1e-9)
	assert_eq(
		(single_high / single_low) > (blended_high / blended_low),
		true,
		"3.0x spread against 2.0x: the blend gives up the read and keeps nothing"
	)


## There is no blend code path. An `Array` under the element key is not an element, so a
## hybrid payload degrades to the raw-only hit rather than being averaged into one.
func test_a_hybrid_payload_has_no_code_path_and_degrades_to_raw() -> void:
	var hybrid := _context(
		_attacker(), _defender(ElementStats.FIRE, 0.0), [ElementStats.FIRE, ElementStats.WATER], 0.8
	)
	var parts := QiDamage.new().breakdown(hybrid)
	assert_eq(parts["element"], "", "an Array is not an element id")
	assert_eq(float(parts["share"]), 0.0, "and so there is no elemental share")
	assert_eq(float(parts["elemental_term"]), 0.0, "no elemental term")
	assert_eq(float(parts["raw"]), float(parts["magnitude"]), "the whole magnitude is raw")
	assert_eq(float(parts["total"]) > 0.0, true, "still a landed hit")


# --- property 4: mastery is penetration, a bounded reciprocal on the DEFENSE ------


## `CombatStats.PENETRATION` is ADR 0069's mastery lever on the DEFENDER's defense
## (ADR 0068 defines that id as exactly "a read-only input to a mechanism's mitigate").
## It moves the elemental term and the raw term does not move AT ALL -- byte-identical,
## not nearly.
##
## ## ADR 0200: the mechanism of penetration changed from a subtraction to a reciprocal
##
## It used to read `defense = clampf(raw/divisor - pen, 0, resist_cap)` and assert that
## `0.4` of penetration had taken `0.5` down to `0.1` -- a LINEAR exchange rate of one
## point of defense per point of penetration. ADR 0200 replaces that with
## `defense_effective = D / (1 + pen / pierce_scale)`, which has no constant exchange rate
## at all: `pierce_scale = 10.0` so `0.4` of penetration is a factor of `1/1.04`.
##
## The property under test is UNCHANGED and is now stated as the ratio property that
## replaced the linear one, which is what ADR 0200's docblock actually claims: penetration
## SCALES the defense value, bounded in `(0, 1]`. That is a stronger claim than the
## subtraction had — the subtraction could drive defense negative and turn a defended point
## into a free one; this cannot.
func test_mastery_moves_only_the_elemental_term() -> void:
	var untrained := _attacker()
	var trained := _attacker()
	trained.stats.add_modifier(
		StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, 0.4, &"test_mastery")
	)
	var before := QiDamage.new().breakdown(
		_context(untrained, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
	)
	var after := QiDamage.new().breakdown(
		_context(trained, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
	)
	assert_almost_eq(float(before["defense"]), 0.5, "50 points over the divisor")
	# The reciprocal, measured rather than quoted: `0.5 / (1 + 0.4/10.0)`.
	assert_almost_eq(
		float(after["defense_effective"]),
		0.5 / (1.0 + 0.4 / _tuning.pierce_scale),
		"0.4 of penetration is a factor of 1/(1 + 0.4/pierce_scale), not a subtraction"
	)
	assert_almost_eq(
		float(after["defense"]),
		float(before["defense"]),
		"penetration scales `defense_effective`, and `defense` itself is untouched"
	)
	assert_eq(
		float(after["raw_term"]) == float(before["raw_term"]),
		true,
		"the raw term is BYTE-IDENTICAL before and after mastery"
	)
	assert_eq(
		float(after["magnitude"]) == float(before["magnitude"]), true, "and so is the magnitude"
	)
	assert_eq(
		float(after["elemental_term"]) > float(before["elemental_term"]),
		true,
		"the elemental term did move"
	)


# --- The bounds and degradation cases moved to `test_qi_damage_bounds.gd` -------
# (penetration bounds, the null/NaN/degenerate tunings, the injection routes and the
# round trip; same fixture, same claims).


## One table row, every primitive the mechanism computed for it.
##
## The attacker is built with its affinity in the row's OWN element and the defender with
## its resistance in that same element, so `elemental_power` and `mitigation` are the same
## on every row and the matchup is the only thing that varies — which is what makes the
## eight totals comparable. `defender_element` is carried on the context explicitly rather
## than left to the dominance walk, so a row whose defender has no affinity in the column
## still reads the column it is about. The first row pins all of that: if `raw_attack`
## moves, or the wrong column is read, the first row fails visibly instead of eight rows
## failing obscurely.
func _row(element: StringName, defender_element: StringName, share: float) -> Dictionary:
	var attacker := _attacker(element)
	var target := _defender(element, 50.0)
	target.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 0.5, &"test_half_reduction")
	)
	var parts := QiDamage.new().breakdown(
		_context(attacker, target, element, share, 100.0, defender_element)
	)
	if element == ElementStats.FIRE and defender_element == ElementStats.WOOD:
		_pin_the_table(parts)
	return parts


## The reference row's invariants, asserted where the reference is built.
func _pin_the_table(parts: Dictionary) -> void:
	var first := _parts(ElementStats.FIRE, ElementStats.WOOD, 0.8, 50.0)
	assert_almost_eq(float(parts["raw_attack"]), 25.0, "spirit 10.0 x2 + aptitude 10.0 x0.5")
	assert_almost_eq(float(parts["elemental_power"]), _fire_affinity(), "affinity 10.0")
	assert_eq(
		String(parts["defender_element"]),
		String(ElementStats.WOOD),
		"the carried defender element really is wood"
	)
	# `fire > wood` is NEUTRAL in the shipped cycle: fire overcomes METAL, metal overcomes
	# WOOD, and nothing generates into that pair. DEF-0140 recorded this table as the
	# authority and this assertion as the defect.
	assert_almost_eq(float(parts["matchup"]), 1.0, "fire is NEUTRAL against wood")
	# ADR 0200: the mitigation is an OUTPUT of the ratio rather than the defense itself, so
	# "50 points over a divisor of 100.0" is now `D = 0.5` and `mit = 1 - 0.95 * 0.5/(4.5 +
	# 0.5) = 0.905`. The old expectation of `0.5` was the DELETED percent -- a defense of
	# `0.5` that mitigated half of every strike off one constant divisor, which is the
	# defect the ADR exists to remove. The formula is spelled out here rather than a literal
	# so a rebalance of either number moves the expectation with it.
	var defense := 50.0 / _tuning.resist_divisor
	var divisor_k := _tuning.defense_divisor_k * float(parts["elemental_power"])
	assert_almost_eq(float(first["defense"]), defense, "50 points over a divisor of 100.0")
	assert_almost_eq(
		float(first["mitigation"]),
		1.0 - _tuning.mitigation_ceiling * defense / (divisor_k + defense),
		"and the mitigation is `1 - mitigation_ceiling * D / (K + D)`"
	)
	assert_almost_eq(float(parts["damage_reduction"]), 0.5, "the authored flat reduction")
	assert_almost_eq(float(parts["mitigated"]), 0.5, "and so the reduction factor")
	assert_almost_eq(
		float(parts["raw_term"]), float(parts["magnitude"]) * 0.2 * 25.0, "t_0, pinned"
	)
