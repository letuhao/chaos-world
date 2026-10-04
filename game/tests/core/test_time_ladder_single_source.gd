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

## `MAX_` is a per-call ceiling, not a cadence, and ADR 0173:88 says so in as many words:
## "`MAX_PERIODS_PER_PULL := 8` stays what it always was: a ceiling on ONE CALL, which a
## budget is not." `MAX_TEACH_PERIODS`, `MAX_WAIT_PERIODS` and `MAX_PERIODS_PER_PULL` are
## the same shape, so they are declined by this rule rather than by three more
## allowlist entries.
const PER_CALL_PREFIX := "MAX_"

## The wall-clock read the named exception is about. Spelled without the trailing `*` so
## one token covers `get_ticks_msec`, `get_ticks_usec` and the rest.
const FORBIDDEN_CLOCK := "Time.get_ticks"

## Floors under the walk, measured 2026-10-04 at 511 `.gd` files in `res://src` and 475
## in `res://tests`. `test_the_walk_actually_reads_the_tree_it_guards` is what turns an
## empty list into a failure rather than an all-clear -- the `SOURCE_FILE_FLOOR`
## argument from `test_save_envelope.gd:414-451`, where a guard that walked `.tres` files
## reported "clean" over an empty file list and a mutation probe left it at 61 passed.
const SRC_FILE_FLOOR := 450
const TESTS_FILE_FLOOR := 400


## The shipped tree declares no cadence outside `core/time_ladder.gd`. Fails naming FILE
## and LINE for every hit, which is the shape `test_realm_rate.gd:208-224` established:
## the only way to add a second definition is to add one of these lines, and the build
## then says which file and which line.
func test_no_file_but_the_ladder_declares_a_time_constant() -> void:
	var offenders: Array[String] = []
	for path in _source_files(SRC_ROOT) + _source_files(TESTS_ROOT):
		if path == SSOT:
			continue
		for declared in _time_constants(FileAccess.get_file_as_string(path)):
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
		_has_entry_named(_time_constants(source), "PERIOD_SECONDS"),
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
		sources.has(SRC_ROOT + "/world_pulse.gd"),
		true,
		"and the walk reaches the file that held the canonical ratio"
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


## Every token in the set must actually fire, or the vocabulary has rotted into a list
## that matches nothing. One fixture per token, each a single `const` line: a token that
## silently stopped matching would leave this test green on the first ones and red on
## whichever one somebody edited, which is the quiet version of the ADR 0116 failure.
func test_the_detector_fires_on_every_shape_the_adr_names() -> void:
	for token in TIME_TOKENS:
		# `SECONDS_PER` is a PREFIX token, so the name is completed the way a real
		# declaration spells it rather than left as the bare prefix.
		var name: String = "SECONDS_PER_PERIOD" if token == "SECONDS_PER" else token
		var line := "\tconst %s := 1.0" % name
		assert_eq(
			_time_constants(line + "\n").size(),
			1,
			"%s is a shape this guard recognises, or the vocabulary has rotted" % token
		)
	# The one carve-out: a per-call ceiling is not a cadence (ADR 0173:88).
	assert_eq(
		_time_constants("\tconst MAX_PERIODS_PER_PULL := 8\n"),
		[],
		"a per-call ceiling is declined, not allow-listed by name"
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


## Every `const` whose name carries a time token and whose value is a numeric literal, as
## `"<line>|<NAME>"`. The line number is the ORIGINAL one -- comments are removed before
## the scan, so an index into the stripped text would point at the wrong line, and a
## guard that names the wrong line is a guard nobody can act on.
##
## The value test is a first-character test on the right-hand side rather than a
## `is_valid_float()`: it accepts what a clock is written as (`120.0`, `1`, `-1.0`) and
## declines everything else, including the arithmetic someone may reach for later
## (`1.0 / (30.0 * 24.0)`), which belongs in the SSOT like any other authored ratio.
func _time_constants(source: String) -> Array[String]:
	var found: Array[String] = []
	for entry in _code_only(source):
		var separator := entry.find("|")
		if separator < 0:
			continue
		var line := String(entry.substr(separator + 1)).strip_edges()
		if not _is_const_line(line):
			continue
		var name := _declared_name(line)
		if name == "" or not _is_time_shaped(name):
			continue
		if not _is_numeric_value(line):
			continue
		found.append("%d|%s" % [int(entry.substr(0, separator)), name])
	return found


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


## Whether a declared name is one of this guard's time shapes. Case-insensitive, because
## a lower-case `var period_seconds` is the same declaration with different manners.
## `PER_CALL_PREFIX` is applied by the CALLER rather than here, because declining a
## per-call ceiling and declining a non-constant are different decisions.
func _is_time_shaped(name: String) -> bool:
	var shouted := name.to_upper()
	for token in TIME_TOKENS:
		if shouted.contains(token):
			return not _is_per_call_ceiling(name)
	return false


## `MAX_PERIODS_PER_PULL`, `MAX_TEACH_PERIODS`, `MAX_WAIT_PERIODS`: a ceiling on ONE call,
## which ADR 0173:88 keeps distinct from "a budget" and from a cadence. A `MAX_` ceiling is
## a bound on how much a single invocation may do; a cadence is how often something
## happens as time passes. They are different kinds of number and only one of them is a
## clock.
func _is_per_call_ceiling(name: String) -> bool:
	return name.to_upper().begins_with(PER_CALL_PREFIX)


## Whether the right-hand side of a declaration begins with a number or a signed number.
## Everything else -- a `&"refusal id"`, a reference to the SSOT, an array, an expression
## -- is declined, which is what keeps a word-shaped constant out of the report.
func _is_numeric_value(line: String) -> bool:
	var at := line.find("=")
	if at < 0:
		return false
	var value := line.substr(at + 1).strip_edges()
	if value.is_empty() or value == ":":
		return false
	var first := value[0]
	return first >= "0" and first <= "9" or first == "-" or first == "+"


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
			found.append("%d|%s" % [int(entry.substr(0, separator)), FORBIDDEN_CLOCK])
	return found
