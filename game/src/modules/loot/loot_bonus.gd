class_name LootBonus
extends RefCounted

## The `loot_bonus` option's real consumer: a bounded policy on three separate
## axes, so one number can never turn into an unbounded drop.
##
## ## Where the number comes from (and why it is not double counted)
##
## `ActorStats` already composes `Stat.LOOT_BONUS` once, through the single
## application stage every modifier goes through (ADR 0026):
##
##     loot_bonus = (fortune * 0.01 + flat) * (1 + percent)
##
## `fortune * 0.01` is core's derivation, and the `core_loot_bonus` master option
## is a PERCENT modifier on `loot_bonus`, so an equipped or rolled item already
## inflated that derived value inside `ActorStats`. This policy therefore reads
## **only the final derived rate**: it never re-reads `Stat.FORTUNE` and never
## inspects item options, so fortune's derivation and an item's affix are each
## counted exactly once, here and nowhere else.
##
## ## The bounded policy
##
##     chance       += min(loot_bonus * 0.05, 0.25)
##     draw count   += min(floor(loot_bonus * 1.0), 2)
##     quality tier += min(floor(loot_bonus / 2.0), 1)
##
## `chance` only ever shifts an *independent* Bernoulli roll, `count` only ever
## adds *weighted draws* (never a guaranteed entry, never an independent roll),
## and `quality` only ever promotes a drop's rarity context by at most one tier.
## The input itself is clamped to [constant MAX_INPUT] first, so the three caps
## are the only thing standing between a stat and a runaway table — there is no
## fourth path by which the bonus can act.

## Ceiling on the input rate. Above this the axes are already at their caps, so
## clamping here only makes that explicit.
const MAX_INPUT := 4.0
## Percentage points added to an independent roll per 1.0 of `loot_bonus`.
const CHANCE_PER_UNIT := 0.05
const MAX_CHANCE_BONUS := 0.25
## Extra weighted draws per 1.0 of `loot_bonus`.
const COUNT_PER_UNIT := 1.0
const MAX_EXTRA_COUNT := 2
## One rarity tier of promotion per this much `loot_bonus`.
const QUALITY_UNIT := 2.0
const MAX_QUALITY_STEPS := 1


## The actor's final composed `loot_bonus` rate, clamped to the policy's input
## window. Read-only: nothing here mutates the actor.
static func rate_for(actor: Actor) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return clampf(actor.stats.derived(Stat.LOOT_BONUS), 0.0, MAX_INPUT)


## The three bounded axes for an already-clamped rate. Keys: `chance` (float),
## `count` (int), `quality_steps` (int).
static func axes(rate: float) -> Dictionary:
	var bounded := clampf(rate, 0.0, MAX_INPUT)
	return {
		"chance": minf(bounded * CHANCE_PER_UNIT, MAX_CHANCE_BONUS),
		"count": mini(int(floor(bounded * COUNT_PER_UNIT)), MAX_EXTRA_COUNT),
		"quality_steps": mini(int(floor(bounded / QUALITY_UNIT)), MAX_QUALITY_STEPS),
	}


## The axes for an actor, in one read of the derived stat.
static func axes_for(actor: Actor) -> Dictionary:
	return axes(rate_for(actor))


## The caps, published so a reader (or a test) never has to restate the policy.
static func limits() -> Dictionary:
	return {
		"max_input": MAX_INPUT,
		"chance_per_unit": CHANCE_PER_UNIT,
		"max_chance_bonus": MAX_CHANCE_BONUS,
		"count_per_unit": COUNT_PER_UNIT,
		"max_extra_count": MAX_EXTRA_COUNT,
		"quality_unit": QUALITY_UNIT,
		"max_quality_steps": MAX_QUALITY_STEPS,
	}
