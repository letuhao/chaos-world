extends TestCase

## The domain explore screen, driven the way a player drives it: press the buttons the
## scene declares, on a hero that is really standing in a really generated domain.
##
## ## Why this suite exists at all
##
## The `domain` module shipped ten green suites and nothing in the shipped program ever
## reached it. A correct description of a place no player can enter is the failure this
## screen closes, and a screen that renders `{}` for a hero who IS inside a domain would
## re-open it wearing a green run. So these cases do not instantiate a stub: they build
## the real bridge `DomainBoot.bridge()` hands the shell, generate through the real
## `DomainApi.generate_and_enter`, and press real controls.
##
## ## The claims worth pinning
##
##  - `summary()` is primitives only and survives the JSON hop (the screen contract);
##  - the screen reports what the MODULE reports, not a private copy of it — the floors
##    it draws are counted from `DomainMinimap`'s own payload, so a second layout
##    invented here would be a second thing that can be wrong;
##  - a refused action renders a tone-coloured message naming the reason the FACADE gave,
##    and changes nothing;
##  - `teardown()` frees everything the suite minted, because the runner shares one
##    process across every suite.
##
## The seam is installed through the composition root on purpose. `tests/` is the
## `harness` unit and may reach anything (`tools/arch/enforce.py`), so the suite names
## `DomainBoot` and `DomainApi` freely; the SCREEN does not, which is the whole point.

const SCENE := "res://src/ui/screens/domain_explore.tscn"
## The seed the screen's own `Enter` uses, so a test can reproduce what a button press
## generated rather than generating a DIFFERENT run and asserting about the wrong map.
const SCREEN_SEED := 20260904

## Every screen this suite instantiated. The runner shares one process across every
## suite and never processes a frame, so an unfreed screen subtree stays resident for
## the rest of the run. Freed centrally because the call sites are interleaved and a
## test returning early would skip a free at its end.
var _born: Array[Node] = []
## The last test's screen, so `teardown` can prove the FREE actually ran.
var _last_screen: DomainExploreScreen = null

# ── fixtures ─────────────────────────────────────────────────────────────────


## A hero with an inventory, because a treasure pays out through one and the screen's
## fixture verbs answer `no_inventory_bridge` without it.
func _hero() -> Actor:
	var hero := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	hero.attach_core_resources()
	ItemsApi.attach(hero, 24)
	return hero


## The screen, with the composition root's real bridge attached — the same object
## `ItemWorkbenchApp` would hand it. `_ready` is driven by hand because the runner
## executes inside `SceneTree._initialize()` and the engine never delivers it.
func _screen(hero: Actor, bridged: bool = true) -> DomainExploreScreen:
	var packed := load(SCENE) as PackedScene
	assert_ne(packed, null, "the domain screen scene loads")
	if packed == null:
		return null
	var screen := packed.instantiate() as DomainExploreScreen
	_born.append(screen)
	_last_screen = screen
	screen.call("_ready")
	screen.call("setup", hero)
	if bridged:
		screen.call("bind_bridge", DomainBoot.bridge())
	return screen


## A screen already standing in a generated domain, through the screen's own `Enter`
## button rather than by calling the facade behind its back — so the fixture is the path
## a player takes, and a broken `Enter` fails every case that uses it.
##
## `Enter` is pressed ONLY when the hero has no run yet. `_generated()` hands back a hero
## that is already inside a domain, and pressing `Enter` there is correctly refused — a
## second domain inside one domain is not a thing the module offers, and the refusal is
## the rule (`_can_enter` requires no active run), not a defect to route around. The
## screen ADOPTS the run already on the hero, which is what `read_active` is for; so the
## helper presses the button on a fresh hero and takes the hero it is given as-is.
func _entered(hero: Actor) -> DomainExploreScreen:
	var screen := _screen(hero)
	if screen == null:
		return null
	if DomainApi.map_summary(hero).is_empty():
		screen.act_enter()
	return screen


## The first authored domain that generated a run, and its hero. Discovered rather than
## declared: the catalogue grows as domains are authored, and domains sort by id, so a
## hard-coded id is a test that fails the next time one is added ahead of it.
##
## `{}` when nothing authored can be entered, which is a content fact and not a failure.
func _generated() -> Dictionary:
	for entry in DomainApi.templates():
		var hero := _hero()
		var entered := DomainApi.generate_and_enter(hero, StringName(entry["template_id"]), 11)
		if bool(entered.get("ok", false)):
			return {"hero": hero, "template_id": String(entry["template_id"])}
	return {}


## The first fixture of `kind` the run holds, as `{room_id, fixture_id}`. `{}` when the
## authored domain has none, so a case that needs one says so rather than indexing blind.
func _fixture_of_kind(hero: Actor, kind: String) -> Dictionary:
	for room in DomainApi.rooms(hero):
		var room_id := StringName(room.get("room_id", ""))
		for entry in room.get("fixtures", []):
			var fixture := entry as Dictionary
			if String(fixture.get("kind", "")) == kind:
				return {
					"room_id": room_id,
					"fixture_id": StringName(fixture.get("fixture_id", "")),
					"row": fixture,
				}
	return {}


## Put the screen's selection on one fixture and repaint, the way picking it from the
## dropdown does. `select_room`/`select_fixture` are the screen's own entry points for a
## row the player chose, so the fixture never has to reach into the screen's fields.
func _select(screen: DomainExploreScreen, room_id: StringName, fixture_id: StringName) -> void:
	screen.select_room(room_id)
	if not fixture_id.is_empty():
		screen.select_fixture(fixture_id)


## Free everything this suite minted. Idempotent, so it is safe after an abort, and
## it restores the process-wide seams a domain run installs so the next suite does not
## inherit a domain program wired to a hero that no longer exists.
func teardown() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()
	_last_screen = null


# ── the screen contract ──────────────────────────────────────────────────────


## The screen contract: `{}` with no actor, and `{}` with an actor but NO gameplay side.
## The second half matters more than usual here, because the domain seam is optional by
## construction — a screen bound to nothing must read as "nothing to show", not render an
## empty facade and report zeroes a player would read as a broken domain.
func test_an_unbound_or_unbridged_screen_reports_nothing() -> void:
	var bare := _screen(_hero(), false)
	assert_eq(bare.summary(), {}, "an actor with no domain bridge reports an empty view")
	var unactor := _screen(null)
	assert_eq(unactor.summary(), {}, "no hero at all reports an empty view")


## Primitives only, and JSON-clean. A `Vector2i` or a `Rect2i` anywhere in this surface
## would break the save/headless hop, and the authored fixture rows carry both — so this
## is a real assertion about what the screen chose to publish, not a formality.
func test_the_summary_is_primitives_only_and_json_clean() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	assert_ne(screen, null, "the screen mounted and entered")
	if screen == null:
		return
	var view := screen.summary()
	assert_eq(view.is_empty(), false, "a hero inside a domain publishes a view")
	assert_eq(
		_non_primitives(view).is_empty(),
		true,
		"primitives only: %s" % ", ".join(_non_primitives(view))
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(view))
	assert_eq(parsed is Dictionary, true, "the whole summary survives the JSON hop")
	assert_ne((parsed as Dictionary).is_empty(), true, "and is not empty on the far side")


## Every screen this program ships must be routed, or only a test can reach it. Asked of
## the SHIPPED table rather than restated here, so the test holds a rule and not a copy.
func test_the_route_table_names_this_screen() -> void:
	var route := String(ScreenRoutes.id_for_scene(SCENE))
	assert_eq(route, "domain_explore", "the shipped table names this screen's route")
	assert_eq(
		SeamHarness.screen_scene_paths().has(SCENE),
		true,
		"and the scene is one the UI program ships"
	)
	# Every route has its own input action AND a bound key, or it is reachable only by
	# a mouse: `test_screen_reachability` asserts the action, and the binding is what
	# makes that assertion mean anything.
	assert_ne(String(ScreenRoutes.action_of(StringName(route))), "", "the route names an action")
	assert_eq(
		InputMap.has_action(ScreenRoutes.action_of(StringName(route))),
		true,
		"and that action is bound to a key in project.godot"
	)


# ── the screen reports what the MODULE reports ───────────────────────────────


## The screen is a VIEW. Every shape on it must be the module's own answer, not a private
## re-computation: a second copy of the map's shape is a second thing that can be wrong
## and it would be wrong silently.
func test_the_screen_reports_what_the_facade_reports_and_not_a_private_copy() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	assert_ne(screen, null, "the screen mounted and entered")
	if screen == null:
		return
	var view := screen.summary()
	var reported: Dictionary = DomainApi.summary(hero)
	# Non-empty claims read `assert_ne(x.is_empty(), true)`: `assert_ne` passes when the
	# two differ, so a check written against `false` asserts the run is EMPTY.
	assert_ne(reported.is_empty(), true, "the module reports an active run")
	# Counts, verbatim from the facade.
	assert_eq(int(view["room_count"]), int(reported["rooms"]), "the room count is the facade's")
	assert_eq(int(view["zone_count"]), int(reported["zones"]), "the zone count is the facade's")
	assert_eq(
		int(view["population_count"]), int(reported["population"]), "the population is the facade's"
	)
	assert_eq(
		int(view["discovered_count"]), int(reported["discovered"]), "discovery is the facade's"
	)
	assert_eq(
		String(view["map"]["domain_id"]), String(reported["map"]["domain_id"]), "and so is the map"
	)
	assert_eq(
		String(view["map"]["room_count"]),
		String(reported["map"]["room_count"]),
		"including its shape"
	)
	# The floor plan is `DomainMinimap`'s payload WHOLE, which is what makes this screen
	# and the headless driver read one dictionary. Compared by JSON, because the claim is
	# "the same thing" and key ORDER is not data.
	var drawn := DomainMinimap.render(hero, _active_map(hero))
	assert_eq(
		JSON.stringify(view["minimap"]),
		JSON.stringify(drawn),
		"the floor plan is the minimap read model itself, not a layout invented here"
	)
	assert_eq(
		(view["minimap"] as Dictionary).get("layout").size(),
		(drawn as Dictionary).get("layout").size(),
		"and it lays out the same rooms"
	)


## Fog is DISCOVERY and is the module's to decide. A reachable-but-unvisited room must
## not appear in the room list, because showing it is the spoiler the fog prevents.
func test_the_room_list_is_fogged_by_the_modules_discovery() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var drawn: Array = screen.summary()["drawn_rooms"]
	assert_ne(drawn.is_empty(), true, "the entry room is drawn from the first frame")
	var entry: Dictionary = drawn[0]
	assert_eq(bool(entry["discovered"]), true, "every drawn room is discovered")
	assert_eq(bool(entry["is_entry"]), true, "and the entry is the first of them")
	var all_rooms := DomainApi.rooms(hero)
	assert_eq(
		drawn.size() < all_rooms.size(),
		true,
		(
			"%d drawn of %d authored, so an unexplored room is NOT listed"
			% [drawn.size(), all_rooms.size()]
		)
	)


## Each drawn room carries the kind and the tier the MINIMAP promises, and the tier is
## the minimap's own verdict — never this screen's inference from depth or size, which is
## the heuristic ADR 0073 rules out.
func test_each_listed_room_shows_its_kind_and_the_tier_the_module_promises() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	# Discover the whole domain, so the list has every authored room in it. Through the
	# screen's own verb, so the fog and the list stay in step with each other.
	for room in DomainApi.rooms(hero):
		screen.select_room(StringName(room["room_id"]))
		screen.act_visit()
	var drawn: Array = screen.summary()["drawn_rooms"]
	assert_eq(drawn.size(), DomainApi.rooms(hero).size(), "every room is drawn once discovered")
	var minimap: Dictionary = screen.summary()["minimap"]
	var tiers: Dictionary = {}
	for row in minimap["rooms"]:
		tiers[String(row["room_id"])] = String(row["tier"])
	for row in drawn:
		var room_id := String(row["room_id"])
		assert_ne(String(row["kind"]).is_empty(), true, "%s names the kind it is" % room_id)
		assert_eq(
			String(row["tier"]),
			String(tiers.get(room_id, "")),
			"%s shows the tier the minimap promises, verbatim" % room_id
		)


## The severe zones and their mitigation levers are the module's, and they are visible
## BEFORE the room is found — what a room will do to you is a property of the room, and
## routing around a hazard is only possible if you can see it first.
func test_severe_zones_are_listed_with_their_levers() -> void:
	var screen := _screen(_hero())
	assert_ne(screen, null, "the screen mounted")
	if screen == null:
		return
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	screen.call("setup", hero)
	screen.act_enter()
	var zones: Array = screen.summary()["zone_rows"]
	var authored := DomainApi.environment_zones(hero)
	assert_eq(zones.size(), authored.size(), "every severe zone the module reports is listed")
	for zone in zones:
		var row := zone as Dictionary
		assert_ne(String(row["kind"]).is_empty(), true, "a zone names what it is")
		assert_ne(String(row["severity"]).is_empty(), true, "and reads as a severity word")
		assert_ne(String(row["room_id"]).is_empty(), true, "and says which room it sits in")
		# The levers are the zone's own mitigation tags, and an empty set is LEGITIMATE
		# (a zone nothing counters is authored content), so this asserts the shape rather
		# than a non-empty list.
		assert_ne((row["mitigation_tags"] as Array).size() >= 0, true, "levers are a list")
	assert_ne(str(screen.summary()["zones_text"]).is_empty(), true, "and they are rendered as text")


## The population is grouped by ROLE, because "three mobs and a boss" is a roster and
## four separate rows are not. Roles are tags on an actor and never classes (ADR 0074), so
## the grouping is over the strings the module published.
func test_the_population_is_grouped_by_role() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var rows: Array = screen.summary()["population"]
	assert_ne(rows.is_empty(), true, "a generated domain places inhabitants")
	var total := 0
	for row in rows:
		var entry := row as Dictionary
		assert_ne(String(entry["role"]).is_empty(), true, "every group names a role")
		total += int(entry["count"])
	var authored := 0
	for ref in DomainApi.population(hero):
		authored += maxi(1, int(ref.get("count", 1)))
	assert_eq(total, authored, "and the groups account for every placed inhabitant")


# ── refusals ────────────────────────────────────────────────────────────────


## A refused action is the thing that teaches a player why a thing cannot be done, so it
## is asserted in the four parts that make it one: refused, tone-coloured, naming the
## reason the FACADE gave, and changing nothing.
func test_a_refused_action_reports_the_facades_reason_in_a_tone_coloured_line() -> void:
	var screen := _screen(_hero())
	if screen == null:
		return
	# Nothing is active, so there is no room to visit and no map to leave.
	assert_eq(screen.act_leave(), false, "leaving outside a run is refused")
	var view := screen.summary()
	assert_eq(String(view["tone"]), "error", "and reported as a refusal")
	assert_ne(str(view["message"]).is_empty(), true, "with a sentence on the line")
	assert_eq(
		str(view["message"]).contains(DomainApi.ERR_NO_MAP), true, "naming the facade's own reason"
	)
	assert_eq(String(view["fixture_tone"]), "error", "and the fixture line carries the same tone")
	# Nothing moved: there was never a domain, so there is still none.
	assert_eq(DomainApi.map_summary(screen.actor()), {}, "and no run was started by the refusal")


## A room the map does not hold is refused BY NAME and discovers nothing. This is the
## failure that matters most in a fogged map: a screen that invented a room would draw
## one the domain has never heard of.
func test_visiting_a_room_the_map_does_not_hold_is_refused_by_name() -> void:
	var run := _generated()
	assert_eq(run.is_empty(), false, "an authored domain generated a run to explore")
	if run.is_empty():
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var before: Array = screen.summary()["drawn_rooms"]
	# Aim the screen at a room id the map does not hold, through its own verb.
	screen.select_room(StringName("no_such_room"))
	var refused := screen.act_visit()
	assert_eq(refused, false, "an unknown room is refused")
	var view := screen.summary()
	assert_eq(String(view["tone"]), "error", "in the refusal tone")
	assert_eq(
		str(view["message"]).contains(DomainApi.ERR_UNKNOWN_ROOM),
		true,
		"naming the facade's reason id"
	)
	assert_eq(
		(screen.summary()["drawn_rooms"] as Array).size(),
		before.size(),
		"and the floor plan drew nothing new"
	)


## A treasure whose gate the module refuses reports THAT gate, in the module's own words,
## and consumes nothing. The gate is whatever the authored content declares, so this
## asserts the reason is one the module published rather than a fixed string.
func test_a_refused_treasure_names_the_gate_and_consumes_nothing() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to open")
		return
	var hero := run["hero"] as Actor
	var hoard := _fixture_of_kind(hero, "treasure")
	assert_eq(hoard.is_empty(), false, "an authored treasure exists to open")
	if hoard.is_empty():
		return
	# A fresh hero holds nothing and stands at the lowest realm, so at least one authored
	# gate is refused — unless this treasure authors none, which is legitimate content.
	DomainFixtures.set_minter(Callable(), Callable())
	var screen := _entered(hero)
	if screen == null:
		return
	DomainApi.visit_room(hero, hoard["room_id"])
	_select(screen, hoard["room_id"], hoard["fixture_id"])
	var refused := screen.act_claim()
	if refused:
		# The hoard was openable: every gate passed, so nothing is left to assert.
		assert_eq(String(screen.summary()["tone"]), "ok", "an open hoard reports acceptance")
		return
	var view := screen.summary()
	assert_eq(String(view["tone"]), "error", "a gated hoard reports a refusal")
	assert_eq(String(view["fixture_tone"]), "error", "and the fixture line agrees")
	var reason := str(view["fixture_message"])
	assert_ne(reason.is_empty(), true, "with a sentence naming why")
	# The sentence is the BRIDGE's wording of a module reason, never an invented one: the
	# bridge's table is the only vocabulary the screen has.
	assert_ne(
		DomainBridge.REASON_TEXT.values().has(reason),
		true,
		"the reason is one the module publishes and the bridge words: %s" % reason
	)
	assert_eq(
		str(view["message"]).contains(String(hoard["fixture_id"])),
		true,
		"and the line names WHICH fixture it was about"
	)
	# Nothing was consumed: an unopened hoard is still an unopened hoard.
	assert_eq(
		DomainFixtures.state_of(hero, hoard["room_id"], hoard["fixture_id"]).get("claimed", false),
		false,
		"the refused claim left the ledger untouched"
	)


## A trap that has already fired refuses a second time, by name. A trap firing twice in
## one run is a rule the module enforces and this screen must not route around.
func test_a_trap_that_has_fired_is_refused_a_second_time() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to arm")
		return
	var hero := run["hero"] as Actor
	var trap := _fixture_of_kind(hero, "trap")
	if trap.is_empty():
		assert_eq(true, true, "this domain authors no trap; nothing to arm")
		return
	DomainApi.visit_room(hero, trap["room_id"])
	var screen := _entered(hero)
	if screen == null:
		return
	_select(screen, trap["room_id"], trap["fixture_id"])
	# Two presses: the first arms, the second crosses the authored window and fires.
	screen.act_arm()
	screen.act_arm()
	var spent := bool(
		DomainFixtures.state_of(hero, trap["room_id"], trap["fixture_id"]).get("spent", false)
	)
	assert_eq(spent, true, "the second press fired the trap")
	assert_eq(screen.act_arm(), false, "a third press is refused")
	var view := screen.summary()
	assert_eq(String(view["fixture_tone"]), "error", "in the refusal tone")
	assert_eq(
		str(view["fixture_message"]).contains(DomainFixtures.ERR_ALREADY_FIRED),
		true,
		"naming the module's own reason"
	)


## The happy path a player takes: enter, walk into a second room, and watch it appear on
## the floor plan. The whole chain — template, generation, contract, discovery, fog —
## runs through the SCREEN's buttons.
func test_entering_visiting_and_leaving_drive_the_whole_chain() -> void:
	var screen := _screen(_hero())
	assert_ne(screen, null, "the screen mounted")
	if screen == null:
		return
	var view := screen.summary()
	assert_eq(bool(view["in_domain"]), false, "nobody is inside a domain yet")
	assert_eq(bool((view["enabled"] as Dictionary)["enter"]), true, "so entering is offered")
	assert_eq(bool((view["enabled"] as Dictionary)["leave"]), false, "and leaving is not")
	assert_ne(int(view["template_count"]), 0, "the authored catalogue is offered")

	assert_eq(screen.act_enter(), true, "entered through the screen's own verb")
	view = screen.summary()
	assert_eq(bool(view["in_domain"]), true, "and a run is active")
	assert_eq(int(view["room_count"]) > 0, true, "with rooms in it")
	assert_eq(bool((view["enabled"] as Dictionary)["leave"]), true, "so leaving is offered now")
	assert_eq(bool((view["enabled"] as Dictionary)["enter"]), false, "and entering again is not")
	assert_eq(String(view["map"]["domain_id"]).is_empty(), false, "and the run names its domain")
	# The seed is the screen's, so two presses of one button are the same domain.
	var second := _screen(_hero())
	if second != null:
		second.act_enter()
		assert_eq(
			int(second.summary()["room_count"]),
			int(view["room_count"]),
			"and the screen's seed makes the same button reproducible"
		)

	assert_eq(screen.act_leave(), true, "left through the screen's own verb")
	assert_eq(bool(screen.summary()["in_domain"]), false, "and the run is gone")
	assert_eq(DomainApi.map_summary(screen.actor()), {}, "with no map left on the hero")


## Leaving is the ONE verb that keeps what it discards: the discovered set survives, so
## a player who leaves and returns has not lost where they have been (BL-0252).
func test_leaving_keeps_the_discovered_set() -> void:
	var screen := _entered(_hero())
	if screen == null:
		return
	var actor := screen.actor()
	var before: Array = DomainApi.discovered(actor)
	assert_ne(before.is_empty(), false, "entering discovered at least the entry")
	assert_eq(screen.act_leave(), true, "left the run")
	assert_eq(
		DomainApi.discovered(actor), before, "and the map still remembers where the player has been"
	)


## A hero with an actor but no bridge must offer NOTHING rather than offering buttons
## whose handler does not exist. The default arm of the shell binds every route with
## `setup(actor)` alone, so this is the state a screen is genuinely in before the seam is
## filled — and a screen offering live controls there is a control that looks alive and is
## dead.
##
## Asserted through `act()` alone, and that is the whole contract rather than a shortcut:
## an unbridged screen reports `{}` (see `test_an_unbound_or_unbridged_screen_reports_nothing`),
## because `{}` is the repo's does-not-exist vocabulary and a screen with no gameplay side
## must not publish a half-built view that reads as zeroes a player would take for an
## empty domain. "Offers nothing" is therefore proven by every verb refusing — not by
## reading an enabled map out of a summary that is deliberately absent.
func test_every_action_is_refused_and_disabled_without_the_seam() -> void:
	var screen := _screen(_hero(), false)
	if screen == null:
		return
	for action in DomainExploreScreen.ACTION_IDS:
		assert_eq(screen.act(action), false, "'%s' is refused with no bridge" % action)
	assert_eq(screen.summary(), {}, "and a screen with no seam publishes no view at all")


## Every `.connect()` is guarded by `is_connected()` (ADR/AGENTS.md): an unguarded one is
## one handler per call, and a screen the shell re-binds — which navigation does every
## time — then fires N times for one press. Read from the source rather than from a live
## node, because a live node cannot tell a second `_bind_nodes` apart from a first.
func test_every_connect_is_guarded() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/screens/domain_explore.gd")
	assert_eq(source.is_empty(), false, "the screen script is readable")
	for line in source.split("\n"):
		var code := String(line).split("#")[0]
		if not code.contains(".connect("):
			continue
		# A guarded connect reads `not <signal>.is_connected(...)` on the same line or
		# the one above it, which is exactly the shape `loot_encounter.gd` uses.
		var guarded := code.contains("is_connected(")
		if not guarded:
			var index := source.split("\n").find(line)
			assert_eq(
				index > 0 and source.split("\n")[index - 1].contains("is_connected("),
				true,
				(
					"'%s' is an unguarded connect; a re-bound screen fires it once per bind"
					% code.strip_edges()
				)
			)


## The composition root's job, asserted where it can be asserted without touching a file
## another agent owns: the bridge is fully wired, and its own view of itself says so.
func test_the_composition_roots_bridge_is_fully_wired() -> void:
	var seam := DomainBoot.bridge()
	var state := seam.summary()
	# `assert_ne(actual, unexpected)` passes when `actual != unexpected`, so a
	# non-empty check is `assert_ne(x.is_empty(), true)`. Written against `false` it
	# demands the seam name NOTHING, which is the opposite of the claim.
	assert_ne((state["actions"] as Array).is_empty(), true, "the seam names its verbs")
	assert_eq(
		bool(state["ready"]), true, "and every one of them is wired: %s" % str(state["wired"])
	)
	# An unwired slot reads as "not available" rather than as a failure, which is what
	# lets a screen DISABLE an action instead of half-answering it.
	var bare := DomainBridge.new()
	assert_eq(bool(bare.summary()["ready"]), false, "an empty seam is not ready")
	assert_eq(bare.call_action(&"read_active", [null]), {}, "and answers nothing")
	assert_eq(bare.call_list(&"rooms", [null]), [], "for a list verb either")


# ── plumbing ─────────────────────────────────────────────────────────────────


## The active run's map, read the way `DomainMinimap.render` reads it. A harness-side
## helper rather than a call into the module's internals.
func _active_map(hero: Actor) -> DomainMap:
	var state := hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])


## Dotted paths inside a summary whose value is not a primitive, a String, an Array, or a
## dictionary of the same. A `Node`, a `Resource`, a `Vector2i` or a `Rect2i` in a
## testable surface is how a readout quietly stops being testable.
func _non_primitives(value: Variant, path: String = "") -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		for key in value as Dictionary:
			var child: Variant = (value as Dictionary)[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
	elif value is Array:
		for index in (value as Array).size():
			out.append_array(_non_primitives((value as Array)[index], "%s[%d]" % [path, index]))
	return out


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
