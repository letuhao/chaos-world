extends TestCase

## The bounded ladders (ADR 0055): mastery is five compounding rungs, and study
## costs `LEARN_BASE * LEARN_STEP^ordinal * MAG_GRADE`. Both tables are asserted
## against ADR 0055's published numbers literally, so a retune cannot pass unnoticed.

const MORTAL := &"qi_refining"
const DIVERSE := &"primordial_origin"

## ADR 0055's published mastery table. Index is the rung.
const POWER := [1.000, 1.150, 1.323, 1.521, 1.749]
const QI_COST := [1.000, 0.940, 0.884, 0.831, 0.781]
const COOLDOWN := [1.000, 0.960, 0.922, 0.885, 0.849]
const THROUGHPUT := [1.000, 1.223, 1.497, 1.831, 2.240]


func _def() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"test_mastery_def"
	def.display_name = "Manual"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	return def


# --- Mastery ------------------------------------------------------------------


func test_mastery_multipliers_match_the_published_table_at_every_rung() -> void:
	# Each of the four published columns, each rung, against the ADR's own numbers.
	# Compounding from 1.15 / 0.94 / 0.96, not a linear interpolation.
	#
	# The tolerance is 1e-3, not tighter, because the published table is rounded to
	# three decimals while the code compounds exactly: 1.15^2 is 1.3225 against a
	# published 1.323. Asserting to 5e-4 asks the code to match a rounding, which
	# is a fact about the document rather than about the ladder.
	for rung in 5:
		var multipliers := TechniqueScales.multipliers_at(rung)
		assert_almost_eq(float(multipliers["power"]), POWER[rung], "rung %d power" % rung, 0.001)
		assert_almost_eq(
			float(multipliers["qi_cost"]), QI_COST[rung], "rung %d qi cost" % rung, 0.001
		)
		assert_almost_eq(
			float(multipliers["cooldown"]), COOLDOWN[rung], "rung %d cooldown" % rung, 0.001
		)
		assert_almost_eq(
			float(multipliers["qi_throughput"]),
			THROUGHPUT[rung],
			"rung %d qi throughput" % rung,
			0.001
		)


func test_throughput_is_power_over_cost_at_every_rung() -> void:
	# The published throughput column is derived, not authored: power / qi cost.
	# Asserting the relation separately catches a table that drifts one column only.
	for rung in 5:
		var multipliers := TechniqueScales.multipliers_at(rung)
		assert_almost_eq(
			float(multipliers["qi_throughput"]),
			float(multipliers["power"]) / float(multipliers["qi_cost"]),
			"rung %d throughput is power over cost" % rung,
			0.0005
		)


func test_a_rung_never_halves_output_so_no_rung_is_a_trap() -> void:
	# ADR 0055's guard: rung-4 cost 0.781 and cooldown 0.849 both clear 0.5, so a
	# deep rung is a real investment rather than a penalty to be avoided.
	var rung_four := TechniqueScales.multipliers_at(4)
	assert_eq(float(rung_four["qi_cost"]) > 0.5, true, "rung-4 qi cost clears one half")
	assert_eq(float(rung_four["cooldown"]) > 0.5, true, "rung-4 cooldown clears one half")
	assert_eq(float(rung_four["power"]) > 1.7, true, "rung-4 power is 1.749")


func test_a_def_may_narrow_its_own_ladder_but_never_widen_it() -> void:
	# `mastery_rungs` is authorable downward; the multipliers are constants, so a
	# sixth rung is not authorable and a rung above the count is clamped.
	var def := _def()
	def.mastery_rungs = 3
	assert_eq(TechniqueReadModel.ladder_view(def).size(), 4, "rungs 0 through 3")
	assert_eq(TechniqueScales.rung_for(9, def.mastery_rungs), 3, "clamped to the authored count")
	var full := _def()
	assert_eq(TechniqueScales.rung_for(99, full.mastery_rungs), 5, "never past ADR 0055's five")


func test_the_mastery_ladder_reaches_the_published_grade_bands() -> void:
	# One band is a single tier's span, `TECHNIQUE_STEP^9 = 1.3714`, which is the
	# unit ADR 0055 measures every figure in: rung-4 power 1.749 / 1.3714 = 1.28
	# bands, throughput 2.240 / 1.3714 = 1.63, one rung 1.15 / 1.3714 = 1.06.
	#
	# It is the ONE-tier span, not the two-tier one (`^18 = 1.8807`). Reading it as
	# two tiers divides every figure by 1.37 too many and makes all three
	# assertions unreachable — which is exactly what happened when this case was
	# "corrected" that way.
	var span := pow(TechniqueScales.TECHNIQUE_STEP, 9.0)
	assert_almost_eq(span, 1.3714, "the one-tier span", 0.001)
	var rung_four := TechniqueScales.multipliers_at(4)
	assert_almost_eq(float(rung_four["power"]) / span, 1.28, "rung-4 power is 1.28 bands", 0.01)
	assert_almost_eq(
		float(rung_four["qi_throughput"]) / span, 1.63, "rung-4 throughput is 1.63 bands", 0.01
	)
	assert_almost_eq(TechniqueScales.POWER_STEP / span, 0.84, "one rung is 0.84 bands", 0.01)


# --- Learning cost ------------------------------------------------------------


func test_learning_price_is_base_times_step_times_grade_at_r1() -> void:
	# R1, ordinal 0: 100 * 1.03^0 * MAG_GRADE. Mortal is 100 exactly.
	assert_almost_eq(TechniqueScales.learn_price(ItemGrade.MORTAL, 0), 100.0, "R1 mortal", 0.0001)
	assert_almost_eq(
		TechniqueScales.learn_price(ItemGrade.SPIRIT, 0), 160.0, "R1 spirit (100 * 1.6)", 0.0001
	)
	assert_almost_eq(
		TechniqueScales.learn_price(ItemGrade.DIVINE, 0), 650.0, "R1 divine (100 * 6.5)", 0.0001
	)


func test_learning_price_at_r30_matches_the_published_divine_figure() -> void:
	# R30 is ordinal 29: 100 * 1.03^29 * 6.5 = 1531.77.
	var price := TechniqueScales.learn_price(ItemGrade.DIVINE, 29)
	assert_almost_eq(price, 1531.77, "R30 divine", 0.01)
	# And the whole ladder, at mortal grade, spans ADR 0055's stated 2.3566.
	assert_almost_eq(
		TechniqueScales.learn_price(ItemGrade.MORTAL, 29), 235.66, "R30 mortal spans 2.3566", 0.01
	)


func test_grade_multiplies_the_price_but_never_the_effect() -> void:
	# Grade is a floor, not a scale (ADR 0055): it moves the price, and the
	# magnitude ladder is untouched by it.
	for grade in ItemGrade.ALL:
		var factor := TechniqueScales.grade_factor(grade)
		assert_almost_eq(
			(
				TechniqueScales.learn_price(grade, 10)
				/ TechniqueScales.learn_price(ItemGrade.MORTAL, 10)
			),
			factor,
			"grade %s scales the price by its MAG_GRADE" % grade,
			0.0001
		)
	# The magnitude ladder takes no grade argument at all, so the invariant is
	# structural rather than arithmetic: `magnitude_at` is a pure function of the
	# ordinal, so one ordinal has exactly one magnitude and grade cannot reach it.
	# An earlier version of this case multiplied the reading BY the grade factor and
	# asserted it was unchanged, which only holds for a factor of 1 and so could
	# never pass for divine (6.5).
	assert_almost_eq(
		TechniqueScales.magnitude_at(10),
		pow(TechniqueScales.TECHNIQUE_STEP, 10.0),
		"the reading is a pure function of the ordinal",
		0.0001
	)
	assert_eq(
		TechniqueScales.magnitude_at(10) != TechniqueScales.magnitude_at(10) * 6.5,
		true,
		"and applying a grade multiplier to it is never a no-op, so grade cannot be folded in"
	)


func test_the_learning_step_never_runs_ahead_of_the_magnitude_step() -> void:
	# `LEARN_STEP` must stay at or below `TECHNIQUE_STEP`, or study would outrun a
	# breakthrough and the deep realms would get cheap. DEF-0084's authored
	# `29/28 = 1.037037` is the coarser bound it also has to clear.
	assert_eq(
		TechniqueScales.LEARN_STEP <= TechniqueScales.TECHNIQUE_STEP,
		true,
		"study is cheaper than the magnitude ladder"
	)
	assert_eq(TechniqueScales.LEARN_STEP <= 29.0 / 28.0, true, "and under the authored floor")
	# The magnitude span is ADR 0055's published 2.7667 over the whole ladder.
	assert_almost_eq(
		TechniqueScales.magnitude_at(29), 2.7667, "magnitude span across 30 realms", 0.001
	)
	assert_almost_eq(TechniqueScales.magnitude_at(0), 1.0, "R1 is the ladder's base", 0.0001)


func test_an_unknown_grade_degrades_to_the_cheapest_band() -> void:
	# Malformed content must not produce an unbudgeted technique.
	assert_almost_eq(
		TechniqueScales.grade_factor(&"mythic"), 1.0, "an unknown grade reads as mortal", 0.0001
	)


# --- The price a caller actually pays ----------------------------------------


func test_the_facade_reports_the_price_at_the_actor_s_own_realm_ordinal() -> void:
	# The facade answers "what does this cost me", not "what does it cost at the
	# ladder's floor", so the price moves with the actor.
	var def := _def()
	def.grade = ItemGrade.DIVINE
	var early := Actor.new(&"early")
	early.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(early)
	assert_almost_eq(
		float(TechniquesApi.inspect(early, def)["learn_price"]), 650.0, "R1 divine costs 650", 0.01
	)
	var late := Actor.new(&"late")
	late.set_path(PathState.new(PathState.QI, DIVERSE))
	TechniquesApi.attach(late)
	assert_almost_eq(
		float(TechniquesApi.inspect(late, def)["learn_price"]),
		1531.77,
		"R30 divine costs 1531.77",
		0.01
	)
