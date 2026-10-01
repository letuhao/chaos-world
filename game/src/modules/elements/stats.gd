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
const RESISTANCE_PREFIX := "element_resistance_"


static func mastery_id(element: StringName) -> StringName:
	return StringName(MASTERY_PREFIX + String(element))


static func power_id(element: StringName) -> StringName:
	return StringName(POWER_PREFIX + String(element))


static func resistance_id(element: StringName) -> StringName:
	return StringName(RESISTANCE_PREFIX + String(element))
