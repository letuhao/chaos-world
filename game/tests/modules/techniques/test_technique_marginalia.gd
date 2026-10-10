extends TestCase

## ADR 0196: a technique MANUAL is fixed text with a variable margin. What the
## sheet inscribes — which two body changes, and at what value — does not move;
## what varies between copies is the annotation a copy picked up in passing. That
## annotation is the roll, and it lands on exactly one thing.
##
## These cases are mostly about the four REFUSALS, because a roll that quietly
## widened is a balance defect rather than a feature:
##
## - **`magnitude` may not roll.** It is the coefficient ADR 0055's authored
##   ladder multiplies, and `CombatSpine.base_damage` reads it off the SHARED
##   catalog resource — so a rolled magnitude could only reach the spine as a
##   per-actor copy of the def, and `technique_casting.gd` already refuses that in
##   writing (the spine is called directly by `app/` and by other modules for hits
##   that never pass through this module).
## - **`qi_cost` and `cooldown` may not roll.** They are exactly the two
##   quantities ADR 0055 publishes rung multipliers on (`0.94^n`, `0.96^n`), so a
##   band there is a second multiplier on a value the mastery ladder already
##   scales.
## - **A pool CAPACITY may not roll.** ADR 0160 refuses a rung scaling one because
##   `RealmScaling` already MULTs `MAX_QI`/`MAX_STAMINA` by the realm's own
##   1.0x-551.46x power and the authored dantian capacity re-seals the pool on top.
## - **The option's OWN `bounds` are respected**, after which the authored band
##   `TechniqueMarginalia` declares is the only other limit.
##
## And on the two things a roll is FOR: a second copy of one manual carries
## different numbers, and the SAME copy carries the same numbers through every
## rebuild and every save/load — because a re-derivation on load is exactly how a
## learned investment quietly changes under a player who did nothing.

# --- The fixtures live in `technique_marginalia_fixture.gd` -------------------
# Every helper and constant below reads `TechniqueMarginaliaFixture.<name>`; this
# suite keeps only the claims.


func test_two_copies_of_the_same_manual_roll_differently_and_contribute_what_they_said() -> void:
	var first_hero := TechniqueMarginaliaFixture.hero()
	var second_hero := TechniqueMarginaliaFixture.hero()
	var first_def := TechniqueMarginaliaFixture.manual()
	var second_def := TechniqueMarginaliaFixture.manual()
	second_def.id = StringName("%s_second" % first_def.id)
	TechniqueCatalog.instance().register(second_def)

	var first := TechniqueMarginaliaFixture.study(first_hero, first_def, 11)
	var second := TechniqueMarginaliaFixture.study(second_hero, second_def, 97)
	assert_eq(bool(first.get("ok")), true, "the first copy was studied")
	assert_eq(bool(second.get("ok")), true, "the second copy was studied")

	# The load-bearing pair: two copies of ONE manual, inscribing the same two
	# options, and the annotations differ. Without this the roll is decorative and
	# every other case in this file passes on authored values alone.
	var first_margin: Dictionary = first.get("margin", {})
	var second_margin: Dictionary = second.get("margin", {})
	assert_eq(
		first_margin.has(String(TechniqueMarginaliaFixture.STAT_OPTION)),
		true,
		"the first copy annotates the stat"
	)
	assert_eq(
		second_margin.has(String(TechniqueMarginaliaFixture.STAT_OPTION)),
		true,
		"the second copy annotates it too"
	)
	assert_ne(
		float(first_margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		float(second_margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		"two copies of one manual carry different numbers"
	)

	# And each contributes EXACTLY what its own margin says — not the sheet, and
	# not the other's.
	TechniquesApi.equip(first_hero, first_def)
	TechniquesApi.equip(second_hero, second_def)
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(first_hero),
		float(first_margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		"first copy",
		0.0001
	)
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(second_hero),
		float(second_margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		"second copy",
		0.0001
	)
	# Not the sheet: at least one of the two landed off the authored figure, so a
	# suite that quietly fell back to authored values could not pass this file.
	assert_ne(
		float(first_margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		TechniqueMarginaliaFixture.STAT_VALUE,
		"the first copy is off the sheet"
	)


func test_the_band_is_both_sided_so_a_copy_is_on_average_the_sheet() -> void:
	# A one-sided band would make every copy strictly better than the printing, and
	# the authored figure would be a number no player ever actually gets. Measured
	# over 200 seeds: values land on BOTH sides of the authored value, and the
	# worst of them is the floor, not the ceiling.
	var def := TechniqueMarginaliaFixture.manual()
	var below := 0
	var above := 0
	var lowest := TechniqueMarginaliaFixture.STAT_VALUE
	var highest := TechniqueMarginaliaFixture.STAT_VALUE
	for seed_value in 200:
		var drawn := TechniqueMarginalia.draw(def, TechniqueMarginaliaFixture.rng(seed_value))
		for effect in drawn:
			if (
				String(effect.get("option_id", ""))
				!= String(TechniqueMarginaliaFixture.STAT_OPTION)
			):
				continue
			var value := float(effect.get("value", 0.0))
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
			if value < TechniqueMarginaliaFixture.STAT_VALUE:
				below += 1
			elif value > TechniqueMarginaliaFixture.STAT_VALUE:
				above += 1
	assert_eq(below > 0, true, "some copies run below the sheet (%d of 400)" % below)
	assert_eq(above > 0, true, "some copies run above it (%d of 400)" % above)
	# ## The band is CONTAINMENT, not attainment
	#
	# `randf()` returns `[0.0, 1.0)`, so `lerpf(band.x, band.y, randf())` reaches
	# exactly `band.x` only on an exact `0.0` draw and exactly
	# `band.y` never. Over 200 seeds the realized extremes are therefore strictly
	# INSIDE the band — measured, the observed floor was `6.0 * 0.756667 = 4.54`
	# against a declared floor of `4.5`, and the observed ceiling likewise sat under
	# `7.5`. This case previously asserted `lowest == floor` and `highest == ceiling`,
	# which is a statement about the RANDOM NUMBER GENERATOR's luck rather than about
	# the band, and it failed on a correct roll.
	#
	# What the band actually promises is that a copy never escapes it, so that is
	# what is asserted. The tolerance is one full percent of the authored value —
	# a generous allowance for where 200 draws happen to stop — because the claim
	# is "inside the band", and asserting equality to the EDGE is a claim about
	# the generator's luck that no implementation can honour.
	var slack := TechniqueMarginaliaFixture.STAT_VALUE * 0.01
	# The declared window for the rarity these copies carry. Read through the one
	# published reader rather than two constants, so the assertion and the drawer
	# cannot disagree about how wide the band is.
	var band := TechniqueMarginalia.band_for(ItemRarity.LEGENDARY)
	assert_eq(
		lowest >= TechniqueMarginaliaFixture.STAT_VALUE * band.x,
		true,
		"the worst of 200 copies is at or above the declared floor"
	)
	assert_eq(
		highest <= TechniqueMarginaliaFixture.STAT_VALUE * band.y,
		true,
		"the best of 200 copies is at or below the declared ceiling"
	)
	# And the extremes land NEAR their edges rather than anywhere inside the band,
	# which is what distinguishes "sampled from this band" from "a much wider band
	# that happens to have drawn twice in the middle".
	assert_eq(
		absf(lowest - TechniqueMarginaliaFixture.STAT_VALUE * band.x) < slack,
		true,
		"the worst of 200 copies is near the declared floor"
	)
	assert_eq(
		absf(highest - TechniqueMarginaliaFixture.STAT_VALUE * band.y) < slack,
		true,
		"the best of 200 copies is near the declared ceiling"
	)
	# And it is a real band, not a rounding artefact: over 200 seeds the copies
	# actually SPREAD. Without this the two assertions above would also pass if the
	# drawer returned the authored value every time.
	assert_eq(
		highest - lowest > TechniqueMarginaliaFixture.STAT_VALUE * 0.2,
		true,
		"the copies spread (%.4f .. %.4f)" % [lowest, highest]
	)


# --- Rarity decides how wide the band is ---------------------------------------


## ADR 0204: the band's width is `ItemRarity.magnitude_budget`, adopted from what
## was dead code (one declaration, zero callers). The band is no longer a constant,
## so both ends are pinned by RARITY rather than by number.
func test_rarity_decides_the_band_and_a_common_copy_carries_no_variance() -> void:
	var common := TechniqueMarginaliaFixture.manual()
	common.rarity = ItemRarity.COMMON
	var legendary := TechniqueMarginaliaFixture.manual()

	# The published edges, per rarity.
	var c := TechniqueMarginalia.band_for(ItemRarity.COMMON)
	var l := TechniqueMarginalia.band_for(ItemRarity.LEGENDARY)
	assert_almost_eq(c.x, 1.0, "a common copy starts at the authored figure", 0.0001)
	assert_almost_eq(c.y, 1.0, "and cannot rise above it", 0.0001)
	assert_almost_eq(l.x, 0.75, "a legendary copy may sit 25% under it", 0.0001)
	assert_almost_eq(l.y, 1.25, "and 25% over", 0.0001)
	# Rarity is the ONLY thing that moves the width: the ladder is ordered, so a
	# rarer book is never the narrower one.
	assert_eq(l.y - l.x > c.y - c.x, true, "rarity widens, never narrows")

	# And the drawer agrees with the published edges — a common copy over 200 seeds
	# is the authored figure every time, which is a real statement and not a band
	# that failed to draw.
	#
	# AGGREGATED, not 200 separate assertions. One assertion per draw means a band
	# that is wrong trips `framework.gd`'s `MAX_FAILURES = 200` backstop on the
	# exact iteration that proves the bug, which kills the process and loses the
	# report: the mutation is caught, but as a crash instead of a failure. The
	# extremes are the claim; every draw landing on the sheet is what the band being
	# zero-width actually means.
	var common_values: Array[float] = []
	for seed_value in 200:
		for effect in TechniqueMarginalia.draw(common, TechniqueMarginaliaFixture.rng(seed_value)):
			if StringName(effect.get("option_id", &"")) == TechniqueMarginaliaFixture.STAT_OPTION:
				common_values.append(float(effect.get("value", 0.0)))
	assert_eq(common_values.size() > 0, true, "the common copy still annotates its option")
	var worst := 0.0
	for value in common_values:
		worst = maxf(worst, absf(value - TechniqueMarginaliaFixture.STAT_VALUE))
	assert_almost_eq(worst, 0.0, "every common copy reads exactly the sheet", 0.01)


## The magnitude_budget this adopted is one number the tree now READS. It was dead
## for the life of the item program, and a guard that only ever counted references
## would not have noticed that adopting it was optional — so this pins the
## adoption, which is what stops it drifting back to dead.
func test_the_rarity_budget_is_read_rather_than_dead() -> void:
	var def := TechniqueMarginaliaFixture.manual()
	var band := TechniqueMarginalia.band_for(def.rarity)
	assert_eq(
		band != Vector2(1.0, 1.0), true, "a legendary def gets a real band, so the budget is read"
	)
	# Every rarity resolves, and none is inverted or out of range.
	for rarity in ItemRarity.ALL:
		var b := TechniqueMarginalia.band_for(rarity)
		assert_eq(b.x > 0.0, true, "%s has a positive lower edge" % rarity)
		assert_eq(b.x <= 1.0, true, "%s does not band below the sheet" % rarity)
		assert_eq(b.y >= 1.0, true, "%s does not band above the sheet" % rarity)
		assert_eq(b.x <= b.y, true, "%s is ordered" % rarity)


# --- A roll never moves an authored ladder -------------------------------------


func test_a_roll_never_moves_the_magnitude_ladder_or_its_own_coefficient() -> void:
	# `technique_power check` walks `technique_magnitude_table.tres`; `magnitude` is
	# the coefficient that table multiplies, and `CombatSpine.base_damage` reads it
	# off the SHARED catalog resource. A rolled magnitude could only reach the
	# spine as a per-actor copy of the def, so it is refused — and refused here at
	# the source, not by a caller remembering to skip it.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var authored_magnitude := def.magnitude
	# Read off a REALM rather than off the actor, so the assertion cannot be
	# satisfied by an actor whose `realm()` is empty and therefore neutral.
	#
	# The realm is `&"core_formation"`, NOT the fixture's own `MORTAL`. R1
	# (`qi_refining`) is authored at exactly 1.0000000 — the ladder is DELIBERATELY
	# neutral at its base (ADR 0055 anchors it there, and `technique_power check`
	# walks exactly that), so asserting `factor(MORTAL) != 1.0` was asserting that
	# the shipped data is wrong. The point of this case is "the factor is a real,
	# non-neutral number the roll could have moved", and R3 is where that is true.
	var ladder_realm := &"core_formation"
	var before := TechniqueMagnitudeTable.factor(ladder_realm)
	assert_ne(before, 1.0, "the R3 rung of the ladder is not neutral")
	var authored_r3 := TechniqueMagnitudeTable.factor(TechniqueMarginaliaFixture.MORTAL)
	assert_almost_eq(
		authored_r3, 1.0, "and the suite still documents that R1 is the neutral base", 0.0001
	)
	var learned := TechniqueMarginaliaFixture.study(hero, def, 7)
	assert_eq(bool(learned.get("ok")), true, "studied")
	assert_almost_eq(def.magnitude, authored_magnitude, "the def's magnitude is untouched", 0.0001)
	assert_almost_eq(
		TechniqueMagnitudeTable.factor(ladder_realm),
		before,
		"the ladder factor is untouched",
		0.0000001
	)
	# The catalog still hands out the one shared resource, with the one number.
	var reread := TechniqueCatalog.instance().definition(def.id)
	assert_almost_eq(reread.magnitude, authored_magnitude, "nor is the catalog's copy", 0.0001)


func test_a_roll_never_moves_the_cost_block_mastery_already_multiplies() -> void:
	# ADR 0055 publishes exactly two rung multipliers that touch an activation:
	# `qi_cost` 0.94^n and `cooldown` 0.96^n. A band on either is a second
	# multiplier on the same value — the shape ADR 0160 refuses for a capacity by
	# name — so `qi_cost`, `stamina_cost` and `cooldown` are all authored.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	def.qi_cost = 54.0
	def.stamina_cost = 16.0
	def.cooldown = 14.0
	var qi := def.qi_cost
	var stamina := def.stamina_cost
	var cooldown := def.cooldown
	assert_eq(bool(TechniqueMarginaliaFixture.study(hero, def, 3).get("ok")), true, "studied")
	assert_almost_eq(def.qi_cost, qi, "qi cost is authored", 0.0001)
	assert_almost_eq(def.stamina_cost, stamina, "stamina cost is authored", 0.0001)
	assert_almost_eq(def.cooldown, cooldown, "cooldown is authored", 0.0001)


func test_a_capacity_option_is_carried_at_its_authored_value_and_never_banded() -> void:
	# The ADR 0160 refusal, from the other direction. `RealmScaling` already MULTs
	# MAX_QI and MAX_STAMINA by the realm's own 1.0x-551.46x power, and the
	# authored dantian capacity re-seals the qi pool on top — so a band here is the
	# least-authored of three multipliers on one number.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var learned := TechniqueMarginaliaFixture.study(hero, def, 23)
	var margin: Dictionary = learned.get("margin", {})
	assert_eq(
		margin.has(String(TechniqueMarginaliaFixture.CAPACITY_OPTION)),
		true,
		"the capacity option is reported"
	)
	assert_almost_eq(
		float(margin[String(TechniqueMarginaliaFixture.CAPACITY_OPTION)]),
		TechniqueMarginaliaFixture.CAPACITY_VALUE,
		"and it carries exactly what the sheet inscribes",
		0.0001
	)
	# Measured across the whole band: a capacity annotation is never once different
	# from the sheet, so the refusal is structural rather than statistical.
	for seed_value in 200:
		for effect in TechniqueMarginalia.draw(def, TechniqueMarginaliaFixture.rng(seed_value)):
			if (
				String(effect.get("option_id", ""))
				!= String(TechniqueMarginaliaFixture.CAPACITY_OPTION)
			):
				continue
			assert_almost_eq(
				float(effect.get("value", 0.0)),
				TechniqueMarginaliaFixture.CAPACITY_VALUE,
				"seed %d" % seed_value,
				0.0001
			)


func test_the_capacity_predicate_agrees_with_the_one_rung_scaling_uses() -> void:
	# Two refusals on the same quantity from opposite directions, and they are
	# written twice — so a tie, not a second truth. Walked over the whole shipped
	# `cult_*` pool rather than over a fixture, because a name list is out of date
	# the moment someone adds a pool.
	var catalog := OptionCatalog.instance()
	var checked := 0
	for option_id in catalog.active_option_ids():
		if not String(option_id).begins_with("cult_"):
			continue
		var record := catalog.option_record(option_id)
		var target: Dictionary = record.get("target", {})
		var target_id := String(target.get("id", ""))
		checked += 1
		# `CodexEntry`'s own predicate is private and stays private: the tie is
		# asserted through what it DOES. A rung-scaled capacity is the refusal, so
		# an entry at rung 4 whose option is a capacity must read back the AUTHORED
		# value while a stat option reads back 1.749x it. Both refusals therefore
		# agree about every option in the shipped pool, or this walks off it.
		var def := TechniqueMarginaliaFixture.manual()
		def.passive_options = [{"option_id": option_id, "value": 4.0}]
		var drawn := TechniqueMarginalia.draw(def, TechniqueMarginaliaFixture.rng(5))
		var value := 4.0
		for effect in drawn:
			if String(effect.get("option_id", "")) == String(option_id):
				value = float(effect.get("value", 0.0))
		var entry := CodexEntry.new(def.id, drawn, TechniqueScales.MAX_RUNGS)
		var at_rung_four := -1.0
		for scaled in entry.effects_for(def):
			if String(scaled.get("option_id", "")) == String(option_id):
				at_rung_four = float(scaled.get("value", 0.0))
		if TechniqueMarginalia.is_capacity_effect(target_id):
			assert_almost_eq(value, 4.0, "'%s' is not banded" % option_id, 0.0001)
			assert_almost_eq(at_rung_four, 4.0, "'%s' is not scaled" % option_id, 0.0001)
		else:
			assert_eq(
				value == 4.0 and at_rung_four == 4.0,
				false,
				"'%s' is classified the same way by both refusals" % option_id
			)
	assert_eq(checked >= 27, true, "the shipped cult_ pool is wide (%d checked)" % checked)


# --- The option's own bounds ----------------------------------------------------


## ## Why this case exists twice, and why the second one is the load-bearing one
##
## The case above walks the SHIPPED bounds, and every shipped `cult_*` option
## declares `{0.0, 9999.0}` — a sanity ceiling far outside a 0.75x-1.25x band. So
## `OptionCatalog.clamp_to_bounds` is a no-op on every one of them, and asserting
## against them proves only that the band is narrow. Deleting the clamp entirely
## left this file GREEN (verified: `make_effect(record, rolled, &"rolled")` with no
## clamp still reported 362 passed / 0 failed), which is exactly the "a green suite
## you have not seen go red is not evidence" shape.
##
## So the clamp is asserted against bounds that ACTUALLY BITE: a synthetic record
## whose ceiling sits inside the band. That is the only way to distinguish "the
## catalog's window is applied after the band" from "the band happens to be
## narrower than every window in the corpus" — and it is the claim the ADR makes.
func test_the_catalogs_own_bounds_clamp_the_band_when_they_are_tighter_than_it() -> void:
	var real_record := OptionCatalog.instance().option_record(
		TechniqueMarginaliaFixture.STAT_OPTION
	)
	assert_ne(real_record.is_empty(), true, "the option exists so a record can be cloned from it")
	# A ceiling INSIDE the band: `STAT_VALUE * 0.90 = 5.4`, reached by any copy whose
	# span exceeds 0.90. `clamp_to_bounds` is static and takes the record as an
	# argument, so this needs no seam into production and cannot narrow the shipped
	# record — the clone is local to this case.
	var ceiling := TechniqueMarginaliaFixture.STAT_VALUE * 0.90
	var tight := real_record.duplicate(true)
	tight["bounds"] = {"min": 0.0, "max": ceiling}
	# What the drawer produces at a given span, reproduced from the two constants it
	# declares rather than re-deriving the band independently.
	var fired := 0
	for seed_value in 200:
		var band := TechniqueMarginalia.band_for(ItemRarity.LEGENDARY)
		var span := lerpf(band.x, band.y, TechniqueMarginaliaFixture.randf_from(seed_value))
		var rolled := snappedf(TechniqueMarginaliaFixture.STAT_VALUE * span, 0.01)
		var clamped := OptionCatalog.clamp_to_bounds(tight, rolled)
		assert_eq(
			clamped <= ceiling + 0.0001,
			true,
			(
				"seed %d: %.4f is held under the option's own ceiling of %.2f"
				% [seed_value, clamped, ceiling]
			)
		)
		if is_equal_approx(clamped, ceiling) and not is_equal_approx(rolled, ceiling):
			fired += 1
	assert_eq(
		fired > 0,
		true,
		(
			"and the clamp actually fired on some copy (%d of 200) — a vacuous pass is not a pass"
			% fired
		)
	)
	# The floor, from the other side, so neither edge of the window is assumed: a
	# record whose floor sits INSIDE the band must hold every copy up to it.
	var floor := TechniqueMarginaliaFixture.STAT_VALUE * 1.10
	var floored := real_record.duplicate(true)
	floored["bounds"] = {"min": floor, "max": 9999.0}
	var lifted := 0
	for seed_value in 200:
		var band := TechniqueMarginalia.band_for(ItemRarity.LEGENDARY)
		var span := lerpf(band.x, band.y, TechniqueMarginaliaFixture.randf_from(seed_value))
		var rolled := snappedf(TechniqueMarginaliaFixture.STAT_VALUE * span, 0.01)
		var clamped := OptionCatalog.clamp_to_bounds(floored, rolled)
		assert_eq(
			clamped >= floor - 0.0001,
			true,
			(
				"seed %d: %.4f is held over the option's own floor of %.2f"
				% [seed_value, clamped, floor]
			)
		)
		if is_equal_approx(clamped, floor) and not is_equal_approx(rolled, floor):
			lifted += 1
	assert_eq(lifted > 0, true, "and the floor clamp fired too (%d of 200)" % lifted)


func test_a_rolled_value_stays_inside_the_options_own_bounds_at_the_extremes() -> void:
	# `OptionCatalog.clamp_to_bounds` is applied AFTER the band, so the catalog's
	# window is the last word. The shipped `cult_*` bounds are `{0.0, 9999.0}` — a
	# sanity ceiling rather than a balance window — which is precisely why the band
	# is authored in `TechniqueMarginalia` and cannot be delegated to the catalog.
	var catalog := OptionCatalog.instance()
	var record := catalog.option_record(TechniqueMarginaliaFixture.STAT_OPTION)
	var bounds: Dictionary = record.get("bounds", {})
	var low := float(bounds.get("min", 0.0))
	var high := float(bounds.get("max", 0.0))
	assert_eq(low >= 0.0, true, "the option declares a floor")
	assert_eq(high > 0.0, true, "the option declares a ceiling")
	# Measured at both extremes of the band, on the authored values actually
	# shipped across the corpus rather than on one fixture.
	var band := TechniqueMarginalia.band_for(ItemRarity.LEGENDARY)
	for seed_value in [1, 2, 3, 7, 11, 97, 2147483646]:
		for authored in TechniqueMarginaliaFixture.shipped_option_values(
			TechniqueMarginaliaFixture.STAT_OPTION
		):
			var def := TechniqueMarginaliaFixture.manual()
			def.passive_options = [
				{"option_id": TechniqueMarginaliaFixture.STAT_OPTION, "value": authored}
			]
			for effect in TechniqueMarginalia.draw(def, TechniqueMarginaliaFixture.rng(seed_value)):
				if (
					String(effect.get("option_id", ""))
					!= String(TechniqueMarginaliaFixture.STAT_OPTION)
				):
					continue
				var value := float(effect.get("value", 0.0))
				assert_eq(value >= low, true, "%.4f is above the floor on %.2f" % [value, authored])
				assert_eq(
					value <= high, true, "%.4f is under the ceiling on %.2f" % [value, authored]
				)
				assert_eq(
					value >= authored * band.x - 0.01,
					true,
					"%.4f is inside the declared band" % value
				)
				assert_eq(
					value <= authored * band.y + 0.01,
					true,
					"%.4f is inside the declared band" % value
				)


func test_a_roll_is_identical_across_rebuilds_and_across_a_save_and_load() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var learned := TechniqueMarginaliaFixture.study(hero, def, 4242)
	var margin: Dictionary = learned.get("margin", {})
	assert_eq(
		margin.has(String(TechniqueMarginaliaFixture.STAT_OPTION)), true, "the copy was annotated"
	)

	# A rebuild re-derives the whole contribution remove-all-then-re-add
	# (ADR 0054). If the roll were re-drawn anywhere on that path, the contribution
	# would move under a player who did nothing.
	TechniquesApi.equip(hero, def)
	var after_equip := TechniqueMarginaliaFixture.qi_control(hero)
	for pass_index in 4:
		TechniquesApi.rebuild(hero)
		assert_almost_eq(
			TechniqueMarginaliaFixture.qi_control(hero),
			after_equip,
			"rebuild %d lands on the same value" % pass_index,
			0.0001
		)

	# The published shape is exactly what a save writes, so this is the payload a
	# save module would round-trip rather than a copy of it built here.
	var saved := TechniquesApi.codex(hero).to_dict()
	var envelope: Dictionary = hero.to_dict()
	envelope["module_data"]["technique_state"] = saved
	var restored := Actor.from_dict(envelope)
	TechniquesApi.attach(restored)
	var restored_row := TechniquesApi.codex(restored).row(def.id)
	var restored_margin: Array = restored_row.get("realized", [])
	assert_eq(restored_margin.size(), margin.size(), "the margin survived the round trip")
	for effect in restored_margin:
		assert_almost_eq(
			float(effect.get("value", 0.0)),
			float(margin[String(effect.get("option_id", ""))]),
			"and carries the same value",
			0.0001
		)
	TechniquesApi.equip(restored, def)
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(restored),
		after_equip,
		"the restored copy contributes the same",
		0.0001
	)


func test_a_refused_learn_writes_no_margin() -> void:
	# ADR 0160's all-or-nothing: a learn that failed takes no progress and leaves no
	# row, so it must leave no annotations either.
	var hero := TechniqueMarginaliaFixture.hero()
	hero.path(PathState.QI).progress = 0.0
	var def := TechniqueMarginaliaFixture.manual()
	var refused := TechniqueMarginaliaFixture.study(hero, def, 5)
	assert_eq(bool(refused.get("ok")), false, "an unaffordable study is refused")
	assert_eq(refused.get("margin", {}).size(), 0, "and annotates nothing")
	assert_eq(TechniquesApi.codex(hero).knows(def.id), false, "and the codex is untouched")


func test_re_learning_keeps_the_copy_the_actor_already_holds() -> void:
	# A duplicate manual re-teaches the technique. It must not re-draw the numbers
	# — that would make re-reading a book a way to gamble an investment the player
	# already paid for.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var first := TechniqueMarginaliaFixture.study(hero, def, 31)
	var again := TechniqueMarginaliaFixture.study(hero, def, 2024)
	assert_eq(bool(again.get("ok")), true, "re-studied")
	assert_eq(
		again.get("margin", {}), first.get("margin", {}), "the margin is unchanged by a second copy"
	)


func test_a_row_migrated_from_the_previous_payload_shape_carries_no_margin() -> void:
	# A v1 row has no annotations recorded and no seed to replay them from. Filling
	# the gap at load would make every old save silently stronger or weaker
	# depending on when it was opened — and AGAIN on every load after that, because
	# nothing in a v1 row records that a roll already happened.
	var legacy := {
		"version": 1,
		"entries": [{"id": "legacy_manual", "rung": 2}],
	}
	var migrated := TechniqueCodex.new(legacy)
	assert_eq(migrated.knows(&"legacy_manual"), true, "the technique is still known")
	assert_eq(migrated.row(&"legacy_manual").get("realized", []).size(), 0, "with no annotations")
	assert_eq(migrated.row(&"legacy_manual").get("rung"), 2, "and its rung intact")
	# A malformed margin is skipped, not repaired into a plausible shape.
	var hostile := {
		"version": 2,
		"entries": [{"id": "hostile_manual", "rung": 0, "realized": ["nope", {"option_id": "x"}]}],
	}
	var hostile_codex := TechniqueCodex.new(hostile)
	assert_eq(
		hostile_codex.row(&"hostile_manual").get("realized", []).size(),
		1,
		"only the dictionary row survives"
	)


func test_an_active_manual_realizes_nothing_because_it_annotates_nothing() -> void:
	# An active technique has no option block at all, so a margin drawn for it would
	# be a number invented for a book that has none. The honest answer is empty —
	# and it is empty for a SHAPE reason (no authored options), not because an
	# active technique is special-cased anywhere.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	def.active = true
	def.passive_options = []
	TechniqueCatalog.instance().register(def)
	var learned := TechniqueMarginaliaFixture.study(hero, def, 17)
	assert_eq(bool(learned.get("ok")), true, "studied")
	assert_eq(learned.get("margin", {}).size(), 0, "an active manual carries no annotations")
	assert_eq(
		TechniqueMarginalia.draw(def, TechniqueMarginaliaFixture.rng(9)).size(),
		0,
		"and the drawer agrees outside a codex"
	)


# --- The band is PUBLISHED, not merely drawn (DEF-0302) ------------------------
#
# `band_for` existed and `draw` used it, so the roll was WIRED — and nothing
# published the window to a player. ADR 0204 promised "a panel showing a player the
# range they may see" and no surface did it. Every assertion below reads the window
# through `band_for` itself, so a panel and the roll cannot disagree about how wide
# the band is, and each asserts a VALUE rather than that a function was called.


## The two edges reach `inspect` as primitives, and they are the edges `band_for`
## declares — read from that one function, never restated as a literal here.
##
## A panel showing a range it computed itself would be a second reader of a roll
## rule, which is the hazard ADR 0196 names; a test holding its own copy of
## `0.75 .. 1.25` would be the same hazard one layer down, and would go green after
## a retune that the roll had already adopted.
func test_the_band_reaches_inspect_as_the_two_edges_band_for_declares() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	TechniqueMarginaliaFixture.study(hero, def, 21)
	var declared := TechniqueMarginalia.band_for(def.rarity)
	var band: Dictionary = TechniquesApi.inspect(hero, def.id).get("marginal_band", {})

	assert_eq(band.has("floor"), true, "the lower edge is published")
	assert_eq(band.has("ceiling"), true, "and the upper one")
	assert_almost_eq(
		float(band["floor"]), float(declared.x), "the floor is band_for's floor", 0.000001
	)
	assert_almost_eq(
		float(band["ceiling"]), float(declared.y), "and the ceiling is band_for's ceiling", 0.000001
	)
	# Primitives only, because every dictionary this module hands a screen is
	# primitives-only and a consumer must never reach back into the module.
	assert_eq(band["floor"] is float or band["floor"] is int, true, "the floor is a number")
	assert_eq(band["ceiling"] is float or band["ceiling"] is int, true, "and so is the ceiling")


## The window is published in the sheet's OWN UNITS, not only as multipliers: for
## every option the band may move, the lowest and highest figure any copy of this
## manual may read. This is the "this sheet says 6.0, a copy may read 4.50-7.50"
## claim, and it is the module's arithmetic — the panel formats it and never
## multiplies.
func test_the_published_range_is_this_manuals_own_figures() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	TechniqueMarginaliaFixture.study(hero, def, 34)
	var declared := TechniqueMarginalia.band_for(def.rarity)
	var view := TechniquesApi.inspect(hero, def.id)
	assert_eq(bool(view.get("marginal_banded", false)), true, "this copy carries variance")

	var figures: Array = view.get("marginal_band_figures", [])
	assert_eq(figures.size(), 1, "only the stat option may be banded — see the next case")
	var row: Dictionary = figures[0]
	assert_eq(
		String(row["option_id"]),
		String(TechniqueMarginaliaFixture.STAT_OPTION),
		"and it is the inscribed option"
	)
	assert_almost_eq(
		float(row["authored"]),
		TechniqueMarginaliaFixture.STAT_VALUE,
		"the sheet's own figure is quoted",
		0.0001
	)
	assert_almost_eq(
		float(row["floor"]),
		TechniqueMarginaliaFixture.STAT_VALUE * float(declared.x),
		"the low end of the range is the band applied to THAT figure",
		0.0001
	)
	assert_almost_eq(
		float(row["ceiling"]),
		TechniqueMarginaliaFixture.STAT_VALUE * float(declared.y),
		"and the high end likewise",
		0.0001
	)
	# The range really is a range: a player told "may read" needs the two ends apart.
	assert_eq(float(row["ceiling"]) > float(row["floor"]), true, "and it is two-sided")
	# The authored figure sits INSIDE its own window, which is what makes a band a
	# band rather than a replacement.
	assert_eq(
		(
			float(row["floor"]) <= float(row["authored"])
			and float(row["authored"]) <= float(row["ceiling"])
		),
		true,
		"the sheet's figure is inside the range a copy may read"
	)


## ADR 0160 refuses the capacity channel, so a capacity option is NOT in the
## published range — and saying otherwise would promise a variance `draw` never
## produced. The test is over the SHIPPED catalog rather than a fixture, so a new
## capacity option cannot quietly join the range.
func test_a_capacity_option_is_never_inside_the_published_range() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	TechniqueMarginaliaFixture.study(hero, def, 8)
	var figures: Array = TechniquesApi.inspect(hero, def.id).get("marginal_band_figures", [])
	var ids: Array[String] = []
	for figure in figures:
		ids.append(String((figure as Dictionary)["option_id"]))
	assert_eq(
		ids.has(String(TechniqueMarginaliaFixture.CAPACITY_OPTION)),
		false,
		"a capacity option is carried as authored"
	)
	assert_eq(
		ids.has(String(TechniqueMarginaliaFixture.STAT_OPTION)),
		true,
		"while the stat option is banded"
	)


## The three rows that have nothing to vary say so with an EMPTY line rather than a
## range around a figure nobody may vary. Each is a different reason, and each would
## otherwise print a promise the module cannot keep.
func test_a_manual_that_cannot_vary_publishes_no_range() -> void:
	# (a) A COMMON copy: rarity reach `0.0`, so the two edges are the same number.
	var common := TechniqueMarginaliaFixture.manual()
	common.rarity = ItemRarity.COMMON
	TechniqueCatalog.instance().register(common)
	var common_view := TechniquesApi.inspect(TechniqueMarginaliaFixture.hero(), common.id)
	assert_eq(bool(common_view.get("marginal_banded", false)), false, "a common copy cannot vary")
	assert_eq((common_view.get("marginal_band_figures", []) as Array).size(), 0, "and says so")

	# (b) An ACTIVE manual: it authors no options at all, so there is nothing to band
	# however wide its rarity band is.
	var active := TechniqueMarginaliaFixture.manual()
	active.active = true
	active.passive_options = []
	TechniqueCatalog.instance().register(active)
	var active_view := TechniquesApi.inspect(TechniqueMarginaliaFixture.hero(), active.id)
	assert_eq(
		bool(active_view.get("marginal_banded", false)), false, "an active manual has no margin"
	)
	assert_eq((active_view.get("marginal_band_figures", []) as Array).size(), 0, "and says so")

	# (c) A capacity-only manual: every option is on the refused channel.
	var capped := TechniqueMarginaliaFixture.manual()
	capped.passive_options = [
		{
			"option_id": TechniqueMarginaliaFixture.CAPACITY_OPTION,
			"value": TechniqueMarginaliaFixture.CAPACITY_VALUE
		}
	]
	TechniqueCatalog.instance().register(capped)
	var capped_view := TechniquesApi.inspect(TechniqueMarginaliaFixture.hero(), capped.id)
	assert_eq(
		bool(capped_view.get("marginal_banded", false)), false, "a capacity-only manual cannot vary"
	)
	assert_eq((capped_view.get("marginal_band_figures", []) as Array).size(), 0, "and says so")


## The roll still lands inside the window this publication promises. A band published
## to a player and a band the roll ignores would be the worst of both — a lie on the
## panel — so the window is asserted to CONTAIN real draws, at both ends of the
## rarity ladder, rather than merely to exist.
func test_every_drawn_copy_lands_inside_the_published_range() -> void:
	for rarity in [ItemRarity.MAGIC, ItemRarity.LEGENDARY]:
		var def := TechniqueMarginaliaFixture.manual()
		def.rarity = rarity
		TechniqueCatalog.instance().register(def)
		var hero := TechniqueMarginaliaFixture.hero()
		var declared := TechniqueMarginalia.band_for(rarity)
		# Twelve seeds: enough to reach both ends of the window rather than landing
		# in the middle by luck. A single draw would pass for a broken band too.
		for seed_value in 12:
			var copy := TechniqueMarginaliaFixture.study(hero, def, seed_value * 97 + 13)
			var rolled: Dictionary = copy.get("margin", {})
			var value := float(rolled[String(TechniqueMarginaliaFixture.STAT_OPTION)])
			var figures: Array = TechniquesApi.inspect(hero, def.id).get(
				"marginal_band_figures", []
			)
			var row: Dictionary = figures[0]
			assert_almost_eq(
				float(row["authored"]),
				TechniqueMarginaliaFixture.STAT_VALUE,
				"the sheet is unbanded",
				0.0001
			)
			assert_eq(
				float(row["floor"]) <= value and value <= float(row["ceiling"]),
				true,
				(
					"seed %d drew %.4f, outside the published %.4f-%.4f (rarity %s, band %.2f-%.2f)"
					% [
						seed_value,
						value,
						float(row["floor"]),
						float(row["ceiling"]),
						String(rarity),
						float(declared.x),
						float(declared.y),
					]
				)
			)


# --- The read model's two cases moved to `test_technique_marginalia_reads.gd` ----
# (the inspect columns and the codex `annotated` flag; same fixture, same claims)

# --- Mastery, and the answer to whether a passive's margin may be banded ---------


## ADR 0140 scales a passive's stat values by `1.15^rung`, so a banded value and a
## rung multiplier meet on the SAME number. They COMPOSE, and this is the whole
## proof: at every rung the effective contribution is exactly
## `banded_value * power`, and `power` is read from `TechniqueScales` rather than
## restated, so the assertion fails if either side moves.
##
## The justification for composing rather than refusing is the ORDER of the two
## facts, not their count. The band is a property of the MANUAL and is fixed once,
## at the learn, forever — `roll * rung` and `rung * roll` are the same float, and
## nothing in the pipeline evaluates them in the other order. So the band is a
## multiplier that was applied ONCE, at a single moment, to a single number, and
## the rung is applied ONCE per rebuild to whatever that number now is. That is one
## multiplier and one subsequent re-scaling of the result, not two multipliers
## stacked on an authored figure.
##
## The alternative — refusing to band anything a rung scales — would empty the
## margin of a passive entirely, because a passive's option values are the only
## thing a margin could ever annotate. The refusal would be total, and a total
## refusal makes the whole component dead content rather than a design decision.
## What IS refused is the CAPACITY channel, and that refusal is on a different
## ground entirely (ADR 0160's triple-multiplier argument), so it does not settle
## this one.
func test_a_band_and_a_rung_multiplier_compose_rather_than_double_count() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var learned := TechniqueMarginaliaFixture.study(hero, def, 606)
	var banded := float(
		(learned.get("margin", {}) as Dictionary)[String(TechniqueMarginaliaFixture.STAT_OPTION)]
	)
	assert_ne(
		banded,
		TechniqueMarginaliaFixture.STAT_VALUE,
		"the copy is genuinely banded before any rung is claimed"
	)
	TechniquesApi.equip(hero, def)
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(hero),
		banded,
		"rung 0 is the band's own number",
		0.0001
	)
	# Rung 4 is the deepest the ladder reaches: `1.15^4 = 1.749`, published by ADR
	# 0055 and read here from `TechniqueScales` so a retune of POWER_STEP cannot
	# silently pass by moving both sides.
	var power := float(TechniqueScales.multipliers_at(4, def.mastery_rungs)["power"])
	var raised := TechniquesApi.raise_mastery(hero, def.id, 4)
	assert_eq(bool(raised.get("ok")), true, "the rung moved")
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(hero),
		banded * power,
		"rung 4 is the band's number times the ladder's power",
		0.001
	)
	# The composition is not an accident of rung 4: at every rung the actor reads
	# exactly `banded * power(rung)`, so nothing double-counts and nothing is
	# applied twice.
	for rung in 5:
		var other := TechniqueMarginaliaFixture.hero()
		var manual := TechniqueMarginaliaFixture.manual()
		var drawn := TechniqueMarginaliaFixture.study(other, manual, 8181)
		var value := float(
			(drawn.get("margin", {}) as Dictionary)[String(TechniqueMarginaliaFixture.STAT_OPTION)]
		)
		TechniquesApi.equip(other, manual)
		TechniquesApi.raise_mastery(other, manual.id, rung)
		var expected := (
			value * float(TechniqueScales.multipliers_at(rung, manual.mastery_rungs)["power"])
		)
		assert_almost_eq(
			TechniqueMarginaliaFixture.qi_control(other),
			expected,
			"rung %d composes the two exactly" % rung,
			0.001
		)
	# And the CAPACITY option in the SAME manual did not compose — it is held at its
	# authored value through rung 4, which is ADR 0160's refusal and the reason the
	# two channels are decided differently.
	var capacity_value := -1.0
	for effect in TechniquesApi.codex(hero).entry(def.id).effects_for(def):
		if (
			String(effect.get("option_id", ""))
			== String(TechniqueMarginaliaFixture.CAPACITY_OPTION)
		):
			capacity_value = float(effect.get("value", 0.0))
	assert_almost_eq(
		capacity_value,
		TechniqueMarginaliaFixture.CAPACITY_VALUE,
		"the capacity option is unscaled by the rung",
		0.0001
	)


# --- The wiring is REACHABLE, and that is what this file is really about --------


## THE REACHABILITY CASE, and the reason it exists.
##
## Every other case in this file calls `TechniquesApi.learn` or
## `TechniqueMarginalia.draw` directly, which proves the component WORKS and says
## nothing about whether anything CALLS it. That is the defect class this program has
## already paid for four times (`delivers`, `bind_target`, `TechniqueCastView`,
## `learn_price`): a verb built, tested, and unreachable from production.
##
## So this drives the real chain a player drives, and no step is skipped:
## `ItemsApi.use_item` → `ItemUse._study_technique` → the installed
## `TechniqueDelivery.study` → `bind_learner` → `TechniquesApi.learn` →
## `TechniqueMarginalia.draw`. The seam is installed the way the composition root
## installs it (`app/item_workbench_body.gd:480`), through `ProjectSettings`, and
## the assert is read off the STORED codex row rather than off a learn return value
## — so a roll that was drawn and then dropped would fail here.
func test_a_margin_is_drawn_by_the_real_item_use_path_and_stored_on_the_codex_row() -> void:
	TechniqueDelivery.install(Callable(TechniqueDelivery, "bind_learner"))
	var hero := TechniqueMarginaliaFixture.hero()
	# The item path needs an inventory, so this hero is built the order `app/` uses.
	ItemsApi.attach(hero)
	var def := TechniqueMarginaliaFixture.manual()
	var technique_id := def.id
	ItemsApi.inventory(hero).add(TechniqueMarginaliaFixture.manual_item(technique_id), 1)

	var result := ItemsApi.use_item(hero, technique_id)
	assert_eq(bool(result.get("ok")), true, "the real item path studied the manual")
	# Read off the STORED ROW. This is the whole point: a margin drawn and not
	# persisted is invisible here, and it is what the save/load case above depends.
	var row := TechniquesApi.codex(hero).row(technique_id)
	var stored: Array = row.get("realized", [])
	assert_eq(stored.size(), 2, "the item path annotated both inscribed options")
	var margin := {}
	for effect in stored:
		margin[String((effect as Dictionary).get("option_id", ""))] = float(
			(effect as Dictionary).get("value", 0.0)
		)
	# A band, not the sheet — asserted here rather than at the facade, because this
	# is the path a player's copy actually travels.
	assert_ne(
		float(margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		TechniqueMarginaliaFixture.STAT_VALUE,
		"the copy a player holds is banded, not the printed figure"
	)
	assert_almost_eq(
		float(margin[String(TechniqueMarginaliaFixture.CAPACITY_OPTION)]),
		TechniqueMarginaliaFixture.CAPACITY_VALUE,
		"and the capacity option is at the sheet",
		0.0001
	)
	# And it is consumed as a projection, so the roll reaches the stat stack through
	# production code rather than through this suite calling a component.
	TechniquesApi.equip(hero, technique_id)
	assert_almost_eq(
		TechniqueMarginaliaFixture.qi_control(hero),
		float(margin[String(TechniqueMarginaliaFixture.STAT_OPTION)]),
		"the item-path copy contributes exactly what it stored",
		0.0001
	)
	TechniqueDelivery.clear()


## The seam is PROCESS-WIDE, and `run_tests.gd` calls `teardown` after every test
## precisely because an install left behind leaks into the next suite. This suite
## installs one above, so it is removed here — the same rule
## `test_technique_delivery.gd` follows for the same reason.
func teardown() -> void:
	TechniqueDelivery.clear()
