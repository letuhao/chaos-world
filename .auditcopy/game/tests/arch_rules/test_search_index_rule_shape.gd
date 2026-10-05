extends "res://tests/arch_rules/test_no_unbounded_wait.gd"

## The search-index rule (accept path 6) as CODE, both sides of the line, and the
## regression for INC-0022.
##
## `test_screen_reachability.gd` scans a file for call sites of one method:
##
##     var at := calls.find(needle)
##     while at != -1:
##         count += 1
##         at = calls.find(needle, at + needle.length())
##
## Every pass advances `at` by at least `needle.length()`, so the loop runs at
## most `calls.length() / needle.length()` times and then reads -1. It is bounded
## by the string it is walking, not by game state. None of the five accept paths
## could name it -- it moves no `+=` counter, drains nothing, fills nothing, and
## does not break -- so `test_no_unbounded_wait.gd` went RED on a correct loop
## and every agent since had to re-derive the bound by hand. The guard was
## wrong; the loop was right, and the loop was not edited to make it pass.
##
## The rule is deliberately narrow. `find(needle, at)` stands still and finds the
## same match forever; `find(needle, at - 1)` walks backwards and finds it
## forever too. Either one is a real unbounded wait, so both are pinned here as
## REJECTED. A guard test that proved only the accept side would pass against a
## rule loose enough to wave through INC-0001's shape.
##
## Fixtures rather than the shipped tree, because the reject side is a defect by
## construction and a defect may not be committed under `res://src` or
## `res://tests` -- the very scan under test would reject the file first. The one
## loop that IS in the tree is read from the tree rather than trusted as a copy.
##
## Run just this suite with:
##   uv run python -m tools test --suite test_search_index_rule_shape

# ── Fixtures: one loop each, written the way a real file writes them ──────────

## `_count_call_sites` transcribed from `tests/app/test_screen_reachability.gd`,
## one `while`, verbatim otherwise. Kept honest against the tree by
## `test_the_real_loop_is_this_rule_s_accept_case`, so a transcription cannot
## drift into a fixture only this rule accepts.
const SCAN_CALL_SITES := (
	"func _count_call_sites(text: String, method: String) -> int:\n"
	+ '\tvar needle := "%s(" % method\n'
	+ '\tvar calls := text.replace("func %s(" % method, "func _declared(")\n'
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at + needle.length())\n"
	+ "\treturn count\n"
)

## `find(needle, at)` hands back the index unchanged, so the pass re-reads the
## match it just counted and `at` never becomes -1.
const STAND_STILL := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at)\n"
	+ "\treturn count\n"
)

## `find(needle, at - 1)` walks BACKWARDS off the match it just took and re-finds
## it. The signed step is the case a bare "the body changed `x`, call it bounded"
## rule would wave straight through.
const WALK_BACKWARDS := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at - 1)\n"
	+ "\treturn count\n"
)

## A fixed positive step of one IS a real scan and it terminates, but it is not
## THIS rule: it walks a character at a time and re-counts every overlap, so the
## count it produces is wrong even though the loop ends. Accepting it would be a
## different, looser rule, which is why the step has to name the needle's own
## length rather than merely moving forward.
const FIXED_STEP := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at + 1)\n"
	+ "\treturn count\n"
)

## `n.size()` rather than `n.length()`: the same step written against a different
## container, and the needle here is a String. Declined rather than guessed.
const WRONG_LENGTH_CALL := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at + needle.size())\n"
	+ "\treturn count\n"
)

## The needle is computed, so `needle.length()` is no longer provable from source
## text. See the rule's honest-limits note: the fix would be the loop, not a wider
## rule here.
const COMPUTED_NEEDLE := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle.strip_edges())\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle.strip_edges(), at + needle.length())\n"
	+ "\treturn count\n"
)

## The step is behind an `if`, so a branch that never holds leaves `at` where it
## was. This is the "append behind a branch" hole rule 5 already refuses, reached
## through rule 6 instead: `count += 1` sits at the loop's own level here and
## rule 1 accepts the loop on it, so the only thing keeping this honest is that
## rule 6 proves its OWN step unconditionally.
const STEP_BEHIND_BRANCH := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tif needle.is_empty():\n"
	+ "\t\t\tat = calls.find(needle, at + needle.length())\n"
	+ "\treturn count\n"
)

## The advance belongs to a different function of the same file, which is exactly
## what rule 3 used to get wrong: a whole-file search reads `at = calls.find(...)`
## in `_close()` as this loop advancing `at`. It advances nothing.
const REMOTE_FIND := (
	"func _count(calls: String, needle: String) -> int:\n"
	+ "\tvar count := 0\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\treturn count\n"
	+ "func _close(calls: String, needle: String) -> int:\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\treturn calls.find(needle, at + needle.length())\n"
)

## INC-0001's own shape: a state value the loop never moves. No rule in the file
## can name it, and rule 6 must not have become the loophole that admits it.
const NEVER_TRUE := "func _wait() -> void:\n" + "\twhile pending == State.DONE:\n" + "\t\t_tick()\n"

## Rule 1 restated here rather than imported, so a future edit to the guard's own
## fixtures cannot quietly move this test's accept cases under it.
const LOCAL_COUNTER := "func _climb() -> void:\n" + "\twhile _step < 16:\n" + "\t\t_step += 1\n"

## Rule 5, likewise.
const LOCAL_FILL_TOWARD_COUNT := (
	"func _rows(target: int) -> Array:\n"
	+ "\tvar rows: Array = []\n"
	+ "\twhile rows.size() < target:\n"
	+ "\t\trows.append(1)\n"
	+ "\treturn rows\n"
)

## Rule 2, likewise: the `!= ""` listing terminator.
const LOCAL_DIR_ACCESS := (
	"func _each(root: String) -> Array:\n"
	+ "\tvar dir := DirAccess.open(root)\n"
	+ "\tvar entry := dir.get_next()\n"
	+ '\twhile entry != "":\n'
	+ "\t\tout.append(entry)\n"
	+ "\t\tentry = dir.get_next()\n"
	+ "\treturn out\n"
)

## Two loops in one file, and the advance in the SECOND one only. Rule 6 is scoped
## by the `while` line, so the first loop must not inherit the second's advance.
##
## The two conditions MUST differ, or the test cannot ask anything: the guard's
## entry point is `_is_bounded(condition, source)`, a pure function of those two
## arguments, so two loops with the same condition are the SAME query and must
## return the same verdict. The first fixture here read `while at != -1:` in both
## functions while the case asserted `false` then `true` over that identical pair,
## which no implementation can satisfy -- the case was red for a reason that had
## nothing to do with scoping. `_first` therefore walks a different index, so each
## query names its own loop and the verdict difference can only come from the
## scoping.
const TWO_LOOPS := (
	"func _first(calls: String, needle: String) -> int:\n"
	+ "\tvar other := calls.find(needle)\n"
	+ "\twhile other != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\tvar second := calls.find(needle, other + needle.length())\n"
	+ "func _second(calls: String, needle: String) -> int:\n"
	+ "\tvar at := calls.find(needle)\n"
	+ "\twhile at != -1:\n"
	+ "\t\tcount += 1\n"
	+ "\t\tat = calls.find(needle, at + needle.length())\n"
)

# ── The accept side ──────────────────────────────────────────────────────────


## Rule 6: the body's own assignment steps the tested index past the match, so
## `at` strictly grows on every pass and the loop ends when `find` returns -1.
func test_a_scan_advanced_past_its_own_match_is_bounded() -> void:
	assert_eq(_verdict(SCAN_CALL_SITES), true, "`find(needle, at + needle.length())` IS a scan")


## A fixture can be accepted by a rule that would reject the shipped loop if the
## two ever drift apart, so this reads the loop out of the tree and puts the
## real line through the real rule rather than trusting the transcription.
func test_the_real_loop_is_this_rule_s_accept_case() -> void:
	var path := "res://tests/app/test_screen_reachability.gd"
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text.is_empty(), true, "%s is readable" % path)
	var line := _scan_line_in(text)
	assert_ne(line, "", "%s still carries the find() scan" % path)
	assert_eq(_advance_steps_past_match(line, "at"), true, "the real advance is the accept case")


## Reached apart from `_is_bounded` so a failure names the rule that moved, and so
## this reads as what it is: a claim about rule 6, not about the whole guard.
func test_rule_six_alone_accepts_the_scan() -> void:
	assert_eq(
		_advances_search_index(SCAN_CALL_SITES, _only_condition(SCAN_CALL_SITES)),
		true,
		"rule 6 accepts the scan"
	)
	for source in [STAND_STILL, WALK_BACKWARDS, STEP_BEHIND_BRANCH, REMOTE_FIND]:
		assert_eq(
			_advances_search_index(source, _only_condition(source)),
			false,
			"rule 6 declines a loop that does not advance past its own match"
		)


## Two loops in one file: the first advances nothing, so rule 6 must not read the
## second loop's `find()` as its own.
func test_the_advance_is_scoped_to_its_own_loop() -> void:
	assert_eq(
		_is_bounded(_nth_condition(TWO_LOOPS, 0), TWO_LOOPS),
		false,
		"loop 1 advances nothing and must not inherit loop 2's find()"
	)
	assert_eq(
		_is_bounded(_nth_condition(TWO_LOOPS, 1), TWO_LOOPS),
		true,
		"loop 2 advances past its own match"
	)


## A tighter rule is only a fixed rule if the accept paths that were sound still
## match, so each is pinned on a string rather than on whatever the tree holds.
func test_the_other_accept_paths_still_match() -> void:
	assert_eq(_verdict(LOCAL_COUNTER), true, "rule 1: a counter the loop moves")
	assert_eq(_verdict(LOCAL_FILL_TOWARD_COUNT), true, "rule 5: a fill toward a fixed count")
	assert_eq(_verdict(LOCAL_DIR_ACCESS), true, 'rule 2: the `!= ""` listing terminator')


# ── The reject side: each of these really does spin ──────────────────────────


func test_find_at_the_same_index_is_not_a_scan() -> void:
	assert_eq(_verdict(STAND_STILL), false, "`find(needle, at)` stands still, so the match repeats")


func test_find_backwards_is_not_a_scan() -> void:
	assert_eq(
		_verdict(WALK_BACKWARDS), false, "`find(needle, at - 1)` re-finds the match it just took"
	)


func test_a_fixed_step_of_one_is_not_this_rule() -> void:
	assert_eq(_verdict(FIXED_STEP), false, "`at + 1` is not a step past the match it found")


func test_size_is_not_length() -> void:
	assert_eq(_verdict(WRONG_LENGTH_CALL), false, "`needle.size()` is not `needle.length()`")


func test_a_computed_needle_is_not_provable_from_source() -> void:
	assert_eq(_verdict(COMPUTED_NEEDLE), false, "a computed needle has no provable step")


func test_a_step_behind_a_branch_is_not_a_scan() -> void:
	assert_eq(
		_verdict(STEP_BEHIND_BRANCH),
		false,
		"a branch in front of the step is the same defect as rule 5's"
	)


func test_a_find_in_another_function_is_not_this_loops_scan() -> void:
	assert_eq(_verdict(REMOTE_FIND), false, "the body advances nothing, so `at` never leaves")


func test_inc_0001_shape_is_still_unbounded() -> void:
	assert_eq(
		_verdict(NEVER_TRUE), false, "a state value that never becomes true is still a runaway"
	)


# ── Helpers ──────────────────────────────────────────────────────────────────


## The `index`-th `while` condition of a fixture that deliberately carries two.
func _nth_condition(source: String, index: int) -> String:
	var found := _while_conditions(source)
	assert_eq(found.size(), 2, "the fixture carries exactly two `while`s")
	return String(found[index]) if found.size() == 2 else ""


## The verdict the tree scan reaches on a one-loop fixture.
func _verdict(source: String) -> bool:
	return _is_bounded(_only_condition(source), source)


## The one `while` condition a fixture carries, as the scan reports it. The size
## assertion is the guard against a fixture silently growing a second loop.
func _only_condition(source: String) -> String:
	var found := _while_conditions(source)
	assert_eq(found.size(), 1, "the fixture carries exactly one `while`")
	return String(found[0]) if found.size() == 1 else ""


## The line in `text` that reassigns `at` from a `find`, read from the tree rather
## than copied out of it, because the copy is what goes stale.
func _scan_line_in(text: String) -> String:
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("at = ") and line.contains(".find("):
			return line
	return ""
