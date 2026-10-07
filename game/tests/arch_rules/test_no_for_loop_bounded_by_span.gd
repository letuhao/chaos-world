extends TestCase

## The span-bounded `for` half of the loop-safety guard, as its own suite.
##
## Split out of `test_no_unbounded_wait.gd` when the `while` guard grew its rules
## 7 and 8: a `for` has no condition for those clauses to read, and the combined
## file crossed gdlint's 1000-line cap, so neither half could keep the docblock
## that lets the next agent re-derive it. The scan itself is unchanged and still
## runs in the `arch_rules` suite. Run just this suite with:
##   uv run python -m tools test --suite test_no_for_loop_bounded_by_span
##
## A `for` whose iteration count is a SPAN, a magnitude, or any count a caller
## can grow without limit is the shape the `while` scan is blind to. The omission
## was not academic: a mutation that turned `TimeLadder.magnitudes_crossed` from
## one division per authored row into `for _step in span_periods` -- precisely
## the per-period loop ADR 0173 exists to remove -- **ran for 420 seconds and
## nothing went red.** `tools arch` stayed green. That is this repo's recorded
## memory incident (67 GB, two power-cycles) in the exact shape the `while` guard
## cannot see, so the gap is closed here rather than documented.
##
## The test is deliberately narrow, because a false positive on every `for` in
## the tree would make this guard as untrusted as the one it replaces. A `for` is
## flagged only when its bound NAMES a span, and never when it walks an authored
## collection -- `for realm in ladder.realms()` and `for row in rows` are the
## shapes the repo wants.

const SRC_ROOT := "res://src"
const TESTS_ROOT := "res://tests"
## Bounds that are DERIVED from an authored table rather than sized by a caller.
## `_retreat_spans` is built row by row from `TimeLadder.magnitudes()`, which
## returns `magnitude_rows` off an authored `.tres`, so walking it is exactly as
## bounded as walking `ladder.realms()` — a shape the rule already exempts.
## A suffix is required so a bare `spans`, which says nothing about its origin,
## keeps its finding.
const AUTHORED_SUFFIXES: Array[String] = [
	"_retreat_spans",
	"_magnitudes",
	"_rows",
	"_table",
]


func test_no_for_loop_is_bounded_by_a_span() -> void:
	var span_words := ["span", "periods_elapsed", "elapsed", "magnitude_count", "years"]
	# The guard's OWN two walks name a span and are bounded anyway: `span_words` and
	# `_span_bounded_for_lines` are both written down above, not sized by a caller.
	# A guard that reports itself is a guard authors learn to mute, so it exempts
	# exactly these two identifiers — named, never a blanket skip of this file, which
	# would blind the rule to a real span walk added to it later.
	# TYPED, because the callee is: `_bound_is_exempt(bound: String, exempt:
	# Array[String])` cannot take an untyped `Array`, and the mismatch is a RUNTIME
	# error rather than a parse error — the suite still loads and still passes 1258
	# assertions while every call raises "Invalid type in function
	# '_bound_is_exempt'. The array of argument 2 (Array) does not have the same
	# element type as the expected typed array argument". A guard that errors on the
	# one path that exempts itself is a guard whose self-exemption silently does
	# nothing, which is how the two identifiers above stop being exempt and the guard
	# starts reporting itself.
	const SELF_EXEMPT: Array[String] = ["span_words", "_span_bounded_for_lines"]
	var audited := 0
	for path in _gdscript_files(SRC_ROOT) + _gdscript_files(TESTS_ROOT):
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		for line in _span_bounded_for_lines(text):
			audited += 1
			var lowered := line.to_lower()
			# The word must be in the BOUND, not anywhere in the line. Testing the whole
			# line matched the word inside an unrelated identifier: every
			# `for tier in RealmLifespan.AUTHORED_TIERS` reads as a span walk because
			# "Lifespan" CONTAINS "span", which fired 45 times across four files and
			# three of them are the guard's own fixtures. A substring rule that
			# cannot tell `RealmLifespan` from `span` catches nothing an author can
			# act on, so the bound is what gets matched.
			var bound_text := _loop_bound(lowered)
			var offender := ""
			for word in span_words:
				if _bound_names_span(bound_text, word):
					offender = word
					break
			# An AUTHORED collection is not a span. `for realm in ladder.realms()` walks
			# 30 rows forever; `for step in span_periods` walks whatever the caller said.
			#
			# A LITERAL array is authored too, and this is the shape that made the guard
			# cry wolf on 33 cases across three files: `for span in [1, 8, 9, 4_380,
			# billion_years_periods()]` in test_time_ladder.gd and
			# test_realm_lifespan_table.gd, and the guard's own source. The old test was
			# `lowered.contains(" in [")` — a literal ` in [`, with the space — and
			# GDScript writes `in [1,` after `strip_edges()`, so NONE of them matched and
			# every one was reported as an unbounded span. A guard that fires 33 times on
			# its own test file gets muted, and then it catches nothing.
			#
			# Spacing-tolerant on purpose: `in [`, `in[`, and `in\t[` all name a literal.
			# Tested against the BOUND, so `for span in [1, 8]` is authored and
			# `for span in spans` is not, on its own. Three shapes count as AUTHORED:
			# a literal array, a `.realms()` accessor, and a bound DERIVED from an
			# authored table — `_retreat_spans` is built from `TimeLadder.magnitudes()`,
			# which reads a `.tres` nobody sizes at run time, so walking it is bounded
			# exactly as `ladder.realms()` is. What stays flagged is a bound whose
			# length a CALLER chose, which is the shape ADR 0173 exists to remove.
			var opens_literal := bound_text.begins_with("[")
			var walks_authored := (
				lowered.contains(".realms()")
				or opens_literal
				or _bound_is_exempt(bound_text, SELF_EXEMPT)
				or _bound_is_authored(bound_text)
				or _bound_is_authored_locally(bound_text, text)
			)
			# These three live INSIDE the `for line` body, which is deliberate and was
			# previously broken by one missing tab: declared one level too far out, they
			# died at the loop's end and the assert below could not see them, so the file
			# failed to COMPILE — "Identifier 'walks_authored' not declared in the current
			# scope" — which takes the whole guard down silently. A loop-safety guard that
			# does not compile is worse than none, because `--suite arch_rules` reports the
			# suite as `failed to load suite` and every other arch rule looks green.
			assert_eq(
				walks_authored or offender == "",
				true,
				(
					(
						"%s iterates a SPAN (`%s`), so its length is data the caller controls — "
						+ "fold instead (ADR 0173), or clamp it"
					)
					% [path, offender]
				)
			)
	# A rule that scans nothing is a rule nobody trusts (INC-0016). Prove the scan
	# reaches `for` lines at all rather than trusting the population is non-empty.
	assert_eq(
		audited > 0,
		true,
		"the span-bounded `for` scan inspected at least one line, or it guards nothing"
	)


## Every `.gd` under `root`, recursively. Copied from `test_no_unbounded_wait.gd`
## rather than inherited: this suite is standalone so its failure cannot ride on
## the `while` scan's, the same reason the other arch rules carry their own walk.
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


## Whether a bound is DERIVED from an authored table rather than sized by a caller.
##
## `_retreat_spans` is built row by row from `TimeLadder.magnitudes()`, which returns
## `magnitude_rows` off an authored `.tres`. Its length is a property of CONTENT, so
## walking it is exactly as bounded as walking `ladder.realms()` — and the rule
## already exempts that shape. Flagging it put three findings on two files where
## every one was a false positive, which is how a guard gets muted.
##
## The name must SAY it is derived: a suffix is required, because a bare `spans`
## says nothing about where it came from, and `_spans` could be a caller's array.
## A caller-sized bound with no such marker keeps its finding.
func _bound_is_authored(bound: String) -> bool:
	var name: String = bound.split("(")[0].strip_edges()
	for suffix in AUTHORED_SUFFIXES:
		if name.ends_with(suffix):
			return true
	return false


## Whether a bare local bound is bounded by AUTHORED data rather than by a caller:
## either assigned a literal array, or read from a published authored key.
##
## `var spans := [1, 400, 4_380, ...]` then `for span in spans:` is bounded by
## what is written down, exactly as `for span in [1, 400, ...]` is. The guard can
## only see the loop, so the assignment is resolved in the same text — which is
## why `text` is threaded through instead of the bare line.
##
## An assignment the scan cannot see (a parameter, a field, a value returned from
## a call) is NOT a literal and keeps its finding: that is the caller-sized shape.
func _bound_is_authored_locally(bound: String, text: String) -> bool:
	var name := bound.split("(")[0].strip_edges()
	if not name.is_valid_identifier():
		return false
	# A `.get("..._spans", [])` read is a published AUTHORED collection when the
	# key names one: `summary.get("retreat_spans", [])` is the panel's own list,
	# built from `TimeLadder.magnitudes()`. Without this the rule flagged three
	# loops that walk a bounded authored table through a published read.
	for line in text.split("\n"):
		if line.contains('"retreat_spans"') and line.contains(name):
			return true
	var marker := "var %s" % name
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with(marker):
			continue
		var after := line.substr(marker.length()).strip_edges()
		# GDScript writes `var spans := [...]` — a SPACE after `:=` — so the
		# literal is reached by stripping the assignment gap, not by testing
		# `":=["`, which never matches a real line.
		after = after.lstrip(":=").strip_edges()
		if after.begins_with("["):
			return true
	return false


## Whether a bound IS one of the named exemptions, compared on the CALLED name
## rather than the whole bound text.
##
## `for line in _span_bounded_for_lines(text):` has the bound
## `_span_bounded_for_lines(text)`, so an equality test against the bare
## identifier never matched and the guard kept reporting its own source.
func _bound_is_exempt(bound: String, exempt: Array[String]) -> bool:
	return exempt.has(bound.split("(")[0].strip_edges())


## Whether the bound NAMES a span, matching WHOLE identifiers rather than a
## substring.
##
## `contains` cannot tell `spans` from `realmlifespan.authored_tiers`: "Lifespan"
## CONTAINS "span" while saying nothing about the loop's length, and matching it
## fired the rule on every authored-tier walk in the tree. A span is named when the
## word stands alone as an identifier of its own — `span`, `spans`,
## `span_periods`, `_retreat_spans` — so each identifier in the bound is tested for
## being the word or for carrying it as a whole `_`-delimited component. Matching
## per identifier is what keeps `spans` (a real span walk, still flagged) apart from
## `Lifespan` (an authored table, not flagged).
func _bound_names_span(bound: String, word: String) -> bool:
	if bound.is_empty():
		return false
	for piece in (
		bound.replace("(", " ").replace(")", " ").replace(",", " ").replace(".", " ").split(" ")
	):
		var name := piece.strip_edges()
		if name.is_empty():
			continue
		if name == word or name.ends_with("_" + word) or name.begins_with(word + "_"):
			return true
		# The plural is the same noun: `for span in spans` is as much a span walk
		# as `for span in span_periods`, and a rule that misses it fires on the
		# composed names while staying quiet on the plain one.
		if name == word + "s" or name.ends_with("_" + word + "s"):
			return true
		# `_retreat_spans` / `span_periods`: the word is a component of the identifier.
		if ("_" + name).contains("_" + word + "_") or name.contains("_" + word):
			return true
	return false


## The collection a `for` header walks: everything after its FIRST ` in `, so the
## rule reads the bound and never the whole line.
##
## `for tier in RealmLifespan.AUTHORED_TIERS:` returns `realm_lifespan.authored_tiers:`
## — the trailing colon is stripped, but a leading `[` is KEPT, because that is how
## `opens_literal` above recognises an authored array. Matching the LINE instead is
## what made the guard fire 45 times on four files, because "Lifespan" contains
## "span" while naming nothing about the loop's length.
func _loop_bound(lowered: String) -> String:
	var split := lowered.split(" in ", true, 1)
	if split.size() < 2:
		return ""
	return split[1].rstrip(":").strip_edges()


## Every `for` header in a file, comments stripped, as `"<line>"`.
func _span_bounded_for_lines(text: String) -> Array[String]:
	var found: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.begins_with("for ") and line.contains(" in "):
			found.append(line)
	return found
