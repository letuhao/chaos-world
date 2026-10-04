extends TestCase

## The technique magnitude ladder's shape (ADR 0055).
##
## A technique's effect has to stay relevant from R1 to R30 without becoming the
## cheapest path to power. That is one number with two obligations: it must RISE
## (so a deep technique is worth learning) and it must rise no faster than the
## per-realm work budget (so a breakthrough never gets cheaper than the study
## that precedes it). The authored table at
## `data/techniques/technique_magnitude_table.tres` satisfies both; the load-bearing
## half is the second.
##
## ## Why this test walks every pair, not the endpoints
##
## The obvious assertions are not enough and pass a table that is exactly wrong:
## R1 at 1.0, "strictly rising", and "the span is about 2.77x" are all satisfied by
## a linear ladder. A linear ladder's step shrinks as a percentage of a rising
## base, so it is SHORTEST at the deep end - 1.1x at R1→R2 and 1.026x at R29→R30 -
## which is precisely where the work-budget floor binds hardest. The authored item
## table has that shape and breaks the ceiling on 19 of its 29 pairs. So the
## assertion here is per pair, every realm, against the step the ADR sized.
##
## The Python guard (`uv run python -m tools technique_power check`) asserts the
## same properties over the file on disk, plus the `LEARN_STEP` relationship, which
## a GDScript suite cannot reach: `LEARN_STEP` lives in the techniques module, and
## a module's internal constant is not something a test outside it may read. This
## suite therefore tests the DATA and its SHAPE from inside Godot - that the
## `.tres` the runtime loads really is the shape the ADR approved.

## The per-realm step, restated from ADR 0055. Duplicated on purpose and not
## imported: it is the yardstick the guard measures against, and a yardstick that
## could be retuned by editing the thing it measures is not a guard. Kept in step
## with `TECHNIQUE_STEP` in `tools/technique_power.py`.
const TECHNIQUE_STEP := 1.035714

const LADDER := preload("res://data/techniques/technique_magnitude_table.tres")

## The three sources the runtime-read cases below read. Spelled out literally rather than
## assembled from a unit name, because this file is a suite outside `src/` and the arch
## gate's `res://` rule binds `ui/`: a moved file must be a failing assertion, not a
## silently skipped scan.
const SPINE := "res://src/modules/combat_engine/spine.gd"
const READ_MODEL := "res://src/modules/techniques/technique_read_model.gd"
const SCALES := "res://src/modules/techniques/technique_scales.gd"


func _entry(realm_id: StringName) -> float:
	return float(LADDER.values.get(realm_id, -1.0))


## One number per realm id on the canonical 30-realm ladder, and no others.
## Keyed by id, so this also proves nothing is positional: a realm inserted in the
## middle of the ladder cannot shift every realm below it onto the wrong number.
func test_one_magnitude_per_realm_id_and_nothing_else() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(realms.size(), 30, "the canonical ladder is 30 realms")
	assert_eq(LADDER.values.size(), realms.size(), "one magnitude per realm")

	var ids: Array[StringName] = []
	for realm in realms:
		ids.append(realm.id)
		assert_eq(LADDER.values.has(realm.id), true, "magnitude for %s" % realm.id)
	for key in LADDER.values.keys():
		assert_eq(ids.has(key), true, "magnitude key %s is on the ladder" % key)


## R1 is the neutral baseline: a mortal's technique is unscaled, so nothing about
## it rides on a number this ladder authors.
func test_the_first_realm_is_the_unscaled_baseline() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_almost_eq(_entry(realms[0].id), 1.0, "R1 is 1.0", 0.0001)


## Every realm above the one below it. A technique that shrinks with depth is a
## technique the game is telling the player not to learn.
func test_the_ladder_rises_at_every_realm() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous := 0.0
	for realm in realms:
		var current := _entry(realm.id)
		assert_eq(current > previous, true, "magnitude rises at %s" % realm.id)
		assert_eq(is_finite(current), true, "magnitude is finite at %s" % realm.id)
		previous = current


## THE LOAD-BEARING TEST. Every consecutive ratio at or below the step.
##
## A linear ladder passes "R1 at 1.0", "strictly rising" and "span about 2.8x",
## and then fails here at the deep end - which is where it matters, because the
## work budget a technique must not outrun is tightest exactly there. Asserting
## only the endpoints is what makes a ceiling look enforced while it is not.
func test_every_consecutive_ratio_stays_at_or_below_the_step() -> void:
	var realms := RealmDefaults.ladder().realms()
	var checked := 0
	for index in range(1, realms.size()):
		var below := _entry(realms[index - 1].id)
		var here := _entry(realms[index].id)
		if below <= 0.0 or here <= 0.0:
			continue
		var ratio := here / below
		assert_eq(
			ratio <= TECHNIQUE_STEP,
			true,
			(
				"ratio %s→%s is %s, over the ceiling %s"
				% [
					realms[index - 1].id,
					realms[index].id,
					ratio,
					TECHNIQUE_STEP,
				]
			)
		)
		checked += 1
	assert_eq(checked, 29, "every transition on the ladder was ratio-checked")


## The shape ADR 0055 quotes, asserted on the numbers actually on disk: about
## 1.3714 per tier and 1.8807 per two tiers, and about 2.7667 across the whole
## ladder. These are read off the table, not pasted onto it - a designer who
## retunes a realm by editing one line moves them, and this is the assertion that
## says so out loud.
func test_the_span_and_the_tier_spans_match_the_adrs_shape() -> void:
	var realms := RealmDefaults.ladder().realms()
	var base := _entry(realms[0].id)
	assert_almost_eq(_entry(realms[9].id) / base, 1.3714, "one tier is about 1.3714x", 0.0001)
	assert_almost_eq(_entry(realms[18].id) / base, 1.8807, "two tiers are about 1.8807x", 0.0001)
	assert_almost_eq(_entry(realms[29].id) / base, 2.7667, "the whole ladder is 2.77x", 0.0001)


## A magnitude, not a power. It rides on TOP of `realm_power_table.tres`, so it
## has to stay two orders of magnitude below the 551x actor table - a technique
## on the actor ladder would multiply 551.46x by 551.46x and put ~304,000x on one
## skill, which is the category error ADR 0050 exists to prevent.
func test_it_stays_an_order_of_magnitude_below_the_actor_power_table() -> void:
	var realms := RealmDefaults.ladder().realms()
	var top := _entry(realms[29].id)
	var actor_top := RealmDefaults.POWER.power_for(realms[29].id)
	assert_eq(top < 10.0, true, "the technique ladder tops out below 10x (%s)" % top)
	assert_eq(actor_top / top > 100.0, true, "the actor table is still two orders above it")


## An unknown or missing realm must not collapse a technique to zero: the fallback
## is the neutral 1.0, the same rule `RealmPowerTable.power_for` follows.
func test_an_unknown_realm_is_neutral() -> void:
	for realm_id in [&"", &"not_a_realm"]:
		assert_almost_eq(LADDER.magnitude_for(realm_id), 1.0, "neutral at %s" % realm_id)


# --- The runtime reads the table ----------------------------------------------
##
## Everything above asserts the DATA, and none of it could have caught the defect these
## cases close, because the defect was not a wrong number. `CombatSpine.base_damage` gated
## a technique magnitude with `RealmRate.factor` -- the TRAINING rate -- while
## `TechniqueReadModel.magnitude_now` computed `pow(TECHNIQUE_STEP, ordinal)`, and the
## authored ladder was opened by NOTHING in `res://src`. Both wrong readings agree with the
## table to 2.5e-6 (R30: 1.775845 and 2.766659 against an authored 2.7666560), so every value
## assertion in this file passed while combat and the UI each priced a technique
## differently. That is "a green guard is not a tested guard" (INC-0016) in its purest
## form: only the STRUCTURAL fact is assertable here, so only that is asserted.


## Both surfaces that price a technique name the table's own lookup. Read from SOURCE,
## not from behaviour, because a uniform bypass -- both sides wrong the same way -- is
## invisible to any comparison between them and agrees with the table to six figures.
func test_the_hit_and_the_display_both_name_the_authored_table() -> void:
	for path in [SPINE, READ_MODEL]:
		var source := _code_only(path)
		assert_ne(source, "", "%s is readable" % path)
		assert_eq(
			source.contains("TechniqueMagnitudeTable.factor"),
			true,
			(
				("%s reads the authored ladder by realm id rather than computing one from a" % path)
				+ " ordinal or a rate"
			)
		)


## The rate does not come back as a technique's realm axis. This is the second half of
## the same guard and the reason it is not one assertion: naming the table is satisfied
## by a call that sits NEXT TO a `RealmRate.factor` multiply, and the defect was a rate
## standing in for the ladder, so both shapes have to be named.
func test_the_training_rate_is_not_a_technique_magnitude_anywhere() -> void:
	var spine := _code_only(SPINE)
	assert_ne(spine, "", "spine.gd is readable")
	assert_eq(
		spine.contains("RealmRate.factor"),
		false,
		"the spine prices a technique through its own ladder, never the training rate"
	)


## The closed form is gone from the module, not merely unused. A surviving
## `magnitude_at` is a second read path with no caller today and a caller tomorrow,
## and it is the exact shape that let the bug hide: a number that matches the table to
## 2.5e-6 is indistinguishable from the table to every value assertion.
func test_the_closed_form_is_gone_from_the_module() -> void:
	var scales := _code_only(SCALES)
	assert_ne(scales, "", "technique_scales.gd is readable")
	assert_eq(
		scales.contains("func magnitude_at"),
		false,
		"no ordinal-indexed magnitude survives beside the authored one"
	)
	assert_eq(
		scales.contains("pow(TECHNIQUE_STEP"),
		false,
		"and the step is never a runtime curve: it authored the table, it does not replace it"
	)


## The call is LOAD-BEARING, not merely present. A `factor` that quietly answered 1.0
## would satisfy the three structural cases above and make every deep technique a
## mortal one, so the number the spine builds must move with the realm it reads.
func test_the_spine_prices_a_deep_technique_through_the_ladder() -> void:
	var early := _actor_at(&"qi_refining")
	var late := _actor_at(&"primordial_origin")
	var def := _def_at(2.0)
	var early_base := CombatSpine.base_damage(early, def)
	var late_base := CombatSpine.base_damage(late, def)
	assert_almost_eq(early_base, 2.0, "R1 pays the authored magnitude unscaled", 0.0001)
	assert_almost_eq(
		late_base,
		2.0 * LADDER.magnitude_for(&"primordial_origin"),
		"R30 pays the authored ladder's top rung",
		0.001
	)
	assert_eq(late_base > early_base, true, "and depth is worth something")


## The displayed number and the hit base are the same number. The structural cases above
## cannot see a ONE-SIDED drift -- a panel fixed to `actor.realm()` while the spine reads
## something else, or the reverse -- because they only ask whether each names the table.
## This asks the question a player would ask: is the figure on screen the figure that
## was swung.
func test_the_displayed_magnitude_is_the_number_the_hit_is_built_from() -> void:
	var realms := RealmDefaults.ladder().realms()
	var checked := 0
	for index in range(0, realms.size()):
		var realm_id: StringName = realms[index].id
		var actor := _actor_at(realm_id)
		var def := _def_at(2.0)
		var shown := float(TechniquesApi.inspect(actor, def)["magnitude_now"])
		var swung := CombatSpine.base_damage(actor, def)
		assert_almost_eq(shown, swung, "at %s the panel and the blow agree" % realm_id, 0.0001)
		assert_almost_eq(
			swung,
			2.0 * LADDER.magnitude_for(realm_id),
			"at %s the blow reads the authored rung" % realm_id,
			0.0001
		)
		checked += 1
	assert_eq(checked, 30, "every realm on the ladder was walked")


## A source file with every comment line dropped. The docblocks on these files QUOTE the
## bug -- `spine.gd` names `RealmRate.factor` to say it no longer calls it, and
## `technique_scales.gd` names `pow(TECHNIQUE_STEP` to say it no longer computes it -- so a
## raw text scan reports the documentation of the fix as the fix's return. Every structural
## case below matches CODE only. Bounded by `split("\n")`, which is the whole file.
func _code_only(path: String) -> String:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var kept: Array[String] = []
	for line in lines:
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(&"ladder_probe")
	actor.set_path(PathState.new(PathState.QI, realm_id))
	TechniquesApi.attach(actor)
	return actor


func _def_at(magnitude: float) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"ladder_probe_def"
	def.display_name = "Probe"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.magnitude = magnitude
	return def
