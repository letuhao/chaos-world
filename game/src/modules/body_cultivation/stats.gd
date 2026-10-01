class_name BodyStats
extends RefCounted

## Stat and resource ids owned by the `body_cultivation` module (ADR 0012).

# Base attributes
const BONE_DENSITY := &"bone_density"
const MUSCLE_FIBER := &"muscle_fiber"
const ORGAN_VITALITY := &"organ_vitality"

# Derived stats
const PHYSICAL_ATTACK := &"physical_attack"
const PHYSICAL_DEFENSE := &"physical_defense"
const MOVE_SPEED := &"move_speed"
const CARRY_CAPACITY := &"carry_capacity"
const REGENERATION := &"regeneration"
const POISE := &"poise"
const BODY_CULTIVATION_POWER := &"body_cultivation_power"
const ACUPOINT_QUALITY := &"acupoint_quality"
const ACUPOINT_COUNT := &"acupoint_count"
const ACUPOINT_BLOCKED_COUNT := &"acupoint_blocked_count"

# Resources
const BODY_INTEGRITY := &"body_integrity"
