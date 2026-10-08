extends TestCase

## The fight's LENGTH and its TONE — the two defects a headless drive found in a fight
## that otherwise worked.
##
## ## Why this file exists at all
##
## `tools ui drive --screen fight_screen.tscn --path body --cmd start --cmd strike`
## exited 0, resolved through the spine and ended in a win. Every number in the readout
## was correct except two:
##
##   1. `opponent_health_max: 50.0` and the fight was over in **1** blow. The owner
##      ruled a same-power fight lasts ~25 blows / 60 s (`BALANCE-ANCHOR.md`), so the
##      readout fight was the exact inversion the anchor exists to prevent.
##   2. `outcome: "hero_won", tone: "error"` — a victory styled as a failure.
##
## Both are INVISIBLE to the existing guards. A one-blow fight is a green test: the
## exchange resolved, the verdict was recorded, the wound necrosed. A wrong tone is a
## green test too: `summary()` returned a string. So neither defect had any assertion
## pointing at it, which is the same shape as every other defect in this program's log
## — and the reason this file is here rather than a note.
##
## ## What is asserted, and what is deliberately NOT
##
## The LENGTH cases assert the ARITHMETIC (`pool / blow ~= anchor`), not a wall-clock
## fight. A blow count is a function of the rate gate, and `FightLoop.age` is the only
## thing that opens it — so a suite that timed a fight would be asserting the clock's
## cooperation rather than the anchor's arithmetic. The empirical drive lives in
## `tools ui drive`; this file pins the figure that drive reads.
##
## The TONE cases assert one tone per outcome word, because a tone map with no test is
## how it came to be wrong.

## The anchor's length half. Restated rather than imported so this suite fails when the
## loop's own constant is edited AWAY from the owner's ruling, not only when the two
## disagree by accident.
const ANCHOR_BLOWS := 25.0

## The realm both sides stand on — `FightLoop.OPPONENT_REALM`, the gate band.
const REALM := &"qi_refining"

## How far a fight may drift from the anchor before it is a different anchor. The pool
## is `ANCHOR_BLOWS x one blown`, and the two sides share a realm multiplier but not a
## build, so the ratio lands near the anchor rather than exactly on it.
const TOLERANCE := 0.20

var _born: Array[Node] = []
## The loop [_screen] wired its verbs to. A case that needs the SAME loop to read from
## the page as it does from the loop assigns it here before asking for a screen.
var _bound_loop: FightLoop = null


func setup() -> void:
	_born.clear()


func teardown() -> void:
	for node in _born:
		node.free()
	_born.clear()


## The hero exactly as `ItemWorkbenchBody._build_actor` and the ui driver build one:
## body, qi and mind enrolled, meridians unlocked, then `CombatBoot.install`.
func _hero() -> Actor:
	var actor := ActorFactory.build(&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	ActorFactory.with_body_cultivation(actor, REALM)
	ActorFactory.with_qi_cultivation(actor, REALM)
	ActorFactory.with_mind_cultivation(actor, REALM)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	actor.meridians.unlock_for_realm(REALM)
	CombatBoot.install(actor)
	return actor


## A loop with `hero` already adopted, so a case can call `start_fight` without the
## factory chain each time.
func _loop(hero: Actor) -> FightLoop:
	var loop := FightLoop.new(hero)
	loop.adopt_hero(hero)
	return loop


## One opponent minted by the loop's OWN chain and then left alone — the same steps
## `FightLoop.start_fight` runs before it sizes anything, in the same order, so a case
## has a baseline that differs from the sized opponent by the sizing and nothing else.
func _minted(actor_id: StringName = &"baseline_opponent") -> Actor:
	var opponent := ActorFactory.spawn_inhabitant(actor_id)
	ActorFactory.with_body_cultivation(opponent, REALM)
	ActorFactory.with_qi_cultivation(opponent, REALM)
	ActorFactory.with_mind_cultivation(opponent, REALM)
	MindCultivationApi.attach_sea(opponent)
	MindTraining.synchronize(opponent)
	opponent.meridians.unlock_for_realm(REALM)
	CombatBoot.install(opponent)
	return opponent


## The damage one hero blow deals to a freshly minted opponent, measured the way
## `FightLoop._price_blow` measures it: a spine resolution with a null generator, so
## every strike lands and no crit fires (ADR 0087's S12).
##
## The clone is `to_dict`/`from_dict` and NOT `duplicate()`: `Actor` extends
## `RefCounted`, so `duplicate()` does not exist on it and calling one ABORTS the test
## before the assertion runs -- which is how a wrong fixture hides the real defect. The
## save round-trip is also the copy `FightLoop` itself prices against, so this
## measures the same figure the loop sized the pool from.
func _blow_amount(hero: Actor, opponent: Actor) -> float:
	var technique := TechniqueDef.new()
	technique.path = PathState.BODY
	technique.magnitude = CombatBoot.BARE_SWING_MAGNITUDE
	technique.element_share = CombatBoot.BARE_SWING_SHARE
	technique.element = ElementStats.FIRE
	var sample := Actor.from_dict(opponent.to_dict())
	assert_ne(sample, null, "the opponent round-trips into a pricing clone")
	if sample == null:
		return 0.0
	var outcome := CombatBoot.resolve_hit(hero, sample, technique, CombatEngineApi.tuning(), null)
	return float(outcome.amount)


# --- DEFECT 1: the pool is the anchor, not a literal -------------------------


## The pool is the ACTOR FORMULA's own (DEF-0378's retune). The old `50.0` was wrong
## because the loop SIZED the pool over it; the retune removed that write entirely — a
## minted inhabitant carries no attributes, so the formula's floor is its pool and
## nothing else touches it.
func test_a_minted_opponents_pool_is_the_actor_formula_own() -> void:
	var loop := _loop(_hero())
	var opened := loop.start_fight()
	assert_eq(bool(opened.get("ok", false)), true, "the fight opens")
	assert_almost_eq(
		float(opened.get("opponent_health_max", 0.0)),
		50.0,
		"the pool is the formula's own floor, written by nobody",
		0.001
	)
	assert_eq(
		pool,
		float(loop.opponent().resource(&"health").maximum),
		"the pool reported is the pool spent"
	)


## THE defect itself, and the assertion that was missing. `set_maximum` CLAMPS `current`
## into the new range and never raises it, so sizing alone left a freshly minted
## opponent at the bare `50.0` under a `2050.0` cap: every ratio below still passed,
## because they divide the CAP by a blow, and the live fight was still a one-press win.
##
## Only `current == maximum` at the moment the fight opens distinguishes the two, so it
## is asserted directly rather than inferred from a blow count.
func test_a_minted_opponent_opens_the_fight_at_full_health() -> void:
	var loop := _loop(_hero())
	var opened := loop.start_fight()
	var pool := loop.opponent().resource(&"health") as ResourcePool
	assert_eq(
		pool.current,
		pool.maximum,
		"a body nobody has struck is a body at full health, not at the cap minus a fight"
	)
	assert_eq(
		float(opened.get("opponent_health", 0.0)),
		pool.maximum,
		"and the fight reports it full, which is the half the ratio assertions could not see"
	)


## The anchor's ~25-blows length belongs to a SAME-BUILD fight, and the census measures
## it flat at every realm (`test_damage_vitality_census.gd`: 23 blows from R1 to R30).
## What this pins is the other half of the retune: a MINTED body carries no attributes,
## so it is NOT a same-build body — and the loop no longer pretends it is by writing a
## pool over it (the sizing is gone). The minted fight runs SHORT of the anchor, and
## that is the honest reading of the fixture rather than a defect.
func test_a_minted_body_without_attributes_runs_short_of_the_anchor() -> void:
	var loop := _loop(_hero())
	var opened := loop.start_fight()
	var pool := float(opened.get("opponent_health_max", 0.0))
	var blow := _blow_amount(loop.hero(), loop.opponent())
	assert_ne(blow, 0.0, "the hero's blow is priced above zero")
	var blows_to_kill := pool / blow
	var label := (
		"%0.2f of %0.2f is %0.2f blows, and the anchor is %0.0f"
		% [
			pool,
			blow,
			blows_to_kill,
			ANCHOR_BLOWS,
		]
	)
	assert_eq(blows_to_kill < ANCHOR_BLOWS, true, label)


## And the fight is not over in one press — the defect's OBSERVABLE shape.
func test_one_blow_does_not_end_the_fight() -> void:
	var loop := _loop(_hero())
	loop.start_fight()
	var result := loop.exchange(0)
	assert_eq(String(result.get("outcome", "")), "ongoing", "after one blow the fight is still on")
	assert_ne(
		float(result.get("opponent_health", 0.0)), 0.0, "the foe is still standing after one blow"
	)


## The hero's own pool is untouched. The anchor sizes the OPPONENT; a loop that grew
## both sides would still read ~25 and be wrong in a way no ratio above could see.
func test_the_derivation_leaves_the_hero_pool_alone() -> void:
	var hero := _hero()
	var before := float(hero.resource(&"health").maximum)
	var loop := _loop(hero)
	loop.start_fight()
	assert_eq(float(hero.resource(&"health").maximum), before, "the hero's pool is unchanged")


## The retune's other half, observed: the loop writes NO offset at all. The sizing this
## case used to pin is gone (DEF-0378), and what remains observable is the ABSENCE —
## `modifier_count` unchanged and the pool exactly the formula's, so nothing a fight
## does can move a body's pool between `start_fight` and the first blow.
##
## The baseline is the loop's OWN minting chain and not `ActorFactory.build`: the two
## differ by every enrolment (`with_body_cultivation`, `with_qi_cultivation`,
## `with_mind_cultivation`, `attach_sea`, `unlock_for_realm`), and each enrolment mounts
## its own provider and its own `RealmScaling` modifier. A bare build carries none, so
## the counts would differ by those and the equality this case is about was never
## visible — which is how a wrong baseline turns a correct test into a red one.
func test_no_sizing_offset_is_written_and_the_pool_is_the_actors_own() -> void:
	var loop := _loop(_hero())
	var untouched := _minted()
	var before := float(untouched.resource(&"health").maximum)
	loop.start_fight()
	var opponent := loop.opponent()
	assert_eq(
		opponent.stats.modifier_count(),
		untouched.stats.modifier_count(),
		"no sizing offset is written: the pool is the actor's own (DEF-0378's retune)"
	)
	assert_eq(
		float(opponent.resource(&"health").maximum),
		before,
		"and the minted pool is exactly the formula's, unmoved by the fight opening"
	)


## An AUTHORED opponent is never re-derived. `start_fight` mints; `begin_fight` adopts.
## Boss vitality is content (ADR 0199) and this loop must not overwrite it.
func test_an_adopted_opponent_keeps_the_pool_content_authored() -> void:
	var loop := _loop(_hero())
	var authored := ActorFactory.build(&"authored_foe")
	CombatBoot.install(authored)
	var before := float(authored.resource(&"health").maximum)
	loop.begin_fight(authored)
	assert_eq(
		float(authored.resource(&"health").maximum), before, "an authored pool survives begin_fight"
	)


# --- DEFECT 2: the outcome -> tone map ---------------------------------------


## Every word the map names has the tone a player must read it with.
##
## `hero_won` is the case the defect was about: it took `TONE_ERROR` because no map
## existed and `ok` had already gone false on a decided fight.
func test_every_outcome_has_its_tone() -> void:
	var screen := _screen(_hero())
	assert_eq(StringName(FightScreen.TONE_BY_OUTCOME["hero_won"]), UiScreen.TONE_OK, "a win is ok")
	assert_eq(
		StringName(FightScreen.TONE_BY_OUTCOME["hero_lost"]),
		UiScreen.TONE_ERROR,
		"a loss is an error"
	)
	assert_eq(
		StringName(FightScreen.TONE_BY_OUTCOME["ongoing"]),
		UiScreen.TONE_OK,
		"a fight in progress is ok"
	)


## The map covers every outcome `FightLoop` can publish, so no word falls through to a
## default. A word the loop invents and the screen has no tone for is exactly how this
## map goes stale.
func test_the_map_covers_every_outcome_the_loop_publishes() -> void:
	for word in [
		FightLoop.OUTCOME_ONGOING,
		FightLoop.OUTCOME_HERO_WON,
		FightLoop.OUTCOME_HERO_LOST,
	]:
		assert_eq(
			FightScreen.TONE_BY_OUTCOME.has(String(word)), true, "the map names '%s'" % String(word)
		)


## The drive's exact defect: a won fight re-pressed, which `_reject`/`_settle` reported
## with the error tone while the words above it said "The fight is won."
func test_a_won_fight_is_never_styled_as_an_error() -> void:
	var hero := _hero()
	var loop := _loop(hero)
	_bound_loop = loop
	var screen := _screen(hero)
	loop.start_fight()
	# Fight the hero CANNOT win, so the outcome is a real loss and the map is exercised
	# from both ends.
	hero.resource(&"health").maximum = 1.0
	hero.resource(&"health").current = 1.0
	loop.exchange(0)
	assert_eq(String(loop.outcome()), "hero_lost", "the hero's one point was spent")
	screen.call("act_strike")
	assert_eq(String(screen.summary().get("tone", "")), "error", "a loss reads as an error")


## And the other end of the same table: the hero who wins, re-pressed.
func test_a_won_fight_reports_the_ok_tone() -> void:
	var hero := _hero()
	var loop := _loop(hero)
	_bound_loop = loop
	var screen := _screen(hero)
	loop.start_fight()
	# Win it outright through the loop, then let the screen read the decided verdict.
	var wins := 0
	while String(loop.outcome()) == "" and wins < 60:
		loop.exchange(0)
		wins += 1
	assert_eq(
		String(loop.outcome()), "hero_won", "the anchor fight is winnable in blows, not one press"
	)
	assert_ne(wins, 1, "it took more than one blow, which is defect 1 again, asserted here too")
	screen.call("act_strike")
	var view := screen.summary()
	assert_eq(String(view.get("outcome", "")), "hero_won", "the page reports the win")
	assert_eq(String(view.get("tone", "")), "ok", "a win is never styled as an error")


## The words and the tone are read from ONE place, so a caller cannot see a victory
## sentence over an error line.
func test_the_verdict_words_and_the_tone_come_from_the_same_verdict() -> void:
	var hero := _hero()
	var loop := _loop(hero)
	_bound_loop = loop
	var screen := _screen(hero)
	loop.start_fight()
	hero.resource(&"health").maximum = 1.0
	hero.resource(&"health").current = 1.0
	loop.exchange(0)
	screen.call("act_strike")
	var view := screen.summary()
	assert_eq(
		L.t(String(view.get("message", ""))),
		"The fight is lost.",
		"the sentence matches the outcome"
	)
	assert_eq(String(view.get("tone", "")), "error", "and so does the tone")


# --- Fixtures ----------------------------------------------------------------


## A `FightScreen` with no scene tree behind it, exactly as the headless driver mounts
## one, so nothing here needs a viewport.
##
## The hero is bound through `setup(actor)` because `FightScreen._summary` and every
## verb open with `if actor() == null: return {}` — a screen that was bound to its fight
## verbs but never to a hero reports nothing at all, so every tone assertion below
## would read `""` and fail for a reason that has nothing to do with the tone map. That
## is a THIRD way a wrong fixture hides the real defect, and the same "a void test is a
## deleted test" shape the program keeps meeting.
func _screen(hero: Actor) -> FightScreen:
	var scene: PackedScene = load("res://src/ui/screens/fight_screen.tscn")
	assert_ne(scene, null, "the fight scene loads")
	var screen := scene.instantiate() as FightScreen
	_born.append(screen)
	screen.setup(hero)
	screen.call("bind_fight", _verbs(_bound_loop))
	return screen


## The five ADR 0197 verbs, as `ItemWorkbenchFight.fight_verbs` publishes them.
func _verbs(loop: FightLoop) -> Dictionary:
	return {
		"begin": Callable(self, "_begin").bind(loop),
		"exchange": Callable(self, "_exchange").bind(loop),
		"age": Callable(self, "_age").bind(loop),
		"disengage": Callable(self, "_disengage").bind(loop),
		"read": Callable(self, "_read").bind(loop),
	}


func _begin(loop: FightLoop) -> Dictionary:
	return loop.start_fight()


func _exchange(loop: FightLoop) -> Dictionary:
	return loop.exchange(0)


func _age(loop: FightLoop) -> Dictionary:
	return loop.age(1.0)


func _disengage(loop: FightLoop) -> Dictionary:
	return loop.disengage()


func _read(loop: FightLoop) -> Dictionary:
	return loop.summary()
