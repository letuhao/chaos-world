class_name Stat
extends RefCounted

## Canonical stat ids. Modules may define their own StringName ids.

enum Op { FLAT, PERCENT, MULT }

# Base attributes — the only stored truth.
const PHYSIQUE := &"physique"
const SPIRIT := &"spirit"
const APTITUDE := &"aptitude"
const COMPREHENSION := &"comprehension"
const AGILITY := &"agility"
const WILL := &"will"
const FORTUNE := &"fortune"

const BASE_ATTRIBUTES := [
	PHYSIQUE,
	SPIRIT,
	APTITUDE,
	COMPREHENSION,
	AGILITY,
	WILL,
	FORTUNE,
]

# Derived stats — recomputed, never stored as truth.
const MAX_HEALTH := &"max_health"
const MAX_QI := &"max_qi"
const MAX_STAMINA := &"max_stamina"
const HEALTH_REGEN := &"health_regen"
const QI_REGEN := &"qi_regen"
const STAMINA_REGEN := &"stamina_regen"
const ATTACK_PHYSICAL := &"attack_physical"
const ATTACK_SPIRITUAL := &"attack_spiritual"
const CRIT_CHANCE := &"crit_chance"
const CRIT_DAMAGE := &"crit_damage"
const PENETRATION := &"penetration"
const ATTACK_SPEED := &"attack_speed"
const DEFENSE_PHYSICAL := &"defense_physical"
const DEFENSE_SPIRITUAL := &"defense_spiritual"
const EVASION := &"evasion"
const DAMAGE_REDUCTION := &"damage_reduction"
const POISE := &"poise"
const STATUS_RESISTANCE := &"status_resistance"
const MOVE_SPEED := &"move_speed"
const CULTIVATION_RATE := &"cultivation_rate"
const QI_ABSORPTION := &"qi_absorption"
const BREAKTHROUGH_CHANCE := &"breakthrough_chance"
const DAO_HEART := &"dao_heart"
const INSIGHT_GAIN := &"insight_gain"
const LOOT_BONUS := &"loot_bonus"
const COOLDOWN_REDUCTION := &"cooldown_reduction"
const QI_COST_REDUCTION := &"qi_cost_reduction"

## Stats whose baseline is a fraction (0..1) or a multiplier (1.0 == no change).
## Derived in core/actor_stats.gd from these scales:
##   crit_chance 0.05 (cap 0.75), evasion (cap 0.6), status_resistance (cap 0.8),
##   cooldown_reduction (cap 0.4), qi_cost_reduction (cap 0.5), damage_reduction 0.0,
##   crit_damage 1.5, attack_speed 1.0 (cap 2.5), cultivation_rate 1.0,
##   insight_gain 1.0, breakthrough_chance 0.1.
## A FLAT modifier on any of these is a content error: `+10` means 1000%, not +10.
## PERCENT is always valid on any stat; only FLAT on a rate stat is wrong.
## Membership requires a NON-ZERO baseline: core/actor_stats.gd resolves a stat
## as `(base + flat) * (1 + percent)`, so PERCENT on a zero baseline is a no-op.
## `damage_reduction` has baseline 0.0 and is deliberately absent (ADR 0022).
const RATE_STATS := [
	ATTACK_SPEED,
	BREAKTHROUGH_CHANCE,
	COOLDOWN_REDUCTION,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	CULTIVATION_RATE,
	EVASION,
	INSIGHT_GAIN,
	QI_COST_REDUCTION,
	STATUS_RESISTANCE,
]
