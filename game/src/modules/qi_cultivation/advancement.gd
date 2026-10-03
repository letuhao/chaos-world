class_name QiAdvancement
extends RefCounted

## The qi breakthrough, as a thin surface over the one implementation.
##
## `QiBreakthroughTransaction` is the production entry point
## (`QiCultivationApi.attempt_breakthrough`), so it is where the gate is enforced.
## This file used to carry a SECOND, inline copy of that gate plus its own copy of
## the roll, and ADR 0036 recorded the duplication as still open. Two copies of a
## gate is how a preview reports a realm enterable while the transaction refuses
## it, so there is now one of each and this file delegates (ADR 0095).
##
## Kept as a public surface because the module's own tests and any caller holding
## this class name keep working; nothing here decides anything.


## Preview the breakthrough: structured unmet conditions, costs and the chance.
## Never consumes items, changes progression, or advances RNG.
static func preview(actor: Actor) -> Dictionary:
	return QiBreakthroughTransaction.preview(actor)


## Execute the breakthrough. Returns true on success. On failure the actor takes
## a qi deviation: lost progress, a scarred dantian, and a damaged channel.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	return QiBreakthroughTransaction.execute(actor, rng)


## Attempt to cancel a committed breakthrough. This counts as a failed attempt
## with disclosed recoverable consequences. It cannot refund/reroll into a free
## second attempt.
static func cancel_attempt(actor: Actor) -> bool:
	return QiBreakthroughTransaction.cancel(actor)


## The chance this attempt would roll. Reads the dantian and nothing else, because
## comprehension is this path's own entry gate and a gate input is a precondition
## rather than a difficulty dial (ADR 0051).
static func chance(actor: Actor) -> float:
	return QiChance.of(QiAccess.dantian(actor))
