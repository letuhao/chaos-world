class_name BodyStats
extends RefCounted

## Stat and resource ids owned by the `body_cultivation` module (ADR 0012).

# Base attributes
const BONE_DENSITY := &"bone_density"
const MUSCLE_FIBER := &"muscle_fiber"
const ORGAN_VITALITY := &"organ_vitality"

# Derived stats
#
# Attack, defense, move speed, and poise are owned by `core`. They are re-exported
# here as aliases, NOT private ids: a provider value replaces the core baseline
# for whatever id it emits (ADR 0026), so a module that invented its own id would
# silently contribute nothing, while a module that emitted the core id with a
# different scale would silently erase the core value. Aliasing them keeps one
# id per concept; `BodyProvider` contributes them additively.
const PHYSICAL_ATTACK := Stat.ATTACK_PHYSICAL
const PHYSICAL_DEFENSE := Stat.DEFENSE_PHYSICAL
const MOVE_SPEED := Stat.MOVE_SPEED
const POISE := Stat.POISE

# Module-owned derived stats: no core baseline exists, so the body module
# defines them outright.
const CARRY_CAPACITY := &"carry_capacity"
const REGENERATION := &"regeneration"
const BODY_CULTIVATION_POWER := &"body_cultivation_power"

# Acupoint read model (ADR 0015)
const ACUPOINT_QUALITY := &"acupoint_quality"
const ACUPOINT_COUNT := &"acupoint_count"
const ACUPOINT_BLOCKED_COUNT := &"acupoint_blocked_count"

# Resources
const BODY_INTEGRITY := &"body_integrity"
