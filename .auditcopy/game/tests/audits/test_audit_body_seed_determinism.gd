extends TestCase

## AUDIT (read-only measurement). Where the shipped body breakthrough roll lands —
## and, after DEF-0250, where it must NOT land.
##
## ADR 0187 recorded DEF-0250: `begin_breakthrough` passed a null rng, so
## `BodyAdvancement._start` wrote `rng_state = 0`, and `resolve_attempt` replayed a
## generator seeded 0. The facade took no generator, so EVERY body breakthrough in play
## rolled that one fixed draw.
##
## MEASURED 2026-10-04: the draw is 0.202272, and the lowest authored `chance_base` on
## the ladder is 0.2580 while the highest is 0.4900. `_chance` only ever RAISES chance
## above `chance_base`, so 0.202272 sits below EVERY realm's band and
## `randf() >= chance` was false for every realm at every quality.
##
## **Read the direction before reading the conclusion.** `resolve_attempt` deviates
## when the roll is at or above the chance, so the shipped defect was not that
## attempts failed — it was that they COULD NOT fail. Every body breakthrough was a
## certain success, the deviation and recovery system was unreachable in production,
## and 30 seeds' worth of authored risk was decorative. `test_body_attempt_survives_
## the_save.gd` was green through all of it because it asserted only invariants that
## hold "whichever way the roll fell", and there was only ever one way it fell.
##
## This file pinned that measurement, which is why it went red when DEF-0250 was fixed.
## It now pins the same measurement from the other side: seed 0 still wins every realm,
## which is why a commit can never store one, and every seed a commit may actually draw
## lands on both sides of every realm's band. No actor is built, so nothing to free.

## Seeds swept per realm. All 128 on the wrong side is bounded by the widest authored
## band: 0.8500^128 ~= 1e-9 at the high ceiling, 0.7420^128 ~= 2e-16 at the low floor.
const SEED_SWEEP := 128


func setup() -> void:
	expect_assertions(2)


## The measurement, unchanged and still true — with the direction spelled out, which is
## the half the old version got backwards. If a future build authors a `chance_base`
## below 0.202272, this goes red and the guard in `BodyAttemptRoll` stops being
## necessary rather than being wrong.
func test_the_excluded_seed_wins_every_realm_on_the_ladder() -> void:
	var draw := BodyAttemptRoll.replay(BodyAttemptRoll.MIN_SEED - 1).randf()
	var lowest := 1.0
	var won := 0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		lowest = minf(lowest, seed.chance_base)
		if draw < seed.chance_base:
			won += 1
	assert_almost_eq(draw, 0.202272, "seed 0 still draws the number DEF-0250 measured", 1e-6)
	assert_eq(
		won,
		30,
		(
			(
				"and still wins every realm: lowest chance_base %.4f is ABOVE it, so `randf() >= "
				+ "chance` never fired and no attempt could ever deviate"
			)
			% lowest
		)
	)


## The fix, in the shape the old assertion had: the seeds a commit DRAWS must land on
## both sides of every realm's band. A sweep over the seed space rather than over
## trials, so this is the same answer on every run.
func test_every_seed_a_commit_can_draw_lands_on_both_sides_of_every_band() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var beaten := 0
		for candidate in SEED_SWEEP:
			if BodyAttemptRoll.replay(candidate + 1).randf() < seed.chance_base:
				beaten += 1
		assert_eq(
			beaten > 0 and beaten < SEED_SWEEP,
			true,
			(
				"%s: %d of %d seeds beat chance_base %.4f, so it is winnable and losable"
				% [realm.id, beaten, SEED_SWEEP, seed.chance_base]
			)
		)
