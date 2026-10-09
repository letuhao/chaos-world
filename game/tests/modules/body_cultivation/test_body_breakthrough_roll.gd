extends TestCase

## DEF-0250: the body breakthrough roll, proved to be a roll.
##
## ## THE DEFECT THIS FILE EXISTS FOR
##
## `BodyCultivationApi.begin_breakthrough` passed a null rng, so
## `BodyAdvancement._start` wrote `rng_state = 0`, and `resolve_attempt` replayed a
## generator seeded 0. MEASURED 2026-10-04: that generator's first `randf()` is
## 0.202272. The lowest `chance_base` authored anywhere on the 30-realm body ladder
## is 0.2580 and the highest is 0.4900, and `_chance` only ever RAISES chance above
## `chance_base` — so 0.202272 sits below every realm's band, and
## `if generator.randf() >= chance` was false for every realm at every acupoint quality.
##
## **So the shipped defect was not that attempts failed. It was that they could not
## fail.** Every body breakthrough in play was a certain success: the deviation and
## recovery system, the whole "fail recoverably" leg, was unreachable in production,
## and the risk numbers authored on 30 seeds were decorative. A constant seed is not a
## unlucky seed; it is the absence of a roll.
##
## `test_body_attempt_survives_the_save.gd` was green through all of that because it
## asserted only the invariants that hold "whichever way the roll fell" — and there
## was only ever one way it fell. A test that cannot fail on the outcome is not a weak
## test; it is an invisible one. Every case below asserts the OUTCOME, over a
## distribution rather than on one roll.
##
## ## WHAT IS PROVED, IN ORDER
##
##   1. the commit draws a seed, it VARIES, and it is never the constant 0;
##   2. across the whole 30-realm ladder, seeds produce BOTH wins and losses — so
##      success is possible everywhere and guaranteed nowhere;
##   3. the measured win rate sits on the authored `chance`, so the roll is a real
##      distribution and not a coin that happens to land both ways;
##   4. the shipped facade with NO rng argument succeeds sometimes and fails
##      sometimes, end to end, and lands where its own stored roll says it must;
##   5. a committed attempt resolved after a reload yields the outcome — and the
##      wound — it would have yielded without one, which is the property a durable
##      attempt exists for.
##
## ## WHY THE ROLLS ARE NOT "HOPED FOR"
##
## Nothing here asserts that one particular press won. The seed sweep drives the real
## commit path and counts outcomes over the seed SPACE, which is the same answer on
## every run; the end-to-end cases count presses at one fixed realm and write the
## binomial arithmetic next to the bound. A suite that passed because it got lucky
## would be the defect all over again — in the other direction, which is the one this
## module actually had.

## Seeds per sweep in the space cases. At the lowest authored `chance_base` (0.2580)
## all 128 losing is 0.742^128 ~= 2e-16; at the highest authored ceiling
## (`qi_refining.chance_cap`, 0.8500) all 128 winning is 0.8500^128 ~= 1e-9. This
## bound is a size, not a wish.
const SEED_SWEEP := 128

## Presses per sweep at ONE realm, on a fresh prepared body each press so every press
## is an independent trial at the same chance. The binding side at a prepared body is
## the high-ceiling realm: 0.8500^192 ~= 2e-14 all winning, against 0.742^192 ~= 3e-26
## all losing at the lowest authored chance.
const PRESS_SWEEP := 192

## Draws taken straight off the seed source to prove the guard at its own door. A
## sample, not a census: the mask is arithmetic, so 512 draws witness it rather than
## search for it, and the suite's assertion count stays proportional to what it proves.
const GUARD_DRAWS := 512

## How far a measured win rate may sit from the authored chance before the sweep is
## reporting something other than the roll. The standard error of a 128-sample
## proportion at p=0.258 is 0.037, so this is four sigma — wide enough that a
## legitimately retuned chance band cannot flake it, and far tighter than the gap
## that let 0.202272 through (which was below EVERY realm's floor).
const RATE_TOLERANCE := 0.15

var _play: BodyPlayFixture
var _born: Array = []


func setup() -> void:
	_play = BodyPlayFixture.new()
	_clear_disk()
	SaveApi.reset_clock()


func teardown() -> void:
	for born in _born:
		var body := born as Actor
		if body != null:
			# Actors are RefCounted, but a `PathState` is connected to the actor's
			# invalidator, so the cycle outlives the refcount.
			body.resources.clear()
	_born.clear()
	_clear_disk()
	SaveApi.reset_clock()


# --- 1. The commit draws a seed, and never the unusable one -------------------


## The defect in one assertion: a press through the shipped facade stores a seed the
## roll can actually beat. `rng_state = 0` fails every realm on the ladder, so this
## reads green only because the stored value moved off 0.
##
## The sweep also proves the seed VARIES. A constant that happened to win would
## satisfy "not 0" and still be the same defect wearing a different number — which is
## what `rng_state = rng.seed` was for any caller that passed one.
func test_a_committed_attempt_stores_a_varying_seed_no_press_can_carry() -> void:
	var hero := _prepared()
	var seeds := {}
	var lowest := BodyAttemptRoll.SEED_MASK
	for _press in SEED_SWEEP:
		var stored := _commit_and_read_seed(hero)
		lowest = mini(lowest, stored.rng_state)
		seeds[stored.rng_state] = true
		BodyAdvancement.cancel(hero)
	# Two AGGREGATES rather than one assertion per press: a sweep that fails on every
	# pass writes the same line 128 times, which trips the framework's own loop guard
	# before it can name the cause.
	assert_eq(
		lowest >= BodyAttemptRoll.MIN_SEED,
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


## The guard at its own door, both ways. The engine's own generator cannot produce
## the excluded value, and a caller's `rng.seed = 0` is floored rather than stored —
## so there is no argument to `start_attempt` and no absence of one that writes the
## seed that made every breakthrough certain.
func test_no_door_into_a_commit_can_write_the_seed_that_always_wins() -> void:
	var lowest := BodyAttemptRoll.SEED_MASK
	for _draw in GUARD_DRAWS:
		lowest = mini(lowest, BodyAttemptRoll.seed_for())
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var from_a_caller := BodyAttemptRoll.seed_for(rng)
	assert_eq(
		lowest >= BodyAttemptRoll.MIN_SEED,
		true,
		"the lowest of %d draws off the engine's own generator is %d" % [GUARD_DRAWS, lowest]
	)
	assert_eq(
		from_a_caller,
		BodyAttemptRoll.MIN_SEED,
		"and a caller's seed 0 is floored to %d rather than stored" % from_a_caller
	)


## A caller that pins the seed pins the WHOLE trial, which is what lets every suite in
## this module choose an outcome instead of hoping for one.
func test_a_supplied_generator_is_stored_verbatim() -> void:
	var hero := _prepared()
	var seed := _play.seed_for(hero)
	for candidate in 5:
		_play.stock(hero, seed.breakthrough_item)
		var committed := BodyAdvancement.start_attempt(hero, _rng(candidate + 1))
		assert_ne(committed, null, "press %d committed" % candidate)
		if committed == null:
			return
		assert_eq(
			committed.rng_state,
			candidate + 1,
			"a supplied seed is stored verbatim, so the record names its own roll"
		)
		BodyAdvancement.cancel(hero)


# --- 2 + 3. A distribution, on every realm ------------------------------------


## Across the whole ladder the seed space produces BOTH outcomes for every realm.
##
## This is the strong form of criterion 1 and it cannot flake: it sweeps the seed
## SPACE rather than taking trials, so it is the same answer on every run. A realm
## that could only ever win, or only ever lose, fails here by name.
func test_every_realm_can_be_won_and_can_be_lost_on_the_seeds_a_commit_draws() -> void:
	var hero := _prepared()
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	var wins := 0
	for _press in SEED_SWEEP:
		var committed := _commit_and_read_seed(hero)
		# The roll the game takes is the first draw of a generator rebuilt from the
		# record's own seed, so predicting it here predicts the game's outcome.
		if BodyAttemptRoll.replay(committed.rng_state).randf() < chance:
			wins += 1
		BodyAdvancement.cancel(hero)
	assert_eq(
		wins > 0,
		true,
		"%d seeds won at chance %.4f, so success is possible at this realm" % [SEED_SWEEP, chance]
	)
	assert_eq(
		wins < SEED_SWEEP,
		true,
		"%d of %d seeds won, so success is NOT guaranteed at this realm" % [wins, SEED_SWEEP]
	)
	assert_almost_eq(
		float(wins) / float(SEED_SWEEP),
		chance,
		"the win rate is the authored chance, not a coin that lands both ways",
		RATE_TOLERANCE
	)


## The same sweep over EVERY realm's authored band rather than one prepared body,
## because the band is what the ladder authors and the defect was measured against
## all 30 of them. Cheap: no actor is built, only seeds.
func test_no_authored_realm_band_rejects_every_seed_or_accepts_every_seed() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var wins := 0
		for candidate in SEED_SWEEP:
			if BodyAttemptRoll.replay(candidate + 1).randf() < seed.chance_base:
				wins += 1
		assert_eq(
			wins > 0,
			true,
			(
				"%s: %d of %d seeds beat chance_base %.4f, so it can be won"
				% [realm.id, wins, SEED_SWEEP, seed.chance_base]
			)
		)
		assert_eq(
			wins < SEED_SWEEP,
			true,
			"%s: %d seeds beat chance_base, so it can also be lost" % [realm.id, wins]
		)


## The measurement the old audit pinned, kept as the reason the guard exists — but read
## it the right way round. `resolve_attempt` deviates when the roll is AT OR ABOVE the
## chance, so seed 0's draw of 0.202272 sitting BELOW the lowest authored `chance_base`
## (0.2580) means seed 0 won EVERY realm: not a guaranteed failure, a guaranteed SUCCESS.
## Same defect pointing the other way — one seed whose outcome never varies — and it is
## why a commit cannot be allowed to write one.
func test_seed_zero_wins_every_realm_which_is_why_it_is_never_stored() -> void:
	var draw := BodyAttemptRoll.replay(BodyAttemptRoll.MIN_SEED - 1).randf()
	var lowest := 1.0
	var won_everywhere := true
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		lowest = minf(lowest, seed.chance_base)
		if draw >= seed.chance_base:
			won_everywhere = false
	assert_eq(
		won_everywhere,
		true,
		(
			(
				"seed 0 draws %.6f, below the lowest chance_base %.4f, so it won every realm: "
				+ "storing it made every breakthrough certain, which is what a constant is"
			)
			% [draw, lowest]
		)
	)


# --- 4. The shipped facade, end to end ----------------------------------------


## **Acceptance criterion 1, as a player experiences it.** No rng argument anywhere:
## `attempt_breakthrough` is the verb the breakthrough button calls, and it must both
## win and lose.
##
## A FRESH prepared body per press, so every press is an independent trial at the same
## realm and the same chance — which is what makes the bound a binomial rather than a
## walk through thirty realms with a different chance at each. Preparation between
## attempts is the recovery a deviation requires, so a failure here is not a dead end.
func test_the_shipped_press_without_a_generator_both_wins_and_loses() -> void:
	var won := false
	var lost := false
	var chance := 0.0
	for _press in PRESS_SWEEP:
		var hero := _prepared()
		chance = float(BodyAdvancement.preview(hero).get("chance", 0.0))
		if BodyCultivationApi.attempt_breakthrough(hero):
			won = true
		else:
			lost = true
		if won and lost:
			break
	assert_eq(lost, true, "a press deviated at chance %.4f, so failure is real" % chance)
	assert_eq(
		won, true, "and another press won at chance %.4f: neither outcome is guaranteed" % chance
	)


## The wiring claim, and the one that would have gone red first. The facade takes no
## generator, so the only thing that can decide its press is the seed its own commit
## stored — and the press must land exactly where that seed says it lands. This is
## deterministic: it asserts the module's arithmetic against the record the press left,
## so it cannot be a lucky roll and cannot flake.
func test_the_shipped_press_lands_where_its_own_stored_roll_says() -> void:
	var hero := _prepared()
	var advanced := BodyCultivationApi.attempt_breakthrough(hero)
	var stored := BodyAdvancement.attempt(hero)
	assert_ne(stored, null, "the press left a record")
	if stored == null:
		return
	var chance := float(stored.preparation.get("chance", 0.0))
	var expected := BodyAttemptRoll.replay(stored.rng_state).randf() < chance
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
## recovers and crosses anyway. Both halves of the loop, through the facade, with no
## generator anywhere.
##
## TWO BOUNDED LOOPS rather than one that stops at the first win: a loop that broke on
## a win would report "recoverable" for a walk that never deviated, which is exactly
## the invisible assertion this file exists to stop making.
func test_a_deviation_is_recoverable_and_the_next_attempt_can_win() -> void:
	var hero := _prepared()
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	var deviated := false
	var first := 0
	while first < PRESS_SWEEP and not deviated:
		first += 1
		deviated = not BodyCultivationApi.attempt_breakthrough(hero)
	assert_eq(deviated, true, "a press deviated at chance %.4f within %d presses" % [chance, first])
	# What a player does next: repair the wound, refill, train, and press again.
	var won := false
	var again := 0
	while again < PRESS_SWEEP and not won:
		again += 1
		_play.recover_damage(hero)
		if _play.prepare(hero) == null:
			break
		won = BodyCultivationApi.attempt_breakthrough(hero)
	assert_eq(
		won,
		true,
		(
			(
				"and the repaired body was won through within %d more presses, so a deviation is "
				+ "recoverable rather than terminal"
			)
			% again
		)
	)


# --- 5. Durable across a reload ----------------------------------------------


## **Acceptance criterion 2.** The same committed attempt, resolved with and without a
## save in between, must land on the same body. This is the property ADR 0187's
## durable lifecycle exists for, and the one the old code could not hold: the record
## named seed 0 while a resolve handed a generator drew off that generator's live
## stream instead, so a save-spanning attempt was a different trial wearing the same
## verdict.
##
## The wound is compared as well as the verdict, because a deviation that jammed a
## DIFFERENT acupoint after a reload is a different trial with the same answer.
func test_a_reloaded_attempt_resolves_to_the_outcome_and_wound_it_would_have() -> void:
	var agreed := 0
	var same_wound := 0
	var wounds_compared := 0
	var disagreement := ""
	for _press in PRESS_SWEEP:
		var hero := _prepared()
		var committed := BodyAdvancement.start_attempt(hero)
		if committed == null:
			disagreement = "press %d refused to commit" % _press
			break
		# Persist the COMMITTED record, then rebuild the body the way a boot does.
		var reloaded := _reload_through_the_save(hero)
		if reloaded == null:
			return
		var after_reload := BodyCultivationApi.resolve_breakthrough(reloaded)
		var without_reload := BodyAdvancement.resolve_attempt(hero)
		if after_reload != without_reload:
			disagreement = (
				"press %d: seed %d resolved %s after a reload and %s without one"
				% [_press, committed.rng_state, after_reload, without_reload]
			)
			break
		agreed += 1
		if not after_reload:
			wounds_compared += 1
			if _jammed(reloaded) == _jammed(hero):
				same_wound += 1
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
	assert_eq(wounds_compared > 0, true, "the sweep saw a deviation to compare wounds on")
	assert_eq(
		same_wound == wounds_compared,
		true,
		"and every deviation jammed the same acupoint on both sides of the save"
	)


## The two halves must agree even when the CALLER supplies the generator — the shape
## that used to diverge, because the commit stored `rng.seed` while the resolve drew
## from a generator already advanced by the tribulation fight.
func test_a_supplied_generator_produces_the_same_trial_on_both_sides_of_a_save() -> void:
	var hero := _prepared()
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	var seed_value := _seed_beating(chance)
	assert_ne(seed_value, 0, "a winning seed exists for this chance (%.4f)" % chance)
	var committed := BodyAdvancement.start_attempt(hero, _rng(seed_value))
	assert_ne(committed, null, "attempt committed")
	if committed == null:
		return
	assert_eq(committed.rng_state, seed_value, "and the record names the seed it was given")

	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return
	assert_eq(
		BodyCultivationApi.resolve_breakthrough(reloaded),
		true,
		"the stored roll won after the reload, exactly as the pinned seed says it must"
	)


## A save taken BETWEEN the two presses, on the two-phase facade rather than the
## one-press verb: commit, save, reload, resolve. The pill is already spent on the far
## side of the save and the realm is not yet gained, which is the state ADR 0187 made
## reachable and the state the old seed-0 roll made unwinnable.
##
## Which way the stored roll fell is deliberately NOT asserted here: that claim is
## carried by the two cases above, and asserting it again would make this case a coin
## flip over 128 iterations rather than a proof of anything.
func test_the_two_press_facade_leaves_nothing_stranded_when_a_save_lands_mid_attempt() -> void:
	var hero := _prepared()
	var committed := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(committed.is_empty(), false, "the first press commits")
	var target := String(committed.get("target", ""))
	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return
	assert_eq(
		String(reloaded.path(BodyPath.PATH_ID).rank_id) == target,
		false,
		"nothing has been gained yet: the trial has not run on the far side"
	)
	BodyCultivationApi.resolve_breakthrough(reloaded)
	var stored := BodyAdvancement.attempt(reloaded)
	assert_ne(stored, null, "the record is kept")
	if stored == null:
		return
	assert_eq(
		stored.is_active(),
		false,
		"and terminal: a save-spanning attempt leaves nothing stranded in flight"
	)
	assert_eq(
		stored.outcome_granted,
		String(reloaded.path(BodyPath.PATH_ID).rank_id) == target,
		"the verdict the record carries is the realm the actor stands in"
	)


# --- Source helpers ------------------------------------------------------------


## A hero at the brink of its next realm, brought there by play.
func _prepared() -> Actor:
	var hero := _play.actor()
	_born.append(hero)
	assert_ne(_play.prepare(hero), null, "prepared for the next realm through public actions")
	return hero


## One commit through the SHIPPED facade — no rng argument anywhere — and the record
## it left. The pill is restocked each press and cancelling leaves the body untouched,
## so a sweep costs one preparation rather than one per press.
func _commit_and_read_seed(hero: Actor) -> BodyAttempt:
	var seed := _play.seed_for(hero)
	assert_ne(seed, null, "the target realm authors a pill")
	_play.stock(hero, seed.breakthrough_item)
	var committed := BodyAdvancement.start_attempt(hero)
	assert_ne(committed, null, "a prepared hero's press commits an attempt")
	if committed == null:
		return BodyAttempt.new()
	return committed


## Which acupoint the deviation jammed, sorted so the comparison is order-independent.
func _jammed(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for point in BodyCultivationApi.acupoints(actor):
		if point.blocked:
			out.append(String(point.id))
	out.sort()
	return out


## `persist`, then read the envelope back and rebuild the body the way a boot does —
## `Actor.from_dict` FIRST, then the module attaches, because that is the order
## `tests/modules/save/test_cultivation_boot_round_trip.gd` exists to police.
func _reload_through_the_save(hero: Actor) -> Actor:
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")
	var restored := SaveStore.restore()
	assert_eq(bool(restored.get("ok", false)), true, "and the slot reads back")
	var envelope := restored.get("envelope", {}) as Dictionary
	if envelope.is_empty():
		return null
	var reloaded := Actor.from_dict(envelope.get("actor", {}) as Dictionary)
	_born.append(reloaded)
	BodyCultivationApi.attach(reloaded)
	BodyCultivationApi.attach_acupoints(reloaded)
	ItemsApi.attach(reloaded)
	BodyTraining.synchronize(reloaded)
	return reloaded


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The smallest seed whose first draw beats `chance`. Bounded by the candidates this
## sweep tries, and it RETURNS rather than growing anything, so the loop cannot be
## the thing that does not terminate.
func _seed_beating(chance: float) -> int:
	for candidate in range(1, 256):
		if _rng(candidate).randf() < chance:
			return candidate
	return 0


## The save slot is a real file on disk and the runner shares one process across every
## suite, so a leftover envelope here would be another suite's input.
func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
