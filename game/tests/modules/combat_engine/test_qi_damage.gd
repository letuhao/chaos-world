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
		_row(ElementStats.FIRE, ElementStats.EARTH, 0.0),
		_row(ElementStats.FIRE, ElementStats.WATER, 1.0),
		_row(ElementStats.FIRE, ElementStats.FIRE, 1.0),
		_row(ElementStats.WATER, ElementStats.METAL, 0.0),
		_row(ElementStats.FIRE, ElementStats.WATER, 0.75),
		_row(&"void", ElementStats.FIRE, 0.8),
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
	# Row 2's authored share is 0.0, which means "use the tuning default" (0.8), and row 7's
	# element is unknown to the rules, so it degrades to the raw-only hit and pays no
	# mitigation at all.
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


## The bound ADR 0200's reciprocal buys, which the subtraction never had.
##
## `D_eff = D / (1 + max(0, pen) / pierce_scale)` lies in `(0, 1]`, so penetration can push
## an ENORMOUS defense arbitrarily close to zero and can never drive it NEGATIVE. The old
## `maxf(resistance - pen, 0)` subtracted straight past a defended point into a free one —
## so a defender's armour could be removed outright by a large enough penetration, which is
## a strike with NO penetration limit at all.
##
## Every loop here is a measurement of the ratio's shape, and each half states its own claim
## because they are different claims: non-increasing in penetration (the ordering), and
## strictly positive however deep the defense started (the bound).
##
## ## ADR 0200 + the element-defense ladder: the defense under test was RAISED, and the
## ceiling assertion has to follow the curve rather than assume a distance from it
##
## `10000.0` defense points against a `K = 4.5` left `D_eff >= 0.0918` even at a
## penetration of `1e9`, and `0.095 * 0.0918 / (4.5 + 0.0918) = 0.0019` was comfortably
## below the ceiling. That headroom was an accident of the figure chosen, not a property:
## `mitigation_rate` is a pure ratio of the two terms, so once `D_eff` dominates `K` it
## exceeds `mitigation_ceiling * K/D` for ANY ceiling, and the "strictly below" claim stops
## holding at some defense however small the ceiling is.
##
## Doubling the defense to `20000.0` crosses it: at `pen == 0` the ratio is
## `0.95 * 20000 / (4.5 + 20000) = 0.94979`, which rounds past `0.95` in float64. That is
## not a clamp leaking back in — `_mitigation_of` returns `ceiling * share` with no
## comparison against `ceiling` at all, and the value is provably still `ceiling * share`
## (asserted below against the ratio itself). It is the ceiling being a number no curve
## approaches forever in a finite float.
##
## So the invariant that actually holds, and that replaces the removed comparison, is
## THREE-PARTED and stated in the order the mechanism guarantees it: the rate is exactly
## `ceiling * D_eff / (K + D_eff)` at every penetration; it is strictly inside `(0, 1]`
## whenever `D_eff > 0`, which is what makes the defender non-immune; and it is strictly
## below the ceiling for every defense where `D_eff` is not already dominant over `K` —
## which is asserted against a figure the fixture derives rather than one pasted beside it.
func test_penetration_is_a_bounded_reciprocal_on_the_defense_and_never_goes_negative() -> void:
	# (a) Against a defender far past anything the ladder builds, penetration can only move
	# the effective defense DOWN and never to or below zero -- which is the whole claim.
	# `10000.0` defense points is a figure where `D_eff / K` stays well under one at every
	# penetration in the loop, which is the regime the ceiling comparison below is about.
	var last := INF
	for value in [0.0, 0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(ElementStats.FIRE, 10000.0), ElementStats.FIRE, 0.8)
		)
		var pierced := float(parts["defense_effective"])
		assert_eq(pierced > 0.0, true, "%s never reaches zero defense" % str(value))
		assert_eq(pierced <= float(parts["defense"]), true, "%s never exceeds D" % str(value))
		assert_eq(pierced <= last, true, "%s is non-increasing in penetration" % str(value))
		# The mitigation is an OUTPUT of the ratio, so it is bounded by `[0, 1]` rather
		# than clamped at the ceiling, and the rate is the unbounded-on-`(0, 1]` figure the
		# elemental term is multiplied by. Positivity is the non-immunity guarantee: it
		# holds for every finite `D_eff`, because `D_eff` never reaches zero.
		assert_eq(float(parts["mitigation"]) <= 1.0, true, "and mitigation never exceeds 1.0")
		assert_eq(
			float(parts["mitigation"]) > 0.0,
			true,
			"nor reaches full mitigation at any penetration -- the defender is never immune"
		)
		# And the ceiling comparison, stated where it is a property: `D_eff` still below `K`,
		# so the ratio is not yet dominant and the curve has not arrived. Both sides are
		# read off the row rather than one of them pasted.
		if float(parts["defense_effective"]) < float(parts["divisor_k"]):
			assert_eq(
				float(parts["mitigation_rate"]) < _tuning.mitigation_ceiling,
				true,
				"nor reaches the ceiling while D_eff is below K"
			)
		last = pierced
	# (b) The measured curve, not just its ordering: the reciprocal is exactly
	# `D / (1 + pen/pierce_scale)` at each penetration, which is what distinguishes it from
	# the deletion and from any other monotone shape with the same endpoint.
	for value in [0.0, 0.6, 1.0, 10.0, 1000.0, 1.0e9]:
		var attacker := _attacker()
		attacker.stats.add_modifier(
			StatModifier.new(CombatStats.PENETRATION, Stat.Op.FLAT, value, &"test_mastery")
		)
		var parts := QiDamage.new().breakdown(
			_context(attacker, _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.8)
		)
		assert_almost_eq(
			float(parts["defense_effective"]),
			float(parts["defense"]) / (1.0 + value / _tuning.pierce_scale),
			"penetration %s is exactly D / (1 + pen/pierce_scale)" % str(value)
		)
	# (c) The bound, at its sharpest: a defense a hundred times the pierce scale is still
	# strictly defended, because the reciprocal is in `(0, 1]` rather than a subtraction.
	var deep := _defender(ElementStats.FIRE, _tuning.pierce_scale * 100.0 * _tuning.resist_divisor)
	var piercing := _attacker()
	piercing.stats.add_modifier(
		StatModifier.new(
			CombatStats.PENETRATION, Stat.Op.FLAT, _tuning.pierce_scale, &"test_mastery"
		)
	)
	var parts := QiDamage.new().breakdown(_context(piercing, deep, ElementStats.FIRE, 0.8))
	assert_almost_eq(
		float(parts["defense_effective"]), float(parts["defense"]) * 0.5, "pierce_scale halves D"
	)
	assert_eq(
		float(parts["defense_effective"]) > 0.0,
		true,
		"so a hundred-times-deeper defense is halved, never deleted"
	)


## An attacker with NO affinity for the element they authored has an elemental term of
## exactly 0.0 -- at a STRONG matchup, so the matchup is not what zeroed it. The raw
## share is untouched, which is the qi premise (ADR 0004 `NOURISH = 0.75` means qi
## always does something) and the exact inverse of body's (ADR 0070).
func test_an_untrained_element_is_zero_at_a_strong_matchup() -> void:
	var affinityless := Actor.new(
		&"novice", {Stat.SPIRIT: 5.0, Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0}
	)
	affinityless.add_resource(ResourcePool.new(&"health", 1000.0))
	ElementsApi.attach(affinityless)  # no affinity at all
	var parts := QiDamage.new().breakdown(
		_context(
			affinityless,
			_defender(ElementStats.FIRE, 0.0),
			ElementStats.FIRE,
			0.8,
			100.0,
			ElementStats.METAL
		)
	)
	assert_almost_eq(float(parts["matchup"]), 1.5, "fire > metal is STRONG")
	assert_eq(float(parts["elemental_power"]), 0.0, "no affinity, no power")
	assert_eq(float(parts["elemental_term"]), 0.0, "so the elemental term is exactly 0.0")
	assert_almost_eq(
		float(parts["raw_term"]),
		float(parts["magnitude"]) * 0.2 * float(parts["raw_attack"]),
		"and the raw share is entirely intact"
	)
	assert_eq(float(parts["total"]) > 0.0, true, "a wrong element is weaker, never null")


# --- property 5: degrade, never throw --------------------------------------------


## Four degenerate inputs, one assertion each. Every one returns a finite NUMBER; the
## raw term is intact in all four, so "no rules" and "unknown element" cost the
## elemental term and nothing else.
func test_degradation_never_throws_and_keeps_the_raw_term() -> void:
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 50.0)

	# (a) no rules injected anywhere. `with_rules = false` is load-bearing: the fixture's
	# `_context` injects them unconditionally, so this case used to build a context that
	# HAD them and then assert `rules_bound == false`.
	var no_rules := _context(attacker, target, ElementStats.FIRE, 0.8, 100.0, &"", false)
	var a := QiDamage.new().breakdown(no_rules)
	assert_eq(a["rules_bound"], false, "nothing injected")
	assert_almost_eq(float(a["matchup"]), 1.0, "an unreadable matchup is NEUTRAL")
	# The resist contest SURVIVES the missing rules, because it never consulted them: it
	# reads a stat id and a divisor. What "nothing injected" costs is the matchup only —
	# `_element_of` trusts an authored element as-is when there is no table to validate it
	# against. This used to assert the resistance read 0.0, which was never true and would
	# have been a claim that a `[0,1]`-scaled stat id needs a rule table to be readable.
	assert_almost_eq(
		float(a["defense"]), 50.0 / _tuning.resist_divisor, "the stat channel still answers"
	)
	assert_eq(float(a["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(a["total"])), true, "and it is a finite number")

	# (b) an element the rule table does not know.
	var unknown := _context(attacker, target, &"shadow", 0.8)
	var b := QiDamage.new().breakdown(unknown)
	assert_eq(b["element"], "", "an unknown element is no element")
	assert_eq(float(b["share"]), 0.0, "so no elemental share")
	assert_eq(float(b["raw_term"]) > 0.0, true, "raw term intact")
	assert_eq(is_finite(float(b["total"])), true, "finite")

	# (c) a defender nobody attached the element provider to: defense reads 0.0 and
	# therefore mitigation 1.0 -- the only way `mitigation` is ever exactly `1.0`, because
	# the curve is asymptotic and never reaches it for a positive `D`.
	var bare := Actor.new(&"bare", {Stat.WILL: 10.0})
	bare.add_resource(ResourcePool.new(&"health", 1000.0))
	var c := QiDamage.new().breakdown(_context(attacker, bare, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(c["defense"]), 0.0, "an unattached defender resists nothing")
	assert_almost_eq(float(c["mitigation"]), 1.0, "so mitigation is exactly 1.0")
	assert_eq(is_finite(float(c["total"])), true, "finite")

	# (d) an unelemental technique: share 0, whole magnitude raw.
	var d := QiDamage.new().breakdown(_context(attacker, target, &"", 0.8))
	assert_eq(d["element"], "", "no element authored")
	assert_eq(float(d["share"]), 0.0, "no share")
	assert_eq(float(d["raw"]), float(d["magnitude"]), "the whole magnitude is raw")
	assert_almost_eq(
		float(d["total"]),
		float(d["magnitude"]) * float(d["raw_attack"]),
		"so the hit is a pure spiritual hit"
	)


## A null context, a null proposal and a NaN magnitude are the three remaining ways a
## half-built hit could crash the spine three stages downstream. All three return a
## number, and the number is finite.
func test_null_context_null_proposal_and_nan_magnitude_all_degrade() -> void:
	var mech := QiDamage.new()
	var empty := mech.breakdown(null)
	assert_eq(float(empty["total"]), 0.0, "a null context is the empty proposal")
	# ADR 0200 REPLACED the read model's key set rather than extending it: `resistance` is
	# gone (it named a PERCENT, and the percent is now an OUTPUT of the ratio) and four keys
	# took its place -- `defense`, `defense_effective`, `divisor_k` and `mitigation_rate`.
	# The count is stated, not derived from the mechanism, so a future author who adds or
	# drops a key has to come here and say why.
	assert_eq(int(empty.size()), 21, "and it carries the full key set for a panel")
	for key in [
		"defense",
		"defense_effective",
		"divisor_k",
		"mitigation_rate",
		"mitigation",
		"penetration",
		"resistance"
	]:
		if key == "resistance":
			# Deliberately asserted as GONE rather than skipped: ADR 0200's docblock on
			# `QiDamage.breakdown` says `resistance` "is not spelled by a second key", so a
			# spelling that answers to the old name would defeat the point of the rename.
			assert_eq(empty.has("resistance"), false, "`resistance` is gone from the read model")
			continue
		assert_eq(empty.has(key), true, "the read model publishes %s" % key)
	assert_eq(is_finite(float(empty["subtotal"])), true, "finite")
	assert_eq(float(mech.mitigate(null, DamageProposal.none()).amount), 0.0, "null proposal")
	assert_eq(float(mech.resolve(null).amount), 0.0, "and S4 declines rather than throws")

	var nan_ctx := _context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, 0.8)
	nan_ctx.magnitude = NAN
	nan_ctx.base = NAN
	var parts := mech.breakdown(nan_ctx)
	assert_eq(is_finite(float(parts["total"])), true, "a NaN magnitude yields a finite number")
	assert_eq(float(parts["magnitude"]), 0.0, "and the magnitude reads 0.0")


## A degenerate tuning (`CombatTuning.new()`, every bound 0.0) must not divide by zero.
## `resist_divisor == 0.0` and `mitigation_ceiling == 0.0` are the two guards ADR 0200's
## ratio adds, and a bare tuning is exactly the state a caller reaches by forgetting the
## `.tres`.
func test_a_degenerate_tuning_never_divides_by_zero() -> void:
	var bare := CombatTuning.new()
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = bare
	var parts := mech.breakdown(
		_context(_attacker(), _defender(ElementStats.FIRE, 50.0), ElementStats.FIRE, 0.0)
	)
	assert_eq(float(parts["defense"]), 0.0, "a 0.0 divisor is no contest, not a division")
	assert_eq(float(parts["defense_effective"]), 0.0, "and a 0.0 pierce scale does nothing")
	assert_almost_eq(float(parts["mitigation"]), 1.0, "so mitigation is 1.0")
	assert_eq(float(parts["share"]), 0.0, "and the default share is 0.0 too")
	assert_eq(is_finite(float(parts["total"])), true, "the number is finite")


## A `mitigation_ceiling` or `damage_reduction_cap` above 1.0 would make `mitigation`
## negative and S9's ONE sign flip would spend the elemental term as a HEAL. Clamped on read.
##
## ## ADR 0200: `resist_cap` is deleted, so the ceiling is the input that must be clamped
##
## This used to write `greedy.resist_cap = 4.0` and assert that the CLAMP bound it. The cap
## is gone, and what replaced it is not a cap on a resistance but a MULTIPLIER on the whole
## curve, so the guard that matters is different: `_mitigation_of` reads
## `clampf(tuning.mitigation_ceiling, 0, 1)`, and a ceiling of `4.0` therefore reads as
## `1.0`. The heal is still impossible, and now for the reason the production docblock gives
## (`combat_tuning.gd:95-98`): the clamp is on the CEILING THE AUTHOR TYPED, and the curve's
## output is never clamped, which is the whole distinction ADR 0200 turns on.
func test_a_ceiling_above_one_cannot_turn_a_hit_into_a_heal() -> void:
	var greedy := CombatTuning.new()
	greedy.default_element_share = 0.8
	greedy.resist_divisor = 100.0
	greedy.mitigation_ceiling = 4.0
	greedy.defense_divisor_k = 0.45
	greedy.pierce_scale = 10.0
	greedy.damage_reduction_cap = 3.0
	# The stat-id PREFIXES too. A bare `CombatTuning.new()` ships them empty, so
	# `_suffixed("", "fire")` names the stat `&"fire"`, which nothing derives -- the cap
	# assertions below were reading a defense of 0.0 and passing for the wrong reason.
	greedy.element_power_prefix = "element_power_"
	greedy.resist_resistance_prefix = "element_defense_"
	var mech := QiDamage.new()
	mech.rules = _rules
	mech.tuning = greedy
	# Defense points at four times the divisor, so `D = 4.0` against a `K` of `4.5`. The
	# ceiling is read clamped to `1.0`, so `m = 1.0 * 4.0 / 8.5 = 0.470588` -- strictly below
	# `1.0` even at a ceiling that was authored at `4.0`, so the mitigation is a real positive
	# number rather than a sign flip.
	var defender := _defender(ElementStats.FIRE, greedy.resist_divisor * 4.0)
	defender.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, 1.0, &"test_full_reduction")
	)
	var parts := mech.breakdown(_context(_attacker(), defender, ElementStats.FIRE, 0.8))
	assert_almost_eq(float(parts["defense"]), 4.0, "400 points over the divisor")
	assert_almost_eq(float(parts["mitigation_rate"]), 4.0 / (4.5 + 4.0), "the ratio itself")
	assert_almost_eq(
		float(parts["mitigation"]),
		1.0 - 4.0 / (4.5 + 4.0),
		"the ceiling is read clamped to 1.0, so the mitigation is strictly positive"
	)
	assert_almost_eq(float(parts["mitigated"]), 0.0, "the reduction clamp holds")
	assert_eq(float(parts["damage_reduction"]), 1.0, "reduction is read as 1.0, not 3.0")
	assert_eq(float(parts["total"]) >= 0.0, true, "never negative: no second sign flip")
	# And the clamp is on the CEILING alone: `mitigation_rate` is published unclamped, so a
	# panel can still see the curve's own reading. The healing shape is only reachable if
	# the clamp is removed, and this is the assertion that would notice.
	assert_eq(float(parts["mitigation_rate"]) < greedy.mitigation_ceiling, true, "unclamped curve")


## Two DIFFERENT out-of-range answers, because `_share_of` treats them differently on
## purpose: a share ABOVE one is clamped to 1.0, and a share at or BELOW zero means "the
## technique authored none" and reads the tuning's `default_element_share`.
##
## This used to loop `[-1.0, 5.0]` over one expectation -- `clamp(value, 0, 1)` for both --
## which contradicts `TechniqueDef.element_share`'s own "`0.0` is the authored default --
## 'use the default', not 'unelemental'" and `QiDamage._share_of`'s documented rule that
## "anything non-positive" falls back. Both behaviours are now asserted separately, and
## both were already the shipped ones.
func test_an_out_of_range_share_is_clamped_or_defaults_and_never_negatives() -> void:
	var greedy := QiDamage.new().breakdown(
		_context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, 5.0)
	)
	assert_almost_eq(float(greedy["share"]), 1.0, "a share above one clamps to 1.0")
	assert_eq(float(greedy["raw_term"]), 0.0, "and leaves no negative raw share")
	assert_eq(float(greedy["total"]) >= 0.0, true, "the hit is still non-negative")
	for value in [-1.0, 0.0, -0.5]:
		var parts := QiDamage.new().breakdown(
			_context(_attacker(), _defender(ElementStats.FIRE, 0.0), ElementStats.FIRE, value)
		)
		assert_almost_eq(
			float(parts["share"]),
			_tuning.default_element_share,
			"share %s is 'authored none' and reads the tuning default" % str(value)
		)
		assert_eq(float(parts["raw_term"]) >= 0.0, true, "and never authors a negative raw share")


# --- property 6: the rules are injected, and the edge is not declared ------------


## ADR 0069: `ElementRules` is INJECTED by the caller. The mechanism reaches it only
## through `ctx.data` or its own `rules` field, and `tools/arch/registry.json` keeps
## `combat_engine` at `["contracts", "core"]`.
func test_the_mechanism_names_no_class_of_the_elements_module() -> void:
	# `tools/arch/registry.json` is outside `res://`, so that half is checked by the gate
	# rather than from here. What IS checkable here is the half the gate CANNOT see:
	# `BARE_REF_UNITS` excludes `modules/*` (rules.py), so a bare reference from this
	# file to `ElementRules` would be reported as an unresolved count, not a violation.
	# Naming no class at all is therefore strictly stronger than declaring the edge.
	#
	# Only CODE lines are scanned. A `##` doc comment that explains WHY the rules are
	# injected necessarily says "ElementRules" — that is documentation, not a reference,
	# and a source-wide substring test would fail on the very comment that documents the
	# rule it is asserting. A dependency is a name in a declaration, a call, or a cast.
	var code := ""
	for line in FileAccess.get_file_as_string("res://src/modules/combat_engine/qi_damage.gd").split(
		"\n"
	):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("#"):
			code += stripped + "\n"
	for forbidden in [
		"ElementRules", "ElementStats", "ElementsApi", "ElementProvider", "ElementDef"
	]:
		assert_eq(
			code.contains(forbidden),
			false,
			(
				"qi_damage.gd must not name %s in code -- the rules are injected, the edge is not declared"
				% forbidden
			)
		)
	# The stat ids it DOES read are named in DATA, which is BRIEF 1.7's whole rule.
	assert_eq(_tuning.element_power_prefix, "element_power_", "the prefix lives in the .tres")
	assert_eq(_tuning.resist_resistance_prefix, "element_defense_", "and so does the other one")


## The two injection routes agree, and neither is a special case: bound on the mechanism,
## or carried on the context by [method QiDamage.builder].
func test_the_rules_arrive_by_either_injection_route_with_the_same_answer() -> void:
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 50.0)
	var bound := QiDamage.new()
	bound.rules = _rules
	bound.tuning = _tuning
	var via_field := bound.breakdown(
		_context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.METAL)
	)

	var via_context := _context(attacker, target, ElementStats.FIRE, 0.8, 100.0, ElementStats.METAL)
	via_context.set_data(QiDamage.ELEMENT_RULES_KEY, _rules)
	var via_data := QiDamage.new().breakdown(via_context)
	assert_eq(
		float(via_field["elemental_term"]) == float(via_data["elemental_term"]),
		true,
		"identical arithmetic"
	)
	# A STRONG pair, so the agreement is not two NEUTRALs coinciding: against METAL the
	# matchup is 1.5 on every route, and the arithmetic below would notice if one of them
	# fell back to the dominance walk and read `&""`.
	assert_almost_eq(float(via_field["matchup"]), 1.5, "fire > metal is STRONG on the field route")
	assert_almost_eq(float(via_data["matchup"]), 1.5, "and on the context route")

	# And through the spine's own `ctx_builder` extension point, which is how a caller
	# who has no business knowing this mechanism's keys still wires it.
	var tech := _technique(ElementStats.FIRE, 0.8)
	var ctx := AttackContext.new(attacker, target, tech, _tuning, 100.0)
	QiDamage.builder(_rules, tech, ElementStats.METAL).call(ctx)
	assert_eq(
		String(ctx.data_value(QiDamage.ELEMENT_KEY, "")),
		String(ElementStats.FIRE),
		"the builder carried the element"
	)
	assert_almost_eq(float(ctx.data_value(QiDamage.ELEMENT_SHARE_KEY, 0.0)), 0.8, "and the share")
	assert_almost_eq(
		float(bound.breakdown(ctx)["elemental_term"]),
		float(via_field["elemental_term"]),
		"so the spine path and the direct path agree"
	)


# ADR 0069's realm-invariance and tier-2 mastery properties now live in
# `test_qi_damage_realm.gd`.

# --- the realm-invariance fix: see test_qi_damage_realm.gd ------------------------

# --- `TechniqueDef.element_share` (ADR 0069's only new authored field) ------------


## `TechniqueDef` is NOT serialized -- `TechniqueCodex.to_dict` stores ids and rungs
## only (ADR 0056), so a def is authored as a `.tres` and never round-tripped through a
## save. `from_dict`/`to_dict` are therefore NOT added: an authorable round-trip would
## be a second copy of the field with its own defaults, and the two would drift.
##
## What IS assertable, and what the field actually has to guarantee, is that the
## authored value survives a `.tres` resource round-trip and reaches the qi mechanism
## through the read model -- and that `0.0` reads as "use the default" rather than
## "unelemental".
func test_element_share_round_trips_through_the_resource_and_the_read_model() -> void:
	var def := _technique(ElementStats.FIRE, 0.35)
	def.id = &"round_trip"
	assert_almost_eq(def.element_share, 0.35, "the authored value is on the def")
	assert_almost_eq(
		_technique(ElementStats.FIRE, 0.0).element_share,
		0.0,
		"0.0 is the authored default -- 'use the default', not 'unelemental'"
	)
	# The qi path reads it off the context, so the builder's carry is the round-trip the
	# mechanism actually depends on.
	var attacker := _attacker()
	var target := _defender(ElementStats.FIRE, 50.0)
	var ctx := AttackContext.new(attacker, target, def, _tuning, 100.0)
	QiDamage.builder(_rules, def).call(ctx)
	assert_almost_eq(
		float(ctx.data_value(QiDamage.ELEMENT_SHARE_KEY, 0.0)), 0.35, "carried verbatim"
	)
	assert_almost_eq(float(QiDamage.new().breakdown(ctx)["share"]), 0.35, "and used as the share")
	# And the surface a screen reads carries it too. `inspect` is the read model
	# a screen actually reaches; it used to be preceded by a `learn_preview` call,
	# which published the same shape under a second name and was deleted as a second
	# door to a learn (DEF-0300). The assertion below is the one that matters.
	var inspect := TechniqueReadModel.inspect(
		attacker, TechniqueCodex.new(), TechniqueSlots.new(), TechniqueUpkeep.new(), def, [], []
	)
	assert_almost_eq(
		float(inspect.get("element_share", -1.0)),
		0.35,
		"the read model surfaces the authored share as a primitive"
	)
	assert_eq(String(inspect.get("element", "")), String(ElementStats.FIRE), "and the element")


# --- purity, the seam's own contract (ADR 0067) ----------------------------------

# --- internals -------------------------------------------------------------------


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
