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
## The fix taxes the MASTERY term only, and BL-0938's bond bounds how far that term can
## run at all:
## `element_power_<e> = affinity * (1 + POWER_CEILING * saturation(mastery) /
## (1 + (tier - 1) * TIER_MASTERY_STEP))`.
## Tier 1's divisor is exactly `1.0` -- `(tier - 1)` is `0` -- so the tax still falls
## only on the dominant tier, and every tier's mastery term is bounded by
## `affinity * (1 + POWER_CEILING)` at the asymptote instead of growing forever.
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
## At `0.10`, tier 2's mastery ceiling is `POWER_CEILING / 1.1` against tier 1's
## `POWER_CEILING` -- the same 9.1% relative cut the old linear term carried, which lands
## tier 2's 1.100000 row mean almost exactly on tier 1's 0.950000 without touching a
## single `ElementDef`. Tier 3 divides by 1.2 for the same reason: the tax compounds with
## the tier a player had to reach, and `ElementMastery.MAX_ELEMENT_TIER` is 3.
const TIER_MASTERY_STEP := 0.10

## What FULL mastery in an element is worth on the offence half, through BL-0938's
## saturating curve: at the asymptote `element_power_<e>` is the affinity times
## `1 + POWER_CEILING` (the owner's x4 ruling -- elemental resistance and weakness
## exploitation become the pivot), and a tier's divisor taxes that ceiling exactly as it
## taxed the old linear term. This is the number an authored resistance is measured
## against, and the reason the mastery channel can no longer out-run the realm ladder.
const POWER_CEILING := 3.0

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
## What FULL mastery is worth on the crit offence half, through the SAME saturating curve
## the power half reads (BL-0938: one curve shared by power and crit). Paired to the
## defence side's reachable span: the only lever a non-elemental defender can move is
## `will` (`CRIT_RESIST_WILL_STEP`, ~0.165 at the authored top), so a ceiling orders of
## magnitude above it would make the crit unanswerable -- a second free ladder wearing a
## contest's name.
const CRIT_MASTERY_CEILING := 0.6
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
			0.0,
			(
				affinity
				* (
					1.0
					+ POWER_CEILING * ElementMastery.saturation(mastery) / _tier_divisor(element)
				)
			)
		)
		out[ElementStats.defense_id(element)] = maxf(0.0, affinity * 0.5 + will * 0.2)
		# ADR 0215. The per-element CRIT pair, published for the SAME set of elements
		# the power/defense families are published for and generated from
		# `ElementStats.all_ids()` rather than written out. Both halves ship together:
		# `AGENTS.md`'s yin-yang rule makes `element_crit_<e>` without
		# `element_crit_resist_<e>` a defect, so there is no point at which one exists
		# and the other does not.
		#
		# Both are MAGNITUDES the contest divides, so neither AFFINITY term needs a cap --
		# but the mastery term rides BL-0938's saturating curve, because THAT was the
		# unbounded faucet, and its ceiling is paired to the defender's `will` span above.
		out[ElementStats.crit_id(element)] = maxf(
			0.0,
			(
				CRIT_BASE
				+ affinity * CRIT_AFFINITY_STEP
				+ CRIT_MASTERY_CEILING * ElementMastery.saturation(mastery)
			)
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
		0.0,
		(
			CRIT_BASE
			+ omni_affinity * CRIT_AFFINITY_STEP
			+ CRIT_MASTERY_CEILING * ElementMastery.saturation(omni_mastery)
		)
	)
	out[ElementStats.crit_resist_id(ElementStats.OMNI)] = maxf(
		0.0,
		CRIT_RESIST_BASE + omni_affinity * CRIT_RESIST_AFFINITY_STEP + will * CRIT_RESIST_WILL_STEP
	)
	# ADR 0004's "pure qi is a real omni channel": the MAGNITUDE pair an ELEMENTLESS
	# attack reads, on the same rule the per-element pair above uses with `affinity`
	# read as the SUM and `mastery` as the SUM. A mono-affinity body with all its
	# mastery in a TIER-1 element reads its own element's power exactly, and breadth pays
	# through the same saturating curve -- the trade pure qi makes is no matchup swing
	# (always NEUTRAL) for no matchup upside. The mastery term is the tier-1 ceiling
	# (`POWER_CEILING` in full), because the omni channel is not an element and has no
	# tier to tax.
	out[ElementStats.power_id(ElementStats.OMNI)] = maxf(
		0.0, omni_affinity * (1.0 + POWER_CEILING * ElementMastery.saturation(omni_mastery))
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


## `1 + (tier - 1) * TIER_MASTERY_STEP`: the divisor a tier's mastery CEILING is paid
## through.
##
## Exactly `1.0` at tier 1 -- so tier 1 keeps the biggest mastery term -- and strictly
## more above it. A null def, a tier below 1 and a non-finite divisor all resolve to tier
## 1, so there is no path through this function that returns a non-finite coefficient and
## poisons `element_power_<e>` for every actor carrying it.
func _tier_divisor(element: StringName) -> float:
	var entry := _rules.element(element)
	if entry == null:
		return 1.0
	var tier := maxi(1, entry.tier)
	var divisor := 1.0 + float(tier - 1) * TIER_MASTERY_STEP
	if not is_finite(divisor) or divisor <= 0.0:
		return 1.0
	return divisor
