extends TestCase

## ADR 0028: the realm profile. Every realm carries a quality and integrity
## target, work requirements, an insight floor, and a resonance rank — and every
## entry gate must be reachable with one realm of training.
##
## Two realm-shaped numbers exist and they are NOT the same kind of thing:
## `RealmRate.factor` is the realm RATE (what one unit of training work is worth)
## and `BodyRealmSeed.work_required` is the PRICE. The body path's MAGNITUDES are
## authored per realm where they belong — `integrity_maximum` for the reservoir,
## and core's `RealmScaling` for the shared combat stats — so nothing here may
## re-derive one. The RATE itself is asserted in `tests/core/test_realm_rate.gd`;
## what this suite owns is the body's PRICE side of the pair.

# --- The rate ---------------------------------------------------------------


## The rate is a gain, so it rises at every realm — a path may never make
## progress convert more slowly as it gets stronger.
func test_the_realm_rate_rises_at_every_one_of_the_30_realms() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var rate := RealmRate.factor(realm.id)
		assert_eq(rate > previous, true, "rate rises at %s" % realm.id)
		previous = rate


## The distinction this suite exists to protect: a RATE is not a MAGNITUDE. It
## must stay bounded across the whole ladder. Reading a shared magnitude here is
## what made one breakthrough worth more than everything else combined — the old
## shared curve reached 1e46, so a single training tick at R30 was worth more
## than every other investment in the game.
func test_the_rate_is_a_bounded_gain_and_not_a_magnitude() -> void:
	var realms := RealmDefaults.ladder().realms()
	var first := RealmRate.factor(realms[0].id)
	var last := RealmRate.factor(realms[realms.size() - 1].id)
	assert_almost_eq(first, 1.0, "R1 is the neutral rate", 0.0001)
	# The span is a consequence of the authored step, not a pasted number.
	assert_almost_eq(
		last,
		pow(RealmRate.RATE_STEP, float(realms.size() - 1)),
		"the span is the authored step compounded over the ladder",
		0.0001
	)
	assert_eq(last <= 2.0, true, "the whole ladder is worth under 2x of gain (%s)" % last)


## An unstarted path, or one holding a rank that is not on the ladder, must
## degrade to neutral rather than scale a stat to zero or throw.
func test_an_unknown_or_empty_realm_is_neutral() -> void:
	for realm_id in [&"", &"not_a_realm"]:
		assert_almost_eq(RealmRate.factor(realm_id), RealmRate.NEUTRAL, "rate for %s" % realm_id)


## The reservoir is the body path's MAGNITUDE and it is authored per realm. It
## must rise strictly with depth, and it must stay a magnitude rather than
## collapsing into the realm's rate: a rate bounded under 2x across the whole
## ladder cannot be what makes the reservoir grow. Together with the no-double-
## count rule in `BodyTraining.synchronize`, this is what stops the rate silently
## becoming the magnitude.
func test_the_reservoir_magnitude_rises_and_is_not_the_rate() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous := 0.0
	for realm in realms:
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(seed.integrity_maximum > previous, true, "reservoir rises for %s" % realm.id)
		previous = seed.integrity_maximum
		assert_eq(
			seed.integrity_maximum > RealmRate.factor(realm.id),
			true,
			"the reservoir is a magnitude, not the rate, at %s" % realm.id
		)


# --- Targets and work ------------------------------------------------------


## True when every entry equals the first within `tolerance`. The authored
## scalars are written to fixed decimal places, so differences recomputed in
## float can disagree in the last ulp; the tolerance is one rounding step, and
## any real disagreement between two ladders is orders of magnitude above it.
func _all_equal(values: Array[float], tolerance: float = 0.0001) -> bool:
	if values.is_empty():
		return false
	var first := values[0]
	for value in values:
		if absf(value - first) > tolerance:
			return false
	return true


## Q(R) and U(R) are AUTHORED DATA (`BodyRealmSeed.quality_target` /
## `integrity_target`), not functions the runtime evaluates. The recipe that
## filled them lives in exactly one place — `tools/cultivation/ladder.py` — and
## `cultivation audit` asserts every `.tres` against it, so a retune is a
## legitimate content change and this suite does not re-own a copy of it. The
## old assertion pasted `0.40 + 0.015i` / `0.45 + 0.015i`, which is a second
## copy of the generator's recipe: it desynchronised the moment a seed was
## retuned, and it asserted nothing about the game.
##
## What is this suite's to own is the SHAPE those two numbers must keep
## together, read out of the data rather than pasted from a curve:
##
##   - the reservoir is charged at least as far as the huyệt are trained, so
##     U(R) must sit strictly above the quality ceiling it is reached with;
##   - and both steps are UNIFORM, so no realm can be retuned out of line with
##     the rest of the ladder.
##
## The uniformity is the half that earns its keep: retuning the base and the
## step together keeps it green without editing this file, while a single realm
## moved by hand fails it.
func test_quality_and_integrity_targets_keep_uniform_gaps() -> void:
	var ceiling_steps: Array[float] = []
	var reservoir_gaps: Array[float] = []
	var counted := 0
	var previous_ceiling := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var ceiling := seed.quality_target
		var reservoir := seed.integrity_target
		assert_eq(
			reservoir > ceiling,
			true,
			(
				"reservoir target %.4f is not charged as far as the %.4f ceiling at %s"
				% [reservoir, ceiling, realm.id]
			)
		)
		if counted > 0:
			ceiling_steps.append(ceiling - previous_ceiling)
		reservoir_gaps.append(reservoir - ceiling)
		previous_ceiling = ceiling
		counted += 1
	assert_eq(counted, 30, "every realm has a seed")
	assert_eq(_all_equal(ceiling_steps), true, "Q(R) steps by one distance across the whole ladder")
	assert_eq(
		_all_equal(reservoir_gaps), true, "U(R) stands off Q(R) by one distance on every realm"
	)


## GDScript's `roundf()` rounds half away from zero. Python's `round()` does not,
## and the generator asserts against this suite, so both sides must use the same
## rule or an exact .5 becomes a one-off mismatch.
func _round_half_up(value: float) -> float:
	return floorf(value + 0.5) if value >= 0.0 else ceilf(value - 0.5)


## The retuner rounds its budget into whole work units and writes those to the
## `.tres`; this suite recomputes the same double from the same authored value.
## Two engines doing the same arithmetic can differ in the last ulp (~1e-14
## relative), which only changes the rounded result when the value sits on a `.5`
## boundary. Both sides are integers, so half a unit is the exact tolerance
## here: any real disagreement is at least 1.0 and still fails.
func _assert_whole_labour(actual: float, expected: float, label: String) -> void:
	assert_almost_eq(actual, expected, label, 0.5)


## Work is the PRICE side of the loop and it is authored per realm, so there is
## no oracle left to check it against — what the ladder deleted along with the
## formula that generated it. What remains, and what the generator still writes,
## is the recipe: the budget rises strictly with depth, and the two sub-budgets
## are that budget cut against the huyệt count the PREVIOUS realm unlocked
## (i.e. max(1, index)), matching the retuner's divisor.
func test_work_budget_rises_with_depth_and_cuts_into_sub_budgets() -> void:
	var ladder := RealmDefaults.ladder()
	var previous := 0.0
	var counted := 0
	for realm in ladder.realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var index := ladder.index_of(realm.id)
		assert_eq(seed.work_required > previous, true, "work rises for %s" % realm.id)
		previous = seed.work_required
		var work := _round_half_up(seed.work_required)
		var divisor := float(maxi(1, 4 * maxi(1, index)))
		var expected_point := _round_half_up(work / divisor)
		var expected_channel := _round_half_up(work / float(maxi(1, 4 * (index + 1))))
		_assert_whole_labour(seed.acupoint_work, expected_point, "acupoint work for %s" % realm.id)
		_assert_whole_labour(
			seed.meridian_work, expected_channel, "meridian work for %s" % realm.id
		)
		counted += 1
	assert_eq(counted, 30, "every realm has a seed")


## The enforced gate and the authored budget must describe one quantity. They
## used to diverge by up to 4.6x at R30. It also ties the price used by
## `test_reward_per_labour_never_gets_worse_with_depth` to the gate the player
## actually has to pass.
func test_progress_requirement_equals_the_work_budget() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_almost_eq(
			seed.progress_required, seed.work_required, "gate matches the budget for %s" % realm.id
		)


## Reward gained per unit of labour work never gets worse — the property that
## stops the top realms becoming free, and the one thing the deleted power ladder
## existed to protect. It is restated here in the units the game actually uses,
## because the ladder's version compared two reads of ONE curve and cannot
## survive that curve's deletion:
##
##   reward per unit of work = the realm RATE — what one unit of training work is
##           worth, which is the only thing this module applies from the ladder's
##           old role
##   price                  = cultivation work units a breakthrough costs: the
##           authored budget (`progress_required`, pinned equal to `work_required`
##           above) divided by the rate `BodyTraining.cultivate` converts with
##
## Both are read from the code under test, so a change to either the profile or
## the training layer lands here as a failure rather than as a stale pin.
##
## ## What was deliberately changed, and why
##
## The original assertion divided the reward ratio by the cost ratio and demanded
## the quotient rise. That was only ever true because the reward WAS the shared
## magnitude, which grew 1e46 while the labour curve grew 100x. With the ladder
## gone there is no magnitude left for a provider to read — core's
## `RealmScaling` owns it for the shared stats and `integrity_maximum` owns it for
## the reservoir — so the only remaining reward-per-unit-of-work IS the rate, and
## a rate cannot rise faster than the price it is measured against without
## ceasing to be a rate. The quotient form is therefore unsatisfiable, not merely
## inconvenient.
##
## What replaces it is the property the invariant was FOR, stated so it cannot be
## satisfied by accident: **reward per unit of work never falls below its R1
## value, and never falls below the reciprocal of the price step at any
## transition.** Together with the price assertions below that means no realm is
## free and no realm is a downgrade: the further you climb the more work each
## breakthrough costs, and the rate you convert that work at never regresses.
func test_reward_per_labour_never_gets_worse_with_depth() -> void:
	var realms := RealmDefaults.ladder().realms()
	var entry_rate := RealmRate.factor(realms[0].id)
	var previous_rate := entry_rate
	var previous_price := 0.0
	var priced := 0
	for index in range(1, realms.size()):
		var here := realms[index - 1]
		var target := realms[index]
		var seed := BodyRealmSeed.for_realm(target.id)
		if seed == null or seed.work_required <= 0.0:
			continue
		var reward := RealmRate.factor(target.id)
		var price := seed.work_required / RealmRate.factor(here.id)
		# (1) Reward per unit of work never regresses: the rate is monotonic and
		# never falls below the R1 reference.
		assert_eq(reward >= entry_rate, true, "reward per labour holds at %s" % target.id)
		assert_eq(reward > previous_rate, true, "reward per labour rises into %s" % target.id)
		# (2) No realm is cheaper than the one below it. Under the old ladder the
		# gain WAS the magnitude, so entering R30 cost ~1e-45 units of work.
		assert_eq(
			price > previous_price, true, "%s costs more labour than %s" % [target.id, here.id]
		)
		# (3) The rate never outruns the price it converts — the condition that
		# makes (2) hold, asserted directly against the authored budget.
		var rate_step := reward / previous_rate
		var budget_step := seed.work_required / BodyRealmSeed.for_realm(here.id).work_required
		assert_eq(
			rate_step <= budget_step,
			true,
			"rate step %s within budget step %s at %s" % [rate_step, budget_step, target.id]
		)
		previous_rate = reward
		previous_price = price
		priced += 1
	assert_eq(priced, 29, "every transition on the ladder was priced")


func test_insight_floor_follows_formula() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var index := RealmDefaults.ladder().index_of(realm.id)
		assert_almost_eq(
			seed.insight_required,
			10.0 + 6.0 * index + 2.0 * index * index,
			"insight floor for %s" % realm.id
		)


func test_resonance_ranks_for_high_realms() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var index := RealmDefaults.ladder().index_of(realm.id)
		if index >= 18:
			assert_eq(seed.resonance_rank, index - 17, "resonance rank for %s" % realm.id)
		else:
			assert_eq(seed.resonance_rank, 0, "no resonance for %s" % realm.id)


## Risk must never reach certainty, and the floor must stay under the ceiling.
## Both bounds are AUTHORED per realm (`chance_base` / `chance_cap`), so this
## suite does not re-own the generator's recipe for them — `tools/cultivation/
## ladder.py` holds it once and `cultivation audit` asserts every `.tres`
## against it. The old assertion pasted `minf(0.55 + 0.008i, 0.80)` /
## `maxf(0.95 - 0.008i, 0.70)`, a second copy of that recipe that reported 148
## failures when the seeds were retuned and asserted nothing about the game.
##
## What is asserted here is the SHAPE the two numbers must keep for the roll to
## mean anything, all read out of the data rather than pasted from a curve:
##
##   - a floor strictly under the ceiling, or `BodyAdvancement._chance`'s clamp
##     swallows the huyệt term and training the body cannot change the outcome;
##   - no realm a certain success, so the deviation loop stays reachable;
##   - the ceiling strictly ABOVE what a fully trained body can roll, so it is a
##     backstop against over-training rather than the thing that prices the
##     attempt — a cap an ordinary body already meets would make the last of the
##     huyệt work free;
##   - and the floor DECLINES with depth, which is what keeps the ceiling
##     meaningful further up the ladder.
##
## That last one is the shape the old `0.55 + 0.008i` recipe violated: a floor
## rising into a falling ceiling crossed at R26 and left five realms certain.
func test_breakthrough_risk_bounds_keep_a_live_band() -> void:
	var ladder := RealmDefaults.ladder()
	var previous_base := INF
	var counted := 0
	for index in ladder.realms().size():
		var realm := ladder.realms()[index]
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var floor := seed.chance_base
		var cap := seed.chance_cap
		# A floor at or above the ceiling is not a band: the clamp in
		# `BodyAdvancement._chance` swallows the acupoint term entirely.
		assert_eq(
			floor < cap,
			true,
			"chance floor %.4f must sit below the ceiling %.4f at %s" % [floor, cap, realm.id]
		)
		assert_eq(cap < 1.0, true, "no realm is a guaranteed success (%s)" % cap)
		assert_eq(
			floor >= BodyAdvancement.MIN_CHANCE,
			true,
			"floor %.4f is under the clamp at %s" % [floor, realm.id]
		)
		# The ceiling is priced against the best quality an actor can actually
		# hold while attempting this realm: the realm BELOW's training ceiling,
		# since standing above `gate` is what the attempt demands.
		var best := seed.quality_target
		if index > 0:
			var below := BodyRealmSeed.for_realm(ladder.realms()[index - 1].id)
			if below != null:
				best = below.quality_target
		var reach := floor + best * BodyAdvancement.QUALITY_TO_CHANCE
		assert_eq(
			cap > reach,
			true,
			"ceiling %.4f is met by the %.4f a trained body reaches at %s" % [cap, reach, realm.id]
		)
		if counted > 0:
			assert_eq(
				floor <= previous_base,
				true,
				"floor %.4f rises into the band at %s" % [floor, realm.id]
			)
		previous_base = floor
		counted += 1
	assert_eq(counted, 30, "every realm has a seed")


func test_channel_training_names_real_meridians() -> void:
	var known: Array[StringName] = []
	for def in MeridianDefaults.all():
		known.append(def.id)
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for meridian_id in seed.channel_training:
			assert_eq(known.has(meridian_id), true, "channel %s exists" % meridian_id)


# --- Reachability ----------------------------------------------------------


## A realm must be enterable with one realm of training: its gate can never ask
## for more than the previous realm can produce. This is the invariant that was
## broken before ADR 0028 and stalled the traversal at R8.
##
## Reachability is the property, so it is asserted as a COMPARISON between two
## seeds and never as a pasted number. The old form demanded
## `quality_required == previous.quality_target`, which was only ever true
## while the generator pinned the gate onto the ceiling — and that pinning is
## itself the bug this suite now guards against, because a gate level with the
## ceiling leaves no span of huyệt quality for the breakthrough roll to price.
## So the two halves are:
##
##   1. REACHABLE — the gate is at or below what the realm below can train to;
##   2. and a strict HEADROOM below it, so acupoint quality still decides
##      something. `test_seed_balance_invariants.gd` asserts the same shape;
##      it is restated here because this suite is the one that owns the entry
##      gate's relationship to the realm below.
##
## The uniform headroom is derived, not pasted: the generator sets every gate
## one `QUALITY_HEADROOM` under the ceiling, so the gap is a constant across the
## ladder. Reading it as a constant asserts the recipe holds uniformly without
## restating its value — retune the ladder and this stays green.
func test_entry_gates_are_reachable_from_the_previous_realm() -> void:
	var realms := RealmDefaults.ladder().realms()
	var headrooms: Array[float] = []
	var counted := 0
	for index in range(1, realms.size()):
		var target := BodyRealmSeed.for_realm(realms[index].id)
		var source := BodyRealmSeed.for_realm(realms[index - 1].id)
		if target == null or source == null:
			continue
		var gate := target.quality_required
		var ceiling := source.quality_target
		assert_eq(
			gate <= ceiling,
			true,
			(
				"gate %.4f for %s is above the %.4f the realm below can train to"
				% [gate, realms[index].id, ceiling]
			)
		)
		assert_eq(
			gate < ceiling,
			true,
			(
				"no huyệt quality to price at %s: gate %.4f is level with ceiling %.4f"
				% [realms[index].id, gate, ceiling]
			)
		)
		headrooms.append(ceiling - gate)
		assert_eq(
			target.required_refinement <= source.refinement_cap,
			true,
			"refinement gate for %s fits in %s" % [realms[index].id, realms[index - 1].id]
		)
		counted += 1
	assert_eq(counted, 29, "every transition on the ladder was checked")
	assert_eq(_all_equal(headrooms), true, "the gate sits one headroom below every ceiling")


func test_meridian_integration_increases_with_each_tier() -> void:
	var previous := 0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.required_meridians.size() >= previous,
			true,
			"meridian demand does not shrink for %s" % realm.id
		)
		previous = seed.required_meridians.size()
