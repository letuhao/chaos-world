class_name CombatStats
extends RefCounted

## The defensive vocabulary's stat ids (ADR 0068) and the defaults the spine reads.
##
## ## These ids live HERE, not in `contracts/stat.gd`
##
## `Stat` is core vocabulary — the seven attributes and the derived stats every path
## already shares. Twenty more combat-only ids would put combat vocabulary in core,
## and ADR 0068's own consequence says it plainly: a module may define its own ids.
## `CombatStats` is that module's list. Adding an id here costs no `contracts/` change
## and no schema bump.
##
## ## The ADR 0022 trap, and why `RATE_IDS` exists
##
## `Stat.DAMAGE_REDUCTION` is FLAT with a `0.0` baseline and is deliberately ABSENT
## from `Stat.RATE_STATS`. A `PERCENT` modifier on a `0.0`-baseline stat evaluates to
## `(0.0 + 0.0) * (1 + p) = 0.0` — a silent no-op that shipped on 44 items, validated
## clean because the contract that validated it was itself wrong.
##
## Every rate-shaped id below has a `0.0` baseline and the same trap. `Stat.RATE_STATS`
## is hand-written over STATIC core ids, so these combat-owned ids are invisible to it
## and **must not be added to it** — ADR 0022's cheaper guard is to derive membership
## from the baselines. `RATE_IDS` is that derived membership for combat's own ids, and
## `tests/modules/combat_engine/test_combat_stats_shape.gd` is the SHAPE TEST ADR 0068
## requires: each one must have a zero-or-rate default and must be authored `op: FLAT`,
## `unit: "rate"`. Adding a rate-shaped id without that is the defect class, silent by
## construction.
##
## ## Defaults are DEFAULTS, not balance
##
## The numbers here are the neutral reading of a stat nobody has invested in, so an
## unstatted actor is parried 0% of the time rather than 50% (ADR 0068). They are not
## the shipped balance — the shipped balance for the spine's own arithmetic lives in
## `combat_damage.tres` (`CombatTuning`), and any rate VALUE in real play arrives as a
## `StatModifier`. This file holds the ids and their neutral shape, nothing else.

# --- Offensive vocabulary -----------------------------------------------------

## ADR 0877. This is the OFFENCE HALF of the hit contest: the attacker must BEAT the
## defender's `EVASION`, not merely out-share it —
## `p_hit = clampf((accuracy - evasion) / rate_scale, 0, 1)`, which reads exactly `0.0`
## at parity. The correction history is kept because every shape shipped: ADR 0068 made
## it a subtraction against a divisor, ADR 0215 made it a RATIO (parity `0.5`), and ADR
## 0877 reverses the ratio on the owner's yin-yang rule — a defender who matches the
## attack cancels it to nothing, and a defender who beats it is a wall. Neither half is
## capped; only the OUTPUT is a probability.
##
## The id string is UNCHANGED, because the id was never the defect and renaming it
## would have silently disowned every shipped `core_evasion`-style option that names it.
## `Stat.ACCURACY` in `contracts/stat.gd` is the same string, DERIVED by core since ADR
## 0877, and `tests/modules/combat_engine/test_combat_stats_shape.gd` asserts they are
## one id rather than two vocabularies.
const ACCURACY := &"accuracy"
## How hard the attacker cuts the defender's guard, as a flat MAGNITUDE on
## `CombatTuning.pierce_scale`'s scale, ANSWERED by the defender's `ABSORPTION`
## (ADR 0876). A read-only input to a mechanism's `mitigate`, never a stage of the spine.
##
## ## Why this is `penetration.rate` and NOT `Stat.PENETRATION`
##
## It was `&"penetration"`, which is core's id, and core derives that one in POINTS
## (`spirit * 0.5`, `core/actor_stats.gd:156`). One string, two quantities: an actor with
## spirit 10.0 derived `5.0`, which `_resistance_of` then subtracted from a resistance
## living in `[0, 1]` — so every elemental resistance in the game read `0.0` and mastery
## penetration could never be observed at all. Nothing caught it because
## `test_no_combat_id_is_a_core_stat_id` compared against `Stat.BASE_ATTRIBUTES +
## Stat.RATE_STATS`, and core's DERIVED ids are in neither list; that test now probes a
## live actor instead, which is the only check that sees this class.
const PENETRATION := &"penetration.rate"
## Scales the attacker's amount up. Read at S7 with `REDUCTION`, and only there.
const AMPLIFICATION := &"amplification"
## The flat subtraction applied at S7. Reads `Stat.DAMAGE_REDUCTION` too; see
## `RESIST_REDUCTION` for why both are summed rather than replaced.
const REDUCTION := &"reduction"
## Share of the amount a defender returns as a post-shield bounce (S10). Bounded below
## 1.0 so thorns can at most tie against an equal-health attacker (ADR 0068).
const REFLECT_RATE := &"reflect.rate"
## Scales the bounced amount. The bounce carries no element payload, so it is neither
## re-mitigated nor able to crit (ADR 0068).
const REFLECT_DAMAGE := &"reflect.damage"
## How hard the resister blunts a bounce: the same flat-delta contest as parry (ADR
## 0877), read by `CombatRecoil.bounce` as the trigger's suppress half, and terminal — a
## bounce that loses it does not bounce again.
const REFLECT_RESIST_RATE := &"reflect.resist.rate"
## The suppress half of the bounce MULTIPLIER. The pair is read at the UNIT scale (one
## share-point is the whole range), so `share = clampf(reflect_damage -
## reflect_resist_damage, 0, 1)` — a flat delta, equal halves cancel to `0.0`, and the
## clamp is what keeps a bounce from ever exceeding the amount it returns (ADR 0068).
## `0.0` resists nothing; a resister at or above the reflector's damage refuses outright.
const REFLECT_RESIST_DAMAGE := &"reflect.resist.damage"

# --- Defensive vocabulary -----------------------------------------------------

## The DEFENCE half of penetration: how much of an incoming `penetration.rate`
## the defender's own absorption turns aside before it ever reaches an armour
## value. Read wherever penetration is read — the three damage mechanisms and
## `StatusApply.elemental_resist` — through [method pierce], never beside it.
const ABSORPTION := &"absorption"
## The DEFENDER's half of the parry trigger (S2): `p_parry =
## clampf((PARRY_RATE - PARRY_BREAK) / rate_scale, 0, 1)` — a flat delta, zero at parity
## (ADR 0877). Carved out of the TOP of the would-have-been-a-hit region, and
## `PARRY_BREAK` is the ATTACKER's suppress half: the yin-yang pair AGENTS.md names,
## which ADR 0068 read as ownership but could not USE until it had a formula — ADR
## 0215's ratio, and now the flat delta. The defender RAISES the trigger and the
## attacker SUPPRESSES it; the ownership is the same, the form is not.
const PARRY_RATE := &"parry.rate"
## The DEFENDER's half of the refusal pair (ADR 0878): a landed parry keeps
## `1.0 - PARRY_COST` minus what `strength` raises and `shred` lowers, as a flat delta
## over `rate_scale`. It is not a second contest on the band — `CombatSpine._parry`
## reads the trigger, `CombatSpine._refusal` reads this.
const PARRY_STRENGTH := &"parry.strength"
## The ATTACKER's half of the refusal pair, the suppress side: every point of `shred`
## lowers what a landed parry removes, and at parity the removal is the neutral. Read at
## `CombatSpine._refusal` (ADR 0878), never inside the band roll. `PARRY_BREAK` is the
## OTHER attacker half — whether the parry HAPPENS — and the two are different
## questions: the trigger, and what the trigger costs.
const PARRY_BREAK := &"parry.break"
const PARRY_SHRED := &"parry.shred"
## Block's twin of the four above. Same band, same contest, one vocabulary (ADR 0877):
## `p_block = clampf((BLOCK_RATE - BLOCK_BREAK) / rate_scale, 0, 1)`.
const BLOCK_RATE := &"block.rate"
## Block's twins of the refusal pair above (ADR 0878): `strength` raises what a landed
## block removes, `shred` lowers it, and the neutral is `1.0 - BLOCK_COST`.
const BLOCK_STRENGTH := &"block.strength"
const BLOCK_BREAK := &"block.break"
const BLOCK_SHRED := &"block.shred"

# --- Shield channels ----------------------------------------------------------

## The shield's authored ceiling, read by `CombatShield.refresh` (ADR 0879): the pool
## S9 drains. `0.0` means no shield, which is why it is also the default.
const SHIELD_CAPACITY := &"shield.capacity"
## Multiplier on the damage the pool is good for, folded as `1.0 + SHIELD_TOUGHNESS`
## (`CombatShield.refresh`): at `2.0` a 30-point pool absorbs up to 60 points of one
## blow, never more than the blow. A channel floors at zero, so this can only be RAISED
## by authoring; the attacker's `SHIELD_PEN` is the weakening half.
const SHIELD_TOUGHNESS := &"shield.toughness"
## The ATTACKER's cut, spent off the defender's pool before the blow lands: read by
## `CombatSpine._absorb` and handed to `CombatShield.absorb` as its second argument.
const SHIELD_PEN := &"shield.pen"
## What the pool restores per second, through `CombatShield.tick`. NOT read by the
## spine: regen belongs to a combat tick, not to one hit's resolution, and a regen
## inside a resolve would reorder the stages it runs between.
const SHIELD_REGEN := &"shield.regen"

# --- Leech, one pair per resource ---------------------------------------------

## ADR 0889. A leech is a PAIR per resource, the way every other advantage in this
## module is: the attacker's `lifesteal.<pool>` against the defender's
## `leech_resist.<pool>`, over the same `rate_scale` every trigger reads. The pools are
## the ones the engine actually holds — core's `health` and `stamina` (`actor_pools.gd`)
## and the qi pool the casting layer owns (`technique_casting.gd:71`).
const LIFESTEAL_PREFIX := "lifesteal."
const LEECH_RESIST_PREFIX := "leech_resist."
const POOLS: Array[StringName] = [&"health", &"qi", &"stamina"]


## ## ADR 0877. The CONTEST pairs, and why this is a derivation rather than a comment
##
## Every trigger contest this module owns is a flat delta over `rate_scale`
## ([method rate_from_zero]), so each one names its two halves here and the pair is
## data: a contest named only by its offence half is how `accuracy` came to be defined
## as a SUBTRACTION off `evasion` in the first place.
##
## `PARRY_BREAK` and `BLOCK_BREAK` MOVE from `DEFAULTS` into `RATE_DEFAULTS` in this
## change, which is the mechanical consequence of ADR 0215 rather than a tidiness pass:
## they stopped being "what parrying costs the defender" and became a half of a contest,
## so they need a neutral reading of `0.0` that a caller can add to a derived stat the
## way every other contest half is read.
const CONTESTS: Dictionary = {
	ACCURACY: &"evasion",
	PARRY_RATE: PARRY_BREAK,
	BLOCK_RATE: BLOCK_BREAK,
	# ADR 0889: the leech pairs, literal because a `const` cannot call `leech_ids()`.
	&"lifesteal.health": &"leech_resist.health",
	&"lifesteal.qi": &"leech_resist.qi",
	&"lifesteal.stamina": &"leech_resist.stamina",
}

## Every id this module owns, in the vocabulary order ADR 0068 lists them. Every id a
## content item, a technique or a mechanism may author.
const ALL_IDS: Array[StringName] = [
	ACCURACY,
	ABSORPTION,
	AMPLIFICATION,
	REDUCTION,
	PENETRATION,
	PARRY_RATE,
	PARRY_BREAK,
	PARRY_STRENGTH,
	PARRY_SHRED,
	BLOCK_RATE,
	BLOCK_BREAK,
	BLOCK_STRENGTH,
	BLOCK_SHRED,
	REFLECT_RATE,
	REFLECT_DAMAGE,
	REFLECT_RESIST_RATE,
	REFLECT_RESIST_DAMAGE,
	SHIELD_CAPACITY,
	SHIELD_TOUGHNESS,
	SHIELD_PEN,
	SHIELD_REGEN,
	&"lifesteal.health",
	&"leech_resist.health",
	&"lifesteal.qi",
	&"leech_resist.qi",
	&"lifesteal.stamina",
	&"leech_resist.stamina",
]

## ## ADR 0215: what this list now means, and what stopped being true
##
## Membership used to be "a `[0, 1]` rate with a cap in its expression", which is why
## `ACCURACY` was here: it was defined as a subtraction off a capped evasion, so it
## behaved like a rate. It no longer is — it is an unbounded MAGNITUDE — so it leaves
## this list for the same reason `Stat.CRIT_CHANCE` left `Stat.RATE_STATS` at ADR 0200:
## a FLAT on a magnitude is an authored number, and refusing it would refuse good work.
##
## **`RATE_IDS` and `RATE_STATS` are different claims and the shape test is what keeps
## them apart.** `test_no_combat_rate_id_is_in_core_rate_stats` still holds: combat-owned
## ids are not core's members. Combat's own claim is "this id is a flat magnitude half
## of a contest", and every id in the list below is read through [method rate_from_zero]
## (the trigger pairs), as the magnitude half of an amount pair, or as a share.
const RATE_IDS: Array[StringName] = [
	ABSORPTION,
	PENETRATION,
	PARRY_RATE,
	PARRY_BREAK,
	PARRY_STRENGTH,
	BLOCK_RATE,
	BLOCK_BREAK,
	BLOCK_STRENGTH,
	REFLECT_RATE,
	REFLECT_RESIST_RATE,
	&"lifesteal.health",
	&"leech_resist.health",
	&"lifesteal.qi",
	&"leech_resist.qi",
	&"lifesteal.stamina",
	&"leech_resist.stamina",
]

## The defaults of the rate-shaped ids. Every entry is `0.0`, deliberately: an unstatted
## actor contests nothing, so a contest half reads 0 and the trigger reads `0.0` rather
## than a midpoint or a sigmoid's unchosen 0.5 (ADR 0068, ADR 0877). Nothing here is
## shipped balance — the values arrive as `StatModifier`s; this is only the neutral
## reading.
const RATE_DEFAULTS: Dictionary = {
	ABSORPTION: 0.0,
	PENETRATION: 0.0,
	PARRY_RATE: 0.0,
	PARRY_BREAK: 0.0,
	PARRY_STRENGTH: 0.0,
	BLOCK_RATE: 0.0,
	BLOCK_BREAK: 0.0,
	BLOCK_STRENGTH: 0.0,
	REFLECT_RATE: 0.0,
	REFLECT_RESIST_RATE: 0.0,
	&"lifesteal.health": 0.0,
	&"leech_resist.health": 0.0,
	&"lifesteal.qi": 0.0,
	&"leech_resist.qi": 0.0,
	&"lifesteal.stamina": 0.0,
	&"leech_resist.stamina": 0.0,
}

## The defaults of every non-rate id. These are also neutral readings, not balance: a
## shield with no capacity absorbs nothing, a strength of 1.0 scales nothing.
const DEFAULTS: Dictionary = {
	REDUCTION: 0.0,
	AMPLIFICATION: 0.0,
	REFLECT_DAMAGE: 1.0,
	# `0.0` resists nothing: a `1.0` baseline here made `1.0 - resist`
	# non-positive for EVERY defender, so every bounce multiplied to zero --
	# the same dead-channel `Stat.CRIT_RESIST_DAMAGE` shipped with, and for the
	# same reason (a share subtracted from `1.0` is a `0.0`-baseline stat).
	REFLECT_RESIST_DAMAGE: 0.0,
	PARRY_SHRED: 0.0,
	BLOCK_SHRED: 0.0,
	SHIELD_CAPACITY: 0.0,
	SHIELD_TOUGHNESS: 1.0,
	SHIELD_PEN: 0.0,
	SHIELD_REGEN: 0.0,
}


## The offence half of the leech pair for `pool`.
static func lifesteal_id(pool: StringName) -> StringName:
	return StringName(LIFESTEAL_PREFIX + String(pool))


## The defence half: the answer to the same pool's drain.
static func leech_resist_id(pool: StringName) -> StringName:
	return StringName(LEECH_RESIST_PREFIX + String(pool))


## Both halves of every pool, offence first per pool. DERIVED from [constant POOLS], so a
## fourth pool joins by existing — the shape `ElementStats.crit_ids` uses. `ALL_IDS` and
## `RATE_IDS` cannot call this (a `const` cannot), which is why the shape test pins the
## literal lists against it instead.
static func leech_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for pool in POOLS:
		out.append(lifesteal_id(pool))
		out.append(leech_resist_id(pool))
	return out


## The neutral reading of `id`: its `RATE_DEFAULTS` entry if it is rate-shaped, its
## `DEFAULTS` entry otherwise, and `0.0` for anything this module does not own — so a
## caller can ask an id it has not heard of without branching.
static func default_of(id: StringName) -> float:
	if RATE_DEFAULTS.has(id):
		return float(RATE_DEFAULTS[id])
	return float(DEFAULTS.get(id, 0.0))


## Whether `id` is rate-shaped. Derived from the baselines, the way ADR 0022 says
## membership should be derived rather than restated by hand.
static func is_rate(id: StringName) -> bool:
	return RATE_DEFAULTS.has(id)


## ADR 0877. The ONE place the flat-delta trigger shape is written:
##
## ```
## p = clampf(maxf(0.0, rate - resist) / scale, 0.0, 1.0)
## ```
##
## This is Keepverse's `RateFromZero`, restored over ADR 0215's ratio. The owner's
## yin-yang reading is the whole argument: two equal halves cancel to exactly `0.0`
## (annihilation, not a coin flip), a defender above the rate is a wall, and NEITHER
## input is capped — `1e10` against `1e10` reads `0.0` at any magnitude. The `[0, 1]`
## on the output is probability arithmetic, not a progression ceiling: the advantage
## keeps mattering against a defender who also stacks, which is why the clamp is never
## the reason to stop investing.
##
## ## Why a non-positive `delta` or `scale` reads `0.0` and never divides
##
## `delta <= 0.0` is the cancellation itself. A non-positive or non-finite `scale`
## cannot say how much advantage is needed, and the honest answer for a rate with no
## exchange rate is `0.0` rather than an `INF` that clamps to a certainty nobody chose
## — the same call `QiDamage._resistance_of` makes for a zero divisor.
static func rate_from_zero(rate_value: float, resist: float, scale: float) -> float:
	var r := maxf(0.0, rate_value if is_finite(rate_value) else 0.0)
	var d := maxf(0.0, resist if is_finite(resist) else 0.0)
	var delta := maxf(0.0, r - d)
	if delta <= 0.0:
		return 0.0
	var s := scale if is_finite(scale) else 0.0
	if s <= 0.0:
		return 0.0
	return minf(1.0, delta / s)


## The id `offense_id` is contested against, or `&""` when it is not half of a contest.
## Total on purpose: a caller asking about an id this module has never heard of gets an
## answer rather than an error, which is what lets [method contest_of] degrade to `0.0`.
static func counterpart_of(offense_id: StringName) -> StringName:
	return CONTESTS.get(offense_id, &"")


## [method rate_from_zero] for two ACTORS rather than two numbers, so the contest halves
## are read the same way everywhere: `CombatStats.default_of` folded in, then `derived`,
## then the flat delta over `scale` (ADR 0877). The scale is the caller's
## (`CombatTuning.rate_scale` in production) so a tuning edit moves every trigger
## together and this file stays a pure vocabulary.
##
## `null` on either side is `0.0`, so a half-built pair reads the neutral contest rather
## than crashing a hit that has already committed to mutating both of them.
static func contest_of(
	offense_id: StringName, offense: Actor, defense_id: StringName, defense: Actor, scale: float
) -> float:
	if defense_id == &"":
		return 0.0
	return rate_from_zero(
		default_of(offense_id) + derived_of(offense, offense_id),
		default_of(defense_id) + derived_of(defense, defense_id),
		scale
	)


## The derived value of `id` on `actor`, or `0.0` for a null actor. The same total read
## [method CombatBand.derived_of] performs, and duplicated rather than reached through it
## so this file stays a pure vocabulary with no dependency on the band roll.
static func derived_of(actor: Actor, id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return actor.stats.derived(id)


## Penetration ANSWERED: `penetration` less `absorption` — a flat difference of
## two flat magnitudes, floored at zero, never a percentage (Keepverse
## `penDelta`). The floor is load-bearing, not tidy: a negative penetration
## would be a defence bonus wearing an attacker's name, and absorption's whole
## job is to neutralise penetration, not to harden armour. Both totals arrive
## with their neutral defaults already folded in, so an unauthored defender
## answers `0.0` and every existing number is byte-identical until content
## authors the half. The single place this formula lives: the three damage
## mechanisms and `StatusApply.elemental_resist` all read through here rather
## than restating the subtraction.
static func pierce(penetration: float, absorption: float) -> float:
	return maxf(0.0, penetration - absorption)


## A `StatModifier` of the only shape ADR 0068 permits for a rate id. The single place
## a rate modifier is constructed, so a new caller cannot reach for `Op.PERCENT` on an
## id that cannot take one — and so the shape test has something to assert about the
## items this module grants.
static func rate_modifier(id: StringName, value: float, source: StringName) -> StatModifier:
	return StatModifier.new(id, Stat.Op.FLAT, value, source)
