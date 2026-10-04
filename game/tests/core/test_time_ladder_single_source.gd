extends TestCase

## ADR 0173: THE CLOCK IS ONE SINGLE SOURCE OF TRUTH -- and this is the guard that makes
## the migration it decided impossible to undo quietly.
##
## ## Why a value assertion cannot do this job
##
## ADR 0116 is the precedent, and it is the reason this file reads SOURCE rather than
## calling anything. A numerically IDENTICAL private copy of a rate constant stayed green
## under every value assertion ever written against it -- 403 passed, 3 failed, and the
## only three were structural pins. The two `*RealmProfile` curves were copies of
## `RealmRate.RATE_STEP` to the last digit, so `x == x` was the whole comparison.
##
## This program just shipped the same disease in time, twice, in the same week:
## `modules/save/save_clock.gd:34` declared its own `PERIOD_SECONDS := 120.0` beside the
## canonical one in `app/world_pulse.gd:88`, and `SaveClock.pull` counted CALLS instead of
## periods -- autosaving about twelve times a second at 60fps while its own docstring
## promised whole periods. Neither defect is visible to a value check: the copy was equal,
## and the schedule was arithmetic nobody compared against wall time.
##
## `tools arch` cannot see it either. `BARE_REF_UNITS` excludes `modules/*`
## (`AGENTS.md:143`), so a module's private constant reports zero violations and
## `app_state_warnings` never reaches for it. Precedent for the technique is
## `tests/core/test_realm_rate.gd:208-224`, which fails the build naming which module and
## which line the moment a second `const RATE_STEP` appears; this is that guard pointed at
## the clock instead of the rate.
##
## ## COMMENTS ARE STRIPPED BEFORE SCANNING, and that is not a detail
##
## The tokens this guard hunts for are named, in prose, by the very files this guard
## reads. `save_clock.gd`'s own docstring explains that it must not read `Time.get_ticks*`
## and names its copy of the ratio; `world_pulse.gd:28` says "Nothing here reads
## `Time.get_ticks*`". Scanning raw text therefore matches the PROSE and reports correct
## code as an offence. The precedent that settled it is
## `tests/modules/save/test_save_envelope.gd:281-297` -- `test_the_clock_never_reads_a_
## wall_clock_or_declares_a_frame_driver` -- whose comment says it exactly: **"A guard
## that fires on its own documentation is a guard nobody trusts."** This file strips whole
## `#` lines (a block comment's middle lines are the ones that mislead: a file may open
## `##` on line one and keep naming the forbidden token for twenty more), trailing `#`
## comments, and the contents of any `"""` block, so the scan reads CODE.
##
## ## What counts as a declaration here
##
## A `const` whose NAME carries a time-shaped token and whose VALUE is a numeric
## literal. Both halves matter and each refuses a different false positive: the token set
## is the ADR's own vocabulary (`PERIOD_SECONDS`, `SECONDS_PER_*`, `*_PERIODS`,
## `PERIOD_INTERVAL`, `TICK_INTERVAL`, `MIN_INTERVAL`, `MAX_COLLAPSE_HELD`), while the
## numeric-literal requirement leaves a string constant alone -- `NO_PERIODS := "no_periods"`
## is a refusal id that happens to contain the word, and reading it as a cadence would be
## the guard crying wolf on its first honest run.
##
## `const` only, deliberately. A `@export var ... := 1.0` on a `Resource` is AUTHORED
## DATA carrying a default (`TechniqueDef.cooldown`, `StatusDef.tick_interval`), which is
## ADR 0050's per-entity keying and not a clock: it lives in the `.tres` the author edits,
## not in the script. The failure this guard exists for was a `const` in a `.gd`.

const SRC_ROOT := "res://src"
const TESTS_ROOT := "res://tests"

## The ONE allowed declaration site. ADR 0173 moves the base ratio out of
## `app/world_pulse.gd:88` and into `core/time_ladder.gd`, beside `RealmRate` and
## `InstitutionBudget`; `core/` is a layer rather than a module (`tools/arch/rules.py:29`),
## so the canonical home costs zero new arch edges. Allow-listed by name rather than by
## pattern so the exemption is one readable line a reviewer can see and delete.
const SSOT := "res://src/core/time_ladder.gd"

## The one named `Time.get_ticks*` the ADR permits, and why it is not a second clock.
## `app/socket_forge_program.gd:85` passes `Time.get_ticks_usec()` as an IDEMPOTENCY
## STAMP: a uniqueness token making two enchantments inside one tick two requests rather
## than one replay. It is not elapsed time and nothing ever subtracts it, so it cannot
## drift from the clock. ADR 0173 blesses it and states the price of refusing it: a guard
## that turned this line away would push a wall-clock stamp back in somewhere worse, or
## make the request id derive from the very clock it exists to prove independence from.
const IDEMPOTENCY_STAMP := "res://src/app/socket_forge_program.gd"

## Time-shaped tokens, matched case-insensitively against a declared NAME. `TICK` and
## `INTERVAL` are one concept spelled two ways (`TICK_INTERVAL`, `MIN_INTERVAL`), and
## `HELD` covers a window the ADR names in seconds (`MAX_COLLAPSE_HELD`) rather than in
## periods. Ordered longest-first so a report can name the pattern that matched.
const TIME_TOKENS := [
	"PERIOD_SECONDS",
	"PERIOD_INTERVAL",
	"SECONDS_PER",
	"_PERIODS",
	"INTERVAL",
	"TICK",
	"HELD",
]

## `MIN_` is a FLOOR on authored data, and it is the one prefix this guard reads as a
## shape rather than as a name. `MIN_INTERVAL` and `MIN_TICK_INTERVAL` bound what a
## `.tres` may ask for, so the file they would have to agree with is the one being read
## and nothing can drift. `MAX_` is a different bound on a different thing and stays
## reported (`PER_CALL_PREFIX` above).
const FLOOR_PREFIX := "MIN_"

## `MAX_` is a per-call ceiling, not a cadence, and ADR 0173:88 says so in as many words:
## "`MAX_PERIODS_PER_PULL := 8` stays what it always was: a ceiling on ONE CALL, which a
## budget is not." `MAX_TEACH_PERIODS`, `MAX_WAIT_PERIODS` and `MAX_PERIODS_PER_PULL` are
## the same shape, so they are declined by this rule rather than by three more
## allowlist entries.
const PER_CALL_PREFIX := "MAX_"

## The tokens that count PERIODS rather than measure a duration, and therefore the only
## ones `PER_CALL_PREFIX` is allowed to waive. `_PERIODS` is the one shape genuinely
## ambiguous between the two: `AUTOSAVE_PERIODS` and `TREASURY_OPENING_PERIODS` are
## cadences, `MAX_TEACH_PERIODS` is a ceiling, so the waiver is decided by the `MAX_`
## prefix and never by the token alone.
const PERIOD_COUNT_TOKENS := ["_PERIODS"]

## ## The four shapes this guard classifies rather than reports
##
## A time-shaped NAME cannot tell a number that COUNTS the SSOT's own unit from one that
## MEASURES a span in seconds, and the difference is the whole of this guard's subject.
## **A count cannot disagree with a ratio** — converting a count of periods into seconds
## needs seconds, and the unit is already spent — which is `save_clock.gd`'s own rule:
## "**A count, never a duration**", "nothing here knows how long a period is, only how
## many have been handed down".
##
## # 1. `PERIOD_COUNT_TOKENS` (`_PERIODS`) — how many periods. `AUTOSAVE_PERIODS`,
##    `NEAR_PERIODS`, `TREASURY_OPENING_PERIODS`, `MEMBER_DUTY_PERIODS`.
## 2. `UNIT_TURN_SUFFIX` — the COMBAT turn tier, which ADR 0173:63 keeps off the world
##    clock outright ("combat resolves on turns inside one period"). A `_TURN` name is
##    measured against turns, and no magnitude of world time is a turn.
## 3. `UI_ROOT` — a presentation step. `ui/` may not reach the world clock at all
##    (`ui/panels/world_pulse_reader.gd:23`: "No `WorldPulse` id or `PERIOD_SECONDS`
##    literal appears here or anywhere else in `ui/`"), so a seconds constant in a screen
##    is sized against authored content and not copied from the SSOT.
## 4. `AUTHORED_FALLBACKS` — one constant, NAMED rather than tokenised.
##    `environment_field.gd`'s `TICK_INTERVAL` is the value a hazard falls back to when
##    its authored `env_scourge.tres` cannot be read, so it mirrors that file and is
##    reached only on a content gap. **A bare `TICK_INTERVAL` is a genuine cadence shape
##    everywhere else**, so this is a name rather than a token on purpose: a rule that
##    declined every bare span token would waive the world cadences this guard exists to
##    catch. `test_an_authored_fallback_is_named_and_not_a_token` holds that line by
##    reporting the same name anywhere else.
##
## `SECONDS_PER` is declined by NONE of them, which is the invariant that keeps this a
## guard rather than a waiver: **no ratio is ever exempt, whatever it is called or
## wherever it sits.** The one clause that precedes `SECONDS_PER` is `UNIT_TURN_SUFFIX`,
## because a name may both measure seconds AND declare the unit it measures them
## against — which is the whole of `SECONDS_PER_GESTATION_DAY_TURN`.
const UNIT_TURN_SUFFIX := "_TURN"
const NON_CADENCE_TOKENS := ["TICK", "INTERVAL", "HELD"]
const UI_ROOT := "res://src/ui/"
const AUTHORED_FALLBACKS := {"res://src/modules/domain/environment_field.gd": ["TICK_INTERVAL"]}

## The wall-clock read the named exception is about. Spelled without the trailing `*` so
## one token covers `get_ticks_msec`, `get_ticks_usec` and the rest.
const FORBIDDEN_CLOCK := "Time.get_ticks"
## The failure message for an empty exemption census, hoisted so the line fits.
const CENSUS_EMPTY_MESSAGE := (
	"the exemption census is empty, so it would pass on any tree — "
	+ "a guard that classifies nothing"
)
## Floors under the walk, measured 2026-10-04 at 511 `.gd` files in `res://src` and 475
## in `res://tests`. `test_the_walk_actually_reads_the_tree_it_guards` is what turns an
## empty list into a failure rather than an all-clear -- the `SOURCE_FILE_FLOOR`
## argument from `test_save_envelope.gd:414-451`, where a guard that walked `.tres` files
## reported "clean" over an empty file list and a mutation probe left it at 61 passed.
const SRC_FILE_FLOOR := 450
const TESTS_FILE_FLOOR := 400

## ## Every exemption in this guard is a CLASSIFICATION, and this is the census
##
## A guard that grows an exemption and never counts what it exempts is a guard that grows
## an exemption silently. The clauses in `_is_clock_duplicate` are vocabulary rules and
## cannot name a file, so nothing above proves the tree still only carries the shapes it
## carried before — only that no *new* shape appeared. This is that proof: **the whole
## set, asserted by name.** It is deliberately written as data rather than as an
## allowance list, so a declaration a future agent did not add a row for turns the build
## red instead of quietly enlarging an exemption.
##
## `app/status_loop.gd` is the interesting one. It once declared
## `SECONDS_PER_GESTATION_DAY := 1.0`, which this guard is right to read as a ratio — the
## name measured seconds — and it was RENAMED to `_TURN` rather than allow-listed, so the
## unit is now in the name and the census below is the record of that decision.
const EXPECTED_NON_CLOCK := {
	# A policy count of the SSOT's unit, not a cadence the SSOT owns. `save_clock.gd`'s
	# docstring is the rule: "A count, never a duration."
	"res://src/modules/save/save_clock.gd": ["30|AUTOSAVE_PERIODS"],
	# Cadence divisors in period units -- every fourth period, every sixteenth. One unit,
	# so no ratio to disagree with; the nearest a real cadence gets.
	"res://src/app/institution_resolver.gd":
	[
		"64|NEAR_PERIODS",
		"65|DISTANT_PERIODS",
		"66|STRATEGIC_PERIODS",
	],
	# Content durations authored in period units. `institution_resolver.gd:_check_base_row`
	# machine-checks the one of these that has a ladder row to check against.
	"res://src/modules/sect/sect_def.gd": ["39|MEMBER_DUTY_PERIODS"],
	"res://src/modules/sect/sect_founding.gd": ["43|TREASURY_OPENING_PERIODS"],
	# A floor on AUTHORED DATA (`TechniqueDef.upkeep_interval`), and a fallback for an
	# authored one (`env_scourge.tres`). Both are a `.tres` edit by ADR 0090, so neither
	# is the clock and neither could drift from it: the file it would have to agree with is
	# the one being read. A cadence the WORLD runs on never sits in that shape.
	"res://src/modules/techniques/technique_upkeep.gd": ["26|MIN_INTERVAL"],
	"res://src/modules/domain/environment_field.gd": ["326|TICK_INTERVAL"],
	# The COMBAT turn tier. Pregnancy resolves inside one period with the world frozen
	# (ADR 0173:63), so this is a turn-tier value and the `_TURN` says so.
	"res://src/app/status_loop.gd": ["67|SECONDS_PER_GESTATION_DAY_TURN"],
	# A UI presentation step: one button press advances a fixture's telegraph by two
	# seconds so the whole armed/spent ledger is reachable from a button.
	"res://src/ui/screens/domain_explore.gd": ["168|ARM_TICK"],
}


## The shipped tree declares no cadence outside `core/time_ladder.gd`. Fails naming FILE
## and LINE for every hit, which is the shape `test_realm_rate.gd:208-224` established:
## the only way to add a second definition is to add one of these lines, and the build
## then says which file and which line.
func test_no_file_but_the_ladder_declares_a_time_constant() -> void:
	var offenders: Array[String] = []
	for path in _source_files(SRC_ROOT) + _source_files(TESTS_ROOT):
		if path == SSOT:
			continue
		for declared in _time_constants(FileAccess.get_file_as_string(path), path):
			offenders.append("%s:%s" % [path, declared])
	assert_eq(
		offenders,
		[],
		(
			"a time constant outside core/time_ladder.gd — the clock has one home "
			+ "(ADR 0173): "
			+ str(offenders)
		)
	)


## The wall clock is read in exactly one place in `res://src`, and that place is the
## named idempotency stamp rather than a second clock. ADR 0089 / DEF-0111 and `AGENTS.md`
## already forbid a module owning a clock; this asserts the EXCEPTION count is still one,
## so a second `Time.get_ticks*` cannot arrive quietly beside it.
func test_the_wall_clock_is_read_only_as_the_named_idempotency_stamp() -> void:
	var offenders: Array[String] = []
	for path in _source_files(SRC_ROOT):
		if path == IDEMPOTENCY_STAMP:
			continue
		for found in _wall_clock_reads(FileAccess.get_file_as_string(path)):
			offenders.append("%s:%s" % [path, found])
	assert_eq(
		offenders,
		[],
		(
			"no wall clock outside the one named stamp at %s (ADR 0173): %s"
			% [IDEMPOTENCY_STAMP, str(offenders)]
		)
	)


## The allowlist may not go vacuous. An exempt path that stopped existing, or that stopped
## declaring anything, would leave `test_no_file_but_the_ladder_declares_a_time_constant`
## permanently green over a rule that no longer describes anything — the same silent
## all-clear `test_the_backup_guard_actually_reads_the_source_tree` was written to kill.
## So the one file the guard declines to read is asserted to hold a real declaration.
func test_the_exempted_ssot_really_declares_the_ratio() -> void:
	var source := FileAccess.get_file_as_string(SSOT)
	assert_ne(source, "", "%s is readable, or the exemption is vacuous" % SSOT)
	# `_time_constants` returns `"<line>|<NAME>"`, so the name is the half after
	# the separator rather than the whole entry.
	assert_eq(
		_has_entry_named(_time_constants(source, SSOT), "PERIOD_SECONDS"),
		true,
		"%s declares PERIOD_SECONDS, which is the whole point of the exemption" % SSOT
	)


## Every `.gd` under `root`, walked by `ContentScan` so the depth cap is the repo's and not
## this guard's (`AGENTS.md:54`: a recursive walk needs a cap and `while` scanning cannot
## see one). The suffix is passed EXPLICITLY — `ContentScan.files_under` defaults to
## `.tres`, which is the trap `test_save_envelope.gd:380-398` documented at length.
func _source_files(root: String) -> Array[String]:
	return ContentScan.files_under(root, ".gd")


## The scan found the tree it claims to cover. Two floors and one landmark, because they
## catch different failures: the landmark proves the walk reaches the composition root
## where a call-site copy would be authored, and the floors catch a suffix typo, a depth
## cap hit early, or a root that moved.
func test_the_walk_actually_reads_the_tree_it_guards() -> void:
	var sources := _source_files(SRC_ROOT)
	var suites := _source_files(TESTS_ROOT)
	assert_eq(
		sources.size() >= SRC_FILE_FLOOR,
		true,
		"read %d .gd under res://src, below the floor of %d" % [sources.size(), SRC_FILE_FLOOR]
	)
	assert_eq(
		suites.size() >= TESTS_FILE_FLOOR,
		true,
		"read %d .gd under res://tests, below the floor of %d" % [suites.size(), TESTS_FILE_FLOOR]
	)
	assert_eq(
		sources.has("%s/app/world_pulse.gd" % SRC_ROOT),
		true,
		"and the walk reaches the composition root that held the canonical ratio"
	)
	assert_eq(sources.has(SSOT), true, "and the file it exempts, which the next row then reads")


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
func _names_only(entries: Array) -> Array:
	var names: Array = []
	for entry in entries:
		var text := String(entry)
		var separator := text.find("|")
		names.append(text.substr(separator + 1) if separator >= 0 else text)
	return _sorted(names)


## Every census row still names a declaration that EXISTS in that file, resolved by
## NAME rather than by line.
##
## **The line in a row is documentation, not the assertion.** Pinning it was a trip-wire
## on comment length — a peer adding two doc lines above `TICK_INTERVAL` moved it from
## `:304` to `:326` and turned this suite red for a reason that has nothing to do with
## the clock, which is the exact failure `test_time_ladder.gd`'s `_declaration_in`
## already solved by resolving content. So the NAME is checked here and the line is only
## reported when it has drifted, which keeps the drift visible without making an
## unrelated edit a red build.
func test_the_census_still_names_a_real_line() -> void:
	for path in EXPECTED_NON_CLOCK:
		var declared := _declared_names_in(FileAccess.get_file_as_string(path))
		for entry in EXPECTED_NON_CLOCK[path]:
			var text := String(entry)
			var separator := text.find("|")
			var line := int(String(text).substr(0, separator))
			var name := String(text).substr(separator + 1)
			assert_eq(
				declared.has(name),
				true,
				(
					"%s no longer declares %s — refresh EXPECTED_NON_CLOCK (row says line %d)"
					% [path, name, line]
				)
			)


## Every declared NAME in a file, as `"<line>|<name>"` entries.
func _declared_names_in(source: String) -> Array[String]:
	var names: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1)).strip_edges()
		if not _is_const_line(line):
			continue
		var name := _declared_name(line)
		if name != "":
			names.append(name)
	return names


## The CODE of one original line number, comments stripped.
func code_only_line(source: String, wanted: int) -> String:
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator >= 0 and _line_of(entry, separator) == wanted:
			return String(entry.substr(separator + 1)).strip_edges()
	return ""


## The declared NAMES on every const line of a file, for the drift check above.
func _const_lines(source: String) -> Array[int]:
	var lines: Array[int] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := _line_of(entry, separator)
		if _is_const_line(String(entry.substr(separator + 1)).strip_edges()):
			lines.append(line)
	return lines


## The near-misses, one per clause of `_is_clock_duplicate`, and the assertion is always
## the same shape: an exempt shape beside a near-miss that must STILL be reported. A rule
## that keeps a duplicate cannot be told from a rule that has been widened, so each pair
## below differs by the ONE thing that decides it — the token, the suffix, the prefix, the
## layer — and nothing else. If a near-miss ever goes quiet, the vocabulary has widened
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


## Stringified for the census comparison, so an assertion names the same entry however
## the scan happened to order it. `sort()` is `void` in GDScript and sorts in place, so
## the copy exists for the caller's list rather than to mutate it. Built entry by entry
## rather than by `duplicate()`: the census is untyped `Array`, which will not convert to
## `Array[String]` whatever it holds.
func _sorted(entries: Array) -> Array:
	var copy: Array[String] = []
	for entry in entries:
		copy.append(String(entry))
	copy.sort()
	return copy


## Every `const` whose name carries a time token and whose value is a numeric literal, as
## `"<line>|<NAME>"`. The line number is the ORIGINAL one -- comments are removed before
## the scan, so an index into the stripped text would point at the wrong line, and a
## guard that names the wrong line is a guard nobody can act on.
##
## The value test is a first-character test on the right-hand side rather than a
## `is_valid_float()`: it accepts what a clock is written as (`120.0`, `1`, `-1.0`) and
## declines everything else, including the arithmetic someone may reach for later
## (`1.0 / (30.0 * 24.0)`), which belongs in the SSOT like any other authored ratio.
func _time_constants(source: String, where: String = SRC_ROOT) -> Array[String]:
	var found: Array[String] = []
	for entry in _classified_constants(source, where):
		found.append(entry)
	return found


## Every time-shaped `const` this file RECOGNISES — the duplicates AND the ones it
## deliberately declines. `want_duplicates` selects between them.
##
## **The census needs both halves and used to read one.** It asserts that every recognised
## shape outside the SSOT is a row in `EXPECTED_NON_CLOCK`, so it must see the DECLINED
## ones too; but `_is_clock_duplicate` is true only for the reported ones. Filtering the
## census by it therefore compared two empty sets, and the test passed on an empty
## `EXPECTED_NON_CLOCK` while a new unclassified shape would have gone unnoticed — the
## quiet version of the ADR 0116 failure this file exists to prevent.
func _classified_constants(
	source: String, where: String = SRC_ROOT, want_duplicates: bool = true
) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1)).strip_edges()
		if not _is_const_line(line):
			continue
		var name := _declared_name(line)
		if name == "" or not _is_numeric_value(line):
			continue
		if not _is_time_shaped(name):
			continue
		if _is_clock_duplicate(where, name) == want_duplicates:
			found.append("%d|%s" % [_line_of(entry, separator), name])
	return found


## The whole rule, in one question: is this declaration a SECOND definition of the clock?
##
## A time-shaped name and a numeric literal get a declaration into this function at all;
## whether it is a duplicate is the classification below, and each clause is a SHAPE with
## a near-miss that must still be reported.
func _is_clock_duplicate(path: String, declared: String) -> bool:
	var tokens := _matched_tokens(declared)
	var duplicate := false
	# A per-call ceiling is a bound on ONE call, declined by its prefix above.
	if not tokens.is_empty() and _is_time_shaped(declared):
		# 1. `SECONDS_PER` — the shape the guard exists for, and the FIRST clause. Nothing
		# below may decline it, which is what keeps a ratio exempt from nothing. The one
		# thing read before it is the unit suffix, because a name may measure seconds AND
		# declare the unit it measures them against — the whole of
		# `SECONDS_PER_GESTATION_DAY_TURN`, which is the COMBAT turn tier that ADR 0173:63
		# keeps off the world clock ("combat resolves on turns inside one period"). A turn
		# is not a magnitude of world time, so it is not a duplicate. **This is not an
		# alibi for a ratio**: `SECONDS_PER_PERIOD_TURN` carries the suffix and is still
		# caught below, because what it converts is the world clock's own unit.
		if declared.ends_with(UNIT_TURN_SUFFIX) and not _measures_the_world_clock(declared):
			duplicate = false
		elif _has_token(tokens, "SECONDS_PER"):
			duplicate = true
		# 2. A floor ON THE RATIO is the ratio. `MIN_PERIOD_SECONDS` carries the base
		# ratio's own name behind a `MIN_` prefix, and a floor on the base ratio is a second
		# definition of it — nothing else in the tree is allowed to say how long a period is.
		# Read before the `MIN_` floor clause below, which declines a floor on AUTHORED DATA;
		# this one is a floor on the CLOCK, so the floor argument does not reach it.
		elif _has_token(tokens, "PERIOD_SECONDS"):
			duplicate = true
		# 3. `MIN_` on a COUNT — `MIN_PERIODS` is a floor on how many periods something
		# takes, which is still a bound and not a cadence. Read BEFORE the `_PERIODS`
		# exemption below, because both shapes carry that token and only the prefix tells
		# them apart: `AUTOSAVE_PERIODS` is the world running on a count, `MIN_PERIODS` is
		# content being bounded by one. A count that is also a floor has to be reported or
		# the floor is invisible.
		elif _is_authored_floor(declared) and _has_token(tokens, "_PERIODS"):
			duplicate = true
		# 4. How many periods. A count and a ratio are different kinds of number, and the
		# read is backwards: `_PERIODS` says "how many periods", not "how many per period".
		elif _has_token(tokens, "_PERIODS"):
			duplicate = false
		# 4. An authored fallback, declined BY NAME because a bare span token is a genuine
		# cadence shape everywhere else — see `AUTHORED_FALLBACKS`.
		elif _is_authored_fallback(path, declared):
			duplicate = false
		# 5. A presentation step in `ui/`, which may not read the world clock at all.
		elif path.begins_with(UI_ROOT):
			duplicate = false
		# 6. `MIN_` — the shortest interval a `.tres` may ask for. A floor on AUTHORED DATA,
		# so the file it would have to agree with is the one being read and nothing drifts.
		else:
			duplicate = not _is_authored_floor(declared)
	return duplicate


## Whether `declared` is one of the named fallbacks above. Read as a dictionary lookup
## rather than as a token test: the exemption is for a value that mirrors an authored
## `.tres` in one named place, and a name that travels is a name that will travel.
func _is_authored_fallback(path: String, declared: String) -> bool:
	return AUTHORED_FALLBACKS.get(path, [] as Array).has(declared)


## `MIN_INTERVAL`, `MIN_TICK_INTERVAL`: a floor on what a `.tres` may ask for, so the
## file it would have to agree with is the one being read and nothing can drift. It is
## also a bound rather than a cadence — nothing runs the world on it. `MAX_` is
## deliberately NOT a trigger here, or the authored-data argument would wave through a
## `MAX_PERIOD` ceiling that ADR 0173:88 says stays a ceiling.
func _is_authored_floor(declared: String) -> bool:
	return declared.begins_with(FLOOR_PREFIX)


## Whether a `SECONDS_PER_*` name converts the SSOT's own unit, which is what makes it a
## duplicate even when it also names a unit to measure against.
##
## `SECONDS_PER_PERIOD` and `SECONDS_PER_PERIOD_SECONDS` both read the base ratio backwards,
## so a `_TURN` suffix on either of them is a unit bolted onto a clock declaration and not
## a turn-tier duration. A name that converts something ELSE — `SECONDS_PER_GESTATION_DAY` —
## is the turn tier's own measurement and is off the world clock entirely. The test is
## therefore about what the name converts, not about the prefix on the end of it.
func _measures_the_world_clock(declared: String) -> bool:
	var upper := declared.to_upper()
	return upper.contains("PERIOD_SECONDS") or upper.contains("PER_PERIOD")


## Whether `wanted` is among the matched tokens. A linear read rather than `in`: the
## matched list is one or two entries long and the two clauses that need this must be
## read as the only two ways a ratio can escape the other three.
func _has_token(tokens: Array[String], wanted: String) -> bool:
	return tokens.has(wanted)


## Every token in `TIME_TOKENS` this declared name actually carries, `PER_CALL_PREFIX`
## already applied. Ordered longest-first as `TIME_TOKENS` itself is, so a report can
## name the pattern that matched.
func _matched_tokens(declared: String) -> Array[String]:
	var matched: Array[String] = []
	for token in TIME_TOKENS:
		if declared.to_upper().contains(token) and not _is_per_call_ceiling(declared, token):
			matched.append(token)
	return matched


## The original line number carried by a `"<line>|<rest>"` entry.
func _line_of(entry: String, separator: int) -> int:
	return int(String(entry).substr(0, separator))


## Every line of `source` that CODE occupies, as `"<original line number>|<line>"`, with
## every comment removed. Line by line because a block comment's middle lines are the ones
## that mislead; character by character within the line because a trailing `#` sits after
## real code on the same row.
##
## `"""` blocks are dropped too. The tree contains none today, so this is insurance rather
## than a live requirement — but a multiline string is prose that a raw scan reads as
## code, and the cost of handling it is nine lines.
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


## Whether a stripped line declares a `const`, `static const` included: GDScript accepts
## the `static` form and `tests/modules/destiny/test_destiny_earning.gd` already uses it,
## so a prefix test that ignored it would quietly skip a declaration site.
func _is_const_line(line: String) -> bool:
	return line.begins_with("const ") or line.begins_with("static const ")


## The name a `const` line declares, or `""`. Read up to the first space, colon or equals
## so `const NAME := 120.0`, `const NAME: float = 1.0` and `const NAME = 1` all yield
## `NAME` and a name carrying a character GDScript would reject yields nothing.
func _declared_name(line: String) -> String:
	var rest := line.substr(7) if line.begins_with("static ") else line.substr(6)
	var at := rest.length()
	for index in rest.length():
		var character := rest[index]
		if character == " " or character == ":" or character == "=":
			at = index
			break
	return rest.substr(0, at).strip_edges()


## Whether a declared name carries any of `TIME_TOKENS` at all, `PER_CALL_PREFIX`
## already applied. Case-insensitive, because a lower-case `period_seconds` is the same
## declaration with different manners, and kept separate from the unit question in
## `_is_clocking_declaration` because "is this name about time" and "is this number a
## duration" are two decisions that one name must not be asked to make at once.
func _is_time_shaped(declared: String) -> bool:
	return not _matched_tokens(declared).is_empty()


## `MAX_PERIODS_PER_PULL`, `MAX_TEACH_PERIODS`, `MAX_WAIT_PERIODS`: a ceiling on ONE call,
## which ADR 0173:88 keeps distinct from "a budget" and from a cadence. A `MAX_` ceiling
## is a bound on how much a single invocation may do; a cadence is how often something
## happens as time passes. They are different kinds of number and only one of them is a
## clock.
##
## **The carve-out is scoped to `PERIOD_COUNT_TOKENS` and to nothing else.** An earlier
## version waived any `MAX_`-prefixed name, and that was a false negative in the guard's
## own subject: it silently spared `status_loop.gd:60` `MAX_COLLAPSE_HELD := 3600.0`, a
## window in SECONDS that ADR 0173 names in its migration table as one of the constants
## that moves here. A `MAX_` that carries a *time* token (`HELD`, `TICK`, `INTERVAL`,
## `SECONDS_PER`) is a duration or a cadence whatever its prefix says, so only a
## `MAX_` carrying a *period count* is a per-call ceiling.
func _is_per_call_ceiling(name: String, matched_token: String) -> bool:
	if not name.to_upper().begins_with(PER_CALL_PREFIX):
		return false
	return matched_token in PERIOD_COUNT_TOKENS


## Whether the right-hand side of a declaration is a plain NUMBER, and nothing else.
##
## **A first-character test is not enough, and the shape that proved it is shipped.**
## `const BASE_BLOW_INTERVAL := 1.0 / BASE_BLOWS_PER_SECOND` (`app/fight_loop.gd:69`)
## begins with a digit, so a "does it start numeric" rule accepted it — and then the
## guard reported a DERIVED interval as a hand-typed cadence, which is the same
## off-by-one the lifespan guard had in its own `_is_numeric_value` (`find(":=")` returns
## the colon, so slicing at `at + 1` left the `=` in the value). A private copy of the
## clock is a bare literal; arithmetic that derives one is a different declaration, and
## only the bare literal can drift from the SSOT on its own.
##
## So the whole value must be a number: digits, a sign, a decimal point and nothing
## else. A trailing operator, a `/`, a `(` or a second identifier all decline it.
func _is_numeric_value(line: String) -> bool:
	var at := line.find("=")
	if at < 0:
		return false
	var value := line.substr(at + 1).strip_edges()
	if value.is_empty() or value == ":":
		return false
	var saw_digit := false
	for index in value.length():
		var character := value[index]
		if character >= "0" and character <= "9":
			saw_digit = true
		elif character == "." or character == "_":
			continue
		elif character == "-" or character == "+":
			# A sign is only a sign in the FIRST position; elsewhere it is arithmetic.
			if index > 0:
				return false
		else:
			return false
	return saw_digit


## Whether any `"<line>|<NAME>"` entry names `wanted`, so a caller can assert on the
## NAME of a declaration rather than on the whole entry — the entry also carries a line
## number that moves every time the file above it is edited.
func _has_entry_named(entries: Array[String], wanted: String) -> bool:
	for entry in entries:
		var separator := entry.find("|")
		if separator >= 0 and String(entry.substr(separator + 1)) == wanted:
			return true
	return false


## Every line of a file's CODE that reads the wall clock, as `"<line>|<number>"`. Read
## from the stripped text for the reason every other scan here is: the token appears in the
## docstring of at least eleven files under `res://src`, and an unstripped scan reports
## correct code as an offence in all of them.
func _wall_clock_reads(source: String) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		if String(entry.substr(separator + 1)).contains(FORBIDDEN_CLOCK):
			found.append("%d|%s" % [_line_of(entry, separator), FORBIDDEN_CLOCK])
	return found
