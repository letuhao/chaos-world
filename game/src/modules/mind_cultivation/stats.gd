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
## ADR 0215. RENAMED from `mind_focus_chance` (ADR 0071's id). It is NOT core's
## `Stat.CRIT_CHANCE` and must never gate a non-mind hit -- it is read ONLY by
## `MindDamage._focus_of`, as the OFFENCE half of the mind crit roll, whose outcome
## multiplies the TURBULENCE term of a mind strike by ADR 0071's `FOCUS_MULT`.
##
## ## Why the rename, and why the CAP is gone with it
## The old id was renamed because the contest now has a NAME for both halves: `mind_clarity`
## attacks and `mind_veil` hides. ADR 0215 then removed the `minf(0.75, …)` ceiling --
## the ADR 0200 defect in a second uniform -- so the stat is an unbounded MAGNITUDE
## rather than a capped fraction, which is why it left `Stat.RATE_STATS` and why a FLAT
## on it is legal authored content rather than 1000%.
const MIND_CLARITY := &"mind_clarity"
## ADR 0215. RENAMED from `mind_avoidance` (ADR 0071's `dodge_chance`), and NOT core's
## `Stat.EVASION`. Read ONLY by `MindDamage._avoidance_of` as the DEFENCE half: its roll
## removes exactly `COHERENCE_DAMP` of the incoming strike's coherence -- half of it at
## the shipped `0.5`, so a spent avoidance is a worse fight rather than a refused one.
## That is the deliberate difference from a crit, which SPENDS `FOCUS_MULT`: avoidance is
## a STEADIER, not a refusal, which is why it can be as cheap as a half and why it can
## never reach a second miss channel the way an evasion stat could. Its `minf(0.6, …)`
## is gone for ADR 0215's reason.
const MIND_VEIL := &"mind_veil"
## ## Retired by ADR 0215 in favour of [constant MIND_VEIL].
## Kept declared so a stale reference fails to COMPILE with a name rather than silently
## reading `0.0` off an unbacked stat -- the exact shape `test_combat_stats_shape.gd`
## exists to catch, and the same treatment `Stat.STATUS_RESISTANCE` gets. Do NOT add a
## read site for it or a publish site: that is how a second vocabulary starts.
const MIND_AVOIDANCE := &"mind_avoidance"
## Retired by ADR 0215 in favour of [constant MIND_CLARITY]. See [constant MIND_AVOIDANCE].
const MIND_FOCUS_CHANCE := &"mind_focus_chance"
## BL-0114 RESIDUE (not fixed here -- `game/data/` is not this module's to edit):
## the ADR 0071 rename is complete in `res://src` but NOT in the authored content. The
## item option `cult_dodge_chance` (`data/item_options/master_option_pool.jsonl:42`,
## `"status": "active"`) still targets `"id": "dodge_chance"`, and
## `data/techniques/passive_quick_reaction.tres:20` ships it at `value = 5.0` under
## a description that promises "Dodge chance and mental attack". `MindProvider` no
## longer emits that id and core's own is `evasion`, so `OptionCatalog.make_effect`
## normalises it to `target_id = &"dodge_chance"` and `ActorStats` applies a PERCENT
## modifier to a bucket no provider ever fills: the modifier is inert and half that
## technique is a no-op. It is also in 5 entries of `derived/option_pools.json`, so
## equipment can roll it. Tracked in `docs/backlog.jsonl`; it needs an `items`/
## content decision (retarget to `mind_veil`, or retire the option), not a
## change to this module.
const MIND_TECHNIQUE_POWER := &"mind_technique_power"
## ## ADR 0215. The `minf(0.8, …)` ceiling is DELETED.
## The stat is unchanged in meaning -- it is the defence half ADR 0071 gave `OBSCURE` and
## nothing else -- but it is now an unbounded MAGNITUDE, so an illusion-resistance build
## keeps buying mitigation past the point where the cap made it stop dead. Not a
## `RATE_STATS` member any more, which is what makes a FLAT on it legal authored content.
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
