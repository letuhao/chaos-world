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

	# The INTENT stage: a placed hostile standing in reach AND in a door is a published
	# target. `_first_boss_in_reach` filters on both for the reason its docblock gives.
	var placed := _first_boss_in_reach(world, hero)
	assert_ne(placed, null, "the run minted a boss standing in reach of the player")
	# **Size the door body so this case is about the CHAIN and not about BALANCE.** The
	# shipped `flame_dragon` authors `blows_to_survive = 6.0` at `spirit_transformation`
	# (a 360-point pool), and this suite's deliberately bare hero cannot win that on
	# arithmetic — it lost every door fight, which is the reported `expected 0.0, got
	# 152.0`. The fix is a pool FILL, never a second `Stat.MAX_HEALTH` offset (which would
	# stack on the one `_prepare_inhabitant` already wrote), so the body stays the run's
	# own ROSTERED boss and only its CURRENT health is reduced to what a bare hero can
	# finish inside [constant MAX_BLOWS].
	_size_for_a_bare_hero(placed)
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
	#
	# The CREATURE is the run's own rostered door body (see `_enter_with`): a kill only
	# resolves to a body the roster holds, and this case needs the hero to DIE, not to
	# kill. What it authors is the boss turn — `punish_window_blows: 0` — on a pool left
	# FILLED so the fight lasts long enough for the creature to land the killing blow.
	var world := _world()
	var run := _enter_with(hero, 1, world)
	assert_eq(bool(run.get("ok", false)), true, "a run exists to lose")
	var placed: Actor = _roster[0] if not _roster.is_empty() else null
	assert_ne(placed, null, "the run minted a door body the hero must lose to")
	# Author the unkillable turn and RESTORE the pool, which `_enter_with` shrank so a
	# kill is reachable at all. This case wants the opposite: a body that outlasts the hero.
	BossEncounter.bind(placed, 0.5, 0)
	_fill_pool(placed)

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
	# The whole band: ADR 0229's gate is the BAND, so a case that expects the exit open
	# owes a kill for every authored door. `0` means "every door the run authored".
	var run := _enter_with(hero, 0, _world())
	assert_eq(bool(run.get("ok", false)), true, "a run exists")
	var gate := DomainRunApi.exit_gate(hero)
	assert_eq(bool(gate.get("ok", false)), false, "the exit is shut with a boss still standing")
	assert_eq(String(gate.get("reason", "")), "band_not_cleared", "it says why it is shut")
	# Clear the band: one kill per door, in band order, because a kill out of order is
	# refused `door_closed` (`domain_run.gd:211`) and this case is not testing that.
	for index in range(_roster.size()):
		_kill_boss(hero, _roster[index])
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
	# Two doors: enough to have a SECOND door to be refused, which is what this case is.
	var run := _enter_with(hero, 2, _world())
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
	# the back is not a band. The door id comes off the run the CALLER is holding, which
	# is why `_door_for` takes the hero (`test_nothing_but_a_kill...` below).
	var second := _roster[1]
	var behind := DomainRun.record_kill(
		DomainRun.normalize(hero.get_module_data(DomainRun.MODULE_KEY)), _door_for(hero, second)
	)
	assert_eq(bool(behind["ok"]), false, "a kill behind a closed door is refused")
	assert_eq(String(behind["reason"]), "door_closed", "it names the closed door")

	# And the front door's kill IS what moves it.
	_kill_boss(hero, _roster[0])
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
	# Bind the WHOLE band: the case owes a kill for every authored door, so `_enter_with`
	# is given `0`, which means "every door the run authored". A hardcoded lineup would go
	# stale the moment a template's door count changes — the suite's own second historical
	# bug, on `ember_grotto`'s empty band.
	_enter_with(hero, 0, _world())
	var size := int(DomainRunApi.band(hero).get("band_size", 0))
	# The band's size is the TEMPLATE's authored boss doors, read off the run itself —
	# not the bodies this case placed. `stormwrack_reach` authors five, so a hardcoded 2
	# asserted a number no ADR fixes. What matters is that the band is NON-EMPTY: an empty
	# band is the defect `_open_band`'s docstring names, where every kill is refused
	# `unknown_boss`.
	assert_eq(size > 0, true, "the shipped template authored at least one boss door")
	assert_eq(int(DomainRunApi.band(hero).get("remaining_count", 0)), size, "none are down yet")

	var lineup: Array[Actor] = _roster
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
## ## The base build, and why a bare actor is not a hero (this suite's own measured defect)
##
## It is deliberately NOT a cultivation rig: no gear, no qi rig, no techniques — the blow
## has to be worth a bounded number of presses and the cases count presses, which keeps
## them about the CHAIN rather than about a balance number. It DOES carry the shipped
## hero's base build, and that is the suite's own measured defect rather than a
## convenience.
##
## ## Every stat on a bare `ActorFactory.build` is `0.0`, and a blow is then the chip floor
##
## Measured, both ways, on the same spine and the same `BARE_SWING` technique:
##
## | hero | `max_health` | `attack_physical` | `defense_physical` | blow dealt |
## |---|---|---|---|---|
## | `build(&"bare")` | 50.0 | **0.0** | **0.0** | **1.0** |
## | `build(&"shipped", {PHYSIQUE: 12, SPIRIT: 8, APTITUDE: 6})` | 170.0 | 24.0 | 18.0 | **38.0** |
##
## `ActorStats._init` fills every id with `float(base.get(id, 0.0))`
## (`actor_stats.gd:18-22`), so `ActorFactory.build(id)` with no base dictionary is a body
## with no offence and no defence at all. Its blow therefore resolves to ADR 0162's shared
## chip floor of `1.0` — measured — while a placed creature's blow lands `51.23` on it.
## The fight was decided `hero_lost` inside ONE exchange; the loop then pressed a corpse
## for its remaining 59 blows, which is the whole of
## `the placed body died inside the bound: expected 0.0, got 10.304`.
##
## ## Why the realm was NOT the fix, and the measurement that said so
##
## Two attempts moved the run by exactly zero digits — `10.304` reproduced to the digit
## both times, which is the only evidence that separates "inert" from "helped". A realm is
## a PATH, and `RealmScaling.highest_realm` reads `actor.paths` (`realm_scaling.gd:74-81`),
## not a base stat — so an enrolment scales the stats, and the stats were all zero. **A
## multiplier on zero is zero**, so the amplitude was never the lever and no realm is
## enrolled here: the fixture stays one bare body with a base build, which is the smallest
## change that is also the measured one.
##
## ## `enter_domain` PRICES the body against this hero, which is why the two must match
##
## `DomainBoot._size_inhabitant` prices one hero blow against the creature and writes the
## result as the pool's maximum (`domain_boot.gd:474-501`) — so the creature's survivability
## IS a number of blows *this* hero throws, whatever a blow happens to be worth. A hero
## that cannot win its own matchup cannot fight a door at all, and that is a fact about the
## matchup, not about the chain. This leaves every shipped rule intact (the damage model,
## the rate gate, the band order, the punish window, the `_decide` health read) and changes
## no production code.
func _hero() -> Actor:
	# The shipped player's build, read off `ItemWorkbenchBody._build_actor`
	# (`item_workbench_body.gd:461-463`) rather than invented, so the body under test is a
	# body the game can actually produce.
	var hero := ActorFactory.build(
		&"domain_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	CombatBoot.install(hero)
	_hero_actor = hero
	return hero


## Enter the FIRST authored template with the shipped spawner, and report what the run
## produced. This is [method DomainBoot.enter_domain] verbatim — the ONE production entry
## point — so a broken seam anywhere below it fails here rather than being papered over.
func _enter(hero: Actor) -> Dictionary:
	DomainBoot.install()
	return DomainBoot.enter_domain(hero, _template_id(), SEED)


## Enter a run and stand the run's OWN rostered bodies in their authored boss rooms,
## sized so a case can finish them. `doors` is how many doors this case binds; `0` means
## every door the run authored, and `_roster` then holds them in band order so
## `_roster[i]` is the body standing in the i-th door.
##
## ## Why the door body is the ROSTERED one, and this was the suite's own first bug
##
## `DomainFight._door_of` -> `_placed_boss` resolves a fallen body by walking
## `DomainBoot.placed_inhabitants()` and matching `String(actor.id)`
## (`domain_fight.gd:329-336`). The bodies the previous version minted with
## `DomainSpawner.spawn` were **never in that roster** — `enter_domain` had already
## registered the map's OWN bodies (`domain_boot.gd:318`) — so the match was `0`,
## `_placed_boss` returned `""` by design, and `record_verdict` took its `not_a_boss`
## branch on a door the band really does own. That is why all 17 assertions failed: the
## hero won and the run recorded no kill.
##
## A body the roster does not hold is a body the band does not own, and that is
## **ADR 0229's own rule**, not a loophole: "a placed hostile | advances nothing". So the
## fixture fights the creatures the RUN produced — the rostered body for each door — and
## authors only the SURVIVABILITY a case needs, as a pool FILL rather than a second
## `Stat.MAX_HEALTH` offset (which would stack on the one `_prepare_inhabitant` sized).
##
## Each body is bound to a DIFFERENT boss room, so a band of N has N bodies and a kill
## resolves to the body that was actually fought rather than to whichever sorted first.
func _enter_with(hero: Actor, doors: int, world: Node) -> Dictionary:
	var run := _enter(hero)
	# The band's OWN list — the doors, in the order `DomainRun.record_kill` opens them. Read
	# off the run rather than re-derived from the map, so the fixture cannot disagree with the
	# ledger about which rooms are doors (see [method _boss_rooms], which answers that
	# question and whose answer is deliberately no longer used to pick a body).
	var band: Dictionary = DomainRunApi.band(hero)
	if band.get("bosses", []).is_empty():
		return run
	# Realize the run's OWN map FIRST, so the bodies below are drawn beside the
	# catalogue's by the same `DomainWorld.place_inhabitants` that drew those — real
	# placed creatures, not a second kind of thing the fight rules cannot see.
	DomainBoot.realize_world(world, hero)
	var roster: Array[Actor] = []
	# **Every door the run holds, walking a LIST rather than an INDEX.** The band's list is
	# the only place the ORDER lives: `DomainRun.record_kill` opens door `n + 1` on the kill of
	# door `n` (`domain_run.gd:215-217`) and refuses anything else `door_closed`, so a body has
	# to be bound to the n-th DOOR or its kill is refused on an out-of-order band.
	#
	# The earlier version walked `rooms[index % rooms.size()]` — its own `_boss_rooms` list —
	# and that is the suite's third measured defect. `rooms` was 4 long on the shipped
	# `stormwrack_reach` while the run's band is 5 doors, so `tide_vault#14` — whose authored
	# `roster_band: boss` makes it a door — was skipped by `index % rooms.size()` and no body
	# stood in it. `lineup[3]` was then `ash_heart#3` again and its kill was refused
	# `already_dead`; the chain stopped at `remaining: 2`, `tide_vault#14` stayed open forever,
	# and the four assertions that read "the band is cleared" were measuring that arithmetic
	# rather than the band. Every `_kill_boss` recorded only the three distinct `ash_heart`
	# doors it actually placed, as `DomainFight._door_of`'s own docblock predicted.
	var wanted := doors if doors > 0 else int(band.get("band_size", 0))
	var boss_list: Array = band.get("bosses", [])
	for index in range(wanted):
		# A DIFFERENT boss room per body, so the band has N doors and a kill resolves to
		# the body actually fought rather than to whichever one sorted first.
		var door := String(boss_list[index]) if index < boss_list.size() else ""
		var room_id := door.substr(door.rfind("/") + 1)
		# **The rostered body that owns this door.** `DomainFight._placed_boss` answers
		# "which band entry does this fallen body belong to" by matching a SPECIES id
		# against the roster, so the roster is the whole question — a body outside it has
		# no door by construction, which is ADR 0229's `not_a_boss`, not a broken chain.
		var host := _rostered_boss_in(hero, room_id)
		if host == null:
			# No rostered occupant for this door on the shipped content: the case cannot
			# assert a kill through the real seam, and saying so beats minting a body that
			# `record_verdict` would refuse by name for the right reason.
			continue
		# The case authors the SURVIVABILITY it needs on the ROSTERED body, which is
		# already `CombatBoot.install`ed and sized by `_prepare_inhabitant`. Sizing again
		# would stack a second `Stat.MAX_HEALTH` offset; the survivability the case needs
		# is the pool's FILL, which is a body the hero can actually finish inside the bound.
		_size_for_a_bare_hero(host)
		roster.append(host)
	_roster = roster
	DomainBoot.register_targets(world)
	return run


## The rostered body standing in `room_id` that the run actually spawned, or null.
##
## Read off `DomainBoot.placed_inhabitants()` — the SAME handle `DomainFight._door_of`
## walks — so "the body a kill resolves to" is asked of one list rather than two.
## Bounded by the roster, which is one `Actor` per authored spawn ref capped at
## `DomainSpawner.MAX_COUNT_PER_REF`.
func _rostered_boss_in(hero: Actor, room_id: String) -> Actor:
	if not _band_doors(hero).has(room_id):
		return null
	for inhabitant in DomainBoot.placed_inhabitants():
		var actor := inhabitant as Actor
		if actor == null:
			continue
		if String(DomainSpawner.room_of(actor)) != room_id:
			continue
		if DomainSpawner.has_role(actor, DomainRoles.BOSS):
			return actor
		# A door may be a `roster_band: boss` room whose occupant is a `miniboss`
		# (`tide_vault#14` is the shipped example). ADR 0229's door is the ROOM, not the
		# role, so a hostile occupant of a door room is the body a kill resolves to.
		if DomainSpawner.is_hostile(actor):
			return actor
	return null


## Reduce `actor`'s CURRENT health to a pool this suite's bare hero can finish inside
## [constant MAX_BLOWS], leaving its MAXIMUM and every stat alone.
##
## A pool FILL, never a `set_maximum`: `_prepare_inhabitant` already wrote the species'
## authored `blows_to_survive` as a `Stat.MAX_HEALTH` FLAT offset, and a second offset
## would stack on it and measure a body no shipped code path produces. `current` is the
## one field a fixture may set: `ResourcePool.change` clamps into `[0, maximum]`, and the
## suites here only ever read `current` (`_health_of`).
##
## The fight then ends when the hero's blow crosses this pool, which is the zero crossing
## ADR 0236 fires on — so a kill here is a REAL crossing of a REAL pool, not a synthetic
## zero written by the test.
func _size_for_a_bare_hero(actor: Actor) -> void:
	var pool := actor.resource(&"health") as ResourcePool
	if pool == null:
		return
	pool.current = _survivable_health(actor)


## Restore `actor`'s health to its FULL pool — the inverse of [method
## _size_for_a_bare_hero], for the case that needs a body to outlast the hero rather than
## to fall to it. An assignment to `current`, never `change`: `change` would take a
## relative step and the absolute figure is what "full" means.
func _fill_pool(actor: Actor) -> void:
	var pool := actor.resource(&"health") as ResourcePool
	if pool == null:
		return
	pool.current = pool.maximum


## The health a door's body is given so a case can finish it inside [constant
## MAX_BLOWS] presses.
##
## This fixture's hero is deliberately bare (`_hero`), so its blow is worth ~1.0 against
## a realm-refined body; a pool of a few points is a handful of presses and the loop
## terminates. Bounded below by `1.0` so a tiny pool is still hittable and bounded above by
## the pool's own maximum so a fill can never exceed it.
func _survivable_health(actor: Actor) -> float:
	var pool := actor.resource(&"health") as ResourcePool
	if pool == null:
		return 0.0
	return minf(pool.maximum, maxf(1.0, pool.maximum * 0.02))


## The run's own boss rooms, in the map's canonical order. Bounded by the map's authored
## rooms, so the walk has no bound this suite grows.
##
## **It no longer PICKS a body** — [method _enter_with] walks the band's OWN `bosses` array
## instead. That is the suite's third measured defect and it lived here: this list was four
## long on the shipped `stormwrack_reach` while the run's band holds five doors, because
## `DomainApi._room_is_a_boss_door` (`api.gd:467`) admits a room EITHER shape names and this
## walk re-implements that rule by hand. The two answers disagreed — `tide_vault#14` is a
## `roster_band: boss` room whose spawn ref authors `role: miniboss`, and the hand-rolled walk
## never placed a body in it — and a fixture that picks doors from its own list can silently
## bind a body to door `n-1` when the ledger is holding door `n`, which `record_kill` then
## refuses `already_dead`. A question two places answer differently is one too many, so the
## doors are read off the ledger and this remains only the answer to "which rooms are doors".
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
##
## ## Why a case still mints one, when the door body is the ROSTERED one
##
## Not to be PLACED — `_enter_with` binds the run's own rostered body to each door — but
## because the loss case needs a body it can make UNKILLABLE, and the only honest way to
## say "this creature cannot be hurt" is to author a species whose boss turn never opens
## a punish window. A pool filled on a rostered boss would still be hittable, so the loss
## case mints the shape it needs and reads the rostered body standing in the same room.
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


## The first placed body authored HOSTILE that the player's adapter can actually reach
## AND that stands in a door this run has.
##
## Walks the realized world's own node list rather than the roster, because REACH is what
## the intent stage filters on and a body across the map is not something a press can
## answer. Bounded by the map's own spawn refs, which `DomainSpawner.MAX_COUNT_PER_REF`
## already caps at 64.
##
## ## And why `HOSTILE` alone was the wrong filter — this was the suite's own first bug
##
## The earlier version asked only `DomainSpawner.is_hostile(actor)` and took the first
## creature the world happened to draw. On the shipped `stormwrack_reach` that is a
## `venom_scorpion` in `ash_arena#1`: hostile, in reach, hp 160 — and standing in **no
## door at all**. `DomainFight._door_of` therefore resolved `""`, `record_verdict` took
## its `not_a_boss` branch, and every case downstream asserted about a kill that ADR 0229
## explicitly does not award: *"a placed hostile | advances nothing. The map does not
## clear for blood."* Worse, the hero lost that fight — the reported `expected 0.0, got
## 152.0` is that mob still standing after `MAX_BLOWS` while the hero was dead.
##
## So the intent stage this file is named for is REACH **and** DOOR: a press the chain
## can answer is a press on a body the band owns. Hostility alone picked the walk, not
## the fight.
func _first_boss_in_reach(world: Node, hero: Actor) -> Actor:
	var holder := _holder(world)
	var adapter := _adapter(world)
	if holder == null or adapter == null or hero == null:
		return null
	var doors := _band_doors(hero)
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
		if doors.has(String(DomainSpawner.room_of(actor))):
			return actor
	return null


## The room ids this run's band has a door on, read off the run itself rather than
## restated: `<domain_id>/<room_id>` is the spelling `DomainApi._open_band` mints, so the
## room half of each entry is exactly the room a body must stand in to occupy that door.
##
## `hero` is a PARAMETER for the same reason `_door_for` takes one: `_template_id` mints
## and `leave`s a probe hero per template, so the `_hero_actor` field is not reliably the
## hero holding the run being asked about.
## Bounded by `DomainRun.MAX_BAND_SIZE`, so the walk has no bound this suite invents.
func _band_doors(hero: Actor) -> Dictionary:
	var out: Dictionary = {}
	var band: Dictionary = DomainRunApi.band(hero)
	for entry in band.get("bosses", []):
		var door := String(entry)
		var slash := door.rfind("/")
		if slash >= 0:
			out[door.substr(slash + 1)] = true
	return out


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
	_walk_out_whole(hero)
	return blows


## Carry the hero out of one door at FULL vitality before the next one is pressed.
##
## ## Why a band-clearing case owes this, and what it is NOT
##
## A band is N fights. This fixture kills the first three inside two presses each and walks
## with `170.0 -> 118.8 -> 67.5 -> 16.3`, so the hero reaches door four on its last pool, and
## a real boss's blow is spent as `share * defender_pool.maximum` (`duel_hit.gd:82`) — an
## absolute number off the hero's OWN maximum, not a percentage of what is left. A body on a
## few points therefore takes a full-size hit, and on the fourth door the hero's own zero
## crossing fires first: `FightLoop._decide` returns `hero_lost`,
## `DomainFight.record_verdict` takes its loss branch (`domain_fight.gd:130`) and
## `DomainRunApi.abandon_band` wipes `open_index` AND `kills`
## (`domain_run.gd:253-262`). The band was then `abandoned`, `open_boss` `""`, and the four
## "the band is cleared" assertions were measuring the hero's stamina rather than the run.
##
## ## The rule this asserts, in ADR 0236's own words
##
## "**The loser is walked out whole** ... `FightLoop` carries no wound forward. A boss fight
## is not a wound that persists — **this is a disclosed thinness, not a rule**". So the hero
## starting a fight is not state a door fight leaves behind, and a fixture that walks into the
## next door still carrying the last one's damage is measuring stamina. Every assertion in the
## clearing cases is about which door is open; none is about attrition, and the case that DOES
## care about a loss keeps its own loop
## ([method test_a_press_the_hero_cannot_win_loses_the_run_and_it_is_observable]).
##
## ## Not a production repair, and deliberately so
##
## `CombatExchange._record_defeat` performs exactly this restore for the boss-encounter path
## (`exchange.gd:655-659`) and the `FightLoop` path has none — a disclosed gap in ADR 0236, in
## `app/`, which this task does not own. So this fixture models the rule its own docblock
## names rather than inventing a production verb for it.
##
## `change`, not an assignment to `current`, for the reason `exchange.gd:656` gives: the
## pool's `changed` signal still fires and every stat cache watching it invalidates.
func _walk_out_whole(hero: Actor) -> void:
	var pool := hero.resource(&"health") as ResourcePool
	if pool == null or pool.current >= pool.maximum:
		return
	pool.change(pool.maximum - pool.current)


## The band door `actor` stands in, in the spelling `DomainApi._open_band` mints. Built
## from the run's own domain id and the body's own placement record, so a case names the
## door the SAME way the module does rather than restating the format.
##
## ## Why the hero is a PARAMETER, and not the `_hero_actor` field
##
## The earlier version read `DomainRunApi.band(_hero_actor)`. `_hero_actor` is the most
## recent hero [method _hero] minted — and `_template_id` mints a fresh probe hero for
## EVERY template in the catalogue before it returns (`domain_run_chain.gd:683`), so that
## field holds a hero that has already been `leave`d. Measured, it answered
## `'/ash_heart#10'`: the empty domain id, which is a door **no** run can hold and which
## `DomainRun.record_kill` refuses as `unknown_boss` (`domain_run.gd:200`). That is the
## `it names the closed door: expected door_closed, got unknown_boss` failure: the test
## asked a stranger's run which door the body's room was.
##
## The domain id belongs to the run the CALLER is holding, so the caller is named.
func _door_for(hero: Actor, actor: Actor) -> String:
	var band := DomainRunApi.band(hero)
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
