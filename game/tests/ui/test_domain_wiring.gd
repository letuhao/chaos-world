extends TestCase

## PROOF AT THE PRODUCTION SEAM: the domain surface is REACHABLE, POPULATED and WIRED
## through the composition root a player actually runs.
##
## ## Why this suite exists at all
##
## The audit found the `domain` module comprehensively BUILT and comprehensively UNWIRED:
## the route table registered `domain_explore` but `ItemWorkbenchApp._bind_route_screen` had
## no arm for it (so `_bridge` stayed null, every verb was dead, `_can_enter()` false and
## the header read "Domains — none authored"); `DomainBoot.install` had zero callers; and
## `DomainSpawner.spawn_map` and `EnvironmentField.apply` had zero production callers, so a
## run had no inhabitants and no hazards.
##
## `test_domain_explore.gd` builds its own bridge (`screen.call("bind_bridge",
## DomainBoot.bridge())`), which proves the SCREEN works given a bridge — it proves nothing
## about whether a player can OBTAIN one. **This suite goes through production**: it boots
## the real `ItemWorkbenchApp` scene, drives the real navigation to the real domain route,
## and asserts on the screen the composition root itself mounted. Remove any of the three
## production wires and this file fails; the screen suite does not.
##
## ## What each case proves
##
##  - the ROUTE mounts a screen whose bridge is `ready` with every seam `wired` — i.e.
##    `_bind_route_screen`'s arm ran, through the real route, on the real root;
##  - `DomainBoot.install` ran (called from the root's attach list), so `DomainSpawner`
##    has a minter and can mint a non-null `Actor`;
##  - entering through the screen's own `Enter` button mints REAL inhabitants — the
##    `DomainSpawner.spawn_map` count equals the `DomainApi.population` count, and those
##    are `Actor`s, not the map's dictionaries;
##  - a severe zone authored in the entered map applies a real status to the hero.
##
## Every claim is made through a public verb on a mounted node. `tests/` is the `harness`
## unit and may reach `app/` and `domain/` freely (`tools/arch/enforce.py`); the SCREEN it
## drives may not, which is the point.

const DOMAIN_ROUTE := &"domain_explore"
## The screen scene the route mounts, asserted through the route table rather than
## restated — a second copy of the table is a second thing that can be wrong.
const DOMAIN_SCENE := "res://src/ui/screens/domain_explore.tscn"
## One seed, held here, so "the same button is the same domain" is a claim this suite can
## make about its own two entries. Matches `DomainExploreScreen.DEFAULT_SEED`.
const SEED := 20261003
## How many authored templates this suite walks before it stops looking for one that
## generates. Bounded and named: the generator is REFUSAL-first by design, so a walk that
## never found one would be an unbounded loop. Three attempts against a catalogue of three
## is slack, not a tuned budget.
const MAX_TEMPLATE_ATTEMPTS := 4

## The mounted composition root, reused across cases so the app is booted once. Freed
## centrally in `teardown()` because the call sites are interleaved and a case that
## returned early would skip a free at its end.
var _harness: SeamHarness = null
## The hero the composition root built, which is the actor every domain verb acts on.
var _hero: Actor = null
## Every screen this suite drove, so teardown frees the subtree the runner would
## otherwise keep resident for the rest of the run.
var _born: Array[Node] = []

# ── the production seam ───────────────────────────────────────────────────────


## The real composition root, booted the way a player boots it, or null with a counted
## failure. `_seam` refuses rather than returning a half-booted root, because every
## assertion below is about the wiring and a claim made on a root that never booted is a
## claim about nothing.
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


## Navigate to the domain route through the real `navigate_to`, the ONE navigation
## mechanism a player drives, and hand back the screen the ROOT mounted. The screen is
## read off the stack, never instantiated here: a screen this suite instantiated itself
## could never prove the root bound it.
func _domain_screen() -> DomainExploreScreen:
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
	assert_eq(
		live.scene_file_path,
		DOMAIN_SCENE,
		"and it is the domain screen the route claims to mount, not some other screen"
	)
	assert_eq(
		harness.bound_actor(live),
		_hero,
		"bound to the app's own hero, so the bridge acts on the body the player plays"
	)
	_born.append(live)
	return live as DomainExploreScreen


# ── the three production wires ────────────────────────────────────────────────


## BLOCKER 1. The route mounts a BRIDGED screen. `bridge.ready == true` and `wired` is
## non-empty are the seam's OWN verdict on its own callables, read through the mounted
## screen's summary — so this cannot pass for a screen the suite bound itself.
func test_the_domain_route_mounts_a_screen_whose_bridge_is_fully_wired() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain route mounted the domain screen")
	if screen == null:
		return
	var view := screen.summary()
	assert_ne(view.is_empty(), true, "a bridged screen publishes a view, not an empty one")
	var seam: Dictionary = view.get("bridge", {}) as Dictionary
	assert_ne(
		(seam.get("wired", []) as Array).is_empty(),
		true,
		"the mounted screen's bridge names the verbs it can reach: %s" % str(seam.get("wired", []))
	)
	assert_eq(
		bool(seam.get("ready", false)),
		true,
		"and every verb the seam advertises is wired: %s" % str(seam.get("wired", []))
	)


## BLOCKER 2. The root installed the spawner's minter. A non-null `Actor` out of
## `DomainSpawner.spawn` is only possible once `DomainBoot.install` ran — without the
## minter the spawner falls back to its core-only default, and the suite proves the FULL
## spine is installed by asking the spawner for a def through the real seam.
##
## The claim is made on the SPAWNER, not on a screen, because the minter is a process-wide
## seam installed by the root's attach list — the same place `NpcBoot.install` runs.
func test_the_root_installed_the_spawner_minter_so_an_inhabitant_can_be_minted() -> void:
	var harness := _seam()
	assert_eq(harness != null, true, "the composition root booted, so install ran on its hero")
	if harness == null:
		return
	# Ask the spawner for the first authored inhabitant, through the module's own facade-
	# free entry. `DomainSpawner` is reached here because `tests/` is the harness unit and
	# may name any module; the SCREEN may not, which is the whole point of the seam.
	var def := _first_inhabitant_def()
	assert_eq(def != null, true, "an authored inhabitant ships to spawn from")
	if def == null:
		return
	var minted := DomainSpawner.spawn(def, DomainRoles.MOB)
	assert_ne(minted, null, "DomainSpawner returns a real Actor with the minter installed")
	if minted == null:
		return
	assert_eq(
		DomainSpawner.role_of(minted),
		DomainRoles.MOB,
		"and it carries the role the spawner stamped, so it is an inhabitant and not a stub"
	)


## BLOCKER 3. Entering mints REAL inhabitants, and their count matches the map's authored
## population. The count equality is the whole claim: `DomainApi.population` is the map's
## spawn REFS, and the screen used to render those rows while nothing stood behind them.
## Matching the count proves the rows and the bodies are the same set.
##
## Entered through the BRIDGE's `enter` verb — which is the exact callable the screen's
## `Enter` button calls (`DomainExploreScreen._enter_with_a_generating_seed`), so this is
## the production path, and its answer is the one a screen sees. The minted `Actor`s are
## read from that answer because the `Actor` list is what `DomainBoot.enter_domain` now
## returns; a player sees them through the same screen the route mounted.
func test_entering_a_domain_mints_real_actors_one_per_authored_ref() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	# A FAILURE, not a skip. `assert_eq(true, true, ...)` here meant that when no template
	# generated at this seed the whole case — the proof that entering MINTS AN ACTOR —
	# passed without asserting anything, which is the same "green that proved nothing"
	# defect this suite was written to replace. A content gap must be loud.
	assert_ne(
		template_id,
		"",
		"an authored template generates at this seed; without one this case cannot run"
	)
	if template_id.is_empty():
		return
	# The bridge's `enter` — the production callable behind the screen's Enter button.
	var seam := DomainBoot.bridge()
	var entered: Dictionary = seam.call_action(&"enter", [_hero, template_id, SEED])
	assert_eq(
		bool(entered.get("ok", false)),
		true,
		"the production enter seam minted a run: %s" % str(entered.get("reason", ""))
	)
	if not bool(entered.get("ok", false)):
		return
	# The run is real on the hero, through the module's own read.
	assert_ne(DomainApi.map_summary(_hero).is_empty(), true, "the hero is standing in a domain")
	# The spawner minted one Actor per authored ref, and the count matches the map.
	var authored := 0
	for ref in DomainApi.population(_hero):
		authored += maxi(1, int(ref.get("count", 1)))
	var inhabitants: Array = entered.get("inhabitants", []) as Array
	assert_eq(
		inhabitants.size(),
		authored,
		"one Actor per authored spawn ref: %d minted, %d authored" % [inhabitants.size(), authored]
	)
	# And those are ACTORS, not the map's dictionaries — the distinction the whole blocker
	# turned on. `DomainApi.population` answers rows; `enter_domain` answers bodies.
	assert_eq(
		authored > 0,
		true,
		"the entered map authored at least one spawn ref, so there is a population to mint"
	)
	for inhabitant in inhabitants:
		assert_eq(inhabitant is Actor, true, "every minted inhabitant is a real Actor")
		assert_eq(
			inhabitant == null,
			false,
			"and never a null standing in for an inhabitant the catalog could not resolve"
		)
	# Each one is PLACED and ROLE-STAMPED: a spawn with no resolvable point is not a spawn,
	# and a role the spawner refuses to read is a body with no identity (ADR 0074). The
	# placement is data on the actor, so it survives a save; asserted as "recorded", not as
	# a coordinate, which would couple this suite to the layout rule it is not testing.
	for inhabitant in inhabitants:
		var actor := inhabitant as Actor
		assert_ne(
			String(DomainSpawner.room_of(actor)),
			"",
			"every minted inhabitant knows the room it was placed in"
		)
		assert_ne(
			String(DomainSpawner.role_of(actor)),
			"",
			"and carries the role the spawner stamped on it"
		)


## BLOCKER 4. A severe zone authored in the entered map applies a real status to the
## hero. `EnvironmentField.apply` hands the hero a `StatusEffect` (it never subtracts a
## pool directly), so the proof is `hero.has_status(<the zone's status_id>)` after the
## production `enter` / `visit` — driven through the real seam, so removing either
## environment wire fails here.
func test_a_severe_environment_in_the_entered_map_applies_a_status_to_the_hero() -> void:
	var screen := _domain_screen()
	assert_eq(screen != null, true, "the domain screen is mounted")
	if screen == null:
		return
	var template_id := _selectable_template(screen)
	# A FAILURE, not a skip — see the note on the sibling case. This one is the proof that
	# a severe environment actually TAXES the hero, so letting it pass without asserting
	# would leave the most expensive subsystem in the module unproven.
	assert_ne(
		template_id,
		"",
		"a template authoring a severe zone generates at this seed; without one this case cannot run"
	)
	if template_id.is_empty():
		return
	assert_eq(
		screen.act_enter(),
		true,
		"the screen's Enter minted a run: %s" % str(screen.summary().get("message", ""))
	)
	# Entering applied the ENTRY room's zones, if it authors any. `enter_domain` wires
	# exactly that, so a domain whose entry room is a hazard already taxed the hero here.
	_assert_zones_applied_on_enter(_hero)
	# A zone anywhere in the entered map is applied when the hero WALKS INTO that room, so
	# the claim is made the way a player meets a hazard: by reaching its room.
	_assert_zones_applied_on_visit(screen, _hero)


# ── the helpers ───────────────────────────────────────────────────────────────


## Every severe zone in the map the hero is standing in, applied on entry. Asserted only
## when the ENTER room authors one, because the entry room is authored content and may
## author none — that is not a wiring defect, it is a room with no hazard in it.
func _assert_zones_applied_on_enter(hero: Actor) -> void:
	var map := _active_map(hero)
	if map == null or map.entry_room == &"":
		assert_eq(true, true, "the hero has no entry room to tax; nothing to assert on entry")
		return
	var room := map.room(map.entry_room)
	if room == null or room.environment_zones.is_empty():
		assert_eq(
			true,
			true,
			"the entry room authors no severe zone, so entering taxed the hero with nothing"
		)
		return
	# It authors one, so the entry wire must have handed the hero its status.
	var zone := room.environment_zones[0]
	assert_eq(
		hero.has_status(zone.status_id),
		true,
		"entering the run applied the entry room's '%s' to the hero" % String(zone.status_id)
	)


## Every severe zone in the map is applied when the hero reaches its room. Walks the
## authored rooms through the screen's OWN `visit` verb, so the discovery ledger and the
## environment stay in step, and asserts for each room that authors a zone the hero took
## the status. Bounded by the map's own room count — a generated domain is a level, not a
## dungeon of 128 rooms, and `DomainPaths` already caps its own walks.
func _assert_zones_applied_on_visit(screen: DomainExploreScreen, hero: Actor) -> void:
	var map := _active_map(hero)
	assert_eq(map != null, true, "the hero has an active map to walk")
	if map == null:
		return
	var zoned := 0
	for room_id in map.room_ids_sorted():
		var room := map.room(room_id)
		if room == null or room.environment_zones.is_empty():
			continue
		zoned += 1
		# Walk in through the screen's own verb — the same control a player presses.
		screen.select_room(room_id)
		screen.act_visit()
		var zone := room.environment_zones[0]
		assert_eq(
			hero.has_status(zone.status_id),
			true,
			(
				"reaching '%s' applied its severe '%s' to the hero"
				% [String(room_id), String(zone.status_id)]
			)
		)
	assert_ne(zoned > 0, false, "the entered map authors at least one severe zone somewhere")


## The first authored `InhabitantDef` on disk, or null when the tree is empty. Read from
## the same directory the module's own catalogue uses, so a newly authored inhabitant is a
## file and never a code edit (ADR 0074).
func _first_inhabitant_def() -> InhabitantDef:
	var dir := DirAccess.open(DomainApi.INHABITANT_DIR)
	if dir == null:
		return null
	var names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var def := load("%s/%s" % [DomainApi.INHABITANT_DIR, name]) as InhabitantDef
		# An inhabitant the spawner refuses to mint (a cultivator with no realm, say) is
		# not a defect here — skip to the next so the case is about the SEAM, not content.
		if def == null or (def.cultivates and def.realm_id == &""):
			continue
		return def
	return null


## Point the screen's template selector at a template the generator accepts at
## [constant SEED], as picking it from the dropdown does, and return its id. `""` when the
## catalogue is empty or none generates — a content fact this suite reports rather than
## indexes blind. Bounded by `MAX_TEMPLATE_ATTEMPTS` so the walk cannot spin.
##
## **Prefers a template that authors a severe zone.** Zones are authored on SOME rooms
## only (`ash_furnace`, `ash_heart`, `tide_vault`, `storm_gallery`), so "the first
## template that generates" is frequently a zone-free one — and a case that then asserts
## a zone was applied would be asserting something about content it never picked. The
## fallback keeps the unzoned templates selectable so the other cases still run.
func _selectable_template(screen: DomainExploreScreen) -> String:
	var templates: Array = DomainBoot.bridge().call_list(&"list_templates")
	assert_eq(templates.is_empty(), false, "the authored domain catalogue is not empty")
	var option := screen.get_node_or_null("%TemplateOption") as OptionButton
	var attempts := 0
	var fallback := ""
	for entry in templates:
		if attempts >= MAX_TEMPLATE_ATTEMPTS:
			break
		attempts += 1
		var template_id := StringName(String(entry.get("template_id", "")))
		# Only aim the screen at a template that generates, so the case is about the
		# WIRING rather than about a seed the content refuses.
		var probe := DomainBoot.bridge()
		var answer: Dictionary = probe.call_action(&"enter", [_hero, template_id, SEED])
		if not bool(answer.get("ok", false)):
			continue
		# Did the run it just minted actually contain a hazard? Read it BEFORE leaving,
		# because `leave` discards the run.
		var zoned := _map_authors_a_zone(_hero)
		probe.call_action(&"leave", [_hero])
		if fallback == "":
			fallback = String(template_id)
		if zoned:
			_select_in_dropdown(option, screen, template_id)
			return String(template_id)
	# Nothing authored a zone: fall back to the first that generates, so the cases that
	# do not care about hazards still run rather than skipping on a content gap.
	if fallback != "":
		_select_in_dropdown(option, screen, StringName(fallback))
	return fallback


## Whether the hero's active run contains at least one authored severe zone.
func _map_authors_a_zone(hero: Actor) -> bool:
	var state: Variant = hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return false
	var map := DomainMap.from_dict((state as Dictionary)["map"])
	for room_id in map.room_ids_sorted():
		var room := map.room(room_id)
		if room != null and not room.environment_zones.is_empty():
			return true
	return false


## Point the dropdown at `template_id`, as a player clicking the list would.
func _select_in_dropdown(
	option: OptionButton, screen: DomainExploreScreen, template_id: StringName
) -> void:
	if option == null:
		return
	for index in option.item_count:
		if String(option.get_item_text(index)).ends_with("(%s)" % String(template_id)):
			option.select(index)
			screen.call("_on_template_selected", index)
			return


## The active run's map, read the way `DomainMinimap.render` reads it. A harness-side
## helper rather than a reach into the module's internals.
func _active_map(hero: Actor) -> DomainMap:
	var state := hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])


## Free everything this suite minted. `remove_child()` then `free()` — `queue_free()` is
## BANNED in this runner (it never processes a frame, so a deferred free leaks for the
## life of the process; that is the shape that took `tests/ui` to 67 GB). The mounted root
## is torn down through the harness, which owns it.
func teardown() -> void:
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
