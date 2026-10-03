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
## ADR 0071 / BL-0114: RENAMED from `critical_chance`. It is NOT core's
## `Stat.CRIT_CHANCE` and must never gate a non-mind hit -- it is read ONLY by
## `MindDamage`, and ONLY as the `mind_focus_chance` roll whose outcome doubles the
## TURBULENCE term of a mind strike (ADR 0071's `FOCUS_MULT`). Renaming it is the whole
## point: the old id read as a second crit dial any future combat system would adopt,
## and folding it into core instead would have made every mind stat boost every qi and
## body hit (ADR 0071's "RENAME, do not fold").
const MIND_FOCUS_CHANCE := &"mind_focus_chance"
## ADR 0071 / BL-0114: RENAMED from `dodge_chance`, and NOT core's `Stat.EVASION`.
## Read ONLY by `MindDamage` as the `mind_avoidance` roll, whose outcome removes exactly
## `COHERENCE_DAMP` of the incoming strike's coherence -- half of it at the shipped
## `0.5`, so a spent avoidance is a worse fight rather than a refused one. That is the
## deliberate difference from a crit, which spends `FOCUS_MULT`: avoidance is a
## STEADIER, not a refusal, which is why it can be as cheap as a half and why it can
## never reach a second miss channel the way an evasion stat could.
const MIND_AVOIDANCE := &"mind_avoidance"
const MIND_TECHNIQUE_POWER := &"mind_technique_power"
const ILLUSION_RESISTANCE := &"illusion_resistance"

## DELETED (BL-0163), and not re-added:
##
## - `comprehension_bonus` (`1.0 + comprehension * 0.01 + technique_factor * 0.02`)
##   was a SECOND rate on the same quantity core already owns as
##   `Stat.INSIGHT_GAIN` (`1.0 + comprehension * 0.01`) — identical base term plus a
##   realm-rate term. Nothing read it, and `MindTraining._grant_insight` now reads
##   `Stat.INSIGHT_GAIN` directly, so keeping it would have priced one gate through
##   two divergent multipliers (ADR 0116's "one number, no copies", and the same
##   duplicate-dial rule ADR 0071 applied to `critical_chance`/`dodge_chance`).
## - `sea_clarity` / `sea_turbulence` were mirrors of the `SeaOfConsciousness`
##   component fields ADR 0071's mind formula reads off the component. A stat that
##   restates a component no reader consults is a second copy of the truth.
## - `sea_full` was a THIRD, disagreeing definition of "full": it compared against
##   `effective_capacity()` while `SeaOfConsciousness.is_full()` compares against
##   the reservoir maximum, so a turbulent sea reported full while not being full.
##   `SeaOfConsciousness.is_full` is the single definition.

# Sea of Consciousness derived stats (ADR 0016)
const SEA_CAPACITY := &"sea_capacity"

# Resources
const MIND_POWER := &"mind_power"
const AWARENESS := &"awareness"
