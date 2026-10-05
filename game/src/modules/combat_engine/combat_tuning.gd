class_name CombatTuning
extends Resource

## Every balance number the shared spine reads, in DATA (ADR 0067, ADR 0068, BRIEF 1.7).
##
## `modules/combat_engine/combat_damage.tres` is the shipped instance; a mechanism, the band
## roll, or a future wave reading a literal out of its own `.gd` is the defect this
## file exists to prevent. The precedent is `RealmScaling` reading `RealmDef.power`
## instead of hardcoding 551.0 — a rebalance becomes a `.tres` edit, and no test has
## to re-pin a number that changed on purpose.
##
## These are VALUES, and the defaults below are the schema's neutral state, not a
## shipped balance: `CombatTuning.new()` is deliberately degenerate (a 0.0 chip floor,
## a 0.0 rate scale) so a caller who forgets the `.tres` gets an obviously broken
## result instead of a plausible one. `CombatApi.tuning()` is the only supported way
## to obtain one.
##
## ## Why some fields exist at all
##
## `min_chip_abs` and `min_chip_share` are the immunity invariant (BRIEF 1.3): because
## `Stat.DAMAGE_REDUCTION` is FLAT with a `0.0` baseline (ADR 0022) it is a
## subtraction rather than a fraction, so a sufficiently large one can drive the amount
## to zero — and the floor restores a landed hit to at least `min_chip_abs`. They are
## DATA precisely because that makes them a balance dial; a test asserting the
## invariant must read them here, not restate 1.0.
##
## `avoidance_band_cap` is the other distributional bound: the band roll caps its total
## at this value so every attack lands at least `1 - avoidance_band_cap` of the time
## and no stack of defensive stats reaches immunity (ADR 0068).
##
## `chain_depth_limit` terminates reflect by DROPPING the bounce, never by clamping it
## to zero, so a deep chain is visibly truncated rather than silently rounded away.

## The floor every landed hit is restored to by S8, in health points. With
## `min_chip_share` this is `maxf(amount, maxf(min_chip_abs, base * min_chip_share))`,
## so immunity is arithmetically unreachable rather than capped (ADR 0067).
@export var min_chip_abs: float = 0.0
## The share of the S1 base below which a landed hit is floored anyway. A small share
## means a very weak hit still chips; the pair is the distributional claim "of hits
## that land, at least this much is spent".
@export var min_chip_share: float = 0.0
## Ceiling on the DEFENSIVE total, `p_parry + p_block` -- NOT on `p_hit` as well. The
## complement is the guaranteed clean share: at 0.95 a defender who saturates both
## bands still leaves 5% of attacks landing CLEAN, so no stack of defensive stats
## reaches immunity (ADR 0068). `p_hit` is the attacker's own contest
## (`accuracy` vs `EVASION`, already floored at 0.4 by core's `Stat.EVASION` cap), so
## folding it into this budget would make a defender's parry build silently delete the
## attacker's accuracy -- S1's "no second dial on `Stat.EVASION`" in reverse.
@export var avoidance_band_cap: float = 0.0
## How many reflect bounces may be spent before the next is DROPPED (ADR 0068). A drop
## is not a clamp: the outcome records that the chain ended, so nothing is silently
## rounded away.
@export var chain_depth_limit: int = 0
## The divisor of the linear-from-zero rate contest: `clampf(maxf(0, rate - resist) /
## rate_scale, 0, 1)`. Linear, never sigmoid — a sigmoid returns 0.5 at parity, so an
## actor with ZERO parry stat would parry half the time, a default nobody chose
## (ADR 0068).
@export var rate_scale: float = 0.0
## The divisor of the amplification/reduction factor at S7: `maxf(0, 1 + d /
## amp_scale)`, linear and floored at zero. See `CombatSpine.amp_factor` for why this is
## NOT a reciprocal -- ADR 0067 refuses `AmpFactorReciprocal` by name, and a reciprocal
## cannot reach zero on the reduction branch, which is the property S8 exists to undo.
## The floor is what makes `d == -amp_scale` a total refusal rather than an infinity.
@export var amp_scale: float = 0.0
## The pool S11's leech writes. `health` by default; a module that adds its own
## reservoir redirects it without touching the spine's arithmetic.
@export var lifesteal_pool: StringName = &"health"

# --- The qi path's own bounds (ADR 0069) --------------------------------------
#
# These are the ONLY numbers `QiDamage` reads, and every one of them is a value: the
# defaults below are the schema's neutral state, so a caller with no `.tres` gets
# share 0.0, a 0.0 divisor and a 0.0 cap -- all visibly broken rather than a plausible
# balance. `resist_divisor` at 0.0 is read as "no scale, so no resistance" and never as
# a division; see `QiDamage._resistance_of` for why that guard is load-bearing.

## The `element_share` a technique falls back to when it authored none, because
## `TechniqueDef.element_share == 0.0` means "use the default" and not "use none".
## The only balance number on this resource the qi path may not tune per technique.
@export var default_element_share: float = 0.0
## The divisor that converts a defender's authored `element_defense_<e>` MAGNITUDE into
## the same magnitude space as the attacker's `element_power_<e>`, so `D` and the `offense`
## `K` is derived from are the same kind of number. ADR 0200 retires the old reading of
## this field -- a fixed divisor meeting a growing `D` is exactly the defect that
## collapsed defense to noise at depth -- and the VALUE is unchanged, because the formula
## that replaced it is `m = mitigation_ceiling * D / (K + D)`, where `D` is a magnitude and
## `K` rides the attacker. Non-positive reads as "no scale, so no defense", never as a
## division by zero.
@export var resist_divisor: float = 0.0
## ADR 0200. The MULTIPLIER every mechanism's mitigation curve carries, NEVER a clamp:
## `m = mitigation_ceiling * D / (K + D)`, so `m` APPROACHES this and never arrives, and
## every further point of defense still raises `m`. `min(0.95, D/(K+D))` is the exact
## failure this field exists to remove -- it makes defense a dead stat one number higher.
##
## Read into `[0, 1]` so an authoring mistake above one cannot hand a mitigation above
## 100%, whose complement is negative and S9's one sign flip would spend the term as a
## HEAL. That clamp is on the CEILING the author typed; the curve's OUTPUT is never
## clamped, which is the whole distinction the ADR turns on.
@export var mitigation_ceiling: float = 0.0
## ADR 0200. `K = defense_divisor_k * offense` -- the share of the ATTACKER's own
## magnitude a defender's defense is measured against. The owner's ruling is that `K` is
## PER MECHANISM: qi, body and mind each author their own here, so the three mechanisms
## stay independent of one another's balance and one path cannot be retuned by another.
@export var defense_divisor_k: float = 0.0
## ADR 0200. The scale penetration is measured against ON THE DEFENSE VALUE:
## `D_eff = D * 1 / (1 + max(0, pen) / pierce_scale)`. Bounded in `(0, 1]`, so
## penetration can push defense arbitrarily close to zero and can NEVER grant negative
## defense -- which would turn mitigation into a second damage source. This is never a
## subtraction from the damage, which is dimensionally wrong: `body_damage.gd` used to do
## exactly that and the ADR says so by name. Non-positive reads as "penetration does
## nothing", never as a division.
@export var pierce_scale: float = 0.0
## The most `Stat.DAMAGE_REDUCTION` may remove at S5. Flat and `0.0`-baselined
## (ADR 0022), so the spine's S8 chip floor -- not this -- is what keeps a landed hit
## non-zero. Clamped to `[0, 1]` on read for the same sign reason as `mitigation_ceiling`.
@export var damage_reduction_cap: float = 0.0
## The authored prefixes of the `elements` module's per-element stat ids, read by the
## qi path so it does not have to name that module's classes to name its stats
## (BRIEF 1.7: tuning in DATA; ADR 0069: `ElementRules` is injected, so the combat layer
## reads `elements` rather than the other way round). These are STRINGS on purpose: a
## `StringName` constant naming `elements` would put a compile-time edge into a module
## whose dependency list is `["contracts", "core"]`, and the registry must not lie.
@export var element_power_prefix: String = ""
@export var resist_resistance_prefix: String = ""

# --- The mind path's own bounds (ADR 0071) ------------------------------------
#
# Every number `MindDamage` reads, and ADR 0071's nine by name. The defaults below
# are the schema's neutral state for the same reason as the qi block above: a caller
# with no `.tres` gets a 0.0 `structural_capacity` floor -- visibly broken (nothing
# resolves) rather than a plausible balance, which is the one property `CombatTuning`
# as a whole is designed around.
#
# ## What is DELIBERATELY absent from this block, and why it is not an oversight
#
# **`Stat.DAMAGE_REDUCTION` has no mind field.** ADR 0071: it is NEVER read by the
# mind mechanism, so a qi/body tank does nothing at all to erosion. Putting a mind
# knob beside it would be the first step toward exactly the seam `DamageMechanism`
# refuses to offer mind -- a stage where a shared stat could reach a mind hit.
#
# ## What ADR 0200 RETIRED from this block
#
# **`MENTAL_DEFENSE_CAP` and `ILLUSION_RESISTANCE_CAP` are GONE**, and with them the 40%
# floor they used to make structural. Both were authored CEILINGS ON AN INPUT, and an
# input is what has to grow: the attacker's `MENTAL_ATTACK` rides the ladder while a
# `0.6`-capped `d/(d+base)` stopped mattering past R3, so 40% of every mind strike landed
# forever. Mitigation is now the shared ADR 0200 curve over the shared
# `mitigation_ceiling` / `defense_divisor_k`, so `m` is asymptotic rather than clamped and
# the deepest defence is the best defence with no number at which investment stops paying.
#
# The floor did not survive as immunity. It survived as the ASYMPTOTE: a mind strike lands
# at least `1 - mitigation_ceiling` of itself at any defense and any realm, because
# `m < mitigation_ceiling` strictly for every finite `D`. `MindDamage.defense_floor()`
# publishes that number and is where a caller reads it.

## The share of `MENTAL_ATTACK` this attack carries, as ADR 0071's `share` term.
## Clamped to `[0, 1]` on read: a share above one would make the erosion exceed a
## full strike and a negative one would author a mind hit that HEALS the sea's
## clarity budget. `0.0` is the degenerate default, meaning "this tuning has not
## chosen a share" -- which erodes nothing, the visibly-broken state.
@export var default_mind_share: float = 0.0
## ADR 0071's `COHERENCE_DAMP`: how much a FULL awareness pool costs an incoming
## strike. `coh = 1 - COHERENCE_DAMP * awareness_ratio`, so at 0.5 coherence is
## exactly 0.5 at a full reserve and 1.0 at an empty one. Clamped to `[0, 1]`: above
## 1.0 the coherence term goes NEGATIVE at a full pool, and a negative multiplier
## would hand the defender a share of the attacker's own erosion as a heal.
@export var coherence_damp: float = 0.0
## ADR 0071's `FOCUS_MULT`: the multiplier a `mind_focus_chance` crit spends, applied
## to the TURBULENCE term only. Above one it is the mind path's crit damage and
## nothing else -- see `MindDamage.resolve`'s effects. Clamped to `[0, 1]`: a value
## below 1.0 would make a crit a WEAKER strike, which no chance stat should ever do.
@export var focus_mult: float = 1.0
## ADR 0071's `TURBULENCE_TO_CLARITY`: the share of the erosion `g` that is paid out
## of clarity for EVERY kind. A whole share (`1.0`) would mean turbulence and clarity
## are the same number wearing two names, so the shipped value is well below it and
## clarity erosion saturates at its own pace. Clamped to `[0, 1]` on read.
@export var turbulence_to_clarity: float = 0.0
## ADR 0071's `RUPTURE_THRESHOLD`: the turbulence above which health moves at all.
## The mind path's own floor of safety, and the property qi (ADR 0069) and body
## (ADR 0070) do not have. Clamped into `[0, 1]`: a threshold at or above 1.0 is
## unreachable by construction and silently disables rupture bleeding.
@export var rupture_threshold: float = 0.0
## ADR 0071's `RUPTURE_BLEED`: the share of `max_health` a fully ruptured sea spends
## PER SECOND. At the threshold the bleed is 0.0 and at `turbulence == 1.0` it is
## this figure, linearly in between. Clamped to `[0, 1]`: above 1.0 a single second at
## full turbulence deletes a whole health pool, and the mechanism's whole premise is
## that the loser is disarmed rather than killed.
@export var rupture_bleed: float = 0.0
## ADR 0071's `RUPTURE_COLLAPSE_TIME`: the CONTINUOUS seconds at `turbulence == 1.0`
## that cost the defender their sea tier. Continuous because ADR 0068's own rule --
## a defending response that resets a timer is a second resource to manage, and
## `meditate` already is one. Non-positive disables collapse entirely, which is the
## only way to turn the consequence off without deleting the mechanism.
@export var rupture_collapse_time: float = 0.0
## ADR 0071's `COLLAPSE_CLARITY_FLOOR`: where clarity is left after a collapse.
## Clarity is the SOLE input to the mind breakthrough roll (ADR 0051), so this is
## literally how much progress a collapse costs. Clamped to `[0, 1]`.
@export var collapse_clarity_floor: float = 0.0
## The `structural_capacity` each demoted sea tier is reset to, keyed by tier id and
## read as a plain dictionary so this resource never names `SeaOfConsciousness` (whose
## module is not a `combat_engine` dependency). A tier missing from it is NOT
## demoted further -- `vast` is the floor of the ladder, so a demotion past it has no
## meaning and inventing a fourth tier would be a cultivation decision this module may
## not make. Non-positive entries read as "leave the capacity alone".
@export var collapse_capacity_floors: Dictionary = {}
## How long the `mind_deviation` status a collapse applies lasts, in seconds.
## ADR 0071: "the loser is disarmed for a minute, not killed". Must stay positive --
## `StatusEffect`'s own `-1.0` sentinel means PERMANENT, so a `0.0` here would build a
## status that is already expired on the frame it was applied.
@export var collapse_deviation_duration: float = 0.0
## The `mind_cultivation` stat ids this module reads, named by PREFIX rather than as a
## `MindStats` constant. `combat_engine`'s deps stay `["contracts", "core"]`, and a
## `StringName` naming `MindStats` from here is exactly the compile-time edge the registry
## would then have to declare. Same discipline as `element_power_prefix` and
## `tissue_stat_ids`, same reason.
##
## **The shipped value is the EMPTY prefix, and that is correct rather than broken.**
## Unlike `element_power_<e>`, mind's ids carry no per-instance suffix: the mechanism reads
## `<prefix>mental_attack`, `<prefix>mental_defense`, `<prefix>illusion_resistance`,
## `<prefix>mind_focus_chance` and `<prefix>mind_avoidance`, which at `""` are exactly the
## bare ids `MindProvider.contribute` already emits. The field exists so the EDGE stays a
## string concatenation instead of a class reference, not because there is something to
## prepend -- an author who sets it must set the `MindProvider` side to match.
@export var mind_stat_prefix: String = ""
## The `mind_cultivation` component key the sea is reached through when a caller injects no
## sea of its own. A STRING in DATA rather than `MindCultivationApi.SEA_COMPONENT` in code,
## for the same edge reason as the prefix above. Empty means the mechanism will not guess:
## a caller must inject the sea, and a caller who forgot gets an erosion of `0.0`.
@export var sea_component: StringName = &""
## The pool whose `current / maximum` is the defender's AWARENESS RATIO -- the depleting
## reserve `coherence` is computed from, and the reserve an `ATTEND` strike drains. A
## `StringName` in DATA rather than `MindStats.AWARENESS` for the edge reason above.
## Empty means "no reserve to read", which is the WORST coherence rather than a neutral one.
@export var awareness_pool_id: StringName = &""
## The pool `rupture_bleed` spends against. Distinct from the spine's own
## `lifesteal_pool` deliberately: leech HEALS health and rupture SPENDS it, and one field
## serving both would make a rebalance of the mind path silently move the leech.
@export var health_pool_id: StringName = &"health"
## The stat `mind_deviation` zeroes, by name and in DATA for the edge reason above. ADR
## 0071: the loser is disarmed, not killed, and a disarm that is not a real `StatusEffect`
## carrying a real zero is a bespoke mind flag rather than something the engine ticks.
@export var mind_deviation_stat: String = "mind_technique_power"
## ADR 0200. The stat-id `StatusApply` reads for the COMBAT half of the status gate.
## It used to be core's `Stat.STATUS_RESISTANCE`, a PERCENT capped at `0.8`; it is now
## `Stat.STATUS_DEFENSE`, an unbounded MAGNITUDE the ladder scales, and a FLAT on it is
## legal content rather than a contract error.
##
## It is a STRING in DATA for the same reason `mind_stat_prefix` above is: `StatusApply`
## may not name a core const it would then have to keep in step with, and the shape the
## gate wants is "whatever the defense magnitude is called today". `contracts/stat.gd`
## declares both spellings so a stale reference compiles and reads `0.0` rather than
## silently answering with the wrong number — which is the failure this indirection is
## guarding against, not enabling.
@export var status_defense_stat: String = "status_defense"

# --- S12: status application (ADR 0087, ADR 0088) ------------------------------
#
# Every number the twelfth stage reads, and the only ones. ADR 0087's own
# consequence calls these PROVISIONAL: the designs' numbers are reasoned guesses, not
# measurements, so they are re-tuned by editing this file and never by an ADR -- none
# of them is an architectural claim.
#
# `status_resist_divisor` / `status_resist_cap` deliberately RESTATE no new
# vocabulary: `QiDamage` already owns `resist_divisor` / `resist_cap` for the damage
# formula, and ADR 0087 requires S12 to read "ADR 0069's formula, read once, not
# restated". Rather than a second pair that could drift from the first, the resist
# shape below REUSES those two fields -- the same authored divisor and cap answer
# "how big is an elemental resistance" for a hit and for a status alike.
#
# `status_mastery_pen` is NOT a second mastery lever (ADR 0088). Mastery's ONE
# meaning is penetration, and `CombatStats.PENETRATION` is already that channel and
# is already read by `QiDamage._resistance_of` for the damage resist term. S12
# subtracts the SAME stat, so a build cannot be a great penetrationist against damage
# and a useless one against statuses -- and, more importantly, penetration is not
# applied to POTENCY anywhere, so the one investment never double-dips.
## The BASE gate chance, before ADR 0087's resist terms are subtracted, for an
## application this repo cannot author a per-technique `status_chance` for.
##
## ## Why this field exists, and what it is NOT
##
## ADR 0087 named a per-attack authored `status_chance` and ADR 0105 REPLACED it: the
## carrier is now the ELEMENT (`StatusDef.element` + its `on_landed_blow` flag), so a
## status cannot be authored per blow and the encounter path has no attack def to read a
## chance off. ADR 0105 left the number as `CombatExchange.STATUS_GATE_CHANCE` and
## recorded exactly this one-line fix as its debt: "add `@export var status_gate_chance`
## to `CombatTuning`, author it in `combat_damage.tres` at `1.0`, and make this read
## `CombatEngineApi.tuning().status_gate_chance`." This is that fix. The value SHIPPED is
## unchanged at `1.0` -- moving it is the work; retuning it is a balance pass's, and
## ADR 0087's consequence ("provisional … re-tuned by an edit, never by an ADR") is
## precisely why it belongs here rather than in a `.gd`.
##
## ## `1.0` does NOT mean resistance is ignored
##
## `StatusApply.apply_chance` is `clampf(gate * (1 - STATUS_RESISTANCE) * (1 -
## elem_resist), status_min_apply, 1.0)`, so a gate of `1.0` hands the whole decision to
## the two resist terms and the roll -- which is what ADR 0087's formula is FOR. What it
## DOES mean is that the base rate is unconditional, so an unresisted actor's `chance`
## short-circuits to `1.0` and consumes no draw: every landed blow of that element
## inflicts with certainty. That saturation is the value a balance pass moves first.
##
## Clamped to `[0, 1]` on read by `StatusApi`/`CombatExchange` callers: above one the
## formula's own `clampf(..., 1.0)` makes it unreachable arithmetic, and a gate below
## `0.0` is the CLOSED gate (ADR 0087), which spends no draw at all.
@export var status_gate_chance: float = 0.0
## Floor on the apply chance of a gate that is OPEN. The multiplicative form
## `chance * (1 - STATUS_RESISTANCE) * (1 - elem_resist)` cannot go negative, so a
## defender can slow application to a crawl but can never make it impossible: this
## value, not a clamp to zero, is what guarantees an authored status still lands
## sometimes (ADR 0087). A CLOSED gate -- an authored `status_chance` of `0` -- reads
## no floor at all and consumes no draw, so a technique that applies nothing costs
## nothing (ADR 0068's "a fully-saturated roll is free", applied to S12).
@export var status_min_apply: float = 0.0
## Coefficient from the attacker's `element_power_<e>` onto the applied status's
## potency. Potency REUSES that id rather than adding an `element_status_power_<e>`
## sibling (ADR 0088), so it inherits ADR 0069's realm-invariance fix with no new stat
## channel, no new authored option and no new read site. `0.0` is the degenerate
## default: an unattached provider means no elemental power, and potency then rests
## entirely on `status_potency_floor`.
@export var status_potency_scale: float = 0.0
## The potency every applied status carries even when the attacker's elemental power
## is `0.0`. Exists because ADR 0088 records that `element_power_<e>` is derived for
## NOBODY until the mastery path and `app/` wiring land: without a floor, S12 would be
## silently dead rather than obviously unwired, and the status layer would ship
## invisible. Potency is scaled by the ELEMENTAL TERM's sign and never negated.
@export var status_potency_floor: float = 0.0
## How long an applied status lasts, in seconds, when its effect authored no
## `duration`. `Actor.tick_statuses(delta)` consumes seconds, and `StatusEffect`'s own
## `-1.0` sentinel means PERMANENT -- so this must stay positive: a `0.0` default
## produces a status that is already expired on the frame it was applied, which is
## exactly the silent-failure shape a degenerate default exists to expose.
@export var status_default_duration: float = 0.0

# --- The body path's own bounds (ADR 0070) --------------------------------------
#
# Every number `BodyDamage`, `BodyLocation` and `BodyWounds` read. ADR 0070 names seven
# of them; the rest are the minimum a THIRD aim mode and the location multipliers need,
# and each carries the same discipline: a default of `0.0` for a coefficient and `1.0`
# for a pure multiplier, which is `CombatStats.DEFAULTS`' own convention for the two
# kinds. A bare `CombatTuning.new()` therefore gives body damage no armour, no
# penetration floor and no tissue weighting -- visibly broken -- while the multipliers
# read as the identity, which is the honest neutral rather than a plausible balance.
#
# `acupoint_data_dir` and `tissue_stat_ids` are here for the same reason
# `element_power_prefix` is: naming another module's CONTENT PATHS and STAT IDS in DATA
# is the one honest way for `combat_engine` to read them while `registry.json` keeps
# this module at `["contracts", "core"]` and the registry does not have to lie about an
# edge that exists only as a string concatenation.

## The floor ADR 0070 calls load-bearing: `penetration = maxf(gross - resistance, gross
## * min_penetration_ratio)`. Without it, enough `DEFENSE_PHYSICAL` and tissue drive
## penetration to `0.0`, the location multiplier multiplies nothing, and a stat the
## defender already had deletes the entire mechanic. Clamped to `[0, 1]` on read: above
## `1.0` the floor would exceed the gross and armour would make a strike STRONGER.
@export var min_penetration_ratio: float = 0.0
## What one step of channel rank is WORTH in armour points, per point of
## `Stat.DEFENSE_PHYSICAL`: `resistance += DEFENSE_PHYSICAL * meridian_armour_step *
## channel.state_rank()`. A `closed` channel has `state_rank() == 0`, contributes nothing,
## and can still be struck -- which is the refusal the flat subtraction exists to make
## expressible (ADR 0070's fourth reason for refusing Keepverse's ratio).
@export var meridian_armour_step: float = 0.0
## What one full point of huyệt quality (ADR 0015's own `0..1` scale) is worth as a
## multiplier: `point_multiplier = 1 + point_quality_step * quality`. Read clamped to
## `0..1` on read, so a hand-edited `.tres` cannot author a point that is BOTH the best
## aim point and a damage REDUCER.
@export var point_quality_step: float = 0.0
## What one step of channel rank is worth as a MULTIPLIER. Deliberately the other side
## of `meridian_armour_step` and not the same sign: training a channel makes it a bigger
## target as well as a harder one, which is the decision a body build actually makes.
@export var channel_mult_step: float = 0.0
## What `MeridianState.injured` adds to a channel's multiplier. ADR 0070's inversion,
## half of it: `get_bonus() == 0.5` takes the channel's AGGREGATE bonus away from every
## path, and this is where the same flag gives the attacker its share back.
@export var injured_mult_step: float = 0.0
## The multiplier on a JAMMED huyệt -- `Acupoint.blocked` read with its OTHER meaning.
## For the cultivator it is a lost investment (`AcupointSet.open_count` drops and
## `average_quality` ignores the point); for the attacker it is the best aim point on
## the body. This must exceed `1 + point_quality_step` for `random` aim to be able to
## answer "it found the jammed Lung node", which is a property the suite asserts.
@export var blocked_mult: float = 1.0
## What a `broad` strike pays per meridian. Applied to EVERY unlocked meridian, so a
## broad hit is worth several single hits and its per-meridian share is always lower --
## a sweep is coverage, not a critical blow.
@export var broad_mult: float = 1.0
## The scalar on the per-meridian TISSUE weighting, `tissue = tissue_scale * (sum of
## each body stat x its archetype weight) / tissue_stat_divisor`. Tissue is a seasoning
## on the armour term, not a second armour: the shipped value keeps it well under one
## point of `Stat.DEFENSE_PHYSICAL` per point of bone.
@export var tissue_scale: float = 0.0
## What a point of `bone_density`/`muscle_fiber`/`organ_vitality` is worth in the same
## space as `Stat.DEFENSE_PHYSICAL`. Those three are BASE attributes and `DEFENSE_PHYSICAL`
## is a derived stat, so without this the two terms are not the same kind of number --
## the same reason `CombatSpine._scaled_core_reduction` exists on the S7 edge.
## Non-positive reads as "no tissue", never as a division.
@export var tissue_stat_divisor: float = 0.0
## The three `body_cultivation` BASE attribute ids, in the order `tissue_weights` reads
## them: bone, then muscle, then organ vitality. STRINGS for the reason
## `element_power_prefix` is a string -- naming `BodyStats` from `combat_engine` would be
## a compile-time edge into a module this one does not depend on. An empty list means no
## tissue is read at all, which is a visibly flat defence rather than a silent one.
@export var tissue_stat_ids: PackedStringArray = []
## Which archetype each meridian's tissue is. The keys are meridian ids (the strings) and
## the values are archetype names; a meridian absent from this table reads NO tissue
## defence and reports it, so adding a 21st meridian without a weighting is a visible
## gap rather than a silently undefended channel.
@export var meridian_archetypes: Dictionary = {}
## Each archetype's `[bone, muscle, vitality]` weighting, applied to the three ids above
## in that order. ADR 0070 is explicit that tissue is "a per-meridian WEIGHTING of the
## defender's existing stats" and NOT a third location axis, so a high-bone build resists
## on skeletal meridians and a high-vitality one resists on visceral and vascular ones --
## the same three numbers, spent somewhere different.
@export var tissue_weights: Dictionary = {}
## The pool whose `maximum` a wound's severity is measured against. A STRING NAME in
## DATA rather than `BodyStats.BODY_INTEGRITY` in code, for the edge reason above.
## ADR 0028's one-reservoir rule means this stays the body's SINGLE pool: severity is a
## float on the meridian, never a second reservoir.
@export var integrity_pool_id: StringName = &""
## The directory of the authored huyệt definitions, read as DATA to build the
## point -> meridian map the location axis needs. No point count, no meridian list and no
## "3 per meridian" constant lives in any `.gd`: the shipped data is 3 for the fourteen
## primary/organ meridians, 4 for `chong_mai`/`dai_mai`/`du_mai`/`ren_mai` and 2 for the
## four `qiao`/`wei` extraordinary ones, and the next balance pass is entitled to move
## those numbers without touching this module. Each file is read through `get()` for its
## own `id` and `meridian_id`, so this names no class of the module that owns them.
@export var acupoint_data_dir: String = ""
## Severity at which a meridian is WOUNDED: `damage_meridian` is called, halving the
## channel's aggregate bonus for EVERY path (ADR 0070's other half-inversion).
@export var wound_threshold: float = 0.0
## Severity at which a meridian NECROSES. Deliberately ONE failed breakthrough's worth:
## `BodyAdvancement._deviate` charges `integrity_maximum * 0.25` through the identical
## shape, so a good fighter costs a cultivator a realm through the wound the existing
## failure path already writes. Necrosis is IRREVERSIBLE downward -- decay floors here
## -- so a jammed huyệt is clearable only through the existing ADR 0031 recovery-item
## path and never by waiting.
@export var necrosis_threshold: float = 0.0
## The quality floor necrosis imposes on a meridian's SURVIVING points, so a gash is not
## a promotion. Floored, never raised: necrosis can only take quality away.
@export var necrosis_quality: float = 0.0
## Severity bled off per SECOND of decay. Decay never REPAIRS: an injured channel stays
## injured until `MeridianNetwork.repair_meridian` runs through a recovery item, so the
## one clearable route stays the one ADR 0070 names.
@export var wound_decay: float = 0.0


## A shipped, sane instance. Used by tests and by any caller with no `.tres` in hand,
## and it is the one place these numbers are written in GDScript — so a caller who
## wants to rebalance edits the `.tres`, not this.
##
## ## Why this hands back a FRESH duplicate, and why that is load-bearing
##
## `load()` on a `.tres` returns the RESOURCE CACHE's instance, so every caller in the
## process shared ONE `CombatTuning`. A test that wanted "the shipped tuning with one field
## overridden" had exactly two options — write the field on `shipped()` and retune every
## later reader in the process, or duplicate first. Three suites found the write-through
## path first (see `_broad_mult_copy` in `test_body_damage_aim.gd`, which used to write
## `broad_mult` straight onto `shipped()` and left the shared instance at `-2.0` for
## every suite after it), and the damage was silent and order-dependent: `broad_sites`
## clamps `broad_mult` into `[0, 1]`, so `-2.0` reads `0.0` and every `broad` strike
## produced a zero-multiplier site — a sweep that dealt no wound at all, reported by
## `test_effect_apply.gd` as "the two channels the fixture opened explicitly are among
## them: expected true, got false" and by `test_body_damage_wounds.gd` as an empty
## `settled[]` indexed at `[0]`.
##
## Returning `duplicate(true)` makes the hazard UNREACHABLE rather than merely documented:
## a caller that writes to what it got can only damage its own copy, and a caller that
## forgets to duplicate still gets the shipped numbers. The one cost is that the resource
## is copied per call, which is irrelevant on a path that is already `load()`-bound and is
## the price of making a global balance file unwritable-by-accident.
static func shipped() -> CombatTuning:
	var cached := load("res://src/modules/combat_engine/combat_damage.tres") as CombatTuning
	return cached.duplicate(true) as CombatTuning if cached != null else null
