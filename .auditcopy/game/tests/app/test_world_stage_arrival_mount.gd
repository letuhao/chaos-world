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
	# **Opened here, not left to boot.** This suite runs beside others that mount and
	# release the root, and `mount_new()` frees whatever they left — so whether boot lands
	# on the arrival route depends on what ran before it. `open_creation` is the shipped
	# verb, so the path under test is still the real one; only the ROUTE it arrives on is
	# stated here rather than inherited from an earlier suite's leftovers.
	#
	# ## And a REFUSAL is a named outcome, not a shrug
	#
	# **This call was made and its answer thrown away, so a boot that refused to offer
	# arrival left every case below failing on a symptom instead of on the cause.** The
	# app's boot path (item_workbench_app.gd:353) hands the program the hero it built
	# (`_creation.adopt(_actor)`), so `has_hero()` is true on EVERY boot — including a
	# brand-new game, because :292-293 builds a fresh hero when there is no save to
	# restore. `open()` therefore refused with `already_has_hero`, the boot gate at :363
	# never called `open_creation()`, and the arrival screen was never on the stack at
	# all: `live_screen()` was the workbench, `_program()` read an unbound
	# `_commit_requested` off it, and no hero was ever committed.
	#
	# The refusal is now READ rather than discarded, so the failure is reported as the
	# reason the app gave when there is one — the arrival screen is a feature the running
	# game must offer a new player, not a precondition this suite may assume.
	# Nothing here forces the route: `open_creation()` is the app's own verb and the
	# answer it gives is the app's own claim about itself.
	var opened := _app.open_creation()
	if not bool(opened.get("ok", false)):
		push_error(
			(
				(
					"the composition root did not offer the arrival screen: %s — a new player is"
					+ " sent straight to the workbench, so there is no arrival to commit"
				)
				% String(opened.get("reason", "no_reason"))
			)
		)


## The body the root plays after a real arrival, committing through the live screen's own
## bound callable. Returns null when this boot already holds a hero — in which case the
## arrival already happened at boot and there is nothing left to commit.
func _committed() -> PlayerAdapter:
	var program := _program()
	if program == null:
		# The boot already created the hero; the arrival it performed IS the mount.
		var existing := WorldStage.player()
		if existing != null:
			return existing
		assert_ne(null, "no live arrival screen to commit through", "the boot reached creation")
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


# --- the contract -------------------------------------------------------------


func test_a_committed_body_is_a_node_in_a_tree() -> void:
	var adapter := _committed()
	assert_ne(adapter, null, "a committed arrival holds a body")
	if adapter == null:
		return
	assert_ne(adapter.get_parent(), null, "the body is parented")
	# ## `is_inside_tree()` is UNREACHABLE under this runner, so it is not asserted here
	#
	# **Measured, not assumed:** `Engine.get_main_loop().root.is_inside_tree()` is `false`
	# for the process's own root window while `run_tests.gd` drives the suites from
	# `SceneTree._initialize()` — and `root.get_tree()` answers `Parameter "data.tree" is
	# null`, because the Window's cached tree pointer is not assigned until the engine
	# finishes initialising. `is_inside_tree()` walks up to that pointer, so **no node
	# parented under `root` can report true here**, including the harness's own mounted app.
	# Asserting it would assert something about the ENGINE, not about the arrival, and the
	# only way to make it pass would be to move the body somewhere `root` is not — i.e. to
	# delete the claim the audit made.
	#
	# What the audit actually found is a body with NO PLAYFIELD behind it, and that is
	# asserted directly below: a `WorldEntry` parent, reached through the tree from the
	# harness's own root, with its authored markers bound. A body parented under a
	# `WorldEntry` that is itself a child of the live `root` window is the production claim.
	var entry := adapter.get_parent() as WorldEntry
	assert_ne(entry, null, "parented under a WorldEntry")
	if entry == null:
		return
	assert_eq(
		entry.get_parent(), _harness.root, "the playfield itself is parented under the live root"
	)
	assert_ne(entry.spawn_position(), Vector2.ZERO, "and its authored spawn marker is bound")


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
	# exists. The claim being proved here is NOT "a handler exists" — `reason !=
	# "no_handler"` stayed green while the handler answered `quest_not_offered` to every
	# hero who had not already finished `the_station_you_held`, which is the defect
	# itself. **A press that reaches a handler and is told "nothing here" is the bug,
	# not the fix**, so the assertion below asks for a REAL offer: `ok`, and at least
	# one row naming a quest the module actually offered this hero.
	var answer := stage.interact("quest_board")
	assert_eq(
		bool(answer.get("ok", false)),
		true,
		(
			("the press reached a handler and was told nothing: %s. A fresh hero must be ") % answer
			+ "handed the chain's ungated root, or the board is inert again."
		)
	)
	var rows := answer.get("offered", []) as Array
	assert_eq(rows.is_empty(), false, "and the offer carries at least one row: %s" % answer)
	var board_id := String(answer.get("quest_id", ""))
	assert_ne(board_id, "", "and names which quest it is handing over")
	assert_eq(
		rows[0].get("quest_id", ""),
		board_id,
		"and the named quest and the first row cannot disagree"
	)
	# The door out of the offer, so the offer can become a commitment: a press changes
	# what a player is OFFERED and never accepts for them (ADR 0065's once-guard), which
	# is only honest while the answer says where the player's own button is.
	assert_eq(
		String(answer.get("accept_via", "")),
		QuestProgram.QUEST_ROUTE,
		"so the press hands over the journal route, which is where accept lives"
	)
	assert_ne(
		String(answer.get("accept_hint", "")), "", "and says in words what the player must do next"
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
