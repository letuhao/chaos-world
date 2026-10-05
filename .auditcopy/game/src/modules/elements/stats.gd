class_name ElementStats
extends RefCounted

## Element ids and per-element derived-stat id helpers (ADR 0004).

# Tier 1 — 五行
const METAL := &"metal"
const WOOD := &"wood"
const WATER := &"water"
const FIRE := &"fire"
const EARTH := &"earth"

# Tier 2 — advanced
const LIGHTNING := &"lightning"
const ICE := &"ice"
const WIND := &"wind"
const LIGHT := &"light"
const DARK := &"dark"

const BASE_ELEMENTS := [METAL, WOOD, WATER, FIRE, EARTH]
const ADVANCED_ELEMENTS := [LIGHTNING, ICE, WIND, LIGHT, DARK]

const MASTERY_PREFIX := "element_mastery_"
const POWER_PREFIX := "element_power_"
## ADR 0200: a defender's mitigation is a MAGNITUDE fed to a ratio, not a capped
## percent, so this is the `D` in `m = mitigation_ceiling * D / (K + D)` rather than a
## fraction of the fight. The old `element_resistance_` prefix named a percent whose
## ceiling is what stopped mattering as offense rode the realm ladder.
const DEFENSE_PREFIX := "element_defense_"


static func mastery_id(element: StringName) -> StringName:
	return StringName(MASTERY_PREFIX + String(element))


static func power_id(element: StringName) -> StringName:
	return StringName(POWER_PREFIX + String(element))


static func defense_id(element: StringName) -> StringName:
	return StringName(DEFENSE_PREFIX + String(element))
