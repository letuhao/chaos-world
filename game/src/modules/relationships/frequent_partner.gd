class_name FrequentPartner
extends RefCounted

## Frequent partner advantage calculation (ADR 0892).
##
## **Output-bounded.** Advantages multiply gains, never add flat stats. The cost is
## emotional energy divided among partners — maintaining N active relationships divides
## emotional energy by sqrt(N), so spreading attention thin yields diminishing returns.
## This prevents a strict best response (dating everyone).

const TIER_FREQUENT := 1
const TIER_CLOSE := 2
const TIER_INTIMATE := 3

const THRESHOLD_FREQUENT := 10
const THRESHOLD_CLOSE := 25
const THRESHOLD_INTIMATE := 50

const EMOTIONAL_ENERGY_BONUS := {
	TIER_FREQUENT: 0.10,
	TIER_CLOSE: 0.20,
	TIER_INTIMATE: 0.30,
}

const DC_EFFICIENCY_BONUS := {
	TIER_FREQUENT: 0.05,
	TIER_CLOSE: 0.10,
	TIER_INTIMATE: 0.15,
}


static func tier_for_interactions(total_interactions: int) -> int:
	if total_interactions >= THRESHOLD_INTIMATE:
		return TIER_INTIMATE
	if total_interactions >= THRESHOLD_CLOSE:
		return TIER_CLOSE
	if total_interactions >= THRESHOLD_FREQUENT:
		return TIER_FREQUENT
	return 0


## The advantage for a partner at `tier`. Returns emotional energy bonus and DC efficiency
## bonus as multipliers (1.0 = no bonus).
static func advantage(tier: int) -> Dictionary:
	var energy := 1.0
	var dc := 1.0
	if tier >= TIER_INTIMATE:
		energy += EMOTIONAL_ENERGY_BONUS[TIER_INTIMATE]
		dc += DC_EFFICIENCY_BONUS[TIER_INTIMATE]
	elif tier >= TIER_CLOSE:
		energy += EMOTIONAL_ENERGY_BONUS[TIER_CLOSE]
		dc += DC_EFFICIENCY_BONUS[TIER_CLOSE]
	elif tier >= TIER_FREQUENT:
		energy += EMOTIONAL_ENERGY_BONUS[TIER_FREQUENT]
		dc += DC_EFFICIENCY_BONUS[TIER_FREQUENT]
	return {"emotional_energy": energy, "dc_efficiency": dc}


## The emotional energy divisor for N active relationships. Spreading attention thin
## yields diminishing returns — this is the yin-yang counterpart to frequent partner
## advantages.
static func energy_divisor(active_relationships: int) -> float:
	if active_relationships <= 1:
		return 1.0
	return sqrt(float(active_relationships))
