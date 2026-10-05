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
##
## Every guard here is paired with a case that proves it can still SEE. A guard whose
## assertions all live inside a filter fires zero times on a clean tree, and zero is
## also exactly what a rule nothing violates produces — the two are indistinguishable
## in the tally. The synthetic fixtures those cases read are held below, in this file,
## and are never loaded.

const UI_ROOT := "res://src/ui"
const MODULES_ROOT := "res://src/modules"
## The shipped program's own roots. `scenes/` is where the composition root lives, so
## a screen it mounts is named there rather than in `src/`.
const PROGRAM_ROOTS := ["res://src", "res://scenes"]
## The facade width cap (`MAX_FACADE_PUBLIC_METHODS`) is DELETED by ADR 0265, and with
## it the local copy that used to live here. Coupling is measured as fan-in by
## `tools arch`, which is a Python-side sweep and cannot be asserted from GDScript.
## Extensions, not suffixes: a `.uid` sibling sits next to every script, and reading
## those would add noise without adding coverage.
##
## Note the absence of a leading dot, which `String.get_extension()` also omits: the
## three guards below used to filter on `".gd"` / `".tscn"` and so rejected every file
## in the tree, including the ones they exist to check. This table is the proof of the
## convention they should have followed.
const SCANNED_SUFFIXES := ["gd", "tscn"]
## The one file of a module that may be named from outside it. Spelled once so the
## rule and the proof that the rule still fires read the same string.
const FACADE_FILENAME := "api.gd"
## Directories under a program root that are not part of the program itself: the test
## suite and the editor's own addons. Anything here is not shipped code, so a rule
## about shipped code does not apply to it.
const EXCLUDED_DIRS := ["tests", "addons", "data", "assets"]

# --- Fixtures: one violation and one control per guard -----------------------
#
# The three guards below can each fire zero times on a clean tree and still look
# perfect in the tally — a filter that matches nothing and a tree with nothing to
# report are the same number. Each fixture here is a file that WOULD break its
# guard, so the proof is unconditional: it does not read `res://src/ui` at all, and
# it cannot be satisfied by that directory being empty.
#
# Synthetic text rather than files, deliberately. Nothing here is ever loaded, only
# scanned, and Godot parses every `.tscn` under `res://` as a resource and pairs
# every `.gd` with a `.uid` sibling — a file would be two extra artifacts to keep in
# step with a string. `tests/ui/fixtures/` holds the other kind: fixtures the engine
# instantiates. Holding the text here also keeps each fixture beside the assertion
# that reads it, so neither can be deleted alone.
#
# Paired with a control that must read CLEAN, or the proof could be satisfied by a
# predicate that flags everything — which is a guard with no rule in it at all.

## A `.tscn` in `src/ui/panels/` that instances a module script as a sub-resource.
const FACADE_FIXTURE_SCENE := {
	"path": "res://src/ui/panels/facade_fixture_panel.tscn",
	"text":
	(
		"[gd_scene load_steps=3 format=3]\n"
		+ "\n"
		+ '[ext_resource type="Script" path="res://src/ui/panels/other_panel.gd" id="1"]\n'
		+ (
			'[ext_resource type="Script" '
			+ 'path="res://src/modules/status/tribulation_blessing.gd" id="2"]\n'
		)
		+ "\n"
		+ '[node name="FixturePanel" type="Control"]\n'
		+ 'script = ExtResource("1")\n'
		+ 'blessing = ExtResource("2")\n'
	),
}

## The same shape naming nothing under `res://src/modules/`, which is every shipped
## scene.
const FACADE_FIXTURE_CLEAN_SCENE := {
	"path": "res://src/ui/panels/facade_fixture_clean_panel.tscn",
	"text":
	(
		"[gd_scene load_steps=2 format=3]\n"
		+ "\n"
		+ '[ext_resource type="Script" path="res://src/ui/panels/other_panel.gd" id="1"]\n'
		+ "\n"
		+ '[node name="FixturePanel" type="Control"]\n'
		+ 'script = ExtResource("1")\n'
	),
}

## A panel that binds a node in `@onready`, and resolves nothing else, so this fixture
## breaks the `@onready` guard and no other. Its own doc comment names the token on
## purpose: the guard must skip that comment and still catch the annotation below it.
const ONREADY_FIXTURE_SCRIPT := {
	"path": "res://src/ui/panels/onready_fixture_panel.gd",
	"text":
	(
		"extends VBoxContainer\n"
		+ "\n"
		+ "var _label: Label = null\n"
		+ "\n"
		+ "## This comment names @onready, and is not what the guard is looking for;\n"
		+ "## the annotation on the next line is.\n"
		+ "@onready var _bound: Label = $Row/Label\n"
	),
}

## A panel that only NAMES the token, in a comment — the shape every real panel that
## documents the rule has.
const ONREADY_FIXTURE_CLEAN_SCRIPT := {
	"path": "res://src/ui/panels/onready_fixture_clean_panel.gd",
	"text":
	(
		"extends VBoxContainer\n"
		+ "\n"
		+ "var _label: Label = null\n"
		+ "\n"
		+ "## No annotation here: this panel resolves lazily, which is why the token\n"
		+ "## is named in this comment and nowhere else.\n"
		+ "func _bind_nodes() -> void:\n"
		+ '\t_label = get_node_or_null("%Label")\n'
	),
}

## A panel that resolves a widget once, in `_ready()`. This is the case the lazy rule
## exists for and no shipped panel has: the headless runner drives suites from
## `SceneTree._initialize()` and never fires `_ready()`, so the binding never happens.
const LAZY_FIXTURE_SCRIPT := {
	"path": "res://src/ui/panels/lazy_fixture_panel.gd",
	"text":
	(
		"extends VBoxContainer\n"
		+ "\n"
		+ "var _rows: VBoxContainer = null\n"
		+ "\n"
		+ "func _ready() -> void:\n"
		+ '\t_rows = get_node_or_null("%Rows")\n'
	),
}

## The same panel resolving lazily, which is what every shipped panel does.
const LAZY_FIXTURE_CLEAN_SCRIPT := {
	"path": "res://src/ui/panels/lazy_fixture_clean_panel.gd",
	"text":
	(
		"extends VBoxContainer\n"
		+ "\n"
		+ "var _rows: VBoxContainer = null\n"
		+ "\n"
		+ "## Idempotent by construction: nothing is cached across calls, so binding\n"
		+ "## twice is the same as binding once.\n"
		+ "func _bind_nodes() -> void:\n"
		+ '\t_rows = get_node_or_null("%Rows")\n'
	),
}

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


func test_no_module_facade_is_an_empty_surface() -> void:
	# The facade WIDTH cap is gone (ADR 0265), so this no longer counts methods. The
	# rule that survives is the one the cap was never about: a facade that publishes
	# nothing is dead code, and a module that lost its interface by accident looks
	# exactly like a module that never had one.
	var facades := _facade_scripts()
	assert_eq(facades.is_empty(), false, "the modules publish facades")
	for path in facades:
		var script: GDScript = load(path)
		assert_ne(script, null, "%s loads" % path)
		if script == null:
			continue
		var public := _public_methods(script)
		assert_ne(
			public.is_empty(),
			true,
			"%s exposes something; a facade with no surface is dead code" % path
		)


func test_no_ui_file_reaches_a_module_by_anything_but_its_facade() -> void:
	# `ui/` may only name a module facade. A `.tscn` that instances a module resource
	# would put a concrete module type on the UI side of the boundary.
	#
	# Two filters decide whether this guard can see anything, and both are load-bearing:
	# `"tscn"` rather than `".tscn"` (a dotted comparison is true for every file in the
	# tree, so the filter `continue`d past everything it exists to check), and a module
	# listing that is not empty (no modules, no crossings, no assertion). Neither
	# reports itself: the dotted filter produced a green run on a clean tree and a
	# green run on a broken one, which is the shape of a guard that is not running.
	var modules := _module_dirs()
	assert_eq(
		modules.is_empty(), false, "the module tree lists directories, so a crossing is visible"
	)
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != "tscn":
			continue
		for module_dir in _module_dirs_named_by(entry["text"] as String, modules):
			assert_eq(
				_may_name_a_module(path),
				true,
				"%s names modules/%s/ directly; only api.gd may cross" % [path, module_dir]
			)


func test_the_facade_guard_still_sees_a_scene_that_names_a_module() -> void:
	# No shipped scene under `res://src/ui` names a module directory, so the scan above
	# runs to completion having asserted nothing and reports a tree that satisfies it.
	# That is the whole rule, so the guard protecting it — the architectural
	# constraint every screen in this program is written against — could go blind with
	# nothing to say so. The case below asks the same predicate the same question
	# about a fixture, so the difference between "the tree is clean" and "the guard is
	# asleep" is an assertion instead of a reading of the tally.
	#
	# Legs, one per way to be wrong, as in `test_arch_rules.gd`: the fixture IS a
	# crossing, the rule REJECTS it, and a scene naming nothing under `modules/` is not
	# one. Drop the third and the second would be satisfied by a predicate that flags
	# every scene it is shown.
	var path := String(FACADE_FIXTURE_SCENE["path"])
	assert_eq(path.get_extension(), "tscn", "the fixture is the shape the scan above filters for")
	assert_eq(
		_module_dirs_named_by(String(FACADE_FIXTURE_SCENE["text"]), _module_dirs()).is_empty(),
		false,
		"a scene that instances a module file is a crossing, and the scan sees it"
	)
	assert_eq(
		_may_name_a_module(path),
		false,
		"and the rule rejects that crossing, because a scene is not a module's facade"
	)
	assert_eq(
		(
			_module_dirs_named_by(String(FACADE_FIXTURE_CLEAN_SCENE["text"]), _module_dirs())
			. is_empty()
		),
		true,
		"a scene naming nothing under modules/ is not a crossing"
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
	# `"gd"` rather than `".gd"`: `String.get_extension()` omits the dot, so the dotted
	# comparison this filter used to make was true of EVERY script under `src/ui`, every
	# one of them was skipped, and the guard reported `asserted nothing`. This is the one
	# filter whose blindness no shape of the tree could expose: the loop was written to
	# assert once per `.gd` file, so on paper the count looked right and in the tally it
	# was zero. A guard that filters with a string nothing produces is the same guard as
	# no guard, and it reads exactly like a rule nothing violates.
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != "gd":
			continue
		assert_eq(
			_binds_in_onready(entry["text"] as String),
			false,
			(
				"%s binds a node in @onready; panels must resolve in _bind_nodes() so a " % path
				+ "screen is drivable before a scene tree exists"
			)
		)


func test_the_onready_guard_still_sees_an_onready_binding() -> void:
	# The scan above asks one boolean question of each panel. Nothing in `res://src/ui`
	# answers it with a yes, so the answer it returns is unverified: a guard that asked
	# the wrong question, or of the wrong text, would report this tree as clean. Three
	# legs, as in `test_arch_rules.gd` — the fixture binds in `@onready` and IS caught,
	# and a panel that only NAMES the token in a comment is NOT, which is what keeps the
	# first leg from being satisfied by a guard that flags the word wherever it finds it.
	assert_eq(
		String(ONREADY_FIXTURE_SCRIPT["path"]).get_extension(),
		"gd",
		"the fixture is the shape the scan above filters for"
	)
	assert_eq(
		_binds_in_onready(String(ONREADY_FIXTURE_SCRIPT["text"])),
		true,
		"a panel that binds a node in @onready is caught"
	)
	assert_eq(
		_binds_in_onready(String(ONREADY_FIXTURE_CLEAN_SCRIPT["text"])),
		false,
		"and a panel that only names the token in a comment is not, which every real one does"
	)


func test_ui_scripts_resolve_their_nodes_lazily() -> void:
	# The positive form of the rule above: a panel that binds widgets must do it
	# through an idempotent `_bind_nodes()`, not a one-shot in `_ready()`.
	#
	# Asked of every `.gd` file rather than of the subset that resolves something, for
	# two reasons. The dotted filter used to make this ask nothing at all (see the guard
	# above), and the inner `continue` meant the count depended on how many panels
	# happened to resolve nodes: a panel that stopped resolving, or a UI program with no
	# panels in it, both read as a tree with nothing to break this rule.
	for entry in _source_texts(UI_ROOT):
		var path: String = entry["path"]
		if path.get_extension() != "gd":
			continue
		assert_eq(
			_resolves_without_bind_nodes(entry["text"] as String),
			false,
			"%s resolves nodes, so it must do it in an idempotent _bind_nodes()" % path
		)


func test_the_lazy_bind_guard_still_sees_a_panel_that_resolves_nothing_lazily() -> void:
	# The other half of the pair above, and the quieter failure of the two: its filter was
	# the same dotted comparison AND its body skipped every file that resolved nothing,
	# so both halves could go blind together: a UI program with no panels in it, or a
	# panel that stopped resolving, each produced a zero that reads like a clean tree.
	# Three legs: a panel resolving in `_ready()` IS caught, the same panel resolving in
	# `_bind_nodes()` is NOT, and the fixture is the shape the scan filters for.
	assert_eq(
		String(LAZY_FIXTURE_SCRIPT["path"]).get_extension(),
		"gd",
		"the fixture is the shape the scan above filters for"
	)
	assert_eq(
		_resolves_without_bind_nodes(String(LAZY_FIXTURE_SCRIPT["text"])),
		true,
		"a panel that resolves a widget in _ready() and has no _bind_nodes() is caught"
	)
	assert_eq(
		_resolves_without_bind_nodes(String(LAZY_FIXTURE_CLEAN_SCRIPT["text"])),
		false,
		"and the same panel resolving in _bind_nodes() is not, which every real one does"
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


## The module directories `text` names. A plain `contains` over the file's own text,
## so it is asked about a file that has not been loaded — which is the point: the rule
## is about what a UI file NAMES, and a load would have to resolve first.
func _module_dirs_named_by(text: String, modules: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for module_dir in modules:
		if text.contains("res://src/modules/%s/" % module_dir):
			out.append(module_dir)
	return out


## Whether `path` may name a module at all. The entire facade rule in one expression,
## read by the scan AND by the case that proves the scan can still see, so the proof
## cannot be satisfied by a rule the scan never consults.
func _may_name_a_module(path: String) -> bool:
	return path.ends_with(FACADE_FILENAME)


## Whether `text` binds a node in `@onready`. Comments are stripped first: the panels
## document *why* they resolve lazily by naming the token, and a doc comment is not a
## regression.
func _binds_in_onready(text: String) -> bool:
	return _strip_comments(text).contains("@onready")


## Whether `text` resolves nodes without an idempotent `_bind_nodes()` to resolve them
## in. A file that resolves nothing has no widgets to bind, so it is not a violation
## and the rule reads as "resolves ⇒ binds in `_bind_nodes()`" — which is why the scan
## asks it of every file rather than of a filtered subset.
func _resolves_without_bind_nodes(text: String) -> bool:
	var code := _strip_comments(text)
	return code.contains("get_node_or_null(") and not code.contains("func _bind_nodes()")


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
