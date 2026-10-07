extends TestCase

## The disk-safety rule as CODE, for every production script rather than for one
## module. AGENTS.md requires that "every `while` on game state needs a bounded,
## SMALL cap that names the condition which failed to converge", because a wait
## whose exit condition can never be met does not fail -- it spins and writes
## gigabytes into the user's C: drive. Prose does not enforce that; this does.
##
## Generalized from the module-local guard in
## `tests/modules/mind_cultivation/test_mind_deviation_recovery.gd`, which exists
## because that module shipped the 1 GB/s loop. That guard only ever read its own
## directory; this one reads all of `res://src` AND all of `res://tests` -- the
## loop that actually filled the disk was a TEST's, so a guard that stopped at
## `res://src` would not have caught it.
##
## A loop is accepted only if it can be shown to terminate:
##
## 1. it reads a counter the loop itself moves (`+=` / `-=`), which is the shape
##    of every bounded wait in the repo;
## 2. it is the `DirAccess` terminator (`!= ""`, or `not entry.is_empty()` fed by
##    `dir.get_next()`), bounded by the directory's contents rather than game state;
## 3. it drains a container, proven by a mutating `pop_*` / `remove_*` / `erase`
##    on the very container the condition tests, INSIDE ITS OWN BODY -- each call
##    strictly shrinks it, once per pass. `clear()` is not one of them: it empties
##    a container once and leaves the loop spinning on an empty one;
## 4. its body breaks or returns, so an unreachable condition still ends the loop;
## 5. it fills a container toward a fixed count, proven by an `append` to that
##    container at the loop's own indentation -- not nested in a branch, because
##    an append behind a branch that never holds is the same defect;
## 6. it advances a SEARCH INDEX strictly past its own match, proven by
##    `<index> = <text>.find(<needle>, <index> + <needle>.length())` in the body's
##    own assignment to the identifier the condition tests;
## 7. it is the `FileAccess` READ terminator (`not <file>.eof_reached()`), fed by
##    a cursor-advancing reader on the SAME `<file>` at the loop's own
##    indentation -- rule 2's sibling for a file rather than a listing;
## 8. it follows a cursor through a map (`<cursor> = <map>[<cursor>]`) that the
##    SAME function built with a preceding, already-bounded loop, capped at a
##    fixed size and placed under a `has` guard.
##
## None of the eight can express the original defect, which was `while <a state
## value that never becomes true>`. Note the honest limit -- a `break` or an
## `append` behind a condition that never holds is still an unbounded wait, and no
## static scan can see that. This catches the shape; it does not prove convergence.
## The older note about the five being the whole list was wrong the moment
## `test_screen_reachability.gd` grew a `find()` scan that the first five could
## not name, which is INC-0022. The lesson held twice more: `asset_catalog.gd`
## reads its JSONL index with `while not file.eof_reached():` and
## `test_chunk_streaming.gd` walks a back-pointer map, and neither shape is
## expressible by the six -- so seven and eight were added, each only after the
## guard went RED on a loop that terminates.
##
## The span-bounded `for` rule has no condition for any of this to read, so it
## lives in its own suite: `test_no_for_loop_bounded_by_span.gd`.

const SRC_ROOT := "res://src"
const TESTS_ROOT := "res://tests"
## The `FileAccess` readers that ADVANCE the file cursor. Named, never a `get_*`
## wildcard: `get_position()` and `get_error()` match the wildcard and advance
## nothing, so a pattern rule would wave through a loop that re-reads its own
## position forever. `get_as_text()` consumes the rest of the file, which is a
## cursor advance like any other -- the next `eof_reached()` is true.
const FILE_CURSOR_READERS: Array[String] = [
	"get_line",
	"get_csv_line",
	"get_as_text",
	"get_buffer",
	"get_string",
	"get_pascal_string",
	"get_var",
	"get_8",
	"get_16",
	"get_32",
	"get_64",
	"get_float",
	"get_double",
	"get_real",
]


func test_no_production_wait_is_unbounded() -> void:
	var audited := 0
	var bounded := 0
	for path in _gdscript_files(SRC_ROOT) + _gdscript_files(TESTS_ROOT):
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		for entry in _while_conditions(text):
			audited += 1
			if _is_bounded(entry, text):
				bounded += 1
			else:
				assert_eq(
					true,
					false,
					(
						(
							"%s has an unbounded `while %s` -- a wait whose exit "
							% [path.get_file(), entry]
						)
						+ "condition can never be met will spin and fill the disk"
					)
				)
	# Both counts must be non-zero, or the scan has gone blind and would pass
	# forever. `bounded` proves the accept paths are still exercised rather than
	# every loop being waved through by a rule that no longer matches.
	assert_eq(audited > 0, true, "the scan still finds `while` loops to audit")
	assert_eq(bounded > 0, true, "the accept paths still match real loops")


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


## Every `while` condition in a file, reassembled across continuation lines and
## stripped of comments, so a multi-line condition cannot hide from the scan.
func _while_conditions(text: String) -> Array[String]:
	var found: Array[String] = []
	var collecting := false
	var depth := 0
	var current := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if not collecting and line.begins_with("while "):
			collecting = true
			current = line.substr(6)
			depth = _paren_depth(current)
			if depth <= 0:
				found.append(current)
				collecting = false
				current = ""
			continue
		if collecting:
			current += " " + line
			depth = _paren_depth(line)
			if depth <= 0:
				found.append(current)
				collecting = false
				current = ""
	return found


func _paren_depth(text: String) -> int:
	var depth := 0
	for index in text.length():
		match text[index]:
			"(":
				depth += 1
			")":
				depth -= 1
	return depth


## Rules 1, 3, 5 and 6, in one predicate each. They are gathered here so
## `_is_bounded` can stay a readable list without tripping `max-returns` -- the
## `if ...: return true` chain this grew would not lint at seven statements, and
## a guard that cannot be formatted and linted cannot be changed safely.
func _bounded_by_shape(condition: String, source: String) -> bool:
	# 1. A counter this loop moves.
	if _moves_a_counter(condition, source):
		return true
	# 3. A container the body provably shrinks.
	var drained := _drained_container(condition)
	if drained != "" and _shrinks_container(_loop_body(source, condition), drained):
		return true
	# 5. A container the body provably fills toward a fixed count.
	if _fills_unconditionally(source, condition):
		return true
	# 6. A search index the body advances strictly past the match it just took.
	return _advances_search_index(source, condition)


func _is_bounded(condition: String, source: String) -> bool:
	if _bounded_without_a_walk(source, condition):
		return true
	# 8. A cursor that unconditionally steps through a map the same function
	# built under a fixed size cap.
	return _walk_follows_capped_map(source, condition)


## Rules 2, 7, 1, 3, 5, 6 and 4 -- every accept path that predates the map walk,
## in the order they have always been checked. Rule 8 proves its FILL with THIS,
## never with `_is_bounded`: a fill that was itself only accepted by citing
## another map walk would make the rule self-supporting, and the base of that
## chain would never stand on a shape that predates it.
func _bounded_without_a_walk(source: String, condition: String) -> bool:
	# 2. The DirAccess terminator: `get_next()` returns "" at the end of a listing,
	# written either as `!= ""` or as `not entry.is_empty()`.
	if condition.contains('!= ""'):
		return true
	if _is_dir_access_sentinel(condition, source):
		return true
	# 7. The FileAccess READ terminator: `eof_reached()` turns true at the end of
	# the file, and the body advances the same handle.
	if _is_file_read_terminator(condition, source):
		return true
	if _bounded_by_shape(condition, source):
		return true
	# 4. A body that leaves the loop on its own.
	return _body_contains_exit(source, condition)


## Rule 1 on its own: the condition reads an identifier the loop moves with
## `+=` / `-=`. Whole-file, as it has always been -- an assignment is not a step,
## which is the whole reason rule 6 had to be written separately.
func _moves_a_counter(condition: String, source: String) -> bool:
	for identifier in _identifiers(condition):
		if source.contains(identifier + " += ") or source.contains(identifier + " -= "):
			return true
	return false


## 6. `while at != -1:` whose body sets `at = <text>.find(<needle>, at +
## <needle>.length())` -- INC-0022, in `tests/app/test_screen_reachability.gd`.
## A scan index is a counter, only the counter is an index into a String and the
## step is the match it just took, so the first five accept paths could not name
## it and the guard cried wolf on a loop that terminates.
##
## WHAT THIS ADMITS, EXACTLY. The condition must test an identifier the body
## assigns, and that assignment must hand `find` a second argument of the form
## `<index> + <needle>.length()`: the same index, plus the length of the needle
## being searched for. `find` then reports a match at `>= index + needle.length()`,
## so `index` strictly grows on every pass by at least one character, and it
## starts at or above 0 -- so it passes the end of the text, where `find` returns
## -1 and the loop ends. Iterations are therefore at most
## `<text>.length() / <needle>.length()`; nothing about the loop's exit condition
## can change that.
##
## WHY IT CANNOT ADMIT AN UNBOUNDED WAIT. INC-0001's shape is `while <a state
## value that never becomes true>`, where the loop has no `while` body that moves
## anything. Here the body moves a name the condition itself tests, on EVERY
## pass and with no branch in front of it -- a branch would be the same defect an
## append behind one is. A strictly positive step is the whole proof: a body that
## assigns the tested index and does not advance it is rejected (rule 1's counter
## search only reads `+=` / `-=`, so an assignment-based spin reaches none of the
## five other paths either), which is why `at = s.find(n, at)` and
## `at = s.find(n, at - 1)` are declined -- the first stands still, the second runs
## backwards, and neither can revisit the match it just took.
##
## HONEST LIMITS. The needle must be a plain name, because the rule reads
## `<needle>.length()` as the step and a computed needle such as
## `s.find(n.strip_edges(), ...)` is not one. The step is assumed positive, which
## holds because `String.length()` is non-negative, and an empty needle is the one
## input that breaks the reasoning -- `find` returns its `from` for an empty needle,
## so the scan never walks off the end. That is a defect in the CALLER, not
## something this rule can see from source text; `tests/app/test_screen_reachability.gd`
## builds its needle from a method name and cannot be empty. If a loop wants a
## step this rule cannot name, the fix is the loop, not a wider rule here.


## The machine behind rule 6, and nothing else. Proved on the body's own lines
## so a `find()` in a DIFFERENT function cannot be read as this loop advancing
## anything -- the same scoping hole the drain rule had (INC-0016's finding).
func _advances_search_index(source: String, condition: String) -> bool:
	var lines := _loop_body_lines(source, condition)
	if lines.is_empty():
		return false
	var shallowest := 1 << 30
	for entry in lines:
		shallowest = mini(shallowest, int(entry.split("|", true, 1)[0]))
	for index in _identifiers(condition):
		if not condition.contains(index):
			continue
		for entry in lines:
			var parts := entry.split("|", true, 1)
			if int(parts[0]) != shallowest:
				continue
			if _advance_steps_past_match(parts[1], index):
				return true
	return false


## `<index> = <text>.find(<needle>, <index> + <needle>.length())`, on ONE line,
## to a bare name, with the same needle on both sides of the step.
##
## Narrow on purpose, and the narrowness IS the rule: `find(needle, at)` leaves
## the index where it was so the same match is found again, and `find(needle,
## at - 1)` walks backwards so the match is found forever. Neither is a scan, and
## a loop written over either spins -- which is why there is no general "the body
## reassigns the tested identifier" rule here to wave them through.
func _advance_steps_past_match(line: String, index: String) -> bool:
	var needle := _find_needle(line)
	if needle == "":
		return false
	var step := index + " + " + needle + ".length()"
	for arguments in _find_calls(line, 1) + _find_calls(line, 2):
		if _scan_step(arguments, step) != "":
			return true
	return false


## Every `.find(` call in `line`, grouped by which argument `from` is: the
## one-argument form, then the two-argument one. Scanning the CALLS rather than
## the whole line is what keeps an unrelated `find(` from being read as a scan;
## the argument count comes from the source text because a GDScript `find` takes
## `from` optionally and the scan does not know the value.
func _find_calls(line: String, wanted_arguments: int) -> Array[String]:
	var out: Array[String] = []
	var cursor := 0
	while true:
		var at := line.find(".find(", cursor)
		if at < 0:
			break
		var start := at + 6
		var depth := 1
		var end := start
		while end < line.length():
			match line[end]:
				"(":
					depth += 1
				")":
					depth -= 1
			if depth == 0:
				break
			end += 1
		var arguments := line.substr(start, end - start)
		if _argument_count(arguments) == wanted_arguments:
			out.append(arguments)
		cursor = end + 1
	return out


## The arguments of a call, split on commas at depth 0 so `find(x, a + f(b))`
## stays two arguments rather than four.
func _argument_count(arguments: String) -> int:
	var count := 1 if arguments.strip_edges() != "" else 0
	var depth := 0
	for index in arguments.length():
		match arguments[index]:
			"(", "[", "{":
				depth += 1
			")", "]", "}":
				depth -= 1
			",":
				if depth == 0:
					count += 1
	return count


## The first argument of a `find` call when it is a bare name, else `""`. A
## computed needle (`a + "b"`, `n.strip_edges()`) is declined on purpose: the
## proof that the step is non-negative is `needle.length()`, which needs a
## needle.
func _find_needle(line: String) -> String:
	# The needle is the FIRST argument of the call the step lives in, so the
	# two-argument form must be read too: the shipped line is
	# `at = calls.find(needle, at + needle.length())`, which carries no
	# one-argument call at all. Reading only the one-argument form made the rule
	# decline the very loop it was written to accept (INC-0022), so the guard
	# cried wolf on a bounded scan and rule 6 could never fire.
	for arguments in _find_calls(line, 1) + _find_calls(line, 2):
		var first := _split_arguments(arguments)[0]
		if _identifiers(first).size() == 1:
			return first
	return ""


## The `<needle>.length()` term of the second argument, when that argument is
## exactly the one the rule admits. `at - 1`, `at + 2`, `at + n.size()` and a
## trailing `+ 1` all read here as something other than a step past the match, so
## they are declined rather than approximated.
func _scan_step(arguments: String, step: String) -> String:
	var parts := _split_arguments(arguments)
	return step if parts.size() == 2 and parts[1].strip_edges() == step else ""


## Comma-separated arguments at depth 0, each stripped.
func _split_arguments(arguments: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var depth := 0
	for index in arguments.length():
		var character := arguments[index]
		match character:
			"(", "[", "{":
				depth += 1
			")", "]", "}":
				depth -= 1
		if character == "," and depth == 0:
			out.append(current.strip_edges())
			current = ""
			continue
		current += character
	out.append(current.strip_edges())
	return out


## `while not entry.is_empty():` fed by `entry = dir.get_next()`. The empty-string
## sentinel written in `is_empty()` form; the engine still ends the listing, so
## this is rule 2 and not a new exemption.
func _is_dir_access_sentinel(condition: String, source: String) -> bool:
	for identifier in _identifiers(condition):
		if (
			condition.contains("not " + identifier + ".is_empty()")
			and source.contains(identifier + " = dir.get_next()")
		):
			return true
	return false


## 7. `while not file.eof_reached():` fed by a cursor-advancing read on the SAME
## handle -- the shape `WorldmapAssets._ensure_loaded` reads its JSONL index
## with, and rule 2's sibling for a file rather than a listing.
##
## WHAT THIS ADMITS, EXACTLY. The condition must negate `eof_reached()` on a
## named handle, and the loop's OWN body -- at the loop's own indentation, not
## nested in a branch -- must call one of `FILE_CURSOR_READERS` on that same
## handle. A `FileAccess` cursor only moves forward as bytes are consumed:
## `eof_reached()` cannot turn false again, and a read that consumes at least
## one byte strictly advances the cursor toward the end of a finite file. So
## every pass moves the cursor the condition reads, and the loop ends the pass
## the read consumes the file's last byte. `get_as_text()` -- the one reader
## that consumes everything left -- ends it in a single pass.
##
## WHY IT CANNOT ADMIT AN UNBOUNDED WAIT. INC-0001's shape is `while <a state
## value that never becomes true>` where nothing in the body moves it. Here the
## condition reads one handle and the body provably advances THAT handle: a
## `file.get_position()` loop (a `get_*` that does not advance) is declined
## because the reader list is named, not a wildcard; a `cache.get_line()` beside
## a `file.eof_reached()` is declined because the handle differs; and a read
## behind an `if` is declined because the rule reads only the body's own
## indentation, the same place rule 5 refuses an append behind a branch.
##
## HONEST LIMITS. Only the `not <file>.eof_reached()` spelling is admitted --
## `!file.eof_reached()` and `file.eof_reached() == false` are the same loop in
## another coat, and the fix is the loop, not a wider rule. A DISJUNCTION is
## declined (`not eof_reached() or X` keeps running after EOF while `X` holds;
## `and` is admitted because the whole condition goes false the moment the file
## ends). The step is assumed to consume at least one byte, which `get_line()`
## and `get_as_text()` do but a zero-length `get_buffer(0)` does not -- the one
## argument a static scan cannot evaluate, the way rule 6 cannot evaluate an
## empty needle. The reader list is authored, so a correct loop over an API added
## later is declined until the list says so. And a read at the loop's own
## indentation is still skippable by an earlier unconditional `continue` in the
## body -- the residue every body-shape rule in this file shares, and one no
## static scan can close.
func _is_file_read_terminator(condition: String, source: String) -> bool:
	if condition.contains(" or "):
		return false
	for identifier in _identifiers(condition):
		if condition.contains("not " + identifier + ".eof_reached()"):
			return _body_advances_handle(source, condition, identifier)
	return false


## Whether the loop's own body calls a cursor-advancing reader on `handle`, at
## the body's shallowest indentation. A read one level deeper is behind a branch,
## which is the defect rule 5 already refuses for an append: the branch may never
## hold, the handle never moves, and the loop spins on a file that never ends.
func _body_advances_handle(source: String, condition: String, handle: String) -> bool:
	var lines := _loop_body_lines(source, condition)
	if lines.is_empty():
		return false
	var shallowest := 1 << 30
	for entry in lines:
		shallowest = mini(shallowest, int(entry.split("|", true, 1)[0]))
	for entry in lines:
		var parts := entry.split("|", true, 1)
		if int(parts[0]) != shallowest:
			continue
		for reader in FILE_CURSOR_READERS:
			if parts[1].contains(handle + "." + reader + "("):
				return true
	return false


## `while rows.size() < needed:` whose body appends to `rows` on EVERY pass. Each
## pass grows the container by one toward a fixed count, so it ends in at most
## `needed` iterations. The append must sit at the loop's own indentation, not
## inside an `if`: an append behind a branch that never holds is the original
## defect wearing a different hat, and this must not wave it through.
func _fills_unconditionally(source: String, condition: String) -> bool:
	var lines := _loop_body_lines(source, condition)
	if lines.is_empty():
		return false
	var shallowest := 1 << 30
	for entry in lines:
		shallowest = mini(shallowest, int(entry.split("|", true, 1)[0]))
	for container in _identifiers(condition):
		if not condition.contains(container + ".size()"):
			continue
		for entry in lines:
			var parts := entry.split("|", true, 1)
			if int(parts[0]) != shallowest:
				continue
			if parts[1].contains(container + ".append("):
				return true
	return false


## The container a drain-loop tests, or `""`. `not pending.is_empty()`,
## `history.size() > MAX` and `edges.size() < count` all name one.
func _drained_container(condition: String) -> String:
	for identifier in _identifiers(condition):
		if (
			condition.contains(identifier + ".is_empty()")
			or condition.contains(identifier + ".size()")
		):
			return identifier
	return ""


## The container the loop TESTS, shrunk by the loop's OWN body. Both halves are
## scoped to the body, and the earlier version of this searched the whole file,
## which made an `.erase(...)` in a different function read as this loop draining
## it — so a loop that left the container exactly as full as it found it passed.
## `clear()` is deliberately absent: it empties the container ONCE and advances
## nothing, so `while queue.size() > 0:` over such a body spins on an emptied
## container forever. `tests/arch_rules/test_drain_rule_shape.gd` pins both.
func _shrinks_container(body: String, container: String) -> bool:
	for verb in ["pop_front", "pop_back", "pop_at", "remove_at", "erase"]:
		if body.contains(container + "." + verb):
			return true
	return false


## True when the LOOP'S OWN BODY leaves the loop. Scoped to the body on purpose:
## searching the whole file for any `return` would accept every loop in the repo,
## because every file has one somewhere, and a guard that cannot fail is worse
## than no guard. A `break` behind a condition that never holds is still an
## unbounded wait and no static scan can see that -- documented on the class.
func _body_contains_exit(source: String, condition: String) -> bool:
	var body := _loop_body(source, condition)
	for keyword in ["break", "return"]:
		if body.contains(keyword):
			return true
	return false


## 8. `while cursor != from: cursor = prev[cursor]` -- a walk that follows
## back-pointers through a map the SAME function built, the shape
## `test_chunk_streaming.gd::_route` walks its BFS tree with.
##
## WHAT THIS ADMITS, EXACTLY. The condition must test one named cursor against a
## sentinel with `!=`, and the body -- at the loop's own indentation, so an
## unconditional step and never one behind a branch -- must reassign that cursor
## from a map lookup on ITSELF (`cursor = prev[cursor]`). The map must then be
## evidenced three ways IN THE SAME FUNCTION, all of it before the walk:
##
##   - a PRECEDING loop the guard already accepts as bounded (`_bounded_without_a_walk`, so a
##     second map walk cannot vouch for this one) that places keys into the map;
##   - that loop's condition caps `<map>.size()` against a FIXED count -- an
##     integer literal or a `CONSTANT_CASE` constant, never a caller's variable;
##   - EVERY key the loop places into the map is also checked with
##     `<map>.has(<key>)` before placement, which is what stops a key from being
##     re-parented and is what makes a cycle impossible in the admitted idiom;
##   - and the map is seeded at the sentinel (`{from: -1}` or `map[from] = ...`),
##     so the chain the walk follows ends where the walk stops.
##
## Given those, every pass moves the cursor to a value the map already holds
## (the seeded-or-placed keys), the map holds at most the capped number of keys,
## and each key has one parent that was placed before it -- so the walk visits
## at most `<cap>` distinct keys and reaches the sentinel, which is what the
## loop tests.
##
## WHY IT CANNOT ADMIT AN UNBOUNDED WAIT. INC-0001 is a body that moves nothing.
## Here the body unconditionally reassigns the tested cursor, and the rule
## refuses to accept the step on its own: without a bounded, capped, guarded,
## seeded build in the same function, the lookup is just an assignment to an
## unknown structure and is declined -- which is why a lone `cursor = prev[cursor]`
## still fails the gate, as does an uncapped build, a build in another function,
## a build that re-parents, and a step that assigns a constant.
##
## HONEST LIMITS. The scan verifies the SHAPE, not the map's semantic integrity:
## a builder that defeats all four checks could still hand the walk a cycle, and
## the walk would spin -- no static scan can follow values through a dictionary.
## A DISJUNCTION is declined: `cursor != from or flag` keeps the loop alive after
## the sentinel and walks into a key the map never placed, whereas every `and`
## clause can only end the loop earlier. The rule is also deliberately narrow
## about spelling: the sentinel must be on the right of `!=`, the lookup must be
## a direct `[` read (not `get()`), and the cap must be the final term of the
## condition. If a loop wants a step this rule cannot name, the fix is the loop,
## not a wider rule here.
func _walk_follows_capped_map(source: String, condition: String) -> bool:
	if condition.contains(" or "):
		return false
	var lookup := _walk_map_lookup(source, condition)
	if lookup.is_empty():
		return false
	var cursor: String = lookup[0]
	var map_name: String = lookup[1]
	var sentinel := _walk_sentinel(condition, cursor)
	if sentinel == "":
		return false
	return _map_built_by_a_capped_traversal(source, condition, map_name, sentinel)


## The `[cursor, map]` pair a walk's body proves: `<cursor> = <map>[<cursor>]` at
## the body's shallowest indentation, where `<cursor>` is the identifier the
## condition tests with `!= `. Empty when no such step exists -- and empty is the
## answer for `cursor = to` (no lookup), for a lookup behind an `if`, and for a
## condition that names no `!=` at all.
func _walk_map_lookup(source: String, condition: String) -> Array[String]:
	var found: Array[String] = []
	var lines := _loop_body_lines(source, condition)
	if lines.is_empty():
		return found
	var shallowest := 1 << 30
	for entry in lines:
		shallowest = mini(shallowest, int(entry.split("|", true, 1)[0]))
	for cursor in _identifiers(condition):
		if not condition.contains(cursor + " != "):
			continue
		for entry in lines:
			var parts := entry.split("|", true, 1)
			if int(parts[0]) != shallowest:
				continue
			for map_name in _identifiers(parts[1]):
				if parts[1].contains(cursor + " = " + map_name + "[" + cursor + "]"):
					var pair: Array[String] = [cursor, map_name]
					return pair
	return found


## The value the walk tests `!= ` against, when it is one bare name. `cursor !=
## from:` returns `from`; a computed sentinel (`cursor != to + 1`) is declined
## because the seed evidence the rule needs is textual.
func _walk_sentinel(condition: String, cursor: String) -> String:
	var at := condition.find(cursor + " != ")
	if at < 0:
		return ""
	var rest := condition.substr(at + cursor.length() + 4).strip_edges()
	var sentinel := ""
	for index in rest.length():
		var character := rest[index]
		if character == " " or character == ":":
			break
		sentinel += character
	return sentinel if sentinel.is_valid_identifier() else ""


## Whether a PRECEDING loop in the SAME function built `map_name` under a fixed
## size cap, with a guarded placement, seeded at `sentinel` -- the four facts
## rule 8 stands on. Each candidate is checked by `_bounded_without_a_walk` (the
## accept paths that predate rule 8), never by `_is_bounded`, so no walk can
## vouch for another.
func _map_built_by_a_capped_traversal(
	source: String, walk_condition: String, map_name: String, sentinel: String
) -> bool:
	var walk_at := _line_index_of(source, _while_line(source, walk_condition))
	if walk_at < 0:
		return false
	for condition in _while_conditions(source):
		if condition == walk_condition:
			continue
		if not _bounded_without_a_walk(source, condition):
			continue
		if not _map_size_is_capped(condition, map_name):
			continue
		if not _has_a_guarded_placement(_loop_body(source, condition), map_name):
			continue
		var fill_at := _line_index_of(source, _while_line(source, condition))
		if fill_at < 0 or fill_at >= walk_at:
			continue
		if _enclosing_function(source, fill_at) != _enclosing_function(source, walk_at):
			continue
		if not _map_is_seeded_at(_function_span(source, walk_at), map_name, sentinel):
			continue
		return true
	return false


## Whether the condition bounds `<map>.size()` against a FIXED count -- an
## integer literal or a `CONSTANT_CASE` name -- as rule 5's target is not
## required to be. A caller-sized cap (`prev.size() < needed`) is a bound whose
## length the caller chose, which is exactly what this refuses.
func _map_size_is_capped(condition: String, map_name: String) -> bool:
	var needle := map_name + ".size()"
	var at := condition.find(needle)
	if at < 0:
		return false
	var rest := condition.substr(at + needle.length()).strip_edges()
	for operator in ["<=", "<"]:
		if rest.begins_with(operator):
			return _is_fixed_count(rest.substr(operator.length()))
	return false


## A count written down: digits (with `_` separators) or a CONSTANT_CASE name.
## `ROUTE_VISIT_CAP` and `1024` are fixed; `needed` and `rows.size()` are not.
func _is_fixed_count(text: String) -> bool:
	var token := text.strip_edges().trim_suffix(":").strip_edges()
	if token == "":
		return false
	if token.replace("_", "").is_valid_int():
		return true
	if not token.is_valid_identifier() or token != token.to_upper():
		return false
	for index in token.length():
		var character := token[index]
		if character >= "A" and character <= "Z":
			continue
		if character >= "0" and character <= "9" or character == "_":
			continue
		return false
	return true


## Whether the fill's body proves that every key it PLACES is checked with `has`
## first, the evidence that a placed key is never re-parented -- which is what
## makes a cycle impossible in the admitted idiom. One unguarded placement is
## enough to allow a cycle (`1 -> 2` set, then `2 -> 1`), so ALL of them must be
## guarded; a body with any unguarded placement is refused.
func _has_a_guarded_placement(body: String, map_name: String) -> bool:
	var placed := _keys_placed_into(body, map_name)
	if placed.is_empty():
		return false
	var checked := _keys_checked_with(body, map_name)
	for key in placed:
		if not checked.has(key):
			return false
	return true


## The keys `<map>` is assigned into, across every nesting of a body:
## `map[key] = ...` yields `key`. A comparison (`map[key] == ...`) yields nothing.
func _keys_placed_into(text: String, map_name: String) -> Array[String]:
	var out: Array[String] = []
	var opening := map_name + "["
	var cursor := 0
	while true:
		var at := text.find(opening, cursor)
		if at < 0:
			break
		var close := text.find("]", at)
		if close < 0:
			break
		var rest := text.substr(close + 1).strip_edges()
		if rest.begins_with("=") and not rest.begins_with("=="):
			out.append(
				text.substr(at + opening.length(), close - at - opening.length()).strip_edges()
			)
		cursor = close + 1
	return out


## The keys `<map>` is checked with `has(...)`: `map.has(key)` yields `key`.
func _keys_checked_with(text: String, map_name: String) -> Array[String]:
	var out: Array[String] = []
	var opening := map_name + ".has("
	var cursor := 0
	while true:
		var at := text.find(opening, cursor)
		if at < 0:
			break
		var close := text.find(")", at)
		if close < 0:
			break
		out.append(text.substr(at + opening.length(), close - at - opening.length()).strip_edges())
		cursor = close + 1
	return out


## Whether the map is seeded at the sentinel the walk stops on: a dictionary
## literal (`{from: -1}`) or an explicit write (`map[from] = ...`). The seed is
## the evidence that the chain ends where the walk stops rather than at another
## root the walk would then read past.
func _map_is_seeded_at(text: String, map_name: String, sentinel: String) -> bool:
	var dense := text.replace(" ", "").replace("\t", "")
	if dense.contains(map_name + ":={" + sentinel + ":"):
		return true
	if not dense.contains(map_name + "[" + sentinel + "]="):
		return false
	return not dense.contains(map_name + "[" + sentinel + "]==")


## The line index of the nearest `func` at indentation 0 above `at`, or -1 when
## the walk is not inside a function. Rule 8 is scoped to one function so a
## bounded build elsewhere in the file cannot vouch for a walk in another.
func _enclosing_function(source: String, at: int) -> int:
	var lines := source.split("\n")
	var index := at - 1
	while index >= 0:
		if _indent_of(lines[index]) == 0 and _starts_a_function(lines[index]):
			return index
		index -= 1
	return -1


## Whether a line opens a function definition at class level.
func _starts_a_function(line: String) -> bool:
	var stripped := line.strip_edges()
	return stripped.begins_with("func ") or stripped.begins_with("static func ")


## The text of the function enclosing `at`, from its `func` line to the line
## before the next class-level `func`. Used to check the walk's own function for
## the seed, so a seed in another function is not read as evidence.
func _function_span(source: String, at: int) -> String:
	var start := _enclosing_function(source, at)
	if start < 0:
		return ""
	var lines := source.split("\n")
	var span := ""
	var index := start
	while index < lines.size():
		if index > start and _indent_of(lines[index]) == 0 and _starts_a_function(lines[index]):
			break
		span += lines[index] + "\n"
		index += 1
	return span


## The first line index whose line EQUALS `line_text`, or -1. Used to order the
## fill loop strictly before the walk and to locate both inside their function.
func _line_index_of(source: String, line_text: String) -> int:
	if line_text == "":
		return -1
	var lines := source.split("\n")
	for index in lines.size():
		if lines[index] == line_text:
			return index
	return -1


## The `_while` line carrying `condition`, reassembled across its continuation
## lines. `""` when the scan cannot locate one -- `_loop_body_lines` used to carry
## this and returns "" when the reassembled line holds no `while ` at all, which
## is how a bare `while at < 0:` in an `if` used to read as a loop header.
func _while_line(source: String, condition: String) -> String:
	var lines := source.split("\n")
	for index in lines.size():
		var line := lines[index]
		if not line.strip_edges().begins_with("while "):
			continue
		if _reassembled(line, lines, index).contains(condition):
			return line
	return ""


## The indented block under the `while` that carries `condition`, by indentation.
## Empty when the body cannot be located, which makes rules 4, 5 and 6 decline
## rather than wave the loop through.
func _loop_body(source: String, condition: String) -> String:
	var parts := _loop_body_lines(source, condition)
	var body := ""
	for entry in parts:
		body += entry.split("|", true, 1)[1] + " "
	return body


## The same block, one `"<indent>|<stripped line>"` string per line, so a caller
## can tell a statement at the loop's own level from one nested in a branch.
## Scoped by the `while` LINE rather than by the bare condition text, because a
## continuation line of some earlier condition can repeat those words: the file's
## own `_reassembled` helper is what proves they belong to a loop header.
func _loop_body_lines(source: String, condition: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var start := -1
	var base_indent := 0
	var header := _while_line(source, condition)
	for index in lines.size():
		if lines[index] != header:
			continue
		start = index
		base_indent = _indent_of(lines[index])
		break
	if start < 0:
		return out
	for index in range(start + 1, lines.size()):
		var line := lines[index]
		if line.strip_edges() == "":
			continue
		if _indent_of(line) <= base_indent:
			break
		out.append("%d|%s" % [_indent_of(line), line.strip_edges()])
	return out


## The `while` line at `index` plus its continuation lines, joined, so a
## multi-line condition matches the same text the scan reported.
func _reassembled(line: String, lines: PackedStringArray, index: int) -> String:
	var current := line.strip_edges()
	var depth := _paren_depth(current)
	while depth > 0 and index + 1 < lines.size():
		index += 1
		current += " " + lines[index].strip_edges()
		depth = _paren_depth(lines[index].strip_edges())
	return current


func _indent_of(line: String) -> int:
	var count := 0
	for index in line.length():
		if line[index] != "\t" and line[index] != " ":
			break
		count += 1
	return count


func _identifiers(text: String) -> Array[String]:
	var found: Array[String] = []
	var current := ""
	for index in text.length():
		var character := text[index]
		var is_word := (
			character >= "a" and character <= "z"
			or character >= "A" and character <= "Z"
			or character >= "0" and character <= "9"
			or character == "_"
		)
		if is_word:
			current += character
		elif current != "":
			found.append(current)
			current = ""
	if current != "":
		found.append(current)
	return found
