class_name BodyAttemptRoll
extends RefCounted

## WHERE a body breakthrough's randomness enters, and the one number that carries it.
##
## Split out of `BodyAdvancement` for the reason `BodyDeviationJam` was split out for:
## "where the roll comes from" and "run the attempt lifecycle" are two reasons to
## change. The seed is decided once, at commit, written into the record, and every
## later draw is replayed from it.
##
## ## WHY THE SEED IS DRAWN AT COMMIT AND REPLAYED
##
## An attempt is committed and then resolved (ADR 0187), and it survives the save
## envelope. So the roll has to be reproducible across a reload, or a resolve after a
## reload disagrees with the attempt the player already paid for — which is the whole
## reason the record exists. ONE seed in the record is what buys that: the roll, and
## the acupoint a deviation jams, both come off a generator rebuilt from it.
##
## Drawing at RESOLVE time from the actor's live rng is one line shorter and is the
## wrong shape. The actor that comes back from a save has no live rng, so the outcome
## would be re-rolled rather than resumed, and a player could quit to change the
## result of an attempt already paid for. `resolve_attempt` therefore takes no rng at
## all: a second door for randomness into a durable decision is the defect, not the
## fix.
##
## ## WHY THE SEED IS NEVER 0
##
## MEASURED 2026-10-04: a generator seeded 0 draws 0.202272 first. The lowest
## `chance_base` authored anywhere on the 30-realm body ladder is 0.2580 and the
## highest is 0.4900, and `_chance` only ever RAISES chance above `chance_base`, so
## 0.202272 sits below EVERY realm's band. `resolve_attempt` deviates when the roll is
## at or above the chance, so seed 0 did not lose every attempt — it WON every one.
## Every shipped body breakthrough was a certain success, the deviation and recovery
## system was unreachable in production, and 30 seeds' worth of authored risk was
## decorative. That is what a constant seed buys, and it is why the seed cannot be a
## constant, a default, or a value derived from something the record already knows.
##
## `seed_for` excludes 0 by construction rather than by re-drawing: re-drawing until
## the draw is nonzero is an unbounded retry for a condition that holds once in 2^31,
## and it is the shape AGENTS.md forbids. The uniform draw makes every attempt an
## independent trial, so `P(win) = chance` on every realm — strictly above 0 because
## every realm authors a positive `chance_base`, and strictly below 1 because the
## highest authored `chance_cap` on the ladder is 0.8500.
##
## ## WHAT A CALL-SUPPLIED GENERATOR MEANS
##
## `rng` is an optional SEED SOURCE, not the generator the roll is taken from. Its
## `seed` is stored verbatim, so `_rng(n)` makes an attempt deterministic and a test
## can pick the outcome by probing `RandomNumberGenerator.new().seed = n; randf()` —
## the idiom every suite in this module already uses. It is NOT a stream: an attempt
## stores the seed it was given, so a caller that loops over one generator replays the
## same roll forever and must re-seed between attempts.

## The smallest seed a commit may store. Seed 0 is not a seed here; see above.
const MIN_SEED := 1

## Folds a signed 32-bit `randi()` into `[0, 2^31 - 2]`, so the `+ MIN_SEED` lands on
## `[1, 2^31 - 1]`: uniform, and never the unusable seed. Bitwise rather than `absi`
## because `absi(INT32_MIN)` has no positive answer.
const SEED_MASK := 0x7ffffffe


## The seed a commit stores, drawn once and never again.
##
## With a generator, that generator's `seed` — so a caller can choose the outcome and
## the choice survives the save. Without one, the engine's own global generator, which
## is the same source `combat/damage.gd`, `combat/duel_hit.gd` and
## `core/tribulation_endurance.gd` roll from when handed no rng.
static func seed_for(rng: RandomNumberGenerator = null) -> int:
	if rng != null:
		return maxi(rng.seed, MIN_SEED)
	return (randi() & SEED_MASK) + MIN_SEED


## The generator a committed attempt resolves against, built from the record's seed
## and from nothing else. Every draw after the first — the roll, and the acupoint a
## deviation jams — comes off this one generator, so a resolve after a reload lands on
## the same body as a resolve without one.
##
## A stored 0 is replayed as 0 rather than redrawn: that record was committed by a
## build that rolled 0, and re-rolling it would break the one property this file exists
## for. `seed_for` is what guarantees no NEW record can carry one — and for the ones
## that can, "reproduces the certain success that was committed" is still a resolution.
static func replay(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator
