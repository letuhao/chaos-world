extends TestCase

## ONE tribulation encounter: one wave driver, one survival formula, one owed-realm
## rule (ADR 0125).
##
## Four implementations had grown for what ADR 0061 described as one thing, and a
## player paid a real cost on one path for free on another:
##
##   - `Tribulation.fight_wave` charged `WAVE_TOLL` and rolled.
##   - `TribulationFight.fight_wave` called `Breakthrough.advance_tribulation`, which
##     walks the phase machine WITHOUT charging the toll, and rolled the verdict
##     itself. The same fight cost one comprehension per wave through a breakthrough
##     action and ZERO through the tribulation screen.
##   - `Tribulation.endurance()` and `TribulationEndurance.endurance()` both answered
##     "how often does this actor survive", and only the second had a caller.
##   - `TribulationFight.target_index` and `TribulationEndurance._owed_realm` both
##     derived which realm was owed, and were free to disagree about it.
##
## So this file does not test the fight. `test_tribulation_fight.gd`,
## `test_tribulation_once.gd` and `test_tribulation_gate.gd` do. It tests the thing
## that was missing: that the two ways IN lead to the same fight, at the same price,
## with the same verdict — because that is the claim nothing could check while two
## drivers existed.

## Bound on every loop here, naming what it catches: a fight that stopped converging
## would spin instead of descending. `max_waves` is authored 3..9 and the phase
## machine refuses to pass it, so 16 covers two whole fights.
const WAVE_BOUND := 16

## Seeds the equivalence test walks. Many, not one: agreement that holds for a single
## hand-picked roll could be a coincidence, agreement that holds for every roll is a
## property of the drivers.
const SEEDS := 24

# --- Fixtures ------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## Ladder index of the first realm the tribulation gate applies to.
func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## A hero standing immediately under the gate, so the fight owed is the gate's own.
## `BodyPath` because `TribulationFight` derives the owed realm from whatever the
## actor has enrolled — with one path, "the first tier owed" and "the path I am
## pressing" are the same realm, which is what makes the two routes comparable.
func _hero() -> Actor:
	var realm_id := _realm_id(_gate() - 1)
	var actor := Actor.new(&"unified_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## Whether the record carries a verdict yet. A decided record is what the gate reads,
## and a decided record must never be fought again.
func _decided(hero: Actor) -> bool:
	return hero.tribulation != null and hero.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED


## A generator whose next draw is below every possible endurance, so the fight is won
## whatever the rating works out at.
func _won_roll() -> RandomNumberGenerator:
	return _seeded(TribulationEndurance.MIN_ENDURANCE, true)


## A generator whose next draw is at or above every possible endurance, so the fight
## is lost whatever the rating works out at.
func _lost_roll() -> RandomNumberGenerator:
	return _seeded(TribulationEndurance.MAX_ENDURANCE, false)


func _seeded(threshold: float, below: bool) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() < threshold) == below:
			rng.seed = seed_value
			return rng
	return rng


# --- The two routes ------------------------------------------------------------


## The breakthrough button's route, verbatim: `face_tribulation` begins the owed fight
## and descends ONE wave, and says the gate as it stood BEFORE the call.
func _drive_via_breakthrough(hero: Actor, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while guard < WAVE_BOUND and not _decided(hero):
		guard += 1
		Breakthrough.face_tribulation(hero, BodyPath.PATH_ID, rng)


## The tribulation screen's route, verbatim: `begin` then `fight_wave` until decided.
func _drive_via_screen(hero: Actor, rng: RandomNumberGenerator) -> void:
	TribulationFight.begin(hero)
	var guard := 0
	while guard < WAVE_BOUND and not _decided(hero):
		guard += 1
		if not bool(TribulationFight.fight_wave(hero, rng).get("ok", false)):
			return


## One actor, one fight, taken by one route with a generator seeded to `seed_value`.
func _fought(route: StringName, seed_value: int) -> Actor:
	var hero := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if route == &"breakthrough":
		_drive_via_breakthrough(hero, rng)
	else:
		_drive_via_screen(hero, rng)
	return hero


# --- The defect, in one assertion ------------------------------------------------


## THE claim. The same actor, the same owed fight, taken through the breakthrough
## action and through the tribulation screen, ends decided the same way and has paid
## the same dao heart.
##
## Walked over many seeds rather than one, because the deciding roll is real: a single
## seed could agree by luck, and only agreement that survives every roll is a property
## of the drivers rather than of the draw.
func test_both_routes_to_the_fight_end_in_the_same_state_and_pay_the_same_price() -> void:
	for offset in range(SEEDS):
		var seed_value := offset + 1
		var via_breakthrough := _fought(&"breakthrough", seed_value)
		var via_screen := _fought(&"screen", seed_value)
		var label := "seed %d" % seed_value
		assert_ne(via_breakthrough.tribulation, null, "%s: the button began a fight" % label)
		assert_ne(via_screen.tribulation, null, "%s: the screen began a fight" % label)
		assert_ne(_decided(via_breakthrough), false, "%s: the button reached a verdict" % label)
		assert_ne(_decided(via_screen), false, "%s: the screen reached a verdict" % label)
		assert_eq(
			via_screen.tribulation.outcome,
			via_breakthrough.tribulation.outcome,
			"%s: same verdict" % label
		)
		assert_eq(
			via_screen.stats.get_base(Stat.COMPREHENSION),
			via_breakthrough.stats.get_base(Stat.COMPREHENSION),
			"%s: same dao heart" % label
		)
		assert_eq(
			via_screen.tribulation.wave, via_breakthrough.tribulation.wave, "%s: same wave" % label
		)
		assert_eq(
			Breakthrough.tribulation_ok(via_screen, _gate()),
			Breakthrough.tribulation_ok(via_breakthrough, _gate()),
			"%s: same gate" % label
		)


## Not a consequence of the first assertion but the reason it can hold: both routes
## fight the SAME fight. Two implementations of "which realm is owed" meant the screen
## could bind a record to one realm while the gate was waiting on another, and then
## both verdicts would have been verdicts about different fights.
func test_both_routes_bind_and_price_the_same_fight() -> void:
	var gate_realm := _realm_id(_gate())
	assert_eq(
		TribulationFight.target_realm(_hero()), gate_realm, "the module owes the gate's realm"
	)
	assert_eq(Breakthrough.owed_realm(_hero()), gate_realm, "and core derives the same realm")
	var via_breakthrough := _fought(&"breakthrough", 3)
	var via_screen := _fought(&"screen", 3)
	assert_eq(
		String(via_screen.tribulation.realm_id), gate_realm, "the screen's fight is bound to it"
	)
	assert_eq(
		via_screen.tribulation.max_waves,
		via_breakthrough.tribulation.max_waves,
		"the screen's fight drags on as long"
	)
	assert_eq(
		via_screen.tribulation.difficulty,
		via_breakthrough.tribulation.difficulty,
		"and is fought at the same rating"
	)


## The toll, measured wave by wave through the SCREEN's own surface, which is where it
## was not being charged at all. Measured only on undecided waves, because the deciding
## wave pays its toll and a reward at once and the two cancel into something that would
## make this assertion pass for the wrong reason.
func test_every_wave_the_screen_fights_costs_exactly_one_toll() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var before := hero.stats.get_base(Stat.COMPREHENSION)
	var rng := _won_roll()
	var waves := 0
	var guard := 0
	while guard < WAVE_BOUND:
		guard += 1
		var step := TribulationFight.fight_wave(hero, rng)
		if bool(step.get("decided", false)):
			break
		waves += 1
		assert_eq(
			hero.stats.get_base(Stat.COMPREHENSION),
			before - float(waves) * Tribulation.WAVE_TOLL,
			"wave %d from the screen cost one toll" % waves
		)
	assert_ne(waves, 0, "the fight took more than one wave, so a driver was measured")


## The same measurement on the breakthrough route, so the two are asserted against the
## same number rather than one against the other.
func test_every_wave_the_breakthrough_button_fights_costs_exactly_one_toll() -> void:
	var hero := _hero()
	var before := hero.stats.get_base(Stat.COMPREHENSION)
	var rng := _won_roll()
	var waves := 0
	var guard := 0
	while guard < WAVE_BOUND and not _decided(hero):
		guard += 1
		Breakthrough.face_tribulation(hero, BodyPath.PATH_ID, rng)
		if _decided(hero):
			break
		waves += 1
		assert_eq(
			hero.stats.get_base(Stat.COMPREHENSION),
			before - float(waves) * Tribulation.WAVE_TOLL,
			"wave %d from the button cost one toll" % waves
		)
	assert_ne(waves, 0, "the fight took more than one wave, so a driver was measured")


## One roll per fight, whichever route took it. `state` is the generator's own PCG
## position, so two runs that finish in the same position consumed the same number of
## draws — a module that rolled AND let the record roll would end up somewhere else,
## and a fight whose odds the player saw were not the odds the roll used.
func test_either_route_consumes_exactly_one_draw_for_a_whole_fight() -> void:
	var via_breakthrough := _hero()
	var first := _won_roll()
	_drive_via_breakthrough(via_breakthrough, first)
	var via_screen := _hero()
	var second := _won_roll()
	_drive_via_screen(via_screen, second)
	assert_eq(second.state, first.state, "both generators ended in the same position")


## A fight the screen cannot lose becomes a formality the moment the toll is real, so
## the losing branch has to stay reachable from the screen too: it is the branch whose
## absence was the point of routing the fight back through the record.
func test_the_screen_can_still_lose_and_the_gate_stays_shut() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var result := TribulationFight.fight_to_verdict(hero, _lost_roll())
	assert_eq(bool(result.get("decided", false)), true, "the fight was decided")
	assert_eq(bool(result.get("survived", false)), false, "and lost")
	assert_eq(String(hero.tribulation.outcome), String(Tribulation.OUTCOME_FAILED), "recorded")
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), false, "the gate stayed shut")
	assert_eq(hero.has_status(&"heavenly_blessing"), false, "and paid nothing")
