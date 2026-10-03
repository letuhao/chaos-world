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
## The divisor on a defender's authored `element_resistance_<e>`, turning a stat
## scaled in points into the `[0, 1]` rate `RESIST_CAP` is expressed in. Non-positive
## reads as "no contest", never as a division by zero.
@export var resist_divisor: float = 0.0
## The most of an elemental term resistance may ever remove. A defender at this value is
## a HARD counter even to a `STRONG` 1.5 matchup, which is ADR 0069's anti-"fire is
## always strong" property; mastery is subtracted before the clamp, so it can only ever
## move this down. Clamped to `[0, 1]` on read: above 1.0 the mitigation goes negative
## and S9's one sign flip would spend the elemental term as a heal.
@export var resist_cap: float = 0.0
## The most `Stat.DAMAGE_REDUCTION` may remove at S5. Flat and `0.0`-baselined
## (ADR 0022), so the spine's S8 chip floor -- not this -- is what keeps a landed hit
## non-zero. Clamped to `[0, 1]` on read for the same sign reason as `resist_cap`.
@export var damage_reduction_cap: float = 0.0
## The authored prefixes of the `elements` module's per-element stat ids, read by the
## qi path so it does not have to name that module's classes to name its stats
## (BRIEF 1.7: tuning in DATA; ADR 0069: `ElementRules` is injected, so the combat layer
## reads `elements` rather than the other way round). These are STRINGS on purpose: a
## `StringName` constant naming `elements` would put a compile-time edge into a module
## whose dependency list is `["contracts", "core"]`, and the registry must not lie.
@export var element_power_prefix: String = ""
@export var resist_resistance_prefix: String = ""

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


## A shipped, sane instance. Used by tests and by any caller with no `.tres` in hand,
## and it is the one place these numbers are written in GDScript — so a caller who
## wants to rebalance edits the `.tres`, not this.
static func shipped() -> CombatTuning:
	return load("res://src/modules/combat_engine/combat_damage.tres") as CombatTuning
