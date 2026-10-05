extends "res://tests/core/time_ladder_ssot_base.gd"

## ## This file holds the DETECTOR half of the single-source guard
##
## The tree census, the walk's own floors, and the wall-clock exemption live in
## `test_time_ladder_single_source.gd`; the vocabulary they share — the `const`
## tables, the `_code_only` stripper and every classifier below — is ONE copy in
## `time_ladder_ssot_base.gd`, which this suite `extends`. A second copy of the
## classifier would drift from the census and the drift would be invisible: both
## suites would still be green against their own private rule.
##
## What is here is the red path proven on STRINGS rather than on the real tree —
## the forged second copy, one fixture per token in `TIME_TOKENS`, every near-miss
## of every clause of `_is_clock_duplicate`, and the prose/`MAX_`/string-value
## cases that keep the guard from crying wolf. Nothing below reads the shipped
## tree except the gestation-rename case, which exists because that site was
## FIXED rather than waived and a "simplification" back to `SECONDS_PER_*` would
## put a turn-tier duration back on the world clock.


## ## The red path, proven ON A FIXTURE rather than on the real tree
##
## "A green guard is not a tested guard" (`AGENTS.md:82`, INC-0016) — that rule is written
## for `tools/selftest_cases.py`, which points each validator at a broken fixture and
## asserts it still goes red. This is the GDScript half of the same idea. It matters here
## more than usual: the guard above is green on a tree whose only sin is a constant
## another agent is still migrating, so the ONLY way to know the detector works is to feed
## it something forbidden and watch it name the line.
##
## The fixture is a STRING rather than a file on disk, so no test in this suite mutates the
## repository and the detector can never go red for a reason unrelated to what it watches.
func test_the_detector_fires_on_a_forged_second_copy() -> void:
	# The forged name is the SSOT's OWN name, so this fixture does not depend on the
	# period-count rule at all: it is the pre-existing red path, unchanged by it. The
	# second spell of the ratio is added below because a duplicate has more than one
	# name and the guard has to catch whichever a copy is pasted under.
	var forged := (
		"\n"
		. join(
			[
				"class_name Forged",
				"extends RefCounted",
				"",
				"const PERIOD_SECONDS := 120.0",
				"",
				"func _init() -> void:",
				"\tpass",
			]
		)
	)
	var flagged := _time_constants(forged)
	assert_eq(flagged.size(), 1, "one declaration, one hit: %s" % str(flagged))
	assert_eq(flagged[0], "4|PERIOD_SECONDS", "named by its ORIGINAL line and by its name")
	assert_eq(
		String(flagged[0]).ends_with("PERIOD_SECONDS"),
		true,
		"and it is named, which is what the build message needs to say"
	)
	# And the copy this guard was written for, under the spelling the ratio rule reads.
	assert_eq(
		_time_constants("\tconst PERIOD_SECONDS := 120.0\n\tconst SECONDS_PER_PERIOD := 120.0\n"),
		["1|PERIOD_SECONDS", "2|SECONDS_PER_PERIOD"],
		"both spellings of the base ratio are the same duplicate and both are named"
	)


## Every token in the set must actually RECOGNISE a declaration, or the vocabulary has
## rotted into a list that matches nothing. One fixture per token, each a single `const`
## line: a token that silently stopped matching would leave this test green on the first
## ones and red on whichever one somebody edited, which is the quiet version of the
## ADR 0116 failure.
##
## **Recognition, not rejection.** Read through `_classified_constants(..., false)` — the
## DECLINED half — because a token may be in this set precisely because it is classified
## rather than reported, and `_PERIODS` is exactly that: a count of periods is a count and
## not a ratio. Asserting every token produced a *duplicate* demanded that the vocabulary
## reject the shapes it is written to recognise, which is the mirror of the ADR 0116
## failure rather than the guard against it.
func test_the_detector_recognises_every_shape_the_adr_names() -> void:
	for token in TIME_TOKENS:
		# `SECONDS_PER` is a PREFIX token, so the name is completed the way a real
		# declaration spells it rather than left as the bare prefix. `PERIODS_PER_` is
		# deliberately NOT in `TIME_TOKENS` (a period divisor is one unit, not a ratio),
		# so no fixture completes it -- `test_every_new_exemption_still_catches_its_near_
		# miss` covers that shape from the other side, where it must stay caught.
		var spell: String = "SECONDS_PER_PERIOD" if token == "SECONDS_PER" else token
		var line := "\tconst %s := 1.0" % spell
		var recognised := _classified_constants(line + "\n", SRC_ROOT, false)
		var reported := _classified_constants(line + "\n", SRC_ROOT, true)
		assert_eq(
			recognised.size() + reported.size(),
			1,
			"%s is a shape this guard classifies, or the vocabulary has rotted" % token
		)
	# The one carve-out: a per-call ceiling is not a cadence (ADR 0173:88). Declined
	# TWICE over now -- `PERIODS_PER_` no longer matches, and `_PERIODS` is a count rather
	# than a duration -- which is what "declined by rule, not by allowlist" has to mean.
	assert_eq(
		_time_constants("\tconst MAX_PERIODS_PER_PULL := 8\n"),
		[],
		"a per-call ceiling is declined, not allow-listed by name"
	)


## The `MAX_` carve-out must not widen into a blanket prefix waiver. It is scoped to
## period COUNTS, so a `MAX_` carrying a seconds-shaped token is still a duration and is
## still reported -- `MAX_COLLAPSE_HELD := 3600.0` is row four of ADR 0173's own migration
## table, and an earlier version of this guard waved it through by prefix alone.
func test_a_max_prefix_waives_a_period_ceiling_but_never_a_window_in_seconds() -> void:
	assert_eq(
		_time_constants("\tconst MAX_COLLAPSE_HELD := 3600.0\n"),
		["1|MAX_COLLAPSE_HELD"],
		"a held window in seconds is a duration, MAX_ prefix notwithstanding"
	)
	assert_eq(
		_time_constants("\tconst MAX_SECONDS_PER_DAY := 3600.0\n"),
		["1|MAX_SECONDS_PER_DAY"],
		"a MAX_ carrying a seconds ratio is a ratio, whatever its prefix"
	)
	assert_eq(
		_time_constants("\tconst MAX_TEACH_PERIODS := 8\n"),
		[],
		"while a per-call period ceiling stays declined"
	)


## The reason `_code_only` exists, asserted as behaviour rather than asserted as a fact.
## Each of these lines NAMES a forbidden token and declares nothing: the first two in
## whole-line `##` documentation (the shape that made `save_clock.gd` unreadable to a raw
## scan), the third as a trailing comment on a line that does declare something else, and
## the fourth inside a string literal. A guard that reported any of them would be a guard
## that fails on its own documentation, which is the sentence nobody trusts a guard more
## than any other in this repo.
func test_the_detector_is_silent_on_prose_and_on_comment_carried_tokens() -> void:
	var documented := (
		"\n"
		. join(
			[
				"## This file must never declare `PERIOD_SECONDS`; the SSOT owns it.",
				"## Another twenty lines of explanation would say TICK_INTERVAL again.",
				'const HELD := &"held_office"',
				"const CADENCE := 3  # not a cadence: SECONDS_PER is quoted here only",
				'var label := "PERIOD_SECONDS is a ratio"',
			]
		)
	)
	assert_eq(_time_constants(documented), [], "prose and string contents are not declarations")
	assert_eq(_wall_clock_reads(documented), [], "nor is a clock named in a comment")


## The wall-clock detector's own red path, and the exemption it is paired with. Without
## this the exception above is untested: a guard that never fires proves nothing about the
## one line it is willing to let through.
func test_the_wall_clock_detector_fires_on_an_unnamed_read() -> void:
	var stolen := (
		"\n"
		. join(
			[
				"extends RefCounted",
				"",
				"## a comment naming it is not a read",
				"func stamp() -> int:",
				"\treturn Time.get_ticks_usec()",
			]
		)
	)
	assert_eq(_wall_clock_reads(stolen).size(), 1, "a clock read is found")


## A `const` naming a token but holding something that is not a number is not a cadence.
## `NO_PERIODS := "no_periods"` is a refusal id that happens to contain the word; the
## numeric-literal half of the rule is what keeps this guard from crying wolf on its
## first honest run, and losing that half would make it unusable rather than strict.
func test_a_string_valued_constant_named_like_a_cadence_is_not_a_cadence() -> void:
	assert_eq(
		_time_constants('\tconst NO_PERIODS := "no_periods"\n'),
		[],
		"a refusal id is not a cadence, however much it looks like one"
	)
	assert_eq(
		_time_constants('\tconst R_PERIOD_NOT_ELAPSED := &"period_not_elapsed"\n'),
		[],
		"nor is a StringName reason id"
	)
	# And the SSOT's own non-numeric neighbours stay out for the same reason.
	assert_eq(_time_constants('\tconst BASE := &"period"\n'), [], "nor is the base row's id")
	assert_eq(
		_time_constants('\tconst BASE := &"period"\n\tconst PERIOD_SECONDS := 120.0\n').size(),
		1,
		"while the numeric declaration beside it is still found"
	)


func test_every_exempted_shape_is_the_whole_set_not_the_first_ten_hits() -> void:
	var census := {}
	for path in _source_files(SRC_ROOT) + _source_files(TESTS_ROOT):
		if path == SSOT:
			continue
		# `false` — the census is of what the guard RECOGNISES AND DECLINES, which is the
		# half `EXPECTED_NON_CLOCK` describes. Reading the duplicates instead compared two
		# empty sets and passed vacuously.
		var found := _classified_constants(FileAccess.get_file_as_string(path), path, false)
		if not found.is_empty():
			census[path] = found
	var actual := {}
	for path in census:
		actual[path] = _names_only(census[path])
	var expected := {}
	for path in EXPECTED_NON_CLOCK:
		expected[path] = _names_only(EXPECTED_NON_CLOCK[path])
	# **The census must not be empty.** A guard whose exemption table is empty is a guard
	# that classifies nothing and exempts everything, and the assertion below would pass on
	# it. This is the shape of `INC-0016`: a guard nobody has seen reject anything.
	assert_eq(actual.size() > 0, true, CENSUS_EMPTY_MESSAGE)
	assert_eq(
		actual,
		expected,
		(
			"the guard's exemptions are a census, not an allowance list — a declaration "
			+ "with no row here is a shape nobody classified (ADR 0173): %s" % str(actual)
		)
	)


## The DECLARED NAMES in a set of `"<line>|<name>"` entries, sorted, with the line numbers
## dropped.
##
## **Compared by name, never by line.** A census pinned to line numbers is a census that
## a concurrent agent invalidates by adding a comment above a constant — which is not a
## clock defect, and it made this test red for a reason that has nothing to do with the
## guard. The names are what the classification is about; the line is where it happened to
## live when the census was written, and `test_the_census_still_names_a_real_line` keeps
## the line reporting available to a human reading a failure.
## past the shapes it was written for, which is the `MAX_` lesson this file already paid.
func test_every_new_exemption_still_catches_its_near_miss() -> void:
	# Clause 1 catches `SECONDS_PER`, and clauses 2 to 5 must never reach it. Two
	# spellings of the base ratio, each with an exemption's whole shape wrapped round it.
	assert_eq(
		_time_constants("\tconst SECONDS_PER_PERIOD := 120.0\n"),
		["1|SECONDS_PER_PERIOD"],
		"a seconds-per-period ratio is a ratio, and no suffix may waive it"
	)
	assert_eq(
		_time_constants("\tconst SECONDS_PER_PERIOD_TURN := 120.0\n"),
		["1|SECONDS_PER_PERIOD_TURN"],
		"nor may the turn suffix, which is a unit and not an alibi"
	)
	assert_eq(
		_time_constants("\tconst SECONDS_PER_PERIODS := 120.0\n"),
		["1|SECONDS_PER_PERIODS"],
		"nor may a `_PERIODS` spelling, which reads as a count and measures seconds"
	)
	# Clause 2 is the `_TURN` unit suffix, beside a bare `SECONDS_PER_*` in the same file.
	assert_eq(
		_time_constants("\tconst SECONDS_PER_GESTATION_DAY_TURN := 1.0\n"),
		[],
		"the turn tier is measured against turns, which no magnitude of world time is"
	)
	# Clause 3 is `_PERIODS`, read backwards. The near-miss is the same word read
	# forwards, which is a divisor of one rather than a count of it.
	assert_eq(
		_time_constants("\tconst AUTOSAVE_PERIODS := 12\n"),
		[],
		"how many periods between writes is a count, which is the exemption"
	)
	assert_eq(
		_time_constants("\tconst PERIODS_PER_SECOND := 0.5\n"),
		[],
		"and how many per second is a divisor of one, declined for the same reason"
	)
	assert_eq(
		_time_constants("\tconst MIN_PERIODS := 1\n"),
		["1|MIN_PERIODS"],
		"while a `MIN_` on a bare count is a bound and stays a bound, prefix or not"
	)
	# Clause 4 is `UI_ROOT`: a presentation step, beside a ratio in the same layer.
	assert_eq(
		_time_constants("\tconst ARM_TICK := 2.0\n", "%s/screens/a_screen.gd" % UI_ROOT),
		[],
		"a screen sizes a step against authored content, never against the clock"
	)
	assert_eq(
		_time_constants(
			"\tconst SECONDS_PER_PERIOD := 120.0\n", "%s/screens/a_screen.gd" % UI_ROOT
		),
		["1|SECONDS_PER_PERIOD"],
		"which is not a licence for a screen to carry a ratio either"
	)
	assert_eq(
		_time_constants("\tconst ARM_TICK := 2.0\n"),
		["1|ARM_TICK"],
		"and the same name outside ui/ is a cadence nobody has classified"
	)
	# Clause 5 is the `.tres` floor, beside the same words with a ceiling's prefix, with
	# none, and with a ratio-shaped name.
	assert_eq(
		_time_constants("\tconst MIN_INTERVAL := 1.0\n"),
		[],
		"a floor on what a .tres may ask for is a bound on authored data"
	)
	assert_eq(
		_time_constants("\tconst MIN_TICK_INTERVAL := 2.0\n"),
		[],
		"and the fallback for one under another name is the same bound"
	)
	assert_eq(
		_time_constants("\tconst MAX_INTERVAL := 1.0\n"),
		["1|MAX_INTERVAL"],
		"a ceiling is a different bound on a different call, and MAX_ is not a floor"
	)
	assert_eq(
		_time_constants("\tconst TICK_INTERVAL := 2.0\n"),
		["1|TICK_INTERVAL"],
		"and the bare span tokens still report outside modules that own a cadence"
	)
	assert_eq(
		_time_constants("\tconst MIN_PERIOD_SECONDS := 1.0\n"),
		["1|MIN_PERIOD_SECONDS"],
		"while a floor ON THE RATIO is the ratio, and no prefix waives it"
	)
	assert_eq(
		_time_constants("\tconst MIN_SECONDS_PER_PERIOD := 120.0\n"),
		["1|MIN_SECONDS_PER_PERIOD"],
		"nor does naming the unit and the floor in one name"
	)


## The renamed constant stays renamed, and the vocabulary that motivated the rename
## still refuses the copy it was right to refuse. A future agent that "simplifies" the
## `_TURN` suffix back to `SECONDS_PER_*` has put a turn-tier duration back into the one
## spelling that means "measured against the world clock", and this is the line that says
## so — there is no exemption to fall back on, because the site was fixed rather than
## waived.
func test_the_gestation_turn_constant_is_named_in_its_unit_and_still_guarded() -> void:
	var status_path := "%s/app/status_loop.gd" % SRC_ROOT
	var status := FileAccess.get_file_as_string(status_path)
	assert_eq(
		_has_entry_named(_time_constants(status, status_path), "SECONDS_PER_GESTATION_DAY"),
		false,
		"the ladder-shaped spelling has not come back (ADR 0173)"
	)
	assert_eq(
		status.contains("const SECONDS_PER_GESTATION_DAY_TURN"),
		true,
		"the renamed declaration is still the one that ships"
	)
	assert_eq(
		_has_entry_named(_time_constants(status, status_path), "MAX_COLLAPSE_HELD"),
		false,
		"and the one status_loop constant that IS a window is still derived, not typed"
	)
