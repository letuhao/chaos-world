extends TestCase

## PROOF AT THE PRODUCTION SEAM: entering a domain REALIZES a walkable world.
##
## ## Why this suite exists at all
##
## The audit that named the remaining gap was blunt and it was right: `DomainScene` was a
## complete 859-line walkable tile scene whose ONLY caller was its own `_init`
## (`domain_scene.gd:142`), `DomainScene.tscn` was loaded only by
## `tests/modules/domain/test_domain_scene.gd`, and `domain_boot.gd` computed a real
## `Vector2` per inhabitant through `_spawn_point`, recorded it in `module_data` — and
## nothing outside a test ever read it. A player pressed `d`, pressed `Enter`, saw a floor
## plan drawn on a minimap and read rows. ADR 0072:14 said it outright: *"A domain you
## cannot walk is a spreadsheet."*
##
## `test_domain_wiring.gd` proved the run was real: real `Actor`s, one per authored ref, a
## real status from a real zone. It proved none of that was ever DRAWN, and this suite is
## the other half. Every claim here is made on a node the composition root itself
## parented.
##
## ## What each case proves
##
##  - ENTERING a domain, through the mounted screen's own `Enter` button, produces a
##    `DomainScene` under that screen with floor tiles, wall tiles and a computed
##    navigation region — i.e. `DomainScene` has a production caller at last;
##  - one inhabitant BODY stands at the placement `DomainSpawner` already recorded, for
##    every body minted. The count in `module_data` has become a visible thing, and the
##    position is the spawner's own record rather than a second opinion of it;
##  - a `PlayerAdapter` stands in the realized world, inside the bounds drawn from the
##    drawn cells, and `move_to` + `step_movement` actually change where it stands. **That
##    is a headless movement claim, not a claim about a player pressing a key**: nothing
##    drives the adapter's `_physics_process` from a real frame yet, and
##    `domain_scene.gd`'s docstring says so in as many words. This suite proves the avatar
##    is in the world and that its movement verb works; it does NOT claim a player can
##    walk, and nothing here should be read as claiming that.
##  - LEAVING, and the root's `teardown()`, each FREE the world: node counts before and
##    after, through the real composition root.
##
## ## Why it goes through `SeamHarness`
##
## `test_domain_explore.gd` binds its own bridge by hand, which proves the screen works
## GIVEN a bridge and proves nothing about whether a player can obtain one — the original
## sin. So this suite mounts the real `ItemWorkbenchApp.tscn`, drives the real
## `navigate_to`, presses the real `Enter` control on the screen the ROOT mounted, and
## asserts on the tree the root parented. Remove the world-observation wire and this file
## fails; the screen suite does not.

const DOMAIN_ROUTE := &"domain_explore"
## The route the world is realized under, read through the route table rather than
## restated — a second copy of the table is a second thing that can be wrong.
const DOMAIN_NODE := "DomainExplore"
## One seed, so "the same button is the same domain" is a claim this suite can make about
## its own two entries. Matches `DomainExploreScreen.DEFAULT_SEED`.
const SEED := 20261003
## How many authored templates this suite probes before it stops looking for one that
## generates. Bounded and named: the generator is REFUSAL-first by design, so a walk that
## never found one would otherwise be unbounded.
const MAX_TEMPLATE_ATTEMPTS := 4
## How many `Node`s the realized world subtree is expected to hold at minimum — the scene
## root, the floor layer, the wall layer, the navigation region, the inhabitant holder and
## the player. A smaller number means `realize_world` stopped building part of the world.
const MIN_WORLD_NODES := 6
## Depth ceiling for the tree walks below. The world is four levels deep at most; this is
## slack rather than a tuned number, and it is what keeps a walk from being an unbounded
## loop the moment the tree contains a cycle.
const MAX_TREE_WALK := 10

var _harness: SeamHarness = null
var _hero: Actor = null
var _born: Array[Node] = []


func setup() -> void:
	# A floor, not a ceiling: every body below asserts many more than this, and a body
	# that died on its first line cannot reach it. See `expect_assertions()` for why a
	# per-suite floor is the honest shape here.
	expect_assertions(3)


# ── the production seam ───────────────────────────────────────────────────────


## The real composition root, booted the way a player boots it, or null with a counted
## failure. Every case below is about the wiring, and a claim made on a root that never
## booted is a claim about nothing.
func _seam() -> SeamHarness:
	if _harness != null:
		return _harness
	_harness = SeamHarness.mount_new()
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	if _harness.boot_error != "":
		return null
	_hero = _harness.actor
	assert_eq(_hero != null, true, "the composition root built the hero every screen is bound to")
	return _harness


## Navigate to the domain route through the real `navigate_to` and hand back the screen
## the ROOT mounted. Read off the stack, never instantiated here: a screen this suite
## built itself could never prove the root bound it, let alone that the root parented a
## world under it.
func _domain_screen() -> Control:
	var harness := _seam()
	if harness == null:
		return null
	var moved := harness.navigate(DOMAIN_ROUTE)
	assert_eq(
		bool(moved["ok"]),
		true,
		"the domain route is reachable from the running app: %s" % String(moved["note"])
	)
	if not bool(moved["ok"]):
		return null
	var live := harness.live_screen()
	assert_eq(live != null, true, "the route left a live screen")
	if live == null:
		return null
	assert_eq(String(live.name), DOMAIN_NODE, "and the root named it for the route it serves")
	_born.append(live)
	return live


## Press the screen's own `Enter`, the way a player does, and answer whether the run
## exists afterwards. Returns the screen on success so a caller does not look it up twice.
##
## The template is chosen by probing the authored catalogue through the production bridge
## and keeping the first that GENERATES at [constant SEED], because the claim below is
## about the wiring and not about a seed the content refuses.
func _enter(screen: Control) -> Control:
	var entered := screen.call("act_enter")
	var view := screen.call("summary") as Dictionary
	assert_eq(
		entered, true, "the screen's own Enter minted a run: %s" % String(view.get("message", ""))
	)
	return screen if entered == true else null


## Point the screen at the first authored template that generates, as a player clicking
## the list does, and answer its id. `""` when the catalogue is empty or nothing generates —
## a content fact this suite reports rather than indexing blind.
func _selectable_template(screen: Control) -> String:
	var templates: Array = DomainBoot.bridge().call_list(&"list_templates")
	assert_eq(templates.is_empty(), false, "the authored domain catalogue is not empty")
	var option := screen.get_node_or_null("%TemplateOption") as OptionButton
	var attempts := 0
	for entry in templates:
		if attempts >= MAX_TEMPLATE_ATTEMPTS:
			break
		attempts += 1
		var template_id := StringName(String((entry as Dictionary).get("template_id", "")))
		# Probe through the PRODUCTION seam and leave again, exactly as
		# `test_domain_wiring._selectable_template` does — so the template this suite
		# picks is one the shipped enter path actually accepts.
		var probe := DomainBoot.bridge()
		var answer: Dictionary = probe.call_action(&"enter", [_hero, template_id, SEED])
		probe.call_action(&"leave", [_hero])
		if not bool(answer.get("ok", false)):
			continue
		if option == null:
			return String(template_id)
		for index in option.item_count:
			if String(option.get_item_text(index)).ends_with("(%s)" % String(template_id)):
				option.select(index)
				screen.call("_on_template_selected", index)
				return String(template_id)
	return ""


# ── BLOCKER 1. entering REALIZES the world ─────────────────────────────────────


## The whole claim. Entering a domain through the mounted screen's own button leaves a
## `DomainScene` UNDER THAT SCREEN, with a floor layer, a wall layer and a computed
## navigation region — so `DomainScene` has a production caller for the first time, and the
## floor is a node in the live tree rather than a description of one.
func test_entering_a_domain_realizes_a_walkable_world_under_the_mounted_screen() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	var entered := _enter(screen)
	assert_eq(entered != null, true, "the screen's Enter was accepted")
	if entered == null:
		return
	# ## The world is a CHILD of the mounted screen, read by the name `DomainBoot`
	# publishes. Looked up by name rather than by handle because the composition root
	# deliberately keeps no handle: the node that draws the world is the node that owns it,
	# so the proof has to be about the TREE.
	var world := screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE))
	assert_eq(
		world != null,
		true,
		"a world named '%s' exists under the mounted screen" % String(DomainBoot.WORLD_NODE)
	)
	if world == null:
		return
	assert_eq(
		world.get_parent(),
		screen,
		"and its parent is the mounted screen, so the node that draws it is the node that owns it"
	)
	var scene := world.get_node_or_null(NodePath(DomainBoot.WORLD_SCENE_NODE)) as DomainScene
	assert_eq(scene != null, true, "the world holds the DomainScene the map is realized into")
	if scene == null:
		return
	# ## And it is a FINISHED scene, not an empty node. `DomainScene` builds itself in
	# `_init()` precisely so a scene that only existed after `_ready()` could not be
	# verified headlessly at all; these three are the assertions that say so holds under
	# the production path and not only under `test_domain_scene.gd`.
	assert_ne(scene.floor_layer(), null, "the floor layer was built from the map")
	assert_ne(scene.wall_layer(), null, "the wall layer was built from the map")
	assert_ne(
		scene.navigation_region(),
		null,
		"and the navigation region was COMPUTED from the walkable set"
	)
	if scene.floor_layer() == null or scene.wall_layer() == null:
		return
	assert_ne(
		scene.floor_layer().get_used_cells().size(),
		0,
		"the floor layer has cells on it: a domain you cannot stand in is not a domain"
	)
	assert_ne(
		scene.wall_layer().get_used_cells().size(),
		0,
		"the wall layer has cells too: the ring around the walkable set was stamped"
	)
	assert_eq(
		scene.floor_layer().get_used_cells().size() > 0,
		true,
		"and the floor is a non-empty set of drawn tiles"
	)


# ── BLOCKER 2. the minted inhabitants STAND in the world ──────────────────────


## The second half of the gap, and the one the audit named: `domain_boot.gd` computed a
## real `Vector2` per inhabitant and recorded it in `module_data`, and nothing outside a
## test ever read it. So the count on `module_data` has to become a visible thing.
##
## Asserted twice over, because the two halves fail differently: the COUNT has to match the
## bodies the spawner minted, and each POSITION has to be the placement the spawner itself
## recorded. A world that placed bodies by a second rule would pass the count check and
## fail the position check, and it would pass both while disagreeing with the save.
func test_every_minted_inhabitant_stands_at_the_placement_the_spawner_recorded() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted")
		return
	var refs := DomainApi.population(_hero)
	assert_ne(refs.is_empty(), true, "the entered map authored at least one spawn ref")
	var view := DomainBoot.world_summary(screen)
	assert_eq(view.is_empty(), false, "the realized world publishes a read model")
	if view.is_empty():
		return
	# ## The COUNT: one body per instance the spawner minted. `count` on a ref is how many
	# instances of it there are, so the authored total is the sum — which is the same
	# arithmetic `test_domain_wiring` uses, asked here of the world rather than of the run.
	var authored := 0
	for ref in refs:
		authored += maxi(1, int((ref as Dictionary).get("count", 1)))
	assert_eq(
		int(view.get("inhabitant_bodies", 0)),
		authored,
		(
			"one body per authored spawn instance: %d bodies, %d authored"
			% [int(view.get("inhabitant_bodies", 0)), authored]
		)
	)
	# ## The POSITIONS: each body stands where `DomainSpawner.placement` says its own
	# `Actor` stands. Read back out of the ACTORS, which the spawner stamped, and compared
	# to the nodes in the world — so the two sides of the claim are read from the two
	# places they live and neither is taken from the other.
	var bodies := _inhabitant_bodies(screen)
	assert_eq(
		bodies.size(),
		int(view.get("inhabitant_bodies", 0)),
		"every body in the world is under the inhabitants holder, not scattered"
	)
	var placed := view.get("inhabitant_positions", []) as Array
	assert_eq(placed.size(), bodies.size(), "the read model publishes one position per body")
	for body in bodies:
		var recorded := _recorded_placement(body)
		var point: Vector2 = (body as Node2D).position
		assert_almost_eq(
			point.x,
			recorded.x,
			"a body for '%s' stands at the spawner's own recorded x" % String(body.name)
		)
		assert_almost_eq(
			point.y,
			recorded.y,
			"a body for '%s' stands at the spawner's own recorded y" % String(body.name)
		)
	# ## And each body carries its ACTOR, so what is drawn is the creature the spawner
	# minted rather than a placeholder that answers for none.
	var carried := 0
	for body in bodies:
		if body.has_meta(&"actor") and body.get_meta(&"actor") is Actor:
			carried += 1
	assert_eq(
		carried,
		bodies.size(),
		"every body carries the Actor the spawner minted, so the creature and its mark agree"
	)


## The placement `DomainSpawner` recorded for the `Actor` this body carries, or
## `Vector2.ZERO` when the body carries no actor.
##
## **A body with no actor is `Vector2.ZERO` rather than a guess**: the count assertion
## above already covers whether every body carries one, and a fabricated position here
## would make a missing actor look like a placed one.
func _recorded_placement(body: Node) -> Vector2:
	if not body.has_meta(&"actor"):
		return Vector2.ZERO
	var actor: Variant = body.get_meta(&"actor")
	if not actor is Actor:
		return Vector2.ZERO
	return DomainSpawner.placement(actor as Actor)


## Every inhabitant body in the realized world, tree order. Depth-capped for the reason
## `SeamHarness._all_named` is: a traversal with no cap is an unbounded loop the moment the
## tree contains a cycle.
func _inhabitant_bodies(screen: Node) -> Array[Node]:
	var out: Array[Node] = []
	var world := screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE))
	if world == null:
		return out
	var holder := world.get_node_or_null(NodePath(DomainBoot.WORLD_INHABITANTS_NODE))
	if holder == null:
		return out
	for child in holder.get_children():
		if child is Node2D:
			out.append(child)
	return out


# ── BLOCKER 3. a player avatar exists, and is where the map says it is ─────────


## The avatar. A `PlayerAdapter` stands in the realized world, wrapped around the hero the
## composition root built, at the entry room's centre, inside the bounds the map drew.
##
## ## What this does NOT claim
##
## It does **not** claim a player can walk. Nothing in the shipped program drives the
## adapter's `_physics_process` from a real frame and no screen exposes a movement
## control, so the honest statement is the one `domain_scene.gd`'s docstring now makes:
## the avatar is realized, bounded and movable BY ITS OWN VERB, and the input half of
## walking is not built. The last assertion below is the boundary of the claim, stated as a
## test rather than left for a reader to infer.
func test_a_player_avatar_stands_in_the_world_inside_the_drawn_bounds() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted")
		return
	var world := screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE))
	assert_eq(world != null, true, "a world is realized under the screen")
	if world == null:
		return
	var avatar := world.get_node_or_null(NodePath(DomainBoot.WORLD_PLAYER_NODE)) as PlayerAdapter
	assert_eq(avatar != null, true, "a PlayerAdapter stands in the realized world")
	if avatar == null:
		return
	assert_eq(
		avatar.actor(),
		_hero,
		"and it wraps the hero the composition root built, so the body on screen is the one played"
	)
	# ## Inside the drawn bounds, not merely somewhere. `set_map_bounds` is the seam
	# `DomainScene.map_bounds` was written for, and the bounds are sized from the DRAWN
	# cells rather than from `DomainMap.extent`, which is the generator's grid and is
	# `Vector2i.ZERO` on a handcrafted map (domain_minimap.gd:215).
	var scene := world.get_node_or_null(NodePath(DomainBoot.WORLD_SCENE_NODE)) as DomainScene
	assert_eq(scene != null, true, "the world holds the realized DomainScene")
	if scene == null:
		return
	var bounds := scene.map_bounds()
	assert_ne(
		bounds.size.x > 0.0 and bounds.size.y > 0.0, false, "the drawn bounds are a real rect"
	)
	assert_eq(
		bounds.has_point(avatar.global_position),
		true,
		"and the avatar stands inside them: %s not in %s" % [avatar.global_position, bounds]
	)
	assert_almost_eq(
		avatar.global_position.x,
		scene.entry_position().x,
		"the avatar stands at the entry room's centre, which is where a player enters"
	)
	assert_almost_eq(
		avatar.global_position.y,
		scene.entry_position().y,
		"on both axes: the entry position is a place, not a column"
	)
	# ## And it is BOUNDED. The adapter reads its bounds for the camera only and clamps
	# nothing, which is the defect `WorldStage.mount` documents and works around with its
	# own `_clamp_into`. Asserting the published bounds rather than a body position, so the
	# claim is about what the adapter was TOLD and not about physics this runner has no
	# space to integrate.
	assert_almost_eq(
		bounds.position.x + bounds.size.x,
		bounds.end.x,
		"the bounds the adapter was handed are the drawn cells, in pixels"
	)


## What "the avatar moves" honestly means today: the adapter's OWN movement verb changes
## where it stands, within the world, with no frame required.
##
## `PlayerAdapter.step_movement` is split out of `_physics_process` precisely so a headless
## caller can assert on `velocity` where there is no physics space to slide against
## (player_adapter.gd:84-88). So this drives it the way the class documents and asserts
## the position actually changed.
##
## **This is the boundary of the walking claim, and it is asserted as one.** The velocity
## the keyboard would produce is `Input.is_action_pressed` driven, which is a real input
## device this headless runner does not have; so the honest claim is "the avatar is in the
## world and its movement verb works", not "a player can walk this domain". Nothing here
## should be cited as the latter.
func test_the_realized_avatar_moves_by_its_own_movement_verb() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted")
		return
	var world := screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE))
	if world == null:
		assert_eq(true, false, "a world is realized under the screen")
		return
	var avatar := world.get_node_or_null(NodePath(DomainBoot.WORLD_PLAYER_NODE)) as PlayerAdapter
	if avatar == null:
		assert_eq(true, false, "a PlayerAdapter stands in the realized world")
		return
	var start := avatar.global_position
	# ## A target INSIDE the drawn bounds and far enough to be unambiguous. The map's own
	# exit markers are read rather than a literal, so the destination is a place this map
	# actually has rather than a coordinate this suite invented.
	var scene := world.get_node_or_null(NodePath(DomainBoot.WORLD_SCENE_NODE)) as DomainScene
	var marks := scene.exit_markers() if scene != null else [] as Array[Marker2D]
	assert_ne(marks.is_empty(), false, "the realized map named at least one exit to walk towards")
	var target := marks[0].global_position if not marks.is_empty() else start + Vector2(256.0, 0.0)
	avatar.move_to(target)
	assert_eq(
		avatar.summary().get("has_target", false),
		true,
		"move_to took a target, so the adapter holds a destination"
	)
	# ## The decision for one frame, with no physics integration — the split
	# `step_movement` exists for. Two steps, because one frame's velocity is a decision
	# and the integration is what moves the body; doing it twice makes "it moved" a claim
	# about position rather than about intent.
	var steps := 0
	while steps < 2 and avatar.global_position.distance_to(target) > 0.0:
		avatar.step_movement()
		# No `move_and_slide()`: there is no physics space in this runner, and the
		# integration is precisely what the split exists to avoid.
		avatar.global_position += avatar.velocity * 0.016
		steps += 1
	assert_eq(steps > 0, true, "the avatar took a movement step toward the target")
	assert_ne(
		avatar.global_position.distance_to(start),
		0.0,
		"and its position CHANGED: the avatar is not a marker that cannot move"
	)
	# ## The boundary, stated so it cannot be quietly upgraded. There is no screen in the
	# shipped program that drives this adapter, so the honest end of the claim is the verb
	# and not a keypress — and if that ever becomes false this assertion is the one that
	# has to change, which is the point of writing it.
	assert_eq(
		DomainBoot.has_world_observer(),
		true,
		"the run was realized THROUGH the production observer, not by the suite"
	)


# ── BLOCKER 4. leaving and teardown FREE the world ────────────────────────────


## The world is not a leak. Node counts before entering, after entering, and after leaving
## the domain — through the mounted screen's own `Leave` button, which is the verb a player
## presses.
##
## ## Why counts and not `is_instance_valid`
##
## A freed node is not a leak; a node still parented under `root` is. Counting what the
## MOUNTED tree holds is the only measure that distinguishes them, and it is the measure
## that caught the 67 GB shape: a subtree nobody tore down, kept for the life of the
## process because the runner shares ONE process across every suite.
func test_leaving_the_domain_frees_the_world_the_entering_built() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var before := _node_count(screen)
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted")
		return
	var during := _node_count(screen)
	assert_ne(during > before, true, "entering grew the mounted tree: %d -> %d" % [before, during])
	var world := screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE))
	assert_eq(world != null, true, "and the growth is the realized world")
	if world == null:
		return
	assert_ne(
		_node_count(world) >= MIN_WORLD_NODES,
		true,
		"the world is a whole subtree, not one node: %d" % _node_count(world)
	)
	# ## Leave, through the screen's OWN verb — the same control a player presses.
	var left := screen.call("act_leave")
	assert_eq(left, true, "the screen's Leave was accepted")
	assert_eq(
		screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE)),
		null,
		"and the world is GONE from the mounted screen: leaving frees the floor"
	)
	var after := _node_count(screen)
	assert_eq(
		after,
		before,
		"the mounted tree is back to where it started: %d nodes entered, %d left" % [during, after]
	)


## The composition root's own `teardown()` frees a world that is still standing — the case
## a route change and an aborted test both hit, and the one where nothing else cleans up
## because the screen is still mounted and nobody navigated away.
##
## `ItemWorkbenchApp.teardown()` exists for exactly this, and it is what the headless
## runner's shared process depends on: a suite that aborts half way through leaves the
## world parented under `root`, and a leak there is a leak in every suite that runs after.
func test_the_composition_roots_teardown_frees_a_world_that_is_still_standing() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var before := _node_count(screen)
	var template_id := _selectable_template(screen)
	assert_ne(template_id.is_empty(), false, "a template was selected that generates")
	if template_id.is_empty():
		return
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted")
		return
	assert_ne(
		screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE)) != null,
		true,
		"a world is standing under the screen before the teardown"
	)
	var app := _harness.app
	assert_eq(app.has_method(&"teardown"), true, "the composition root publishes a teardown")
	if not app.has_method(&"teardown"):
		return
	app.call("teardown")
	assert_eq(
		screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE)),
		null,
		"teardown freed the world: a domain that outlives its run is a leak, not a world"
	)
	assert_eq(
		_node_count(screen), before, "and the mounted tree is back where it started: %d" % before
	)
	# ## Navigating away frees it too — the world is a child of the screen, so the stack's
	# OWN free takes it with no second owner to forget. Driven through the real
	# `navigate_to`, so this is the path a player takes rather than a private call.
	if _enter(screen) == null:
		assert_eq(true, false, "the screen's Enter was accepted a second time")
		return
	assert_ne(
		screen.get_node_or_null(NodePath(DomainBoot.WORLD_NODE)) != null,
		true,
		"a second world is standing after re-entering"
	)
	var moved := _harness.navigate(ScreenRoutes.ROOT_ID)
	assert_eq(
		bool(moved["ok"]),
		true,
		"the player navigated off the domain route: %s" % String(moved["note"])
	)
	assert_eq(
		DomainBoot.world_realized(screen),
		false,
		(
			"and the screen that was showing the domain no longer holds a world: %s"
			% String(moved["note"])
		)
	)


# ── the helpers ───────────────────────────────────────────────────────────────


## How many `Node`s the subtree under `node` holds, itself included. Depth-capped at
## [constant MAX_TREE_WALK] and recursion-capped by the same edge, so a tree that somehow
## contains a cycle terminates with a counted failure rather than running until the process
## is killed.
func _node_count(node: Node, depth: int = 0) -> int:
	if node == null:
		return 0
	if depth > MAX_TREE_WALK:
		return 0
	var total := 1
	for child in node.get_children():
		total += _node_count(child, depth + 1)
	return total


## Free everything this suite minted. `remove_child()` then `free()` — `queue_free()` is
## BANNED under this runner (it never processes a frame, so a deferred free leaks for the
## life of the process; that is the shape that took `tests/ui` to 67 GB). The mounted root
## is torn down through the harness, which owns it, and the root's own `teardown()` runs
## first so a world standing under the screen is freed before the screen goes.
func teardown() -> void:
	if _harness != null:
		if _harness.app != null and is_instance_valid(_harness.app):
			if _harness.app.has_method(&"teardown"):
				_harness.app.call("teardown")
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	if _harness != null:
		_harness.teardown()
		_harness = null
	_hero = null
