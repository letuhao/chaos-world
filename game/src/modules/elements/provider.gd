class_name ElementProvider
extends StatProvider

## Contributes per-element derived stats: element_power_<e> and
## element_defense_<e> for every element in the rules (ADR 0004, ADR 0200), plus the
## OMNI pair (`element_power_` / `element_defense_`) an elementless attack reads —
## ADR 0004's "pure qi is a real omni channel".
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

## ## ADR 0215: the per-element crit pair's four coefficients, and why they are CONSTANTS
## ## here and not fields on a tuning resource
##
## A balance pass would legitimately want to move all four. They are still constants
## because this provider has no tuning resource of its own to move them to and
## `combat_engine` may not hold an `elements` edge (ADR 0087's precedent: the per-element
## ids are named as STRING PREFIXES on `CombatTuning` precisely so that module needs no
## edge). Inventing one would be a second balance surface, which is the worse outcome.
## The honest statement is that these four are ELEMENT coefficients — they price what
## affinity and mastery mean for a weapon — and the shared contest they feed reads
## `element_crit_prefix` off `CombatTuning` like every other per-element prefix.
##
## ## The numbers, and the one that is load-bearing
##
## `CRIT_BASE` is `0.05`, the same constant core's `Stat.CRIT_CHANCE` carries, and it is
## what makes an actor with no affinity and no mastery still crit 5% of the time with an
## untrained element. It is a BASELINE, not a ceiling: nothing here is `minf`-ed, and
## that is the whole ADR consequence — a cap on a half of a ratio is the ADR 0200 defect
## in a second uniform.
##
## `CRIT_RESIST_WILL_STEP` is the only term a body with no elemental affinity can move on
## the defence side, which is what makes a tank's answer to crit available without the
## tank having an element at all.

## What an actor with no affinity and no mastery crits an element at.
const CRIT_BASE := 0.05
## What one point of that element's AFFINITY is worth on the offence half.
const CRIT_AFFINITY_STEP := 0.004
## What one point of that element's MASTERY is worth on the offence half.
const CRIT_MASTERY_STEP := 0.002
## What an actor with no affinity and no will resists an element's crit at.
const CRIT_RESIST_BASE := 0.05
## What one point of that element's AFFINITY is worth on the defence half. Half the
## offence step, so an affinity build is a slightly BETTER critter than a better evader
## of the same number — a tilt a balance pass can flip by editing two constants.
const CRIT_RESIST_AFFINITY_STEP := 0.002
## What one point of `will` is worth on the defence half. The only defence term a
## non-elemental build can move.
const CRIT_RESIST_WILL_STEP := 0.003

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
		out[ElementStats.defense_id(element)] = maxf(0.0, affinity * 0.5 + will * 0.2)
		# ADR 0215. The per-element CRIT pair, published for the SAME set of elements
		# the power/defense families are published for and generated from
		# `ElementStats.all_ids()` rather than written out. Both halves ship together:
		# `AGENTS.md`'s yin-yang rule makes `element_crit_<e>` without
		# `element_crit_resist_<e>` a defect, so there is no point at which one exists
		# and the other does not.
		#
		# Both are UNBOUNDED MAGNITUDES. A cap here is the ADR 0200 defect in a second
		# uniform — the defender's ceiling loses by construction as the ladder rises —
		# and the contest that reads them is a ratio, so neither half needs one.
		out[ElementStats.crit_id(element)] = maxf(
			0.0, CRIT_BASE + affinity * CRIT_AFFINITY_STEP + mastery * CRIT_MASTERY_STEP
		)
		out[ElementStats.crit_resist_id(element)] = maxf(
			0.0,
			CRIT_RESIST_BASE + affinity * CRIT_RESIST_AFFINITY_STEP + will * CRIT_RESIST_WILL_STEP
		)
	# The omni pair, on the SAME rule as every element above rather than as a
	# special case. `ElementStats.all_ids()` carries [constant ElementStats.OMNI], and a
	# special case is the first thing a fourth prefix would be written next to.
	var omni_affinity := _affinity_sum(context, _rules.ids())
	var omni_mastery := 0.0
	for element in _rules.ids():
		omni_mastery += maxf(0.0, context.value(ElementStats.mastery_id(element)))
	out[ElementStats.crit_id(ElementStats.OMNI)] = maxf(
		0.0, CRIT_BASE + omni_affinity * CRIT_AFFINITY_STEP + omni_mastery * CRIT_MASTERY_STEP
	)
	out[ElementStats.crit_resist_id(ElementStats.OMNI)] = maxf(
		0.0,
		CRIT_RESIST_BASE + omni_affinity * CRIT_RESIST_AFFINITY_STEP + will * CRIT_RESIST_WILL_STEP
	)
	# ADR 0004's "pure qi is a real omni channel": the MAGNITUDE pair an ELEMENTLESS
	# attack reads, on the same rule the per-element pair above uses with `affinity`
	# read as the SUM and `mastery` as the SUM. A mono-affinity body with all its
	# mastery in that element reads its own element's power exactly, and breadth pays
	# linearly on both halves -- the trade pure qi makes is no matchup swing (always
	# NEUTRAL) for no matchup upside. The mastery rate is `_mastery_rate(OMNI)`, which
	# reads as tier 1 because the omni channel is not an element and has no tier to tax.
	out[ElementStats.power_id(ElementStats.OMNI)] = maxf(
		0.0, omni_affinity * (1.0 + _mastery_rate(ElementStats.OMNI) * omni_mastery)
	)
	out[ElementStats.defense_id(ElementStats.OMNI)] = maxf(0.0, omni_affinity * 0.5 + will * 0.2)
	return out


## Every element's affinity summed, which is what the OMNI channel's offense half reads.
## A separate function because the sum is only meaningful for the omni id: a per-element
## id must read its OWN affinity or a trained fire build would crit as though it were
## trained in all ten.
func _affinity_sum(context: StatContext, elements: Array) -> float:
	var total := 0.0
	for element in elements:
		total += maxf(0.0, context.affinity(element))
	return total


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
