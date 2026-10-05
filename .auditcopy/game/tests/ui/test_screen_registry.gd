extends TestCase

## The screen registration seam (ADR 0184 §6): `ScreenRegistry` maps a screen id
## to `{scene_path, label}`, and `ScreenStack.push_registered` mounts by id.
##
## Every refusal is asserted BEHAVIOURALLY — by its return value and by the
## state it leaves untouched — never by driving a `push_error` branch. The
## loud errors themselves are covered by the source census in
## `tests/core/test_reconcile_stamp.gd`, which pins the same shape.

const STACK_SCENE := "res://src/ui/screens/screen_stack.tscn"
const FIXTURE_SCENE := "res://tests/fixtures/registry_fixture_screen.tscn"
const WORKBENCH_SCENE := "res://src/ui/screens/item_workbench.tscn"


## Duck-typed stand-in for the stored `RegistrationContext` rows: the seam reads
## `ctx.screens` and nothing else, so the test never names the module that owns
## the real context type (the facade-only rule).
class FakeContext:
	extends RefCounted

	var screens: Array[Dictionary] = []


func setup() -> void:
	ScreenRegistry.clear()


func teardown() -> void:
	ScreenRegistry.clear()


# --- The registry -----------------------------------------------------------


func test_register_stores_the_row_and_lookup_resolves_to_the_path() -> void:
	assert_eq(
		ScreenRegistry.register("fixture", FIXTURE_SCENE, "Fixture"), true, "a fresh id is accepted"
	)
	assert_eq(ScreenRegistry.path_of("fixture"), FIXTURE_SCENE, "lookup resolves to the path")
	assert_eq(ScreenRegistry.label_of("fixture"), "Fixture", "and the label is kept")
	assert_eq(ScreenRegistry.ids(), ["fixture"], "ids() lists the registered id")


func test_register_refuses_a_duplicate_id_and_keeps_the_first_row() -> void:
	assert_eq(
		ScreenRegistry.register("fixture", FIXTURE_SCENE, "First"),
		true,
		"the first row is accepted"
	)
	assert_eq(
		ScreenRegistry.register("fixture", WORKBENCH_SCENE, "Second"),
		false,
		"a duplicate id is refused"
	)
	assert_eq(
		ScreenRegistry.path_of("fixture"), FIXTURE_SCENE, "the first row is kept, not overwritten"
	)
	assert_eq(ScreenRegistry.label_of("fixture"), "First", "and its label too")
	assert_eq(ScreenRegistry.ids().size(), 1, "still exactly one row")


func test_register_refuses_an_empty_id_and_an_empty_scene_path() -> void:
	assert_eq(ScreenRegistry.register("", FIXTURE_SCENE, "NoId"), false, "an empty id is refused")
	assert_eq(
		ScreenRegistry.register("no_path", "", "NoPath"), false, "an empty scene path is refused"
	)
	assert_eq(ScreenRegistry.ids().size(), 0, "neither refusal stored a row")


func test_lookup_of_an_unknown_id_is_empty() -> void:
	assert_eq(ScreenRegistry.path_of("never_registered"), "", "an unknown id resolves to no path")
	assert_eq(ScreenRegistry.label_of("never_registered"), "", "and no label")


# --- The wire thread ---------------------------------------------------------


func test_register_from_contexts_folds_the_recorded_rows() -> void:
	var ctx := FakeContext.new()
	ctx.screens = [
		{"id": "fixture", "scene": FIXTURE_SCENE, "label": "Fixture"},
		{"id": "workbench", "scene": WORKBENCH_SCENE, "label": "Workbench"},
	]
	assert_eq(ScreenRegistry.register_from_contexts([ctx]), 2, "both recorded rows are accepted")
	assert_eq(ScreenRegistry.path_of("fixture"), FIXTURE_SCENE, "the first row resolves")
	assert_eq(ScreenRegistry.path_of("workbench"), WORKBENCH_SCENE, "and the second")


func test_register_from_contexts_refuses_a_duplicate_and_skips_a_null_context() -> void:
	var ctx := FakeContext.new()
	ctx.screens = [
		{"id": "fixture", "scene": FIXTURE_SCENE, "label": "First"},
		{"id": "fixture", "scene": WORKBENCH_SCENE, "label": "Duplicate"},
	]
	assert_eq(
		ScreenRegistry.register_from_contexts([ctx]),
		1,
		"the duplicate row is refused, not folded twice"
	)
	assert_eq(ScreenRegistry.path_of("fixture"), FIXTURE_SCENE, "the first row won")
	assert_eq(ScreenRegistry.register_from_contexts([null]), 0, "a null context is skipped")


# --- Mounting through the stack ----------------------------------------------


func test_push_registered_mounts_the_registered_screen() -> void:
	ScreenRegistry.register("fixture", FIXTURE_SCENE, "Fixture")
	var stack: ScreenStack = load(STACK_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	var screen := stack.push_registered("fixture")
	assert_ne(screen, null, "the registered screen is mounted")
	assert_eq(stack.depth(), 1, "one screen on the stack")
	assert_eq(stack.current() == screen, true, "and it is the live one")
	assert_eq(screen.scene_file_path, FIXTURE_SCENE, "the fixture scene, by its own path")
	assert_eq(screen.call("summary"), {"fixture": true}, "its summary reports it")
	stack.free()


func test_push_registered_refuses_an_unknown_id_and_leaves_the_stack_empty() -> void:
	var stack: ScreenStack = load(STACK_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	assert_eq(stack.push_registered("never_registered"), null, "an unknown id mounts nothing")
	assert_eq(stack.depth(), 0, "the stack is untouched")
	assert_eq(stack.current(), null, "and no screen is live")


# --- The old path is unaffected ------------------------------------------------


func test_existing_mounting_by_direct_load_is_unaffected() -> void:
	var stack: ScreenStack = load(STACK_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	var screen := load(WORKBENCH_SCENE).instantiate() as Control
	stack.push(screen)
	assert_eq(stack.depth(), 1, "a directly loaded screen still mounts")
	assert_eq(stack.current() == screen, true, "and is the live one")
	assert_eq(stack.summary()["input_names"], [String(screen.name)], "and owns input")
	stack.free()
