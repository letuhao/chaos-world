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
