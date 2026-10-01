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
