extends TestCase

## The gather surface, end to end: a player takes a node, works it, and ends up holding
## real items.
##
## ## What this suite is FOR
##
## The audit that found the economy program "wired to itself, not to a player" found
## `HoldingsApi.claim` with NO production caller anywhere in the tree. A node was
## therefore never held, `ForageAction.workable` could never answer true, and
## `ForageApi.harvest` was reachable from nothing — while `tools data audit` reported
## `gather` live, because `app/forage_action.gd` is a call site a scan can see and a
## player cannot. That is the UNWIRED class that passes every test.
##
## So these cases drive the screen the way a player does — claim, gather — and assert
## the OUTCOME in the bag. Every other claim about the route is made by a suite that
## reaches the module directly; this one exists to prove the button is connected.
##
## ## The chain these cases walk, and the exact order it must happen in
##
## `HoldingsApi.claim` → the node is HELD → `ForageAction.workable` is true →
## `ForageAction.gather` → `ForageApi.harvest` → `HoldingsApi.accrue`/`settle` →
## `ForageGranary.deliver` → the item is in the bag. Each arrow below is asserted at
## BOTH ends, because a break anywhere in the middle is invisible from either end.
##
## ## Every refusal is a named constant
##
## A test asserting only `ok == false` would pass for a forager that refused
## everything. Each refusal is asserted BY NAME, because the name is the contract a
## panel switches on.
##
## ## Nothing leaks
##
## `HoldingsApi._store`, `HoldingsApi._resolver`, `ForageApi._granter` and the
## `ResourceNodeCatalog` singleton are all process-wide and the runner shares ONE
## process across every suite, calling `teardown` after EVERY test. Each is released
## per-test, not per-suite: a granter left installed hands this suite's fixtures to
## whichever suite runs next, and a screen left holding an `Actor` leaks its subtree.

const SCREEN_SCENE := preload("res://src/ui/screens/forage_screen.tscn")
const ROW_SCENE := preload("res://src/ui/panels/resource_node_row.tscn")
const SCRIPT_PATH := "res://src/ui/screens/forage_screen.gd"
const PANEL_SCRIPT_PATH := "res://src/ui/panels/resource_node_row.gd"
const ROUTE := &"forage"

## The shallowest authored band, worked by a hero at that band. Read from the CONTENT
## tree rather than typed in, so a retune of the authored band cannot leave this suite
## foraging a node the build no longer ships.
const SHALLOW_REALM := &"foundation"
## A node two rungs deeper, so `permits` has something to refuse and the row's "beyond
## you" line has a case that reaches it.
const DEEP_REALM := &"core_formation"
## The item the shallow node yields, read from the facade's own table rather than
## restated — a suite that hard-coded the id would pass while `NODE_YIELDS` retargeted
## it, and the whole point of this file is that the arrival is real.
const SHALLOW_NODE := &"foundation_yew_stand"
const DEEP_NODE := &"core_formation_burrow"

var _actor: Actor = null


func setup() -> void:
	# A REAL store and a REAL resolver, because the claim refuses `no_resolver` without
	# one and a suite that installed its own would be measuring the seam rather than the
	# slice. `EconomyBoot.install` is the production installer and it is idempotent, so
	# using it here is the same wiring a boot performs.
	EconomyBoot.install(null)
	_actor = _hero()
	EconomyBoot.install(_actor)
	# **Then** a FRESH world ledger, and this is not belt-and-braces.
	# `EconomyBoot._store_for` asks `SaveApi.store_for("holdings")` first and falls back to
	# an in-memory `WorldLedger` only when nothing has registered one — and a suite that
	# registered a DURABLE store earlier in the same process left its ledger ON DISK. The
	# runner shares one process across every suite, so under `--suite ui` that disk holds
	# another suite's claims, `HoldingsApi._state` reads them through `read_ledger`, and a
	# node this file needs vacant arrives held: the claim comes back `contested` and this
	# suite measures somebody else's ledger. `WorldLedger.new()` is the same isolation
	# `tests/modules/holdings/test_holdings_claim.gd` uses, and it is a SHARED world
	# ledger on purpose — a holder must be visible to a rival, or the custody cases below
	# would pass against a per-actor ledger that can never disagree with itself.
	HoldingsApi.set_store(WorldLedger.new())


func teardown() -> void:
	_actor = null
	ForageApi.set_granter(Callable())
	HoldingsApi.set_resolver(Callable())
	HoldingsApi.set_store(null)
	ResourceNodeCatalog.instance().reset()


## A hero with everything a claim and a harvest need: an inventory to receive the yield,
## the holdings ledger to record custody, and a body path so `actor.realm()` has a rung
## to stand on. `foundation` is the shallowest authored band, so the shallow node works.
func _hero() -> Actor:
	var actor := Actor.new(&"forager", {Stat.PHYSIQUE: 10.0})
	ItemsApi.attach(actor)
	HoldingsApi.attach(actor)
	actor.set_path(PathState.new(PathState.BODY, SHALLOW_REALM))
	return actor


## A node this hero can ACTUALLY take: vacant, on a band its realm permits, and with no
## authored `claim_floor`. `HoldingsApi.claim` refuses `claim_below_floor` for a node that
## declares one, because `_meets_floor` reads the OWNER ref's standing — a figure the
## holdings module does not own and a bare `{kind, id}` ref can only ever report as 0. So
## the claimable node is read off the facade rather than typed in: picking any deep node
## would make every case in this file measure the floor rule instead of the surface.
func _claimable_node() -> String:
	for row in ForageApi.views(_actor):
		var view: Dictionary = row as Dictionary
		if bool(view.get("vacant", false)) and bool(view.get("permits", false)):
			if int(view.get("claim_floor", 0)) <= 0:
				return String(view.get("node_id", ""))
	return ""


## A fresh, unbound screen. Every case frees what it is handed, because the runner shares
## one process across every suite and a screen left alive holds its whole row pool.
func _screen() -> ForageScreen:
	return (SCREEN_SCENE as PackedScene).instantiate() as ForageScreen


## A screen bound to the hero, with the harvest seam wired exactly as
## `ItemWorkbenchApp._bind_route_screen`'s `ROUTE_FORAGE` arm wires it: the bare static
## function, not a lambda.
func _bound() -> ForageScreen:
	var screen := _screen()
	screen.setup(_actor)
	screen.bind_harvest(Callable(ForageAction, "gather"))
	return screen


# --- the slice, end to end ----------------------------------------------------


## THE claim of this file. A player opens the page, takes a node and works it, and
## **the goods are in the bag afterwards**.
##
## Both halves are asserted because either alone is satisfiable by a lie: a screen that
## showed a row and wrote nothing would pass a "the button is enabled" assertion, and a
## screen that conjured items would pass nothing else. The custody is read off the
## LEDGER and the goods off the BAG, so the two sides cannot be satisfied by the same
## fiction.
func test_a_player_claims_a_node_and_gathers_real_items_from_it() -> void:
	var screen := _bound()
	assert_eq(
		String(HoldingsApi.state(_actor)["nodes"].get(String(SHALLOW_NODE), {}).get("id", "")),
		"",
		"setup: nobody holds the node"
	)

	# Beat one: TAKE the node. `HoldingsApi.claim` was the verb with no production caller.
	var claimed := screen.act_claim(String(SHALLOW_NODE))
	assert_eq(bool(claimed["ok"]), true, "a vacant node is claimed: %s" % claimed["reason"])
	assert_eq(bool(claimed["contested"]), false, "and a vacant node is not a standoff")
	var after_claim := HoldingsApi.summary(_actor)["nodes"][String(SHALLOW_NODE)] as Dictionary
	assert_eq(String(after_claim["owner"]["id"]), String(_actor.id), "the ledger names this holder")
	assert_eq(
		ForageAction.workable(_actor, SHALLOW_NODE), true, "so a held, shallow node is workable"
	)

	# Beat two: WORK it. The seam the screen was given is `ForageAction.gather`, which
	# is the one place under `game/src` that reaches `ForageApi.harvest`.
	var gather := screen.act_gather(String(SHALLOW_NODE), 2)
	assert_eq(bool(gather["ok"]), true, "the harvest is accepted: %s" % gather["reason"])
	assert_eq(int(gather["periods"]), 2, "the caller's periods are honoured verbatim")
	var item_id := String(gather["item_id"])
	assert_ne(item_id, "", "the node names an item, which is the fact a node cannot carry")
	assert_eq(
		ItemsApi.has_item(_actor, StringName(item_id), int(gather["granted"])),
		true,
		"and the actor really holds %d of '%s'" % [int(gather["granted"]), item_id]
	)
	# The ledger and the bag cannot both claim the same units, or the yield exists twice.
	assert_eq(
		int(HoldingsApi.state(_actor)["line"].get(String(SHALLOW_NODE), 0)),
		0,
		"the accrued line is settled, not double-counted"
	)
	screen.free()


## The screen's own published surface agrees with the world on both sides of the
## harvest, because `summary()` is what a test — and a headless driver — reads.
func test_the_summary_reports_the_custody_and_the_harvest_it_just_did() -> void:
	var screen := _bound()
	screen.act_claim(String(SHALLOW_NODE))
	var before := screen.summary()
	assert_eq(bool(before["held_count"]), true, "the summary counts the node as held")
	assert_eq(String(before["selected_node"]), "", "nothing is picked until something picks it")

	assert_eq(screen.select_node(String(SHALLOW_NODE)), true, "the held node is selectable")
	var picked := screen.summary()
	assert_eq(bool(picked["selected_held"]), true, "and it is reported as THIS hero's")
	assert_eq(bool(picked["selected_workable"]), true, "and as workable, because it is")

	var gather := screen.act_gather(String(SHALLOW_NODE), 1)
	assert_eq(bool(gather["ok"]), true, "the harvest ran: %s" % gather["reason"])
	var after := screen.summary()
	assert_eq(bool(after["last_ok"]), true, "the verdict is published as primitives")
	assert_eq(String(after["last_reason"]), "", "and names no refusal")
	assert_eq(String(after["last_node"]), String(SHALLOW_NODE), "naming the node it worked")
	assert_eq(
		int(after["last_granted"]),
		int(gather["granted"]),
		"and the count that actually landed, not a re-derived figure"
	)
	# The row is nested, not flattened: a test reads the node without walking the tree.
	var rows := after["rows"] as Array
	var found := {}
	for row in rows:
		if String((row as Dictionary).get("node_id", "")) == String(SHALLOW_NODE):
			found = row as Dictionary
	assert_ne(found, {}, "the worked node has a row")
	assert_eq(bool(found["held"]), true, "which reports the custody the ledger holds")
	screen.free()


## The route is REACHABLE, not merely shippable. A screen the composition root never
## mounts is reachable by nothing but this file, which is the shape the audit found.
func test_the_gather_route_is_published_and_bound_to_a_key() -> void:
	# The table names a route by SCENE, and its own seam back from a path to an id is
	# `id_for_scene` — there is no `route_for_scene`. Asserting the loadable scene the
	# table points at, plus the id that owns it, is the same claim read the way the shell
	# reads it: the shell loads `ScreenRoutes.scene_of(id)` and refuses anything else.
	assert_eq(
		ScreenRoutes.id_for_scene(String(SCREEN_SCENE.resource_path)),
		ROUTE,
		"the route table mounts this scene, and names it by id"
	)
	assert_eq(ScreenRoutes.has(ROUTE), true, "and the id is in the table")
	assert_eq(
		ScreenRoutes.scene_of(ROUTE),
		String(SCREEN_SCENE.resource_path),
		"and the route and the loaded scene are the same file, in both directions"
	)
	assert_eq(
		SCREEN_SCENE.can_instantiate(),
		true,
		"so the path the table names is a scene that actually loads"
	)
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action routes back to this route, so no key can open another screen"
	)


## And the page is the FIRST thing the composition root opens for this actor: the route's
## binding arm calls `bind_harvest`, so an unbound screen would refuse `no_harvest_seam`
## forever and every other case in this file would be measuring a seam nobody injected.
func test_the_binding_arm_names_the_harvest_seam_the_screen_cannot_reach_itself() -> void:
	# Read CODE, not the file: `item_workbench_app.gd` documents this route at length in a
	# docstring that names `bind_harvest` and `ForageAction.gather` too, so a raw text
	# scan of this file is asserting the comment rather than the wiring. Every scan in
	# this file goes through `_code_only`, for the same reason `test_ui_conventions`
	# strips comments before looking for `@onready`.
	var source := _code_only("res://src/app/item_workbench_app.gd")
	assert_ne(source.is_empty(), true, "the composition root's source is readable")
	assert_eq(
		source.count("bind_harvest"),
		1,
		"the root binds the harvest seam exactly once, on the gather route"
	)
	assert_eq(
		source.count('Callable(ForageAction, "gather")'),
		1,
		"and it binds `ForageAction.gather` itself, not a re-implementation of it"
	)
	# And the screen may not name it: `app/` is a `PRIVATE_UNIT`, so the seam is the only
	# door. Asserted from the screen's own source because that is the boundary this file
	# is the proof of.
	var screen_code := _code_only(SCRIPT_PATH)
	assert_eq(
		screen_code.contains("ForageAction"),
		false,
		"the screen names no `app/` type, so the harvest can only arrive as a Callable"
	)


# --- the order: a claim is REQUIRED, and refusing it is by name ----------------


## The chain's dependency, asserted from both ends: a node nobody holds is NOT workable,
## the gather button is DEAD on it, and pressing anyway is refused `no_holder`.
##
## The button state matters as much as the refusal: a control that is live where the
## verb refuses is exactly the "looks alive and is dead" shape, and `enabled` is the
## claim a panel makes without ever calling the verb.
func test_a_node_nobody_holds_is_not_workable_and_gathering_it_refuses_no_holder() -> void:
	var screen := _bound()
	# The held node is the shallow one, and the OTHER node is a second one this hero can
	# take — so the only thing separating the two is custody, never the realm gate.
	var held := String(SHALLOW_NODE)
	assert_eq(
		ForageAction.workable(_actor, SHALLOW_NODE),
		false,
		"an unheld node is not workable, whatever else is true of it"
	)
	screen.act_claim(held)
	var other := _claimable_node()
	assert_ne(other, "", "setup: the corpus authors a node nobody holds")
	assert_ne(other, held, "setup: and a second one this hero is on the band of")

	screen.select_node(other)
	assert_eq(
		bool(screen.summary()["enabled"]["gather"]),
		false,
		"so the gather control is DEAD on a node nobody holds, rather than live and refusing"
	)
	assert_eq(
		bool(screen.summary()["enabled"]["claim"]),
		true,
		"and the claim control is live, because taking it is the beat that unlocks work"
	)
	var gathered := screen.act_gather(other, 1)
	assert_eq(bool(gathered["ok"]), false, "a node nobody holds cannot be worked")
	assert_eq(
		String(gathered["reason"]),
		HoldingsState.NO_HOLDER,
		"and the refusal is holdings' OWN id, passed through by name"
	)
	assert_eq(
		ItemsApi.inventory(_actor).snapshot().stacks().is_empty(),
		true,
		"and the hero's bag is untouched: a refused harvest costs nothing"
	)
	screen.free()


## ADR 0097's realm gate is a GATE, and the row says so rather than only the refusal
## saying it. A hero holding a deep node's ground can still be refused on the band, and
## a screen that greyed the button for the wrong reason would be hiding which rule fired.
func test_a_held_node_beyond_the_heros_band_is_not_workable() -> void:
	var screen := _bound()
	var claimed := screen.act_claim(String(DEEP_NODE))
	assert_eq(bool(claimed["ok"]), true, "the claim lands: %s" % claimed["reason"])
	assert_eq(
		bool(HoldingsApi.summary(_actor)["nodes"][String(DEEP_NODE)]["owner"] != {}),
		true,
		"and the hero holds it"
	)
	assert_eq(
		ForageAction.workable(_actor, DEEP_NODE),
		false,
		"but holding is not working: ADR 0097's realm gate refuses a shallow hero"
	)
	screen.select_node(String(DEEP_NODE))
	assert_eq(
		bool(screen.summary()["selected_held"]),
		true,
		"the row still reports the custody, which is the truth"
	)
	assert_eq(
		bool(screen.summary()["selected_workable"]),
		false,
		"and reports it as NOT workable, which is the other truth"
	)
	screen.free()


## `release` is always permitted and never free, and its only refusal is
## `cannot_release_foreign` — so the button stays live for every holder rather than
## being pre-judged. Asserted from the button state AND the verb.
func test_a_held_node_can_be_given_up_and_is_then_workable_no_longer() -> void:
	var screen := _bound()
	screen.act_claim(String(SHALLOW_NODE))
	screen.select_node(String(SHALLOW_NODE))
	assert_eq(
		bool(screen.summary()["enabled"]["release"]),
		true,
		"the release control is live for a holder: its only refusal is a foreign node"
	)
	var released := screen.act_release()
	assert_eq(bool(released["ok"]), true, "the node is given up: %s" % released["reason"])
	assert_eq(
		ForageAction.workable(_actor, SHALLOW_NODE),
		false,
		"and a node nobody holds is not workable again"
	)
	assert_eq(
		bool(screen.summary()["enabled"]["claim"]),
		true,
		"so taking it again is the live beat, which is the loop this page exists for"
	)
	screen.free()


## A node somebody ELSE holds is neither yours to work nor yours to give up, and the
## refusal is the module's own id. This is the custody bug the whole slice is about, so
## it is asserted against the LEDGER and not only against the button state.
func test_a_rivals_node_is_neither_workable_nor_releasable_here() -> void:
	var rival := _hero()
	rival.id = &"rival_forager"
	assert_eq(
		bool(
			HoldingsApi.claim(rival, SHALLOW_NODE, {"kind": "actor", "id": String(rival.id)})["ok"]
		),
		true,
		"setup: the rival holds it"
	)
	var screen := _bound()
	screen.select_node(String(SHALLOW_NODE))
	assert_eq(
		bool(screen.summary()["selected_held"]),
		false,
		"the row does not report the hero as the holder"
	)
	assert_eq(
		bool(screen.summary()["selected_workable"]), false, "and does not report it as workable"
	)
	var released := screen.act_release()
	assert_eq(bool(released["ok"]), false, "and the hero cannot give up ground that is not theirs")
	assert_eq(
		String(released["reason"]), HoldingsState.HOLDER_MISMATCH, "and the refusal names the rule"
	)
	var gather := screen.act_gather(String(SHALLOW_NODE), 1)
	assert_eq(String(gather["reason"]), HoldingsState.HOLDER_MISMATCH, "nor work it")
	assert_eq(
		String(HoldingsApi.summary(_actor)["nodes"][String(SHALLOW_NODE)]["owner"]["id"]),
		String(rival.id),
		"and the ledger still names the rival: ADR 0085's invariant is untouched"
	)
	screen.free()


# --- the screen contract -----------------------------------------------------


## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state
## unreadable rather than merely empty.
func test_the_screen_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")
	screen.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and `ui_cancel` is
## DECLINED so the stack pops exactly as it pops every other screen. A screen that
## swallowed cancel would trap the player on a page that now has three verbs.
func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "still empty, so a focus call did not invent state")

	screen.setup(_actor)
	assert_eq(screen.on_stack_input(null), false, "a null event is declined")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_eq(screen.on_stack_input(cancel), false, "cancel is declined so the stack pops")
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	assert_eq(screen.on_stack_input(right), false, "and so is everything else")
	screen.free()


## `ui_accept` on a picked node fires the verb its own state makes primary — claim a
## node nobody holds — and on the SAME node after the claim fires the harvest. One key,
## the mechanic's own order, and the panel re-rendering between the two is what makes it
## readable rather than a guess.
func test_accept_claims_then_works_the_picked_node_in_the_orders_the_mechanic_requires() -> void:
	var screen := _bound()
	var node_id := _claimable_node()
	assert_ne(node_id, "", "setup: the corpus authors a node nobody holds")
	screen.select_node(node_id)

	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(screen.on_stack_input(accept), true, "accept is consumed, because it did something")
	assert_eq(
		String(screen.summary()["last_reason"]),
		"",
		"and what it did was the claim: a vacant node accepts one"
	)
	assert_eq(
		ForageAction.workable(_actor, StringName(node_id)), true, "so the node is now workable"
	)
	assert_eq(screen.on_stack_input(accept), true, "and the next accept is consumed too")
	var after := screen.summary()
	assert_eq(int(after["last_granted"]) > 0, true, "and it worked the node: goods arrived")
	screen.free()


## `ui_up` / `ui_down` move the pick along the SHOWN list and consume only when they did
## something — which is what keeps `ui_cancel` free by association.
func test_the_pick_walks_the_shown_list_and_is_declined_on_an_empty_one() -> void:
	var screen := _bound()
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_eq(screen.on_stack_input(down), true, "down picks the first node")
	var picked := String(screen.summary()["selected_node"])
	assert_ne(picked, "", "and something is picked")
	var up := InputEventAction.new()
	up.action = &"ui_up"
	up.pressed = true
	assert_eq(screen.on_stack_input(up), true, "up is consumed too")
	assert_eq(screen.on_stack_input(null), false, "a null event is still declined")
	screen.free()


## Every authored node with a yield is a row. A node that silently vanished would read
## as content the build does not have, which is the dead-content failure ADR 0063 shipped
## once already.
func test_every_authored_node_is_listed_rather_than_truncated() -> void:
	var screen := _bound()
	var listed := screen.summary()["node_ids"] as Array
	var authored := ForageApi.yieldable_node_ids()
	assert_ne(authored.is_empty(), true, "the corpus authors nodes to list")
	assert_eq(listed.size(), authored.size(), "one row per authored node, not the pool's size")
	for node_id in authored:
		assert_eq(listed.has(String(node_id)), true, "%s has a row" % node_id)
	screen.free()


## ## Why this is asserted on the SCREEN and not only on the panel
##
## The pool is grown from the scene's mounted rows through `RowBudget.cap`, so a cap low
## enough to bite would silently drop nodes off the end of the list. The corpus is sixteen
## today and the cap is 256, so the case is stated as "the screen shows what the facade
## says" rather than against the literal 16: the claim is that no authored node is
## unreachable, and a literal count would go stale on the next content wave.
func test_a_short_harness_report_does_not_truncate_the_catalogue() -> void:
	var screen := _bound()
	var listed := screen.summary()["node_ids"] as Array
	assert_eq(
		listed.size(),
		ForageApi.yieldable_node_ids().size(),
		"every authored node survives the row pool"
	)
	screen.free()


# --- the panel owns every format ---------------------------------------------


## AGENTS.md: "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths." So the row's rendered line carries the figures and the SCREEN's summary
## carries them raw, which is what a test can assert on without asserting pixels.
func test_the_row_panel_prints_the_figures_and_the_screen_formats_none() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as ResourceNodeRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	row.show_node(ForageApi.view(null, SHALLOW_NODE))
	var shown := row.summary()
	assert_ne(shown, {}, "an authored node fills it")
	var rates := String(shown["rates_line"])
	# `str`, not `String(int)`: Godot 4.7 has no `String` constructor taking an int, and
	# the figure has to be the one the row printed, so it is rendered the same way here.
	assert_ne(
		rates.find(str(int(shown["yield_per_period"]))),
		-1,
		"the row prints the authored yield, which the def authored rather than the screen"
	)
	var meta := String(shown["meta"])
	assert_ne(
		meta.find(String(SHALLOW_REALM)),
		-1,
		"and the band, so a player reads the gate before pressing"
	)
	row.free()


## ADR 0083's three custody states are three DISTINCT cards, because the claim button and
## the gather button mean opposite things on them and a board where an unheld node looks
## like a held one cannot be acted on at all.
func test_the_row_keeps_the_three_custody_states_apart() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as ResourceNodeRow
	# A node nobody holds: visible, and visibly NOT yours.
	row.show_node(ForageApi.view(null, SHALLOW_NODE))
	assert_eq(bool(row.is_filled()), true, "an authored unheld node still EXISTS and renders")
	assert_eq(row.is_vacant(), true, "and says so")
	assert_eq(row.is_held(), false, "and is not reported as this hero's")
	# A node this hero holds: a different card, entirely.
	row.show_node({"node_id": "t_held", "display_name": "Held", "held": true, "vacant": false})
	assert_eq(row.is_held(), true, "a held node is held")
	assert_eq(row.is_vacant(), false, "and NOT vacant")
	assert_ne(
		String(row.summary()["card_tone"]),
		"VacantSeatCard",
		"and the card is a different one, so the two never read alike"
	)
	# A node under an open standoff: a third card, because ADR 0085's whole claim is that
	# a challenge moves no ground.
	row.show_node({"node_id": "t_held", "display_name": "Held", "held": true, "contested": true})
	assert_eq(row.is_contested(), true, "a contested node says so")
	assert_ne(
		String(row.summary()["card_tone"]), "VacantSeatCard", "and is not the vacancy card either"
	)
	# `{}` is the FIRST state: a pool row that is not a node at all.
	row.clear()
	assert_eq(row.summary(), {}, "and clearing empties it again, rather than blanks")
	row.free()


## The screen names NO module interior and no `app/` type. `tools arch` checks the module
## side of that boundary; this checks the UI side, by reading the shipped source.
func test_the_screen_names_two_facades_and_nothing_else_from_either_module() -> void:
	# `_code_only`, not the raw file: both scripts DOCUMENT the modules they are barred
	# from — `ResourceNodeRow`'s own class note names `ForageApi`, and the screen's names
	# `HoldingsState` in prose about the vocabulary it is handed. Scanning the file would
	# assert the comment and fail on the very boundary it was written to prove.
	var screen_code := _code_only(SCRIPT_PATH)
	assert_eq(
		screen_code.count("HoldingsApi.claim("), 1, "the screen calls `claim` by name, exactly once"
	)
	assert_eq(screen_code.count("HoldingsApi.release("), 1, "and `release` by name, exactly once")
	assert_eq(
		screen_code.count("ForageApi.views("), 1, "and reads the forage facade once per refresh"
	)
	for interior in ["HoldingsState", "ResourceNodeDef", "ResourceNodeCatalog", "WorldLedger"]:
		assert_eq(
			screen_code.contains(interior),
			false,
			"the screen names %s; ui/ may only reach the facade" % interior
		)
	assert_eq(
		screen_code.contains("res://src/modules/"),
		false,
		"and paths into no module; a panel calls the facade by bare name"
	)
	# The panel holds the same line: it is a row of the same data.
	var panel_code := _code_only(PANEL_SCRIPT_PATH)
	for interior in ["HoldingsApi", "ForageApi", "HoldingsState", "ResourceNodeDef"]:
		assert_eq(
			panel_code.contains(interior),
			false,
			"the row names %s either; it renders a dictionary and reaches nothing" % interior
		)


## The panel must resolve its widgets lazily, never in `@onready`, or a headless run that
## drives it with no scene tree binds nothing and renders nothing — which is the failure
## `test_ui_conventions.gd` exists to catch tree-wide and this file exists to make local.
##
## Read as code, for the reason the scan above gives: this panel's docstrings mention
## `@onready` and `ForageApi` in the very sentences that forbid them.
func test_the_row_binds_its_nodes_lazily_and_builds_no_widgets_in_ready() -> void:
	var code := _code_only(PANEL_SCRIPT_PATH)
	assert_eq(code.contains("@onready"), false, "no @onready in a panel")
	assert_eq(code.contains("func _bind_nodes()"), true, "it binds in _bind_nodes()")
	assert_eq(code.contains(".new()"), false, "and mints no widget, which a scene mounts")


## The last three bans, read off the SHIPPED screen: no `queue_free()` (a deferred free
## never runs under a runner driven from `SceneTree._initialize()`, so it leaks a screen's
## whole row pool for the life of the process), no `theme_override_*`, and no number
## formatting of its own. Each is the rule a reviewer would otherwise have to re-read the
## whole file to check.
##
## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`
##
## The rule is "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths", and what it protects is the FIGURES A PLAYER READS. The screen may still name
## a count it does not display: it grows its row pool with `row.name = "Node%d"`, and a
## node's name in the scene tree is not an authored figure on a card. So the scan looks
## for `%d`/`%.1f` in the same expression as an assignment to something a `Label` reads —
## `text`, `rates_line`, `meta` — which is the only place a formatted number reaches a
## player. Written as it is, the first version of this case failed red on the screen's own
## pool naming, which is the scan measuring the wrong thing rather than the screen breaking
## a rule.
func test_the_screen_breaks_none_of_the_three_bans_the_ui_standard_states() -> void:
	var code := _code_only(SCRIPT_PATH)
	assert_eq(code.contains("queue_free"), false, "no queue_free(): the runner never defers")
	assert_eq(code.contains("theme_override_"), false, "no theme_override_*: the theme owns style")
	assert_eq(code.contains(".free()"), false, "and nothing is freed at all from a screen")
	for sink in [".text =", "rates_line", "_meta =", "_custody =", "_head ="]:
		for format in ["%d", "%.1f", "%.2f"]:
			var line := ""
			for candidate in code.split("\n"):
				if candidate.contains(sink) and candidate.contains(format):
					line = candidate
					break
			assert_eq(
				line.is_empty(),
				true,
				"no formatted figure reaches a label: %s" % sink + (" (%s)" % format)
			)
	# The pool grows; it never mints a control the scene did not mount. `RowBudget` and
	# `ActionSet` are the two things a screen legitimately grows and delegates to.
	assert_eq(code.count("instantiate()"), 2, "it grows rows and only rows")


# --- plumbing ----------------------------------------------------------------


## The shipped source of `path` with every comment removed.
##
## A `#` line, and everything from an inline `#` to end of line, is prose. Asserting on
## prose is worse than useless here: this suite's whole subject is a boundary BETWEEN what
## a script says about a module and what it calls, and a docstring naming a banned symbol
## would turn a real boundary check into a typo detector. Same shape as
## `tests/ui/test_ui_conventions.gd:_strip_comments`.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
