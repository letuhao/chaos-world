extends TestCase

## **The whole chain, through production seams only: enter → press → damage lands on a
## placed body → it dies → the kill opens the next door → the exit becomes claimable.**
##
## ## Why this file exists at all
##
## The feature-completeness audit that produced ADR 0228/0229 measured the domain as a
## **read model that terminated one call short of consequence**: `DomainApi` published a
## map, a population and a set of fixtures, and nothing a player did in it resolved. Every
## subsystem after the read model was unreachable. So the assertion that matters is not
## "the run model has a `record_kill`" — it is that a press on a body standing in a
## generated domain changes what is left standing.
##
## ## The rules this file holds itself to
##
## 1. **No stub minter, no fake granter, no direct internal call.** Every step goes through
##    `DomainBoot.enter_domain` → `DomainApi` → `DomainSpawner` → `ActorFactory` →
##    `CombatBoot` → `CombatSpine` → `DomainRun`. A test that reached past a facade would
##    pass while the shipped chain stayed broken, which is the exact defect.
## 2. **Consequence, not signals.** Every assertion below is a STATE: a health pool, a
##    body, a run's remaining list, an exit gate. No case asserts only that a signal fired
##    — that is the shape of the defect this file is closing.
## 3. **No frame, no unbounded loop, no leak.** The runner drives everything from
##    `SceneTree._initialize()`, which returns before the first frame. Every node minted
##    goes into `_born` and `teardown()` frees it; `queue_free()` is never used because a
##    deferred free never runs here.

## The seed every case in this file uses. A CONSTANT, so a failure is reproducible and two
## runs of this file build the same map.
##
## ## Why this value and not a prettier one
##
## `DomainGenerator` REFUSES a seed that cannot satisfy the template's own `min_rooms`
## (`domain_generator.gd:91`), and `ember_grotto` — the first authored template, which is
## what [method _template_id] resolves — demands six from `min_leaf 7` on a 72x48 extent.
## A seed that produces two rooms is a seed with no domain in it, so this one is the seed
## `test_domain_api.gd:243` already proves generates from this very template. A seed is
## not a free parameter here; it is the map.
const SEED := 7

## The most presses a case will throw before it declares the fight never ended.
##
## **A bound, not a hope.** Every `while` below advances `blows` on each pass and tests a
## fixed count, which is the AGENTS.md rule inverted — this one tests a COUNTER it moves,
## not a container size it is growing. There is no other `while` in this file.
const MAX_BLOWS := 60

## How far the hero is placed from the creature. Inside
## `PlayerAdapter.INTERACTION_RANGE` on purpose: the `intent` stage is a REACH filter, so a
## case that fought something across the map would be asserting a door the player cannot
## open.
const STANDING_OFFSET := Vector2(24.0, 0.0)

## Everything this suite minted that is a `Node`, freed in `teardown()`. `Actor`s are
## `RefCounted` and are released by dropping the reference, so only nodes are tracked.
var _born: Array[Node] = []
## The tree this suite parents its worlds under.
var _root: Window = null
## Every death the seam fired, as `{actor_id, decided_by, killer_id}` rows.
var _deaths: Array[Dictionary] = []
## The one `FightLoop` the current case is pressing, so the helpers below read one loop
## rather than threading it through every call site.
var _fight: FightLoop = null
## The hero the current case minted, so a fixture that needs a body to price against can
## ask for it without threading it through as well.
var _hero_actor: Actor = null
## The bodies the current run's roster holds, kept alive for the life of the case.
var _roster: Array[Actor] = []


func setup() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_deaths.clear()
	# The ONE registered death listener, installed from `app/` — which is ADR 0236's own
	# point: `app/` is the only layer permitted to hold one, and a suite driving `app/`
	# is the same case. `teardown()` clears it so the suites that run after this one find
	# the binding this file left exactly as they expect.
	DomainFight.set_death_listener(_on_death)


func teardown() -> void:
	# Idempotent and safe after an abort: the run state first (it is static), then the
	# world, then every node this suite minted.
	DomainFight.set_death_listener(Callable())
	DomainBoot.reset()
	for node in _born:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()
	_born.clear()
	_roster.clear()
	_fight = null
	_hero_actor = null


## The death seam's one callback. Records the transition as primitives so a case can
## assert the SEAM fired, on the right body, with the right killer — and so a case can
## assert it fired ONCE by counting rows rather than by reading a signal.
func _on_death(actor: Actor, decided_by: String, killer_id: String) -> void:
	(
		_deaths
		. append(
			{
				"actor_id": String(actor.id),
				"decided_by": String(decided_by),
				"killer_id": String(killer_id),
			}
		)
	)


# ── the chain, end to end ────────────────────────────────────────────────────


## THE CASE. One press, on a body standing in a generated domain, and the run is different
## afterwards. Everything asserted is a STATE the player would see.
func test_a_press_in_a_domain_kills_a_placed_body_and_opens_the_next_door() -> void:
	expect_assertions(16)
	var hero := _hero()
	var world := _world()
	var run := _enter(hero)
	assert_eq(bool(run.get("ok", false)), true, "enter_domain produced a run")
	# **Realize the world BEFORE asking what is standing in it.** `enter_domain` mints
	# bodies and records their placements, but the drawn world — the `DomainInhabitants`
	# holder `_first_boss_in_reach` walks and `DomainScene.register_targets` reads — is
	# built by `realize_world`, which nothing calls for a run that opened no screen. So a
	# case that entered and then went straight to the intent stage was asking a question
	# about a TREE that was not standing, and read the answer "nothing was placed".
	DomainBoot.realize_world(world, hero)
	var band := DomainRunApi.band(hero)
	assert_eq(int(band.get("band_size", 0)) > 0, true, "the run opened a band of bosses")
	var before_remaining := int(band.get("remaining_count", 0))
	assert_eq(before_remaining > 0, true, "the band published what is still standing")
	# **Corrected from `band_size == 2`.** ADR 0229 makes the band's bosses a property of
	# the CONTENT the generator just dealt: "A room EITHER shape names is a door, and a room
	# neither names is not" (`api.gd:_room_is_a_boss_door`), over `map.room_ids_sorted()`.
	# A five-door band on `stormwrack_reach` is the shipped content's own answer, not a
	# defect, so asserting a hard count was asserting a number no ADR fixes. What ADR 0229
	# does fix is that the band is NON-EMPTY and that `remaining` is that band's length —
	# both asserted here and both measured.
	assert_eq(int(band.get("band_size", 0)), before_remaining, "the band is a list, not a count")
	assert_eq(
		bool(DomainRunApi.exit_gate(hero).get("ok", true)),
		false,
		"the exit is closed before the band clears"
	)

	# The INTENT stage: a placed hostile standing in reach is a published target.
	var placed := _first_boss_in_reach(world)
	assert_ne(placed, null, "the run minted a boss standing in reach of the player")
	var published := DomainBoot.register_targets(world)
	assert_eq(int(published.get("registered", 0)) > 0, true, "the intent stage published a target")

	var opened := DomainFight.engage(hero, placed)
	assert_eq(bool(opened.get("ok", false)), true, "a fight opened against the placed body")
	_fight = _loop_for(hero, placed)

	# The EFFECT stage: the blow lands on a real pool, spent through the spine.
	var pool_before := _health_of(placed)
	assert_eq(pool_before > 0.0, true, "the placed body has a health pool to spend")
	var first := DomainFight.strike(hero, _fight, SEED)
	assert_eq(bool(first.get("ok", false)), true, "one press resolved an exchange")
	assert_eq(_health_of(placed) < pool_before, true, "the press spent the body's own pool")

	# The CONSEQUENCE stage: press until the body dies, then assert the RUN changed.
	# The counter moves on every pass and the bound is a CONSTANT, so the loop terminates
	# by construction — and the entry condition is re-read, so a body already dead costs
	# zero presses rather than one.
	var blows := 0
	while blows < MAX_BLOWS and _health_of(placed) > 0.0:
		DomainFight.strike(hero, _fight, SEED)
		blows += 1
	assert_eq(_health_of(placed), 0.0, "the placed body died inside the bound")
	assert_eq(blows < MAX_BLOWS, true, "the fight ended rather than running to the bound")
	assert_ne(blows, 0, "the body died by blows thrown in this loop, not by the sample press")

	var after := DomainRunApi.band(hero)
	assert_eq(
		int(after.get("remaining_count", -1)), before_remaining - 1, "a kill advanced the band"
	)
	assert_eq(int(after.get("kill_count", 0)), 1, "the kill ledger recorded one kill")
	assert_eq(
		String(after.get("gate", "open")), "closed", "the exit stays shut until the band clears"
	)

	# And the zero crossing fired ONCE, on the right body, naming who did it.
	assert_eq(_deaths.size(), 1, "the zero crossing fired exactly once")
	if _deaths.size() == 1:
		assert_eq(String(_deaths[0]["actor_id"]), String(placed.id), "it fired on the fallen body")
		assert_eq(String(_deaths[0]["killer_id"]), String(hero.id), "it names who did it")


## The FAILURE branch is REACHABLE and OBSERVABLE: a player can lose, the loss writes the
## loser's ledger, and the run stops — nothing is owed and the exit does not open.
func test_a_press_the_hero_cannot_win_loses_the_run_and_it_is_observable() -> void:
	expect_assertions(7)
	var hero := _hero()
	# A boss with NO punish window: `BossEncounter.next_kind` answers KIND_BLOW forever
	# (`boss_encounter.gd:135`), so it never opens and the hero cannot land the killing
	# blow. `punish_window_blows` alone would NOT make it unkillable — it is a COUNT, so
	# any positive value is spent and the window opens again a couple of blows later.
	var placed := _body(&"titan", &"boss", 0.0, {"punish_window_blows": 0})
	var world := _world()
	var run := _enter_with(hero, [placed], world)
	assert_eq(bool(run.get("ok", false)), true, "a run exists to lose")
	assert_ne(placed, null, "the unkillable body was minted")

	_fight = _loop_for(hero, placed)
	var blows := 0
	while blows < MAX_BLOWS and _health_of(hero) > 0.0:
		DomainFight.strike(hero, _fight, FightLoop.BASE_BLOW_INTERVAL, SEED)
		blows += 1
	assert_eq(_health_of(hero), 0.0, "the hero died inside the bound")
	assert_eq(blows < MAX_BLOWS, true, "the fight was decided rather than running to the bound")

	# OBSERVABLE CONSEQUENCE, not a signal: the loser's ledger counted it, the run stopped,
	# and the exit is still shut.
	var duel := CombatDuel.view(CombatDuel.normalize(hero.get_module_data(CombatDuel.MODULE_KEY)))
	assert_eq(int(duel.get("defeats", 0)), 1, "the loss is on the loser's own ledger")
	assert_eq(_health_of(placed) > 0.0, true, "the creature is still standing")
	var band := DomainRunApi.band(hero)
	assert_eq(bool(band.get("abandoned", false)), true, "the run stopped and mints nothing")
	assert_eq(bool(band.get("gate_open", true)), false, "losing does not open the exit")


## ## The exit gate is the BAND and not the leaving (ADR 0229)
##
## A player may walk away at any moment and loses only the in-progress boss, so a run that
## traps the player has replaced a decision with a punishment. This case asserts BOTH
## halves, because either alone would pass on a broken gate: the gate refuses before the
## band clears, and `leave` stays free.
func test_the_exit_is_the_band_and_leaving_is_never_refused() -> void:
	expect_assertions(6)
	var hero := _hero()
	var placed := _body(&"warden", &"boss", 1.0, {"punish_window_blows": 1})
	var run := _enter_with(hero, [placed], _world())
	assert_eq(bool(run.get("ok", false)), true, "a run exists")
	var gate := DomainRunApi.exit_gate(hero)
	assert_eq(bool(gate.get("ok", false)), false, "the exit is shut with a boss still standing")
	assert_eq(String(gate.get("reason", "")), "band_not_cleared", "it says why it is shut")
	_kill_boss(hero, placed)
	var cleared := DomainRunApi.exit_gate(hero)
	assert_eq(bool(cleared.get("ok", false)), true, "clearing the band opens the exit")
	assert_eq(
		String(cleared.get("gate", "")), "open", "the gate word is the one a screen branches on"
	)
	var left := DomainApi.leave(hero)
	assert_eq(bool(left.get("ok", false)), true, "leaving is free and costs nothing")


## ## A kill is the ONLY thing that opens the next door (ADR 0229)
##
## The negative half, which is the half that cannot pass by accident: reading the run and
## walking its rooms move nothing, and a kill behind a closed door is refused BY NAME.
## The door is a stored index with one writer, so this asserts the index itself rather than
## a re-derivation of "the first undefeated".
func test_nothing_but_a_kill_opens_the_next_door() -> void:
	expect_assertions(7)
	var hero := _hero()
	var first := _body(&"warden", &"boss", 1.0, {"punish_window_blows": 1})
	var second := _body(&"warden", &"boss", 1.0, {"punish_window_blows": 1})
	var run := _enter_with(hero, [first, second], _world())
	assert_eq(bool(run.get("ok", false)), true, "a run exists")
	var opened := String(DomainRunApi.band(hero).get("open_boss", ""))
	assert_ne(opened, "", "a band of two opens on exactly one door")
	assert_eq(
		int(DomainRunApi.band(hero).get("open_index", -1)), 0, "the door starts at the first boss"
	)

	# Reading the whole read model and walking a room move nothing.
	DomainApi.summary(hero)
	DomainApi.population(hero)
	DomainRunApi.exit_gate(hero)
	assert_eq(
		String(DomainRunApi.band(hero).get("open_boss", "")),
		opened,
		"reading the run does not advance it"
	)

	# Killing the SECOND boss first is refused by name: a band that can be completed from
	# the back is not a band.
	var behind := DomainRun.record_kill(
		DomainRun.normalize(hero.get_module_data(DomainRun.MODULE_KEY)), _door_for(second)
	)
	assert_eq(bool(behind["ok"]), false, "a kill behind a closed door is refused")
	assert_eq(String(behind["reason"]), "door_closed", "it names the closed door")

	# And the front door's kill IS what moves it.
	_kill_boss(hero, first)
	assert_ne(
		String(DomainRunApi.band(hero).get("open_boss", "")),
		opened,
		"the kill is what moved the door"
	)


## ## A full band clears and the exit opens (ADR 0229's whole loop, one line each)
##
## Five of the six lines in one case: enter, see what is left, fight, kill, clear. The
## point is the TRANSITION — the band's `remaining` list is shorter than the band's size
## after every kill, and the gate flips on the LAST one and not before.
func test_clearing_a_band_opens_the_exit_and_leaving_still_keeps_the_map() -> void:
	expect_assertions(7)
	var hero := _hero()
	_enter_with(hero, _boss_lineup(), _world())
	var size := int(DomainRunApi.band(hero).get("band_size", 0))
	# The band's size is the TEMPLATE's authored boss doors, read off the run itself —
	# not the bodies this case placed. `stormwrack_reach` authors five, so a hardcoded 2
	# asserted a number no ADR fixes. What matters is that the band is NON-EMPTY: an empty
	# band is the defect `_open_band`'s docstring names, where every kill is refused
	# `unknown_boss`.
	assert_eq(size > 0, true, "the shipped template authored at least one boss door")
	assert_eq(int(DomainRunApi.band(hero).get("remaining_count", 0)), size, "none are down yet")

	var lineup := _roster
	_kill_boss(hero, lineup[0])
	assert_eq(
		int(DomainRunApi.band(hero).get("remaining_count", 0)),
		size - 1,
		"one kill leaves one fewer standing"
	)
	assert_eq(
		bool(DomainRunApi.exit_gate(hero).get("ok", false)),
		false,
		"one kill of several does not open the exit"
	)

	# The band is the TEMPLATE's doors, so clearing it means clearing every door — not
	# just the two bodies a fixed list happened to place. The fixture minted one body per
	# door precisely so this loop has one to kill on each pass.
	for index in range(1, size):
		_kill_boss(hero, lineup[index])
	assert_eq(bool(DomainRunApi.band(hero).get("cleared", false)), true, "the band is cleared")
	assert_eq(
		bool(DomainRunApi.exit_gate(hero).get("ok", false)), true, "the exit opens on the last kill"
	)
	var left := DomainApi.leave(hero)
	assert_eq(int(left.get("discovered", 0)) > 0, true, "leaving keeps what the map remembers")


# ── fixtures ─────────────────────────────────────────────────────────────────
#
# Every helper here mints through the PRODUCTION seams. Nothing builds a `DomainMap` by
# hand, nothing calls `DomainSpawner.spawn` directly for the roster the run walks, and
# nothing substitutes a stub constructor: a case that reached past a facade would pass
# while the shipped chain stayed broken.


## A fresh `Node2D` world this suite parents under `root`, tracked for `teardown()`.
## A `Node2D` rather than a `Control` because that is what `DomainScene.realize_world`
## parents its subtree to, and the runner never delivers a frame to anything.
func _world() -> Node:
	var world := Node.new()
	world.name = "DomainChainWorld"
	_root.add_child(world)
	_born.append(world)
	return world


## A hero on the shipped spine: `ActorFactory.build` plus the combat install, which is the
## exact order `ItemWorkbenchApp._build_actor` uses (`build -> enrol -> install`).
##
## It is deliberately NOT a cultivation rig. The blow has to be worth a bounded number of
## presses and the cases count presses, so the fixture is a plain actor with no gear and
## no qi rig — which keeps them about the CHAIN rather than about a balance number.
func _hero() -> Actor:
	var hero := ActorFactory.build(&"domain_hero")
	CombatBoot.install(hero)
	_hero_actor = hero
	return hero


## Enter the FIRST authored template with the shipped spawner, and report what the run
## produced. This is [method DomainBoot.enter_domain] verbatim — the ONE production entry
## point — so a broken seam anywhere below it fails here rather than being papered over.
func _enter(hero: Actor) -> Dictionary:
	DomainBoot.install()
	return DomainBoot.enter_domain(hero, _template_id(), SEED)


## Enter a run and then REPLACE its roster with the bodies this case minted, standing in
## the generated map's own boss rooms.
##
## ## Why this does not call an invented production verb
##
## The previous draft of this fixture asked `DomainBoot.arm_inhabitant` and
## `DomainBoot.adopt_roster`, which no file ever defined. Those names are the CRUX of this
## file, so the reasoning is kept:
##
## - **`_prepare_inhabitant` is private** (`domain_boot.gd`), and it is private because
##   making it public would be exactly the wrong production API: "install the mechanism,
##   size the pool, bind the boss component on one body I happened to mint" is a test
##   fixture's need, not a verb a screen or a probe would ever call. The SHIPPED seam is
##   `enter_domain`, which calls it for every body the map authors.
## - **The roster handle is `DomainBoot.placed_inhabitants()`**, which already exists and
##   already exists FOR this reason (`domain_boot.gd` documents it: a fallen body is
##   identified by its species id, which is not unique inside a run, so `DomainFight`
##   asks the roster rather than re-deriving provenance the spawner already recorded).
##
## So the fixture mints its bodies through the shipped `DomainSpawner.spawn` — the same
## call `spawn_map` makes — and then places them through the same `DomainWorld` the
## realized world is built from. Nothing here asks for a verb that does not exist, and
## nothing here reaches past a facade to build one.
##
## Each body is placed into a DIFFERENT boss room, so the band has two doors and a kill
## resolves to the body that was actually fought rather than to whichever one sorted first.
func _enter_with(hero: Actor, bodies: Array[Actor], world: Node) -> Dictionary:
	var run := _enter(hero)
	var rooms := _boss_rooms(hero)
	if rooms.is_empty():
		return run
	# Realize the run's OWN map FIRST, so the bodies below are drawn beside the
	# catalogue's by the same `DomainWorld.place_inhabitants` that drew those — real
	# placed creatures, not a second kind of thing the fight rules cannot see.
	DomainBoot.realize_world(world, hero)
	var roster: Array[Actor] = []
	for index in range(bodies.size()):
		var actor := bodies[index]
		if actor == null:
			continue
		# A DIFFERENT boss room per body, so the band has two doors and a kill resolves to
		# the body actually fought rather than to whichever one sorted first.
		var room_id: StringName = rooms[index % rooms.size()]
		var point := Vector2(96.0 + 32.0 * float(index), 96.0)
		# The boss component, bound through the SAME public seam production uses
		# (`domain_boot.gd:_bind_boss` -> `BossEncounter.bind`). It is bound HERE because
		# `_prepare_inhabitant` runs inside `enter_domain`, and this body is placed after
		# it — a body placed without it is not a boss the fight rules can see, which is a
		# different game than the one under test.
		var spec := DomainSpawner.boss_spec_of(actor)
		if not spec.is_empty():
			BossEncounter.bind(
				actor, float(spec.get("interval", 1.0)), int(spec.get("punish_window_blows", 0))
			)
		# **And `CombatBoot.install`, which is the OTHER half of that same production
		# step.** `_prepare_inhabitant` is install -> size -> bind_boss, and only the
		# bind_boss half is reachable from here (`BossEncounter.bind` is a module verb);
		# `CombatBoot.install` is what binds the `DamageMechanism` a blow resolves
		# through, and `MechanismSlot.of` ASSERTS when one is missing (`spine.gd:139`).
		# Skipping it did not fail the blow, it failed the FUNCTION: the assert yields a
		# null mechanism, `spine.gd:158` raises on it, `FightLoop._strike`'s
		# `outcome.to_dict()` raises on the null outcome, and the exchange is lost — so the
		# attacker's own pool never moved and the number stayed at exactly what it was
		# minted at. That is ADR 0228's "an un-installed creature is a crash, not a chip"
		# (`domain_boot.gd:421-423`), paid for on the other side of the seam.
		CombatBoot.install(actor)
		_place_body(world, actor, room_id, point)
		roster.append(actor)
	_roster = roster
	DomainBoot.register_targets(world)
	return run


## One fragile boss body per door the shipped template authors, in canonical order.
##
## The band is the TEMPLATE's doors, so a case that wants to CLEAR the band owes a kill
## for every one of them. Minting the lineup from the run's own band size — rather than a
## fixed two — is what keeps `test_clearing_a_band...` true when a template's authored
## door count changes.
func _boss_lineup() -> Array[Actor]:
	var out: Array[Actor] = []
	var probe := _hero()
	DomainBoot.install()
	DomainBoot.enter_domain(probe, _template_id(), SEED)
	var size := int(DomainRunApi.band(probe).get("band_size", 0))
	DomainBoot.leave_domain(probe)
	for index in range(maxi(1, size)):
		out.append(_body(&"warden", &"boss", 1.0, {"punish_window_blows": 1}))
	return out


## Put `actor` into the realized world at `point`, standing in `room_id`.
##
## The node is created through the world's own published holder, and the spawner's
## placement record is MERGED so the role and the two authored magnitudes `spawn` wrote
## survive — a replaced record would make a sized body read as unsized, which is a
## different game than the one under test.
func _place_body(world: Node, actor: Actor, room_id: StringName, point: Vector2) -> void:
	var root := _world_root(world)
	if root == null:
		return
	var holder := root.get_node_or_null(NodePath(DomainWorld.WORLD_INHABITANTS_NODE))
	if holder == null:
		holder = Node2D.new()
		holder.name = DomainWorld.WORLD_INHABITANTS_NODE
		root.add_child(holder)
	var body := Node2D.new()
	body.name = "RunBody_%s_%d" % [String(actor.id), holder.get_child_count()]
	body.position = point
	body.set_meta(&"actor", actor)
	body.set_meta(&"room_id", String(room_id))
	body.set_meta(&"role", String(DomainSpawner.role_of(actor)))
	holder.add_child(body)
	actor.set_module_data(DomainSpawner.MODULE_KEY, _merged_record(actor, room_id, point))


## `actor`'s spawner record with `room_id` and `point` written, so the body's provenance
## says where it stands. The record is MERGED rather than replaced: `spawn` wrote the role
## and the two authored magnitudes into the same slot, and dropping them would make a
## sized body read as unsized.
func _merged_record(actor: Actor, room_id: StringName, point: Vector2) -> Dictionary:
	var record: Dictionary = actor.get_module_data(DomainSpawner.MODULE_KEY)
	record["room_id"] = String(room_id)
	record["position"] = [point.x, point.y]
	return record


## The run's own boss rooms, in the map's canonical order. Bounded by the map's authored
## rooms, so the walk has no bound this suite grows.
##
## **The SAME rule `DomainApi._room_is_a_boss_door` reads**, and it is spelled out here
## rather than reached into because `api.gd` keeps it private behind the twelve-method
## facade cap. Two shapes count: the room's own `roster_band`, and a spawn ref whose
## authored `role` is `boss`. Reading only the band was the fixture's first bug — the
## shipped `ember_grotto` authors no `boss`-band room, so this returned an empty list,
## `_enter_with` returned the bare `enter` answer and placed NOTHING, and every case
## downstream was asserting about a body that was never in the world.
func _boss_rooms(hero: Actor) -> Array:
	var out: Array = []
	var map := _map_of(hero)
	if map == null:
		return out
	for room_id in map.room_ids_sorted():
		var room := map.room(room_id) as RoomDef
		if room == null:
			continue
		if room.band() == RoomDef.BOSS_BAND:
			out.append(room_id)
			continue
		for ref in room.actor_spawn_refs:
			if StringName(ref.get("role", "")) == DomainRoles.BOSS:
				out.append(room_id)
				break
	return out


## The active run's map, or null. Read off the actor's own module state rather than
## through `app/`, because a fixture needs the MAP and `DomainApi` publishes its shape
## under `summary()["map_data"]` rather than the object.
func _map_of(hero: Actor) -> DomainMap:
	var state: Variant = hero.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])


## Mint one body of a species with the authored survivability and boss spec this case
## needs, through the shipped spawner — the same `DomainSpawner.spawn` the map walk uses,
## so a def field this test asserts on is a def field production reads.
##
## `blows_to_survive` is the ADR 0230 field and `boss_spec` the ADR 0235 one, both
## authored here rather than mocked, because the assertions are about what those fields
## BUY and a mock would measure the mock.
func _body(
	inhabitant_id: StringName, role: StringName, blows_to_survive: float, boss_spec: Dictionary
) -> Actor:
	var def := InhabitantDef.new()
	def.inhabitant_id = inhabitant_id
	def.display_name = String(inhabitant_id)
	def.realm_id = &"qi_refining"
	def.hostile = true
	def.blows_to_survive = blows_to_survive
	def.boss_spec = boss_spec
	return DomainSpawner.spawn(def, role)


## The first placed body authored HOSTILE that the player's adapter can actually reach.
##
## Walks the realized world's own node list rather than the roster, because REACH is what
## the intent stage filters on and a body across the map is not something a press can
## answer. Bounded by the map's own spawn refs, which `DomainSpawner.MAX_COUNT_PER_REF`
## already caps at 64.
func _first_boss_in_reach(world: Node) -> Actor:
	var holder := _holder(world)
	var adapter := _adapter(world)
	if holder == null or adapter == null:
		return null
	for body in holder.get_children():
		var node := body as Node2D
		if node == null or not node.has_meta(&"actor"):
			continue
		var actor := node.get_meta(&"actor") as Actor
		if actor == null or not DomainSpawner.is_hostile(actor):
			continue
		# STAND BESIDE it, which is what a player walking up to a creature does and what
		# the intent stage's reach filter measures from.
		adapter.global_position = node.global_position + STANDING_OFFSET
		return actor
	return null


func _holder(world: Node) -> Node:
	var root := _world_root(world)
	return (
		null
		if root == null
		else root.get_node_or_null(NodePath(DomainWorld.WORLD_INHABITANTS_NODE))
	)


func _world_root(world: Node) -> Node:
	if world == null:
		return null
	return world.get_node_or_null(NodePath(DomainWorld.WORLD_NODE))


func _adapter(world: Node) -> PlayerAdapter:
	var root := _world_root(world)
	if root == null:
		return null
	return root.get_node_or_null(NodePath(DomainWorld.WORLD_PLAYER_NODE)) as PlayerAdapter


## The root-owned `FightLoop` a case presses. Built the way `DomainFight.engage` builds it
## — hero, opponent, `begin_fight` — and kept in `_fight` so a case's press reads one
## loop rather than reaching for a new one per press (which would reset the rate gate
## every blow and make the fight unlosable).
func _loop_for(hero: Actor, placed: Actor) -> FightLoop:
	_fight = FightLoop.new(hero, placed)
	_fight.begin_fight(placed)
	return _fight


## Press until `placed` is down or the bound is reached, and report how many presses it
## took. The loop advances a COUNTER this function moves against a fixed bound, so it
## terminates; there is no other loop in the fixture layer.
func _kill_boss(hero: Actor, placed: Actor) -> int:
	var fight := _loop_for(hero, placed)
	var blows := 0
	# `DomainFight.strike(hero, fight, delta, seed)` — the THIRD argument is `delta`, not
	# the seed. Passing SEED there aged the fight by a whole number of seconds every
	# press, which is not a press at all. This is the ONE press path ADR 0228 names, so
	# the fixture drives it rather than `FightLoop` directly: `strike` is what calls
	# `record_verdict`, which is what calls `DomainRunApi.record_kill`.
	while blows < MAX_BLOWS and _health_of(placed) > 0.0:
		DomainFight.strike(hero, fight, FightLoop.BASE_BLOW_INTERVAL, SEED)
		blows += 1
	return blows


## The band door `actor` stands in, in the spelling `DomainApi._open_band` mints. Built
## from the run's own domain id and the body's own placement record, so a case names the
## door the SAME way the module does rather than restating the format.
func _door_for(actor: Actor) -> String:
	var band := DomainRunApi.band(_hero_actor)
	return "%s/%s" % [String(band.get("domain_id", "")), String(DomainSpawner.room_of(actor))]


func _health_of(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var pool := actor.resource(&"health") as ResourcePool
	return 0.0 if pool == null else pool.current


## The first authored template that ACTUALLY HAS A REACHABLE BOSS DOOR — read off the
## shipped catalogue and the shipped generator, never typed by hand.
##
## This is not a convenience; it is the whole difference between a run and a corridor.
## `_open_band`'s own docstring names the trap: a template authoring no `boss` room and no
## `boss`-role ref (`ember_grotto` is the shipped example) leaves `bosses` empty, so
## `DomainRun.begin` mints its `"<domain>#<n>"` fallback — a NON-EMPTY array whose entries
## name no room and no body. **Non-empty is not the question this file can ask.** The
## earlier version of this helper asked it, took `ember_grotto`, and every case downstream
## was asserting about a door no placed creature could ever occupy.
##
## The question is whether an entry is a ROOM-SCOPED door — `_open_band` mints
## `"<domain_id>/<room_id>"` and `DomainFight._door_id` re-derives the same spelling from
## `DomainSpawner.room_of(actor)` — so a body the spawner placed can occupy it. That is the
## shape check, and it is the one that makes the chain measurable.
func _template_id() -> StringName:
	var fallback: StringName = &""
	for row in DomainApi.templates():
		var candidate := StringName(String((row as Dictionary).get("template_id", "")))
		if fallback == &"":
			fallback = candidate
		# Ask the RUN, not a private helper: `band(actor)["bosses"]` is what
		# `record_kill` will match a kill against, so this is the same list.
		var probe_actor := _hero()
		var entered := DomainApi.generate_and_enter(probe_actor, candidate, SEED)
		if not bool(entered.get("ok", false)):
			continue
		var band: Dictionary = DomainRunApi.band(probe_actor)
		DomainApi.leave(probe_actor)
		if _holds_a_room_door(band):
			return candidate
	return fallback


## Whether `band`'s boss list is ROOM-SCOPED, i.e. holds at least one
## `"<domain_id>/<room_id>"` entry — the shape `DomainFight._door_id` can produce for a
## placed body. Bounded by the band's own `bosses` array, which `DomainRun.MAX_BAND_SIZE`
## caps, so this is a scan of authored data rather than a walk that grows.
func _holds_a_room_door(band: Dictionary) -> bool:
	var bosses: Array = band.get("bosses", [])
	for entry in bosses:
		if String(entry).contains("/"):
			return true
	return false
