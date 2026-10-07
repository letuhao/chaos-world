extends TestCase

## The qi path's price/rate pair, and the invariant the deleted power ladder
## existed to protect.
##
## `RealmRate.factor` is a bounded per-realm RATE (what one unit of circulation
## work is worth); `QiRealmSeed.progress_required` is the PRICE. The qi path's
## MAGNITUDES belong elsewhere — `dantian_capacity` for the reservoir, applied once
## by `QiTraining.synchronize`, and `RealmScaling` (core) for the shared combat
## stats — so nothing here may re-derive one. The contract is that reward per unit
## of work never regresses, and that a breakthrough is never cheaper than the one
## below it.
##
## The RATE is one shared curve in `core` (ADR 0066), asserted on its own terms in
## `tests/core/test_realm_rate.gd`. This suite keeps the qi path's PRICE-side
## pairing of that rate against this path's own authored budget, and it is
## duplicated across the three paths rather than shared because each suite reads
## its own path's seed — a regression in one path's content must not hide behind
## another's.


## Cultivation work units needed to break into `realm_id`, measured from the realm
## below it: the authored progress budget divided by the rate `QiTraining.
## cultivate` converts one unit of work with.
func _price_of(realm_id: StringName, below_id: StringName) -> float:
	var seed := QiRealmSeed.for_realm(realm_id)
	if seed == null or seed.progress_required <= 0.0:
		return 0.0
	return seed.progress_required / RealmRate.factor(below_id)


func test_the_rate_rises_at_every_realm_and_stays_bounded() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous := 0.0
	for realm in realms:
		var rate := RealmRate.factor(realm.id)
		assert_eq(rate > previous, true, "rate rises at %s" % realm.id)
		previous = rate
	assert_almost_eq(RealmRate.factor(realms[0].id), 1.0, "R1 is neutral", 0.0001)
	# The span is a consequence of the authored step, not a pasted number.
	assert_almost_eq(
		previous,
		pow(RealmRate.RATE_STEP, float(realms.size() - 1)),
		"the span is the authored step compounded over the ladder",
		0.0001
	)
	assert_eq(previous <= 2.0, true, "the whole ladder is worth under 2x of gain (%s)" % previous)


func test_an_unknown_or_empty_realm_is_neutral() -> void:
	for realm_id in [&"", &"not_a_realm"]:
		assert_almost_eq(RealmRate.factor(realm_id), RealmRate.NEUTRAL, "rate for %s" % realm_id)


## The dantian reservoir is the qi path's MAGNITUDE, authored per realm, and is
## applied exactly once by `QiTraining.synchronize`. The realm rate may not reach
## it — a second factor counts the same investment twice.
func test_dantian_capacity_is_the_authored_value_and_nothing_else() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var actor := (
			Actor
			. new(
				&"cultivator",
				{
					Stat.SPIRIT: 10.0,
					Stat.APTITUDE: 10.0,
					QiStats.QI_AFFINITY: 20.0,
					QiStats.QI_CONTROL: 15.0,
					QiStats.DANTIAN_CAPACITY: 30.0,
				}
			)
		)
		QiCultivationApi.attach(actor)
		actor.set_path(PathState.new(QiPath.PATH_ID, realm.id))
		QiTraining.synchronize(actor)
		var dantian := QiTestKit.dantian(actor)
		assert_ne(dantian, null, "dantian at %s" % realm.id)
		if dantian == null:
			continue
		assert_almost_eq(
			dantian.structural_capacity,
			seed.dantian_capacity,
			"authored capacity at %s" % realm.id,
			0.0001
		)


## Reward gained per unit of labour work never gets worse, and no realm is free —
## the three assertions the body path makes, against this path's own authored
## budget. The old quotient form (reward ratio over cost ratio) is unsatisfiable
## once the shared magnitude is gone: the only reward-per-unit-of-work left is the
## rate, and a rate cannot rise faster than the price it is measured against
## without ceasing to be a rate. See `tests/core/test_realm_rate.gd` for the rate
## itself, and `test_realm_profile.gd` in the body suite for the full argument.
func test_reward_per_labour_never_gets_worse_with_depth() -> void:
	var realms := RealmDefaults.ladder().realms()
	var entry_rate := RealmRate.factor(realms[0].id)
	var previous_rate := entry_rate
	var previous_price := 0.0
	var priced := 0
	for index in range(1, realms.size()):
		var here := realms[index - 1]
		var target := realms[index]
		var seed := QiRealmSeed.for_realm(target.id)
		var here_seed := QiRealmSeed.for_realm(here.id)
		if seed == null or here_seed == null or seed.progress_required <= 0.0:
			continue
		var reward := RealmRate.factor(target.id)
		var price := seed.progress_required / RealmRate.factor(here.id)
		# (1) Reward per unit of work never regresses.
		assert_eq(reward >= entry_rate, true, "reward per labour holds at %s" % target.id)
		assert_eq(reward > previous_rate, true, "reward per labour rises into %s" % target.id)
		# (2) No realm is cheaper than the one below it.
		assert_eq(
			price > previous_price, true, "%s costs more labour than %s" % [target.id, here.id]
		)
		# (3) The rate never outruns the budget it converts. The first transition
		# sets the baseline price and has no predecessor realm to be cheaper
		# than, and qi's R1 and R2 budgets are authored equal, so the comparison
		# starts at the second.
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
