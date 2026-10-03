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
## Findings are named one by one up to here, then only counted. A tree with hundreds
## of markers must not walk `TestCase.MAX_FAILURES` and `OS.crash` the process — the
## count assertion below still fails, and the first dozen still say where to look.
const MAX_REPORTED := 12
## A named count so an emptied or truncated table is a failure rather than a scan
## that has quietly stopped matching anything.
const SHAPE_COUNT := 5

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
##  - `#` or `//` plus the root: the token immediately after a comment introducer, so
##    prose about mutation passes, and so does the bare `MUTATE` in `spine.gd`.
##  - `XXX` plus `MUTAT`: the mutation-testing tombstone. A run of capital X is never
##    English.
##
## Case-sensitive on purpose, and load-bearing rather than fussy: the tree says
## "mutation" in lowercase prose on 172 lines, and every one has to survive this.
##
## The tokens are assembled from fragments so this file cannot trip its own scan.
## `test_the_guard_does_not_flag_its_own_source` holds that line: a guard nobody can
## write down is a guard nobody can extend, and spelling a token out in a clarifying
## comment fails the build on the guard instead of on a probe. Not hypothetical — it
## happened to this file while the guard was being built.
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
	assert_eq(SHAPES.size(), SHAPE_COUNT, "the shape table is the size it claims")
	for shape in SHAPES:
		var sample := _sample_for(shape)
		var hits := _markers_in(sample)
		assert_eq(hits.size(), 1, "the shape that forbids `%s` also finds it" % sample)
		if hits.size() == 1:
			assert_eq(int(hits[0]["line"]), 1, "and reports the line it is written on")


func test_the_incident_s_own_marker_shape_is_what_fires() -> void:
	# The one marker this guard exists for, written every way it could plausibly
	# have been written: behind a comment mark, bare in code, with nothing after the
	# id, and behind a doc-comment. The bare form is the case that matters — the
	# first cut of the shape table demanded a whitespace run AFTER the hyphen, so it
	# matched none of these and the guard was clean against the very marker it was
	# built from. Deriving every positive sample from the shape table is what hid
	# that: the table and its own proof agreed with each other, and both were wrong
	# about the incident. So the incident is pinned here by hand as well.
	for sample in [
		"#" + MARKER + "-M1 core commit removed",
		MARKER + "-M1 core commit removed",
		MARKER + "-M1",
		MARKER + "-2",
		"## " + MARKER,
		"#     " + MARKER,
		"var x := 1  # " + MARKER + "-M4 removed",
	]:
		assert_eq(_markers_in(sample).size(), 1, "`%s` is the incident's own shape" % sample)


func test_the_shapes_decline_the_prose_the_shipped_tree_actually_contains() -> void:
	# Transcribed verbatim from files that really do use the word, so each near-miss
	# is pinned beside the shape that could have taken it. All four are lower case or
	# differently punctuated, which is the whole reason the table is case-sensitive.
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
	# the token out.
	var text := FileAccess.get_file_as_string((get_script() as Script).resource_path)
	assert_ne(text.is_empty(), true, "the guard can read its own source")
	var hits := _markers_in(text)
	assert_eq(hits.size(), 0, "the guard's own source is clean: %s" % _describe(hits))


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


## Every marker in `text`, as `{"line": int, "text": String}`, in file order.
func _markers_in(text: String) -> Array[Dictionary]:
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
				hits.append({"line": number + 1, "text": line.substr(at, end - at)})
				at = end
			else:
				at += 1
	return hits


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
