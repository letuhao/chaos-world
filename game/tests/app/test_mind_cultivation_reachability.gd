extends TestCase

## PROOF THAT MIND CULTIVATION IS REACHABLE IN THE SHIPPED BUILD, AND THAT ITS
## PRICED VERBS ARE OFFERED (BL-0102's residual G1).
##
## Everything here runs against the **real** `run/main_scene`, mounted through
## `SeamHarness`, and drives the controls a player drives. Nothing constructs a
## second actor: the hero under test is the one the composition root built, and
## every assertion is on *its* mind path, not on a copy.
##
## Why this file exists at all. `MindCultivationApi.recover_next` shipped with zero
## callers in `res://src`, so the `mind_<realm>_recovery_elixir` every realm authors
## (ADR 0031) had no way to leave a player's inventory and a burned channel was a
## permanent dead end. Ten thousand green assertions did not see it, because every
## Mind suite hand-builds an `Actor` and hand-calls `MindCultivationApi.attach_sea`
## (`test_full_traversal.gd`, `mind_gate_probe.gd`, `test_mind_persistence.gd`,
## `test_mind_cultivation_screen.gd`, `test_mind_ascent.gd`). The same hand-call
## hid `attach_sea` itself having no production caller at all (BL-0523): the module
## was green, the game had no Sea of Consciousness. **A suite that builds its own
## actor can only ever report that its own fixture works.** These tests read the one
## actor the app shipped.
##
## Modelled on `test_body_cultivation_reachability.gd`, including the reason the
## route is opened with `navigate()` rather than a nav-bar press: `NavBar` publishes
## its route table from `_ready()`, which `SceneTree._initialize()` never delivers,
## so a bar press is a silent no-op under the headless runner. The bar's own offer
## and wiring are asserted separately below.

const MIND_SCENE := "res://src/ui/screens/mind_cultivation_screen.tscn"
const MIND_ROUTE := &"mind_cultivation"
const NAV_BAR := "%NavBar"
## The composition root, and the only layer allowed to wire a module to the shipped
## hero. A mind enrolment found anywhere else would be the same boundary violation
## read from the other side.
const APP_DIR := "res://src/app"
## `src/app/` is two levels deep at most; this is slack, not a tuned number.
const MAX_WALK_DEPTH := 8
## The ladder's first realm, which is where `ActorFactory.with_mind_cultivation`
## enrols the shipped hero.
const START_REALM := "qi_refining"
## The only meridian this realm requires, and the cheapest wound to burn. Taken from
## the realm seed the module publishes for the price, never hardcoded, so a seed
## that renames it is a named failure rather than a silent no-op.
const FIRST_REQUIRED := &"lung"
## A refusal that named nothing a player can act on.
const FALSE_NEGATIVE := "No channel left to train"


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## Open the mind route through the app's single navigation door, and pin that the
## screen it leaves is the real one, bound to the app's own hero. Returns the live
## screen, or null when the app refuses the route.
##
## `bound_actor` is the load-bearing assertion in this file: a screen bound to a
## hand-built actor would render a mind path the shipped hero does not have, which
## is the whole shape of the defect.
func _open_mind(harness: SeamHarness) -> Control:
	assert_eq(
		SeamHarness.route_for_scene(MIND_SCENE),
		MIND_ROUTE,
		"the route table serves this screen under the id the suite navigates to"
	)
	var moved := harness.navigate(MIND_ROUTE)
	assert_eq(moved["ok"], true, "the mind route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return null
	var live := harness.live_screen()
	assert_ne(live, null, "the route left a live screen on the stack")
	if live == null:
		return null
	assert_eq(live.scene_file_path, MIND_SCENE, "and that screen is the mind-cultivation screen")
	assert_eq(String(live.name), ScreenRoutes.node_of(MIND_ROUTE), "named for its route")
	assert_eq(harness.bound_actor(live), harness.actor, "and bound to the app's own hero")
	return live


## The realm's own recovery elixir — the id `recover_next` spends. Read from the
## module's seed because this is a test: the suite's job is to put the authored
## price in the hero's hand, which is precisely the step a player cannot skip.
func _recovery_id() -> StringName:
	var seed := MindRealmSeed.for_realm(START_REALM)
	return &"" if seed == null else seed.recovery_item


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


func _burn(actor: Actor, meridian_id: StringName) -> void:
	actor.meridians.damage_meridian(meridian_id)


## Every burned channel the facade itself reports as on the actor's network. Scoped
## to channels that exist, because the facade reports a not-yet-unlocked channel as
## injured and a count that included those would answer "you owe an elixir" to a
## hero who was never burned.
func _burned_ids(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for entry in MindCultivationApi.summary(actor).get("channels", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String(entry.get("state", "")) == "unknown":
			continue
		if bool(entry.get("injured", false)):
			out.append(String(entry.get("id", "")))
	return out


# --- The feature is reachable -------------------------------------------------


func test_a_player_can_open_mind_cultivation_from_the_running_app() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var view := screen.summary() as Dictionary
	assert_ne(view.is_empty(), true, "the screen renders a real view, not keys")
	assert_eq(String(view["realm"]), START_REALM, "the hero is enrolled on the mind path")
	assert_eq(float(view["mind_power_max"]) > 0.0, true, "with a sea of consciousness")
	assert_eq((view["channels"] as Array).is_empty(), false, "and a meridian network to read")
	# The gate's own target, read off the shared ladder rather than hardcoded, so a
	# realm inserted below R1 cannot turn this into a stale literal.
	assert_eq(
		String(view["target"]),
		String(RealmDefaults.ladder().next(StringName(START_REALM)).id),
		"and the gate names the next realm on the ladder"
	)


func test_the_hero_the_app_built_carries_a_mind_path() -> void:
	# The root cause in one assertion: before BL-0523 the only actor the app built
	# had no Sea of Consciousness, so every mind facade call answered "not on the
	# mind path" and 10,186 assertions still reported the module healthy.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	var state := actor.path(MindPath.PATH_ID)
	assert_ne(state, null, "the shipped hero is enrolled on the mind path")
	if state == null:
		return
	assert_eq(String(state.rank_id), START_REALM, "at the ladder's first realm")
	assert_ne(MindCultivationApi.sea(actor), null, "and carries a sea of consciousness")
	assert_ne(actor.resource(MindStats.MIND_POWER), null, "with the mind-power pool the verbs fill")
	assert_ne(actor.resource(MindStats.AWARENESS), null, "and the awareness pool")


func test_pressing_cultivate_advances_real_mind_progress_on_the_shipped_hero() -> void:
	# The end-to-end claim. A real Button press on the app's own mounted screen
	# moves the app's own actor's own path state. Nothing here builds an actor.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var actor := harness.actor
	var before := actor.path(MindPath.PATH_ID)
	assert_ne(before, null, "there is a mind path to advance")
	if before == null:
		return
	var progress_before := float(before.progress)
	assert_eq(harness.press(screen, "%CultivateButton"), true, "Cultivate is a live control")

	var after := actor.path(MindPath.PATH_ID)
	assert_eq(after, before, "the press mutated the hero's own path state, not a copy of it")
	assert_eq(
		float(after.progress) - progress_before >= MindCultivationApi.CULTIVATE_STEP,
		true,
		"pressing Cultivate advanced real mind progress on the shipped hero"
	)
	# The player can see it: the screen re-read the facade and repainted.
	var view := screen.summary() as Dictionary
	assert_eq(
		float(view["progress"]),
		float(after.progress),
		"the screen shows the progress the press produced"
	)
	assert_eq(String(view["tone"]), "ok", "and reports the outcome")


# --- The recovery verb is OFFERED (defect 1) ---------------------------------


func test_the_screen_offers_the_recovery_verb_every_realm_prices_a_burn_with() -> void:
	# The defect: `recover_next` existed on the facade and no screen declared the
	# action, so `ActionSet` never authored the button and no player could spend the
	# elixir. The action list is what a button IS here, so it is asserted on the
	# screen's own read model and then on the node the app actually parented.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var actions := screen.summary() as Dictionary
	var bar := actions["actions"] as Dictionary
	var declared: Array = bar.get("actions", [])
	assert_ne(declared.has("recover"), false, "the screen declares a recover action")
	assert_eq(
		(bar.get("enabled", {}) as Dictionary).get("recover"),
		true,
		"and offers it on a hero who is on the path"
	)
	var button := harness.button(screen, "%RecoverButton")
	assert_ne(button, null, "so a Recover control was authored, not just declared")
	if button == null:
		return
	assert_eq(button.disabled, false, "and a player can press it")


func test_pressing_recover_on_an_unburned_hero_says_there_is_no_burn() -> void:
	# The half of the refusal that is NOT a purchase. One bool covers "nothing is
	# damaged" and "the elixir is missing", and those send the player in opposite
	# directions, so the screen separates them.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	assert_eq(harness.press(screen, "%RecoverButton"), true, "Recover is a live control")
	var refused := screen.summary() as Dictionary
	assert_eq(String(refused["tone"]), "error", "a refused action is reported as one")
	assert_eq(String(refused["message"]), "No burned channel to repair", "and says what is absent")
	assert_eq(
		String(refused["message"]).contains("elixir"),
		false,
		"an unwounded hero is not told to go and buy an elixir"
	)


func test_pressing_recover_with_a_burn_and_no_elixir_names_the_missing_elixir() -> void:
	# The diagnosable refusal. The burn is applied through core's own
	# `damage_meridian` — the same call a failed breakthrough makes — to the APP'S
	# OWN hero. No actor is built here; a hand-built one is what let this defect hide.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var actor := harness.actor
	assert_ne(_recovery_id(), &"", "the first realm authors a recovery elixir")
	_burn(actor, FIRST_REQUIRED)
	assert_eq(_burned_ids(actor).has(String(FIRST_REQUIRED)), true, "the hero's own channel burned")
	assert_eq(
		ItemsApi.inventory(actor).count(_recovery_id()),
		0,
		"and the hero holds no elixir, so the repair is unaffordable"
	)

	assert_eq(harness.press(screen, "%RecoverButton"), true, "Recover is a live control")

	var refused := screen.summary() as Dictionary
	assert_eq(String(refused["tone"]), "error", "the unaffordable repair is refused")
	assert_eq(
		String(refused["message"]),
		"Recovery elixir absent",
		"and names the missing price instead of reporting nothing damaged"
	)
	assert_eq(
		actor.meridians.get_meridian(FIRST_REQUIRED).is_injured(),
		true,
		"a refused recovery spends nothing"
	)


func test_pressing_recover_spends_the_elixir_and_closes_the_burn_on_the_shipped_hero() -> void:
	# The end-to-end claim for the verb itself: the authored content leaves the
	# inventory. Before the control existed the elixir was reachable content and
	# unspendable, which is the defect in one assertion.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var actor := harness.actor
	var elixir := _recovery_id()
	assert_ne(elixir, &"", "the first realm authors a recovery elixir")
	_burn(actor, FIRST_REQUIRED)
	_stock(actor, elixir)
	assert_eq(ItemsApi.inventory(actor).count(elixir), 1, "the hero carries one elixir")
	assert_eq(_burned_ids(actor).size() > 0, true, "and one burned channel")

	assert_eq(harness.press(screen, "%RecoverButton"), true, "Recover is a live control")

	assert_eq(
		actor.meridians.get_meridian(FIRST_REQUIRED).is_injured(),
		false,
		"pressing Recover closed the burn on the app's own hero"
	)
	assert_eq(
		ItemsApi.inventory(actor).count(elixir),
		0,
		"and spent the authored elixir, so it is not dead content"
	)
	var view := screen.summary() as Dictionary
	assert_eq(String(view["tone"]), "ok", "and the screen reports the repair")
	assert_eq(String(view["message"]), "Repaired a burned channel", "in words the player reads")


# --- The refusal names the PRICE, not a dead end (defect 1, second half) ------


func test_pressing_train_channel_with_no_elixir_names_the_missing_price() -> void:
	# The undiagnosable half. `act_train_next_channel` walks its candidates and,
	# having been refused by every one of them, used to report "No channel left to
	# train". That sentence cannot be true on this path: the loop only reaches its
	# end because a channel did NOT meet `required_channel_state`. What is missing
	# is the elixir, and a player told there is nothing to do does not go and buy it.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var live := MindCultivationApi.summary(harness.actor)
	var target_state := String(live.get("required_channel_state", ""))
	assert_eq(target_state.is_empty(), false, "the realm authors a channel gate")
	var required: Array = live.get("required_channels", [])
	assert_eq(required.is_empty(), false, "and names the channels it applies to")

	assert_eq(harness.press(screen, "%TrainChannelButton"), true, "Train Channel is a live control")

	var refused := screen.summary() as Dictionary
	assert_eq(String(refused["tone"]), "error", "the unpayable training is refused")
	assert_eq(
		String(refused["message"]) != FALSE_NEGATIVE,
		true,
		(
			"the screen does NOT claim there is no channel left to train: %s"
			% String(refused["message"])
		)
	)
	assert_eq(
		String(refused["message"]).contains("elixir"),
		true,
		"and names the missing price: %s" % String(refused["message"])
	)
	assert_eq(
		String(refused["message"]).contains("still owed"),
		true,
		"while still saying the work is owed: %s" % String(refused["message"])
	)


func test_the_channel_gate_is_still_reachable_so_the_refusal_is_not_a_dead_end() -> void:
	# A refusal that names a price is only honest if the price buys the thing. Stock
	# the realm's channel elixir and the SAME press that just refused must now
	# succeed, which is what makes "elixir absent" a diagnosis rather than an excuse.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_mind(harness)
	if screen == null:
		return
	var actor := harness.actor
	var seed := MindRealmSeed.for_realm(START_REALM)
	assert_ne(seed, null, "the first realm has a seed")
	if seed == null:
		return
	var elixir := seed.training_item
	assert_ne(elixir, &"", "the first realm authors a channel elixir")
	var channel := harness.actor.meridians.get_meridian(FIRST_REQUIRED)
	assert_ne(channel, null, "the required channel is on the hero's network")
	if channel == null:
		return
	var rank_before := channel.state_rank()
	assert_eq(harness.press(screen, "%TrainChannelButton"), true, "Train Channel is a live control")
	assert_eq(
		String(screen.summary()["message"]).contains("absent"),
		true,
		"and refuses while the elixir is unheld"
	)

	_stock(actor, elixir)
	assert_eq(harness.press(screen, "%TrainChannelButton"), true, "Train Channel is still live")
	var view := screen.summary() as Dictionary
	assert_eq(String(view["tone"]), "ok", "the paid press succeeds")
	assert_eq(String(view["message"]), "Trained %s" % FIRST_REQUIRED, "on the required channel")
	assert_eq(
		channel.state_rank() > rank_before,
		true,
		"and the channel the refusal pointed at advanced on the app's own hero"
	)
	assert_eq(
		channel.meets(MeridianState.STRENGTHENED),
		false,
		(
			"one elixir is one state, so the refusal names a price bought repeatedly -- "
			+ "it is not claiming the press would clear the gate"
		)
	)


# --- The production enrolment, named before any behaviour test needs it ------


func test_a_production_caller_enrols_the_hero_on_the_mind_path() -> void:
	# The defect CLASS as a structural claim rather than a convention.
	#
	# BL-0102 was filed as "no app enrols the path, attaches the providers, or pushes
	# the screen" and the whole reachability question turned on that one line. A
	# behavioural assertion catches the removal; this catches the DRIFT — a future edit
	# that moves the enrolment out of `app/` leaves every Mind suite green, because
	# they all enrol their own fixture by hand (`test_full_traversal.gd`,
	# `mind_gate_probe.gd`, `test_mind_persistence.gd`, `test_mind_cultivation_screen.gd`,
	# `test_mind_ascent.gd`). Read from the filesystem so a renamed verb cannot make
	# this vacuous.
	assert_eq(
		_production_callers_of(&"with_mind_cultivation"),
		true,
		"something under src/app/ enrols an actor on the mind path, not only tests"
	)


func _production_callers_of(verb: StringName) -> bool:
	for path in _script_paths(APP_DIR, 0):
		if FileAccess.get_file_as_string(path).contains("%s(" % verb):
			return true
	return false


## Depth-capped because the arch rule requires it of any recursive walk: a
## traversal with no cap is an unbounded loop the moment the tree contains a cycle,
## and the `while`-scanning rules cannot see a recursive call at all.
func _script_paths(root: String, depth: int) -> Array[String]:
	var out: Array[String] = []
	if depth > MAX_WALK_DEPTH:
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := "%s/%s" % [root, entry]
			if dir.current_is_dir():
				out.append_array(_script_paths(path, depth + 1))
			elif entry.ends_with(".gd"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# --- The bar is the only thing between a player and this screen --------------


func test_the_navigation_bar_offers_the_mind_route_and_is_wired_to_the_app() -> void:
	# The bar's OFFER and its WIRING, not its press: `NavBar._publish_routes()`
	# publishes the table `_on_slot_pressed` reads from `_ready()`, which the headless
	# runner never delivers, so a press here would prove nothing about the shipped
	# game. `src/app/nav_probe.gd` presses it in a live SceneTree instead, and
	# `test_screen_reachability.gd` asserts the move end to end.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var nav := harness.app.get_node_or_null(NAV_BAR) as Control
	assert_ne(nav, null, "the app resolves its own navigation bar")
	if nav == null:
		return
	assert_eq(
		nav.is_connected(&"route_requested", Callable(harness.app, "_on_route_requested")),
		true,
		"a request from the bar reaches the app's navigation seam"
	)
	var slot := ScreenRoutes.index_of(MIND_ROUTE)
	assert_ne(slot, -1, "the route table names a mind route")
	if slot < 0:
		return
	var button := harness.button(nav, NavBar.slot_unique_name(slot)) as Button
	assert_ne(button, null, "the bar authored a slot for the mind route")
	if button == null:
		return
	assert_eq(button.disabled, false, "and a player can press it")
	assert_ne(button.pressed.get_connections().size(), 0, "with a handler attached")
	assert_ne(
		String(harness.current_route().get("route", "")),
		String(MIND_ROUTE),
		"and the game does not boot on the mind route, so it is a move away"
	)
