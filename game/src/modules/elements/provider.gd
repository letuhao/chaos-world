class_name ElementProvider
extends StatProvider

## Contributes per-element derived stats: element_power_<e> and
## element_resistance_<e> for every element in the rules (ADR 0004).
## element_mastery_<e> is a base attribute owned by core, not passed through here.
##
## ## The per-tier mastery divisor, and why it lives HERE
##
## Measured over the shipped 10-element graph, `ElementDefaults.advanced()` gives
## `lightning` and `ice` a row mean of **1.100000**, `wind`/`light`/`dark` **1.050000**,
## and every tier-1 row **0.875..0.975** (the tier-1-vs-tier-1 mean is exactly
## 0.950000; grand mean 0.997500). Every advanced element's row sits ABOVE every
## tier-1 row: an advanced element is a strictly better attack than a basic one with
## the same numbers. "Tier 2 has two overcomes" is true of `lightning`/`ice`/`wind` and
## FALSE of `light`/`dark`, which have one each -- so the dominance is a property of
## the shipped data, not of a rule.
##
## The fix taxes the MASTERY term only:
## `element_power_<e> = affinity * (1 + mastery * 0.1 / (1 + (tier - 1) * TIER_MASTERY_STEP))`.
## Tier 1's divisor is exactly `1.0` -- `(tier - 1)` is `0` -- so **tier 1 is
## bit-for-bit unchanged** and `tests/modules/elements/test_element_provider.gd::
## test_mastery_scales_power` needs no edit. The tax falls only on the dominant tier.
##
## ## The tax divides the MASTERY term, never the affinity
##
## That is what keeps an actor's `element_power_<e>` rising MONOTONICALLY with
## mastery at every tier: the divisor moves where mastery saturates, never whether it
## pays. An untrained element (affinity 0) still reads 0.0 at every tier, which is the
## qi mechanism's "untrained element" case, and a trainer with no mastery pays no tax
## at all -- the tax is on the marginal return of mastery in a dominant element, which
## is where the excess is.
##
## ## A missing or malformed `ElementDef` reads as TIER 1
##
## `rules.element(id)` returning null must not divide by a tier-1 tax on an advanced
## element, nor throw on a null. It reads as tier 1 -- divisor 1.0, no tax -- which is
## the same fail-safe as every other null read here: the shape nobody authored.

## The extra mastery tax per tier above the first, on the MASTERY term only.
##
## At `0.10`, tier 2's mastery coefficient is `0.1 / 1.1 = 0.0909...` against tier 1's
## `0.1`, a 9.1% reduction on the mastery term -- which lands tier 2's 1.100000 row mean
## almost exactly on tier 1's 0.950000 without touching a single `ElementDef`. Tier 3
## divides by 1.2 for the same reason: the tax compounds with the tier a player had to
## reach, and `ElementMastery.MAX_ELEMENT_TIER` is 3.
const TIER_MASTERY_STEP := 0.10

var _rules: ElementRules


func _init(rules: ElementRules) -> void:
	_rules = rules


func contribute(context: StatContext) -> Dictionary:
	var will := context.value(Stat.WILL)
	var out := {}
	for element in _rules.ids():
		var affinity := context.affinity(element)
		# Read mastery post-modifier so an item modifier on it flows into power
		# exactly once, with no stale input and no double application (ADR 0026).
		var mastery := context.value(ElementStats.mastery_id(element))
		out[ElementStats.power_id(element)] = maxf(
			0.0, affinity * (1.0 + _mastery_rate(element) * mastery)
		)
		out[ElementStats.resistance_id(element)] = maxf(0.0, affinity * 0.5 + will * 0.2)
	return out


## `0.1 / (1 + (tier - 1) * TIER_MASTERY_STEP)`: the mastery coefficient this element's
## tier is allowed to pay.
##
## Exactly `0.1` at tier 1 -- the number `ElementProvider` has always contributed -- and
## strictly less above it. A null def, a tier below 1 and a non-finite mastery all
## resolve to tier 1, so there is no path through this function that returns a
## non-finite coefficient and poisons `element_power_<e>` for every actor carrying it.
func _mastery_rate(element: StringName) -> float:
	var entry := _rules.element(element)
	if entry == null:
		return 0.1
	var tier := maxi(1, entry.tier)
	var divisor := 1.0 + float(tier - 1) * TIER_MASTERY_STEP
	if not is_finite(divisor) or divisor <= 0.0:
		return 0.1
	return 0.1 / divisor
