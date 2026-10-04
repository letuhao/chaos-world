extends TestCase

## DEF-0250 on the mind path: the mind breakthrough roll, proved to be a roll.
##
## ## THE DEFECT THIS FILE EXISTS FOR
##
## `MindAdvancement.start` wrote `committed.rng_state = 0 if rng == null else
## rng.seed`, and the shipped facade passes no rng. `resolve_attempt` then replayed a
## generator seeded 0. MEASURED 2026-10-04: that generator's first `randf()` is
## 0.202272.
##
## Mind authors no `chance_base`. `MindAdvancement._chance` derives the chance as
## `clamp(MIN_CHANCE + sea.clarity * CLARITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)` = a
## `[0.05, 0.95]` band, and `start` refuses unless
## `sea.clarity >= source_seed.clarity_required`. The lowest `clarity_required` on
## all 30 mind seeds is 0.40 (`qi_refining.tres`), so the lowest chance any committed
## mind attempt can carry is `0.05 + 0.40 * 0.5` = **0.25**.
##
## **DIRECTION, measured rather than assumed: seed 0 WON every realm, exactly as it
## did on the body.** `resolve_attempt` deviates when the roll is at or above the
## chance, and 0.202272 < 0.25, so `randf() >= chance` never fired. Not a guaranteed
## failure — a guaranteed SUCCESS. Every shipped mind breakthrough was certain, the
## mental-deviation and recovery leg of the program was unreachable in production,
## and 30 seeds' worth of authored preparation risk was decorative. A constant seed
## is not an unlucky seed; it is the absence of a roll.
##
## `test_a_pending_attempt_survives_save_and_load` was green through all of it
## because it committed with seed 21 and then resolved with a hand-searched WINNING
## seed, asserting a victory its own record never licensed: it named `rng_state` in
## an assertion and did not use it. That case now reads the stored roll, and the
## pair of files is why this defect class stays visible.
##
## ## WHAT IS PROVED, IN ORDER
##
##   1. the measured seed-0 draw, and the direction it pointed on THIS ladder;
##   2. the commit draws a seed, it VARIES, and it is never the constant 0;
##   3. no door into a commit can write the excluded seed, either way;
##   4. every realm the gate admits can be won AND lost on the seeds a commit draws;
##   5. the shipped facade with NO rng succeeds sometimes and fails sometimes, and
##      lands exactly where its own stored roll says it must;
##   6. a committed attempt resolved after a reload yields the outcome — and the
##      burn — it would have yielded without one;
##   7. `MindAttemptRoll` and `BodyAttemptRoll` cannot drift apart silently.
##
## ## WHY THE ROLLS ARE NOT "HOPED FOR"
##
## Nothing here asserts that one particular press won. The sweeps drive the real
## commit path and count outcomes over the seed SPACE, which is the same answer on
## every run; the end-to-end cases count presses at one fixed realm and write the
## binomial arithmetic next to the bound. A suite that passed because it got lucky
## would be this defect all over again, in the other direction.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## Seeds per sweep in the space cases. At the floor chance any mind commit can carry
## (0.25) all 128 winning is 0.75^128 ~= 1e-16; at the deepest authored realm's
## ceiling (0.05 + 0.83 * 0.5 = 0.465) all 128 losing is 0.465^128 ~= 1e-35. This
## bound is a size, not a wish.
const SEED_SWEEP := 128

## Presses per sweep at ONE realm, on a fresh prepared actor each press so every press
## is an independent trial at the same chance. The binding side at a prepared actor is
## the shallow floor: 0.75^192 ~= 1e-24 all winning, against 0.465^192 ~= 1e-63 all
## losing at the deepest authored ceiling.
const PRESS_SWEEP := 192

## Draws taken straight off the seed source to prove the guard at its own door. A
## sample, not a census: the mask is arithmetic, so 512 draws witness it rather than
## search for it, and the suite's assertion count stays proportional to what it proves.
const GUARD_DRAWS := 512

## How far a measured win rate may sit from the authored chance before the sweep is
## reporting something other than the roll. The standard error of a 128-sample
## proportion at p=0.25 is 0.039, so this is close to four sigma — wide enough that a
## legitimately retuned chance band cannot flake it, and far tighter than the gap
## that let 0.202272 through (which was below EVERY realm the gate admits).
const RATE_TOLERANCE := 0.15

var _born: Array = []


func teardown() -> void:
	# Actors are RefCounted, but a `PathState` is connected to the actor's
	# invalidator, so the cycle outlives the refcount. The runner shares one process
	# across every suite, so nothing minted here is left for the next one.
	for born in _born:
		var actor := born as Actor
		if actor != null:
			actor.resources.clear()
	_born.clear()


# --- 1. The measurement, and the direction it pointed ------------------------


## The number the whole finding rests on, pinned from the engine rather than copied
## out of another module's docblock. If a Godot upgrade changes the first draw of a
## seed-0 generator, this goes red and the reasoning in `MindAttemptRoll` is re-checked
## rather than left standing on a stale figure.
func test_seed_zero_draws_the_measured_number() -> void:
	var draw := MindAttemptRoll.replay(MindAttemptRoll.MIN_SEED - 1).randf()
	assert_almost_eq(draw, 0.202272, "seed 0 draws the number the finding measured", 1e-6)


## **The direction, on the MIND ladder specifically.** Not assumed from the body.
##
## The reachable band is computed from the seeds themselves, so a retune of any
## `clarity_required` moves the floor and this assertion moves with it rather than
## going quietly stale. If the floor ever drops below 0.202272 the shipped defect
## would INVERT — every mind breakthrough would become a certain FAILURE — and this
## assertion is what says so instead of leaving it to be discovered in play.
func test_seed_zero_won_every_realm_the_mind_gate_admits() -> void:
	var draw := MindAttemptRoll.replay(MindAttemptRoll.MIN_SEED - 1).randf()
	var lowest := _reachable_chance_floor()
	var won_everywhere := true
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		# The chance a commit at THIS realm's source gate would carry.
		var chance := (
			MindAdvancement.MIN_CHANCE + seed.clarity_required * MindAdvancement.CLARITY_TO_CHANCE
		)
		if draw >= chance:
			won_everywhere = false
	assert_eq(
		won_everywhere,
		true,
		(
			(
				"seed 0 draws %.6f, below the %.4f floor the mind gate admits, so it WON every realm: "
				+ "storing it made every mind breakthrough certain, which is what a constant is"
			)
			% [draw, lowest]
		)
	)
	# The reverse claim is the severe one, so it is stated rather than assumed: had
	# the draw sat ABOVE the floor, every shipped attempt would have been a certain
	# failure instead. Neither direction is survivable, which is why the seed cannot
	# be a constant at all.
	assert_eq(
		draw < _reachable_chance_floor(),
		true,
		"and the draw is below the floor rather than above it, so the defect was certainty not ruin"
	)


## The lowest chance any mind commit can actually carry: `start` refuses below
## `source_seed.clarity_required`, and `_chance` reads clarity alone. Read off the
## seeds, so it is the authored floor and not a number typed in here.
func _reachable_chance_floor() -> float:
	var lowest := 1.0
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var chance := (
			MindAdvancement.MIN_CHANCE + seed.clarity_required * MindAdvancement.CLARITY_TO_CHANCE
		)
		lowest = minf(lowest, chance)
	return lowest


# --- 2 + 3. The commit draws a seed, and never the unusable one --------------


## The defect in one assertion: a press through the shipped facade stores a seed the
## roll can actually beat. `rng_state = 0` fails every realm on the ladder, so this
## reads green only because the stored value moved off 0.
##
## The sweep also proves the seed VARIES. A constant that happened to win would
## satisfy "not 0" and still be the same defect wearing a different number — which is
## what `rng_state = rng.seed` was for any caller that passed one.
func test_a_committed_attempt_stores_a_varying_seed_no_press_can_carry() -> void:
	var actor := _prepared()
	var seeds := {}
	var lowest := MindAttemptRoll.SEED_MASK
	for _press in SEED_SWEEP:
		var stored := _commit_and_read_seed(actor)
		lowest = mini(lowest, stored.rng_state)
		seeds[stored.rng_state] = true
		MindAdvancement.cancel(actor)
	# Two AGGREGATES rather than one assertion per press: a sweep that fails on every
	# pass writes the same line 128 times, which trips the framework's own loop guard
	# before it can name the cause.
	assert_eq(
		lowest >= MindAttemptRoll.MIN_SEED,
		true,
		(
			"the lowest of %d pressed seeds is %d, and 0 is the one seed whose outcome never varies"
			% [SEED_SWEEP, lowest]
		)
	)
	assert_eq(
		seeds.size() > 1,
		true,
		(
			"%d presses drew %d distinct seeds, so the seed is entropy and not a constant"
			% [SEED_SWEEP, seeds.size()]
		)
	)


## The guard at its own door, both ways. The engine's own generator cannot produce the
## excluded value, and a caller's `rng.seed = 0` is FLOORED rather than stored — so
## there is no argument to `start` and no absence of one that writes the seed which
## made every mind breakthrough certain.
func test_no_door_into_a_commit_can_write_the_seed_that_always_wins() -> void:
	var lowest := MindAttemptRoll.SEED_MASK
	for _draw in GUARD_DRAWS:
		lowest = mini(lowest, MindAttemptRoll.seed_for())
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var from_a_caller := MindAttemptRoll.seed_for(rng)
	assert_eq(
		lowest >= MindAttemptRoll.MIN_SEED,
		true,
		"the lowest of %d draws off the engine's own generator is %d" % [GUARD_DRAWS, lowest]
	)
	assert_eq(
		from_a_caller,
		MindAttemptRoll.MIN_SEED,
		"and a caller's seed 0 is floored to %d rather than stored" % from_a_caller
	)


## A caller that pins the seed pins the WHOLE trial, which is what lets every suite in
## this module choose an outcome instead of hoping for one.
func test_a_supplied_generator_is_stored_verbatim() -> void:
	var actor := _prepared()
	var seed := _next_seed(actor)
	for candidate in 5:
		Probe.stock(actor, seed.breakthrough_item)
		var committed := MindAdvancement.start(actor, _rng(candidate + 1))
		assert_ne(committed, null, "press %d committed" % candidate)
		if committed == null:
			return
		assert_eq(
			committed.rng_state,
			candidate + 1,
			"a supplied seed is stored verbatim, so the record names its own roll"
		)
		MindAdvancement.cancel(actor)


# --- 4. Every realm the gate admits, on both sides ---------------------------


## Across the whole ladder the seed space produces BOTH outcomes for every realm the
## entry gate can admit. This is the strong form of the claim and it cannot flake: it
## sweeps the seed SPACE rather than taking trials, so it is the same answer on every
## run. A realm that could only ever win, or only ever lose, fails here by name.
func test_every_realm_can_be_won_and_can_be_lost_on_the_seeds_a_commit_draws() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		# The chance a commit out of THIS realm would carry, which the gate floors at
		# the realm's own `clarity_required`.
		var chance := (
			MindAdvancement.MIN_CHANCE + seed.clarity_required * MindAdvancement.CLARITY_TO_CHANCE
		)
		var wins := 0
		for candidate in SEED_SWEEP:
			if MindAttemptRoll.replay(candidate + 1).randf() < chance:
				wins += 1
		assert_eq(
			wins > 0,
			true,
			(
				"%s: %d of %d seeds beat chance %.4f, so it can be won"
				% [realm.id, wins, SEED_SWEEP, chance]
			)
		)
		assert_eq(
			wins < SEED_SWEEP,
			true,
			"%s: %d seeds beat chance %.4f, so it can also be lost" % [realm.id, wins, chance]
		)


## The chance band is bounded away from both ends on every realm, so `P(win) = chance`
## is strictly interior rather than accidentally total. One realm whose floor sat at
## `MIN_CHANCE` and another's ceiling at `MAX_CHANCE` would make the sweep above pass
## for the wrong reason.
func test_the_chance_band_is_strictly_interior_on_every_realm() -> void:
	var lowest := 1.0
	var highest := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var chance := (
			MindAdvancement.MIN_CHANCE + seed.clarity_required * MindAdvancement.CLARITY_TO_CHANCE
		)
		lowest = minf(lowest, chance)
		highest = maxf(highest, chance)
	assert_eq(
		lowest > MindAdvancement.MIN_CHANCE,
		true,
		(
			"the shallowest realm still commits at %.4f, above the %.2f floor: never a certain failure"
			% [lowest, MindAdvancement.MIN_CHANCE]
		)
	)
	assert_eq(
		highest < MindAdvancement.MAX_CHANCE,
		true,
		(
			"the deepest realm commits at %.4f, under the %.2f ceiling: never a certain success"
			% [highest, MindAdvancement.MAX_CHANCE]
		)
	)


# --- 5. The shipped facade, end to end --------------------------------------


## **Acceptance criterion 1, as a player experiences it.** No rng argument anywhere:
## `MindCultivationApi.try_breakthrough` is the verb the Breakthrough button calls —
## `app/mind_cultivation_ui.gd` calls it DIRECTLY, skipping the facade entirely — so
## it must both win and lose.
##
## A FRESH prepared actor per press, so every press is an independent trial at the
## same realm and the same chance, which is what makes the bound a binomial rather
## than a walk up thirty realms with a different chance at each. Preparation between
## attempts is the recovery a deviation requires, so a failure here is not a dead end.
func test_the_shipped_press_without_a_generator_both_wins_and_loses() -> void:
	var won := false
	var lost := false
	var chance := 0.0
	for _press in PRESS_SWEEP:
		var actor := _prepared()
		chance = float(MindCultivationApi.preview(actor).get("chance", 0.0))
		if MindCultivationApi.try_breakthrough(actor):
			won = true
		else:
			# `false` is also what a REFUSAL returns, so a refused press must not be
			# counted as a deviation. The record's own `trial_complete` is the
			# difference between "rolled and lost" and "never ran", and without this
			# check the sweep would report a working roll on a fixture that refuses.
			var stored := MindAdvancement.attempt(actor)
			if stored != null and stored.trial_complete:
				lost = true
		if won and lost:
			break
	assert_eq(lost, true, "a press ROLLED and deviated at chance %.4f, so failure is real" % chance)
	assert_eq(
		won, true, "and another press won at chance %.4f: neither outcome is guaranteed" % chance
	)


## The wiring claim, and the one that would have gone red first. The facade takes no
## generator, so the only thing that can decide its press is the seed its own commit
## stored — and the press must land exactly where that seed says it lands. This is
## deterministic: it asserts the module's arithmetic against the record the press
## left, so it cannot be a lucky roll and cannot flake.
func test_the_shipped_press_lands_where_its_own_stored_roll_says() -> void:
	var actor := _prepared()
	var advanced := MindCultivationApi.try_breakthrough(actor)
	var stored := MindAdvancement.attempt(actor)
	assert_ne(stored, null, "the press left a record")
	if stored == null:
		return
	var chance := float(stored.preparation.get("chance", 0.0))
	var expected := MindAttemptRoll.replay(stored.rng_state).randf() < chance
	assert_eq(
		advanced,
		expected,
		(
			"seed %d drew below %.4f: the press returned what its own committed roll says"
			% [stored.rng_state, chance]
		)
	)
	assert_eq(
		stored.trial_complete,
		true,
		"and the trial ran, so this is a decided record rather than a cancellation"
	)


## The pair the program is judged on, stated as one sentence: a player who deviates
## recovers and crosses anyway. Both halves of the loop, through the shipped verb,
## with no generator anywhere.
##
## TWO BOUNDED LOOPS rather than one that stops at the first win: a loop that broke on
## a win would report "recoverable" for a walk that never deviated, which is exactly
## the invisible assertion this file exists to stop making.
##
## The FIRST loop presses a FRESH prepared actor each time, because a success advances
## the realm and would leave every later press aimed at the wrong target — burning the
## budget on refusals while reporting a roll that never varied. The mind that actually
## deviated is carried into the recovery half, so "recover and cross anyway" is claimed
## about ONE actor rather than about a walk of unrelated ones.
func test_a_deviation_is_recoverable_and_the_next_attempt_can_win() -> void:
	var chance := 0.0
	var hurt := _prepared()
	var deviated := false
	var first := 0
	while first < PRESS_SWEEP and not deviated:
		first += 1
		var candidate := _prepared()
		chance = float(MindCultivationApi.preview(candidate).get("chance", 0.0))
		if MindCultivationApi.try_breakthrough(candidate):
			continue
		# A refusal also returns `false`; only a record that RAN its trial and came
		# back failed is the deviation this loop is hunting.
		var rolled := MindAdvancement.attempt(candidate)
		if rolled != null and rolled.trial_complete and not rolled.outcome_granted:
			deviated = true
			hurt = candidate
	assert_eq(
		deviated,
		true,
		"a press ROLLED and deviated at chance %.4f within %d presses" % [chance, first]
	)
	# What a player does next: repair the wound, refill, train, and press again — on
	# the mind that deviated, at the realm it is still standing in.
	var won := false
	var again := 0
	while again < PRESS_SWEEP and not won:
		again += 1
		var burns := _burned_channel(hurt)
		if not burns.is_empty():
			# The recovery is the realm's own elixir (ADR 0031), which the deviation
			# itself consumed, so a player pays a fresh one to come back.
			var here := MindRealmSeed.for_realm(hurt.path(MindPath.PATH_ID).rank_id)
			Probe.stock(hurt, here.recovery_item)
			MindTraining.recover(hurt, burns[0])
		if _prepare(hurt) == null:
			break
		won = MindCultivationApi.try_breakthrough(hurt)
	assert_eq(
		won,
		true,
		(
			(
				"and the repaired actor was won through within %d more presses, so a deviation is "
				+ "recoverable rather than terminal"
			)
			% again
		)
	)


# --- 6. Durable across a reload --------------------------------------------


## **Acceptance criterion 2.** The same committed attempt, resolved with and without a
## save in between, must land on the same sea. This is the property ADR 0187's durable
## lifecycle exists for, and the one the old code could not hold: the record named
## seed 0 while `try_breakthrough` handed the SAME generator to both halves, so a
## save-spanning attempt was a different trial wearing the same verdict.
##
## The burn is compared as well as the verdict, because a deviation that burned a
## DIFFERENT meridian after a reload is a different trial with the same answer.
func test_a_reloaded_attempt_resolves_to_the_outcome_and_burn_it_would_have() -> void:
	var agreed := 0
	var burns_compared := 0
	var same_burn := 0
	var disagreement := ""
	for _press in PRESS_SWEEP:
		var actor := _prepared()
		var committed := MindAdvancement.start(actor)
		if committed == null:
			disagreement = "press %d refused to commit" % _press
			break
		var reloaded := Actor.from_dict(actor.to_dict())
		MindCultivationApi.attach(reloaded)
		MindCultivationApi.attach_sea(reloaded)
		ItemsApi.attach(reloaded)
		MindTraining.synchronize(reloaded)
		_born.append(reloaded)
		var after_reload := MindAdvancement.resolve_attempt(reloaded)
		var without_reload := MindAdvancement.resolve_attempt(actor)
		if after_reload != without_reload:
			disagreement = (
				"press %d: seed %d resolved %s after a reload and %s without one"
				% [_press, committed.rng_state, after_reload, without_reload]
			)
			break
		agreed += 1
		var rolled := MindAdvancement.attempt(actor)
		if not after_reload:
			# Both sides agreeing on a REFUSAL would agree on nothing: the point is
			# that they agree on the ROLL. `trial_complete` is what says it ran.
			if rolled == null or not rolled.trial_complete:
				continue
			burns_compared += 1
			if _burned_channel(reloaded) == _burned_channel(actor):
				same_burn += 1
	# The sweep STOPS at the first disagreement rather than asserting 192 times: a
	# resolve that stops honouring the record fails on the first press, and 192
	# identical lines would trip the framework's loop guard before naming it.
	assert_eq(
		disagreement,
		"",
		(
			"%d of %d attempts resolved identically across the save%s"
			% [agreed, PRESS_SWEEP, "" if disagreement.is_empty() else "; " + disagreement]
		)
	)
	assert_eq(burns_compared > 0, true, "the sweep saw a deviation to compare burns on")
	assert_eq(
		same_burn == burns_compared,
		true,
		"and every deviation burned the same meridian on both sides of the save"
	)


## The two halves must agree even when the CALLER supplies the generator — the shape
## that used to diverge, because `try_breakthrough` handed one rng to both and the
## commit stored `rng.seed` while the resolve drew the stream that the tribulation
## fight had already advanced.
func test_a_supplied_generator_produces_the_same_trial_on_both_sides_of_a_save() -> void:
	var actor := _prepared()
	var chance := float(MindCultivationApi.preview(actor).get("chance", 0.0))
	var winning := _seed_beating(chance)
	assert_ne(winning, 0, "a winning seed exists for chance %.4f" % chance)
	var committed := MindAdvancement.start(actor, _rng(winning))
	assert_ne(committed, null, "attempt committed")
	if committed == null:
		return
	assert_eq(committed.rng_state, winning, "and the record names the seed it was given")

	var reloaded := Actor.from_dict(actor.to_dict())
	MindCultivationApi.attach(reloaded)
	MindCultivationApi.attach_sea(reloaded)
	ItemsApi.attach(reloaded)
	MindTraining.synchronize(reloaded)
	_born.append(reloaded)
	assert_eq(
		MindAdvancement.resolve_attempt(reloaded),
		true,
		"the stored roll won after the reload, exactly as the pinned seed says it must"
	)


# --- 7. The two helpers cannot drift apart ----------------------------------


## `MindAttemptRoll` is a module-local copy of `BodyAttemptRoll`'s policy, deliberately
## (see its docblock on why it is not in `core/`). The arithmetic in them is a
## property of the engine's RNG, and the one honest defence against two copies of a
## number is a test that says they must agree — which is what this is.
##
## It is a cross-module reference in a TEST, which is allowed: the facade-only rule
## governs `src/`, and `tests/audits/test_audit_body_seed_determinism.gd` already
## reads `BodyAttemptRoll` from outside its module. What would NOT be allowed is
## `mind_cultivation` PRELOADING it, and no file in `src/` does.
##
## Collapsing the pair into one `core/` class is the right end state and needs an ADR
## plus a `body_cultivation` edit in the same commit. Until both happen, this is what
## holds them to each other.
func test_the_mind_roll_helper_matches_the_body_one_it_was_modelled_on() -> void:
	assert_eq(MindAttemptRoll.MIN_SEED, BodyAttemptRoll.MIN_SEED, "same excluded seed")
	assert_eq(MindAttemptRoll.SEED_MASK, BodyAttemptRoll.SEED_MASK, "same fold into range")
	var disagreed := ""
	var pairs := 0
	for candidate in range(MindAttemptRoll.MIN_SEED, 32):
		var mine := MindAttemptRoll.replay(candidate)
		var theirs := BodyAttemptRoll.replay(candidate)
		for _draw in 3:
			pairs += 1
			if not is_equal_approx(mine.randf(), theirs.randf()):
				disagreed = "seed %d drew different values" % candidate
				break
		if not disagreed.is_empty():
			break
	assert_eq(
		disagreed,
		"",
		(
			"%d draws from seeds 1..31 matched the body helper exactly%s"
			% [pairs, "" if disagreed.is_empty() else "; " + disagreed]
		)
	)


# --- Source helpers ------------------------------------------------------------


## An actor at the brink of its next realm, brought there through public actions.
func _prepared() -> Actor:
	var actor := _actor()
	_born.append(actor)
	assert_ne(_prepare(actor), null, "prepared for the next realm through public actions")
	return actor


func _actor() -> Actor:
	var actor := Actor.new(&"roll_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	return actor


## Bring the actor to the brink of the next realm through public actions.
##
## Every wait is ASSERTED, not ignored. A prepare that quietly failed to converge
## would make `try_breakthrough` REFUSE, and a refusal also returns `false` — so the
## sweeps below would count a refused attempt as a deviation and report the roll as
## both-winnable-and-loseable while never having rolled at all. That is the invisible
## assertion this file exists to stop making, and it would have been mine.
func _prepare(actor: Actor) -> MindRealmSeed:
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	Probe.stock(actor, target_seed.breakthrough_item)
	Probe.stock(actor, source_seed.training_item)
	Probe.stock(actor, source_seed.sea_catalyst)
	Probe.stock(actor, source_seed.recovery_item)
	assert_eq(Probe.train_channels(actor, source_seed), true, "channels trained")
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.calm_sea(actor), true, "sea calm")
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened")
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned")
	assert_eq(Probe.fill_sea(actor), true, "sea filled")
	return target_seed


## One commit through the SHIPPED facade — no rng argument anywhere — and the record it
## left. The pill is restocked each press and cancelling leaves the actor untouched, so
## a sweep costs one preparation rather than one per press.
func _commit_and_read_seed(actor: Actor) -> MindAttempt:
	var seed := _next_seed(actor)
	assert_ne(seed, null, "the target realm authors a pill")
	Probe.stock(actor, seed.breakthrough_item)
	var committed := MindAdvancement.start(actor)
	assert_ne(committed, null, "a prepared actor's press commits an attempt")
	if committed == null:
		return MindAttempt.new()
	return committed


## The seed of the realm this actor is trying to ENTER, or null at the top.
func _next_seed(actor: Actor) -> MindRealmSeed:
	var target := RealmDefaults.ladder().next(actor.path(MindPath.PATH_ID).rank_id)
	return null if target == null else MindRealmSeed.for_realm(target.id)


## The meridian a deviation burned, sorted so the comparison is order-independent.
func _burned_channel(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured():
			out.append(def.id)
	out.sort()
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The smallest seed whose first draw beats `chance`. Bounded by the candidates this
## sweep tries, and it RETURNS rather than growing anything, so the loop cannot be the
## thing that does not terminate.
func _seed_beating(chance: float) -> int:
	for candidate in range(MindAttemptRoll.MIN_SEED, 256):
		if _rng(candidate).randf() < chance:
			return candidate
	return 0
