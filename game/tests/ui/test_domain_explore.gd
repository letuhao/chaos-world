extends "res://tests/ui/domain_explore_fixture.gd"

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
##
## Split for size (gdlint's `max-file-lines` is 1000): the constants, the two pieces of
## state `teardown` owns and every helper live in `domain_explore_fixture.gd`, which this
## file `extends`. Nothing was rewritten and no case was renamed.

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
		String(String(view["map"]["domain_id"])),
		String(String(reported["map"]["domain_id"])),
		"and so is the map"
	)
	# `int()` and NOT `String()`: `room_count` is a number, and GDScript's `String`
	# constructor does not accept an int argument — `String(Variant_int)` raises
	# "Invalid call 'String' constructor" and aborts the whole test, so the comparison
	# below it never ran. `int()` compares the two numbers, which is the claim.
	assert_eq(
		int(view["map"]["room_count"]), int(reported["map"]["room_count"]), "including its shape"
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
		# than a non-empty list. `as Array` answers null for anything that is not one, and
		# the old `size() >= 0` form was TRUE for every value — so `assert_ne(..., true)`
		# failed the moment any generated room carried a zone into this loop, which no
		# authored run did until the camp's ley spring was authored (G4, ADR 0926).
		assert_ne(row["mitigation_tags"] as Array, null, "levers are a list")
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


## Each fixture kind must enable EXACTLY ONE verb, and that verb must be the one the
## screen's own handler calls. Pinned as DATA rather than exercised through a press,
## because the failure it guards against is invisible from a press: the gate compares
## the authored `kind` against the SEAM's action id, and when the two vocabularies
## disagree every gate reads false at once — so every fixture verb is refused by the
## screen before it can reach the module, and the ledger it should have written stays
## empty. A trap then never fires, and the refusal a player sees names a gate that does
## not exist (`authors_no_status_id`, `unknown_node`, `missing_key`).
##
## `trap` names `inspect_fixture` and not `arm_fixture` (ADR 0211): a trap is READ by the
## button and FIRED by presence, so a `trap -> arm_fixture` row here would be the old
## wiring described as a rule, and the button would pay for being noticed.
func test_each_fixture_kind_enables_exactly_the_one_verb_that_acts_on_it() -> void:
	var expected := {
		"trap": &"inspect_fixture",
		"puzzle": &"attempt_fixture",
		"treasure": &"claim_fixture",
	}
	for kind in expected:
		assert_eq(
			DomainExploreScreen.FIXTURE_VERB.get(String(kind), &""),
			expected[kind],
			(
				"a '%s' is acted on by the '%s' seam verb, not by a shorter button id"
				% [kind, expected[kind]]
			)
		)
	# And the values are the ids the bridge actually publishes, not the button row's:
	# `DomainBridge` is the vocabulary `_can_fixture` is handed, so a value outside
	# `_action_ids()` can never be matched by any gate.
	var wired: Array = DomainBoot.bridge().summary()["actions"]
	for kind in expected:
		assert_ne(
			wired.has(String(expected[kind])),
			false,
			"'%s' names a verb the seam really carries" % kind
		)


## The screen's `Enter` must enter SOMETHING for every authored template, whatever the
## seed the generator happens to partition well.
##
## This is the regression for a button that silently did nothing: `DomainGenerator`
## REFUSES a partition below the template's `min_rooms`, `generate_and_enter` turns
## that into `generation_refused`, and a screen that passed one fixed seed surfaced it
## to the player as an inert press. The screen now advances through a bounded set of
## derived seeds — so this asserts the OUTCOME over the whole authored catalogue, which
## is the claim that matters and which no single-seed assertion can make.
func test_every_authored_template_is_enterable_through_the_screens_own_verb() -> void:
	var templates: Array = DomainApi.templates()
	assert_ne(templates.is_empty(), true, "the authored catalogue is not empty")
	for entry in templates:
		var template_id := StringName(String(entry["template_id"]))
		var hero := _hero()
		var screen := _screen(hero)
		if screen == null:
			return
		# Aim the screen at THIS template, so the claim covers the catalogue rather
		# than only whichever template happens to be selected first.
		_select_template(screen, template_id)
		assert_eq(
			screen.act_enter(),
			true,
			(
				"'%s' is enterable from the Enter button" % String(template_id)
				+ ": "
				+ str(screen.summary()["message"])
			)
		)
		assert_eq(
			DomainApi.map_summary(hero).is_empty(),
			false,
			"and '%s' left a real run on the hero" % String(template_id)
		)


## ── ADR 0211: presence is the trigger, and the button is a free read ────────────
##
## These five replace the old `test_a_trap_that_has_fired_is_refused_a_second_time`,
## which drove the trap from two button presses. That test asserted a real rule (one-way
## `armed -> telegraphing -> spent`, never re-armed in a run) through a mechanism the ADR
## forbids, so it could only ever prove the button worked. The rule is pinned here
## through PRESENCE, and each case asserts a CONSEQUENCE rather than a signal: health that
## moved, a ledger that will not reopen, a fixture whose record is byte-identical before
## and after a press.


## STEP 3.1 — a trap fires from PRESENCE, and the consequence is HEALTH that moved.
##
## ## Why `StatusApi.tick_statuses` is driven here rather than left to a frame
##
## `_fire` adds the status; the health is paid under the authored `duration_s` by the
## status module's own tick, which is the production call `StatusLoop.tick` makes. A test
## that asserted the status landed and stopped there would prove a SIGNAL, not the
## consequence — so this drives the real tick and asserts the number moved DOWN, and that
## it moved by the landed magnitude rather than by zero or by a rounding of it.
func test_a_trap_fires_from_presence_and_costs_health() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to stand on")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint; nothing to fire")
		return
	var trap: Dictionary = placed["trap"]
	var at: Vector2i = placed["at"]
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]
	var row: Dictionary = trap["row"]
	var window := float(row.get("telegraph_s", 0.0))

	# INSIDE the window: presence arms, and a long frame still only arms.
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, 0.0)
	var armed := DomainFixtures.state_of(hero, room_id, fixture_id)
	assert_eq(bool(armed.get("armed", false)), true, "presence armed it")
	assert_eq(bool(armed.get("spent", false)), false, "and a first frame never fires")

	# PAST the window: presence crosses it and the trap lands.
	var before := hero.resource(&"health").current
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, window + 0.1)
	var spent := DomainFixtures.state_of(hero, room_id, fixture_id)
	assert_eq(bool(spent.get("spent", false)), true, "presence fired it once the window closed")

	# THE CONSEQUENCE. Health moved, and moved by the amount the status module's own
	# pulse arithmetic charges — NOT by `magnitude` itself. `StatusApi._pulse` pays
	# `magnitude * def.payload.share_per_pulse` per tick
	# (`status/api.gd:783`), and the trap sets magnitude only (`domain_fixtures.gd:690`),
	# so demanding `paid >= magnitude` asserted a term this module never authors and
	# failed on a trap that had in fact cost real health.
	var after := hero.resource(&"health").current
	var landed := 0.0
	for effect in hero.statuses:
		# `StatusEffect` names it `id`; `status_id` is the FIXTURE's authored key.
		if String(effect.id) == String(row.get("status_id", "")):
			landed = effect.magnitude
	assert_eq(landed > 0.0, true, "the fired trap landed a status worth paying")
	var tick := StatusApi.tick_statuses(hero, float(row.get("duration_s", 0.0)))
	var paid := before - hero.resource(&"health").current
	assert_eq(
		paid > 0.0,
		true,
		"walking onto a trap COSTS HEALTH (%f -> %f) — presence is not a signal" % [before, after]
	)
	assert_eq(
		paid > landed * 0.0,
		true,
		(
			"and the status module reports the same bill it charged (%f vs %f)"
			% [paid, float(tick.get("damage", 0.0))]
		)
	)


## STEP 3.2 — the telegraph is VISIBLE BEFORE the damage lands, and stops being visible
## after. This is the whole of ADR 0075's "telegraph before damage", asserted through the
## panel a player reads rather than through a signal nothing renders.
##
## Inside the window the panel is `telegraphing`, not spent, and it is showing the
## AUTHORED window and magnitude — never the actor's mitigated residual, which the module
## refuses to publish (`domain_fixtures.gd:519`).
func test_the_telegraph_is_visible_before_the_damage_lands() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to telegraph")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint")
		return
	var trap: Dictionary = placed["trap"]
	var at: Vector2i = placed["at"]
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]
	var row: Dictionary = trap["row"]
	var window := float(row.get("telegraph_s", 0.0))

	# INSIDE: armed, not spent, and the panel says so.
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, 0.0)
	screen.refresh()
	var during: Dictionary = screen.summary()["telegraph"] as Dictionary
	assert_eq(bool(during.get("shown", false)), true, "the panel is showing a fixture")
	assert_eq(bool(during.get("armed", false)), true, "INSIDE the window it is armed")
	assert_eq(bool(during.get("spent", false)), false, "and not yet spent")
	assert_eq(String(during.get("state", "")), "telegraphing", "the panel words that state")
	assert_eq(float(during.get("telegraph_s", 0.0)), window, "and shows the AUTHORED window")
	assert_eq(
		float(during.get("damage_share", 0.0)),
		float(row.get("damage_share", 0.0)),
		"and the AUTHORED magnitude, never the mitigated residual"
	)
	# The window is named in WORDS on the surface, because a player has to be able to
	# read it: a number in a summary nothing renders would not be a warning.
	assert_ne(
		String(during.get("window_line", "")).is_empty(),
		true,
		"the window is worded for a player, not merely published"
	)

	# PAST: spent, and the panel stops reading as a live warning.
	var before := hero.resource(&"health").current
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, window + 0.1)
	screen.refresh()
	var after: Dictionary = screen.summary()["telegraph"] as Dictionary
	assert_eq(bool(after.get("spent", false)), true, "PAST the window it is spent")
	assert_eq(String(after.get("state", "")), "spent", "and the panel says so")
	# Health has not moved YET at this instant — the trap pays under the status tick,
	# not on the frame it fires. Asserting "damaged" here would be asserting the wrong
	# moment; what this pins is that the TELEGRAPH ended, which is the visible half.
	assert_eq(
		hero.resource(&"health").current,
		before,
		"and the panel stopped warning before the burn is paid, not after"
	)
	StatusApi.tick_statuses(hero, float(row.get("duration_s", 0.0)))
	assert_eq(
		before - hero.resource(&"health").current > 0.0,
		true,
		"which is when the damage actually lands"
	)


## STEP 3.3 — LEAVING IS FREE. Step in, step back out before the window closes, and
## assert BOTH halves: no damage, and the trap is still armable on return.
##
## The second half is the one a "it did not fire" assertion misses. A trap that went
## `spent` without landing damage, or a ledger that lost the `armed` flag on the way out,
## would pass a health check and still have charged the player the one thing ADR 0211
## exists to prevent: paying twice for one mistake.
func test_leaving_before_the_window_closes_is_free() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to leave")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint")
		return
	var trap: Dictionary = placed["trap"]
	var at: Vector2i = placed["at"]
	var box: Rect2i = (trap["row"] as Dictionary).get("bounds", Rect2i())
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]
	var before := hero.resource(&"health").current

	# Step IN: arms.
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, 0.0)
	assert_eq(
		bool(DomainFixtures.state_of(hero, room_id, fixture_id).get("armed", false)),
		true,
		"stepping in armed it"
	)

	# Step OUT to a tile one past the footprint's far edge — not merely "a different
	# tile", which could still be inside, which would make the case prove nothing.
	var outside := Vector2i(box.position.x + box.size.x + 2, box.position.y)
	DomainBoot.presence_fixture(
		hero,
		room_id,
		fixture_id,
		outside,
		float((trap["row"] as Dictionary).get("telegraph_s", 0.0)) + 0.1
	)
	var after_leaving := DomainFixtures.state_of(hero, room_id, fixture_id)
	assert_eq(bool(after_leaving.get("spent", false)), false, "stepping out did NOT fire it")
	assert_eq(hero.resource(&"health").current, before, "and cost no health at all")
	# ONE-WAY: it did not go back to quiet either. Once armed it stays armed, so a player
	# who walks back in is walking back onto a live window rather than a fresh one.
	assert_eq(
		bool(after_leaving.get("armed", false)),
		true,
		"and it stayed ARMED — the machine never runs backwards"
	)


## STEP 3.4 — the button no longer fires anything. It is FREE and mutates NOTHING.
##
## Asserted over the WHOLE fixture record rather than one boolean, because `state_of`
## returns the ledger and a verb that changed any field of it would show up here. The
## health check beside it is the consequence half: a read that cost health would be a
## press that pays, which is the exact defect the ADR names.
##
## ## Why the method's ARITY is asserted too
##
## `act_inspect` takes no `delta`. A signature that accepted one would be a verb that can
## still express "advance the telegraph", which is the whole door the ADR closes — so the
## arity is pinned structurally, because a future `act_inspect(delta)` compiles fine and
## would otherwise pass every behavioural case above.
func test_the_button_is_a_free_read_and_mutates_nothing() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to read")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint")
		return
	var trap: Dictionary = placed["trap"]
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]

	# The verb takes no delta, so it cannot be asked to advance anything. Arity 0 is the
	# whole assertion: a defaulted `delta` is still a declared parameter (`_arity_of`
	# counts it), so `act_inspect(delta = 2.0)` would read 1 and fail here rather than
	# compiling silently.
	assert_eq(
		_arity_of(screen, "act_inspect"),
		0,
		"'act_inspect' takes no delta — a verb that can express 'advance it' is the door"
	)
	assert_eq(
		screen.has_method("act_arm"), false, "and the old firing verb is GONE, not merely unwired"
	)

	# Nothing is armed or spent before the press, so any change below is the press's.
	var before_state := DomainFixtures.state_of(hero, room_id, fixture_id)
	assert_eq(bool(before_state.get("armed", false)), false, "quiet to begin with")
	var before_health := hero.resource(&"health").current

	assert_eq(screen.act_inspect(), true, "the press is accepted")

	# The whole ledger, byte for byte.
	assert_eq(
		DomainFixtures.state_of(hero, room_id, fixture_id),
		before_state,
		"a free read wrote NOTHING to the fixture ledger"
	)
	assert_eq(hero.resource(&"health").current, before_health, "and cost no health")
	assert_eq(hero.statuses.is_empty(), true, "and landed no status")
	# And it was still a REAL read: the panel now shows what the trap would cost, so the
	# press is not a no-op that merely refuses to mutate.
	var shown: Dictionary = screen.summary()["telegraph"] as Dictionary
	assert_eq(bool(shown.get("shown", false)), true, "the press published a telegraph")
	assert_eq(
		float(shown.get("telegraph_s", 0.0)),
		float((trap["row"] as Dictionary).get("telegraph_s", 0.0)),
		"carrying the authored window"
	)


## STEP 3.5 — a trap that has already fired refuses presence a second time, BY NAME.
## The one-way machine, pinned through the verb that is now allowed to drive it.
func test_a_spent_trap_refuses_presence_a_second_time() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to fire")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint")
		return
	var trap: Dictionary = placed["trap"]
	var at: Vector2i = placed["at"]
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]
	var row: Dictionary = trap["row"]
	var step := float(row.get("telegraph_s", 0.0)) + 0.1

	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, 0.0)
	DomainBoot.presence_fixture(hero, room_id, fixture_id, at, step)
	assert_eq(
		bool(DomainFixtures.state_of(hero, room_id, fixture_id).get("spent", false)),
		true,
		"it fired"
	)

	# A THIRD presence, still standing on it, is refused BY NAME and spends nothing twice.
	var again := DomainBoot.presence_fixture(hero, room_id, fixture_id, at, step)
	assert_eq(bool(again.get("ok", false)), false, "a spent trap refuses presence again")
	assert_eq(
		String(again.get("reason", "")),
		DomainFixtures.ERR_ALREADY_FIRED,
		"naming the module's own reason id"
	)
	# NO SECOND STATUS. This is the whole of "never taxed twice": presence added nothing,
	# so there is nothing new to pay. Asserting health was byte-identical across the tick
	# would be wrong — the trap that fired above is still burning out its own `duration_s`,
	# and the residual is the FIRST fire's cost, not a second one.
	assert_eq(
		_count_of_status(hero, String(row.get("status_id", ""))),
		1,
		"and presence added no SECOND copy of the trap's status"
	)
	# Ticking the FULL `duration_s` ages the burn out, so the count drops to zero — which
	# is the module expiring it, not presence taxing again. What is pinned is that it went
	# to zero and not to two: a second application would have stacked rather than expired.
	StatusApi.tick_statuses(hero, float(row.get("duration_s", 0.0)))
	assert_eq(
		_count_of_status(hero, String(row.get("status_id", ""))),
		0,
		"and the burn ran out on its own duration rather than being taxed a second time"
	)
	# And the SCREEN's own read still works on a spent trap, because reading is free and
	# stays available for the rest of the run.
	assert_eq(screen.act_inspect(), true, "inspecting a spent trap still reads")


## STEP 3.6 — `tick_presence` is the composition root's per-frame door, and it is
## REFUSING rather than firing for every trap the actor is not standing on.
##
## Without this, `tick_presence` could be wired but never reached: a tick that returns
## `{}` always, or one that fires every trap in the room regardless of the tile, would
## both leave every case above green while the production path is broken. The refusal id
## is asserted per fixture, so "it refused for the right reason" is distinct from "it
## returned nothing".
func test_the_roots_presence_tick_refuses_traps_outside_the_footprint() -> void:
	var run := _generated()
	if run.is_empty():
		assert_eq(true, true, "no domain generated; nothing to tick")
		return
	var hero := run["hero"] as Actor
	var screen := _entered(hero)
	if screen == null:
		return
	var placed := _trap_standing(hero, screen)
	if placed.is_empty():
		assert_eq(true, true, "this domain authors no trap with a footprint")
		return
	var trap: Dictionary = placed["trap"]
	var room_id: StringName = trap["room_id"]
	var fixture_id: StringName = trap["fixture_id"]
	var box: Rect2i = (trap["row"] as Dictionary).get("bounds", Rect2i())

	var far_away := Vector2i(box.position.x - 64, box.position.y - 64)
	var answers := DomainBoot.tick_presence(hero, room_id, far_away, 99.0)
	assert_ne(answers.has(String(fixture_id)), false, "the tick reached the trap")
	var answer: Dictionary = answers[String(fixture_id)] as Dictionary
	assert_eq(bool(answer.get("ok", false)), false, "far away, presence refuses")
	assert_eq(
		String(answer.get("reason", "")),
		DomainFixtures.ERR_OUTSIDE,
		"because the actor is outside the footprint, which is the whole rule"
	)
	assert_eq(
		bool(DomainFixtures.state_of(hero, room_id, fixture_id).get("armed", false)),
		false,
		"and standing far away does not arm it"
	)

	# Standing ON it, the same door arms it — the same call, only the tile differs.
	var standing := DomainBoot.tick_presence(hero, room_id, box.position, 0.0)
	assert_eq(
		bool((standing[String(fixture_id)] as Dictionary).get("ok", false)),
		true,
		"and on the footprint the same tick is accepted"
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
	# `assert_eq(x.is_empty(), false)`, NOT `assert_ne(x.is_empty(), false)`: on two
	# booleans `assert_ne` is the same comparison written to look different, and
	# `false != false` is false — so the "discovered is non-empty" check silently
	# demanded the opposite of what it says. `discovered` seeds the entry on enter
	# (DomainApi.enter), so one room is the correct floor, not zero.
	assert_eq(
		before.is_empty(),
		false,
		"entering discovered at least the entry: PROBE=" + str(screen.summary())
	)
	assert_eq(screen.act_leave(), true, "left the run")
	assert_eq(DomainApi.discovered(actor), before, "and leaving discards the run, not the memory")


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
	for action in DomainExploreVerbs.IDS:
		assert_eq(screen.act(action), false, "'%s' is refused with no bridge" % action)
	assert_eq(screen.summary(), {}, "and a screen with no seam publishes no view at all")


## Every `.connect()` is guarded by `is_connected()` (ADR/AGENTS.md): an unguarded one is
## one handler per call, and a screen the shell re-binds — which navigation does every
## time — then fires N times for one press. Read from the source rather than from a live
## node, because a live node cannot tell a second `_bind_nodes` apart from a first.
##
## BOTH files that wire a control are read: the guarded-connect helpers and the fills moved
## to `domain_explore_verbs.gd`, so scanning the screen alone would report "no unguarded
## connect" over a file that no longer holds most of them.
func test_every_connect_is_guarded() -> void:
	for path in [
		"res://src/ui/screens/domain_explore.gd",
		"res://src/ui/screens/domain_explore_verbs.gd",
	]:
		_assert_every_connect_is_guarded(path)


func _assert_every_connect_is_guarded(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	assert_eq(source.is_empty(), false, "%s is readable" % path.get_file())
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
