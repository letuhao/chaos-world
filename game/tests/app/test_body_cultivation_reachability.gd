extends TestCase

## PROOF THAT BODY CULTIVATION IS REACHABLE IN THE SHIPPED BUILD (BL-0119).
##
## Everything here runs against the **real** `run/main_scene`, mounted through
## `SeamHarness`, and drives the controls a player drives. Nothing constructs a
## second actor: the hero under test is the one the composition root built, and
## the assertion is on *its* body path, not on a copy.
##
## The distinction this file exists to enforce: a screen that exists, parses, and
## even instantiates in a test proves nothing. Body cultivation shipped for
## months behind `main.gd`, a composition root for a scene that was deleted, so it
## had a panel, a facade and thirty realms of content and no way in. Every
## assertion below is therefore made against a node the running app parented and a
## button the app connected.

const BODY_SCENE := "res://src/ui/screens/body_cultivation_panel.tscn"
const NAV_BAR := "%NavBar"
const BODY_ROUTE := &"body_cultivation"
## The first realm on the ladder, and therefore what a fresh hero enrols at.
const START_REALM := "qi_refining"
## A training step is `STEPS.cultivate`, and every realm's rate factor is at or
## above 1, so one press moves progress by at least this much.
const MIN_STEP := 1.0


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_clear_save_slot()


## Delete the REAL save slot, so every test below boots a FRESH hero.
##
## `SeamHarness.clear_save()` removes `user://item_workbench_state.json` — the workbench
## screen's own file — and not `SavePaths.PRIMARY` / `SavePaths.BACKUP`, which is what
## `SaveApi.restore()` actually reads through `SaveStore`. So whether this suite exercised
## the fresh-boot branch or the restore branch depended on whether some earlier run in the
## machine's history had persisted a slot: a green suite could be asserting about a
## returning player while claiming to be asserting about a new one.
##
## Which is exactly how `test_elements_state_is_live_on_the_shipped_hero` came to be red
## for a reason nobody wrote down. `restore_actor` re-mounted every module that CONTRIBUTES
## to a restored hero except the element provider, so a restored body derived no elemental
## power and no elemental resistance at all — five missing `element_resistance_<e>` keys
## and one dead power value, with `element_power_<e>` still present because
## `ActorStats._recompute` backs every modifier bucket at `0.0`.
##
## The restore branch is not hidden to stay hidden: the restored case below persists
## a slot and drives it deliberately.
## below persists a slot and drives it deliberately.
func _clear_save_slot() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## Open the body route through the app's single navigation door.
##
## This is `navigate_to(route_id)` rather than a press of the navigation bar's Body
## button, and the reason is a headless-runner limitation rather than a weaker
## claim: `NavBar._publish_routes()` — which fills the table `_on_slot_pressed`
## reads — runs only from `NavBar._ready()`, and `SeamHarness` documents that the
## runner never delivers `_ready()` for anything it parents under the tree root.
## So a bar press is a silent no-op in every headless suite. `navigate_to` is what
## that press calls (`_on_route_requested` forwards to it and nothing else), and
## the bar-to-app wiring it depends on is asserted separately below; `nav_probe`
## drives the bar itself in a live SceneTree, where `_ready()` does run.
##
## Returns the live screen, or null when the app refuses the route.
func _open_body(harness: SeamHarness) -> Control:
	var moved := harness.navigate(BODY_ROUTE)
	assert_eq(moved["ok"], true, "the body route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return null
	var live := harness.live_screen()
	assert_ne(live, null, "the route left a live screen on the stack")
	if live == null:
		return null
	assert_eq(live.scene_file_path, BODY_SCENE, "and that screen is the body-cultivation panel")
	assert_eq(String(live.name), ScreenRoutes.node_of(BODY_ROUTE), "named for its route")
	assert_eq(harness.bound_actor(live), harness.actor, "and bound to the app's own hero")
	return live


# --- The feature is reachable -------------------------------------------------


func test_a_player_can_open_body_cultivation_from_the_running_app() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_body(harness)
	if screen == null:
		return
	var view := screen.summary() as Dictionary
	assert_ne(view.is_empty(), true, "the panel renders a real view, not keys")
	assert_eq(String(view["realm"]), START_REALM, "the hero is enrolled on the body path")
	assert_eq(int(view["acupoints"]) > 0, true, "with an acupoint layout")
	assert_eq((view["channels"] as Array).is_empty(), false, "and its channels unlocked")
	var vitals := view["vitals"] as Dictionary
	assert_eq(String(vitals["realm"]), START_REALM, "the vitals row reads the same realm")
	assert_eq(
		float(vitals["integrity_maximum"]) > 0.0,
		true,
		"and a body-integrity ceiling the player can see"
	)


func test_the_hero_the_app_built_carries_a_body_path() -> void:
	# The root cause in one assertion: before this, the only actor the app built
	# had no path at all, so every body facade call answered "not on the body path".
	var harness := _boot()
	if harness.boot_error != "":
		return
	var state := harness.actor.path(BodyPath.PATH_ID)
	assert_ne(state, null, "the shipped hero is enrolled on the body path")
	if state == null:
		return
	assert_eq(String(state.rank_id), START_REALM, "at the ladder's first realm")
	assert_ne(
		harness.actor.component(&"body_cultivation_provider"), null, "the body provider is attached"
	)
	assert_ne(BodyCultivationApi.acupoints(harness.actor).size(), 0, "with acupoints")
	assert_ne(
		harness.actor.resource(BodyStats.BODY_INTEGRITY),
		null,
		"and the body-integrity pool the training verbs fill"
	)


# --- The feature does something -----------------------------------------------


func test_pressing_cultivate_advances_real_body_progress_on_the_shipped_hero() -> void:
	# The end-to-end claim. A real Button press on the app's own mounted panel
	# moves the app's own actor's own path state. Nothing here builds an actor.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_body(harness)
	if screen == null:
		return
	var actor := harness.actor
	var before := actor.path(BodyPath.PATH_ID)
	assert_ne(before, null, "there is a body path to advance")
	if before == null:
		return
	var progress_before := float(before.progress)
	var quality_before := BodyCultivationApi.acupoints(actor)[0].quality
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY) as ResourcePool
	assert_ne(integrity, null, "the body reservoir the press fills exists")
	if integrity == null:
		return
	# A fresh hero's reservoir is already at its ceiling, so a press could not raise
	# it. Spend it first: that is the state a player is actually in between presses.
	actor.change_resource(BodyStats.BODY_INTEGRITY, -60.0)
	var integrity_spent := integrity.current
	assert_eq(integrity_spent < integrity.maximum, true, "the body reservoir is spent")

	assert_eq(harness.press(screen, "%CultivateButton"), true, "Cultivate is a live control")

	var after := actor.path(BodyPath.PATH_ID)
	assert_eq(after, before, "the press mutated the hero's own path state, not a copy of it")
	assert_eq(
		float(after.progress) - progress_before >= MIN_STEP,
		true,
		"pressing Cultivate advanced real body progress on the shipped hero"
	)
	assert_eq(
		BodyCultivationApi.acupoints(actor)[0].quality > quality_before,
		true,
		"and raised an acupoint's quality"
	)
	assert_eq(
		integrity.current > integrity_spent,
		true,
		"and refilled the shared body-integrity reservoir"
	)
	# The player can see it: the panel re-read the facade and repainted.
	var view := screen.summary() as Dictionary
	assert_eq(
		float(view["progress"]),
		float(after.progress),
		"the screen shows the progress the press produced"
	)
	assert_eq(String(view["tone"]), "ok", "and reports the outcome")


func test_pressing_strengthen_with_no_elixir_is_refused_and_says_why() -> void:
	# The gate has to be legible in both directions: an unmet gate offers a dead
	# control, and pressing it anyway says what is missing rather than doing
	# nothing silently (ADR 0043).
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_body(harness)
	if screen == null:
		return
	var view := screen.summary() as Dictionary
	assert_eq((view["unmet"] as Array).is_empty(), false, "the gate names what is unmet")
	assert_eq(
		(view["actions"] as Dictionary)["breakthrough"],
		false,
		"so the screen does not offer a breakthrough"
	)
	var breakthrough := harness.button(screen, "%BreakthroughButton")
	assert_ne(breakthrough, null, "the breakthrough control exists")
	if breakthrough != null:
		assert_eq(breakthrough.disabled, true, "and a player cannot press an unmet gate")
	assert_eq(harness.press(screen, "%StrengthenButton"), true, "Strengthen is a live control")
	var refused := screen.summary() as Dictionary
	assert_eq(String(refused["tone"]), "error", "a refused action is reported as one")
	assert_ne(String(refused["message"]), "", "with a message, not silence")


func test_the_body_screen_own_world_map_button_is_a_navigation_door() -> void:
	# A wired button, not a dead one: the body screen asks for another screen and
	# the app's single navigation mechanism moves there.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var screen := _open_body(harness)
	if screen == null:
		return
	assert_eq(harness.press(screen, "%WorldMapButton"), true, "World Map is a live control")
	var live := harness.live_screen()
	assert_ne(live, null, "a live screen replaced the body panel")
	if live == null:
		return
	assert_eq(live.scene_file_path, "res://src/ui/screens/world_map_screen.tscn", "the world map")
	assert_eq(
		String(harness.app.call(&"current_route")),
		String(ScreenRoutes.id_for_scene(live.scene_file_path)),
		"and the app reports the route it navigated to"
	)


func test_the_navigation_bar_offers_the_body_route_and_is_wired_to_the_app() -> void:
	# The bar is the only thing standing between a player and this screen, so its
	# offer and its wiring are asserted rather than assumed. The *press* is not:
	# `NavBar` publishes its route table from `_ready()`, which the headless runner
	# does not deliver, so pressing it here would prove nothing about the shipped
	# game. `src/app/nav_probe.gd` presses it in a live SceneTree instead.
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
	var slot := ScreenRoutes.index_of(BODY_ROUTE)
	assert_ne(slot, -1, "the route table names a body route")
	if slot < 0:
		return
	var button := harness.button(nav, NavBar.slot_unique_name(slot)) as Button
	assert_ne(button, null, "the bar authored a slot for the body route")
	if button == null:
		return
	assert_eq(button.disabled, false, "and a player can press it")
	# `get_connections` is a method on a SIGNAL, not on the object that declares it:
	# `Button` has no such member, and calling it aborted the whole run before the
	# Results line. `button.pressed` is the Signal, and that is what carries the
	# connection list.
	assert_ne(button.pressed.get_connections().size(), 0, "with a handler attached")
	# "One move away" is the claim, and it is asserted as the CLAIM rather than as the
	# route boot happened to pick. ADR 0130 made `character_creation` a route the
	# composition root opens at boot for a player who has no hero yet, so pinning
	# `ScreenRoutes.ROOT_ID` here asserted a boot decision that is not this file's to make
	# — and it went red for that reason while the wiring above it, which is the part that
	# decides whether a player can reach Body at all, stayed exactly as strong. What must
	# hold is: boot landed somewhere the route table NAMES (the shell mounted a screen it
	# can leave), and it is not already the body route (so Body really is a move).
	#
	# The repo's own idiom for exactly this is `test_screen_reachability.gd`'s
	# "the game does not boot on the route this button opens".
	var booted_at := String(harness.app.call(&"current_route"))
	assert_eq(
		ScreenRoutes.index_of(StringName(booted_at)) >= 0,
		true,
		"and boot landed on a route the table names (%s), so the shell can be left" % booted_at
	)
	assert_ne(booted_at, String(BODY_ROUTE), "and not already on Body, so Body is a move away")
	# …and the move is the app's single navigation door, which every other case here drives.
	assert_eq(
		bool(harness.navigate(BODY_ROUTE).get("ok", false)), true, "and that one move opens it"
	)
	assert_eq(
		String(harness.app.call(&"current_route")), String(BODY_ROUTE), "leaving the player on Body"
	)


# --- The three dead modules are no longer dead (BL-0228) ----------------------
#
# Each assertion reads state the module owns, on the actor the app shipped. A
# call to `attach()` proves nothing; a populated stat or a filled pool does.


func test_dual_cultivation_state_is_live_on_the_shipped_hero() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	var essence := actor.resource(DualCultivationStats.ESSENCE) as ResourcePool
	assert_ne(essence, null, "the essence pool exists")
	if essence == null:
		return
	var capacity := actor.stats.derived(DualCultivationStats.ESSENCE_CAPACITY)
	assert_eq(
		capacity > 0.0,
		true,
		"the dual-cultivation provider contributes an essence capacity the hero has"
	)
	assert_almost_eq(essence.maximum, capacity, "and the pool was synced to it")
	assert_eq(essence.current, essence.maximum, "and the pool starts full")
	assert_ne(actor.resource(DualCultivationStats.YIN), null, "the yin pool exists")
	assert_ne(actor.resource(DualCultivationStats.YANG), null, "the yang pool exists")
	assert_eq(
		(actor.resource(DualCultivationStats.YIN) as ResourcePool).current,
		0.0,
		"and starts at zero, as the facade's own rule says"
	)


func test_fertility_state_is_live_on_the_shipped_hero() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	# `FertilityProvider` contributes a floor of 0.05 conception chance and a
	# gestation speed above 1.0 whatever the bases are, so both are non-zero only
	# while the provider is on the actor.
	assert_eq(
		actor.stats.derived(FertilityStats.CONCEPTION_CHANCE) > 0.0,
		true,
		"the fertility provider contributes a conception chance"
	)
	assert_eq(
		actor.stats.derived(FertilityStats.GESTATION_SPEED) > 1.0,
		true,
		"and a gestation speed that scales with the hero's build"
	)
	assert_eq(
		actor.stats.derived(FertilityStats.RECOVERY_RATE) > 1.0,
		true,
		"and a recovery rate, so a pregnancy would have somewhere to go"
	)
	assert_eq(FertilityApi.pregnancy(actor), null, "with no pregnancy open on a fresh hero")


func test_elements_state_is_live_on_the_shipped_hero() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	# A FRESH boot, deliberately: `setup` removed the real slot, so this case can only be
	# green if `ActorFactory.build` mounted the element provider. The restore branch runs a
	# different list of verbs and is its own case below.
	assert_eq(
		bool(harness.app.call(&"restored_from_save")),
		false,
		"this case boots a fresh hero, not one restored from a slot"
	)
	_assert_element_channel(harness.actor, "the fresh shipped hero")


## THE RESTORE BRANCH, and the class guard for the defect this suite was red for.
##
## `restore_actor` re-mounts every module that CONTRIBUTES to a restored hero's stats, and
## it omitted the element provider: it called `ElementsApi.apply_realm_modifiers`, which
## writes the realm `MULT` onto `element_power_<e>` and touches nothing else, while core
## never serializes a `StatProvider`. So a returning player's body carried no elemental
## power and no elemental resistance at all, and the surface LOOKED half-alive, because
## `ActorStats._recompute` backs every modifier bucket at `0.0`, so a realm multiplier
## mounted on nothing still publishes `element_power_<e>`, while `element_resistance_<e>`,
## which no modifier ever names, simply was not there.
##
## Nothing about that was visible from a fresh boot, from `Actor.new`, or from any module
## suite: `ActorFactory.build` mounts the provider, and the only path that skips it is the
## one a save takes. So it is driven here on purpose: persist a slot through the shipped
## writer, boot again, and assert the same channel on the body that comes back.
func test_a_restored_shipped_hero_carries_the_same_element_ids() -> void:
	var first := _boot()
	if first.boot_error != "":
		return
	assert_eq(
		bool(SaveApi.persist(first.actor).get("ok", false)),
		true,
		"the shipped writer persists a slot for the next boot to read"
	)
	# `SeamHarness.mount_new` tears the previous mount down; the slot on disk survives it,
	# because `clear_save` only removes the workbench screen's own file.
	var restored := SeamHarness.mount_new()
	assert_eq(restored.boot_error, "", "and the app boots again over that slot")
	if restored.boot_error != "":
		return
	assert_eq(
		bool(restored.app.call(&"restored_from_save")),
		true,
		"the second boot really took the restore branch, or this case proves nothing"
	)
	_assert_element_channel(restored.actor, "the restored shipped hero")


## What "the element channel is live" means, asserted identically on either boot path.
##
## `derived_all()` carries every key a provider contributes, so the ids being present at
## all is the provider being attached -- a plain `derived()` read would be `0.0` for an
## untrained element either way. `element_resistance_<e>` is the id that matters most here:
## it is the one no realm modifier names, so it is the one that cannot be accidentally
## reproduced by the `0.0` modifier backing that made the power half look healthy.
func _assert_element_channel(actor: Actor, label: String) -> void:
	var surface := actor.stats.derived_all()
	for element in ElementStats.BASE_ELEMENTS:
		assert_eq(
			surface.has(String(ElementStats.power_id(element))),
			true,
			"the element provider contributes element_power_%s on %s" % [element, label]
		)
		assert_eq(
			surface.has(String(ElementStats.resistance_id(element))),
			true,
			"and element_resistance_%s on %s" % [element, label]
		)
	# And it is a live value, not a stale key: give the hero an affinity the way a
	# cross-training unlock would, and the power stat follows it. On the restore branch
	# this is the assertion that failed while every key assertion above it passed.
	actor.set_affinity(ElementStats.FIRE, 2.0)
	actor.mark_stats_dirty()
	assert_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)) > 0.0,
		true,
		"an affinity in an element becomes elemental power on %s" % label
	)
	# The realm multiplier ADR 0069 exists for is only written when a path exists;
	# the body path is what gives the element channel a realm to scale by.
	var realm := RealmScaling.highest_realm(actor)
	assert_ne(realm, null, "the hero has a realm for the element channel to scale by")


func test_the_shipped_hero_carries_every_module_the_slice_offers() -> void:
	# One read of the whole attach list, so a future removal of any one of them is
	# a named failure rather than a symptom somewhere else.
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor
	assert_ne(actor.component(&"body_cultivation_provider"), null, "body cultivation")
	assert_ne(actor.resource(DualCultivationStats.ESSENCE), null, "dual cultivation")
	assert_eq(actor.stats.derived(FertilityStats.CONCEPTION_CHANCE) > 0.0, true, "fertility")
	# `>= 0.0` was the old form of this line and it could never fail: `ActorStats.derived`
	# answers `0.0` for an id the actor does not carry, so every absent stat passed it. That
	# is how the missing `element_resistance_<e>` channel survived a suite that claimed to
	# read every module the slice offers. The KEY has to be on the surface, which is the
	# only statement here that can distinguish a mounted provider from an absent one.
	assert_eq(
		actor.stats.derived_all().has(String(ElementStats.resistance_id(ElementStats.WOOD))),
		true,
		"elements"
	)
	assert_ne(ItemsApi.inventory(actor), null, "items")
	assert_ne(actor.component(&"socket_ledger"), null, "socket")
	assert_ne(actor.get_module_data(&"loot_state"), {}, "loot")
	assert_ne(actor.resource(&"health"), null, "core resources")


# --- The orphaned composition root is gone ------------------------------------


func test_the_orphaned_composition_root_is_deleted() -> void:
	# `main.gd` was a second composition root for `Main.tscn`, a scene that no
	# longer exists. It could only ever hard-fail, and it carried a stock cheat
	# that papered over a gate a player is supposed to meet honestly. Body
	# cultivation lives in the shipped app now, so the orphan must not come back.
	assert_eq(FileAccess.file_exists("res://src/app/main.gd"), false, "src/app/main.gd is gone")
	assert_eq(FileAccess.file_exists("res://scenes/Main.tscn"), false, "scenes/Main.tscn is gone")
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene", ""),
		"res://scenes/item_workbench/ItemWorkbenchApp.tscn",
		"and the shipped entry point is the app that owns body cultivation"
	)
	assert_eq(
		_orphaned_main_scripts(), [], "no script still declares the orphaned Main composition root"
	)


## Every `src/app/*.gd` that still carries the deleted root's class name. Read from
## the filesystem rather than restated, so a rename cannot make this vacuous.
func _orphaned_main_scripts() -> Array[String]:
	var out: Array[String] = []
	for path in _source_texts("res://src/app"):
		if path.ends_with(".gd") and ("class_name Main\n" in FileAccess.get_file_as_string(path)):
			out.append(path)
	return out


static func _source_texts(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := "%s/%s" % [root, entry]
			if dir.current_is_dir():
				out.append_array(_source_texts(path))
			elif entry.ends_with(".gd"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
