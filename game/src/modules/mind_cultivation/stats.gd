class_name MindStats
extends RefCounted

## Stat and resource ids owned by the `mind_cultivation` module (ADR 0013).

# Base attributes
const PERCEPTION := &"perception"
const MENTAL_CLARITY := &"mental_clarity"

# Derived stats
const MENTAL_ATTACK := &"mental_attack"
const MENTAL_DEFENSE := &"mental_defense"
const SPIRITUAL_SENSE_RANGE := &"spiritual_sense_range"
const CRITICAL_CHANCE := &"critical_chance"
const DODGE_CHANCE := &"dodge_chance"
const ILLUSION_RESISTANCE := &"illusion_resistance"
const MIND_TECHNIQUE_POWER := &"mind_technique_power"
const COMPREHENSION_BONUS := &"comprehension_bonus"

# Sea of Consciousness derived stats (ADR 0016)
const SEA_CAPACITY := &"sea_capacity"
const SEA_CLARITY := &"sea_clarity"
const SEA_TURBULENCE := &"sea_turbulence"
const SEA_FULL := &"sea_full"

# Resources
const MIND_POWER := &"mind_power"
const AWARENESS := &"awareness"
