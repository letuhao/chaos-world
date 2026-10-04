extends TestCase

## A mutation probe that was never reverted, as CODE.
##
## The incident this exists for: an agent deleted the shared
## `WorldAnchor.commit(actor, ...)` from `core/breakthrough.gd` to prove a mutation
## went red, lost its editing tools mid-run, and the deletion shipped. The suite
## stayed green the whole time — body and qi each commit the same milestone by hand
## — so nothing in the build could see it. A stranded mutation fails OPEN, which is
## strictly worse than a failing test: the build is green and the behaviour is
## wrong. Same class of hazard as the unbounded `while` that put ~10 GB of Godot
## logs on the user's C: drive, and the same remedy as
## `test_no_unbounded_wait.gd`: scan the tree structurally and fail the build, over
## the same two roots, so the two guards behave consistently.
##
## WHAT THIS DOES NOT CATCH, stated plainly because overclaiming is worse than the
## hazard: it detects MARKED probes only. A mutation that deletes a whole function,
## renames a symbol or inverts a comparison and writes no marker leaves nothing to
## find, and no text scan could find it. An unmarked mutation is still a finding to
## report, never a coin to re-roll. Nothing here should be read as making the suite
## mutation-complete. It also does not scan `tools/` (outside `res://`, and Python)
## or `res://data`, whose authored `.tres` carry no comments to mark.

const SRC_ROOT := "res://src"
const TESTS_ROOT := "res://tests"
## The file the incident happened in: the shared milestone commit was deleted from
## here and never restored. Asserted to be inside the scan's own file list, so
## "res://src is covered" is a fact this suite checks rather than a claim it makes.
const INCIDENT_FILE := "res://src/core/breakthrough.gd"
## A shipped file that legitimately NAMES a mutation id mid-sentence, in three places.
## Read rather than transcribed, so the claim tracks the real file; the exact three
## line shapes are pinned by hand in the prose test below so it survives either half
## being changed.
const SHIPPED_PROSE := "res://tests/modules/mind_cultivation/test_mind_stat_reachability.gd"
## Findings are named one by one up to here, then only counted. A tree with hundreds
## of markers must not walk `TestCase.MAX_FAILURES` and `OS.crash` the process — the
## count assertion below still fails, and the first dozen still say where to look.
const MAX_REPORTED := 12
## A named count so an emptied or truncated table is a failure rather than a scan
## that has quietly stopped matching anything.
const SHAPE_COUNT := 5
## Line numbers in `_fixture_lines` that are PROBES, and line numbers that are prose.
## Both are asserted by name, and together they are the whole proof: the two sets are
## disjoint, cover every shaped line in the fixture, and a guard that dropped
## everything would fail the first while a guard with no filter would fail the second.
const FIXTURE_LIVE: Array = [3, 4, 5, 7]
const FIXTURE_DOCUMENTATION: Array = [6, 8, 9]
const FIXTURE_SHAPES := 7

## One or more spaces or tabs. The gap is what keeps the numbered banner in
## `tests/app/test_mutation_guards.gd` — shipped prose, not a probe — from reading as
## the bare-comment shape below, and it lets two spaces be a marker as one space is.
const GAP := 0
## Exactly one letter or digit. Needed because the incident's marker puts the id
## straight against the hyphen — the root, a dash, then `M1` with nothing between —
## so a shape of root + dash + gap matched neither that line nor the same marker
## written bare. See `test_the_incident_s_own_marker_shape_is_what_fires`.
const ALNUM := 1

## The forbidden shapes. A shape is a list of parts: a `String` is matched
## literally, `GAP` matches a run of whitespace, `ALNUM` one letter or digit, and
## the search restarts one character along, so a shape can begin anywhere on a line.
## At one offset the LONGEST match wins.
##
## Every shape is narrow because the tree's own real prose has to survive it:
##  - root, dash, id character: the stranded `core/breakthrough.gd` marker. Nothing
##    shipped joins those three.
##  - root plus `PROBE`: two uppercase words. `MUTATING_VERBS` in the sect and nation
##    screens is a different word, and that file's numbered banner has a number.
##  - `#` or `//` plus the root: a comment introducer and the token right after it.
##  - `XXX` plus `MUTAT`: the mutation-testing tombstone. A run of capital X is never
##    English.
##
## Case-sensitive on purpose, and load-bearing rather than fussy: the tree says
## "mutation" in lowercase prose on 172 lines, and every one has to survive this.
##
## FINDING A SHAPE IS NOT THE SAME AS IT BEING A PROBE, and that is where the prose
## filter lives — in `_is_documentation`, not in this table. Three lines in
## `test_mind_stat_reachability.gd` name a mutation id mid-sentence and matched these
## shapes verbatim, which left this guard permanently red on false positives: the tree
## was correct and the gate was wrong, which is how a gate gets deleted.
##
## `mutation_history.py` is the ref-tip half of this same guard and draws the identical
## cut in `is_documentation`. The tokens are assembled from fragments so this file
## cannot trip its own scan. `test_the_guard_does_not_flag_its_own_source` holds that
## line: a guard nobody can write down is a guard nobody can extend, and spelling a
## token out in a clarifying comment fails the build on the guard instead of on a
## probe. Not hypothetical — it happened to this file while the guard was being built.
const MARKER := "MUTAT" + "ION"
const SHAPES: Array = [
	[MARKER, "-", ALNUM],
	[MARKER, GAP, "PROBE"],
	["#", GAP, MARKER],
	["//", GAP, MARKER],
	["XXX", GAP, "MUTAT"],
]


func test_no_mutation_marker_is_left_in_the_tree() -> void:
	var tokens := _gate_tokens()
	var sources := _gdscript_files(SRC_ROOT)
	var suites := _gdscript_files(TESTS_ROOT)
	# Scope first, findings second. A scan that finds nothing because it read
	# nothing is the failure mode this repo keeps producing, so the file list is
	# pinned before anything is reported — including the exact file the incident
	# happened in, which is what turns "res://src is scanned" into a checkable
	# claim instead of an assumption. It would also fire if `core/` ever moved out
	# of `res://src`, which is exactly when this guard would stop covering it.
	assert_eq(sources.is_empty(), false, "res://src is walked, and is not empty")
	assert_eq(suites.is_empty(), false, "res://tests is walked, and is not empty")
	assert_eq(sources.has(INCIDENT_FILE), true, "and the incident's own file is in scope")
	var found := 0
	for path in sources + suites:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		if not _may_contain(text, tokens):
			continue
		for hit in _markers_in(text):
			found += 1
			if found <= MAX_REPORTED:
				assert_eq(true, false, _report(path, hit))
	assert_eq(
		found,
		0,
		"%d mutation marker(s) left in the tree; up to %d are named above" % [found, MAX_REPORTED]
	)


func test_the_detector_recognises_every_shape_it_forbids() -> void:
	# One sample per shape, built FROM the shape, so the table and its own proof
	# cannot drift apart. This is the anti-vacuity check: a shape the matcher cannot
	# find is a failure here rather than a shape nobody has ever seen fire.
	#
	# DETECTION, deliberately, not liveness: three of the five samples are a bare
	# marker at the start of a line, and the cut in `_is_documentation` correctly
	# calls those documentation. Asserting liveness here instead would either force
	# the cut to lie or hide that the detector still sees them, and both are worse
	# than asking the two questions in two places.
	assert_eq(SHAPES.size(), SHAPE_COUNT, "the shape table is the size it claims")
	for shape in SHAPES:
		var sample := _sample_for(shape)
		var hits := _shape_hits(sample)
		assert_eq(hits.size(), 1, "the shape that forbids `%s` also finds it" % sample)
		if hits.size() == 1:
			assert_eq(int(hits[0]["line"]), 1, "and reports the line it is written on")


func test_the_incident_s_own_marker_shape_is_what_fires() -> void:
	# The one marker this guard exists for, written every way it could plausibly have
	# been written: behind a comment mark, bare in code, with nothing after the id,
	# and behind a doc-comment. The bare form is the case that first mattered — the
	# first cut of the shape table demanded a whitespace run AFTER the hyphen, so it
	# matched none of these and the guard was clean against the very marker it was
	# built from. Deriving every positive sample from the shape table is what hid
	# that: the table and its own proof agreed with each other, and both were wrong
	# about the incident. So the incident is pinned here by hand as well.
	#
	# Every one of them is DETECTED. The bare ones are then declined as liveness, for
	# one reason that is specific to GDScript: a bare marker token in code position is
	# a parse error, so a line carrying one is a multi-line string, and a tombstone
	# string is a tombstone. That is also why `mutation_history.py` agrees.
	var live := [
		"#" + MARKER + "-M1 core commit removed",
		"## " + MARKER + "-M1",
		"#     " + MARKER + "-M1",
		"var x := 1  # " + MARKER + "-M4 removed",
	]
	var declined := [
		MARKER + "-M1 core commit removed",
		MARKER + "-M1",
		MARKER + "-2",
	]
	for sample in live + declined:
		assert_eq(_shape_hits(sample).size(), 1, "`%s` is detected" % sample)
	for sample in live:
		assert_eq(_markers_in(sample).size(), 1, "`%s` is still LIVE" % sample)
	for sample in declined:
		assert_eq(_markers_in(sample).size(), 0, "`%s` is documentation, not a probe" % sample)


func test_a_marker_behind_real_code_is_still_a_probe() -> void:
	# The case a blanket comment exemption loses, and losing it is worse than the
	# false positive being fixed: the marker IS in a comment, and the line still has
	# to be red. Pinned on its own so the cut cannot be widened to "ignore comments"
	# and still pass — a mid-sentence marker on a code line, a marker inside a string
	# literal, and a marker after a keyword all reach the reader through a comment
	# introducer, and all three are live.
	for sample in [
		"var x := 1  # " + MARKER + "-M6",
		"var x := 1  # deletes " + MARKER + "-M6",
		'var note := "' + MARKER + '-M6 is the id"',
		"if not is_bound() and false:  # " + MARKER + "-M6",
	]:
		assert_eq(_shape_hits(sample).size(), 1, "`%s` is detected" % sample)
		assert_eq(_markers_in(sample).size(), 1, "`%s` is LIVE" % sample)


func test_prose_that_names_a_mutation_is_documentation() -> void:
	# The three shapes that made this guard permanently red, transcribed by hand from
	# `test_mind_stat_reachability.gd` so the claim survives that file being edited,
	# plus the two bare forms. The marker is spliced in from `MARKER`, which is what
	# keeps THIS file out of its own scan while still asserting on the real text.
	for sample in [
		"## assertion about the mechanism still passes. " + MARKER + "-B (the defence published",
		"## regression " + MARKER + "-A below reproduces.",
		"\t# and leaves the defence this module published. " + MARKER + "-A (meridian_power",
		"# the regression " + MARKER + "-A below reproduces.",
		"\t" + MARKER + "-6 core commit removed",
	]:
		assert_eq(_shape_hits(sample).size(), 1, "`%s` is detected" % sample)
		assert_eq(_markers_in(sample).size(), 0, "`%s` is documentation" % sample)


func test_the_shipped_file_naming_mutations_is_read_clean() -> void:
	# The permanent version of the prose test: the real file, read, asserted to hold a
	# shaped line so this cannot pass vacuously, and asserted to hold no LIVE one.
	var text := FileAccess.get_file_as_string(SHIPPED_PROSE)
	assert_ne(text.is_empty(), true, "the shipped prose file is readable")
	assert_eq(
		_shape_hits(text).is_empty(),
		false,
		"it still holds marker-shaped line(s) to be judged: %s" % _describe(_shape_hits(text))
	)
	var live := _markers_in(text)
	assert_eq(live.size(), 0, "every shaped line in it is prose: %s" % _describe(live))


func test_one_fixture_holding_a_probe_and_its_prose_splits_them() -> void:
	# The proof, in one file: a probe AND the prose that names one. A probe-only fixture
	# passes a filter that drops everything; a prose-only fixture passes a guard with
	# no filter. Neither can pass this.
	var fixture := _fixture_text()
	# The OLD behaviour, measured rather than claimed: adjacency-blind, so the prose is
	# in the count. This is the assertion a blanket drop fails, because a drop reports
	# fewer shapes, not zero live ones.
	assert_eq(
		_shape_hits(fixture).size(),
		FIXTURE_SHAPES,
		"detection finds all %d shapes in the fixture" % FIXTURE_SHAPES
	)
	var live := _line_numbers(_markers_in(fixture))
	assert_eq(live, FIXTURE_LIVE, "only the probes stay live, and they stay found")
	for number in FIXTURE_DOCUMENTATION:
		assert_eq(live.has(number), false, "line %d is documentation" % number)
	# Disjoint and total: no line is claimed twice and none is unaccounted for, so a
	# cut that quietly reclassified a probe as prose would fail the first assertion.
	assert_eq(
		live.size() + FIXTURE_DOCUMENTATION.size(),
		FIXTURE_SHAPES,
		"every shaped line in the fixture is accounted for by one set or the other"
	)


func test_the_shapes_decline_the_prose_the_shipped_tree_actually_contains() -> void:
	# Transcribed verbatim from files that really do use the word, so each near-miss
	# is pinned beside the shape that could have taken it. All four are lower case or
	# differently punctuated, which is the whole reason the table is case-sensitive.
	# None of these matches a shape at all, which is a different defence from the cut
	# in `_is_documentation` and worth keeping separate.
	for sample in [
		"# --- MUTATION 1: a rolled value that ignores the seed ----",
		"## the mutations that **survived**, which are the findings",
		"const MUTATING_VERBS := [",
		"## MUTATE, as opposed to the eight that compute.",
		"## mutation and on every equipment change, so the two subsystems cannot",
	]:
		assert_eq(_markers_in(sample).size(), 0, "`%s` is prose, not a probe" % sample)


func test_the_guard_reads_the_shipped_files_that_legitimately_say_mutation() -> void:
	# The permanent version of "does it misfire". These files really do carry the
	# word, in the shapes a case-insensitive `/mutation/` scan would trip on, and
	# the point of a narrow table is that they still read clean. Asserting on them
	# cannot add a failure the main scan does not already have.
	for path in [
		"res://tests/app/test_mutation_guards.gd",
		"res://tests/ui/test_sect_screen.gd",
		"res://src/modules/combat_engine/spine.gd",
		"res://src/modules/socket/socket_effects.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		var hits := _markers_in(text)
		assert_eq(hits.size(), 0, "%s ships prose, not a marker: %s" % [path, _describe(hits)])


func test_the_guard_does_not_flag_its_own_source() -> void:
	# The shape table names the forbidden tokens, so a file that spells them out in
	# full would trip its own scan and fail the build on the guard rather than on a
	# probe. The fragments in `MARKER` make that impossible to do by accident; this
	# is what holds it, and it fires the moment a comment is "clarified" by writing
	# the token out. Asserted on DETECTION, because this file also carries the shape
	# samples as strings and those must be seen to be worth anything.
	var text := FileAccess.get_file_as_string((get_script() as Script).resource_path)
	assert_ne(text.is_empty(), true, "the guard can read its own source")
	var hits := _shape_hits(text)
	assert_eq(hits.size(), 0, "the guard's own source is clean: %s" % _describe(hits))
	assert_eq(_markers_in(text).size(), 0, "and holds no live marker either")


func test_every_shape_needs_a_literal_the_whole_file_gate_looks_for() -> void:
	# The scan skips any file containing none of the gate tokens, so a shape whose
	# literals were all below the token threshold would be unreachable: the table
	# would look right and nothing would ever look for it. Every shape here has a
	# literal of three characters or more, which is what makes the gate sound.
	var tokens := _gate_tokens()
	assert_eq(tokens.is_empty(), false, "the whole-file gate has literals to look for")
	for shape in SHAPES:
		var covered := false
		for part in shape:
			if tokens.has(_literal(part)):
				covered = true
		assert_eq(covered, true, "every shape is reachable through the gate")


# ── Helpers ──────────────────────────────────────────────────────────────────


## Every LIVE marker in `text`, as `{"line": int, "text": String}`, in file order. What
## the scan gates on, so this is where the documentation cut is applied. Detection and
## liveness are kept apart on purpose: a filter that drops everything passes a
## detector-only check, and a detector with no filter cannot be tested against prose.
func _markers_in(text: String) -> Array[Dictionary]:
	var live: Array[Dictionary] = []
	var lines := text.split("\n")
	for hit in _shape_hits(text):
		var line := String(lines[int(hit["line"]) - 1])
		if _is_documentation(line, int(hit["root"])):
			continue
		live.append({"line": int(hit["line"]), "text": String(hit["text"])})
	return live


## Every SHAPE match in `text`, adjacency-blind, as
## `{"line": int, "at": int, "root": int, "text": String}`. This is the DETECTOR: what
## a line holds, before the question of whether it is talking about a mutation or
## leaving one behind. `root` is where the marker TOKEN starts, which is not where the
## match starts for the two comment shapes.
func _shape_hits(text: String) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var lines := text.split("\n")
	for number in lines.size():
		var line := String(lines[number])
		# Bounded by the line's own length, and bounded in a way that cannot be got
		# wrong: BOTH branches advance, so a malformed shape that matches nothing
		# still steps forward instead of re-testing one offset forever. The first cut
		# of this loop did `at = end` on any non-negative answer, and when the
		# comparison below raised a script error `_match` returned its 0 default, so
		# `at` never moved: it spun, appended a hit per pass and wrote 33 MB of
		# engine log. `end > at` is the guard, not a detail.
		var at := 0
		while at < line.length():
			var end := _shape_end(line, at)
			if end > at:
				var matched := line.substr(at, end - at)
				var hit := {
					"line": number + 1,
					"at": at,
					"root": _root_offset(matched, at),
					"text": matched,
				}
				hits.append(hit)
				at = end
			else:
				at += 1
	return hits


## True when the marker TOKEN at `root` is prose that NAMES a mutation rather than a
## probe. Three cases, and each is one branch, mirroring
## `mutation_history.is_documentation` so the two halves of this guard cannot drift:
##
##  - nothing but whitespace in front of it: documentation. In GDScript that position
##    is a multi-line string, because a bare marker in code position is a parse error,
##    and a tombstone string is a tombstone.
##  - code in front of it: a live probe, whatever else the line also holds. This is the
##    case a blanket "ignore comments" exemption loses.
##  - a comment introducer then COMMENT TEXT: documentation, because the comment is
##    talking ABOUT a mutation. The introducer then nothing but the marker is a probe
##    LABELLED, and stays live.
##
## The reasoning is positional on purpose: there is no lexical difference between a
## probe marker and a sentence that mentions one — the same token serves both — so only
## the marker's place in the line can separate them. Adjacency is what a probe author
## actually writes, because a probe comment exists to be found by grepping it, so the
## marker goes first.
##
## Line-bounded by construction and branch-complete: the only slice is the prefix up to
## the marker and every path returns, so there is no loop here to bound. `_hash_run` is
## the one loop and it is bounded by `before.length()`.
func _is_documentation(line: String, root: int) -> bool:
	var before := line.substr(0, root).strip_edges()
	if before.is_empty():
		return true
	if not (before.begins_with("//") or before.begins_with("#")):
		return false
	# `##` and `###` are one introducer repeated, so skip the whole run, then the gap.
	var opener := 2 if before.begins_with("//") else _hash_run(before)
	# Comment text in front of the marker means the comment is TALKING ABOUT one.
	return not before.substr(opener).strip_edges().is_empty()


## The length of the leading run of `#`, bounded by `before.length()`: the introducer
## count on a line like `### marker`. Deliberately not a count of every `#` in the
## prefix, which would skip past the comment text and call prose a probe — the exact
## false positive this whole cut exists to remove.
func _hash_run(before: String) -> int:
	var count := 0
	while count < before.length() and before[count] == "#":
		count += 1
	return count


## Where the marker TOKEN starts, not where the match starts. The two comment shapes
## carry the introducer (a hash, or a pair of slashes) and then the token, so a match
## begins at the introducer and every commented marker would read as documentation -
## the guard's own `#MARKER-M1` sample and the shipped probes alike. The tombstone
## shape carries no full marker token, so a miss means the match already begins at the
## marker. Same helper, same answer, as `mutation_history._root_offset`.
func _root_offset(matched: String, at: int) -> int:
	var inside := matched.find(MARKER)
	return at if inside < 0 else at + inside


## The fixture as one file's worth of lines: a live probe on most of them and the
## shipped prose that names one on the rest. The marker is spliced in from `MARKER`, so
## the probe half exists at RUN TIME and this source stays clean enough for its own
## scan — the same trick `MARKER` itself is built with. Line numbers are the verdicts,
## in `FIXTURE_LIVE` and `FIXTURE_DOCUMENTATION`.
func _fixture_lines() -> Array[String]:
	return [
		"extends RefCounted",
		"",
		"var kept := 1  # " + MARKER + "-M6 deleted the commit",
		"# " + MARKER + "-M6 removed the commit",
		"#" + MARKER + "-M6",
		"# the regression " + MARKER + "-A below reproduces.",
		'var note := "' + MARKER + '-M6 is the id"',
		"# the assertion about the mechanism still passes. " + MARKER + "-B (the defence",
		"\t" + MARKER + "-6 core commit removed",
	]


## The fixture joined into one file's text. The bound is snapshotted BEFORE the loop:
## `lines.size()` is read once here rather than per pass, so nothing the body does can
## move it.
func _fixture_text() -> String:
	var lines := _fixture_lines()
	var text := ""
	for number in lines.size():
		if number > 0:
			text += "\n"
		text += lines[number]
	return text


## The line numbers of `hits`, for a failure that has to name WHICH lines and not only
## how many. Bounded by `hits.size()`, which is finite by construction.
func _line_numbers(hits: Array[Dictionary]) -> Array:
	var numbers: Array = []
	for hit in hits:
		numbers.append(int(hit["line"]))
	return numbers


## One marker line built from a shape, so the table and its proof cannot drift.
## Two spaces stand in for the gap and `1` for the single alphanumeric.
func _sample_for(shape: Array) -> String:
	var sample := ""
	for part in shape:
		if _is_gap(part):
			sample += "  "
		elif _is_alnum_part(part):
			sample += "1"
		else:
			sample += String(part)
	return sample


## True for a shape sentinel rather than a literal. Spelled with `typeof` rather
## than `part == GAP` because GDScript raises a runtime script error when a Variant
## `String` is compared against an `int`, and inside a per-character loop that error
## becomes a log line per character. Typed once, here, so the comparison cannot be
## written wrongly a second time — the first version of this file cost a 64 MB log.
func _is_sentinel(part: Variant) -> bool:
	return typeof(part) == TYPE_INT


func _is_gap(part: Variant) -> bool:
	return _is_sentinel(part) and int(part) == GAP


func _is_alnum_part(part: Variant) -> bool:
	return _is_sentinel(part) and int(part) == ALNUM


## The literal a shape part carries, or `""` for a sentinel. Godot 4.7 rejects
## `String(0)` as an invalid constructor call, so the sentinels are filtered out
## rather than stringified — the second cut of this file raised three script
## errors on exactly that before this helper existed.
func _literal(part: Variant) -> String:
	return "" if _is_sentinel(part) else String(part)


## Where the LONGEST shape matching at `at` ends, or -1 when none does. Longest
## rather than first-in-table, because several shapes match inside one written
## marker and the message should name the whole run the agent has to delete rather
## than the shorter prefix of it. Nothing is shadowed out of existence: the earlier
## offset and the longer match both win, so only the wording is affected.
func _shape_end(line: String, at: int) -> int:
	var longest := -1
	for shape in SHAPES:
		var end := _match(line, at, shape)
		if end > longest:
			longest = end
	return longest


func _match(line: String, at: int, shape: Array) -> int:
	var cursor := at
	for part in shape:
		if _is_gap(part):
			var gap := _gap_length(line, cursor)
			if gap == 0:
				return -1
			cursor += gap
			continue
		if _is_alnum_part(part):
			if cursor >= line.length() or not _is_alnum(line[cursor]):
				return -1
			cursor += 1
			continue
		var literal := String(part)
		if line.substr(cursor, literal.length()) != literal:
			return -1
		cursor += literal.length()
	return cursor


## The run of spaces or tabs starting at `at`, zero when there is none.
func _gap_length(line: String, at: int) -> int:
	var count := 0
	for index in range(at, line.length()):
		if line[index] != " " and line[index] != "\t":
			break
		count += 1
	return count


func _is_alnum(character: String) -> bool:
	return (
		character >= "0" and character <= "9"
		or character >= "A" and character <= "Z"
		or character >= "a" and character <= "z"
	)


## The distinct literals of three characters or more that the shapes need. A shape
## can only match a file holding every one of its literals, so a file holding none
## of these cannot match any shape and is skipped without reading a line — which is
## what keeps this affordable across the whole tree. Derived rather than hand-listed:
## a hand-written gate list is one edit away from covering less than the table, and
## it would go quiet instead of failing.
func _gate_tokens() -> Array[String]:
	var tokens: Array[String] = []
	for shape in SHAPES:
		for part in shape:
			var literal := _literal(part)
			if literal.length() >= 3 and not tokens.has(literal):
				tokens.append(literal)
	return tokens


func _may_contain(text: String, tokens: Array[String]) -> bool:
	for token in tokens:
		if text.contains(token):
			return true
	return false


## The hits as one readable phrase each, so a failure says what was found rather
## than only how many.
func _describe(hits: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for hit in hits:
		out.append("line %d: `%s`" % [int(hit["line"]), String(hit["text"])])
	return ", ".join(out)


func _report(path: String, hit: Dictionary) -> String:
	return (
		(
			"%s:%d carries the mutation marker `%s` -- a probe that was never reverted"
			% [path, int(hit["line"]), String(hit["text"])]
		)
		+ ". Restore the original line by hand, then grep this marker to confirm it is"
		+ " gone: `git restore` and `git checkout` take every other agent's uncommitted"
		+ " work with them and have destroyed finished work in this repo. If the"
		+ " mutation is still wanted, apply it to a temp copy and assert it there the"
		+ " way `uv run python -m tools cultivation mutate` does. A stranded mutation"
		+ " fails OPEN: the suite stays green while the behaviour is wrong."
	)


## Every `.gd` under `root`, recursively.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
