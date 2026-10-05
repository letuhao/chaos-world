extends TestCase

## ADR 0258 §3: the age bands are AUTHORED DATA beside the lifespan table, keyed by NAME,
## and an inserted band shifts NOTHING.
##
## ## The property under test, stated once
##
## `tests/core/test_realm_lifespan_table.gd` proves its anti-shift property by inserting a
## row and comparing every value before and after. This file proves the SAME property for
## the sibling table, because the sibling is where the mistake would be cheap: a band table
## keyed by array position reads perfectly, and the day a fifth band lands in the middle
## every band below it silently slides.
##
## ## The insertion here is IN MEMORY, never on disk
##
## The shipped `.tres` is read, a fifth band is added to a DUPLICATE of it, and every
## authored fraction is compared across the two. No file another agent may be editing is
## written (INC-0007, INC-0016), and the guard cannot go red for a reason unrelated to what
## it watches. A duplicate rather than a mutation of the loaded resource, because `load()`
## caches: the catalogue every later suite reads holds the same instance.

## The shipped table. Loaded rather than reached through a `const`, so this suite fails if
## the loader is removed rather than reading a null and passing every assertion vacuously.
const TABLE_PATH := "res://src/core/age_band_table.tres"

## A whole DAY per year, for the day/year conversion these tests read through
## `TimeLadder`. Derived, never typed: `SoulAge.days_per_year` divides the ladder's own two
## ratios, so a retune of either row moves the fixture with it instead of leaving a 365
## lying beside it (ADR 0173).
const DAY := &"day"
const YEAR := &"year"


func _table() -> AgeBandTable:
	return load(TABLE_PATH) as AgeBandTable


## Every authored fraction as `{name: float}`, so one `assert_eq` compares the WHOLE table
## rather than four rows that could disagree and still read as a pass.
func _fractions(table: AgeBandTable) -> Dictionary:
	assert_ne(table, null, "the shipped .tres loads")
	if table == null:
		return {}
	var out: Dictionary = {}
	for band in AgeBandTable.AUTHORED_BANDS:
		out[String(band)] = table.fraction_for(band)
	return out


# --- Shape: four authored bands and no others ----------------------------------


func test_the_table_authors_four_named_bands_and_no_others() -> void:
	var table := _table()
	assert_eq(AgeBandTable.AUTHORED_BANDS.size(), 4, "four band names are declared")
	# Named rather than counted, so a substituted band fails as loudly as a fifth one.
	assert_eq(
		AgeBandTable.AUTHORED_BANDS,
		[&"first_ash", &"greenwood", &"gilded", &"lastlight"],
		"and they are the four this feature ships"
	)
	# The `.tres` authors exactly those four — a name the literal does not carry is a row
	# nothing can reach, and a literal name the `.tres` omits is a band that always falls
	# back to `first_ash`.
	var authored: Array[String] = []
	for band in table.fractions.keys():
		authored.append(String(band))
	authored.sort()
	var declared: Array[String] = []
	for band in AgeBandTable.AUTHORED_BANDS:
		declared.append(String(band))
	declared.sort()
	assert_eq(authored, declared, "the .tres authors every declared band and no other")


## The youngest band enters at exactly zero and the last strictly below one. A last band
## at `1.0` would be unreachable (a body cannot outlive its own lifespan and keep ticking),
## which is the "a guard that cannot fail is a missing guard" shape in the data itself.
func test_the_youngest_band_is_zero_and_the_oldest_is_below_one() -> void:
	var table := _table()
	assert_eq(table.fraction_for(AgeBandTable.FIRST_ASH), 0.0, "the youngest band enters at 0.0")
	var oldest := AgeBandTable.AUTHORED_BANDS[AgeBandTable.AUTHORED_BANDS.size() - 1]
	assert_eq(
		table.fraction_for(oldest) < 1.0,
		true,
		"the oldest band is reachable, so its fraction is strictly below 1.0"
	)


## STRICTLY rising across the four rows. Not a floor: two bands at the same crossing would
## make one of them a row that can never be the answer, and a test that only checked
## "non-decreasing" would call that clean. `band_for` resolves a tie to the FURTHEST band
## reached precisely so this assertion is what names the defect.
func test_the_fractions_rise_strictly_from_the_youngest_to_the_oldest() -> void:
	var table := _table()
	for index in range(AgeBandTable.AUTHORED_BANDS.size() - 1):
		var below := table.fraction_for(AgeBandTable.AUTHORED_BANDS[index])
		var above := table.fraction_for(AgeBandTable.AUTHORED_BANDS[index + 1])
		assert_eq(
			above > below,
			true,
			(
				"%s enters before %s (%s < %s)"
				% [
					String(AgeBandTable.AUTHORED_BANDS[index + 1]),
					String(AgeBandTable.AUTHORED_BANDS[index]),
					above,
					below
				]
			)
		)


func test_every_authored_fraction_is_a_finite_share_of_a_lifespan() -> void:
	var table := _table()
	for band in table.fractions.keys():
		var value := table.fraction_for(StringName(band))
		assert_eq(is_finite(value), true, "%s is finite" % String(band))
		assert_eq(value >= 0.0 and value <= 1.0, true, "%s is a share in [0, 1]" % String(band))


# --- The read ----------------------------------------------------------------


## The crossing IS `>=`, because a band ENTERING is the event: a body standing exactly on
## a crossing has ARRIVED at it. Asserted ON the boundary rather than near it, because
## "just past" would pass against a `>` that had silently become a `>=` in the wrong place
## and against a boundary that had moved a thousandth off the authored fraction.
func test_a_body_exactly_on_a_crossing_has_arrived_at_that_band() -> void:
	var table := _table()
	var greenwood := table.fraction_for(&"greenwood")
	var gilded := table.fraction_for(&"gilded")
	assert_eq(
		table.band_for(greenwood * 1000.0, 1000.0), &"greenwood", "exactly a quarter is greenwood"
	)
	assert_eq(table.band_for(gilded * 1000.0, 1000.0), &"gilded", "exactly a half is gilded")
	assert_eq(table.band_for(0.0, 1000.0), AgeBandTable.FIRST_ASH, "and day one is the first band")
	# And the last band really is reachable — the contrast, so the first half above is not
	# satisfied by a table whose oldest row is past one and therefore dead.
	assert_eq(
		table.band_for(0.999 * 1000.0, 1000.0),
		&"lastlight",
		"a body at 99.9% of its life has reached the oldest band"
	)


## A body past its own lifespan is still the OLDEST band and not a refusal or a crash: ADR
## 0258 §5 ends the BODY at the lifespan, and the band table's job is to name the stage a
## body has reached, never to adjudicate whether it is allowed to still be alive.
func test_a_body_past_its_lifespan_reads_the_oldest_band() -> void:
	var table := _table()
	assert_eq(
		table.band_for(5000.0, 1000.0),
		&"lastlight",
		"overrun clamps to the last band rather than falling out of the table"
	)


## The NULL case, and it is the one that matters most: a body with no lifespan at all —
## no `race_def` component, so `RealmLifespan.effective_lifespan_for` answers `0.0` — must
## read as the YOUNGEST band. It must never read as the oldest, which would be a guard that
## expires every hero who has not been assigned a race on their first frame.
func test_no_lifespan_is_the_youngest_band_and_never_the_oldest() -> void:
	var table := _table()
	for lifespan in [0.0, -1.0, -10_000.0]:
		assert_eq(
			table.band_for(999.0, lifespan),
			AgeBandTable.FIRST_ASH,
			"a lifespan of %s reads as the first band, never the last" % lifespan
		)


func test_an_unauthored_band_name_is_the_youngest_band() -> void:
	var table := _table()
	assert_eq(table.fraction_for(&"no_such_band"), 0.0, "an unauthored name has no crossing")
	assert_eq(
		table.band_for(900.0, 1000.0) == &"no_such_band",
		false,
		"and can never be the answer for any age"
	)
	assert_eq(table.fraction_for(&""), 0.0, "an empty name is not a band either")


## The read model the lineage screen takes: primitives only, youngest first, and every
## AUTHORED row present. Asserted through the COUNT against the table's own data rather
## than against a literal, so the assertion is about the reader covering the table rather
## than about a number typed here — and the ORDER is asserted, because a screen drawing the
## crossings from an unsorted list would draw them in whatever order the `.tres` was typed.
func test_bands_is_primitives_and_covers_every_authored_band() -> void:
	var table := _table()
	var rows := table.bands()
	assert_eq(rows.size(), table.fractions.size(), "one row per authored band, none dropped")
	var previous := -1.0
	for row in rows:
		var as_dict := row as Dictionary
		# The FAILING side is the OBJECT/NIL one: a String is what this row must carry, so
		# `assert_eq(is_object_or_nil, false)` is the form that says "not a Resource".
		assert_eq(
			(
				typeof(as_dict.get("band", null)) == TYPE_OBJECT
				or typeof(as_dict.get("band", null)) == TYPE_NIL
			),
			false,
			"the band is a plain String, not a Resource and not absent"
		)
		assert_eq(typeof(as_dict.get("fraction", 0)), TYPE_FLOAT, "the fraction is a float")
		# Ordering, read off the value rather than off a sorted copy: a screen reading this
		# draws the crossings, and it can only do that if they arrive youngest-first.
		var fraction := float(as_dict["fraction"])
		assert_eq(fraction >= previous, true, "rows arrive youngest-first (%s)" % fraction)
		previous = fraction


# --- THE ANTI-SHIFT PROPERTY -------------------------------------------------


## Inserting a band changes NO existing band's value.
##
## This is the assertion the whole keyed-by-name decision exists for. A fifth band is added
## to a DUPLICATE of the shipped table, positioned BETWEEN two existing rows — the position
## that an index key would answer wrongly — and every authored fraction is compared across.
##
## The inserted band carries a fraction of its own that is NOT on a chain (a fifth-band
## author picks a crossing point), which is the property: no existing row is derived from
## any other, so there is nothing to rebasing.
func test_inserting_a_band_moves_no_existing_fractions() -> void:
	var table := _table()
	var before := _fractions(table)
	var grown: AgeBandTable = table.duplicate()
	grown.fractions = table.fractions.duplicate()
	# Inserted between `gilded` and `lastlight`, which is where an index key would slide
	# `lastlight` onto the wrong crossing.
	grown.fractions[&"ember_late"] = 0.625
	assert_eq(_fractions(grown) == before, true, "an inserted band leaves the old four alone")
	# The control: the insertion really happened, or the comparison above proves nothing.
	assert_eq(grown.fractions.size(), table.fractions.size() + 1, "the band was really added")
	assert_eq(grown.fraction_for(&"ember_late"), 0.625, "and it carries its own crossing")


## The same property read the way a consumer reads it: an inserted band must not change the
## band any GIVEN age resolves to, except by arriving where it was authored to arrive.
##
## The loop walks the AUTHORED band names, so it is bounded by the table's own declared row
## count rather than by anything a caller passes (AGENTS.md:52). The ages are the authored
## fractions scaled into a lifespan, so the comparison is over real crossings rather than
## over arbitrary numbers that might miss every one.
func test_an_inserted_band_leaves_every_existing_age_resolving_as_it_did() -> void:
	var table := _table()
	var grown: AgeBandTable = table.duplicate()
	grown.fractions = table.fractions.duplicate()
	grown.fractions[&"ember_late"] = 0.625
	# Snapshot the bound BEFORE the loop: the walk is over the AUTHORED names, and a row
	# count read from the table under test would be the data-derived bound this rule names.
	var crossings := AgeBandTable.AUTHORED_BANDS
	for band in crossings:
		var fraction := table.fraction_for(band)
		var age := fraction * 1000.0
		assert_eq(
			grown.band_for(age, 1000.0),
			table.band_for(age, 1000.0),
			"a body at %s of its lifespan resolves the same after an insertion" % fraction
		)


## ## The converse, and why it is the sharper half: an inserted band DOES take effect
##
## An anti-shift test is satisfied by a table whose lookup ignores its own data, so this is
## its control: a band that is only in the authored fractions — with no `const` edited and no
## code touched — must resolve at its own crossing and change nothing else. That is what
## "keyed by NAME" has to mean for a fifth band to be one file edit.
##
## Without this the anti-shift pair above would also be satisfied by a reader that answered
## `first_ash` forever, which is a guard that cannot fail (ADR 0188).
func test_the_inserted_band_is_reachable_at_its_own_crossing() -> void:
	var grown := _with_inserted()
	# Just before the new crossing: the previous band. On it: the new one. After it: the
	# band that used to own this span. This is what makes the insertion a real row rather
	# than an ignored key.
	assert_eq(grown.band_for(620.0, 1000.0), &"gilded", "just before, still gilded")
	assert_eq(grown.band_for(625.0, 1000.0), &"ember_late", "on it, the inserted band")
	assert_eq(grown.band_for(760.0, 1000.0), &"lastlight", "and the next band still follows")


## The inserted row is reachable WITHOUT touching `AUTHORED_BANDS`, which is the property
## that makes a fifth band a data edit rather than a code edit — and the anti-shift test
## above would still pass if this one did, so the pair is what covers the reader.
func test_an_inserted_band_needs_no_code_change_to_be_read() -> void:
	assert_eq(
		AgeBandTable.AUTHORED_BANDS.has(&"ember_late"),
		false,
		"the shape literal was not edited to make this band reachable"
	)
	assert_eq(
		_with_inserted().fraction_for(&"ember_late"), 0.625, "its crossing is authored data alone"
	)
	assert_eq(
		_with_inserted().band_for(625.0, 1000.0),
		&"ember_late",
		"and the reader answers with it at that crossing"
	)


## The shipped `.tres` plus one row, on a DUPLICATE so the loaded resource every other suite
## reads is untouched (`load()` caches the instance — INC-0007, INC-0016).
func _with_inserted() -> AgeBandTable:
	var base := _table()
	var grown: AgeBandTable = base.duplicate()
	grown.fractions = base.fractions.duplicate()
	# Inserted between `gilded` and `lastlight`, which is where an index key would slide
	# `lastlight` onto the wrong crossing.
	grown.fractions[&"ember_late"] = 0.625
	return grown


# --- Invariances --------------------------------------------------------------


## The bands are AUTHORED DATA and must be invariant under an authored MAGNITUDE: rewrite a
## `RealmDef.power` and every crossing is unchanged. `power` is the shared combat multiplier
## and has nothing to say about how long a body lives; if this ever fails, the age bands have
## started tracking strength, which is ADR 0050's category error wearing a new hat.
##
## Restored BEFORE the assertion, so a failure here cannot leak a mutated ladder into whichever
## suite runs next and turn one failure into three.
func test_the_bands_are_invariant_under_the_authored_realm_power() -> void:
	var realm := RealmDefaults.ladder().realm(&"earth_immortal")
	assert_ne(realm, null, "the probe realm is on the ladder")
	if realm == null:
		return
	var before := _fractions(_table())
	var power_before := realm.power
	assert_eq(
		power_before != 0.0, true, "the probe power is non-zero, or the rewrite proves nothing"
	)
	realm.power = power_before * 7.5
	var after := _fractions(_table())
	realm.power = power_before
	assert_eq(after, before, "a retuned RealmDef.power does not move an age band")


## And invariant under the authored LIFESPAN MULTIPLIER — the sibling table's own numbers.
## A band is a fraction, so every tier of every race must cross at the same share, which is
## the property that makes "three quarters of a life" mean the same thing to a mortal and to
## a Transcendent. The bands live at their own authored fractions and nowhere else, so
## nothing here may scale with the tier.
func test_the_bands_are_invariant_under_the_authored_lifespan_multiplier() -> void:
	var table := _table()
	var before := _fractions(table)
	# The multiplier is read through the SAME table `race/provider.gd` contributes from, so
	# a tier that resolves a different lifespan must still resolve the same band at the same
	# fraction. The bound is `RealmLifespan.AUTHORED_TIERS`, an authored literal.
	for tier in RealmLifespan.AUTHORED_TIERS:
		var lifespan := RealmDefaults.LIFESPAN.effective_days(36500.0, tier)
		assert_eq(lifespan > 0.0, true, "tier %d authors a lifespan" % tier)
		assert_eq(
			table.band_for(lifespan * table.fraction_for(&"gilded"), lifespan),
			&"gilded",
			"a body at half of tier %d's lifespan is gilded whatever the multiplier" % tier
		)
	assert_eq(_fractions(table), before, "and the read changed nothing on the way")


## ## Why the fixture reads the CALENDAR rather than typing a year
##
## A lifespan is authored in DAYS (`RaceDef.lifespan`) and the age fields are named in
## YEARS, so something has to bridge them. `TimeLadder` is the only converter (ADR 0173)
## and every ratio is measured from the BASE, so days-per-year is
## `ratio_for(&"year") / ratio_for(&"day")` — derived here rather than typed, so a retune of
## either row moves this fixture with it instead of leaving a 365 beside it.
##
## The band table itself never converts: it takes DAYS in both arguments precisely so the
## conversion happens ONCE, at the caller that owns both units.
func test_days_and_years_are_converted_through_the_ladder_never_by_a_second_constant() -> void:
	var table := _table()
	var days_per_year := TimeLadder.ratio_for(YEAR) / TimeLadder.ratio_for(DAY)
	assert_eq(days_per_year > 0, true, "the ladder authors both magnitudes")
	# A CENTURY-long lifespan, expressed in days through the ladder, and a body twenty
	# years into it. `greenwood` ENTERS at 0.25 and a fifth of a life is still
	# `first_ash` — asserted rather than nudged, because this is where an off-by-a-band
	# fixture would hide.
	var years := 20.0
	var lifespan_days := 100.0 * float(days_per_year)
	var age_days := years * float(days_per_year)
	assert_eq(years, 20.0, "the fixture body is twenty years into a hundred-year life")
	assert_eq(
		table.band_for(age_days, lifespan_days),
		AgeBandTable.FIRST_ASH,
		"a fifth of a life has not reached greenwood"
	)
	# And the same body once it has crossed a quarter, so the assertion above is about the
	# crossing and not about a reader that never leaves `first_ash`.
	assert_eq(
		table.band_for(26.0 * float(days_per_year), lifespan_days),
		&"greenwood",
		"past a quarter, it is greenwood"
	)
	assert_eq(
		table.band_for(76.0 * float(days_per_year), lifespan_days),
		&"lastlight",
		"and past three quarters, it is lastlight"
	)
