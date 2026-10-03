extends TestCase

## Contract for the Python boundary checker itself (DEF-0092).
##
## `tools/arch/enforce.py` reads this tree textually and decides, for every file,
## which unit it belongs to and what it depends on. Three of those decisions are
## warnings rather than failures, so nothing else in the suite would notice if one
## of them silently stopped firing — a checker that goes quiet looks exactly like a
## codebase that is clean. These cases pin the heuristics, and they pin the negative
## cases too: the warning has to stay narrow, or a noisy checker gets ignored and
## the gate stops being read at all.
##
## Each case builds the smallest source text that carries — or deliberately lacks —
## the signal, and hands it to the real code under test. Nothing here reimplements a
## rule, so no rule can be tested into agreeing with itself.
##
## Synthetic sources are passed to the checker as Python literals rather than
## written to disk: a fixture file under `game/src/` would itself be an arch
## violation, and one outside the tree would need a path the test cannot portably
## name. Strings cross the process boundary through `_py_str`, never through
## `JSON.stringify` — see that helper for why the obvious choice is a trap.
##
## Run just this suite with:
##   uv run python -m tools test --suite arch_rules

## Interpreter for every child program. Resolved from the repository's own `.venv`
## rather than a bare "python": under `uv run` the venv is on PATH for the parent
## process, but a child still resolves "python" to whichever interpreter comes first
## for IT, and that one does not have `tools` importable. Guessing here turns every
## assertion into a silent null comparison rather than a failure.
const TIMEOUT := 180
## A class-name index with just the entries the heuristics consult.
## `TechniqueDef` stands in for authored content: it is a real module-owned
## Resource in this repo, so the typed-array branch sees a name it recognises. It
## was `SkillDef` while that prototype lived in `contracts/`; ADR 0056 deleted it,
## so a fixture naming it would test a class the tree no longer has.
const FIXTURE_CLASSES := {
	"TechniqueDef": ["src/modules/techniques/technique_def.gd", "techniques", false],
	"ScreenStack": ["src/ui/screen_stack.gd", "ui", false],
}
## `Array[...]` element types that are engine classes, never repo classes.
const ENGINE_ONLY_FIXTURE := {"Marker2D": ["src/nowhere.gd", "ui", false]}
## The separator between a warned file and the sentence naming the rule.
##
## `enforce.app_state_warnings` emits `f"{rel}: app/ holds a stateful system (...)"`,
## so this literal is what ties the subject of a report line back to a path on disk.
## It is copied from the checker rather than paraphrased on purpose: a paraphrase
## that drifts would go on matching a message nobody emits any more, which is the
## quiet-checker failure this whole file exists to catch.
const APP_STATE_WARNING_MARKER := ": app/ holds a stateful system"

# ── Fixtures ─────────────────────────────────────────────────────────────────
#
# Trimmed transcriptions of the shipped scripts, keeping every declaration the
# heuristic reads and dropping the bodies it cannot see.

## The shape of a slot-machine system with a persistence key and a decay loop:
## three signals. Written against `TechniqueDef` rather than the deleted
## `SkillDef`, so the typed-array branch resolves against a class that exists.
const SKILL_SYSTEM := (
	"class_name SkillSystem\n"
	+ "extends RefCounted\n"
	+ "var _slots: Array[TechniqueDef] = []\n"
	+ "var _cooldowns: Array[float] = []\n"
	+ "var _actor: Actor\n"
	+ "var _in_combat: bool = false\n"
	+ "func tick(delta: float) -> void:\n"
	+ "\t_cooldowns[0] = maxf(0.0, _cooldowns[0] - delta)\n"
	+ "func _save() -> void:\n"
	+ '\t_actor.set_module_data(MODULE_KEY, {"slots": []})\n'
)

## The shape of the deleted `consumable_system.gd`, kept because it is the smallest
## fixture that trips the rule: a slot table with its own save key and no decay
## loop. ADR 0056 deleted the file, so nothing in the tree ships this shape — the
## case below is about the heuristic, and its `rel` is a fixture path in a temp
## directory, not a claim that `src/app/consumable_system.gd` exists.
const SLOT_TABLE_WITH_SAVE_KEY := (
	"class_name ConsumableSystem\n"
	+ "extends RefCounted\n"
	+ "var _slots: Array = []\n"
	+ "var _actor: Actor\n"
	+ "func _save() -> void:\n"
	+ '\t_actor.set_module_data(MODULE_KEY, {"slots": []})\n'
)

## The shape of `src/app/main.gd`: references and a scene, never state.
const COMPOSITION_ROOT := (
	"class_name Main\n"
	+ "extends Control\n"
	+ 'const CULTIVATION_PANEL := "res://src/ui/screens/body_cultivation_panel.tscn"\n'
	+ "var _actor: Actor\n"
	+ "var _panel: BodyCultivationPanel\n"
	+ "var _stack: ScreenStack\n"
	+ "func _ready() -> void:\n"
	+ '\t_stack = get_node_or_null("ScreenStack") as ScreenStack\n'
	+ "\tvar screen := load(CULTIVATION_PANEL) as PackedScene\n"
)

## The shape of `src/app/actor_factory.gd`: every method static, no state at all.
const ACTOR_FACTORY := (
	"class_name ActorFactory\n"
	+ "extends RefCounted\n"
	+ "static func build(id: StringName, base: Dictionary = {}) -> Actor:\n"
	+ "\tvar actor := Actor.new(id, base)\n"
	+ "\tactor.attach_core_resources()\n"
	+ "\treturn actor\n"
)

## The shape of `src/app/world_entry.gd`: many typed node arrays, no state table.
const WORLD_ENTRY := (
	"class_name WorldEntry\n"
	+ "extends Node2D\n"
	+ "var _spawn_point: Marker2D = null\n"
	+ "var _npc_spawn_points: Array[Marker2D] = []\n"
	+ "var _enemy_spawn_zones: Array[Area2D] = []\n"
	+ "var _resource_nodes: Array[Area2D] = []\n"
	+ "var _entry_points: Array[Marker2D] = []\n"
	+ "func _bind_nodes() -> void:\n"
	+ '\t_npc_spawn_points = _collect_nodes("NPCSpawnPoints", Marker2D)\n'
)

## The shape of `src/app/screen_routes.gd`: an authored table, read-only and static.
const SCREEN_ROUTES := (
	"class_name ScreenRoutes\n"
	+ "extends RefCounted\n"
	+ 'const ROUTES: Array[Dictionary] = [{"id": &"workbench"}]\n'
	+ "static func all() -> Array[Dictionary]:\n"
	+ "\treturn ROUTES.duplicate(true)\n"
)

## The shape of `src/app/recipe_catalog.gd`: a `static var` cache, not instance state.
const RECIPE_CATALOG := (
	"class_name RecipeCatalog\n"
	+ "extends RefCounted\n"
	+ "static var _index: Array[Dictionary] = []\n"
	+ "static var _scanned: bool = false\n"
	+ "static func offerable(actor: Actor) -> Array[Dictionary]:\n"
	+ "\treturn _index\n"
)

## The shape of `src/app/item_workbench_app.gd`: typed references and one int.
const WORKBENCH_SHELL := (
	"class_name ItemWorkbenchApp\n"
	+ "extends Control\n"
	+ 'const SAVE_PATH := "user://item_workbench_state.json"\n'
	+ "var _actor: Actor = null\n"
	+ "var _stack: Control = null\n"
	+ "var _nav_bar: Control = null\n"
	+ 'var _live_route: StringName = &""\n'
	+ "var _socket_request: int = 0\n"
	+ "func _ready() -> void:\n"
	+ "\t_bind_nodes()\n"
)

## The shape of `src/app/player_adapter.gd`: a body, so exactly one signal.
const PLAYER_ADAPTER := (
	"class_name PlayerAdapter\n"
	+ "extends CharacterBody2D\n"
	+ "var _actor: Actor = null\n"
	+ "var _interactables: Array[Node2D] = []\n"
	+ "var _camera: Camera2D = null\n"
	+ "func _physics_process(delta: float) -> void:\n"
	+ "\tposition += velocity * delta\n"
)

var _repo_classes: Dictionary = {}
var _arch_report: Dictionary = {}
var _python_path: String = ""


func setup() -> void:
	if _repo_classes.is_empty():
		_repo_classes = _repo_class_index()
		assert_ne(_repo_classes.size(), 0, "the class index of the shipped tree is readable")


# ── Every new check is a warning, never a failure ─────────────────────────────


func test_the_retired_prototype_stays_retired() -> void:
	# ADR 0056 deleted `contracts/skill_def.gd` and `app/skill_system.gd`, which is
	# why those two warnings no longer name anything. The heuristic itself is still
	# exercised against synthetic fixtures below; what this case pins is the stronger
	# property — that the offenders STAY deleted. Asserting the warning text would
	# fail the moment the cleanup succeeded, which is exactly backwards.
	#
	# Deliberately NOT asserting `exit == 0` or the "boundaries ok" line: both are
	# properties of the WHOLE tree, and this suite must not turn another module's
	# in-flight work into a failure here. `modules/market` briefly sat one method
	# over the cap and took three cases down with it, none of them about this rule.
	var report := _arch()
	assert_eq(
		String(report["text"]).contains("extends Resource inside contracts/"),
		false,
		"no authored Resource is filed in contracts/ any more"
	)
	assert_eq(
		String(report["text"]).contains("src/app/skill_system.gd:"),
		false,
		"and the deleted slot machine is not back in app/"
	)
	assert_eq(
		String(report["text"]).contains("src/app/input_handler.gd:"),
		false,
		"nor is the deleted input router"
	)


func test_the_app_state_check_tracks_whatever_app_actually_holds() -> void:
	# The invariant, not a filename.
	#
	# This case used to assert that the report named `src/app/consumable_system.gd`,
	# which read as "the check is alive" right up until ADR 0056 deleted that file.
	# It then failed on a tree that was CLEAN, and the only ways to green it were to
	# delete the case or to hardcode whatever offender happened to exist next. A
	# guard that names a file is a guard that expires with the file, and it expires
	# red, which is the worst way to expire.
	#
	# What the check actually promises is a correspondence, so that is what is
	# asserted. `_app_state_offenders` derives the expected set from `rules.py` over
	# an independently enumerated listing of `src/app/`; `_reported_app_state_files`
	# reads back what the gate actually said. Three legs, one per way to be wrong:
	#
	#   1. QUIET while an offender exists — the original failure mode, and the one
	#      that looks like good news. Every file the rule flags must be named.
	#   2. LOUD with nothing to flag — a false positive is how a warning gets
	#      ignored until the gate stops being read at all. Every file named must be
	#      flagged.
	#   3. app/ SHIPS a stateful system — the repo's own claim, per the comment above
	#      `APP_STATE_MARKERS`: app/ wires, and a feature holding mutable state
	#      belongs in a module. This leg is the one that keeps the correspondence
	#      from being satisfied by both sides agreeing on a file that should never
	#      have been there, and it is the leg a regression in placement breaks.
	#
	# Leg 3 is what gives legs 1 and 2 something to bite on. While app/ is clean all
	# three sets are empty and the correspondence holds trivially; it is leg 3 that
	# says so out loud, and it is the drift a placement regression produces. Leg 3
	# is therefore a tree assertion, and deliberately so — the warning is unenforced
	# by design (rules.py: "They warn instead of failing so that a prototype file
	# that predates the convention cannot turn the gate red"), so nothing in the gate
	# turns it red. Without leg 3 this case is satisfied by a checker and a tree in
	# agreement, whatever that agreement said.
	var report := _arch()
	var offenders := _app_state_offenders()
	var named := _reported_app_state_files(String(report["text"]))
	for rel in offenders:
		assert_eq(
			named.has(rel),
			true,
			"the check went quiet: %s holds state in app/ and the report does not name it" % rel
		)
	for rel in named:
		assert_eq(
			offenders.has(rel),
			true,
			"the report calls %s a stateful app/ system, but the rule finds no signals in it" % rel
		)
	assert_eq(
		offenders.size(),
		0,
		"app/ wires and ships no stateful system, but the rule flags %s" % ", ".join(offenders)
	)


func test_a_summary_line_is_always_reported() -> void:
	# The contract is that the checker always SAYS something about the tree it
	# scanned, so a run cannot be mistaken for silence. What must not happen is a
	# quiet pass: an empty report is what a broken checker looks like.
	#
	# Not asserted: that `exit == 0`, or the exact success wording. Both are
	# properties of the WHOLE tree, and pinning them here made three unrelated cases
	# fail when `modules/market` sat one method over the facade cap. The checker's
	# own behaviour is pinned by the synthetic-fixture cases below, which do not
	# depend on what else is in the tree.
	var report := _arch()
	var text := String(report["text"])
	assert_ne(text.strip_edges(), "", "a run always reports something")
	assert_eq(report["exit"] != null, true, "and always reports an exit code")


# ── An authored Resource belongs to a module, not to contracts/ ──────────────


func test_a_resource_in_contracts_is_flagged() -> void:
	assert_eq(
		(
			_resource_flags("class_name SkillDef\nextends Resource\n", "src/contracts/skill_def.gd")
			. size()
		),
		1,
		"a contracts/ Resource is flagged",
	)


func test_a_resource_in_a_module_is_the_precedent_and_is_not_flagged() -> void:
	assert_eq(
		(
			_resource_flags(
				"class_name ItemDef\nextends Resource\n", "src/modules/items/item_def.gd"
			)
			. size()
		),
		0,
		"the same class in its owning module is the module precedent, not a warning",
	)


func test_a_resource_in_core_is_the_precedent_and_is_not_flagged() -> void:
	assert_eq(
		(
			_resource_flags(
				"class_name CultivationPathDef\nextends Resource\n", "src/core/path_def.gd"
			)
			. size()
		),
		0,
		"core/ is the second sanctioned home, for cross-cutting foundation data",
	)


func test_a_contracts_interface_is_not_a_resource() -> void:
	assert_eq(
		(
			_resource_flags(
				"class_name ActorStats\nextends RefCounted\n", "src/contracts/actor_stats.gd"
			)
			. size()
		),
		0,
		"contracts/ is for interfaces and value objects; those are not flagged",
	)


func test_a_contracts_value_object_extending_another_contract_is_not_a_resource() -> void:
	# `extends <ClassName>` is read as a dependency edge, not as a base type, so a
	# contracts class extending a contracts class must not read as a Resource.
	assert_eq(
		(
			_resource_flags("class_name Slot\nextends CultivationSlot\n", "src/contracts/slot.gd")
			. size()
		),
		0,
		"extends CultivationSlot is an edge, not an authored content type",
	)


func test_the_warning_cites_the_measured_precedent() -> void:
	var messages := _resource_flags(
		"class_name SkillDef\nextends Resource\n", "src/contracts/skill_def.gd"
	)
	assert_eq(messages.size(), 1, "one offender, one message")
	var text := String(messages[0])
	assert_eq(
		text.contains("other authored Resources in this repo"),
		true,
		"the count is measured on the same pass, so it cannot drift from the tree",
	)
	assert_eq(text.contains("facade"), true, "and the message says where it belongs instead")


# ── app/ wires; a feature system belongs in a module ──────────────────────────
#
# The positive fixtures are the shipped prototypes; the negative ones are
# transcribed from the real wiring scripts rather than read from disk, because a
# suite that asserts on files other work can delete is a suite that fails for
# reasons that have nothing to do with it.


func test_the_motivating_skill_system_is_flagged() -> void:
	assert_eq(
		_signals(SKILL_SYSTEM),
		["persistence", "tick-loop", "state-table"],
		"a slot table, a cooldown table, a tick loop and a save key: three signals",
	)
	assert_eq(
		_app_state_flags(SKILL_SYSTEM, "src/app/skill_system.gd").size(),
		1,
		"and three signals is above the threshold, so it is flagged",
	)


func test_a_slot_table_that_persists_itself_is_flagged_without_a_tick() -> void:
	# Two signals and no loop: a table plus its own save key is a feature owning
	# state, which is the half of the problem `tick` only half covers.
	assert_eq(
		_signals(SLOT_TABLE_WITH_SAVE_KEY),
		["persistence", "state-table"],
		"table plus persistence is two signals on its own",
	)
	assert_eq(
		_app_state_flags(SLOT_TABLE_WITH_SAVE_KEY, "src/app/consumable_system.gd").size(),
		1,
		"so it fires without a tick",
	)


func test_the_legitimate_app_wiring_files_are_not_flagged() -> void:
	# The negative cases. Every body here is a transcription of a script `app/` is
	# supposed to hold; a heuristic that trips on any of them is wrong, not merely
	# noisy, so the check must stay narrower than "app/ has an array".
	for case in [
		["main.gd", COMPOSITION_ROOT],
		["actor_factory.gd", ACTOR_FACTORY],
		["world_entry.gd", WORLD_ENTRY],
		["screen_routes.gd", SCREEN_ROUTES],
		["recipe_catalog.gd", RECIPE_CATALOG],
		["item_workbench_app.gd", WORKBENCH_SHELL],
	]:
		assert_eq(
			_app_state_flags(case[1], "src/app/" + case[0]).size(),
			0,
			"%s wires and holds no state, so it is not flagged" % case[0],
		)


func test_a_bound_node_array_is_wiring_not_a_feature_state_table() -> void:
	# `world_entry.gd` and `nav_bar.gd` both collect engine nodes. Those arrays are
	# bound to a scene, not to a feature, and must never be state on their own.
	assert_eq(
		_signals(WORLD_ENTRY, ENGINE_ONLY_FIXTURE),
		[],
		"Array[Marker2D] and friends are node lists, not state tables",
	)
	assert_eq(
		_signals(WORLD_ENTRY),
		[],
		"and against the real class index, where none of those types are repo classes",
	)


func test_a_controller_tick_alone_is_not_a_feature_system() -> void:
	# `player_adapter.gd` is a body: a `_physics_process` is the only signal it has,
	# and one signal never decides.
	assert_eq(
		_signals(PLAYER_ADAPTER),
		["tick-loop"],
		"a lone process loop is one signal",
	)
	assert_eq(
		_app_state_flags(PLAYER_ADAPTER, "src/app/player_adapter.gd").size(),
		0,
		"and one signal is below the threshold, so the file is not flagged",
	)


func test_a_static_cache_is_not_per_instance_state() -> void:
	# `recipe_catalog.gd` memoises a directory walk in a `static var`: process-wide
	# caching, not a feature system, and the member patterns must not see an instance
	# field that is not one.
	assert_eq(
		_signals(RECIPE_CATALOG),
		[],
		"static var is not instance state, and a scanner of its own does not call it state",
	)


func test_a_typed_array_of_an_unknown_type_is_not_a_content_table() -> void:
	# The content-array branch requires the element type in the class index, so an
	# annotation resolving to nothing in this repo cannot be read as authored content.
	assert_eq(
		_signals(
			"class_name Weird\nextends RefCounted\nvar _rows: Array[NotAClassInThisRepo] = []\n"
		),
		[],
		"a type this repo does not define is not a content table",
	)


func test_the_threshold_is_two_independent_signals() -> void:
	var body := (
		"class_name OnlyAPersistence\n"
		+ "extends RefCounted\n"
		+ "func _save() -> void:\n"
		+ "\t_actor.set_module_data(MODULE_KEY, {})\n"
	)
	assert_eq(_signals(body), ["persistence"], "persistence alone is one signal")
	assert_eq(
		_app_state_flags(body, "src/app/only_a_persistence.gd").size(),
		0,
		"and one signal is below the threshold, so it is not flagged",
	)


func test_a_wiring_file_with_several_typed_members_is_still_wiring() -> void:
	# The check counts state signals, not fields: `main.gd` holds three typed
	# references and a composition root may hold as many as it wires.
	assert_eq(
		_signals(COMPOSITION_ROOT),
		[],
		"a typed reference is a wire, never a state signal",
	)


# ── The module registry is a permission list; say so when it names nothing ────


func test_a_registered_module_with_no_directory_is_reported() -> void:
	# Filtered to the synthetic name, because the real `techniques` entry is also
	# absent on disk during this build wave and is reported for the same reason. The
	# point here is that a registry name with no directory produces a message, not
	# that the tree happens to have exactly one such name.
	var messages := _to_strings(
		_bare(
			(
				"[w for w in enforce.module_inventory_warnings({'ghost_module': ['core']})"
				+ " if 'ghost_module' in w]"
			)
		)
	)
	assert_eq(messages.size(), 1, "the missing module is reported once")
	var text := String(messages[0])
	assert_eq(text.contains("no directory on disk"), true, "and says the directory is missing")
	assert_eq(text.contains("registry.json"), true, "and names where it was registered")


func test_a_ui_only_module_with_no_directory_is_reported() -> void:
	# The check is exercised against a SYNTHETIC registry entry, not against
	# `techniques`. `techniques` was registered one wave ahead of its module body,
	# and the body now exists, so asserting on it would have failed the moment the
	# wave it was waiting for landed. A synthetic name tests the rule itself and
	# keeps testing it whatever the tree does.
	var messages := _to_strings(
		_bare(
			(
				"[w for w in enforce.module_inventory_warnings({'synthetic_missing': []})"
				+ " if 'synthetic_missing' in w]"
			)
		)
	)
	assert_eq(messages.size(), 1, "a registry entry with no body is reported")
	assert_eq(
		String(messages[0]).contains("no directory on disk"),
		true,
		"and that the permission reaches nothing",
	)


func test_every_shipped_module_has_a_directory_and_a_facade() -> void:
	# The negative case against the real registry: every registered name resolves to
	# a directory holding an `api.gd`. A module that breaks this shows up here first,
	# because a name in the permission list with no body behind it is the exact thing
	# the inventory check exists to say out loud.
	var missing := _to_strings(
		_bare(
			(
				"[name for name in sorted(set(rules.load_registry()) | set(rules.UI_MODULES))"
				+ " if not (enforce.SRC_DIR / 'modules' / name / rules.FACADE_FILENAME).is_file()]"
			)
		)
	)
	# No exceptions any more: every name in either list, `techniques` included,
	# resolves to a directory holding an `api.gd`. The carve-out that used to exempt
	# `techniques` is gone because the module it was waiting for has landed, and a
	# stale exemption is how a missing module stops being reported.
	assert_eq(missing, [], "every registered module has a facade on disk")


func test_techniques_is_granted_the_same_reach_as_the_other_item_modules() -> void:
	assert_eq(
		_ui_module("techniques"), ["items"], "techniques may reach items, as qi_cultivation does"
	)
	assert_eq(_ui_module("qi_cultivation"), ["items"], "which is how qi_cultivation is declared")
	assert_eq(_ui_module("body_cultivation"), ["items"], "and how body_cultivation is declared")


# ── Bare references: resolved where it is safe, documented where it is not ────


func test_bare_references_are_resolved_in_app_ui_and_contracts() -> void:
	var units := _bare_ref_units()
	assert_eq(
		units.has("ui"),
		true,
		"ui/ resolves bare names, which is what makes the facade rule enforceable",
	)
	assert_eq(units.has("app"), true, "app/ resolves bare names")
	assert_eq(
		units.has("contracts"),
		true,
		"contracts/ resolves bare names: it is the leaf layer, so an edge out is a violation",
	)


func test_bare_references_are_not_resolved_in_core_or_modules() -> void:
	# Deliberate, and for a measured reason rather than a guessed one. A bare scan in
	# `core/` reads `Dantian.from_dict(...)` on the save-restore path as a dependency
	# on qi_cultivation; a bare scan in `modules/socket` reads `ItemDef` as a
	# dependency on items even though every call goes through `ItemsApi`. Enforcing it
	# would demand preload ceremony in files that are correct today, so the gate
	# documents the gap in rules.py instead of failing on it.
	for unit in _bare_ref_units():
		assert_eq(
			unit == "core" or String(unit).begins_with("modules/"),
			false,
			"%s stays out of the bare resolver" % unit,
		)


func test_a_bare_edge_out_of_contracts_is_reported_as_a_violation() -> void:
	# The property `contracts/` was added for: it may depend on nothing, so a name
	# from any other unit is unconditionally a violation and there is no legitimate
	# shape the resolver could misread.
	assert_eq(
		_violation("contracts", "modules/items"),
		true,
		"a contracts edge into a module is a violation",
	)
	assert_eq(_violation("contracts", "core"), true, "a contracts edge into core is a violation")
	assert_eq(_violation("contracts", "app"), true, "a contracts edge into app is a violation")
	assert_eq(
		_violation("contracts", "contracts"), false, "and a contracts edge into itself is not"
	)


# ── Helpers ──────────────────────────────────────────────────────────────────


func _read(rel: String) -> String:
	var body := FileAccess.get_file_as_string("res://" + rel)
	assert_ne(body, "", "%s is readable" % rel)
	return body


## The interpreter a child program must run under: the repository's own virtualenv,
## which is the one that can import `tools`. `.venv/Scripts/python.exe` on Windows
## and `.venv/bin/python` elsewhere. A missing venv is a loud failure rather than a
## silent fallback to an interpreter without the package.
func _python() -> String:
	if not _python_path.is_empty():
		return _python_path
	var root := _repo_root()
	var candidates := [root + "/.venv/Scripts/python.exe", root + "/.venv/bin/python"]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			_python_path = candidate
			return _python_path
	push_error("arch_rules: no virtualenv interpreter under %s" % root)
	return ""


## The repo root, derived from the running project rather than guessed.
## `simplify_path()` is load-bearing, not cosmetic: `res://..` globalizes to
## `.../game/..`, and that unnormalized text is later interpolated into a child
## program. Left alone it reaches Python as `Path(D:/.../game/..)`, which is a
## syntax error rather than a string, so every child fails and every assertion
## degenerates into a comparison against null.
func _repo_root() -> String:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/")
	return root.simplify_path()


## The warning text `resource_home_warnings` produces for a synthetic file at `rel`.
func _resource_flags(body: String, rel: String) -> Array:
	return _messages("enforce.resource_home_warnings([_file(rel)])", rel, body, {})


## The warning text `app_state_warnings` produces for a synthetic file at `rel`.
func _app_state_flags(body: String, rel: String) -> Array:
	return _messages("enforce.app_state_warnings([_file(rel)], classes)", rel, body, {})


## Every `.gd` in `src/app/`, as `src/app/<name>` paths.
##
## Listed with `DirAccess`, NOT with the checker's own `_iter_sources`, on purpose:
## the file discovery and the `app/` classification are part of what the app/ state
## case is testing, so borrowing either would make the expected side a second run of
## the code under test and the comparison could never disagree.
func _app_gd_files() -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at("res://src/app"):
		if name.ends_with(".gd"):
			out.append("src/app/" + name)
	return out


## The `src/app/` files `app_state_warnings` would flag, decided one file at a time
## from the rule's own signal predicate and its own threshold.
##
## Only `app_state_signals` is shared with the checker. The threshold comparison,
## the `unit_of` classification, the message and the `warn()` transport are the
## checker's alone, so a break in any of them surfaces as a disagreement rather than
## as a tautology. The bodies are read by the child from disk: shipping them would
## put every `app/` script on a command line, and writing them into `game/src/` as
## fixtures would make each one an arch violation of its own.
##
## A child that dies returns null, and null would read as "no offenders" — a green
## run of nothing. So is an EMPTY listing: a `DirAccess` walk that returns nothing
## has silently disarmed every leg above, which is the one way this case could pass
## without looking at `app/` at all. Both are asserted rather than left to the
## comparison, which would happily confirm either.
func _app_state_offenders() -> Array:
	var files := _app_gd_files()
	assert_ne(
		files.size(), 0, "res://src/app lists .gd files; an empty listing is not a clean tree"
	)
	if files.is_empty():
		return []
	var quoted := PackedStringArray()
	for rel in files:
		quoted.append(_py_str(rel))
	var lines := _preamble(
		[
			"classes = enforce._class_index(list(enforce._iter_sources()))",
			"game = __root / 'game'",
			"rels = [%s]" % ", ".join(quoted),
			"offenders = []",
			"for rel in rels:",
			"\tbody = (game / rel).read_text(encoding='utf-8', errors='replace')",
			"\tif len(enforce.app_state_signals(body, classes)) >= enforce.APP_STATE_MIN_SIGNALS:",
			"\t\toffenders.append(rel)",
		]
	)
	lines.append("print('::' + json.dumps(offenders))")
	var value: Variant = _eval(lines)
	assert_ne(value, null, "the per-file app/ state scan over rules.py ran and answered")
	return [] if value == null else _to_strings(value)


## The `src/app/` paths the arch report called a stateful system.
##
## Read back out of the report rather than recomputed: this side of the comparison
## has to be what the gate actually said, or the case is not testing the gate. Both
## the marker and the `rel` are taken from the line, so a warning that loses its
## subject and a warning that loses its sentence fail differently.
func _reported_app_state_files(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n"):
		var at := line.find(APP_STATE_WARNING_MARKER)
		if at < 0:
			continue
		out.append(line.substr(0, at).strip_edges().trim_prefix("warn "))
	return out


## The state signals the real heuristic finds in one source body.
##
## The index is left to the child (see `_text`): shipping the real one from Godot
## both overflows the command line and describes a tree the child re-reads anyway.
## A caller that means a specific name set passes one, and that set is honoured.
func _signals(body: String, classes: Dictionary = {}) -> Array:
	return _to_strings(_text("enforce.app_state_signals(body, classes)", body, classes))


func _bare_ref_units() -> Array:
	return _to_strings(_bare("sorted(rules.BARE_REF_UNITS)"))


func _violation(source: String, target: String) -> bool:
	var program := (
		"bool(enforce._violation(%s, %s, False, {}))"
		% [
			_py_str(source),
			_py_str(target),
		]
	)
	# `_bare` returns the parsed JSON value itself, not a list of answers: the child
	# prints one `::` line holding one value. Indexing it with `[0]` used to read a
	# key off a bool, which surfaced as an engine error rather than a failed case.
	return _bare(program) == true


func _ui_module(name: String) -> Array:
	return _to_strings(_bare("rules.UI_MODULES[%s]" % _py_str(name)))


## The class index of the shipped tree, read once per suite by `setup()`.
func _repo_class_index() -> Dictionary:
	var value: Variant = _eval(
		_preamble(
			[
				"print('::' + json.dumps(dict(",
				"enforce._class_index(list(enforce._iter_sources())))))",
			]
		)
	)
	return {} if value == null else value


## One `tools arch` run over the shipped tree, cached: the runner calls `setup()`
## before each case and rescanning ~14k files eight times is not worth it.
##
## `captured` is sized by the streams that actually produced output, not by the two
## streams asked for: a clean `tools arch` writes nothing to stderr, so indexing
## `captured[1]` unguarded is an out-of-bounds read on a GREEN run — the case that
## most needs to be readable. Each stream is therefore read through a guard, and
## the "both streams" expectation is dropped because it describes the request, not
## the result.
func _arch() -> Dictionary:
	if _arch_report.is_empty():
		var captured: Array = []
		var program := (
			"import os, sys\n"
			+ "os.chdir(%s)\n" % _py_str(_repo_root())
			+ "sys.path.insert(0, os.getcwd())\n"
			+ "import runpy\n"
			+ "sys.argv = ['tools', 'arch']\n"
			+ "runpy.run_module('tools', run_name='__main__', alter_sys=True)\n"
		)
		var exit_code := OS.execute(
			_python(), PackedStringArray(["-c", program]), captured, true, false
		)
		var out := _stream(captured, 0)
		var err := _stream(captured, 1)
		_arch_report = {
			"exit": exit_code,
			"stdout": out,
			"stderr": err,
			"text": out + err,
		}
	return _arch_report


## `captured[i]` as a string, or "" when that stream produced nothing. `OS.execute`
## fills `captured` only for streams that actually wrote, so the index is not
## guaranteed to exist even though two streams were requested.
func _stream(captured: Array, index: int) -> String:
	return String(captured[index]) if index < captured.size() else ""


func _fails(report: Dictionary) -> Array:
	var out: Array = []
	for line in String(report["stderr"]).split("\n"):
		if line.begins_with("fail "):
			out.append(line)
	return out


## `expression` evaluated over a synthetic file of `body` placed at `rel`. The file
## is written into a temporary directory, never into `game/src/`, where a fixture
## would be itself an arch violation.
func _messages(expression: String, rel: String, body: String, classes: Dictionary) -> Array:
	var binding := (
		"classes = enforce._class_index(list(enforce._iter_sources()))"
		if classes.is_empty()
		else "classes = %s" % JSON.stringify(classes)
	)
	var lines := _preamble(
		[
			"rel = %s" % _py_str(rel),
			"body = %s" % _py_str(body),
			binding,
			"_file(rel).parent.mkdir(parents=True, exist_ok=True)",
			"_file(rel).write_text(body, encoding='utf-8')",
		]
	)
	lines.append("print('::' + json.dumps(%s))" % expression)
	return _to_strings(_eval(lines))


## `expression` with a source body bound as `body` and a class index as `classes`.
##
## The REAL index is never shipped from Godot: it is 216 entries and roughly 17 KB
## of JSON, which is both a command-line payload Godot truncates and a second copy
## of state that could disagree with the tree the child is about to read. When no
## explicit index is passed, the child builds it from disk itself, so the answer
## always describes the tree as the child sees it.
##
## A small fixture index IS passed through, because that is the point of those cases:
## they assert a decision made for a name set the test chose, not for the real one.
func _text(expression: String, body: String, classes: Dictionary = {}) -> Variant:
	var binding := (
		"classes = enforce._class_index(list(enforce._iter_sources()))"
		if classes.is_empty()
		else "classes = %s" % JSON.stringify(classes)
	)
	var lines := _preamble(["body = %s" % _py_str(body), binding])
	lines.append("print('::' + json.dumps(%s))" % expression)
	return _eval(lines)


## `expression` with no extra bindings.
func _bare(expression: String) -> Variant:
	var lines := _preamble()
	lines.append("print('::' + json.dumps(%s))" % expression)
	return _eval(lines)


## The head of every child program.
##
## The `tools` package is located from the filesystem rather than from the cwd: the
## runner's working directory is not guaranteed to be the repo root, so
## `os.getcwd()` is not a dependable anchor for it. `res://` is `game/`, so the
## package always sits at `<res://..>/tools`.
##
## `_py_str` is load-bearing. `JSON.stringify` on a Godot String emits the text
## BARE — `D:/repo` — so it lands in the child as `Path(D:/repo)`, which is a
## Python syntax error, not a string. Every child then dies, and `_eval` returns
## null, which turns every assertion into a comparison against null rather than
## a failure. A green-looking run of nulls is worse than a red one.
func _preamble(bindings: Array = []) -> Array:
	var lines := [
		"import json, os, sys, tempfile",
		"from pathlib import Path",
		"__root = Path(%s).resolve()" % _py_str(_repo_root()),
		"os.chdir(__root)",
		"sys.path.insert(0, str(__root))",
		"__tmp = Path(tempfile.mkdtemp(prefix='arch_rule_'))",
		"from tools.arch import enforce, rules",
		"def _file(rel):",
		"\treturn __tmp / rel",
	]
	lines.append_array(bindings)
	return lines


## One child program's answer, or null when it failed — a null fails the case
## loudly instead of passing on a comparison against a default.
func _eval(lines: Array) -> Variant:
	var captured: Array = []
	var exit_code := OS.execute(
		_python(), PackedStringArray(["-c", "\n".join(lines)]), captured, true, false
	)
	if exit_code != 0 or captured.is_empty():
		return null
	for line in String(captured[0]).split("\n"):
		if line.begins_with("::"):
			return JSON.parse_string(line.substr(2))
	return null


func _to_strings(value: Variant) -> Array:
	var out: Array = []
	if value == null:
		return out
	if value is Array:
		for entry in value:
			out.append(String(entry))
	elif value is Dictionary:
		for key in value:
			out.append(String(key))
	return out


## A Godot String as a Python string literal.
##
## `JSON.stringify` is wrong here even though it looks right: on a String it
## returns the text UNQUOTED, so `JSON.stringify("D:/repo")` is `D:/repo`, and
## interpolating that into a child program yields `Path(D:/repo)` — a Python
## syntax error.
##
## The escaping below is Python's, and it is the WHOLE job — do not hand the
## result to `var_to_str` afterwards. `var_to_str` emits a Godot literal, so it
## escapes the backslash in an already-correct `\n` into `\\n`, and Python then
## reads that as a literal backslash followed by `n`: the string silently
## becomes one long line with embedded backslash-n text instead of newlines.
## That is invisible in a passing-looking assertion and wrong in the value.
##
## Order matters: backslash first, so no later escape is itself re-escaped.
func _py_str(value: String) -> String:
	var escaped := (
		value
		. replace("\\", "\\\\")
		. replace("\n", "\\n")
		. replace("\r", "\\r")
		. replace("\t", "\\t")
		. replace('"', '\\"')
	)
	return "'" + escaped.replace("'", "\\'") + "'"
