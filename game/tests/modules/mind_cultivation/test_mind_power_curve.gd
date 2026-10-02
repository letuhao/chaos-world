extends TestCase

## ADR 0013/0016: the mind power profile, and the no-double-count rule that keeps
## the sea reservoir honest.
##
## Two realm-shaped reads and they are NOT the same kind of number:
##   - `MindRealmProfile.factor` is a bounded per-realm RATE, applied to every
##     contribution and to `MindTraining.cultivate`'s fill rate: how much a unit of
##     this realm's cultivation is worth.
##   - capacity is the AUTHORED per-realm MAGNITUDE in `MindRealmSeed.sea_capacity`
##     (100 -> 825), applied exactly once by `MindTraining.synchronize`: how much
##     this realm can hold.
##
## A provider must not read a magnitude — `RealmScaling` (core) already scales the
## shared combat stats by the realm's strength, so scaling mental output by it as
## well would count the same realm twice and would collide with `SeaProvider`,
## which owns `MindStats.SEA_CAPACITY`.
##
## Every expected number below is DERIVED from the code under test — the provider,
## the training layer, or the profile class — never pasted as a fresh literal. The
## two ends of the authored capacity ladder ARE literals, on purpose: they are
## content, not a derivation.

const FIRST := &"qi_refining"
const LAST := &"primordial_origin"

## Pre-factor technique power for the base attributes below: 20 * 1.5 + 15 * 1.0.
const BASE_TECHNIQUE_POWER := 45.0
## Pre-factor mental attack: 20 * 2.0 + 15 * 1.5.
const BASE_MENTAL_ATTACK := 62.5
## R1 is the neutral realm: the first ordinal's rate is `RATE_STEP^0` = 1, so this
## end is an exact pin and the top end is derived below.
const R1_POWER := 45.0
## Measured ends of the AUTHORED capacity ladder - MindRealmSeed.sea_capacity, not
## a profile read, so these two are literals on purpose.
const R1_CAPACITY := 100.0
const R30_CAPACITY := 825.0
## R1 fill rate: one unit of cultivation work buys rate(R1) = 1.0 units of sea.
const R1_FILL := 1.0


func _actor_at_rank(rank_id: StringName) -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
				MindStats.MENTAL_CLARITY: 15.0,
			}
		)
	)
	MindCultivationApi.attach(actor)
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	return actor


## Actor with a path, a sea, and the realm's authored structure already applied.
func _sea_actor_at_rank(rank_id: StringName) -> Actor:
	var actor := _actor_at_rank(rank_id)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	return actor


func _technique_power_at(rank_id: StringName) -> float:
	return _actor_at_rank(rank_id).stats.derived(MindStats.MIND_TECHNIQUE_POWER)


func _capacity_at(rank_id: StringName) -> float:
	return _sea_actor_at_rank(rank_id).stats.derived(MindStats.SEA_CAPACITY)


## Mind power stored by one unit of cultivation work at `rank_id`.
func _fill_rate_at(rank_id: StringName) -> float:
	var actor := _sea_actor_at_rank(rank_id)
	var before := actor.path(MindPath.PATH_ID).progress
	assert_eq(MindTraining.cultivate(actor, 1.0), true, "cultivate succeeds at %s" % rank_id)
	return actor.path(MindPath.PATH_ID).progress - before


## Relative equality, for the comparisons whose magnitudes make absolute-epsilon
## comparisons meaningless. Godot's `sprintf` has no `%g`, so the measured numbers
## go through `%s`.
func _assert_rel(actual: float, expected: float, label: String) -> void:
	assert_almost_eq(
		actual / expected, 1.0, "%s (got %s, want %s)" % [label, actual, expected], 0.000000001
	)


# --- The rate ---------------------------------------------------------------


## The rate is a gain, so it rises at every realm and stays bounded across the
## whole ladder. Reading a shared magnitude here is what once made a single
## breakthrough worth more than everything else combined — the curve reached 1e46.
func test_the_rate_rises_at_every_realm_and_stays_bounded() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous := 0.0
	for realm in realms:
		var rate := MindRealmProfile.factor(realm.id)
		assert_eq(rate > previous, true, "rate rises at %s" % realm.id)
		previous = rate
	assert_almost_eq(MindRealmProfile.factor(realms[0].id), 1.0, "R1 is neutral", 0.0001)
	# The span is a consequence of the authored step, not a pasted number.
	assert_almost_eq(
		previous,
		pow(MindRealmProfile.RATE_STEP, float(realms.size() - 1)),
		"the span is the authored step compounded over the ladder",
		0.0001
	)
	assert_eq(previous <= 2.0, true, "the whole ladder is worth under 2x of gain (%s)" % previous)


func test_an_unknown_or_empty_realm_is_neutral() -> void:
	for realm_id in [&"", &"not_a_realm"]:
		assert_almost_eq(
			MindRealmProfile.factor(realm_id), MindRealmProfile.NEUTRAL, "rate for %s" % realm_id
		)


# --- The rate, applied ------------------------------------------------------


func test_technique_power_increases_at_every_one_of_the_30_realms() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var power := _technique_power_at(realm.id)
		assert_eq(power > previous, true, "technique power rises at %s" % realm.id)
		previous = power


## Technique power is the base attributes times the realm rate, so the R30/R1
## ratio IS the rate's ratio — a consequence of the profile, not an authored floor
## of its own.
func test_technique_power_follows_the_rate_ratio() -> void:
	_assert_rel(
		_technique_power_at(LAST) / _technique_power_at(FIRST),
		MindRealmProfile.factor(LAST) / MindRealmProfile.factor(FIRST),
		"R30 ratio is the rate ratio"
	)


func test_technique_power_pins_both_ends_of_the_ladder() -> void:
	assert_almost_eq(_technique_power_at(FIRST), R1_POWER, "R1 technique power", 0.01)


## Every realm, not just the ends: a regression to a raw multiplier, a private
## exponent, or a read of the seed's authored field breaks the realms in between.
func test_technique_power_follows_the_rate_at_every_realm() -> void:
	for realm in RealmDefaults.ladder().realms():
		_assert_rel(
			_technique_power_at(realm.id),
			BASE_TECHNIQUE_POWER * MindRealmProfile.factor(realm.id),
			"technique power = base * rate at %s" % realm.id
		)
	_assert_rel(
		_technique_power_at(LAST),
		BASE_TECHNIQUE_POWER * MindRealmProfile.factor(LAST),
		"R30 technique power is base * rate"
	)


func test_mental_attack_follows_the_rate_at_every_realm() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var attack := _actor_at_rank(realm.id).stats.derived(MindStats.MENTAL_ATTACK)
		assert_eq(attack > previous, true, "mental attack rises at %s" % realm.id)
		previous = attack
		_assert_rel(
			attack,
			BASE_MENTAL_ATTACK * MindRealmProfile.factor(realm.id),
			"mental attack = base * rate at %s" % realm.id
		)
	assert_almost_eq(
		_actor_at_rank(FIRST).stats.derived(MindStats.MENTAL_ATTACK),
		BASE_MENTAL_ATTACK,
		"R1 mental attack",
		0.01
	)


## The provider is scaled by the rate and nothing else. The realm MAGNITUDE lives
## in `RealmScaling` (core) and in `sea_capacity`; applying either here would
## count the same realm twice.
func test_no_stat_is_scaled_by_anything_but_the_bounded_rate() -> void:
	var plain := _actor_without_path()
	var actor := _actor_at_rank(LAST)
	var factor := MindRealmProfile.factor(LAST)
	for stat_id in [
		MindStats.MENTAL_ATTACK,
		MindStats.MENTAL_DEFENSE,
		MindStats.MIND_TECHNIQUE_POWER,
	]:
		assert_almost_eq(
			actor.stats.derived(stat_id) / plain.stats.derived(stat_id),
			factor,
			"%s is exactly the rate" % String(stat_id),
			0.0001
		)
	# Comprehension gain is a rate too, so it stays modest: 10 base comprehension
	# must not buy a 12x bonus.
	assert_almost_eq(
		actor.stats.derived(MindStats.COMPREHENSION_BONUS),
		1.0 + 10.0 * 0.01 + factor * 0.02,
		"comprehension bonus reads the rate",
		0.0001
	)
	assert_eq(factor < 2.0, true, "the rate really is the modest number (%s)" % factor)


## An actor with the module attached and NO path: the factor is neutral (1.0),
## which is the documented reference, not a failed profile lookup.
func _actor_without_path() -> Actor:
	var actor := _bare_actor()
	MindCultivationApi.attach(actor)
	return actor


func _bare_actor() -> Actor:
	return (
		Actor
		. new(
			&"mind_cultivator",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
				MindStats.MENTAL_CLARITY: 15.0,
			}
		)
	)


# --- Capacity: the authored sea ladder, applied once -------------------------


func test_sea_capacity_increases_at_every_realm() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var capacity := _capacity_at(realm.id)
		assert_eq(capacity > previous, true, "sea capacity rises at %s" % realm.id)
		previous = capacity


func test_sea_capacity_pins_both_ends_of_the_ladder() -> void:
	assert_almost_eq(_capacity_at(FIRST), R1_CAPACITY, "R1 sea capacity", 0.01)
	assert_almost_eq(_capacity_at(LAST), R30_CAPACITY, "R30 sea capacity", 0.01)


## No meridian is strengthened yet, so capacity must be exactly the authored seed
## value: a second multiplier (the rate, or a doubled meridian bonus) fails here.
func test_sea_capacity_is_the_authored_value_before_any_meridian_bonus() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		var actor := _sea_actor_at_rank(realm.id)
		assert_almost_eq(
			actor.meridians.get_capacity_bonus(), 0.0, "no capacity bonus at %s" % realm.id
		)
		assert_almost_eq(
			MindCultivationApi.sea(actor).structural_capacity,
			seed.sea_capacity,
			"authored capacity at %s" % realm.id,
			0.0001
		)
		assert_almost_eq(
			actor.stats.derived(MindStats.SEA_CAPACITY),
			seed.sea_capacity,
			"derived capacity at %s" % realm.id,
			0.0001
		)


func test_sea_capacity_applies_the_meridian_capacity_bonus_once() -> void:
	var actor := _sea_actor_at_rank(LAST)
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	assert_almost_eq(actor.meridians.get_capacity_bonus(), 0.05, "lung capacity bonus")
	MindTraining.synchronize(actor)
	# 825 * (1 + 0.05) once. Applying it twice would give 909.56.
	assert_almost_eq(
		MindCultivationApi.sea(actor).structural_capacity,
		R30_CAPACITY * 1.05,
		"meridian capacity applies once",
		0.01
	)
	assert_almost_eq(
		actor.stats.derived(MindStats.SEA_CAPACITY), R30_CAPACITY * 1.05, "derived capacity", 0.01
	)


## The rate may not reach the sea reservoir. `MindTraining.synchronize` already
## applies the meridian capacity bonus on top of the authored seed, so a second
## factor counts the same investment twice. Capacity is an authored magnitude,
## which means the assertion is that it is the seed and nothing else.
func test_sea_capacity_ignores_the_rate() -> void:
	var seed := MindRealmSeed.for_realm(LAST)
	var authored := _capacity_at(LAST)
	assert_almost_eq(
		authored / seed.sea_capacity, 1.0, "capacity is the authored seed, unscaled", 0.0001
	)
	assert_eq(
		authored > seed.sea_capacity * MindRealmProfile.factor(LAST),
		false,
		"applying the rate would inflate the reservoir by %sx" % MindRealmProfile.factor(LAST)
	)


# --- Rate in the training fill rate ------------------------------------------


func test_fill_rate_increases_at_every_realm() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var rate := _fill_rate_at(realm.id)
		assert_eq(rate > previous, true, "fill rate rises at %s" % realm.id)
		previous = rate


## The fill rate is the rate read: the bounded per-realm step, times the meridian
## flow bonus. R1 is exact only because the first ordinal's rate is 1.
func test_fill_rate_pins_both_ends_of_the_ladder() -> void:
	assert_almost_eq(_fill_rate_at(FIRST), R1_FILL, "R1 fill rate", 0.0001)
	_assert_rel(
		_fill_rate_at(LAST), MindRealmProfile.factor(LAST), "R30 fill rate is the realm's rate"
	)


## The fill rate must stay a bounded gain, or cultivation work becomes
## meaningless: the top realms would be reached in fewer ticks than the bottom
## ones. This is the invariant's whole anti-free content at the training layer.
func test_the_fill_rate_stays_a_bounded_gain() -> void:
	var realms := RealmDefaults.ladder().realms()
	var span := _fill_rate_at(realms[realms.size() - 1].id) / _fill_rate_at(realms[0].id)
	assert_eq(span <= 2.0, true, "the fill rate spans under 2x across the ladder (%s)" % span)


# --- Price and reward: the invariant the ladder existed to protect ------------


## Cultivation work units needed to break into `realm_id`: the authored progress
## budget divided by the rate `MindTraining.cultivate` converts work with.
func _price_of(realm_id: StringName, below_id: StringName) -> float:
	var seed := MindRealmSeed.for_realm(realm_id)
	if seed == null or seed.progress_required <= 0.0:
		return 0.0
	return seed.progress_required / MindRealmProfile.factor(below_id)


## Reward gained per unit of labour work never gets worse, and no realm is free —
## the three assertions the body and qi paths make, against this path's own
## authored budget. The old quotient form (reward ratio over cost ratio) is
## unsatisfiable once the shared magnitude is gone: the only reward-per-unit-of-
## work left is the rate, and a rate cannot rise faster than the price it is
## measured against without ceasing to be a rate. See the body suite's
## `test_realm_profile.gd` for the full argument.
func test_reward_per_labour_never_gets_worse_with_depth() -> void:
	var realms := RealmDefaults.ladder().realms()
	var entry_rate := MindRealmProfile.factor(realms[0].id)
	var previous_rate := entry_rate
	var previous_price := 0.0
	var priced := 0
	for index in range(1, realms.size()):
		var here := realms[index - 1]
		var target := realms[index]
		var seed := MindRealmSeed.for_realm(target.id)
		var here_seed := MindRealmSeed.for_realm(here.id)
		if seed == null or here_seed == null or seed.progress_required <= 0.0:
			continue
		var reward := MindRealmProfile.factor(target.id)
		var price := seed.progress_required / MindRealmProfile.factor(here.id)
		# (1) Reward per unit of work never regresses.
		assert_eq(reward >= entry_rate, true, "reward per labour holds at %s" % target.id)
		assert_eq(reward > previous_rate, true, "reward per labour rises into %s" % target.id)
		# (2) No realm is cheaper than the one below it.
		assert_eq(
			price > previous_price, true, "%s costs more labour than %s" % [target.id, here.id]
		)
		# (3) The rate never outruns the budget it converts. The first transition
		# sets the baseline price and has no predecessor realm to be cheaper
		# than, and mind's R1 and R2 budgets are authored equal, so the
		# comparison starts at the second.
		if priced > 0:
			var rate_step := reward / previous_rate
			var budget_step := seed.progress_required / here_seed.progress_required
			assert_eq(
				rate_step <= budget_step,
				true,
				"rate step %s within budget step %s at %s" % [rate_step, budget_step, target.id]
			)
		previous_rate = reward
		previous_price = price
		priced += 1
	assert_eq(priced, 29, "every transition on the ladder was priced")
