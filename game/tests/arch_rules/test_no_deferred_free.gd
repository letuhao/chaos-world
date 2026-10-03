extends TestCase

## The memory-safety rule as CODE, for every production script. AGENTS.md requires
## that nothing under `root` is left unfreed; the half of that rule this file
## enforces is the `queue_free()` half.
##
## `queue_free()` defers deletion to the end of the frame. The headless runner
## drives every test from inside `SceneTree._initialize()`, which returns before
## the first `SceneTree` iteration — so no frame is ever processed and a deferred
## free NEVER runs under test. Production code that frees this way is correct in
## the editor and leaks for the life of the process under `tools test`, which is
## where the leak is measured and therefore where it matters.
##
## Two incidents, both from this one cause:
##   - `WorldMapScreen._clear_graph()` left every rebuilt node parented, and each
##     `refresh()` stacked a fresh set on top.
##   - `ScreenStack.pop()` orphaned a whole screen subtree per navigation, which
##     is ~14 full screens per `navigate_to`.
##
## Together these took a `tests/ui` run to 67 GB resident and forced a power-cycle.
## `free()` is the correct primitive for both: the node is already detached from
## the tree, so there is nothing left to defer, and `free()` disconnects the
## node's signals on the way out.
##
## The honest limit: this is a source scan, so it cannot see a leak that uses
## neither `queue_free()` nor `free()`. That case — a node dropped on the floor
## with no free call at all — is what `RAM_CEILING_BYTES` in `tools/godot.py` is
## for. This rule catches the deferred shape; the ceiling catches the residue.

const SRC_ROOT := "res://src"
## The one legitimate caller. `queue_free()` is correct when something else owns
## the node's lifetime and the frame boundary is real, which the headless runner
## never provides — so there is no exemption here. If a future case needs one, it
## has to argue why the headless runner is not the environment, not that the
## deferral is convenient.
const ALLOWED_FILES: Array[String] = []


func test_no_production_script_defers_a_free() -> void:
	var audited := 0
	for path in _gdscript_files(SRC_ROOT):
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text.is_empty(), true, "%s is readable" % path)
		if not text.contains("queue_free"):
			continue
		# Comments explain the rule and must not read as a violation of it. Only
		# lines that actually call it count.
		for entry in _call_sites(text):
			audited += 1
			var relative := path.replace("res://", "")
			assert_eq(
				ALLOWED_FILES.has(relative),
				true,
				(
					(
						"%s calls queue_free() at line %d. The headless runner never "
						% [relative, entry.line]
					)
					+ "processes a frame, so a deferred free never runs there and the "
					+ "node leaks for the life of the process. Detach it, then free() "
					+ "it: see ScreenStack.pop()."
				)
			)
	# A scan that has gone blind passes forever, so prove it still reads files and
	# would still see a call. Both counts must be non-zero.
	assert_eq(audited > 0, true, "the scan still finds production scripts to audit")
	assert_eq(_gdscript_files(SRC_ROOT).size() > 0, true, "the scan still sees res://src")


## Every line that CALLS queue_free, as `{"line": int}` — comments that merely
## name it are the documentation of the rule, not violations of it.
func _call_sites(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines := text.split("\n")
	for index in lines.size():
		var line: String = lines[index].strip_edges()
		if line.begins_with("#"):
			continue
		# A trailing comment is stripped so prose after the call is not read as
		# part of it, but a call that is itself commented out stays excluded above.
		var code := line.split("#")[0]
		if code.contains("queue_free") and code.contains("("):
			out.append({"line": index + 1})
	return out


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
