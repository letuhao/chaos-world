extends TestCase

## A tribulation is an encounter, not a caller-supplied flag (ADR 0058).
##
## Two rules are pinned here and neither is reachable from the phase machine alone:
## the outcome is decided by a roll against the tribulation's own rating, and it is
## decided exactly once. The first makes defeat real; the second makes winning a
## realm's fight pay for that fight only.

# --- Deterministic rolls ------------------------------------------------------
# `fight_wave` takes an `rng`, so a test chooses the roll instead of hoping for one.
# These find a seed whose first draw is unambiguously below or above every possible
# endurance, so the assertion survives any retuning of the rating.


## A generator whose next draw is below `Tribulation.MIN_ENDURANCE`.
func _roll_below_floor() -> RandomNumberGenerator:
	return _seeded(Tribulation.MIN_ENDURANCE, false)


## A generator whose next draw is at or above `Tribulation.MAX_ENDURANCE`.
func _roll_above_ceiling() -> RandomNumberGenerator:
	return _seeded(Tribulation.MAX_ENDURANCE, true)


func _seeded(threshold: float, above: bool) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		var draw := rng.randf()
		if (draw >= threshold) == above:
			rng.seed = seed_value
			return rng
	return null


# --- Fixtures -----------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _actor(comprehension: float = 40.0) -> Actor:
	return Actor.new(&"tribulation_hero", {Stat.COMPREHENSION: comprehension})


func _actor_at(index: int, path_id: StringName = QiPath.PATH_ID) -> Actor:
	var actor := _actor()
	actor.set_path(PathState.new(path_id, _realm_id(index)))
	return actor


## An actor standing one realm below the Immortal tier with its channels unlocked
## and untrained, so preparation measures something real and something zero.
func _actor_at_r18(path_id: StringName = QiPath.PATH_ID) -> Actor:
	var actor := _actor_at(17, path_id)
	actor.meridians.unlock_for_realm(_realm_id(17))
	return actor


## Fight through the production entry point until the record is decided, which is
## true for a loss as well as a win. A decided record is what the gate reads, so
## there is nothing left to drive.
func _fight_to_verdict(actor: Actor, rng: RandomNumberGenerator, path_id: StringName) -> void:
	var guard := 0
	while guard < 64:
		guard += 1
		Breakthrough.face_tribulation(actor, path_id, rng)
		if (
			actor.tribulation != null
			and actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED
		):
			return


## Drive the phase machine to its last phase and then wave-fight it, for the tests
## that need the record decided without a gate in the way.
func _fight_to_completion(actor: Actor, rng: RandomNumberGenerator) -> void:
	Breakthrough.begin_tribulation(actor, 18)
	var guard := 0
	while guard < 64:
		guard += 1
		actor.tribulation.fight_wave(actor, rng)
		if actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED:
			return


# --- The roll decides ---------------------------------------------------------


## A roll below every possible endurance is survived: the fight is won by the roll,
## not by whoever called it.
func test_a_good_roll_survives_the_tribulation() -> void:
	var actor := _actor_at_r18()
	_fight_to_verdict(actor, _roll_below_floor(), QiPath.PATH_ID)
	assert_ne(actor.tribulation, null, "a fight was fought")
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_SURVIVED, "survived")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), true, "the gate it opens is open")


## A roll at or above every possible endurance is not. Before this rule the fight
## had no roll at all, so `_apply_failure` — and every item serving it — was
## unreachable from production.
func test_a_bad_roll_loses_the_tribulation() -> void:
	var actor := _actor_at_r18()
	_fight_to_verdict(actor, _roll_above_ceiling(), QiPath.PATH_ID)
	assert_ne(actor.tribulation, null, "a fight was fought")
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_FAILED, "defeat recorded")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "the gate stays shut")
	assert_eq(actor.has_status(&"heavenly_blessing"), false, "no reward for a lost fight")


## Defeat is consequential, not a flag: the meridians take the lightning and the dao
## heart takes the damage. This is the code the unreachable outcome left dead.
func test_defeat_damages_the_body_it_was_fought_with() -> void:
	var actor := _actor_at_r18()
	_fight_to_verdict(actor, _roll_above_ceiling(), QiPath.PATH_ID)
	var wounded := 0
	for channel in actor.meridians.get_all_meridians():
		if channel.is_injured():
			wounded += 1
	assert_eq(wounded > 0, true, "the lightning broke channels")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION) < 40.0, true, "the dao heart took damage")


## A lost tribulation leaves a decided record, and a decided record is replaced on
## the next attempt rather than inherited. Re-fighting is how a lost gate opens.
func test_a_lost_fight_can_be_refought() -> void:
	var actor := _actor_at_r18()
	_fight_to_verdict(actor, _roll_above_ceiling(), QiPath.PATH_ID)
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "shut after the loss")
	_fight_to_verdict(actor, _roll_below_floor(), QiPath.PATH_ID)
	assert_eq(Breakthrough.tribulation_ok(actor, 18), true, "shut only until the fight is won")


## Endurance is a share of fights survived at, never a certainty and never a
## coin-flip: a gate a player cannot walk through is as broken as no gate at all.
## Read through `TribulationEndurance`, the one curve — the record's own
## actor-free `endurance` was a second answer and is deleted (ADR 0125).
func test_endurance_is_bounded_at_both_ends() -> void:
	var actor := _actor_at_r18()
	for realm in RealmDefaults.ladder().realms():
		var tribulation := Tribulation.new(Tribulation.ELEMENTAL)
		tribulation.start(actor, realm.id)
		var share := TribulationEndurance.endurance(actor, tribulation)
		assert_eq(share >= TribulationEndurance.MIN_ENDURANCE, true, "%s has a floor" % realm.id)
		assert_eq(share <= TribulationEndurance.MAX_ENDURANCE, true, "%s has a ceiling" % realm.id)
		assert_eq(share < 1.0, true, "%s can still be lost" % realm.id)


## Bounded at both ends is NOT pinned to a value, and two formulas can share a clamp
## and still disagree about every fight inside it. The record's deleted `endurance()`
## read `MAX - rating * PER` where the live curve reads
## `MIN + dao_heart * 0.01 - rating * PER`: for this exact fight it answered 0.1675
## while the roll that decided the fight used 0.3192. That is the whole reason there
## is one curve, so this pins the arithmetic, not just its limits.
func test_the_survival_curve_is_pinned_to_a_value_and_not_only_to_its_bounds() -> void:
	var actor := _actor_at_r18()
	actor.stats.set_base(Stat.COMPREHENSION, 70.0)
	var record := Tribulation.new(Tribulation.ELEMENTAL)
	record.start(actor, &"earth_immortal")
	assert_eq(
		record.difficulty,
		(
			float(Tribulation.WAVES_BY_TIER[RealmDefaults.IMMORTAL])
			* float(Tribulation.TYPE_PRESSURE[Tribulation.ELEMENTAL])
		),
		"the rating is the wave count times the kind's pressure"
	)
	var share := TribulationEndurance.endurance(actor, record)
	assert_eq(
		share,
		(
			TribulationEndurance.MIN_ENDURANCE
			+ 70.0 * TribulationEndurance.DAO_HEART_TO_ENDURANCE
			- record.difficulty * Tribulation.ENDURANCE_PER_RATING
		),
		"the share is the authored slope applied to this actor and this rating"
	)
	assert_eq(
		share > TribulationEndurance.MIN_ENDURANCE and share < TribulationEndurance.MAX_ENDURANCE,
		true,
		"and it is interior, so the two assertions above were not the clamp talking"
	)


## A harder tribulation is a smaller share of fights survived at. Without this the
## rating would be priced and never read.
##
## The actor is given the dao heart that keeps every answer INTERIOR, and that is the
## point: at the floor or the ceiling every pair compares EQUAL, so the version of
## this assertion that ran on a comprehension of 40 passed only because both fights
## clamped, and would have passed with the rating deleted entirely.
func test_a_harder_tribulation_is_endured_less_often() -> void:
	var actor := _actor_at_r18()
	actor.stats.set_base(Stat.COMPREHENSION, 70.0)
	var light_spirit := Tribulation.new(Tribulation.LIGHTNING)
	light_spirit.start(actor, &"spirit_condensation")
	var elemental_spirit := Tribulation.new(Tribulation.ELEMENTAL)
	elemental_spirit.start(actor, &"spirit_condensation")
	var light_immortal := Tribulation.new(Tribulation.LIGHTNING)
	light_immortal.start(actor, &"earth_immortal")
	for record in [light_spirit, elemental_spirit, light_immortal]:
		var share := TribulationEndurance.endurance(actor, record)
		assert_eq(
			(
				share > TribulationEndurance.MIN_ENDURANCE
				and share < TribulationEndurance.MAX_ENDURANCE
			),
			true,
			"%s is interior, so the order is the rating's and not the clamp's" % record.type
		)
	assert_eq(
		(
			TribulationEndurance.endurance(actor, elemental_spirit)
			< TribulationEndurance.endurance(actor, light_spirit)
		),
		true,
		"the harder kind of the same fight is endured less"
	)
	assert_eq(
		(
			TribulationEndurance.endurance(actor, light_immortal)
			< TribulationEndurance.endurance(actor, elemental_spirit)
		),
		true,
		"and so is the same kind fought over more waves"
	)


# --- The wave toll ------------------------------------------------------------


## Every wave a fight drags on costs dao-heart strain. The old phase machine
## advanced a counter and charged nothing.
func test_every_wave_costs_dao_heart_strain() -> void:
	var actor := _actor_at_r18()
	Breakthrough.begin_tribulation(actor, 18)
	var tribulation := actor.tribulation
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var rng := _roll_below_floor()
	for wave_index in range(1, 4):
		tribulation.fight_wave(actor, rng)
		assert_eq(
			actor.stats.get_base(Stat.COMPREHENSION),
			before - float(wave_index) * Tribulation.WAVE_TOLL,
			"wave %d charged its toll" % wave_index
		)


## The fight is what costs and the reward is what restores, so surviving pays for
## the waves it took.
func test_surviving_restores_what_the_waves_took() -> void:
	var actor := _actor_at_r18()
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	Breakthrough.begin_tribulation(actor, 18)
	var tribulation := actor.tribulation
	var toll := float(tribulation.max_waves + 2) * Tribulation.WAVE_TOLL
	_fight_to_completion(actor, _roll_below_floor())
	assert_eq(tribulation.survived(), true, "the fight was won")
	assert_eq(
		actor.stats.get_base(Stat.COMPREHENSION),
		before - toll + float(tribulation.get_rewards()["insight"]),
		"insight covers the toll and more"
	)


# --- Preparation is measured, not declared ------------------------------------


## `start` used to read `preparation` and then clear it, so the aid it priced was
## always the *previous* fight's. It is measured off the actor now.
func test_start_measures_preparation_from_the_actor() -> void:
	var actor := _actor_at_r18()
	var tribulation := Tribulation.new(Tribulation.LIGHTNING)
	tribulation.start(actor, &"earth_immortal")
	assert_eq(tribulation.preparation.size(), Tribulation.PREPARATION_AIDS.size(), "named aids")
	assert_eq(float(tribulation.preparation["formation"]), 0.0, "no training, no formation")
	assert_eq(
		tribulation.preparation.has("environment"), true, "the arena is named even when absent"
	)
	assert_eq(float(tribulation.preparation["environment"]), 0.0, "no world, no arena")


## Preparation is real: it lowers the rating a fight is fought at.
func test_preparation_lowers_the_rating() -> void:
	var actor := _actor_at_r18()
	var untrained := Tribulation.new(Tribulation.LIGHTNING)
	untrained.start(actor, &"earth_immortal")
	actor.inside_world = InsideWorld.new(InsideWorld.SEED)
	actor.inside_world.improve_stability(0.4)
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.open_meridian(channel.id)
		actor.meridians.expand_meridian(channel.id)
	var trained := Tribulation.new(Tribulation.LIGHTNING)
	trained.start(actor, &"earth_immortal")
	assert_eq(float(trained.preparation["formation"]), 1.0, "a developed array is measured")
	assert_eq(float(trained.preparation["environment"]), 0.9, "a stable world is an arena")
	assert_eq(
		trained.difficulty < untrained.difficulty, true, "a trained actor is fought more gently"
	)


## It cannot be farmed away: no preparation removes more than the authored floor.
func test_preparation_is_capped_at_the_authored_floor() -> void:
	var actor := _actor_at_r18()
	var tribulation := Tribulation.new(Tribulation.LIGHTNING)
	tribulation.start(actor, &"earth_immortal")
	var unaided := tribulation.rate(actor)
	for aid in Tribulation.PREPARATION_AIDS:
		tribulation.preparation[aid] = 99.0
	assert_eq(
		tribulation.rate(actor),
		unaided * (1.0 - Tribulation.PREPARATION_FLOOR),
		"an impossible aid buys exactly the floor"
	)


## The `environment` leg is the inside world's stability, and paying the anchor moves it
## by NOTHING. Both halves are invisible to the tests above, which is how a raise nothing
## could read shipped as a reward (BL-0830): `test_preparation_lowers_the_rating` opens
## every channel AND raises stability, so its `formation` of 1.0 alone already pins the
## reduction at `PREPARATION_FLOOR`, and an `_arena_quality` returning `0.0` would leave it
## green. Both aids are therefore held OFF the cap here — `formation` stays 0.0 and both
## worlds sit BELOW 0.5, the only window where an aid is worth its own value. 0.4 is the
## mutation witness: one raise short of the floor, so restoring `improve_stability(0.1)`
## pushes the sounded world to 0.5 and saturates the reduction.
func test_the_environment_leg_is_read_below_the_floor() -> void:
	var actor := _actor_at_r18()
	actor.inside_world = InsideWorld.new(InsideWorld.SEED, 1.0, 0.0)
	actor.inside_world.strengthen_anchor()
	var bare := Tribulation.new(Tribulation.LIGHTNING)
	bare.start(actor, &"earth_immortal")
	actor.inside_world.improve_stability(0.4)
	var sounded := Tribulation.new(Tribulation.LIGHTNING)
	sounded.start(actor, &"earth_immortal")
	assert_eq(float(bare.preparation["formation"]), 0.0, "no channel developed")
	assert_eq(float(bare.preparation["environment"]), 0.0, "paying the anchor moves no stability")
	assert_eq(float(sounded.preparation["environment"]), 0.4, "a sounded world IS the arena")
	assert_eq(sounded.difficulty < bare.difficulty, true, "and it is spent, not merely reported")


## The measured aid is part of the fight's price, so a resumed fight is the same
## fight: a save between waves must not soften it or harden it.
func test_preparation_and_its_rating_survive_a_save() -> void:
	var actor := _actor_at_r18()
	Breakthrough.begin_tribulation(actor, 18)
	actor.tribulation.fight_wave(actor, _roll_below_floor())
	var restored := Actor.from_dict(actor.to_dict())
	assert_ne(restored.tribulation, null, "the fight is on the save")
	assert_eq(
		restored.tribulation.difficulty, actor.tribulation.difficulty, "the rating is unchanged"
	)
	assert_eq(
		restored.tribulation.preparation, actor.tribulation.preparation, "the aid is unchanged"
	)


# --- The rating is keyed, not positional --------------------------------------


## `3 + ladder.index_of(id) / 4` moved every tribulation above an inserted realm,
## which is the positional coupling ADR 0050 removed from the power table.
func test_the_wave_count_comes_from_the_realm_id_not_its_position() -> void:
	var actor := _actor_at_r18()
	for realm in RealmDefaults.ladder().realms():
		var tribulation := Tribulation.new(Tribulation.LIGHTNING)
		tribulation.start(actor, realm.id)
		var tier := RealmDefaults.ladder().tier_of(realm.id)
		assert_eq(
			tribulation.max_waves,
			int(Tribulation.WAVES_BY_TIER[tier]),
			"realm %s is priced by its tier" % realm.id
		)


## A realm id the ladder has never heard of is still a fight, and is priced at the
## floor rather than at a position derived from a missing realm.
func test_an_unknown_realm_is_priced_at_the_floor() -> void:
	var tribulation := Tribulation.new(Tribulation.LIGHTNING)
	tribulation.start(_actor_at_r18(), &"not_a_realm")
	assert_eq(tribulation.max_waves, Tribulation.BASE_WAVES, "floor wave count")


## Every tier has an authored wave count, so no realm can fall through to the floor
## through a typo in a tier constant.
func test_every_tier_has_an_authored_wave_count() -> void:
	for tier in [
		RealmDefaults.MORTAL,
		RealmDefaults.SPIRIT,
		RealmDefaults.IMMORTAL,
		RealmDefaults.TRANSCENDENT,
	]:
		assert_eq(Tribulation.WAVES_BY_TIER.has(tier), true, "tier %d is authored" % tier)
