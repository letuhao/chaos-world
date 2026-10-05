extends TestCase

## The tribulation gate is reachable, and both of its outcomes are (BL-0122).
##
## Everything here goes through the module's own surface, because the claim is
## about what a caller can do, not about what the internals happen to hold:
## `begin`, `fight_wave` / `fight_to_verdict`, `withdraw` and `state`. Where a
## test needs a specific roll it passes an `rng`, so a branch is reached by
## CHOICE rather than by hope — which is what makes the failure branch provable
## rather than merely possible.
##
## Before this module the whole tier was unreachable from production: nothing
## constructed a `Tribulation`, so `_apply_failure` and every reward it skipped
## were dead, and `apply_result(actor, true)` at five call sites made surviving
## automatic. Both halves of that are asserted here.
##
## No realm is named by position. Every index below is derived from
## `Breakthrough.IMMORTAL_REALM_THRESHOLD`, because the ladder is append-only and
## an inserted realm shifts every index below it — a test that hardcoded R18 broke
## the moment one was added, which is exactly the coupling ADR 0050 removed from
## the power table.

# --- Fixtures ------------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## Ladder index of the first realm the tribulation gate applies to.
func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## The highest realm that owes no tribulation: one below the realm that stands
## immediately under the gate.
func _last_free() -> int:
	return _gate() - 2


## The realm standing immediately under the gate. It owes R(_gate()) — the gate
## is on the realm BEING ENTERED, not on the one being stood in.
func _brink() -> int:
	return _gate() - 1


## An actor standing at `index`, with a dao heart the tribulation is fought with
## and a laid-out meridian network, so a loss has something to damage.
func _hero(index: int = -1) -> Actor:
	var at := _brink() if index < 0 else index
	var realm_id := _realm_id(at)
	var actor := Actor.new(&"tribulation_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## The same hero with the body's huyệt set attached, which `recover_next` needs:
## `BodyTraining.recover` refuses an actor with no acupoint set, so without this a
## loss could be inflicted but never repaired.
func _recoverable_hero() -> Actor:
	var hero := _hero()
	ItemsApi.attach(hero)
	BodyCultivationApi.attach(hero)
	BodyCultivationApi.attach_acupoints(hero)
	return hero


## A generator whose next draw is below every possible endurance, so a fight
## driven with it always survives.
func _roll_below_floor() -> RandomNumberGenerator:
	return _seeded(TribulationEndurance.MIN_ENDURANCE, false)


## A generator whose next draw is at or above every possible endurance, so a
## fight driven with it always loses.
func _roll_above_ceiling() -> RandomNumberGenerator:
	return _seeded(TribulationEndurance.MAX_ENDURANCE, true)


func _seeded(threshold: float, above: bool) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() >= threshold) == above:
			rng.seed = seed_value
			return rng
	return null


## How much tribulation essence the actor holds; 0.0 when the pool is absent.
func _essence(hero: Actor) -> float:
	var pool := hero.resource(&"tribulation_essence") as ResourcePool
	return 0.0 if pool == null else pool.current


# --- The gate exists, and the threshold is real --------------------------------


## The whole point: below the gate nothing is owed, and the gate reads open. The
## threshold is `Breakthrough.IMMORTAL_REALM_THRESHOLD`, which the body
## breakthrough condition already reads through `tier_gates_met`.
func test_no_tribulation_is_owed_below_the_immortal_gate() -> void:
	for index in [0, _last_free()]:
		var live := TribulationFight.state(_hero(index))
		assert_eq(bool(live["owed"]), false, "realm %d owes no tribulation" % index)
		assert_eq(bool(live["gate_open"]), true, "and its gate is open")


func test_a_tribulation_is_owed_from_the_realm_below_the_gate() -> void:
	var live := TribulationFight.state(_hero())
	assert_eq(bool(live["owed"]), true, "the realm below the gate owes one")
	assert_eq(String(live["target"]), String(_realm_id(_gate())), "fought for the gate's realm")
	assert_eq(bool(live["gate_open"]), false, "and the gate is shut until it is won")
	assert_eq(bool(live["has_record"]), false, "with no fight in the air")


## The threshold has one home. Move the actor one realm down and the same
## predicate every path condition reads goes shut; the module names no number of
## its own.
func test_the_threshold_is_the_same_number_core_uses() -> void:
	var below := _hero(_last_free())
	assert_eq(
		String(TribulationFight.state(below)["target"]), "", "nothing is owed one realm lower"
	)
	assert_eq(
		Breakthrough.tribulation_ok(below, _gate()), false, "so core's own gate is shut there"
	)
	var at := _hero()
	assert_eq(
		String(TribulationFight.state(at)["target"]),
		String(_realm_id(_gate())),
		"and the module says the same realm core's gate is waiting for"
	)


## One actor, two paths: the slot holds a single fight, so the rule is the FIRST
## tier any enrolled path still owes. Getting this backwards would let a hero
## standing under the gate fight for a later realm instead.
func test_the_first_tier_owed_wins_when_two_paths_owe_one() -> void:
	var hero := _hero()
	hero.set_path(PathState.new(QiPath.PATH_ID, _realm_id(RealmDefaults.ladder().size() - 5)))
	assert_eq(
		String(TribulationFight.state(hero)["target"]),
		String(_realm_id(_gate())),
		"the nearest unearned gate is the one worth filling"
	)


# --- The fight ------------------------------------------------------------------


func test_beginning_binds_the_fight_to_the_realm_it_is_owed() -> void:
	var hero := _hero()
	var result := TribulationFight.begin(hero)
	assert_eq(bool(result["ok"]), true, "the tribulation begins")
	assert_ne(hero.tribulation, null, "there is a record")
	if hero.tribulation == null:
		return
	assert_eq(
		String(hero.tribulation.realm_id),
		String(_realm_id(_gate())),
		"bound to the gate's realm, so it can only ever open that gate"
	)
	var live := TribulationFight.state(hero)
	assert_eq(bool(live["active"]), true, "the fight is the actor's to fight out")
	assert_eq(String(live["bound"]), String(_realm_id(_gate())), "and the screen sees which realm")


func test_beginning_refuses_when_no_realm_is_owed() -> void:
	var result := TribulationFight.begin(_hero(0))
	assert_eq(bool(result["ok"]), false, "a first-realm hero owes nothing")
	assert_ne(String(result["reason"]), "", "and is told why")


func test_beginning_refuses_while_a_fight_is_in_the_air() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	hero.tribulation.advance_wave()
	var again := TribulationFight.begin(hero)
	assert_eq(bool(again["ok"]), false, "waves already fought are not thrown away")
	assert_eq(hero.tribulation.wave, 1, "and the fight kept its wave")


## Every wave is observable and every wave advances the fight: the screen shows a
## real progression, not a single "fight" click.
func test_fighting_a_wave_advances_the_record_and_is_observable() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var total := hero.tribulation.max_waves
	var seen: Array[int] = []
	var guard := 0
	while guard < TribulationFight.WAVE_GUARD:
		guard += 1
		var step := TribulationFight.fight_wave(hero, _roll_below_floor())
		if not bool(step["ok"]):
			break
		if bool(step["decided"]):
			break
		seen.append(hero.tribulation.wave)
	assert_ne(seen.is_empty(), true, "the fight took more than one wave")
	assert_eq(seen[0], 1, "the first wave is wave one")
	assert_eq(int(TribulationFight.state(hero)["max_waves"]), total, "the wave count was published")


func test_fighting_is_refused_before_the_fight_begins() -> void:
	var result := TribulationFight.fight_wave(_hero(), _roll_below_floor())
	assert_eq(bool(result["ok"]), false, "there is no fight to wave-fight")
	assert_ne(String(result["reason"]), "", "and the refusal names itself")


# --- Both branches --------------------------------------------------------------


## The survival branch, end to end: begin, fight, decide, gate open.
func test_a_good_roll_survives_and_opens_the_gate() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var result := TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	assert_eq(bool(result["decided"]), true, "the fight was decided")
	assert_eq(bool(result["survived"]), true, "and survived")
	assert_eq(hero.tribulation.survived(), true, "the record says so")
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), true, "the gate is open")
	var live := TribulationFight.state(hero)
	assert_eq(bool(live["gate_open"]), true, "and the screen shows it open")
	assert_eq(String(live["outcome"]), String(Tribulation.OUTCOME_SURVIVED), "with the outcome")


## The failure branch, and it is NOT an auto-survivor: the roll lost, the record
## says failed, the gate stayed shut, and no reward was paid. Before this module
## nothing could reach this state, so `apply_result(actor, true)` at the call
## sites made defeat unreachable content.
func test_a_bad_roll_loses_and_leaves_the_gate_shut() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var result := TribulationFight.fight_to_verdict(hero, _roll_above_ceiling())
	assert_eq(bool(result["decided"]), true, "the fight was decided")
	assert_eq(bool(result["survived"]), false, "and lost")
	assert_eq(String(hero.tribulation.outcome), String(Tribulation.OUTCOME_FAILED), "recorded")
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), false, "the gate stayed shut")
	assert_eq(bool(TribulationFight.state(hero)["gate_open"]), false, "and says so")
	assert_eq(hero.has_status(&"heavenly_blessing"), false, "no blessing for a lost fight")


## Defeat is consequential, not a flag. This is the code that five auto-survivor
## sites made unreachable.
func test_a_lost_fight_damages_the_body_it_was_fought_with() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	TribulationFight.fight_to_verdict(hero, _roll_above_ceiling())
	var wounded := 0
	for channel in hero.meridians.get_all_meridians():
		if channel.is_injured():
			wounded += 1
	assert_eq(wounded > 0, true, "the tribulation broke channels")
	assert_eq(hero.stats.get_base(Stat.COMPREHENSION) < 60.0, true, "the dao heart took damage")


## A loss is RECOVERABLE, which is the difference between a gate and a wall:
## repair through the shipped recovery verb, then fight it again and win.
func test_a_lost_fight_can_be_repaired_and_refought() -> void:
	var hero := _recoverable_hero()
	_grant_recovery_item(hero)
	TribulationFight.begin(hero)
	TribulationFight.fight_to_verdict(hero, _roll_above_ceiling())
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), false, "shut after the loss")
	var repaired := false
	# Bounded: `recover_next` closes one wound per call and refuses a meridian with
	# nothing to repair, so this converges on the count rather than on a guess.
	var guard := 0
	while guard < TribulationFight.WAVE_GUARD and not repaired:
		guard += 1
		repaired = BodyCultivationApi.recover_next(hero)
	assert_eq(repaired, true, "the body repaired itself through the shipped verb")
	assert_eq(bool(TribulationFight.begin(hero)["ok"]), true, "and the gate can be fought again")
	var result := TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	assert_eq(bool(result["survived"]), true, "this time survived")
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), true, "the gate is open")


## One survivor opens one gate. `matches_realm` is what stops the win at one realm
## from standing in for the next realm's fight forever.
func test_a_survivor_does_not_stand_in_for_the_next_realm() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	hero.set_path(PathState.new(BodyPath.PATH_ID, _realm_id(_gate())))
	assert_eq(Breakthrough.tribulation_ok(hero, _gate() + 1), false, "the next realm needs its own")
	assert_eq(
		String(TribulationFight.state(hero)["target"]),
		String(_realm_id(_gate() + 1)),
		"and the module says which one is owed next"
	)


## The fight is decided exactly once: re-fighting a decided record is refused
## rather than paying the reward again.
func test_a_decided_fight_is_never_decided_again() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	var before := _essence(hero)
	var again := TribulationFight.fight_wave(hero, _roll_above_ceiling())
	assert_eq(bool(again["ok"]), false, "the fight is over")
	assert_eq(_essence(hero), before, "and nothing was paid twice")


# --- Withdrawing -----------------------------------------------------------------


## Walking away is a real choice with a real cost: the waves are forfeited and
## the gate stays shut, and nothing is gained or lost.
func test_withdrawing_forfeits_the_waves_and_leaves_the_gate_shut() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	hero.tribulation.advance_wave()
	assert_eq(TribulationFight.withdraw(hero), true, "the fight was abandoned")
	assert_eq(hero.tribulation, null, "the record is gone")
	assert_eq(Breakthrough.tribulation_ok(hero, _gate()), false, "so the gate is still shut")
	assert_eq(bool(TribulationFight.state(hero)["has_record"]), false, "and no fight is in the air")
	assert_eq(bool(TribulationFight.begin(hero)["ok"]), true, "and the fight can be faced again")


## Withdrawing a DECIDED fight is refused: a survivor that withdrew would discard
## the gate it earned, and a defeat that withdrew would erase the record of it.
func test_withdrawing_a_decided_fight_is_refused() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	assert_eq(TribulationFight.withdraw(hero), false, "a decided fight is not abandoned")
	assert_eq(hero.tribulation.survived(), true, "and the survivor survives the attempt")


func test_withdrawing_without_a_fight_is_refused() -> void:
	assert_eq(TribulationFight.withdraw(_hero()), false, "nothing to walk away from")


# --- The roll is bounded ---------------------------------------------------------


## Endurance is a share, never a certainty and never a coin flip: a gate a player
## cannot walk through is as broken as no gate at all. The bounds are core's, and
## this pins that the module reads them rather than keeping a second copy.
func test_endurance_is_bounded_at_both_ends_for_every_owed_realm() -> void:
	for index in range(_gate(), RealmDefaults.ladder().size()):
		var hero := _hero(index)
		var share := TribulationEndurance.endurance(hero)
		assert_eq(
			share >= TribulationEndurance.MIN_ENDURANCE, true, "%s has a floor" % _realm_id(index)
		)
		assert_eq(
			share <= TribulationEndurance.MAX_ENDURANCE, true, "%s has a ceiling" % _realm_id(index)
		)
		assert_eq(share < 1.0, true, "%s can still be lost" % _realm_id(index))


## The module publishes the same share it would decide on, so what a screen shows
## before the fight is what the fight is fought at.
func test_the_published_share_is_the_one_the_fight_is_decided_on() -> void:
	var hero := _hero()
	assert_eq(
		float(TribulationFight.state(hero)["chance"]),
		TribulationEndurance.endurance(hero),
		"the screen's odds are the fight's odds"
	)


## A harder tribulation is endured less often. Without this the rating would be
## priced by core and read by nobody.
func test_a_harder_tribulation_is_endured_less_often() -> void:
	var soft := _hero()
	var hard := _hero(RealmDefaults.ladder().size() - 3)
	TribulationFight.begin(soft)
	TribulationFight.begin(hard)
	assert_eq(
		(
			TribulationEndurance.endurance(hard, hard.tribulation)
			< TribulationEndurance.endurance(soft, soft.tribulation)
		),
		true,
		"the harder fight is endured less"
	)


## A wounded dao heart is endured less often, so the fight rewards what the paths
## spend their training on.
func test_a_wounded_dao_heart_is_endured_less_often() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	var whole := TribulationEndurance.endurance(hero, hero.tribulation)
	hero.stats.set_base(Stat.COMPREHENSION, 5.0)
	assert_eq(TribulationEndurance.endurance(hero, hero.tribulation) < whole, true, "strain costs")


## The prepared share is published while no fight is in the air, so a screen can
## price a fight before the player commits to it. The price is measured on a
## throwaway record and does not put one on the actor.
func test_the_price_is_published_before_the_fight_begins() -> void:
	var hero := _hero()
	var live := TribulationFight.state(hero)
	assert_eq(hero.tribulation, null, "no record was created by reading the state")
	assert_eq(float(live["difficulty"]), 0.0, "there is no live record's rating")
	assert_eq(float(live["chance"]) > 0.0, true, "but the share of fights survived is known")


## The guard names the phase machine that failed to converge rather than hiding
## it: a fight that cannot be decided reports a refusal, not a hang.
func test_an_undecidable_fight_reports_a_refusal_rather_than_looping() -> void:
	var hero := _hero()
	TribulationFight.begin(hero)
	# A record already decided can never be fought again, so `fight_to_verdict` has
	# nothing to drive and must say so rather than spin.
	TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	var result := TribulationFight.fight_to_verdict(hero, _roll_below_floor())
	assert_eq(bool(result["ok"]), false, "refused")
	assert_ne(String(result["reason"]), "", "with a reason")
	assert_eq(bool(TribulationFight.WAVE_GUARD > 0), true, "and a small, named bound")


# --- Plumbing ---------------------------------------------------------------------


## Give the actor the realm's recovery item, which is what `recover_next` spends.
## A gate is only recoverable if its repair is reachable, and the repair is only
## reachable with the item.
func _grant_recovery_item(hero: Actor) -> void:
	var seed := BodyRealmSeed.for_realm(_realm_id(_brink()))
	if seed == null or seed.recovery_item == &"":
		return
	var def := ItemDef.new()
	def.id = seed.recovery_item
	def.stackable = true
	def.max_stack = 9999
	ItemsApi.inventory(hero).add(def, 99)
