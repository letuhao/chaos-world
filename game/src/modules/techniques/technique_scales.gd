class_name TechniqueScales
extends RefCounted

## A technique's bounded ladders and multipliers (ADR 0055).
##
## Three numbers live here and nowhere else, because the failure mode this file
## exists to prevent is two files each restating a curve.
##
## `magnitude_at` is a third per-realm table, deliberate alongside the other two
## (see AGENTS.md): it is neither an actor's strength (`realm_power_table.tres`,
## 1.0 -> 551x) nor a relative item upgrade
## (`item_magnitude_scale.json`, 1.0 -> 3.9x). A technique is a bonus riding on
## top of both, so it sits two orders of magnitude below the actor table.

## The geometric magnitude step, equal to qi's own measured per-realm work-budget
## floor (29/28 = 1.035714). Geometric, not linear: a constant ratio is what
## satisfies the floor everywhere once it satisfies it at the deep end.
const TECHNIQUE_STEP := 1.035714

## Per-mastery-rung multipliers. Compounding, so rung `n` is `step^n`. A rung
## never halves output: rung 4 power is 1.749 and its cooldown is 0.849, both well
## clear of 0.5, so a deep rung is never a trap.
const POWER_STEP := 1.15
const QI_COST_STEP := 0.94
const COOLDOWN_STEP := 0.96

## Learning cost, per path and never shared (like `RATE_STEP`). `1.03` sits just
## under the magnitude step, so study is always cheaper than a breakthrough and
## never runs ahead of one.
const LEARN_STEP := 1.03
const LEARN_BASE := 100.0

## Grade multiplies the ladder by how wide a band it spans; it never multiplies
## the effect. Grade is a floor, not a scale.
const MAG_GRADE := {
	ItemGrade.MORTAL: 1.0,
	ItemGrade.SPIRIT: 1.6,
	ItemGrade.EARTH: 2.2,
	ItemGrade.HEAVEN: 3.2,
	ItemGrade.IMMORTAL: 4.5,
	ItemGrade.DIVINE: 6.5,
}

## The number of rungs ADR 0055 defines. A def may author a lower `mastery_rungs`,
## never a sixth: the multipliers are constants, not data.
const MAX_RUNGS := 5


## Magnitude multiplier at realm ordinal `index` (0 at Qi Refining), R1 at 1.0.
## Span `TECHNIQUE_STEP^29 = 2.7667`; per tier `^9 = 1.3714`.
static func magnitude_at(index: int) -> float:
	if index <= 0:
		return 1.0
	return pow(TECHNIQUE_STEP, float(index))


## Grade multiplier, defaulting to mortal so malformed content degrades to the
## cheapest band rather than producing an unbudgeted technique.
static func grade_factor(grade: StringName) -> float:
	return float(MAG_GRADE.get(grade, MAG_GRADE[ItemGrade.MORTAL]))


## Price of learning `grade` at realm ordinal `index`: `LEARN_BASE * LEARN_STEP^index
## * grade`. R1 mortal is 100; R30 divine is 1531.77.
static func learn_price(grade: StringName, index: int) -> float:
	if index <= 0:
		return LEARN_BASE * grade_factor(grade)
	return LEARN_BASE * pow(LEARN_STEP, float(index)) * grade_factor(grade)


## Every multiplier at mastery `rung`, clamped to the authored rung count and to
## `MAX_RUNGS`. `{power, qi_cost, cooldown, qi_throughput}` — throughput is the
## ratio of the two, which is the number a player actually feels.
static func multipliers_at(rung: int, rung_count: int = MAX_RUNGS) -> Dictionary:
	var r := clampi(rung, 0, mini(rung_count, MAX_RUNGS))
	var power := pow(POWER_STEP, float(r))
	var qi_cost := pow(QI_COST_STEP, float(r))
	return {
		"power": power,
		"qi_cost": qi_cost,
		"cooldown": pow(COOLDOWN_STEP, float(r)),
		"qi_throughput": power / qi_cost,
	}


## A rung clamped into the range this technique may actually reach. Clamping here
## rather than trusting a save means a def lowered to three rungs cannot leave a
## fourth rung's multipliers in the stat stack.
static func rung_for(entry_rung: int, rung_count: int) -> int:
	return clampi(entry_rung, 0, maxi(0, mini(rung_count, MAX_RUNGS)))
