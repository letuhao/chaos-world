extends TestCase

## ADR 0902 (T7, decision 7): the mind tree is NOT gated by the new mechanisms, and
## nothing anywhere may keep a SECOND copy of the counter store, the ICD clock or the
## family field. Each claim is a source scan compared by SET EQUALITY, so a new file
## joining any of them goes red at its own name (INC-0016: a guard that cannot go red
## is not a guard).

const SRC_ROOT := "res://src"
const MAX_DEPTH := 8

## The ONE per-instance ICD clock and its reader (alphabetical). The reader is the
## facade's `StatusEngine.icd_refusal`, which the api split moved to `status_engine.gd`.
const ICD_CLOCK_FILES: Array[String] = [
	"res://src/modules/status/api.gd",
	"res://src/modules/status/status_engine.gd",
	"res://src/modules/status/status_runtime.gd",
]

## The ONE `status_icd` vocabulary: the refusal (api), the tuning key and the
## composition-root push. The def's own field is spelled `icd` and is NOT this token.
const ICD_VOCAB_FILES: Array[String] = [
	"res://src/app/status_loop.gd",
	"res://src/modules/combat_engine/combat_tuning.gd",
	"res://src/modules/status/api.gd",
]

## The ONE family DECLARATION (the request builders read locals, they do not declare).
const FAMILY_FILES: Array[String] = ["res://src/modules/status/status_def.gd"]

## The ONE counter store and its facade verbs. The app funnel reaches the store through
## `StatusApi.record_landed_blow`, never by naming `StatusCounters` itself. The meter feed
## that advances a counter store also lives behind the facade, in `status_engine.gd`.
const COUNTER_FILES: Array[String] = [
	"res://src/modules/status/api.gd",
	"res://src/modules/status/status_counters.gd",
	"res://src/modules/status/status_engine.gd",
]

## The mind tree: its own roles, shapes and locks — never the new mechanisms.
const MIND_FILES: Array[String] = [
	"res://src/modules/status/mind_status_def.gd",
	"res://src/modules/status/mind_status_api.gd",
	"res://src/modules/status/mind_status_catalog.gd",
]

const MIND_FORBIDDEN: Array[String] = [
	"family",
	"icd",
	"StatusCounters",
	"counter_snapshot",
	"status_meter_fired",
]

var _paths: Array[String] = []
var _codes: Dictionary = {}


func test_the_icd_clock_exists_in_exactly_two_files() -> void:
	assert_eq(
		_files_containing("icd_elapsed"),
		ICD_CLOCK_FILES,
		"the per-instance ICD clock lives in the runtime record and its one reader"
	)


func test_the_status_icd_vocabulary_lives_in_its_four_files() -> void:
	assert_eq(
		_files_containing("status_icd"),
		ICD_VOCAB_FILES,
		"the refusal vocabulary has ONE home per layer, never a second implementation"
	)


func test_the_family_field_is_declared_once() -> void:
	assert_eq(
		_files_containing("@export var family"),
		FAMILY_FILES,
		"one family declaration; a second one is the ADR 0066 copy defect"
	)


func test_the_counter_store_is_referenced_only_by_its_store_facade_and_funnel() -> void:
	assert_eq(
		_files_containing("StatusCounters"),
		COUNTER_FILES,
		"one counter store: its own file, the facade verbs, and the app funnel"
	)


func test_no_file_keeps_a_second_counter_table() -> void:
	var found: Array[String] = []
	for path in _all_paths():
		var code := _code_of(path)
		if code.contains("static var _by_actor") and code.to_lower().contains("counter"):
			found.append(path)
	found.sort()
	assert_eq(
		found,
		["res://src/modules/status/status_counters.gd"],
		"the per-actor table idiom with a counter in scope exists once"
	)


func test_the_mind_tree_is_not_gated_by_the_new_mechanisms() -> void:
	for path in MIND_FILES:
		var code := _code_of(path)
		assert_ne(code.is_empty(), true, "%s loads" % path)
		for token in MIND_FORBIDDEN:
			assert_eq(
				code.contains(token),
				false,
				"%s must not name '%s' (ADR 0902 decision 7)" % [path, token]
			)


# --- helpers ---------------------------------------------------------------------


## Every `.gd` under [constant SRC_ROOT], read ONCE per suite run (the scan is the
## expensive half; the cache is a member, so one suite instance pays it once).
func _all_paths() -> Array[String]:
	if _paths.is_empty():
		_paths = _gd_files(SRC_ROOT, 0)
		_paths.sort()
	return _paths


func _code_of(path: String) -> String:
	if not _codes.has(path):
		_codes[path] = _stripped_code(path)
	return _codes[path] as String


## A file's CODE with comments stripped: a docblock naming a token must not satisfy —
## or break — a scan.
func _stripped_code(path: String) -> String:
	var out := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


## Every file whose CODE contains `token`, sorted (the constants are alphabetical).
func _files_containing(token: String) -> Array[String]:
	var found: Array[String] = []
	for path in _all_paths():
		if _code_of(path).contains(token):
			found.append(path)
	found.sort()
	return found


## Every `.gd` under `root`, depth-capped at [constant MAX_DEPTH]. The `while` is the
## accepted DirAccess drain and the recursion carries the cap `test_no_unbounded_wait.gd`
## cannot see.
func _gd_files(root: String, depth: int) -> Array[String]:
	var found: Array[String] = []
	if depth > MAX_DEPTH:
		return found
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gd_files(path, depth + 1))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
