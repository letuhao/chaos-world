extends TestCase

## THE ARRIVAL IS A NODE IN A TREE. The proof for DEF-0183's remaining half.
##
## ## What was broken
##
## `CharacterCreationProgram._stand_in_the_world` and
## `ItemWorkbenchBody.stand_restored_in_the_world` each constructed a `PlayerAdapter` and
## handed it to `WorldStage.mount` — and **never `add_child`ed it**. Every stage call still
## answered `{"ok": true, …}`, because nothing in `mount` could tell the difference. Three
## capabilities were quietly severed by the missing parent:
##
##  1. `_world_entry()` requires `get_parent() != null`, so it returned null;
##  2. `_register_nodes()` therefore returned early, `_nodes` stayed empty, and the
##     playfield's authored `ResourceNodes` never reached the adapter;
##  3. the adapter's own `_interactables` stayed EMPTY, so `interact()` exited at its first
##     line — and an unparented node is in no `SceneTree`, so `_unhandled_input` was never
##     delivered to it either.
##
## ## Why the EXISTING suite could not see it
##
## `test_world_stage.gd`'s `_mounted()` helper adds the adapter to `root` ITSELF (line 84),
## so that suite supplied the parent the production path never did. Every case below drives
## the SHIPPED path instead, which is the only way the difference is observable at all.

## The origin id the shipped catalog offers, asked of the catalog rather than hardcoded, so
## a content rename fails here by name instead of silently turning every case into a refusal.
var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _born: Array = []


func setup() -> void:
	SeamHarness.clear_save()
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp


func teardown() -> void:
	# Freed, never queued. The runner shares one process across every suite and never
	# reaches the end of a frame, so a `queue_free()` here is a permanent node (INC-0002).
	WorldStage.release_the_tree(WorldStage.player())
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null
	for born in _born:
		var body := born as Actor
		if body != null:
			body.resources.clear()
	_born.clear()
	SeamHarness.clear_save()
	if WorldStage.instance() != null:
		WorldStage.instance().leave()


## The mounted root's OWN creation program, read out of the commit callable the live arrival
## screen was bound with — never a freshly constructed one, which would prove a program can
## build a hero rather than that the shipped boot can.
##
## Narrowed through `is Callable` rather than `get(...) as Callable`: a screen that was
## never bound holds a DEFAULT-CONSTRUCTED `Callable`, and casting to `Callable` is a hard
## error on exactly the value this check exists to detect.
func _program() -> CharacterCreationProgram:
	var live := _harness.live_screen()
	if live == null:
		return null
	var bound: Variant = live.get(&"_commit_requested")
	if not bound is Callable:
		return null
	var commit_callable := bound as Callable
	if not commit_callable.is_valid():
		return null
	return commit_callable.get_object() as CharacterCreationProgram


func _first_origin() -> StringName:
	var ids := FateCatalog.instance().destinies_in_group(&"origin")
	if ids.is_empty():
		return &""
	return StringName(ids[0])


## Commit a real arrival through the real composition root and hand back the body the root
## then plays. The chain under test is exactly the shipped one:
## `commit` -> `_stand_in_the_world` -> `WorldStage.stand_in_the_tree` -> `mount`.
func _committed() -> PlayerAdapter:
	var program := _program()
	assert_ne(program, null, "the boot left a live arrival screen holding the commit")
	if program == null:
		return null
	var committed := program.commit(_first_origin())
	assert_eq(
		bool(committed.get("ok", false)),
		true,
		"the arrival committed: %s" % committed.get("reason", "")
	)
	if not bool(committed.get("ok", false)):
		return null
	var hero := committed.get("actor", null) as Actor
	if hero != null:
		_born.append(hero)
	return WorldStage.player()


# --- the contract -------------------------------------------------------------


func test_a_committed_body_is_a_node_in_a_tree() -> void:
	var adapter := _committed()
	assert_ne(adapter, null, "a committed arrival holds a body")
	if adapter == null:
		return
	assert_ne(adapter.get_parent(), null, "the body is parented")
	assert_eq(adapter.is_inside_tree(), true, "and that parent is in the live tree")
	assert_ne(adapter.get_parent() as WorldEntry, null, "parented under a WorldEntry")


func test_a_committed_body_carries_the_playfields_interactables() -> void:
	var adapter := _committed()
	assert_ne(adapter, null, "a committed arrival holds a body")
	if adapter == null:
		return
	# `_register_nodes` is the one call that reads `WorldEntry.resource_nodes()`, so a
	# non-zero count here is a DIRECT reading of whether `_world_entry()` resolved — and
	# it is the exact precondition `interact()` needs, since `_nearest_interactable` walks
	# this very list.
	assert_eq(
		int(adapter.summary()["interactable_count"]) > 0, true, "the adapter holds interactables"
	)
	var stage := WorldStage.instance()
	assert_ne(stage, null, "a stage is mounted")
	if stage != null:
		assert_eq(int(stage.summary()["node_count"]) > 0, true, "the stage registered scene nodes")


func test_a_press_on_a_real_target_is_answered() -> void:
	var adapter := _committed()
	assert_ne(adapter, null, "a committed arrival holds a body")
	if adapter == null:
		return
	assert_ne(adapter.get_parent(), null, "precondition: the body is in a tree")
	var stage := WorldStage.instance()
	assert_ne(stage, null, "a stage is mounted")
	if stage == null:
		return
	# `quest_board` is the one press the shipped handler maps to a board
	# (`_QUEST_BOARD_ALIASES`), and it is authored into `mortal_plains.tres` so the row
	# exists. Whatever the answer, it is NOT `no_handler`: that refusal means no seam was
	# installed at all, which is a different defect from this one.
	var answer := stage.interact("quest_board")
	assert_ne(
		String(answer.get("reason", "")), "no_handler", "the press reached an installed handler"
	)
	assert_eq(
		String(answer.get("target", "")), "quest_board", "and the answer names what was pressed"
	)


# --- the RED half -------------------------------------------------------------
##
## The same arrival, mounted WITHOUT the parent. Every assertion above is evaluated again
## against a body no one ever `add_child`ed, which is the state the audit found. Kept as a
## live case rather than a comment because the defect it guards is a REGRESSION to a shape
## that reads green: `mount` answers `ok` either way.


func test_without_the_parent_the_same_arrival_is_inert() -> void:
	var program := _program()
	assert_ne(program, null, "a live arrival screen is bound")
	if program == null:
		return
	var actor := _app.actor()
	if actor == null:
		return
	# Stand the stage up by hand, skipping `stand_in_the_tree` — the pre-fix chain.
	var stage := WorldStage.new()
	var body := PlayerAdapter.new(actor)
	var answer := stage.mount(body, &"mortal_plains")
	assert_eq(
		bool(answer.get("ok", false)), true, "and the mount STILL reports ok — that is the trap"
	)
	assert_eq(body.get_parent(), null, "the body is still parentless")
	assert_eq(
		int(body.summary()["interactable_count"]), 0, "so it holds nothing a press could reach"
	)
	body.free()
