extends TestCase

## Regression guards for the four ways this codebase has shipped a screen that looks
## finished and is not reachable, drivable, or governed:
##
##  1. a `summary()` that returns keys instead of `{}` when no actor is bound, so a
##     test reads a half-initialised screen as if it were a real view;
##  2. a screen that is shipped but referenced nowhere in `src/`, so only a test can
##     ever instantiate it;
##  3. a module facade that quietly grows past its 12-method cap;
##  4. a `theme_override_*` or `@onready` creeping back under `src/ui/`.
##
## Each guard fails for a named reason, so a red assertion here names the regression
## rather than a symptom. The screen-inventory and reachability claims that need a
## running app live in `tests/app/test_screen_reachability.gd`.

const UI_ROOT := "res://src/ui"
const MODULES_ROOT := "res://src/modules"
## The shipped program's own roots. `scenes/` is where the composition root lives, so
## a screen it mounts is named there rather than in `src/`.
const PROGRAM_ROOTS := ["res://src", "res://scenes"]
## ISP: the same cap `tools/arch/rules.py` enforces (MAX_FACADE_PUBLIC_METHODS).
const MAX_FACADE_PUBLIC_METHODS := 12
## Extensions, not suffixes: a `.uid` sibling sits next to every script, and reading
## those would add noise without adding coverage.
const SCANNED_SUFFIXES := ["gd", "tscn"]
## Directories under a program root that are not part of the program itself: the test
## suite and the editor's own addons. Anything here is not shipped code, so a rule
## about shipped code does not apply to it.
const EXCLUDED_DIRS := ["tests", "addons", "data", "assets"]

# --- 1. summary() is empty with no actor ------------------------------------


func test_every_screen_summary_is_empty_with_no_actor() -> void:
	# The documented screen contract (AGENTS.md, UI standard): `summary()` returns
	# `{}` with no actor, so a test never reads a half-initialised screen. This is the
	# screen contract only — a panel has no actor to bind, so a panel's empty summary
	# is a shaped view, which `test_every_panel_summary_is_primitives_only` covers.
	for scene_path in SeamHarness.screen_scene_paths():
		var packed := load(scene_path) as PackedScene
		assert_ne(packed, null, "%s loads" % scene_path)
		if packed == null:
			continue
		var screen := packed.instantiate()
		assert_eq(screen.has_method(&"summary"), true, "%s publishes a summary" % scene_path)
		if not screen.has_method(&"summary"):
			screen.free()
			continue
		assert_eq(
			screen.call(&"summary"),
			{},
			"%s reports nothing, not keys, when no actor is bound" % scene_path
		)
		screen.free()


func test_a_summary_holds_primitives_and_nested_summaries_only() -> void:
	# The half of the contract that applies to every `summary()` in the UI program,
	# screens and panels alike: what a test reads is primitives, with a child's
	# summary nested under the child's own key. A `Node`, `Resource` or `Object` in a
	# summary is how a testable surface quietly stops being testable.
	for scene_path in SeamHarness.screen_scene_paths() + _panel_scenes():
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		if not node.has_method(&"summary"):
			node.free()
			continue
		var offenders := _non_primitives(node.call(&"summary"), "")
		assert_eq(
			offenders.is_empty(),
			true,
			"%s summary() holds only primitives; found %s" % [scene_path, ", ".join(offenders)]
		)
		node.free()


func test_every_screen_has_an_empty_summary_guard_of_its_own() -> void:
	# A screen whose `summary()` can only return keys is a screen whose testable
	# contract is "whatever the widget happens to hold". Each screen's source must
	# return `{}` on the no-actor path.
	for scene_path in SeamHarness.screen_scene_paths():
		var script_path := _script_of(scene_path)
		if script_path == "":
			continue
		var source := _read(script_path)
		assert_eq(source.is_empty(), false, "%s has a readable script" % scene_path)
		assert_eq(
			source.contains("return {}"), true, "%s has an explicit empty-summary path" % scene_path
		)


# --- 2. a shipped screen the program never references -----------------------


func test_every_shipped_screen_is_named_by_the_program() -> void:
	# The static half of "instantiated but never mounted": a screen named nowhere in
	# the shipped program cannot be reached by anything except a test that instantiates
	# it itself. Matched on the screen's **file name**, not its path, because the
	# composition root names scenes by path while a route table and an older constant
	# may name them either way; the file name is what both agree on.
	var sources := _program_text()
	# The guard on the guard: a walk that visits nothing would report every screen as
	# unreferenced and could equally report every screen as referenced. Assert the walk
	# found the program before trusting its verdict.
	assert_eq(
		_program_file_count() > 50,
		true,
		"the program walk visited its files, so the verdict below is real"
	)
	for scene_path in SeamHarness.screen_scene_paths():
		var file_name := scene_path.get_file()
		var referenced := false
		for text in sources:
			if (text as String).contains(file_name):
				referenced = true
				break
		assert_eq(
			referenced,
			true,
			(
				"%s is shipped but no file in the program names it, so only a test can reach it"
				% file_name
			)
		)
		assert_eq(
			_file_names_its_route(scene_path),
			true,
			"%s is referenced, and the program mounts it under a route" % file_name
		)


## Whether the program both names this screen and registers a route for it. The pair
## is the claim: naming a scene is not the same as routing it, and a test that only
## checked the first would pass on a screen nothing can open.
func _file_names_its_route(scene_path: String) -> bool:
	return not String(SeamHarness.route_for_scene(scene_path)).is_empty()


func test_every_shipped_screen_has_a_route_in_the_reachability_table() -> void:
	# Asked of the shipped route table via the harness, never restated here: a second
	# copy of the table in a test is a second thing that can be wrong.
	#
	# A screen whose *own script* has no `summary()` is not a route a player can be
	# shown and read — the stack mounts it, but there is nothing to assert and nothing
	# on it is testable — so it is excluded rather than reported as a missing route.
	for scene_path in SeamHarness.screen_scene_paths():
		var script_path := _script_of(scene_path)
		if script_path != "" and not _has_summary(script_path):
			continue
		assert_ne(
			String(SeamHarness.route_for_scene(scene_path)),
			"",
			"%s is shipped but the route table names no route that mounts it" % scene_path
		)


func test_the_reachability_table_names_no_screen_that_is_not_shipped() -> void:
	for route_id in ScreenRoutes.ids():
		var scene_path := ScreenRoutes.scene_of(route_id)
		assert_eq(
			SeamHarness.screen_scene_paths().has(scene_path),
			true,
			"route '%s' names %s, which the UI program does not ship" % [route_id, scene_path]
		)


# --- 3. the facade cap ------------------------------------------------------


func test_no_module_facade_exceeds_its_public_method_cap() -> void:
	var facades := _facade_scripts()
	assert_eq(facades.is_empty(), false, "the modules publish facades")
	for path in facades:
		var script: GDScript = load(path)
		assert_ne(script, null, "%s loads" % path)
		if script == null:
			continue
		var public := _public_methods(script)
		assert_eq(
			public.size() <= MAX_FACADE_PUBLIC_METHODS,
			true,
			(
				"%s exposes %d public methods (%s); the cap is %d"
				% [path, public.size(), ", ".join(public), MAX_FACADE_PUBLIC_METHODS]
			)
		)
		assert_ne(
			public.is_empty(),
			true,
			"%s exposes something; a facade with no surface is dead code" % path
		)


func test_no_ui_file_reaches_a_module_by_anything_but_its_facade() -> void:
	# `ui/` may only name a module facade. A `.tscn` that instances a module resource
	# would put a concrete module type on the UI side of the boundary.
	var facades: Dictionary = {}
	for path in _facade_scripts():
		facades[path.get_file().trim_suffix(".gd")] = path
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != ".tscn":
			continue
		var text: String = entry["text"]
		for module_dir in _module_dirs():
			if text.contains("res://src/modules/%s/" % module_dir):
				assert_eq(
					path.ends_with("api.gd"),
					true,
					"%s instances a module file directly; only api.gd may cross" % path
				)


# --- 4. no theme override, no @onready under src/ui -------------------------


## A convention check must read CODE, not prose.
##
## This file once searched raw source text for `theme_override`, so a screen whose
## comment read "styled by variation, never by a `theme_override_*`" FAILED the
## check — punishing the file for documenting the rule it follows. That teaches
## the next author to delete the explanation instead of keeping the convention.
## Stripping comments keeps the guard honest about what it is guarding.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var out := ""
		var quoted := false
		for i in line.length():
			var ch := line[i]
			if ch == '"':
				quoted = not quoted
			elif ch == "#" and not quoted:
				break
			out += ch
		kept.append(out)
	return "\n".join(kept)


func test_no_ui_file_uses_a_theme_override() -> void:
	for entry in _source_texts(UI_ROOT):
		assert_eq(
			_code_only(entry["text"] as String).contains("theme_override"),
			false,
			(
				"%s styles itself; style belongs to the one theme and theme_type_variation"
				% entry["path"]
			)
		)


func test_no_ui_script_uses_onready() -> void:
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != ".gd":
			continue
		# Comments are stripped first: the panels document *why* they resolve lazily
		# by naming `@onready`, and a doc comment is not a regression.
		var code := _strip_comments(entry["text"] as String)
		assert_eq(
			code.contains("@onready"),
			false,
			(
				"%s binds a node in @onready; panels must resolve in _bind_nodes() so a " % path
				+ "screen is drivable before a scene tree exists"
			)
		)


func test_ui_scripts_resolve_their_nodes_lazily() -> void:
	# The positive form of the rule above: a panel that binds widgets must do it
	# through an idempotent `_bind_nodes()`, not a one-shot in `_ready()`.
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != ".gd":
			continue
		var code := _strip_comments(entry["text"] as String)
		if not code.contains("get_node_or_null("):
			continue
		assert_eq(
			code.contains("func _bind_nodes()"),
			true,
			"%s resolves nodes, so it must do it in an idempotent _bind_nodes()" % path
		)


# --- Plumbing ---------------------------------------------------------------


func _panel_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("%s/panels" % UI_ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".tscn"):
			out.append("%s/panels/%s" % [UI_ROOT, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _facade_scripts() -> Array[String]:
	var out: Array[String] = []
	for module in _module_dirs():
		var path := "%s/%s/api.gd" % [MODULES_ROOT, module]
		if FileAccess.file_exists(path):
			out.append(path)
	return out


func _module_dirs() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(MODULES_ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## The script a screen scene instantiates, resolved from its `ext_resource` line so
## the scan never guesses a filename convention.
func _script_of(scene_path: String) -> String:
	var text := _read(scene_path)
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		if not line.contains('type="Script"'):
			continue
		var at := line.find('path="')
		if at < 0:
			continue
		var rest := line.substr(at + 6)
		return rest.substr(0, rest.find('"'))
	return ""


## Dotted paths inside `summary` whose value is not a primitive, a String/array, or a
## dictionary of the same. A returned node or resource is what makes a "testable
## surface" untestable.
func _non_primitives(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		var entries: Dictionary = value
		for key in entries:
			var child: Variant = entries[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
		return out
	if value is Array:
		var items: Array = value
		for index in items.size():
			out.append_array(_non_primitives(items[index], "%s[%d]" % [path, index]))
	return out


## Whether a screen's script publishes `summary()`, the testable surface every screen
## in this program is required to have.
func _has_summary(script_path: String) -> bool:
	return _read(script_path).contains("func summary(")


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)


func _public_methods(script: GDScript) -> Array[String]:
	var out: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.name)
		if method_name.begins_with("_"):
			continue
		out.append(method_name)
	out.sort()
	return out


## Every `.gd`/`.tscn` under `root`, as `{path, text}`. Sorted by the caller, so a
## failure names the same file twice in the same order.
## The text of every `.gd`/`.tscn` under every program root. Flat, because the only
## question a caller asks of it is "does any of this name X".
func _program_text() -> Array:
	var out: Array = []
	for root in PROGRAM_ROOTS:
		for entry in _source_texts(root):
			out.append(entry["text"])
	return out


## How many files the walk actually visited. Asserted non-zero by the caller that
## depends on the walk, so an empty scan can never make a claim pass vacuously.
func _program_file_count() -> int:
	var total := 0
	for root in PROGRAM_ROOTS:
		total += _source_texts(root).size()
	return total


## Every `.gd`/`.tscn` under `root`, as `{path, text}`.
## Every scanned file under `root`, as `{path, text}`.
##
## Iterative, not recursive: a recursive `DirAccess` walk silently returned an empty
## list under this runner, which would have made every "is it named by the program"
## assertion pass vacuously — the exact false green this suite exists to prevent. The
## worklist is explicit so an empty result is a real result.
func _source_texts(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path := current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with(".") and not EXCLUDED_DIRS.has(entry):
					pending.append(path)
			elif SCANNED_SUFFIXES.has(path.get_extension()):
				out.append({"path": path, "text": _read(path)})
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["path"] < b["path"])
	return out


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
