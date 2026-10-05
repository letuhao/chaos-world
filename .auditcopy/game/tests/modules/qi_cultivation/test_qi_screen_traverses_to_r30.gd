extends TestCase

## A qi player carries a hero ACROSS the two realms the ascent gate shut: R29 and
## R30, by pressing the shipped screen's own Breakthrough.
##
## `test_qi_ascent_reaches_r30.gd` proves the ascent is offered, walked and opens
## `ascension_ok` for both realms. That is the part that was dead. This file is the
## other half: that the gate being open is enough, and that pressing the screen's own
## Breakthrough then actually enters both realms — the claim BL-0693 made about
## qi, which had never been driven end to end by anything.
##
## The ascent is walked THROUGH THE SCREEN here too, not by a helper, because a
## helper is what made every earlier proof of this ladder green while the verb had no
## caller. Everything else these gates want — channels at the demanded depth,
## progress, comprehension, a full refined dantian, the pill, and the tribulation —
## is earned through the module's production actions and the probe's shared
## fixtures, because no single press on this screen does those things.
##
## Cost is the design constraint here. The tribulation is fought ONCE per realm and
## never re-fought: `tribulation_ok` reads a decided survivor bound to the realm it
## gates, so `face_tribulation` inside the transaction returns early on every later
## press. An earlier draft re-fought it on every attempt and was expensive enough to
## trip a runner ceiling — a test that cannot finish proves nothing.

## Not a suite: the runner only collects `test_*.gd`. Its `fight` and `stock` are
## production entry points, and a tribulation is a fight a player has to win rather
## than something a test may waive (ADR 0041).
const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const SCREEN := "res://src/ui/screens/qi_cultivation_screen.tscn"

const PATH := QiPath.PATH_ID

## Presses spent on one realm's breakthrough. `QiChance.of` is 0.05 plus half the
## dantian's quality, so a prepared dantian clears 0.3 and a handful of rolls is a
## fair budget. Fixed, naming the rolls, never a count read off anything the loop
## grows.
const ROLL_BOUND := 10

## Presses spent walking the ascent; the screen refuses the step past the caps, so
## its own `false` is the exit and this only names a screen that will not stop.
const ASCENT_BOUND := 8


func _screen() -> QiCultivationScreen:
	return (load(SCREEN) as PackedScene).instantiate() as QiCultivationScreen


func _ascent_of(view: Dictionary) -> Dictionary:
	return view.get("ascent", {}) as Dictionary


## A qi hero the player's own breakthrough carried into R28 — the tier where the
## ascent begins and the two shut gates start.
func _hero_advanced_into_r28() -> Actor:
	var realms := RealmDefaults.ladder().realms()
	var hero := Actor.new(
		&"qi_traverse_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	hero.set_path(PathState.new(PATH, realms[WorldAnchor.COMMIT_MICRO - 1].id))
	QiCultivationApi.attach(hero)
	ItemsApi.attach(hero, 512)
	assert_eq(QiCultivationApi.cultivate(hero, 1.0), true, "cultivate drives synchronization")
	Breakthrough.try_advance(hero, PATH)
	return hero


## Walk the ascent by pressing the screen's own button.
func _walk_by_pressing(screen: QiCultivationScreen) -> int:
	var walked := 0
	# Bounded by a FIXED count; the loop reads the screen's own steps-to-walk and the
	# screen refuses the step past the caps, so `false` is the real exit.
	var guard := 0
	while guard < ASCENT_BOUND and int(_ascent_of(screen.summary() as Dictionary)["steps"]) > 0:
		guard += 1
		if not screen.act_ascend():
			break
		walked += 1
	return walked


## Everything the next realm's gate wants APART FROM the ascent. The ascent is the
## player's walk and is deliberately absent here.
func _earn_rest_of_gate(hero: Actor) -> void:
	var target := Probe.target_after(hero.path(PATH).rank_id)
	if target == null:
		return
	var seed := QiRealmSeed.for_realm(target.id)
	Probe.recover_all(hero)
	Probe.stock(hero, seed.breakthrough_item)
	Probe.train_gate_channels(hero, seed)
	Probe.recover_all(hero)
	Probe.earn_progress(hero, seed)
	Probe.meditate_to_floor(hero, seed.comprehension_required)
	Probe.fill_and_refine(hero, seed)
	Probe.recover_all(hero)
	Probe.fill_and_refine(hero, seed)
	Probe.stock(hero, seed.breakthrough_item)


## Earn the gate and press the screen's own Breakthrough until the realm is entered.
## A refusal is a real roll, and a deviation scars the dantian, burns a channel and
## halves progress, so the wounds are closed between attempts — cheaply, because the
## tribulation is already decided.
func _enter_next_realm(screen: QiCultivationScreen, hero: Actor) -> bool:
	var before := hero.path(PATH).rank_id
	var target := Probe.target_after(before)
	if target == null:
		return false
	Probe.fight(hero, target)
	_earn_rest_of_gate(hero)
	# Bounded by a FIXED count naming the rolls.
	for roll in range(ROLL_BOUND):
		if screen.act_breakthrough():
			return true
		_earn_rest_of_gate(hero)
	return hero.path(PATH).rank_id != before


# --- The claim -------------------------------------------------------------------


## THE test. Two realms, two presses, and no helper standing in for the ascent.
func test_a_qi_player_presses_through_r29_and_r30_on_the_screen() -> void:
	var screen := _screen()
	var hero := _hero_advanced_into_r28()
	var realms := RealmDefaults.ladder().realms()
	screen.setup(hero)

	# The ascent, by pressing, before anything else: it is the gate that was shut.
	assert_eq(
		_walk_by_pressing(screen),
		AscensionState.ASCENT_STEPS,
		"the player walked the whole ascent by pressing"
	)

	assert_eq(_enter_next_realm(screen, hero), true, "R29 is entered by a press")
	assert_eq(
		String(hero.path(PATH).rank_id),
		String(realms[WorldAnchor.COMMIT_MICRO + 1].id),
		"and the hero stands in R29"
	)
	assert_eq(
		Breakthrough.ascension_ok(hero, WorldAnchor.COMMIT_MICRO + 2),
		true,
		"whose gate is still the one the walk opened"
	)

	assert_eq(_enter_next_realm(screen, hero), true, "R30 is entered by a press")
	assert_eq(
		String(hero.path(PATH).rank_id),
		String(realms[WorldAnchor.COMMIT_MICRO + 2].id),
		"so no realm on this ladder is unreachable by a qi player"
	)
	assert_eq(
		String(realms[WorldAnchor.COMMIT_MICRO + 2].id),
		String(RealmDefaults.ladder().realms()[RealmDefaults.ladder().size() - 1].id),
		"and R30 is the top of it"
	)
	screen.free()


## A hero at the top has nothing left to advance into, so the last press is a
## refusal rather than a second R30. The ladder's end is not a gate that opens.
func test_the_screen_refuses_to_walk_past_r30() -> void:
	var screen := _screen()
	var top := RealmDefaults.ladder().size() - 1
	var hero := Actor.new(
		&"qi_terminal_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	hero.set_path(PathState.new(PATH, RealmDefaults.ladder().realms()[top].id))
	QiCultivationApi.attach(hero)
	ItemsApi.attach(hero, 64)
	screen.setup(hero)
	var view := screen.summary() as Dictionary
	assert_eq(
		String(view.get("realm", "")),
		String(RealmDefaults.ladder().realms()[top].id),
		"the hero stands at the terminal realm"
	)
	assert_eq(String(view.get("target", "")), "", "the top realm has no target to enter")
	assert_eq(screen.act_breakthrough(), false, "so Breakthrough refuses")
	assert_eq(
		String(hero.path(PATH).rank_id),
		String(RealmDefaults.ladder().realms()[top].id),
		"and the hero is still at the top"
	)
	screen.free()
