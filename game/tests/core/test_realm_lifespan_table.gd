extends TestCase

## ADR 0169: the lifespan MAGNITUDE is one authored table in `core`, keyed by realm
## TIER, and exactly one multiplication lives in `core` (ADR 0050 / 0116 / 0169).
##
## ## Why this file reads SOURCE and not numbers
##
## ADR 0116 is the precedent, and it is the reason this suite exists. A numerically
## IDENTICAL private copy of a rate constant stayed green under every value
## assertion ever written against it — 403 passed, 3 failed, and the only three were
## structural pins. The two `*RealmProfile` curves were `RealmRate.RATE_STEP` to the
## last digit, so `x == x` was the whole comparison. The fourth copy, in
## `dual_cultivation`, was then an inline `1.0 + ordinal * 0.05` with no constant
## and no `pow(` at all, so even the constant-shaped pins missed it and only a
## call-site pin caught it.
##
## The hazard here is the same one one level up: a module that typed
## `def.lifespan * 10.0` instead of reading `RealmLifespan.effective_lifespan_for`
## would be right today and free to drift tomorrow, and `tools arch` cannot see it
## either — `BARE_REF_UNITS` is `{ui, app, contracts}` (`rules.py:61`), so a bare
## reference out of `core/` or `modules/*` reports zero violations. Hence
## `test_no_file_but_the_table_declares_a_lifespan_multiplier` below, which fails
## naming FILE and LINE for every hit.
##
## ## The negative, which is the other half of the ADR
##
## A lifespan must never read a WORLD time-flow. `WorldTierDef.time_flow_min/max`
## (`world_tier_def.gd:14-15`) is an authored ~100x ladder whose bands
## 1-9/10-18/19-27/28-30 coincide with the realm tiers BY ACCIDENT, and two
## vocabularies that agree by coincidence are what gets merged by accident.

const SRC_ROOT := "res://src"

## The ONE allowed home of a lifespan multiplier. Allow-listed by path rather than
## by pattern so the exemption is one readable line a reviewer can see and delete.
const SSOT := "res://src/core/realm_lifespan_table.gd"

## A DECLARED name carrying one of these, matched case-insensitively. `SCALE` is
## NOT in the set, and the omission is measured rather than cautious: replaying it
## over the tree names `PERCENT_SCALE` (`ui/panels/difficulty_preset_row.gd:42`),
## `SCALE_VERSION` (`modules/items/option_catalog.gd:14`) and `UNSCALED`
## (`modules/clan/clan_gate.gd:70`) — three legitimate numbers that would have made
## this guard red on its first honest run, which is how a guard stops being trusted.
## The bare `LIFESPAN` token already catches `LIFESPAN_SCALE`; the compounds name
## what the thing IS, and the rott test below asserts each one still matches on its
## own, so a token cannot silently stop recognising anything.
const LIFESPAN_TOKENS := [
	"LIFESPAN_MULTIPLIER",
	"LIFESPAN_SCALE",
	"LIFESPAN_FACTOR",
	"LIFESPAN",
]

## The one legitimate `lifespan`-named declaration outside the table, as
## `"<path>|<line>|<name>"`. `RaceDef.lifespan` is the authored per-race MORTAL
## baseline the multiplier scales — content, not a second copy of the rule — so it is
## exempt BY NAME rather than by weakening the token that finds it.
const AUTHORED_BASELINE := ["res://src/modules/race/race_def.gd|56|lifespan"]

## Tokens that mark a WORLD time-flow read rather than a lifespan. `time_flow`
## covers `InsideWorld.time_flow` (`core/inside_world.gd:17`) and the published
## `&"inside_world_time_flow"` (`core/inside_world_provider.gd:16`);
## `time_flow_rate` covers `WorldState.time_flow_rate`
## (`core/world_creation.gd:36`); `time_flow_min`/`time_flow_max` cover the
## authored world-tier band (`modules/world/world_tier_def.gd:14-15`) — the ladder
## whose coincidence with the realm tiers is the whole hazard.
##
## `WorldState` and `InsideWorld` are deliberately NOT tokens: they are the TYPES,
## and `core/actor.gd:71-72` holds one of each on every actor, so treating the type
## as the read would forbid `core/` from having an actor at all. A file that wants
## a world time-flow reads a FIELD, and a field is what these tokens name.
const WORLD_TOKENS := [
	"time_flow_min",
	"time_flow_max",
	"time_flow_rate",
	"time_flow",
]

## The files allowed to touch the field. Each OWNS the vocabulary, and a guard that
## fired on the file that declares `time_flow` would be a guard that could never be
## written — the sentence `test_save_envelope.gd:281-297` exists to write down.
## Each is asserted below to still declare what it is exempt for, so an exemption
## cannot go vacuous.
const WORLD_EXEMPT: Array[String] = [
	"res://src/core/inside_world.gd",
	"res://src/core/inside_world_provider.gd",
	"res://src/core/world_creation.gd",
	"res://src/modules/world/world_tier_def.gd",
]

## Floors under the walk, and the test that turns an empty list into a failure
## rather than an all-clear (`test_save_envelope.gd:414-451`, where a guard that
## walked `.tres` files reported "clean" over an empty file list).
const SRC_FILE_FLOOR := 450

## The four authored realm tiers, as `RealmDefaults` writes them.
const MORTAL := 1
const SPIRIT := 2
const IMMORTAL := 3
const TRANSCENDENT := 4

# --- Shape: four authored rows and no others ----------------------------------


## The table authors exactly the four bands the ladder has, and no others. A fifth
## tier is a new AUTHORED ROW the author decides, never a formula this table grew
## — so a row nobody planned is a shape change and has to be argued for.
func test_the_table_authors_four_rows_and_no_others() -> void:
	var rows := _rows()
	assert_eq(rows.size(), 4, "four authored tier rows: %s" % str(rows.keys()))
	# Untyped, not `Array[int]`: `AUTHORED_TIERS` is an untyped Array, and reading a
	# static `Array` property yields a Variant — so the annotated sort was a runtime
	# `Trying to assign an array of type "Array" to a variable of type "Array[int]"`
	# that aborted THIS body after two assertions, which the per-assertion tally
	# reports as neither a pass nor a failure. See `run_tests.gd:97-116`.
	var keys = rows.keys()
	keys.sort()
	assert_eq(keys, [MORTAL, SPIRIT, IMMORTAL, TRANSCENDENT], "and they are tiers 1..4")
	assert_eq(
		RealmLifespan.AUTHORED_TIERS,
		[MORTAL, SPIRIT, IMMORTAL, TRANSCENDENT],
		"declared as four too"
	)


## Mortal is the NEUTRAL row, exactly 1.0 and not merely near it. Every actor
## starts on a mortal realm, so a Mortal multiplier off by a percent silently
## rescales every authored race in the game and invalidates every test that pins a
## lifespan against an authored default.
func test_mortal_is_exactly_one() -> void:
	assert_eq(_rows().get(MORTAL, -1.0), 1.0, "tier 1 is 1.0")
	assert_eq(_table().multiplier_for(MORTAL), RealmLifespan.NEUTRAL, "and it is NEUTRAL")
	assert_eq(RealmLifespan.NEUTRAL, 1.0, "and NEUTRAL is 1.0, never 0.0")


## A decade a tier, at least. The shape the author CHOSE — "x10 per tier" is a
## reading of four cells, not a recipe — but if one row ever fell to 1x the next,
## a tier would stop buying any life at all, which is the whole claim of ADR 0169's
## table. A FLOOR, not an equality, so a retune upward stays legal.
func test_each_row_is_at_least_ten_times_the_row_below() -> void:
	for tier in range(MORTAL, TRANSCENDENT):
		var below := float(_rows().get(tier, 0.0))
		var above := float(_rows().get(tier + 1, 0.0))
		assert_eq(below > 0.0, true, "tier %d is positive" % tier)
		assert_eq(
			above >= below * 10.0,
			true,
			"tier %d is >= 10x tier %d (%s >= %s)" % [tier + 1, tier, above, below]
		)


## A non-finite multiplier makes every effective lifespan at that tier NaN or INF,
## and a NaN stat propagates silently through the whole derived pipeline rather
## than failing where it was written. Read off the values as authored in the `.tres`.
func test_every_authored_multiplier_is_finite() -> void:
	for tier in _rows().keys():
		assert_eq(is_finite(float(_rows()[tier])), true, "tier %d is finite" % tier)


## These are MAGNITUDES, so the span is large on purpose. This is the invariant
## that says the table has not been quietly grown from the rate: a rate is bounded
## under 2x (`RealmRate.RATE_STEP^29 = 1.776`) precisely BECAUSE it is a gain. If
## this ever fails, someone read one exponential as the other — the ADR 0066
## failure `AGENTS.md:141` records.
func test_the_span_is_a_magnitude_and_never_a_gain() -> void:
	var span := _table().multiplier_for(TRANSCENDENT) / _table().multiplier_for(MORTAL)
	assert_almost_eq(span, 1000.0, "the authored span is 1000x", 0.0001)
	assert_eq(span > 2.0, true, "a lifespan ladder is a magnitude, not a gain (%s)" % span)
	assert_eq(
		span > pow(RealmRate.RATE_STEP, 29.0), true, "and it is not the rate's span in disguise"
	)


# --- The fallback -------------------------------------------------------------


## A tier nobody authored is 1.0 and NEVER 0.0. A missing row must leave a body
## exactly as authored rather than scale its life to nothing — the same fallback,
## for the same reason, as `realm_power_table.gd:32`. Asserted across a spread of
## unauthored tiers so an off-by-one boundary fails here rather than in a balance
## report a year from now.
func test_an_unauthored_tier_is_one_and_never_zero() -> void:
	for tier in [-1, 0, 5, 6, 99]:
		assert_eq(_table().multiplier_for(tier), 1.0, "tier %d falls back to 1.0" % tier)
		assert_eq(_table().multiplier_for(tier) != 0.0, true, "and never to 0.0")


## A negative baseline is a content bug in a `.tres`, not a lifespan. Clamped at
## zero rather than propagating a negative stat — the same refusal the race
## provider applied to `def.lifespan` before ADR 0169 moved the arithmetic into
## core.
func test_effective_days_clamps_a_negative_baseline_at_zero() -> void:
	assert_eq(_table().effective_days(-5.0, SPIRIT), 0.0, "no negative life")
	assert_eq(_table().effective_days(0.0, TRANSCENDENT), 0.0, "and no life stays none")


# --- The effective read -------------------------------------------------------


## The one authored baseline and the one tier row meet in a single number. Read the
## baseline from the CATALOG rather than pasting it, so a retune of
## `data/races/*.tres` is a balance change that must not require editing this suite
## (`test_realm_scaling.gd:3-6` is the precedent).
##
## At Mortal the answer is the authored baseline EXACTLY, which is what keeps every
## existing race test — and the `DEFAULT_LIFESPAN_DAYS` content threshold at
## `tests/modules/race/test_race_content.gd:29` — meaning the same thing after this
## change.
func test_the_effective_lifespan_is_the_baseline_at_the_authors_tier() -> void:
	var baseline := RaceCatalog.instance().race_definition(&"commonborn").lifespan
	assert_almost_eq(_table().effective_days(baseline, MORTAL), baseline, "Mortal is 1x", 0.01)
	for tier in RealmLifespan.AUTHORED_TIERS:
		assert_almost_eq(
			_table().effective_days(baseline, tier),
			baseline * _table().multiplier_for(tier),
			"tier %d" % tier,
			0.01
		)


## The stat a provider publishes is the effective number, not the authored
## baseline. Asserted through the shipped read on a real actor, so a provider that
## went back to contributing `def.lifespan` raw fails here while every core
## assertion above still passes.
##
## The realm at each tier is read off the ladder rather than pasted, so
## `realm_defaults.gd` can gain a realm or a tier without this needing an edit.
func test_the_race_provider_publishes_the_effective_lifespan_at_its_realm() -> void:
	var baseline := RaceCatalog.instance().race_definition(&"commonborn").lifespan
	for tier in RealmLifespan.AUTHORED_TIERS:
		var realm := _a_realm_at_tier(tier)
		if realm == null:
			continue
		var actor := _body_at(&"commonborn", realm.id)
		assert_almost_eq(
			actor.stats.derived(RaceStats.LIFESPAN),
			_table().effective_days(baseline, tier),
			"race_lifespan at tier %d" % tier,
			0.01
		)


## The published stat and the core read are the SAME number, so the one
## multiplication cannot be re-done on the way out. If a future provider multiplied
## by the tier a second time this fails while every core assertion above still
## passes.
func test_the_provider_and_the_core_read_agree() -> void:
	var baseline := RaceCatalog.instance().race_definition(&"tidecaller").lifespan
	for realm_id in [&"qi_refining", &"spirit_sea", &"earth_immortal", &"primordial_origin"]:
		var actor := _body_at(&"tidecaller", realm_id)
		var published := actor.stats.derived(RaceStats.LIFESPAN)
		assert_almost_eq(
			published, _table().effective_lifespan_for(actor), "one number at %s" % realm_id
		)
		# A MORTAL realm stands on the neutral row, so its published number IS the
		# authored baseline. Asserting otherwise would demand the one multiplier that
		# is exactly 1.0 be something else. The tiers that must differ are the ones the
		# table actually scales, so the difference is asserted from Spirit upward.
		var tier := RealmDefaults.ladder().tier_of(realm_id)
		assert_eq(
			published != baseline,
			tier != RealmDefaults.MORTAL,
			(
				"only a tier above MORTAL departs from the baseline, and %s is tier %d"
				% [realm_id, tier]
			)
		)


## An actor with no path at all stands on no realm, which reads as a MORTAL body —
## the neutral row — and an actor with no body plan has no life to scale. Neither
## is a silent zero: `0.0` for a missing baseline is honest (there is no body),
## while `0.0` for a mortal body would be a death nobody authored.
func test_no_realm_is_the_mortal_baseline_and_no_body_is_no_life() -> void:
	var actor := Actor.new(&"pathless")
	assert_almost_eq(_table().effective_lifespan_for(actor), 0.0, "no body plan, no lifespan")
	RaceApi.set_race(actor, &"commonborn")
	assert_almost_eq(
		_table().effective_lifespan_for(actor),
		RaceCatalog.instance().race_definition(&"commonborn").lifespan,
		"a body plan and no realm is the authored mortal baseline",
		0.01
	)


# --- The two invariances ------------------------------------------------------


## `RealmLifespan` must be invariant under an authored MAGNITUDE: rewrite a
## `RealmDef.power` and the lifespan ladder is unchanged. `power` is the shared
## combat multiplier (`realm_power_table.tres`) and has nothing to say about how
## long a body lives; if this ever fails, the lifespan has started tracking
## strength, which is the ADR 0066 confusion wearing a different hat.
##
## Restored BEFORE the assertion, so a failure here cannot leak a mutated ladder
## into whichever suite runs next and turn one failure into three.
func test_the_ladder_is_invariant_under_the_authored_realm_power() -> void:
	var realm := RealmDefaults.ladder().realm(&"earth_immortal")
	assert_ne(realm, null, "the probe realm is on the ladder")
	if realm == null:
		return
	var before := _every_multiplier()
	var power_before := realm.power
	assert_eq(
		power_before != 0.0, true, "the probe power is non-zero, or the rewrite proves nothing"
	)
	realm.power = power_before * 7.5
	var after := _every_multiplier()
	realm.power = power_before
	assert_eq(after, before, "a retuned RealmDef.power does not move the lifespan ladder")


## And invariant under the authored RATE. `RATE_STEP` is the curve that once made
## a single breakthrough worth more than everything else combined (ADR 0066); a
## lifespan computed from it would be `1.02^ordinal` days, which is both the wrong
## kind of number and two orders of magnitude too small.
##
## **`RATE_STEP` is a `const`, and a `const` is the one thing a test cannot
## rewrite** without editing a file another agent may be reading — GDScript has
## no const-patch API. So this states exactly what it can prove and refuses to
## fake the rest.
##
## It used to end on `assert_eq(_every_multiplier(), before, ...)`, which compares
## a value against itself with nothing in between and can never fail — the
## `assert_eq(x, x)` shape `test_time_ladder.gd` had already removed from itself.
## What is left is the half that IS provable: the rate step is authored at the
## value this repo documents, and **no lifespan multiplier is reachable from it** —
## every authored row differs from every `RATE_STEP^ordinal` on the whole ladder,
## which is the numeric half of ADR 0169's separation and is checked here rather
## than asserted in a comment. The full independence sweep is
## `test_the_two_ladders_share_no_number` beside it.
func test_the_ladder_is_invariant_under_the_authored_rate_step() -> void:
	assert_almost_eq(RealmRate.RATE_STEP, 1.02, "the authored rate step, exactly", 0.0)
	var rows := _rows()
	var ladder := RealmDefaults.ladder()
	for tier in rows.keys():
		for ordinal in ladder.size():
			# Ordinal 0 is skipped for the reason its sibling test gives: `RATE_STEP^0`
			# is 1.0 and so is the Mortal row, which is neutral arithmetic rather than a
			# shared authorship.
			if ordinal == 0:
				continue
			assert_eq(
				is_equal_approx(float(rows[tier]), RealmRate.factor(ladder.realms()[ordinal].id)),
				false,
				"tier %d is not reachable from the rate at ordinal %d" % [tier, ordinal]
			)


## The two ladders are INDEPENDENT: no lifespan row equals any power of the rate
## at any of the 30 realms, and no row equals `RATE_STEP^tier`. 124 comparisons —
## the numbers ADR 0169 and `AGENTS.md:141` say may never coincide.
func test_the_two_ladders_share_no_number() -> void:
	var rows := _rows()
	var ladder := RealmDefaults.ladder()
	for tier in rows.keys():
		var lifespan := float(rows[tier])
		assert_eq(
			lifespan != pow(RealmRate.RATE_STEP, float(tier)),
			true,
			"tier %d is not RATE_STEP^tier" % tier
		)
		for ordinal in ladder.size():
			# Ordinal 0 is EXCLUDED, and the reason is the point of the whole separation.
			# `RealmRate.factor` at ordinal 0 is `RATE_STEP^0 == 1.0` by definition, and
			# the Mortal lifespan row is `1.0` by definition, so the two coincide
			# ARITHMETICALLY and not by any shared authorship. Asserting they differ would
			# demand the neutral row be something other than neutral, and would fail on a
			# table that is exactly right. What has to hold is that no tier scales the way
			# the rate scales — the shape assertion above, not this numeric one.
			if ordinal == 0:
				continue
			assert_eq(
				not is_equal_approx(lifespan, RealmRate.factor(ladder.realms()[ordinal].id)),
				true,
				"tier %d (%s) is not the rate at ordinal %d" % [tier, lifespan, ordinal]
			)


# --- The source guard ---------------------------------------------------------


## The guard this suite exists for. It fails naming FILE and LINE for every
## declaration of a lifespan multiplier outside `core/realm_lifespan_table.gd`.
##
## A value comparison cannot do this and ADR 0116 has the number: a
## numerically-identical private copy stayed green under every value assertion
## (403 passed / 3 failed, only the structural pins firing). `tools arch` cannot
## either — `BARE_REF_UNITS` excludes `core/` and `modules/*`. So the only way to
## add a second definition is to add one of these lines, and the build then says
## which file and which line.
##
## A NUMERIC VALUE is required, because `RaceStats.LIFESPAN` is a `StringName`
## stat id every provider keys its contribution by, and reading that as a scale
## would make this guard red on its first honest run.
##
## **The AUTHORED BASELINE is exempt by name.** `RaceDef.lifespan`
## (`modules/race/race_def.gd:56`) is the per-race MORTAL figure the four `.tres`
## files author, and ADR 0169 keeps it exactly as authored — the multiplier scales
## it, it does not replace it. A guard that flagged it would demand the baseline
## move into `core/`, which is the opposite of the ADR: the baseline is CONTENT and
## the table is the RULE, and only one of those two is core's to hold.
func test_no_file_but_the_table_declares_a_lifespan_multiplier() -> void:
	var offenders: Array[String] = []
	for path in _source_files(SRC_ROOT):
		if path == SSOT:
			continue
		for declared in _lifespan_declarations(FileAccess.get_file_as_string(path)):
			if AUTHORED_BASELINE.has("%s|%s" % [path, declared]):
				continue
			offenders.append("%s:%s" % [path, declared])
	assert_eq(
		offenders,
		[],
		(
			"a lifespan multiplier outside core/realm_lifespan_table.gd — the lifespan is "
			+ "authored in ONE place (ADR 0169): "
			+ str(offenders)
		)
	)


## The second spelling of the same copy: a tier-keyed TABLE rather than a named
## constant, which is the shape `dual_cultivation` actually shipped — an inline
## literal under a name no constant-shaped pin could see. A row table is a curve
## by another name.
##
## `TechniquePolicy.UNIVERSAL_SLOTS_BY_TIER` is in `src/` right now and is NOT a
## finding: four tiers keyed by tier, but a slot COUNT (0/1/2/3 universal
## technique slots) carrying no lifespan token. The name rule is what keeps it out
## of both this guard and the one above.
func test_no_lifespan_table_is_authored_anywhere_but_the_ssot() -> void:
	var offenders: Array[String] = []
	for path in _source_files(SRC_ROOT):
		if path == SSOT:
			continue
		for hit in _tier_keyed_lifespan_rows(FileAccess.get_file_as_string(path)):
			offenders.append("%s:%s" % [path, hit])
	assert_eq(offenders, [], "a tier-keyed lifespan table outside the one .tres: " + str(offenders))


## ADR 0169's explicit NEGATIVE, made mechanical: a lifespan code path may not
## read a world time-flow. `time_flow_min/max` is authored and dead,
## `InsideWorld.time_flow` is published with zero production readers,
## `WorldState.time_flow_rate` is serialize-only — and the two tier band sets
## COINCIDE at 1-9 / 10-18 / 19-27 / 28-30. That coincidence is exactly what gets
## merged by accident, and `days x (days per day)` is not days.
##
## Exempt: the four files that OWN the field, and this file, which must name the
## tokens to refuse them — a guard that fires on its own documentation is a guard
## nobody trusts.
func test_no_lifespan_code_reads_a_world_time_flow() -> void:
	var offenders: Array[String] = []
	var scanned: Array[String] = []
	for path in _source_files(SRC_ROOT):
		scanned.append(path)
		if path == SSOT or path in WORLD_EXEMPT or path == get_script().resource_path:
			continue
		for hit in _world_time_flow_reads(FileAccess.get_file_as_string(path)):
			offenders.append("%s:%s" % [path, hit])
	assert_eq(
		offenders,
		[],
		(
			"a world time-flow read outside the four files that own it — a lifespan is a "
			+ "MAGNITUDE keyed by REALM tier and never a world RATE (ADR 0169): "
			+ str(offenders)
		)
	)
	# The walk really happened, so the empty offender list is an answer.
	assert_eq(scanned.size() >= SRC_FILE_FLOOR, true, "read %d .gd files" % scanned.size())


## The scan found the tree it claims to cover: a floor, and the two landmarks that
## catch a root that moved or an exemption that no longer exists.
func test_the_walk_actually_reads_the_tree_it_guards() -> void:
	var sources := _source_files(SRC_ROOT)
	assert_eq(
		sources.size() >= SRC_FILE_FLOOR,
		true,
		"read %d .gd under res://src, below the floor of %d" % [sources.size(), SRC_FILE_FLOOR]
	)
	assert_eq(
		sources.has("res://src/app/actor_factory.gd"), true, "and it reaches the composition root"
	)
	assert_eq(sources.has(SSOT), true, "and the file it exempts")


## The exemptions are not vacuous. A file that stopped existing would leave the
## SSOT exemption green over a rule that no longer describes anything — the silent
## all-clear `test_the_backup_guard_actually_reads_the_source_tree` was written to
## kill. So each excluded path is asserted to hold what it is exempt for.
func test_the_exempted_files_really_declare_what_they_are_exempt_for() -> void:
	var source := FileAccess.get_file_as_string(SSOT)
	assert_ne(source, "", "%s is readable, or the exemption is vacuous" % SSOT)
	assert_eq(source.contains("class_name RealmLifespan"), true, "and it is the table class")
	for exempt in WORLD_EXEMPT:
		var text := FileAccess.get_file_as_string(exempt)
		assert_ne(text, "", "%s is readable, or the exemption is vacuous" % exempt)
		assert_eq(_world_time_flow_reads(text).size() > 0, true, "%s declares time_flow" % exempt)


# --- The red paths, proven ON FIXTURES ----------------------------------------


## "A green guard is not a tested guard" (`AGENTS.md:82`, INC-0016). The fixture is
## a STRING, so no test in this suite mutates a file another agent may be editing
## (INC-0016, INC-0007) and the detector cannot go red for a reason unrelated to
## what it watches.
##
## The shapes are the ways a copy actually arrives: a `const`, a differently
## spelled `const` beside it, and an inline tier-keyed table under a
## lifespan-shaped name.
func test_the_detector_fires_on_a_forged_second_copy() -> void:
	var forged := (
		"\n"
		. join(
			[
				"class_name Forged",
				"extends RefCounted",
				"",
				"const LIFESPAN_SCALE := 10.0",
				"const TIDE_CALLER_LIFESPAN_MULTIPLIER := 100.0",
				"var tier_lifespan := {1: 1.0, 2: 10.0, 3: 100.0, 4: 1000.0}",
				"",
				"func _init() -> void:",
				"	pass",
			]
		)
	)
	var flagged := _lifespan_declarations(forged)
	assert_eq(flagged.size(), 2, "two constants, one hit each: %s" % str(flagged))
	assert_eq(flagged[0], "4|LIFESPAN_SCALE", "named by its ORIGINAL line and its name")
	assert_eq(flagged[1], "5|TIDE_CALLER_LIFESPAN_MULTIPLIER", "a longer name is the same copy")
	var rows := _tier_keyed_lifespan_rows(forged)
	assert_eq(rows.size(), 1, "and the tier-keyed table is found: %s" % str(rows))
	assert_eq(String(rows[0]).contains("tier_lifespan"), true, "named by what it is")


## The guard must be SILENT on prose and on vocabulary that merely LOOKS like a
## scale. A docblock is allowed to name `LIFESPAN_SCALE` while explaining why
## nothing declares one — which is what `core/realm_lifespan_table.gd` and this
## file both do — and a guard that failed on the explanation would teach the next
## agent to write a worse one.
func test_the_detector_is_silent_on_prose_and_on_the_real_neighbours() -> void:
	var documented := (
		"\n"
		. join(
			[
				"## This file must never declare `LIFESPAN_SCALE`; core owns it.",
				"## Twenty more lines would say LIFESPAN_MULTIPLIER again.",
				"const UNITS_PER_TURN := 3  # LIFESPAN is quoted here only, not declared",
				'var label := "LIFESPAN_SCALE is a magnitude"',
			]
		)
	)
	assert_eq(
		_lifespan_declarations(documented), [], "prose and string contents are not declarations"
	)
	assert_eq(_tier_keyed_lifespan_rows(documented), [], "nor is a quoted tier table one")
	# `RaceStats.LIFESPAN` is a `StringName` stat id, and it ships in `src/` right
	# now, so this is a real file and not only a fixture.
	assert_eq(
		_lifespan_declarations(FileAccess.get_file_as_string("res://src/modules/race/stats.gd")),
		[],
		"the module's own stat id is not a multiplier, however much it looks like one"
	)
	# And the three legitimate `SCALE` numbers the vocabulary deliberately excludes.
	var neighbour := "\n".join(
		["const PERCENT_SCALE := 100.0", "const SCALE_VERSION := 1", "const UNSCALED := 0.25"]
	)
	assert_eq(
		_lifespan_declarations(neighbour), [], "a name carrying no lifespan token is not a lifespan"
	)
	assert_eq(
		_tier_keyed_lifespan_rows(
			FileAccess.get_file_as_string("res://src/modules/techniques/technique_policy.gd")
		),
		[],
		"a tier-keyed slot COUNT is not a lifespan, and stays out of the report"
	)


## The world-read guard's own red path, paired with the exemptions it hands out.
## Without this the exemption above is untested: a guard that never fires proves
## nothing about the vocabulary it is written to refuse.
func test_the_world_read_detector_fires_on_an_unnamed_read() -> void:
	var stolen := (
		"\n"
		. join(
			[
				"extends RefCounted",
				"",
				"## a comment naming it is not a read",
				"func lifespan_of(actor: Actor) -> float:",
				"	var flow: float = actor.world.time_flow_rate",
				"	return flow * 36500.0",
			]
		)
	)
	assert_eq(
		_world_time_flow_reads(stolen),
		["5|time_flow_rate"],
		"a world rate read is found and named by its ORIGINAL line, comment included"
	)
	assert_eq(
		_world_time_flow_reads("\treturn world.time_flow_min"),
		["1|time_flow_min"],
		"and so is the authored band"
	)
	assert_eq(
		_world_time_flow_reads("## time_flow_rate is named here"), [], "and a comment is not a read"
	)


## Every token in each vocabulary must actually RECOGNISE something, or the list
## has rotted into tokens that match nothing — a token that silently stopped
## matching leaves this green on the first entries and red on whichever one
## somebody edited, which is the quiet version of the ADR 0116 failure.
func test_the_detector_recognises_every_shape_the_adrs_name() -> void:
	for token in LIFESPAN_TOKENS:
		assert_eq(
			_lifespan_declarations("\tconst %s := 10.0" % token).size(),
			1,
			"%s is a shape this guard recognises, or the vocabulary has rotted" % token
		)
	for token in WORLD_TOKENS:
		assert_eq(
			_world_time_flow_reads("\tvar x = world.%s" % token).size(),
			1,
			"%s is a shape this guard recognises, or the vocabulary has rotted" % token
		)


# --- Internals ----------------------------------------------------------------


## The shipped table. Loaded rather than reached through `RealmDefaults.LIFESPAN`
## so this suite fails if the preload is removed from `realm_defaults.gd`, rather
## than reading a null and passing every assertion above it vacuously.
func _table() -> RealmLifespan:
	return load("res://src/core/realm_lifespan_table.tres") as RealmLifespan


## The authored rows as `{tier: float}`, so every shape assertion above reads the
## `.tres` and not a literal pasted here.
func _rows() -> Dictionary:
	var table := _table()
	assert_ne(table, null, "the shipped .tres loads")
	if table == null:
		return {}
	var out: Dictionary = {}
	for tier in table.multipliers.keys():
		out[int(tier)] = float(table.multipliers[tier])
	return out


## Every authored multiplier in tier order, so the invariance tests can compare
## the WHOLE ladder with one `assert_eq` instead of four.
func _every_multiplier() -> Array[float]:
	var rows := _rows()
	var out: Array[float] = []
	for tier in range(MORTAL, TRANSCENDENT):
		out.append(float(rows.get(tier, -1.0)))
	return out


## A realm on the ladder at `tier`, read off the ladder rather than pasted — the
## tier bands are authored data (`realm_defaults.gd:7-10`) and a band change must
## not require editing this suite.
func _a_realm_at_tier(tier: int) -> RealmDef:
	var realms := RealmDefaults.ladder().tier_realms(tier)
	assert_eq(realms.size() > 0, true, "the ladder authors realms at tier %d" % tier)
	return realms[0] if realms.size() > 0 else null


## An actor holding `race_id` as its body plan and standing on `realm_id`, which is
## the exact shape `RaceApi.attach` plus `Actor.set_path` produce.
func _body_at(race_id: StringName, realm_id: StringName) -> Actor:
	var actor := Actor.new(&"lifespan_probe")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	actor.set_path(PathState.new(&"qi_cultivation", realm_id))
	return actor


## Every `.gd` under `root`, walked by `ContentScan` so the depth cap is the
## repo's and not this guard's (`content_scan.gd:9-14`). The suffix is EXPLICIT —
## its default is `.tres`, which is the trap `test_save_envelope.gd:380-398`
## documented at length.
func _source_files(root: String) -> Array[String]:
	return ContentScan.files_under(root, ".gd")


## Every declared lifespan multiplier in `source`, as `"<line>|<NAME>"`, comments
## stripped. The line number is the ORIGINAL one: comments are removed before the
## scan, so an index into the stripped text would point at the wrong line, and a
## guard that names the wrong line is a guard nobody can act on.
##
## **`_code_only`, not a raw substring.** The tokens this guard hunts for are named
## in prose by the very files it reads — `core/realm_lifespan_table.gd` explains
## `LIFESPAN_SCALE` in its own docstring while declaring none — so a raw scan
## reports correct code as an offence. Stripping whole-line comments, trailing `#`
## comments and the contents of any `"""` block, the way
## `test_time_ladder_single_source.gd:869-910` does it, is what makes this a
## source-shape guard rather than a second parser.
func _lifespan_declarations(source: String) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1)).strip_edges()
		var name := _declared_name(line)
		if name == "" or not _is_lifespan_shaped(name) or not _is_numeric_value(line):
			continue
		found.append("%d|%s" % [_line_of(entry, separator), name])
	return found


## Every line of `source` that DECLARES something, and the name it binds.
##
## `const`, `static const`, `@export var` and a bare `var` all count, plus a
## plain `NAME := ...` inference — because a private copy may be written as any
## of them, and restricting this to `const` is the mistake ADR 0116's fourth copy
## records: the shape that actually shipped had no `const` in it at all.
func _declared_name(line: String) -> String:
	var prefixes := PackedStringArray(
		["static const ", "const ", "@export var ", "@export var ", "static var ", "var "]
	)
	for prefix in prefixes:
		if line.begins_with(prefix):
			return _bound_name(line.substr(prefix.length()))
	# A plain inferred local or member — but not an assignment to an existing
	# field (`world.time_flow = x` binds nothing) and not an equality test.
	var at := line.find(":=")
	if at <= 0:
		return ""
	return _bound_name(line.substr(0, at))


## The identifier a declaration binds, or `""`. Read up to the first space,
## colon, dot or equals so `NAME := 1.0`, `NAME: float = 1.0` and `NAME = 1` all
## yield `NAME`.
##
## **No `is_valid_identifier()` filter, and that is the fix.** The filter looked
## defensive and was the reason this detector found nothing: a `String` built by
## stripping a line and slicing it keeps its own encoding, and `is_valid_identifier()`
## rejected it, so every fixture and every real declaration came back as `""` and the
## guard reported zero hits — a guard that cannot see its own subject. The parse is
## already bounded by the stop set below, so a name cannot contain anything a
## declaration could not bind. `test_time_ladder_single_source.gd` reads it the same
## way, and it is the version that has actually caught a copy.
func _bound_name(text: String) -> String:
	var stop := text.length()
	for index in text.length():
		var character := text[index]
		if character == " " or character == ":" or character == "=" or character == ".":
			stop = index
			break
	return text.substr(0, stop).strip_edges()


## Whether the right-hand side of a declaration begins with a number, a sign or a
## decimal point. Everything else — `&"race_lifespan"`, a reference to
## `RealmLifespan`, an array, an expression — is declined, and that is what keeps
## the module's own stat id out of the report. A first-character test rather than
## `is_valid_float()`, for the reason `test_time_ladder_single_source.gd:962`
## gives: it accepts what a table is written as and declines the arithmetic a
## later author might reach for, which belongs in the `.tres` like any other
## authored number.
##
## ## The `:=` operator is TWO characters, and reading one of them is what
## ## silenced this guard
##
## `find(":=")` returns the index of the COLON, so skipping `at + 1` left a leading
## `=` in the value: `const LIFESPAN_SCALE := 10.0` was read as the value `= 10.0`,
## whose first character is `=`, which no number starts with — so it was declined
## by the very rule above. Every `:=` declaration in the tree and in every fixture
## was declined the same way, which is why `_declared_name`, `_bound_name` and
## `_is_lifespan_shaped` all returned the right answers on a multi-line file while
## the guard reported ZERO hits on a single-line one. An off-by-one in the
## separator, in the only function that reads a VALUE.
func _is_numeric_value(line: String) -> bool:
	var inferred := line.find(":=")
	var equals := line.find("=")
	var at := -1
	var past := 1
	if inferred >= 0 and (equals < 0 or inferred < equals):
		at = inferred
		past = 2
	elif equals >= 0:
		at = equals
	if at < 0:
		return false
	var value := line.substr(at + past).strip_edges()
	if value.is_empty() or value == ":":
		return false
	var first := value[0]
	return (first >= "0" and first <= "9") or first == "-" or first == "+" or first == "."


## Whether a declared NAME carries any of `LIFESPAN_TOKENS`, case-insensitively —
## a lower-case `lifespan_scale` is the same declaration with different manners.
func _is_lifespan_shaped(name: String) -> bool:
	var upper := name.to_upper()
	for token in LIFESPAN_TOKENS:
		if upper.contains(token):
			return true
	return false


## Every line of `source` that declares a TIER-KEYED lifespan table, as
## `"<line>|<name>"`. The row shape is what a copy written as an inline literal
## takes — `{1: 1.0, 2: 10.0, 3: 100.0, 4: 1000.0}` — and it is the shape
## `dual_cultivation` actually shipped, which no constant-shaped pin would see.
##
## Two deliberate limits, both inherited rather than reinvented: the literal must
## CLOSE on its own line (a multiline row table is a review finding, not a blind
## spot worth a parser in a source guard — `test_time_ladder_single_source.gd:20`
## says the same), and the name must carry a lifespan token, which is what keeps
## the four tier-keyed SLOT budgets in the tree out of this report.
func _tier_keyed_lifespan_rows(source: String) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1)).strip_edges()
		if not line.ends_with("}"):
			continue
		var braced := line.rfind("{")
		if braced < 0:
			continue
		if not _is_tier_keyed(line.substr(braced + 1, line.length() - braced - 2)):
			continue
		var name := _declared_name(line.substr(0, braced).strip_edges())
		if name == "" or not _is_lifespan_shaped(name):
			continue
		found.append("%d|%s" % [_line_of(entry, separator), name])
	return found


## Whether the inside of a brace holds at least two INTEGER-KEYED rows. Two is
## enough: a one-entry literal is a value, and a dictionary keyed by names is a
## different shape entirely — `realm_power_table.tres` is one of those, and it is
## data.
func _is_tier_keyed(inside: String) -> bool:
	var rows := 0
	for row in inside.split(","):
		var at := row.find(":")
		if at > 0 and row.substr(0, at).strip_edges().is_valid_int():
			rows += 1
	return rows >= 2


## Every line of `source` whose CODE reads a world time-flow, as
## `"<line>|<token>"`. Read from the stripped text for the reason every other scan
## here is: the token appears in the docstring of four files under `res://src`,
## and an unstripped scan reports correct code as an offence in all of them.
##
## One hit per line: a line reading both a field and its local repeats the same
## violation, and naming it twice would pad the report rather than add
## information.
func _world_time_flow_reads(source: String) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1))
		for token in WORLD_TOKENS:
			if line.contains(token):
				found.append("%d|%s" % [_line_of(entry, separator), token])
				break
	return found


## Every line of `source` that CODE occupies, as `"<original line number>|<line>"`,
## with every comment removed. Line by line because a block comment's middle
## lines are the ones that mislead; character by character within the line
## because a trailing `#` sits after real code on the same row. `"""` blocks are
## dropped too.
##
## Taken from `test_time_ladder_single_source.gd:869-910` rather than written a
## third time: a fourth copy of a comment stripper is a fourth thing to keep
## correct, and the one that shipped is the one that had to survive being read.
func _code_only(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var in_block := false
	for index in lines.size():
		var line := String(lines[index])
		if line.strip_edges().begins_with("#"):
			continue
		var kept := ""
		var at := 0
		var quote := ""
		while at < line.length():
			var character := line[at]
			if in_block:
				if line.substr(at, 3) == '"""':
					in_block = false
					at += 3
				else:
					at += 1
				continue
			if quote == "" and line.substr(at, 3) == '"""':
				in_block = true
				at += 3
				continue
			if quote == "" and (character == '"' or character == "'"):
				quote = character
				at += 1
				continue
			if quote != "":
				if character == "\\":
					at += 2
					continue
				if character == quote:
					quote = ""
				at += 1
				continue
			if character == "#":
				break
			kept += character
			at += 1
		out.append("%d|%s" % [index + 1, kept])
	return out


## The original line number carried by a `"<line>|<rest>"` entry.
func _line_of(entry: String, separator: int) -> int:
	return int(String(entry.substr(0, separator)))
