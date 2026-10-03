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
##    on the very container the condition tests -- each call strictly shrinks it;
## 4. its body breaks or returns, so an unreachable condition still ends the loop;
## 5. it fills a container toward a fixed count, proven by an `append` to that
##    container at the loop's own indentation -- not nested in a branch, because
##    an append behind a branch that never holds is the same defect.
##
## None of the five can express the original defect, which was `while <a state
## value that never becomes true>`. Note the honest limit -- a `break` or an
## `append` behind a condition that never holds is still an unbounded wait, and no
## static scan can see that. This catches the shape; it does not prove convergence.

const SRC_ROOT := "res://src"
const TESTS_ROOT := "res://tests"


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


func _is_bounded(condition: String, source: String) -> bool:
	# 2. The DirAccess terminator: `get_next()` returns "" at the end of a listing,
	# written either as `!= ""` or as `not entry.is_empty()`.
	if condition.contains('!= ""'):
		return true
	if _is_dir_access_sentinel(condition, source):
		return true
	# 1. A counter this loop moves.
	for identifier in _identifiers(condition):
		if source.contains(identifier + " += ") or source.contains(identifier + " -= "):
			return true
	# 3. A container the body provably shrinks.
	var drained := _drained_container(condition)
	if drained != "" and _shrinks_container(source, drained):
		return true
	# 5. A container the body provably fills toward a fixed count.
	if _fills_unconditionally(source, condition):
		return true
	# 4. A body that leaves the loop on its own.
	return _body_contains_exit(source, condition)


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


func _shrinks_container(source: String, container: String) -> bool:
	for verb in ["pop_front", "pop_back", "pop_at", "remove_at", "erase", "clear"]:
		if source.contains(container + "." + verb):
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


## The indented block under the `while` that carries `condition`, by indentation.
## Empty when the body cannot be located, which makes rules 4 and 5 decline
## rather than wave the loop through.
func _loop_body(source: String, condition: String) -> String:
	var parts := _loop_body_lines(source, condition)
	var body := ""
	for entry in parts:
		body += entry.split("|", true, 1)[1] + " "
	return body


## The same block, one `"<indent>|<stripped line>"` string per line, so a caller
## can tell a statement at the loop's own level from one nested in a branch.
func _loop_body_lines(source: String, condition: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var start := -1
	var base_indent := 0
	for index in lines.size():
		var line := lines[index]
		if not line.strip_edges().begins_with("while "):
			continue
		if not _reassembled(line, lines, index).contains(condition):
			continue
		start = index
		base_indent = _indent_of(line)
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
