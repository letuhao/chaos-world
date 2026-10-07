extends "res://tests/arch_rules/test_no_unbounded_wait.gd"

## The FileAccess read terminator (accept path 7) and the bounded map walk
## (accept path 8) as CODE, both sides of each line, and the regression for the
## two loops that taught them.
##
## `WorldmapAssets._ensure_loaded` reads its JSONL index with
## `while not file.eof_reached():` and `test_chunk_streaming.gd::_route` walks a
## BFS back-pointer map with `while cursor != from: cursor = prev[cursor]`.
## Neither is an unbounded wait, and neither loop was edited to fit the guard --
## the guard learned the two idioms, as it learned the `find()` scan before them.
##
## The reject side is the point. A rule that accepted the shape without proving
## the body advances THE SAME handle (7) would wave through a `get_position()`
## loop, which re-reads one position forever. A rule that accepted any
## `cursor = map[cursor]` (8) would wave through a walk over a map whose build
## re-parents its keys -- a build that can put `1 -> 2` and `2 -> 1` in the map,
## after which the walk follows a cycle forever. Each of those is pinned here as
## REJECTED, and each reject fixture is the smallest code that really can spin.
##
## Fixtures rather than the shipped tree for the reject side, because these loops
## are defects by construction and a defect may not be committed under
## `res://src` or `res://tests` -- the very scan under test would reject the file
## first. The two loops that ARE in the tree are read from the tree rather than
## trusted as copies, so a transcription cannot drift into a fixture only this
## rule accepts.
##
## Run just this suite with:
##   uv run python -m tools test --suite test_file_read_and_walk_rule_shape

# ── Fixtures: the read side (rule 7) ─────────────────────────────────────────

## The read every JSONL loader writes: `get_line()` consumes a line and advances
## the cursor, so `eof_reached()` turns true at the end of a finite file.
const FILE_READ := (
	"func _load(path: String) -> Array:\n"
	+ "\tvar out: Array = []\n"
	+ "\tvar file := FileAccess.open(path, FileAccess.READ)\n"
	+ "\twhile not file.eof_reached():\n"
	+ "\t\tvar line := file.get_line()\n"
	+ "\t\tout.append(line)\n"
	+ "\treturn out\n"
)

## `get_position()` READS the cursor; it does not advance it. The loop re-reads
## one position forever, and a `get_*` wildcard rule would accept it because the
## call is on the right handle.
const FILE_READ_STANDING_STILL := (
	"func _load(file: FileAccess) -> void:\n"
	+ "\twhile not file.eof_reached():\n"
	+ "\t\t_position = file.get_position()\n"
)

## The read is on a DIFFERENT handle: `file`'s cursor never moves, so its
## `eof_reached()` never turns true. The advancing read must be on the SAME
## handle the condition tests -- one `get_line()` elsewhere advances nothing here.
const FILE_READ_OTHER_HANDLE := (
	"func _load(file: FileAccess, cache: FileAccess) -> void:\n"
	+ "\twhile not file.eof_reached():\n"
	+ "\t\tcache.get_line()\n"
)

## The advancing read is behind an `if`: a branch that never holds leaves the
## handle exactly where it was, which is rule 5's append-behind-a-branch reached
## through a reader.
const FILE_READ_BEHIND_BRANCH := (
	"func _load(file: FileAccess) -> void:\n"
	+ "\twhile not file.eof_reached():\n"
	+ "\t\tif _has_line(file):\n"
	+ "\t\t\tfile.get_line()\n"
)

# ── Fixtures: the walk side (rule 8) ─────────────────────────────────────────

## `_route`'s shape: a capped BFS fills `prev` with one parent per key, guarding
## every placement with `has`, and seeds the root at `from`; the walk then
## follows `prev` until it reaches `from`. Every pass moves `cursor` to a value
## placed strictly earlier, and the map holds at most `VISIT_CAP` keys.
const WALK_BOUNDED_BUILD := (
	"func _route(from: int, to: int) -> Array:\n"
	+ "\tvar prev := {from: -1}\n"
	+ "\tvar queue: Array = [from]\n"
	+ "\twhile not queue.is_empty() and prev.size() < VISIT_CAP:\n"
	+ "\t\tvar current: int = queue.pop_front()\n"
	+ "\t\tfor next in [current + 1]:\n"
	+ "\t\t\tif prev.has(next):\n"
	+ "\t\t\t\tcontinue\n"
	+ "\t\t\tprev[next] = current\n"
	+ "\t\t\tqueue.append(next)\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tcursor = prev[cursor]\n"
	+ "\treturn []\n"
)

## The build RE-PARENTS: `prev[next] = current` with no `has` guard, so a key
## already in `prev` can be assigned again. Re-parenting is exactly how a cycle
## forms (`1 -> 2` set first, then `2 -> 1`), and a cyclic chain never reaches
## `from`, so the walk spins. This fixture is the reason rule 8 requires the
## guard, not merely a placement.
const WALK_REPARENTING_BUILD := (
	"func _route(from: int, to: int) -> Array:\n"
	+ "\tvar prev := {from: -1}\n"
	+ "\tvar queue: Array = [from]\n"
	+ "\twhile not queue.is_empty() and prev.size() < VISIT_CAP:\n"
	+ "\t\tvar current: int = queue.pop_front()\n"
	+ "\t\tfor next in [current + 1, current - 1]:\n"
	+ "\t\t\tprev[next] = current\n"
	+ "\t\t\tqueue.append(next)\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tcursor = prev[cursor]\n"
	+ "\treturn []\n"
)

## The build is NOT capped: `prev.size() < VISIT_CAP` is absent, so the map the
## walk stands on has no bounded size -- and this build itself never ends,
## because every pop appends a fresh key that will pop later.
const WALK_UNCAPPED_BUILD := (
	"func _route(from: int, to: int) -> Array:\n"
	+ "\tvar prev := {from: -1}\n"
	+ "\tvar queue: Array = [from]\n"
	+ "\twhile not queue.is_empty():\n"
	+ "\t\tvar current: int = queue.pop_front()\n"
	+ "\t\tfor next in [current + 1]:\n"
	+ "\t\t\tif prev.has(next):\n"
	+ "\t\t\t\tcontinue\n"
	+ "\t\t\tprev[next] = current\n"
	+ "\t\t\tqueue.append(next)\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tcursor = prev[cursor]\n"
	+ "\treturn []\n"
)

## The build is bounded, capped and guarded -- but lives in ANOTHER function. A
## walk may not borrow a bound it cannot see the map being built under.
const WALK_FILL_ELSEWHERE := (
	"func _build(prev: Dictionary, from: int) -> void:\n"
	+ "\tvar queue: Array = [from]\n"
	+ "\twhile not queue.is_empty() and prev.size() < VISIT_CAP:\n"
	+ "\t\tvar current: int = queue.pop_front()\n"
	+ "\t\tif prev.has(current + 1):\n"
	+ "\t\t\tcontinue\n"
	+ "\t\tprev[current + 1] = current\n"
	+ "\t\tqueue.append(current + 1)\n"
	+ "func _route(prev: Dictionary, from: int, to: int) -> Array:\n"
	+ "\tprev[from] = -1\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tcursor = prev[cursor]\n"
	+ "\treturn []\n"
)

## The body assigns a CONSTANT: `cursor` is reset to `to` every pass, so it never
## reaches `from` when the two differ. This is the "the body changed `x`" shape a
## bare assignment rule would accept.
const WALK_WITHOUT_A_LOOKUP := (
	"func _route(from: int, to: int) -> void:\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tcursor = to\n"
)

## The lookup is behind an `if`: a branch that never holds leaves the cursor
## where it was, which is INC-0001 reached through a back-pointer.
const WALK_LOOKUP_BEHIND_BRANCH := (
	"func _route(from: int, to: int) -> Array:\n"
	+ "\tvar prev := {from: -1}\n"
	+ "\tvar queue: Array = [from]\n"
	+ "\twhile not queue.is_empty() and prev.size() < VISIT_CAP:\n"
	+ "\t\tvar current: int = queue.pop_front()\n"
	+ "\t\tif prev.has(current + 1):\n"
	+ "\t\t\tcontinue\n"
	+ "\t\tprev[current + 1] = current\n"
	+ "\t\tqueue.append(current + 1)\n"
	+ "\tvar cursor: int = to\n"
	+ "\twhile cursor != from:\n"
	+ "\t\tif _steppable(cursor):\n"
	+ "\t\t\tcursor = prev[cursor]\n"
	+ "\treturn []\n"
)

# ── The accept paths the new rules must not have broken ──────────────────────

## Rule 2 restated here rather than imported, so a future edit to the guard's own
## fixtures cannot quietly move this test's accept cases under it.
const LOCAL_DIR_SENTINEL := (
	"func _each(root: String) -> Array:\n"
	+ "\tvar dir := DirAccess.open(root)\n"
	+ "\tvar entry := dir.get_next()\n"
	+ "\twhile not entry.is_empty():\n"
	+ "\t\tout.append(entry)\n"
	+ "\t\tentry = dir.get_next()\n"
	+ "\treturn out\n"
)

## Rules 1 and 5, likewise: the shapes the `_bounded_without_a_walk` extraction
## moved, pinned so the extraction cannot have dropped one of them.
const LOCAL_COUNTER := "func _climb() -> void:\n" + "\twhile _step < 16:\n" + "\t\t_step += 1\n"

const LOCAL_FILL_TOWARD_COUNT := (
	"func _rows(target: int) -> Array:\n"
	+ "\tvar rows: Array = []\n"
	+ "\twhile rows.size() < target:\n"
	+ "\t\trows.append(1)\n"
	+ "\treturn rows\n"
)

# ── Rule 7: the accept side, read from the tree ──────────────────────────────


## Rule 7 accepts its real loop, read out of the tree rather than copied from it:
## a transcription can drift into a fixture only this rule accepts, while the
## shipped file is what the guard actually scans.
func test_the_real_read_loop_is_this_rule_s_accept_case() -> void:
	var path := "res://src/modules/worldmap/asset_catalog.gd"
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text.is_empty(), true, "%s is readable" % path)
	var condition := _condition_containing(text, "eof_reached()")
	assert_ne(condition, "", "%s still reads its index through eof_reached()" % path)
	assert_eq(
		_is_file_read_terminator(condition, text), true, "the shipped read IS rule 7's accept case"
	)
	assert_eq(_is_bounded(condition, text), true, "and the guard accepts it as bounded")


## The rule as its own predicate, so a failure names rule 7 rather than the whole
## guard: the advancing read is accepted, and each way of reading nothing is not.
func test_rule_seven_alone_accepts_the_read_and_declines_the_rest() -> void:
	assert_eq(_file_read_verdict(FILE_READ), true, "`get_line()` on the same handle IS a read")
	for source in [FILE_READ_STANDING_STILL, FILE_READ_OTHER_HANDLE, FILE_READ_BEHIND_BRANCH]:
		assert_eq(
			_file_read_verdict(source),
			false,
			"rule 7 declines a body that does not advance the handle it tests",
		)


# ── Rule 8: the accept side, read from the tree ──────────────────────────────


## Rule 8 accepts its real loop, read out of the tree rather than copied from it,
## for the same reason as rule 7's: the transcription is not what the guard runs.
func test_the_real_walk_loop_is_this_rule_s_accept_case() -> void:
	var path := "res://tests/modules/worldmap/test_chunk_streaming.gd"
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text.is_empty(), true, "%s is readable" % path)
	var condition := _walk_condition(text)
	assert_ne(condition, "", "%s still walks a back-pointer map" % path)
	assert_eq(
		_walk_follows_capped_map(text, condition),
		true,
		"the shipped walk IS rule 8's accept case",
	)
	assert_eq(_is_bounded(condition, text), true, "and the guard accepts it as bounded")


## The rule as its own predicate, both sides: a build that is bounded, capped,
## guarded and seeded is a bound; each missing leg is not, and the fixture names
## which leg it removes.
func test_rule_eight_alone_accepts_the_bounded_walk_and_declines_the_rest() -> void:
	assert_eq(_walk_verdict(WALK_BOUNDED_BUILD), true, "a capped, guarded, seeded build IS a bound")
	for source in [
		WALK_REPARENTING_BUILD,
		WALK_UNCAPPED_BUILD,
		WALK_FILL_ELSEWHERE,
		WALK_WITHOUT_A_LOOKUP,
		WALK_LOOKUP_BEHIND_BRANCH
	]:
		assert_eq(
			_walk_verdict(source),
			false,
			"rule 8 declines a walk the evidence cannot support",
		)


# ── The reject side, through the whole predicate ─────────────────────────────


## The live shapes the whole guard must still refuse, so rule 7 cannot have
## become the loophole that admits a standing read.
func test_a_read_that_advances_nothing_still_fails_the_whole_predicate() -> void:
	assert_eq(_verdict(FILE_READ_STANDING_STILL), false, "a loop that reads nothing still fails")
	assert_eq(_verdict(FILE_READ_OTHER_HANDLE), false, "and one that reads another handle")


## The live shapes the whole guard must still refuse, so rule 8 cannot have
## become the loophole that admits a walk whose builder can cycle it.
func test_a_walk_the_evidence_cannot_support_still_fails_the_whole_predicate() -> void:
	for source in [
		WALK_REPARENTING_BUILD,
		WALK_UNCAPPED_BUILD,
		WALK_WITHOUT_A_LOOKUP,
		WALK_LOOKUP_BEHIND_BRANCH
	]:
		assert_eq(_walk_is_bounded(source), false, "the walk is still refused as unbounded")


# ── What the new rules must not have broken ──────────────────────────────────


func test_the_other_accept_paths_still_match() -> void:
	assert_eq(_verdict(LOCAL_COUNTER), true, "rule 1: a counter the loop moves")
	assert_eq(_verdict(LOCAL_FILL_TOWARD_COUNT), true, "rule 5: a fill toward a fixed count")
	assert_eq(_verdict(LOCAL_DIR_SENTINEL), true, "rule 2: the `is_empty()` listing terminator")


# ── Helpers ──────────────────────────────────────────────────────────────────


## Rule 7 on its own, on a one-`while` fixture.
func _file_read_verdict(source: String) -> bool:
	return _is_file_read_terminator(_only_condition(source), source)


## Rule 8 on its own. The walk fixtures carry TWO `while`s (the build and the
## walk), so this reads the walk's own condition rather than the single-loop
## helper the sibling suites use.
func _walk_verdict(source: String) -> bool:
	var condition := _walk_condition(source)
	assert_ne(condition, "", "the fixture carries a `cursor != from` walk to read")
	return _walk_follows_capped_map(source, condition)


## The WHOLE guard's verdict on a fixture's walk, again by its own condition.
func _walk_is_bounded(source: String) -> bool:
	var condition := _walk_condition(source)
	assert_ne(condition, "", "the fixture carries a `cursor != from` walk to read")
	return _is_bounded(condition, source)


## The condition the walk tests, wherever it sits in the fixture.
func _walk_condition(source: String) -> String:
	for condition in _while_conditions(source):
		if String(condition).contains("cursor != from"):
			return String(condition)
	return ""


## The first `while` condition whose text contains `needle`, or "".
func _condition_containing(text: String, needle: String) -> String:
	for condition in _while_conditions(text):
		if String(condition).contains(needle):
			return String(condition)
	return ""


## The one `while` condition a fixture carries, as the scan reports it. The size
## assertion is the guard against a fixture silently growing a second loop, which
## would make every verdict above read the first one twice.
func _only_condition(source: String) -> String:
	var found := _while_conditions(source)
	assert_eq(found.size(), 1, "the fixture carries exactly one `while`")
	return String(found[0]) if found.size() == 1 else ""


## The verdict the tree scan reaches on a one-loop fixture.
func _verdict(source: String) -> bool:
	return _is_bounded(_only_condition(source), source)
