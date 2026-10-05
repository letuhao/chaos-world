extends "res://tests/arch_rules/test_no_unbounded_wait.gd"

## The drain rule (accept path 3) as CODE, and the regression for the hole it had.
##
## `test_no_unbounded_wait.gd` proved a `while` terminates by five accept paths.
## Four of them look at the loop's OWN body. The drain path did not: it searched
## the WHOLE FILE for `<container>.<verb>`, so an `.erase(...)` in a different
## function of the same file was read as this loop shrinking the container it
## tests. A loop that leaves the container exactly as full as it found it was
## therefore accepted, which is INC-0001's shape wearing a plausible hat: no
## counter the loop moves, no exit, no DirAccess sentinel, and it never ends.
##
## The same verb list carried `clear()`, which is worse. It empties the container
## ONCE and advances nothing: `while not queue.is_empty(): queue.clear()` exits
## by accident, but `while queue.size() > 0:` over the same body spins on an
## emptied container forever, and `clear()` is not a per-pass decrement of the
## condition the loop tests. It is not a drain.
##
## Fixtures rather than the shipped tree, because these loops are defects by
## construction and a defect may not be committed under `res://src` or
## `res://tests` — the very scan under test would reject the file first.
##
## Run just this suite with:
##   uv run python -m tools test --suite arch_rules

# ── Fixtures: one loop each, written the way a real file writes them ──────────

## The drain every real bounded wait in this repo writes, so the fixture that
## must stay bounded really is one.
const LOCAL_POP := (
	"func _drain() -> Array:\n"
	+ "\tvar queue: Array = [1, 2, 3]\n"
	+ "\twhile not queue.is_empty():\n"
	+ "\t\tvar item: int = queue.pop_back()\n"
	+ "\t\tout.append(item)\n"
	+ "\treturn out\n"
)

## The loop body pops `outgoing`, a different container, while a LATER function
## of the same file pops `queue`. Two properties in one fixture: the body leaves
## `queue` exactly as full as it found it, and the removed whole-file search
## found `queue.pop_back` and read it as the drain.
const REMOTE_POP := (
	"func _drain() -> Array:\n"
	+ "\tvar queue: Array = [1, 2, 3]\n"
	+ "\twhile not queue.is_empty():\n"
	+ "\t\toutgoing.pop_back()\n"
	+ "\treturn out\n"
	+ "func _close() -> void:\n"
	+ "\tqueue.pop_back()\n"
)

## `queue.erase(0)` in another function of the same file. The whole-file search
## read it as this loop shrinking `queue`. It shrinks nothing.
const REMOTE_ERASE := (
	"func _drain() -> void:\n"
	+ "\twhile not queue.is_empty():\n"
	+ "\t\t_total += 1\n"
	+ "func _close() -> void:\n"
	+ "\tqueue.erase(0)\n"
)

## One `queue.clear()` on the first pass, then forever on an emptied container.
const CLEAR_ONCE := (
	"func _drain() -> void:\n"
	+ "\twhile not queue.is_empty():\n"
	+ "\t\tqueue.clear()\n"
	+ "\t\t_total += 1\n"
)

## Rule 1, the counter the loop moves. Nothing to do with the drain, and the
## reason the scan as a whole is not blind.
const COUNTER := "func _climb() -> void:\n" + "\twhile _step < 16:\n" + "\t\t_step += 1\n"

## Rule 5: `rows` grows by one on every pass toward a fixed count.
const FILL_TOWARD_COUNT := (
	"func _rows(target: int) -> Array:\n"
	+ "\tvar rows: Array = []\n"
	+ "\twhile rows.size() < target:\n"
	+ "\t\trows.append(1)\n"
	+ "\treturn rows\n"
)

# ── What the removed whole-file search believed ──────────────────────────────


func test_the_removed_drain_check_accepted_these_loops() -> void:
	# The three defects, transcribed as the OLD helper read them rather than deleted
	# with it: a regression needs something that can still fail, and this is the
	# exact question the removal answered. A defect may not be committed under
	# `res://src` or `res://tests`, so the loops live here as strings.
	assert_eq(
		_old_drain_accepts(REMOTE_ERASE),
		true,
		"an `erase` in another function used to count as this loop's drain",
	)
	assert_eq(
		_old_drain_accepts(CLEAR_ONCE),
		true,
		"and so did a `clear()` that empties the container once and stops",
	)
	assert_eq(
		_old_drain_accepts(REMOTE_POP),
		true,
		"and a `pop_back()` outside the body",
	)
	# The replacement, on the same three inputs. Without these the transcription
	# above would be a claim about dead code rather than about a change.
	assert_eq(_drain_verdict(CLEAR_ONCE), false, "the body-scoped check declines the clear")
	assert_eq(_drain_verdict(REMOTE_ERASE), false, "and the unrelated erase")
	assert_eq(_drain_verdict(REMOTE_POP), false, "and the pop outside the body")


## The removed whole-file search, verbatim: `<container>.<verb>` anywhere in the
## file was read as the loop shrinking it.
func _old_drain_accepts(source: String) -> bool:
	for verb in ["pop_front", "pop_back", "pop_at", "remove_at", "erase", "clear"]:
		if source.contains("queue." + verb):
			return true
	return false


# ── The rule as it stands: the body's own mutation, `clear()` excluded ───────


## An `.erase(...)` outside the loop body shrinks nothing the loop tests, so the
## loop is unbounded and the build must fail on it.
func test_an_erase_outside_the_loop_body_is_not_a_drain() -> void:
	assert_eq(_verdict(REMOTE_ERASE), false, "`queue` is never shrunk by the loop")


## The same hole reached through a different verb: a pop on a neighbouring
## container is not a drain of the one the condition tests.
func test_a_pop_on_another_container_is_not_a_drain() -> void:
	assert_eq(_verdict(REMOTE_POP), false, "`outgoing` is not the container the loop tests")


## `clear()` empties the container once and advances nothing, so the loop's exit
## condition is only ever satisfied by accident.
func test_clear_is_not_a_drain() -> void:
	assert_eq(_verdict(CLEAR_ONCE), false, "one clear ends nothing the loop re-tests")


# ── What the tightening must not have broken ─────────────────────────────────


func test_a_loop_that_drains_the_container_it_tests_is_still_bounded() -> void:
	assert_eq(_verdict(LOCAL_POP), true, "a `pop_back()` in the body IS the drain")


## A tighter rule is only a fixed rule if the accept paths that were sound still
## match, so each is pinned on a string rather than on whatever the tree holds.
func test_the_other_accept_paths_still_match() -> void:
	assert_eq(_verdict(COUNTER), true, "rule 1: a counter the loop moves")
	assert_eq(_verdict(FILL_TOWARD_COUNT), true, "rule 5: a fill toward a fixed count")


# ── Helpers ──────────────────────────────────────────────────────────────────


## The verdict the tree scan reaches on a one-loop fixture.
func _verdict(source: String) -> bool:
	return _is_bounded(_only_condition(source), source)


## Rule 3 on its own: the container the loop tests, shrunk by the loop's OWN
## body. Asserted apart from `_is_bounded` so a failure says which path moved.
func _drain_verdict(source: String) -> bool:
	var condition := _only_condition(source)
	var drained := _drained_container(condition)
	return drained != "" and _shrinks_container(_loop_body(source, condition), drained)


## The one `while` condition a fixture carries, as the scan reports it. The size
## assertion is the guard against a fixture silently growing a second loop, which
## would make every verdict above read the first one twice.
func _only_condition(source: String) -> String:
	var found := _while_conditions(source)
	assert_eq(found.size(), 1, "the fixture carries exactly one `while`")
	return String(found[0]) if found.size() == 1 else ""
