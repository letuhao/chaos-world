extends TestCase

## DEF-0287: a module that CALLS a sibling's facade must DECLARE the edge in
## `tools/arch/registry.json`, and nothing else in the tree can check that.
##
## ## Why this is a test and not a note
##
## `BARE_REF_UNITS` in `tools/arch/rules.py` is `frozenset({"ui", "app", "contracts"})`
## and deliberately excludes `modules/*` — a bare typed reference out of a module is
## "reported as an unresolved count rather than enforced", as that file's own header
## says. So a module-to-module call is:
##
##   - not a boundary violation (`LAYER_DEPS` allows a module to depend on `*`),
##   - not a cycle edge (`_find_cycle` is fed by `registry.json` alone), and
##   - not a gate failure of any kind — `tools arch` prints `ok` with the edge absent.
##
## That is why ADR 0134 §2 calls it "the rule that has already failed once", on `quest`,
## and why the declaration used to be a hand edit to a JSON file discoverable only by
## reading ADR prose. This file is the enforcement that was missing: it reads the real
## source, finds every module whose CODE calls `DestinyApi.`, and asserts the registry
## says so.
##
## ## Why a comment is not a call
##
## The detector strips comment LINES, not everything after the first `#` on a line.
## An earlier version of the same rule in
## `tests/modules/destiny/test_destiny_earn_sources_combat.gd` did
## `body.split("#")[0].contains(...)`, which keeps only the text BEFORE the first `#`
## anywhere in the file — so every call sitting after any comment was invisible and the
## count read 0 with the wiring fully present. That shape is the DEF-0231/0232 failure
## in test form: a guard that reports an all-clear because it never looked.
##
## ## What it does NOT catch, stated because overclaiming is worse than the hazard
##
##   - A facade reached through a `preload()` and a `const` alias rather than by bare
##     name. The scan is a text scan for `DestinyApi.`; an indirection defeats it. The
##     repo has none (asserted below by requiring the bare call to be how the tree does
##     it), but a new one would be a hole, not a pass.
##   - An edge declared and never used. That is harmless — `tools arch` and the cycle
##     finder both want the declaration — so it is not this file's business.
##   - `ui/` and `app/`. `app/` may depend on anything, and `ui/` is already covered by
##     `UI_MODULES` in the same rules file, which is enforced rather than declared. Only
##     the module-to-module case is unenforced, so only that case is here.
##
## ## Why it must not be a Python guard instead
##
## Because then nothing would assert it still goes RED (INC-0016), exactly as
## `tools/adr_cite.py` carries its own red path in `tools/adr_cite_selftest.py`. This
## file is reachable from `uv run python -m tools test --suite arch_rules`, so the
## engine sees it, and a Python guard cannot be the only copy of a rule.

const SRC_ROOT := "res://src"
const MODULES_ROOT := "res://src/modules"
## The facade a consumer reaches `destiny` through, and the ONLY legal spelling from
## another module: `game/src/modules/destiny/api.gd` (AGENTS.md, facade-only rule).
const FACADE := "DestinyApi."
## The registry. It sits OUTSIDE `game/`, which is what `res://` points at, so it is
## read through `res://../` — the same seam
## `tests/modules/destiny/test_destiny_earn_sources_combat.gd` already uses.
const REGISTRY := "res://../tools/arch/registry.json"
## The module whose facade is being consumed. `destiny` itself is excluded by
## `_consumers`: it owns the facade and may never list itself as a dependency.
const TARGET := "destiny"

## One directory level of `modules/` per scan. `_scan` recurses, so this is a bound on
## the walk rather than on the work; the engine test runner drives every suite in one
## process and an unbounded walk is the failure mode AGENTS.md warns about.
const SCAN_ROOT := MODULES_ROOT


## THE rule: every module whose source CALLS `DestinyApi` declares `destiny`.
##
## Each offender is named individually rather than dumped as one array, because the
## whole point is that the reader can act on the failure: the fix is one line in one
## JSON entry, and a reader who has to count a list to find out which module it is has
## already lost.
func test_every_module_calling_destiny_declares_it_in_the_registry() -> void:
	var modules := _modules()
	var offenders: Array[String] = []
	var consumers := 0
	for module_name in _module_names():
		if module_name == TARGET:
			continue
		var calls := _call_sites(_module_text(module_name), FACADE)
		if calls.is_empty():
			continue
		consumers += 1
		var entry: Dictionary = modules.get(module_name, {}) as Dictionary
		var deps: Array = entry.get("deps", []) as Array
		if deps.has(TARGET):
			continue
		(
			offenders
			. append(
				(
					"%s calls %s at %s but its registry deps are [%s]"
					% [
						module_name,
						FACADE,
						", ".join(calls),
						", ".join(deps),
					]
				)
			)
		)
	assert_eq(
		consumers > 0,
		true,
		"no module under %s calls %s in code, so this rule proved nothing" % [SCAN_ROOT, FACADE]
	)
	for offence in offenders:
		assert_eq(
			offence,
			"",
			(
				("%s — BARE_REF_UNITS excludes modules/*, so `tools arch` reports this " % offence)
				+ (
					"edge as ok and `_find_cycle` cannot see it either. Add `destiny` to that "
					+ "module's deps in tools/arch/registry.json (or scaffold with "
					+ "`new_module <name> --deps destiny`), and never reach past the facade."
				)
			)
		)
	assert_eq(offenders.size(), 0, "every module calling the destiny facade declares it")


## The registry names the modules it decides, and this one is really among them.
##
## Without it a rename or a reformat that emptied the `modules` map would make every
## assertion above pass vacuously — `get()` returns `{}` for an unknown module, which
## looks exactly like a module with no declared deps, and `destiny` not being in the
## map is the same shape.
func test_the_registry_is_readable_and_names_both_ends_of_the_edge() -> void:
	var modules := _modules()
	assert_eq(
		modules.has(TARGET),
		true,
		"the consumed module is itself declared in tools/arch/registry.json"
	)
	var deps: Array = (modules.get(TARGET, {}) as Dictionary).get("deps", []) as Array
	assert_eq(
		deps.has("core") and deps.has("contracts"),
		true,
		"the destiny module keeps the default layer deps it was scaffolded with"
	)


## A module that declares `destiny` and calls it is the SHAPE the rule protects, and
## it is asserted here as a positive rather than assumed. A rule that only ever fires
## on negatives can also pass by never matching at all.
func test_the_scan_really_sees_a_declared_consumer() -> void:
	var modules := _modules()
	var declared_and_calling: Array[String] = []
	for module_name in _module_names():
		if module_name == TARGET:
			continue
		var deps: Array = (modules.get(module_name, {}) as Dictionary).get("deps", []) as Array
		if deps.has(TARGET) and not _call_sites(_module_text(module_name), FACADE).is_empty():
			declared_and_calling.append(module_name)
	declared_and_calling.sort()
	assert_eq(
		declared_and_calling.size() > 0,
		true,
		(
			"no module both declares `destiny` and calls it, so the rule above is being "
			+ "satisfied by an empty scan rather than by correct declarations"
		)
	)


## The two detectors still fire, on strings rather than on the tree.
##
## A guard that has stopped matching is a guard that reads as an all-clear, and this is
## the only part of the file that would notice. The prose in this very docblock names
## `DestinyApi.` many times and must NOT register as a call — that is the half that
## went wrong before.
func test_the_detector_ignores_comments_and_reads_code() -> void:
	assert_eq(
		_call_sites("## `DestinyApi.earn_fate` is exactly-once.", FACADE).size(),
		0,
		"a comment naming the facade is not a call"
	)
	assert_eq(
		_call_sites("\t# see DestinyApi.has_fate for the idiom\n", FACADE).size(),
		0,
		"an indented comment line is not a call either"
	)
	assert_eq(
		_call_sites("\tDestinyApi.earn_fate(actor, id, source)\n", FACADE).size(),
		1,
		"a real call is found"
	)
	assert_eq(
		_call_sites("\tvar v := DestinyApi.summary(actor)\n", FACADE).size(),
		1,
		"a read through the facade is a call too: the edge is the same either way"
	)
	# The whole point of the fix, asserted directly: a call that sits AFTER a comment
	# is still a call. The old `split("#")[0]` shape read this file as zero calls.
	var after_a_comment := "## The docstring.\n## More prose.\n\tDestinyApi.attach(a)\n"
	assert_eq(
		_call_sites(after_a_comment, FACADE).size(),
		1,
		"a call after two comment lines must be counted; stripping per LINE, not per file"
	)
	# A `#` INSIDE a code line's trailing comment must not hide the call on it.
	assert_eq(
		_call_sites("\tDestinyApi.attach(a)  # the bridge\n", FACADE).size(),
		1,
		"a trailing comment does not remove the call it follows"
	)


## ## An earn site whose PARTICIPANT is a defaulted parameter is an earn site
## ## that can be wired to nothing and still typecheck.
##
## DEF-0320 was exactly this, and it survived a census that counted earn CALL
## SITES and found twelve of them. `CombatDuelHit._record_win` called
## `CombatDuel.record_win(duel, entry)` without the third argument, and
## `record_win`'s signature is `(duel, entry, actor: Actor = null)` with
## `if actor != null:` guarding the earn — so a duel closed with a killing blow
## moved the `wins` counter, wrote `duel_won` into the history, recorded the duel
## fact, and granted NO fate. The call site compiled, read as correct, and paid
## nothing. Counting sites proves a call EXISTS; it never proves the call is
## REACHED.
##
## So the rule here is about the SHAPE of the earn's own signature: a function
## that can earn must not make its participant optional. A default of `null` on
## the actor is legal GDScript and it is exactly what makes the failure silent —
## there is no refusal, no warning, and no type error.
func test_no_earn_bearing_function_makes_its_participant_optional() -> void:
	# The verbs that PAY, and the participant each one needs. `source` is a string
	# and `amount` a number, so neither can be the null that silently skips a
	# reward. `record` is here because `DestinyApi.record` is the counter earn and
	# `CombatDuel.record_win` / `record_defeat` are the fate earns; the match is on
	# the verb name with a WORD BOUNDARY after it, because a bare `record` substring
	# also matches `record_duel_won`, and matching the wrong family would make this
	# guard's population a guess.
	var verbs := ["earn_fate", "earn_destiny", "record", "grant", "pay"]
	var optional_sites: Array[String] = []
	var signatures := 0
	for path in _gdscript_files(SRC_ROOT):
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#"):
				continue
			if not code.begins_with("static func ") and not code.begins_with("func "):
				continue
			# Only a DEFINITION line, not a call: a definition names the verb after
			# `func`, and the `(` follows the name. `code.contains("(")` alone would
			# match every line that merely mentions the verb.
			var open := code.find("(")
			if open < 0:
				continue
			var name := code.substr(code.find("func ") + 5, open - (code.find("func ") + 5))
			if not _pays_by_name(name, verbs):
				continue
			signatures += 1
			# The optional-participant signatures are NAMES, not an accusation. A
			# bare-ledger write with no body is a real shape —
			# `test_the_ledger_writers_still_work_without_an_actor` proves a duel record
			# can be written with no actor at all — so `actor: Actor = null` is legal
			# HERE. What was never legal is a PRODUCTION CALLER omitting it, and that
			# is the second case below. Recording the names is what lets the caller
			# check know its population is non-empty, so the rule cannot pass by
			# scanning nothing.
			if code.contains("= null"):
				optional_sites.append("%s: %s" % [path.get_file(), name])
	assert_eq(
		signatures > 0,
		true,
		(
			"the scan found at least one earn signature, or it is guarding nothing "
			+ "(INC-0016: a green guard nobody watched go red)"
		)
	)
	# The optional signatures are NAMES, not an accusation: the rule is about callers,
	# and a function may keep a null default for the bare-ledger shape.
	assert_eq(
		optional_sites.size() > 0,
		true,
		(
			"the scan found at least one earn with a null-defaulted participant, or the "
			+ "caller check above is inspecting nothing (INC-0016)"
		)
	)


## Every PRODUCTION call of an earn whose participant can be null must PASS one.
##
## This is DEF-0320's exact shape, and it is the check that would have caught it:
## `CombatDuelHit._record_win` and `CombatBoot._record_win` each called
## `CombatDuel.record_win(duel, entry)` with two arguments against a signature whose
## third is `actor: Actor = null`, and the `if actor != null:` guard turned that into
## a silent skip. Counting call SITES proved twelve earns existed; it never proved
## any was REACHED with its participant.
func test_no_production_caller_omits_an_optional_earn_participant() -> void:
	var offenders: Array[String] = []
	var checked := 0
	# The optional-participant earns, by NAME and fully qualified. Bare `record_win(`
	# also matches `_record_win(`, which is the CALLER HELPER of the same name and
	# takes `(attacker, defender)` legitimately — matching it would flag the very
	# functions that are supposed to pass the actor on. So the class name is required.
	#
	# And the class name is followed by WHITESPACE, not a dot, because the house call
	# style splits them across lines:
	#     CombatDuel
	#       . record_win(
	# A literal `CombatDuel.record_win(` never appears, so an adjacency match reports
	# a clean tree over every real call site. Measured: with adjacency this file
	# passed 18/18 against a tree where `duel_hit.gd` passed an explicit `null`
	# participant — the exact defect the guard exists to catch.
	var callee := "CombatDuel"
	for path in _gdscript_files(SRC_ROOT):
		var text := FileAccess.get_file_as_string(path)
		# A CALL SPANS LINES in this codebase — `CombatDuel\n\t\t.record_win(\n\t\t\tduel,`
		# is the house style — so the search is over the whole file with comments
		# stripped per line, not line by line. A line-by-line read sees `record_win(`
		# alone and counts its arguments as zero, which is the false positive this
		# shape produces.
		var stripped: Array[String] = []
		for raw in text.split("\n"):
			var line: String = raw.strip_edges()
			stripped.append("" if line.begins_with("#") else line)
		var body := "\n".join(stripped)
		var cursor := 0
		while true:
			var at := body.find(callee, cursor)
			if at < 0:
				break
			cursor = at + callee.length()
			# The verb follows the class name across WHITESPACE and an optional `.`,
			# because the house style puts `CombatDuel` and `. record_win(` on
			# separate lines. The gap is bounded so a distant verb cannot be paired
			# with this class name by accident.
			var verb := ""
			var open := -1
			for candidate in ["record_win", "record_defeat"]:
				var probe := cursor
				var gap := 0
				while probe < body.length() and gap < 24:
					var ch: String = body[probe]
					if ch == "(":
						break
					if not (ch == " " or ch == "\t" or ch == "\n" or ch == "."):
						break
					probe += 1
					gap += 1
				if probe + candidate.length() < body.length():
					if body.substr(probe, candidate.length()) == candidate:
						if body.substr(probe + candidate.length(), 1) == "(":
							verb = candidate
							open = probe + candidate.length()
							break
			if verb == "":
				continue
			checked += 1
			var depth := 0
			var commas := 0
			var closed := false
			# Where the LAST argument STARTS, so its VALUE can be read. Counting
			# arguments alone is not enough and this file learned that by mutation:
			# passing an explicit `null` is still three arguments, so an arg-count
			# check reports a clean tree while the participant is exactly as absent as
			# before. The defect is a participant that IS null, not one that is
			# missing, so the third argument's text is what has to be inspected.
			var last_argument_at := -1
			for position in range(open, body.length()):
				var ch := body[position]
				if ch == "(":
					depth += 1
				elif ch == ")":
					depth -= 1
					if depth == 0:
						closed = true
						break
				elif ch == "," and depth == 1:
					commas += 1
					last_argument_at = position + 1
			if not closed:
				continue
			if commas < 2:
				offenders.append(
					(
						"%s passes %d argument(s) to %s (the participant is MISSING)"
						% [path.get_file(), commas + 1, verb]
					)
				)
				continue
			var participant := body.substr(last_argument_at).strip_edges()
			# Take the FIRST LINE of the span and strip a trailing comment from it.
			# Both are load-bearing and the second one was found by mutation: the real
			# call site puts the participant after a NINE-LINE explanatory comment
			# (`# THE ACTOR. Without it ...`), so reading the whole span and trimming
			# its ends yields the comment's text and never `null` — the guard reported a
			# clean tree against the exact defect it exists to catch. A line, then the
			# code before any `#`, is the only read that survives that layout.
			var newline := participant.find("\n")
			if newline >= 0:
				participant = participant.substr(0, newline)
			var hash := participant.find("#")
			if hash >= 0:
				participant = participant.substr(0, hash)
			participant = participant.strip_edges()
			participant = participant.trim_suffix(")").strip_edges()
			participant = participant.trim_suffix(",").strip_edges()
			if participant == "null":
				(
					offenders
					. append(
						(
							"%s passes an explicit null participant to %s (the reward is silently unpaid)"
							% [path.get_file(), verb]
						)
					)
				)
	assert_eq(
		checked > 0,
		true,
		(
			"the scan found at least one call of an optional-participant earn, or it is "
			+ "guarding nothing (INC-0016)"
		)
	)
	assert_eq(
		offenders.size(),
		0,
		(
			(
				"a production caller omits an earn's participant, so the reward is silently "
				+ "unpaid (DEF-0320): %s"
			)
			% str(offenders)
		)
	)


## `-- Fixtures and readers -----------------------------------------------------


## Whether a function NAME is one of the paying verbs, on a WORD BOUNDARY.
##
## `record` alone would also match `record_duel_won` and `record_restored`, which are
## not earns, so a bare `contains` makes this guard's population a guess — and a
## guard that inspects the wrong family is worse than no guard, because it reports
## a green it has not earned. The boundary is checked on BOTH sides: the name must
## equal the verb, or continue with `_` after it.
func _pays_by_name(name: String, verbs: Array) -> bool:
	for verb in verbs:
		var word := String(verb)
		if name == word:
			return true
		if name.begins_with(word) and name.substr(word.length(), 1) == "_":
			return true
	return false


## `tools/arch/registry.json`'s module map. Asserted to be a Dictionary by its caller.
func _modules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	assert_eq(parsed is Dictionary, true, "tools/arch/registry.json is readable JSON")
	return {} if not (parsed is Dictionary) else (parsed as Dictionary)["modules"] as Dictionary


## Every module directory name under `res://src/modules`, sorted.
##
## `DirAccess` is the terminator `test_no_unbounded_wait.gd` accepts, and the worklist
## is collected before anything consumes it, so no loop here grows what it tests.
func _module_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SCAN_ROOT)
	if dir == null:
		assert_eq(false, true, "res://src/modules is readable")
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and dir.current_is_dir():
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## Every `.gd` under one module, concatenated with newlines so a line number in the
## result means the same line number in any single file.
##
## `read_off` is `true` when a line is CODE. It strips a WHOLE-LINE comment, which is
## the fix over `split("#")[0]`: that kept only the text before the first `#` in the
## entire file and made every call after any comment invisible.
func _module_text(module_name: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for path in _gdscript_files(MODULES_ROOT.path_join(module_name)):
		out.append(FileAccess.get_file_as_string(path))
	return "\n".join(out)


## Every code line naming `needle`, as `path:line`.
func _call_sites(text: String, needle: String) -> Array[String]:
	var out: Array[String] = []
	var lines := text.split("\n")
	for index in lines.size():
		var line: String = lines[index]
		if line.strip_edges().begins_with("#"):
			continue
		if not line.contains(needle):
			continue
		# `needle` is the facade's dotted name and a call opens a paren, so a prose
		# mention inside a string or a dict key is not counted as one.
		out.append("%d" % (index + 1))
	return out


## Every `.gd` under `root`, recursively — the same walk `test_fact_ledger_writers.gd`
## performs, and the same `DirAccess` terminator the unbounded-wait rule accepts.
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
