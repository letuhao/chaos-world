class_name MindAttemptRoll
extends RefCounted

## WHERE a mind breakthrough's randomness enters, and the one number that carries it.
##
## Split out of `MindAdvancement` for the reason `BodyDeviationJam` was split out for:
## "where the roll comes from" and "run the attempt lifecycle" are two reasons to
## change. The seed is decided once, at commit, written into the record, and every
## later draw is replayed from it.
##
## This is the mind instance of the policy ADR 0191 decided for the body, applied
## unchanged: one seed, drawn at commit, and a resolve that takes NO generator.
## `BodyAttemptRoll` is the same shape on the same arithmetic — see
## `test_mind_attempt_roll.gd`, which pins the two to each other so the pair cannot
## drift apart silently.
##
## ## WHY IT IS NOT IN `core/`
##
## The arithmetic here is a property of the engine's `RandomNumberGenerator`, not a
## balance number: `MIN_SEED` is 1 because 1 is the first usable seed, and
## `SEED_MASK` folds a signed 32-bit draw into the positive range. Neither is
## tuned, so there is nothing in them that can be retuned out of step the way
## `RealmRate.RATE_STEP` can (ADR 0116) — and that is the only real argument for
## giving them one home.
##
## What the file actually carries is a LIFECYCLE RULE — "commit draws, the record is
## the only door, resolve replays" — and the rule is enforced by `resolve_attempt`
## reading `committed.rng_state`, which is one call in one file. Promoted to `core/`
## the arithmetic becomes reachable from every module while the rule stays
## unenforced everywhere, so `AttemptRoll.seed_for()` at RESOLVE time would be a
## perfectly ordinary call that silently undoes the whole design. `core/` here is
## primitives (`actor.gd`, `realm_rate.gd`, `tribulation_endurance.gd`), and a rule
## is not a primitive.
##
## Collapsing the two into one `core/` class is the right END state and is a
## separate change: it needs an ADR, and it needs `body_cultivation` edited in the
## same commit, because until body's copy is deleted the repo would hold two live
## implementations of one policy and a reader would have no way to tell which is
## canonical. Doing half of it is worse than doing either half properly.
##
## ## WHY THE SEED IS DRAWN AT COMMIT AND REPLAYED
##
## An attempt is committed and then resolved (ADR 0187), and it survives the save
## envelope. So the roll has to be reproducible across a reload, or a resolve after
## a reload disagrees with the attempt the player already paid for — which is the
## whole reason the record exists. ONE seed in the record is what buys that: the
## roll, and the meridian a deviation burns, both come off a generator rebuilt from
## it.
##
## Drawing at RESOLVE time from the actor's live rng is one line shorter and is the
## wrong shape. The actor that comes back from a save has no live rng, so the
## outcome would be re-rolled rather than resumed, and a player could quit to change
## the result of an attempt already paid for. `MindAdvancement.resolve_attempt`
## therefore takes no rng at all: a second door for randomness into a durable
## decision is the defect, not the fix.
##
## ## WHY THE SEED IS NEVER 0
##
## MEASURED 2026-10-04: a generator seeded 0 draws 0.202272 first. The mind ladder's
## chance is not authored per realm — `MindAdvancement._chance` derives it as
## `clamp(MIN_CHANCE + sea.clarity * CLARITY_TO_CHANCE, MIN_CHANCE, MAX_CHANCE)`, so
## the band is `[0.05, 0.95]`. But `start` REFUSES unless
## `sea.clarity >= source_seed.clarity_required`, and the lowest `clarity_required`
## authored on all 30 mind seeds is 0.40 (`qi_refining.tres:23`). So the lowest
## chance any committed mind attempt can carry is `0.05 + 0.40 * 0.5` = **0.25**,
## and 0.202272 sits below it.
##
## `resolve_attempt` deviates when the roll is at or above the chance, so seed 0 did
## not lose every attempt — it WON every one. Every shipped mind breakthrough was a
## certain success: the mental-deviation and recovery leg of the program was
## unreachable in production, and 30 seeds' worth of authored preparation risk was
## decorative. That is what a constant seed buys, and it is why the seed cannot be a
## constant, a default, or a value derived from something the record already knows.
##
## Mind's margin is THINNER than body's — 0.0477 against body's 0.0557 — and it is
## thinner only because the gate raises the floor, not because the roll is safer.
## The `_chance` fallback at resolve time (a record written before this fix, whose
## `preparation` carries no `chance`) reads the CURRENT clarity instead of the
## committed one, and can fall to the 0.05 floor, where 0.202272 would deviate on
## every realm. So seed 0 was a guaranteed SUCCESS through the shipped path and a
## guaranteed FAILURE through that fallback — which is exactly why one constant
## seed is not a weakened roll but an absent one, whichever way it points.
##
## `seed_for` excludes 0 by construction rather than by re-drawing: re-drawing until
## the draw is nonzero is an unbounded retry for a condition that holds once in 2^31,
## and it is the shape AGENTS.md forbids. The uniform draw makes every attempt an
## independent trial, so `P(win) = chance` on every realm — strictly above 0 because
## the floor is 0.25 for every realm a commit can reach, and strictly below 1
## because `MAX_CHANCE` is 0.95 and the highest authored `clarity_required` is 0.83
## (`primordial_origin.tres:23`), which puts the ceiling at `0.05 + 0.83 * 0.5` =
## 0.465 for the deepest realm authored.
##
## ## WHAT A CALL-SUPPLIED GENERATOR MEANS
##
## `rng` is an optional SEED SOURCE, not the generator the roll is taken from. Its
## `seed` is stored verbatim, so `_rng(n)` makes an attempt deterministic and a test
## can pick the outcome by probing `RandomNumberGenerator.new().seed = n; randf()` —
## the idiom every suite in this module already uses. It is NOT a stream: an attempt
## stores the seed it was given, so a caller that loops over one generator replays
## the same roll forever and must re-seed between attempts.

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
## and from nothing else. Every draw after the first — the roll, and the meridian a
## deviation burns — comes off this one generator, so a resolve after a reload lands
## on the same sea as a resolve without one.
##
## A stored 0 is replayed as 0 rather than redrawn: that record was committed by a
## build that rolled 0, and re-rolling it would break the one property this file
## exists for. `seed_for` is what guarantees no NEW record can carry one — and for
## the ones that can, "reproduces the certain success that was committed" is still a
## resolution.
static func replay(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator
