extends TestCase

## THE headline leg — "reach the terminal realm" — proved with nothing waived.
##
## Two proofs of it already existed and each waived exactly what the other proved:
##
##   - `test_player_walks_to_r30.gd` ends its helper with
##     `hero.tribulation.apply_result(hero, true)`, so the FIGHT is forced and the
##     file proves the ascent, not the terminal realm.
##   - `test_high_tier_traversal.gd` fights honestly through
##     `Breakthrough.face_tribulation`, but its `_commit` calls `WorldAnchor.commit`
##     from the test, so the MILESTONE is granted and the file proves the fight, not
##     the milestone.
##
## Together they cover each other's gap, which is a defensible pair — and neither is
## a proof of the leg the program is judged on. This file is the third thing: one
## walk in which every gate is EARNED, with a negative that shows the gate still
## bites.
##
## Nothing here is a shortcut:
##
##   1. THE FIGHT. `Breakthrough.face_tribulation` — the entry
##      `body_cultivation/advancement.gd:149` calls on every attempt — descends waves
##      through `Tribulation.fight_wave` and is decided by
##      `TribulationEndurance.survives` (`core/tribulation_endurance.gd:59`), the one
##      curve in core that answers "did this actor survive". `apply_result` is never
##      called with a chosen verdict, and no seed is searched for at test time: the
##      two seeds below are pinned constants whose first draw sits on the far side of
##      `TribulationEndurance`'s own floor and ceiling, so the outcome cannot move if
##      the rating is retuned.
##
##   2. THE MILESTONE. Every high-tier transition goes through
##      `Breakthrough.try_advance_gated` — the entry the Breakthrough press calls —
##      and that call runs `WorldAnchor.commit` at `core/breakthrough.gd:56` as part
##      of the advance. There is no test-side commit anywhere in this file.
##      `test_the_milestone_is_the_advances_and_not_the_tests` is what makes that
##      load-bearing rather than decorative: it shows a hero whose R28 rank was
##      written by hand, with nothing else granted, is refused at R29 by name.
##
##   3. THE ASCENT. Walked by pressing the shipped screen's own `act_ascend`
##      (`ui/screens/body_cultivation_panel.gd:321`), asserted on `summary()` — the
##      same surface a player sees, never pixels.
##
## SCOPE, so it is not over-read: the thousands of cultivate presses that carry a
## hero from R1 to R18 are each path's own business and are measured by
## `tests/modules/<path>/test_full_traversal.gd`. What is proved here is that every
## transition from R1 to R30 is *satisfiable by the shipped verbs* — which is a
## different and weaker claim than "the training is tuned", and is the claim that
## was dead.

const SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"

## Ladder index of the terminal realm, R30.
const TERMINAL := 29

## Bounds that name what they catch. `LADDER_GUARD` catches a ladder that stopped
## adding realms (it would otherwise walk 29 transitions and never arrive);
## `WAVE_GUARD` catches a phase machine that stopped converging;
## `ASCENT_GUARD` catches a screen that keeps offering a walk that never finishes.
## None of them is the reason a walk ends: `ascend` refuses a fifth step and the
## loop's own state test ends it first.
const LADDER_GUARD := 64
const WAVE_GUARD := 24
const ASCENT_GUARD := 16

## Presses one rung of the BODY walk may spend. A press that is refused by the
## tribulation gate has descended a wave; a press that commits either wins the
## breakthrough or deviates and owes a recovery. So one rung costs a fight's waves plus
## a run of rolls at the authored floor chance (0.2580), where `MAX_ATTEMPTS = 96`
## all losing is 0.742^96 ~= 4e-13. This is sized above both, not tuned to either.
const BODY_PRESS_GUARD := 128

## The two pinned rolls. `TribulationEndurance.MIN_ENDURANCE` is the floor every
## possible rating clamps to and `MAX_ENDURANCE` the ceiling, so a draw below the
## floor survives ANY fight and a draw at or above the ceiling loses ANY fight. The
## numbers are constants, not the result of a scan run at test time: a scan would
## make the seed a property of the scan's order, and this file's whole claim is that
## the outcome is a property of the pinned seed. `_seed_side` asserts the invariant
## they were chosen for, so a retune of either bound is caught here rather than
## turning this file into a coin flip.
## (`13` draws 0.062118 and `4` draws 0.900177 when probed, and `_seed_side` below
## re-checks the only property that matters — which side of the bound each draw falls
## on — rather than the exact figure, so a retune of either bound is caught here
## instead of turning this file into a coin flip.)
const WINNING_SEED := 13
const LOSING_SEED := 4

# --- Fixtures -------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## A hero on the body path at R1, with the body module attached the way `app/main.gd`
## attaches it. Nothing about its high-tier state is written: no ascension, no
## inside world, no created world, no tribulation record. Every one of those is
## produced by an advance or a fight below.
func _hero() -> Actor:
	var hero := Actor.new(&"earned_hero", {Stat.COMPREHENSION: 60.0})
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(0)))
	BodyCultivationApi.attach(hero)
	BodyCultivationApi.attach_acupoints(hero)
	return hero


func _screen() -> Control:
	var packed := load(SCREEN) as PackedScene
	assert_ne(packed, null, "%s loads" % SCREEN)
	if packed == null:
		return null
	var node := packed.instantiate() as Control
	if node == null:
		return null
	assert_eq(node.has_method(&"act_ascend"), true, "the screen exposes act_ascend")
	return node


## The ladder index this hero would advance into, or -1 at the top.
func _next_index(hero: Actor) -> int:
	var upcoming := RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id)
	return -1 if upcoming == null else RealmDefaults.ladder().index_of(upcoming.id)


func _ascent(view: Dictionary) -> Dictionary:
	return view.get("ascent", {}) as Dictionary


## A fresh generator on the pinned winning seed. Fresh per fight, and the fight
## helper below never retries — see `_fought_once` for why that is the whole design.
func _roll_winning() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = WINNING_SEED
	return rng


func _roll_losing() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = LOSING_SEED
	return rng


## Whether the pinned seed's first draw is on the requested side of the bound. This
## is what makes the seeds a guarantee rather than a hope: below `MIN_ENDURANCE` the
## fight is survived whatever the rating, at or above `MAX_ENDURANCE` it is lost
## whatever the rating.
func _seed_side(threshold: float, above: bool) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = WINNING_SEED if not above else LOSING_SEED
	return (rng.randf() >= threshold) == above


## Fight the tribulation owed for `target_index` ONCE, to a verdict, and return the
## record it left behind. Never retries, and never looks for a roll that works.
##
## NO RETRY IS THE POINT, and the first draft of this file got it wrong. A decided
## tribulation is complete, so `begin_tribulation` REPLACES it on the next
## `face_tribulation` — a helper that loops until the gate opens re-fights the same
## hero with the SAME generator, spends its SECOND draw, and a "losing" seed wins
## anyway. A pinned seed guarantees its FIRST draw only, so a negative built on a
## retrying helper proves nothing at all. One seed, one fight, one verdict.
##
## Bounded by `WAVE_GUARD`, which names the phase machine that failed to converge.
func _fought_once(hero: Actor, target_index: int, rng: RandomNumberGenerator) -> Tribulation:
	if Breakthrough.tribulation_ok(hero, target_index):
		return hero.tribulation
	if Breakthrough.begin_tribulation(hero, target_index) == null:
		return hero.tribulation
	var guard := 0
	while guard < WAVE_GUARD and not hero.tribulation.is_complete():
		guard += 1
		Breakthrough.face_tribulation(hero, BodyPath.PATH_ID, rng)
	return hero.tribulation


## Climb from R1 into the Transcendent tier by earning every gate and pressing the
## same advance the Breakthrough press calls. Records what each transition had to
## earn, so the caller can assert the gates were SHUT when it arrived rather than
## merely open when it left.
##
## Bounded by `LADDER_GUARD`, which names the condition that failed to converge: a
## gate that never opens stops the climb, and the caller asserts the realm reached.
func _climbed_to_the_tier(hero: Actor) -> Array:
	var records: Array = []
	var tier_realm := _realm_id(WorldAnchor.COMMIT_MICRO)
	var guard := 0
	while hero.path(BodyPath.PATH_ID).rank_id != tier_realm and guard < LADDER_GUARD:
		guard += 1
		var index := _next_index(hero)
		if index < 0:
			break
		var gated := index >= Breakthrough.IMMORTAL_REALM_THRESHOLD
		var gate_before := Breakthrough.tribulation_ok(hero, index)
		_fought_once(hero, index, _roll_winning())
		var won := Breakthrough.tribulation_ok(hero, index)
		var advanced := Breakthrough.try_advance_gated(hero, BodyPath.PATH_ID)
		(
			records
			. append(
				{
					"index": index,
					"gated": gated,
					"gate_before": gate_before,
					"won": won,
					"gate_after": Breakthrough.tribulation_ok(hero, index),
					"advanced": advanced,
					"rank": hero.path(BodyPath.PATH_ID).rank_id,
				}
			)
		)
		# A transition that did not advance ends the climb: spinning the ladder guard
		# on a gate that never opens would bury the one line naming which gate it was.
		if not advanced:
			break
	return records


## Walk the ascent by pressing the screen's own button, and nothing else.
func _pressed_ascent(screen: Control) -> int:
	var pressed := 0
	var guard := 0
	while guard < ASCENT_GUARD and int(_ascent(screen.summary() as Dictionary)["steps"]) > 0:
		guard += 1
		if not screen.call("act_ascend"):
			break
		pressed += 1
	return pressed


# --- The proof ------------------------------------------------------------------


## The whole leg, in one walk, with nothing waived: every tribulation fought through
## core's production entry, every high tier entered by the advance that commits its
## own milestone, the ascent walked by pressing the screen.
func test_a_player_reaches_r30_with_every_gate_earned() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)

	# The seeds are the guarantee, checked here so a retune of either bound is a red
	# in this file rather than a coin flip in it.
	assert_eq(
		_seed_side(TribulationEndurance.MIN_ENDURANCE, false),
		true,
		"the pinned winning seed draws below the floor every rating clamps to"
	)
	assert_eq(
		_seed_side(TribulationEndurance.MAX_ENDURANCE, true),
		true,
		"the pinned losing seed draws at or above the ceiling"
	)

	var records := _climbed_to_the_tier(hero)
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(WorldAnchor.COMMIT_MICRO)),
		"R1 -> R28 on earned fights and earned advances"
	)
	# Every high-tier transition of the climb started SHUT and was earned. This is
	# the traversal suite's claim, made here on the same walk that never granted a
	# milestone — so the two files disagree about nothing and agree about everything.
	var gated := 0
	for step: Dictionary in records:
		if not bool(step["gated"]):
			assert_eq(step["gate_before"], true, "R%d owes no fight" % (int(step["index"]) + 1))
			continue
		gated += 1
		assert_eq(step["gate_before"], false, "R%d started shut" % (int(step["index"]) + 1))
		assert_eq(step["won"], true, "R%d was fought and survived" % (int(step["index"]) + 1))
		assert_eq(step["advanced"], true, "R%d was entered" % (int(step["index"]) + 1))
		assert_eq(step["rank"], _realm_id(int(step["index"])), "and the rank is the target")
	assert_eq(
		gated,
		WorldAnchor.COMMIT_MICRO - Breakthrough.IMMORTAL_REALM_THRESHOLD + 1,
		"every gated transition of the climb, R19 through R28"
	)

	# The advance into R28 is what BEGAN the ascent and built the world — not this
	# file. Assert the state a hand-written commit would have had to fake.
	assert_ne(hero.ascension, null, "entering R28 began the ascent")
	assert_eq(hero.ascension.steps, 0, "and walked none of it")
	assert_ne(hero.world, null, "and built the world the R29 gate reads")

	# The ascent, by pressing. Four presses of the screen's own button.
	screen.setup(hero)
	var offered := _ascent(screen.summary() as Dictionary)
	assert_eq(bool(offered["required"]), true, "so the screen offers the ascent")
	assert_eq(int(offered["steps"]), AscensionState.ASCENT_STEPS, "with every step to walk")
	assert_ne(String(offered["outstanding"]), "", "and says what is outstanding")
	var pressed := _pressed_ascent(screen)
	assert_eq(pressed, AscensionState.ASCENT_STEPS, "the player walked every step, by pressing")
	var climbed := _ascent(screen.summary() as Dictionary)
	assert_eq(int(climbed["steps"]), 0, "and the screen shows none left")
	assert_eq(String(climbed["outstanding"]), "", "with nothing outstanding")
	assert_eq(bool(climbed["met"]), true, "and the ascent gate reads open")

	# The two remaining transitions: R28 -> R29 and R29 -> R30, each a fought tribulation
	# and then the advance that commits the milestone it produces.
	var guard := 0
	while hero.path(BodyPath.PATH_ID).rank_id != _realm_id(TERMINAL) and guard < LADDER_GUARD:
		guard += 1
		var index := _next_index(hero)
		if index < 0:
			break
		var gate_before := Breakthrough.tribulation_ok(hero, index)
		_fought_once(hero, index, _roll_winning())
		assert_eq(
			Breakthrough.tribulation_ok(hero, index), true, "R%d fought and won" % (index + 1)
		)
		assert_eq(
			Breakthrough.try_advance_gated(hero, BodyPath.PATH_ID),
			true,
			"R%d entered" % (index + 1)
		)
		assert_eq(
			gate_before,
			false,
			"R%d started shut, so the advance above was the thing that opened it" % (index + 1)
		)
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(TERMINAL)),
		"the hero stands at the terminal realm, reached by playing"
	)
	assert_eq(
		RealmDefaults.ladder().next(_realm_id(TERMINAL)), null, "which is the end of the ladder"
	)
	screen.free()


## The milestone is the advance's, not the test's. A hero whose R28 rank was written
## by hand has fought the R29 tribulation and is STILL refused, and the thing refusing
## it is named. This is what makes the absence of a test-side `WorldAnchor.commit`
## above mean something: the hand-grant is not a convenience, it is the gate.
func test_the_milestone_is_the_advances_and_not_the_tests() -> void:
	var hero := _hero()
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(WorldAnchor.COMMIT_MICRO)))

	assert_eq(hero.ascension, null, "a rank written by hand begins no ascent")
	assert_eq(hero.world, null, "and creates no world")
	_fought_once(hero, WorldAnchor.COMMIT_MICRO + 1, _roll_winning())
	assert_eq(
		Breakthrough.tribulation_ok(hero, WorldAnchor.COMMIT_MICRO + 1),
		true,
		"the R29 tribulation can be fought and won on its own, through core's entry point"
	)
	assert_eq(
		Breakthrough.inside_world_ok(hero, WorldAnchor.COMMIT_MICRO + 1),
		false,
		"but the world the R29 gate reads is still missing"
	)
	assert_ne(
		WorldAnchor.ascension_unmet(hero),
		"",
		"and the shortfall is reported rather than silently absent"
	)
	assert_eq(
		Breakthrough.try_advance_gated(hero, BodyPath.PATH_ID),
		false,
		"so R29 is refused even to a hero who won its fight"
	)
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(WorldAnchor.COMMIT_MICRO)),
		"and the hero has not moved"
	)


# --- The negative ---------------------------------------------------------------
#
# A test that only ever passes protects nothing. These two run the SAME walk on the
# losing seed and require the terminal realm to stay out of reach, by name.


## The fight is load-bearing: lose it and the ascent being fully walked does not help,
## `act_breakthrough` refuses, and the screen names the tribulation as the gate.
func test_a_lost_fight_leaves_r30_unreachable_and_names_the_gate() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)
	_climbed_to_the_tier(hero)
	screen.setup(hero)
	_pressed_ascent(screen)

	# Everything but the fight is now earned and open. A refusal below is therefore
	# attributable to the fight and to nothing else.
	var index := _next_index(hero)
	assert_eq(index, WorldAnchor.COMMIT_MICRO + 1, "R29 is the realm in front of this hero")
	var record := _fought_once(hero, index, _roll_losing())
	assert_ne(record, null, "one seed, one fight, one verdict")
	assert_eq(
		record.survived(),
		false,
		"and on the losing seed the R29 tribulation is lost: %s" % [record.outcome]
	)
	assert_eq(Breakthrough.tribulation_ok(hero, index), false, "so its gate is shut")

	var gates := (screen.summary() as Dictionary)["tier_gates"] as Dictionary
	assert_eq(bool(gates["ascent"]), true, "the ascent is walked and open")
	assert_eq(bool(gates["inside_world"]), true, "the world the gate reads is there")
	assert_eq(bool(gates["world"]), true, "and stable")
	assert_eq(bool(gates["tribulation"]), false, "only the fight is shut")

	assert_eq(screen.call("act_breakthrough"), false, "so the screen's own Breakthrough refuses")
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(WorldAnchor.COMMIT_MICRO)),
		"and the hero has not moved"
	)
	assert_ne(
		RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id),
		null,
		"there is still a realm in front of them"
	)
	# The refusal names itself, so the player is told which gate to go and open. Only
	# the tribulation: every other high-tier gate above is asserted open, and the
	# body's own training work is not a gate and must not be mistaken for one.
	var unmet := (screen.summary() as Dictionary).get("unmet", []) as Array
	assert_eq(
		_clauses_about(unmet, "tribulation"),
		["Survive a tribulation fought for this realm"],
		"and names the tribulation as a high-tier gate outstanding"
	)
	assert_eq(_clauses_about(unmet, "ascent"), [], "and names no ascent clause — it was walked")
	screen.free()


## The ascent is load-bearing the same way: at R28 the walk has not been made, so
## R29 is shut on the ASCENT clause even though the fight has been won.
func test_an_unwalked_ascent_shuts_r29_on_the_ascent_clause() -> void:
	var screen := _screen()
	if screen == null:
		return
	var hero := _hero()
	screen.setup(hero)
	_climbed_to_the_tier(hero)
	screen.setup(hero)

	var index := _next_index(hero)
	assert_eq(index, WorldAnchor.COMMIT_MICRO + 1, "R29 is the realm in front of this hero")
	_fought_once(hero, index, _roll_winning())
	assert_eq(Breakthrough.tribulation_ok(hero, index), true, "and its tribulation is won")
	assert_eq(
		Breakthrough.ascension_ok(hero, index), false, "but nothing has walked the ascent yet"
	)
	assert_eq(
		Breakthrough.try_advance_gated(hero, BodyPath.PATH_ID),
		false,
		"so R29 is refused on a won fight"
	)
	var unmet := (screen.summary() as Dictionary).get("unmet", []) as Array
	assert_eq(
		_clauses_about(unmet, "tribulation"), [], "no tribulation is outstanding — it was won"
	)
	assert_eq(
		_ascent(screen.summary() as Dictionary)["outstanding"],
		(
			"Walk the ascent: %d of %d steps to walk"
			% [AscensionState.ASCENT_STEPS, AscensionState.ASCENT_STEPS]
		),
		"and the ascent is what the screen says is outstanding"
	)
	screen.free()


## The unmet clauses naming `subject`, so a negative above can name the gate that is
## refusing without also swallowing the body's own training work.
func _clauses_about(unmet: Array, subject: String) -> Array[String]:
	var found: Array[String] = []
	for clause in unmet:
		if String(clause).to_lower().contains(subject):
			found.append(String(clause))
	return found


# --- The body path's own leg ---------------------------------------------------
#
# THE GAP THIS FILE HAD, and it was not "the body is unproven" — `test_full_traversal.gd`
# walks all 30 realms through `BodyAdvancement.try_breakthrough`. It was that the walk
# above, the one cited as the terminal-realm leg, drives `Breakthrough` DIRECTLY and so
# proves core's ladder is satisfiable rather than that the body's verb is: it never
# calls `BodyTraining.cultivate`, never satisfies `BodyBreakthroughCondition`, and
# never presses `BodyCultivationApi.attempt_breakthrough` at all.
#
# That verb was the broken one. It supplies no generator, so before DEF-0250 every
# press committed seed 0, drew 0.202272, and sat BELOW every realm's chance band — so
# every press was a certain success, never a trial. This walk was therefore reachable
# but never actually rolled anything, and the file above was green throughout: nothing
# in it could tell a real crossing from a rigged one.
#
# So this is the same claim the file above makes, made through the body path: every
# gate earned, the training paid for, and the realm entered by pressing the verb a
# player presses. It adds to what is above and weakens none of it.


## R1 -> R30 on the body's own breakthrough verb, with no generator anywhere.
##
## Nothing here is waived. The tribulation is fought through
## `Breakthrough.face_tribulation` on the file's pinned surviving seed — the same
## device the three cases above use, and the same guarantee, which `_seed_side` checks
## rather than this file hoping for. The training is `BodyPlayFixture.prepare`, which
## only ever calls `cultivate`, `meditate`, `strengthen` and `recover`, so
## `BodyBreakthroughCondition` is satisfied the way it is satisfied in play.
func test_the_body_path_reaches_r30_through_its_own_breakthrough_verb() -> void:
	var play := BodyPlayFixture.new()
	var hero := play.actor(&"qi_refining")
	# One rung per iteration and the ladder is 30 long, so the cap is the whole climb
	# plus slack. Its body check names the rung that would not converge.
	var visited: Array[StringName] = [hero.path(BodyPath.PATH_ID).rank_id]
	var pressed_total := 0
	var rungs := 0
	while rungs < LADDER_GUARD:
		rungs += 1
		var index := _next_index(hero)
		if index < 0:
			break
		var before := hero.path(BodyPath.PATH_ID).rank_id
		# The fight, through the same entry the commit makes on every attempt.
		_fought_once(hero, index, _roll_winning())
		var presses := 0
		var advanced := false
		# Bounded by `BODY_PRESS_GUARD`: a press spends either a wave of the fight or
		# the breakthrough's own roll, and 96 rolls at the lowest authored chance
		# landing the same way is 0.742^96 ~= 4e-13.
		while presses < BODY_PRESS_GUARD and not advanced:
			presses += 1
			if play.prepare(hero) == null:
				break
			# THE VERB. No rng argument exists for it, so its roll comes from the seed
			# its own commit drew, which is the whole point of this case.
			advanced = BodyCultivationApi.attempt_breakthrough(hero)
			if not advanced:
				# What a player does after a refusal or a deviation: repair, refill,
				# train, press again.
				play.recover_damage(hero)
		pressed_total += presses
		if not advanced:
			break
		var after: StringName = hero.path(BodyPath.PATH_ID).rank_id
		visited.append(after)
		assert_eq(
			after,
			_realm_id(index),
			(
				"rung %d: a press reported an advance and the rank moved %s -> %s (index %d)"
				% [rungs, before, after, index]
			)
		)
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(_realm_id(TERMINAL)),
		"the body path stands at the terminal realm, reached by pressing its own verb"
	)
	assert_eq(visited.size(), 30, "and visited all 30 realms, none of them written by hand")
	assert_eq(
		RealmDefaults.ladder().next(_realm_id(TERMINAL)),
		null,
		"which is the end of the ladder, and no realm was added by a test to get there"
	)
	assert_eq(
		pressed_total > 29,
		true,
		"spending %d presses over 29 rungs, so the roll really was rolled" % pressed_total
	)
	# Not asserted: that a deviation occurred. Over 29 rungs the chance that every roll
	# came out the winning way is far below any bound worth writing, and a case that
	# needs luck to prove a loop works is a case that would flake. `test_body_
	# breakthrough_roll.gd` measures the two-sided distribution instead.
	hero.resources.clear()
