class_name QiStats
extends RefCounted

## Stat and resource ids owned by the `qi_cultivation` module (ADR 0011).

# Resources
## One active qi reservoir. The dantian owns structural tier, quality, and injury
## only; a second qi axis was removed rather than left as a constant no-op.
const QI := &"qi"

# Base attributes
const QI_AFFINITY := &"qi_affinity"
const QI_CONTROL := &"qi_control"
const DANTIAN_CAPACITY := &"dantian_capacity"

# Derived stats
const QI_REGEN_RATE := &"qi_regen_rate"
const QI_ABSORPTION := &"qi_absorption"
const TECHNIQUE_COST_REDUCTION := &"technique_cost_reduction"
const TECHNIQUE_POWER := &"technique_power"
const FLIGHT_SPEED := &"flight_speed"
const QI_SENSE_RANGE := &"qi_sense_range"
const DANTIAN_QUALITY := &"dantian_quality"
const DANTIAN_FULL := &"dantian_full"
